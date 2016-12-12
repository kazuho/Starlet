package Starlet::Server;
use strict;
use warnings;

use Carp ();
use Plack;
use Plack::HTTPParser qw( parse_http_request );
use IO::Socket::INET;
use HTTP::Date;
use HTTP::Status;
use List::Util qw(max sum);
use Plack::Util;
use Plack::TempBuffer;
use POSIX qw(EINTR EAGAIN EWOULDBLOCK);
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use File::Temp qw(tempfile);
use Fcntl qw(:flock);

use Try::Tiny;
use Time::HiRes qw(time);

use constant MAX_REQUEST_SIZE => 131072;
use constant CHUNKSIZE        => 64 * 1024;
use constant MSWin32          => $^O eq 'MSWin32';

my $null_io = do { open my $io, "<", \""; $io };

sub new {
    my($class, %args) = @_;

    my $self = bless {
        listens              => $args{listens} || [],
        host                 => $args{host} || 0,
        port                 => $args{port} || $args{socket} || 8080,
        timeout              => $args{timeout} || 300,
        keepalive_timeout    => $args{keepalive_timeout} || 2,
        max_keepalive_reqs   => $args{max_keepalive_reqs} || 1,
        server_software      => $args{server_software} || $class,
        server_ready         => $args{server_ready} || sub {},
        min_reqs_per_child   => (
            defined $args{min_reqs_per_child}
                ? $args{min_reqs_per_child} : undef,
        ),
        max_reqs_per_child   => (
            $args{max_reqs_per_child} || $args{max_requests} || 100,
        ),
        spawn_interval       => $args{spawn_interval} || 0,
        err_respawn_interval => (
            defined $args{err_respawn_interval}
                ? $args{err_respawn_interval} : undef,
        ),
        is_multiprocess      => Plack::Util::FALSE,
        child_exit           => $args{child_exit} || sub {},
        _using_defer_accept  => undef,
    }, $class;

    if ($args{max_workers} && $args{max_workers} > 1) {
        Carp::carp(
            "Preforking in $class is deprecated. Falling back to the non-forking mode. ",
            "If you need preforking, use Starman or Starlet instead and run like `plackup -s Starlet`",
        );
    }

    $self;
}

sub run {
    my($self, $app) = @_;
    $self->setup_listener();
    $self->accept_loop($app);
}

sub setup_listener {
    my $self = shift;
    if (scalar(grep {defined $_} @{$self->{listens}}) == 0) {
        my $sock;
        if ($self->{port} =~ /^[0-9]+$/s) {
            $sock = IO::Socket::INET->new(
                Listen    => SOMAXCONN,
                LocalPort => $self->{port},
                LocalAddr => $self->{host},
                Proto     => 'tcp',
                ReuseAddr => 1,
            ) or die "failed to listen to port $self->{port}:$!";
        } else {
            $sock = IO::Socket::UNIX->new(
                Listen => SOMAXCONN,
                Local  => $self->{port},
            ) or die "failed to listen to socket $self->{port}:$!";
        }
        $self->{listens}[fileno($sock)] = {
            host => $self->{host},
            port => $self->{port},
            sock => $sock,
        };
    }

    my @listens = grep {defined $_} @{$self->{listens}};
    for my $listen (@listens) {
        my $family = Socket::sockaddr_family(getsockname($listen->{sock}));
        $listen->{_is_tcp} = $family != AF_UNIX;

        # set defer accept
        if ($^O eq 'linux' && $listen->{_is_tcp}) {
            setsockopt($listen->{sock}, IPPROTO_TCP, 9, 1)
                and $listen->{_using_defer_accept} = 1;
        }
    }

    if (scalar(@listens) > 1) {
        $self->{lock_path} ||= do {
            my ($fh, $lock_path) = tempfile(UNLINK => 1);
            # closing the file handle explicitly for two reasons
            # 1) tempfile retains the handle when UNLINK is set
            # 2) tempfile implicitely locks the file on OS X
            close $fh;
            $lock_path;
        };
    }

    $self->{server_ready}->($self);
}

sub accept_loop {
    # TODO handle $max_reqs_per_child
    my($self, $app, $max_reqs_per_child) = @_;
    my $proc_req_count = 0;
    my $is_keepalive = 0;

    local $SIG{TERM} = sub {
        $self->{term_received} = 1;
    };
    local $SIG{PIPE} = 'IGNORE';

    my $acceptor = $self->_get_acceptor;

    while (! defined $max_reqs_per_child || $proc_req_count < $max_reqs_per_child) {
        # accept (or exit on SIGTERM)
        if ($self->{term_received}) {
            $self->{child_exit}->($self, $app);
            exit 0;
        }
        my ($conn, $peer, $listen) = $acceptor->();
        next unless $conn;

        $self->{_is_deferred_accept} = $listen->{_using_defer_accept};
        defined($conn->blocking(0))
            or die "failed to set socket to nonblocking mode:$!";
        my ($peerport, $peerhost, $peeraddr) = (0, undef, undef);
        if ($listen->{_is_tcp}) {
            $conn->setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
                or die "setsockopt(TCP_NODELAY) failed:$!";
            ($peerport, $peerhost) = unpack_sockaddr_in $peer;
            $peeraddr = inet_ntoa($peerhost);
        }
        my $req_count = 0;
        my $pipelined_buf = '';

        while (1) {
            ++$req_count;
            ++$proc_req_count;
            my $env = {
                SERVER_PORT => $listen->{port} || 0,
                SERVER_NAME => $listen->{host} || 0,
                SCRIPT_NAME => '',
                REMOTE_ADDR => $peeraddr,
                REMOTE_PORT => $peerport,
                'psgi.version' => [ 1, 1 ],
                'psgi.errors'  => *STDERR,
                'psgi.url_scheme' => 'http',
                'psgi.run_once'     => Plack::Util::FALSE,
                'psgi.multithread'  => Plack::Util::FALSE,
                'psgi.multiprocess' => $self->{is_multiprocess},
                'psgi.streaming'    => Plack::Util::TRUE,
                'psgi.nonblocking'  => Plack::Util::FALSE,
                'psgix.input.buffered' => Plack::Util::TRUE,
                'psgix.io'          => $conn,
                'psgix.harakiri'    => 1,
                'psgix.informational' => sub {
                    $self->_informational($conn, @_);
                },
            };

            my $may_keepalive = $req_count < $self->{max_keepalive_reqs};
            if ($may_keepalive && $max_reqs_per_child && $proc_req_count >= $max_reqs_per_child) {
                $may_keepalive = undef;
            }
            $may_keepalive = 1 if length $pipelined_buf;
            my $keepalive;
            ($keepalive, $pipelined_buf) = $self->handle_connection($env, $conn, $app, 
                                                                    $may_keepalive, $req_count != 1, $pipelined_buf);

            if ($env->{'psgix.harakiri.commit'}) {
                $conn->close;
                return;
            }
            last unless $keepalive;
            # TODO add special cases for clients with broken keep-alive support, as well as disabling keep-alive for HTTP/1.0 proxies
        }
        $conn->close;
    }
}

sub _get_acceptor {
    my $self = shift;
    my @listens = grep {defined $_} @{$self->{listens}};

    if (scalar(@listens) == 1) {
        my $listen = $listens[0];
        return sub {
            if (my ($conn, $peer) = $listen->{sock}->accept) {
                return ($conn, $peer, $listen);
            }
            return +();
        };
    }
    else {
        # wait for multiple sockets with select(2)
        my @fds;
        my $rin = '';
        for my $listen (@listens) {
            defined($listen->{sock}->blocking(0))
	        or die "failed to set listening socket to non-blocking mode:$!";
            my $fd = fileno($listen->{sock});
            push @fds, $fd;
            vec($rin, $fd, 1) = 1;
        }

        open(my $lock_fh, '>', $self->{lock_path})
            or die "failed to open lock file:@{[$self->{lock_path}]}:$!";

        return sub {
            if (! flock($lock_fh, LOCK_EX)) {
                die "failed to lock file:@{[$self->{lock_path}]}:$!"
                    if $! != EINTR;
                return +();
            }
            my $nfound = select(my $rout = $rin, undef, undef, undef);
            for (my $i = 0; $nfound > 0; ++$i) {
                my $fd = $fds[$i];
                next unless vec($rout, $fd, 1);
                --$nfound;
                my $listen = $self->{listens}[$fd];
                if (my ($conn, $peer) = $listen->{sock}->accept) {
                    flock($lock_fh, LOCK_UN);
                    return ($conn, $peer, $listen);
                }
            }
            flock($lock_fh, LOCK_UN);
            return +();
        };
    }
}

my $bad_response = [ 400, [ 'Content-Type' => 'text/plain', 'Connection' => 'close' ], [ 'Bad Request' ] ];
sub handle_connection {
    my($self, $env, $conn, $app, $use_keepalive, $is_keepalive, $prebuf) = @_;
    
    my $buf = '';
    my $pipelined_buf='';
    my $res = $bad_response;
    
    while (1) {
        my $rlen;
        if ( $rlen = length $prebuf ) {
            $buf = $prebuf;
            undef $prebuf;
        }
        else {
            $rlen = $self->read_timeout(
                $conn, \$buf, MAX_REQUEST_SIZE - length($buf), length($buf),
                $is_keepalive ? $self->{keepalive_timeout} : $self->{timeout},
            ) or return;
        }
        my $reqlen = parse_http_request($buf, $env);
        if ($reqlen >= 0) {
            # handle request
            my $protocol = $env->{SERVER_PROTOCOL};
            if ($use_keepalive) {
                if ($self->{term_received}) {
                    $use_keepalive = undef;
                } elsif ( $protocol eq 'HTTP/1.1' ) {
                    if (my $c = $env->{HTTP_CONNECTION}) {
                        $use_keepalive = undef 
                            if $c =~ /^\s*close\s*/i;
                    }
                } else {
                    if (my $c = $env->{HTTP_CONNECTION}) {
                        $use_keepalive = undef
                            unless $c =~ /^\s*keep-alive\s*/i;
                    } else {
                        $use_keepalive = undef;
                    }
                }
            }
            $buf = substr $buf, $reqlen;
            my $chunked = do { no warnings; lc delete $env->{HTTP_TRANSFER_ENCODING} eq 'chunked' };

            if ( $env->{HTTP_EXPECT} ) {
                if ( lc $env->{HTTP_EXPECT} eq '100-continue' ) {
                    $self->write_all($conn, "HTTP/1.1 100 Continue\015\012\015\012")
                        or return;
                } else {
                    $res = [417,[ 'Content-Type' => 'text/plain', 'Connection' => 'close' ], [ 'Expectation Failed' ] ];
                    last;
                }
            }

            if (my $cl = $env->{CONTENT_LENGTH}) {
                my $buffer = Plack::TempBuffer->new($cl);
                while ($cl > 0) {
                    my $chunk;
                    if (length $buf) {
                        $chunk = $buf;
                        $buf = '';
                    } else {
                        $self->read_timeout(
                            $conn, \$chunk, $cl, 0, $self->{timeout})
                            or return;
                    }
                    $buffer->print($chunk);
                    $cl -= length $chunk;
                }
                $env->{'psgi.input'} = $buffer->rewind;
            }
            elsif ($chunked) {
                my $buffer = Plack::TempBuffer->new;
                my $chunk_buffer = '';
                my $length;
                DECHUNK: while(1) {
                    my $chunk;
                    if ( length $buf ) {
                        $chunk = $buf;
                        $buf = '';
                    }
                    else {
                        $self->read_timeout($conn, \$chunk, CHUNKSIZE, 0, $self->{timeout})
                            or return;
                    }

                    $chunk_buffer .= $chunk;
                    while ( $chunk_buffer =~ s/^(([0-9a-fA-F]+).*\015\012)// ) {
                        my $trailer   = $1;
                        my $chunk_len = hex $2;
                        if ($chunk_len == 0) {
                            last DECHUNK;
                        } elsif (length $chunk_buffer < $chunk_len + 2) {
                            $chunk_buffer = $trailer . $chunk_buffer;
                            last;
                        }
                        $buffer->print(substr $chunk_buffer, 0, $chunk_len, '');
                        $chunk_buffer =~ s/^\015\012//;
                        $length += $chunk_len;                        
                    }
                }
                $env->{CONTENT_LENGTH} = $length;
                $env->{'psgi.input'} = $buffer->rewind;
            } else {
                if ( $buf =~ m!^(?:GET|HEAD)! ) { #pipeline
                    $pipelined_buf = $buf;
                    $use_keepalive = 1; #force keepalive
                } # else clear buffer
                $env->{'psgi.input'} = $null_io;
            }

            $res = Plack::Util::run_app $app, $env;
            last;
        }
        if ($reqlen == -2) {
            # request is incomplete, do nothing
        } elsif ($reqlen == -1) {
            # error, close conn
            last;
        }
    }

    if (ref $res eq 'ARRAY') {
        $self->_handle_response($env->{SERVER_PROTOCOL}, $res, $conn, \$use_keepalive);
    } elsif (ref $res eq 'CODE') {
        $res->(sub {
            $self->_handle_response($env->{SERVER_PROTOCOL}, $_[0], $conn, \$use_keepalive);
        });
    } else {
        die "Bad response $res";
    }
    
    return ($use_keepalive, $pipelined_buf);
}

sub _informational {
    my ($self, $conn, $status_code, $headers) = @_;

    my @lines = "HTTP/1.1 $status_code @{[ HTTP::Status::status_message($status_code) ]}\015\012";
    for (my $i = 0; $i < @$headers; $i += 2) {
        my $k = $headers->[$i];
        my $v = $headers->[$i + 1];
        push @lines, "$k: $v\015\012";
    }
    push @lines, "\015\012";

    $self->write_all($conn, join("", @lines), $self->{timeout});
}

sub _handle_response {
    my($self, $protocol, $res, $conn, $use_keepalive_r) = @_;
    my $status_code = $res->[0];
    my $headers = $res->[1];
    my $body = $res->[2];
    
    my @lines;
    my %send_headers;
    for (my $i = 0; $i < @$headers; $i += 2) {
        my $k = $headers->[$i];
        my $v = $headers->[$i + 1];
        my $lck = lc $k;
        if ($lck eq 'connection') {
            $$use_keepalive_r = undef
                if $$use_keepalive_r && lc $v ne 'keep-alive';
        } else {
            push @lines, "$k: $v\015\012";
            $send_headers{$lck} = $v;
        }
    }
    if ( ! exists $send_headers{server} ) {
        unshift @lines, "Server: $self->{server_software}\015\012";
    }
    if ( ! exists $send_headers{date} ) {
        unshift @lines, "Date: @{[HTTP::Date::time2str()]}\015\012";
    }

    # try to set content-length when keepalive can be used, or disable it
    my $use_chunked;
    if (defined($protocol) && $protocol eq 'HTTP/1.1') {
        if (defined $send_headers{'content-length'}
                || defined $send_headers{'transfer-encoding'}) {
            # ok
        } elsif (!Plack::Util::status_with_no_entity_body($status_code)) {
            push @lines, "Transfer-Encoding: chunked\015\012";
            $use_chunked = 1;
        }
        push @lines, "Connection: close\015\012" unless $$use_keepalive_r;
    } else {
        # HTTP/1.0
        if ($$use_keepalive_r) {
            if (defined $send_headers{'content-length'}
                || defined $send_headers{'transfer-encoding'}) {
                # ok
            } elsif (!Plack::Util::status_with_no_entity_body($status_code)
                     && defined(my $cl = Plack::Util::content_length($body))) {
                push @lines, "Content-Length: $cl\015\012";
            } else {
                $$use_keepalive_r = undef;
            }
        }
        push @lines, "Connection: keep-alive\015\012" if $$use_keepalive_r;
        push @lines, "Connection: close\015\012" if !$$use_keepalive_r; #fmm..
    }

    unshift @lines, "HTTP/1.1 $status_code @{[ HTTP::Status::status_message($status_code) ]}\015\012";
    push @lines, "\015\012";
    
    if (defined $body && ref $body eq 'ARRAY' && @$body == 1
            && length $body->[0] < 8192) {
        # combine response header and small request body
        my $buf = $body->[0];
        if ($use_chunked ) {
            my $len = length $buf;
            $buf = sprintf("%x",$len) . "\015\012" . $buf . "\015\012" . '0' . "\015\012\015\012";
        }
        $self->write_all(
            $conn, join('', @lines, $buf), $self->{timeout},
        );
        return;
    }
    $self->write_all($conn, join('', @lines), $self->{timeout})
        or return;

    if (defined $body) {
        my $failed;
        my $completed;
        my $body_count = (ref $body eq 'ARRAY') ? $#{$body} + 1 : -1;
        Plack::Util::foreach(
            $body,
            sub {
                unless ($failed) {
                    my $buf = $_[0];
                    --$body_count;
                    if ( $use_chunked ) {
                        my $len = length $buf;
                        return unless $len;
                        $buf = sprintf("%x",$len) . "\015\012" . $buf . "\015\012";
                        if ( $body_count == 0 ) {
                            $buf .= '0' . "\015\012\015\012";
                            $completed = 1;
                        }
                    }
                    $self->write_all($conn, $buf, $self->{timeout})
                        or $failed = 1;
                }
            },
        );
        $self->write_all($conn, '0' . "\015\012\015\012", $self->{timeout}) if $use_chunked && !$completed;
    } else {
        return Plack::Util::inline_object
            write => sub {
                my $buf = $_[0];
                if ( $use_chunked ) {
                    my $len = length $buf;
                    return unless $len;
                    $buf = sprintf("%x",$len) . "\015\012" . $buf . "\015\012"
                }
                $self->write_all($conn, $buf, $self->{timeout})
            },
            close => sub {
                $self->write_all($conn, '0' . "\015\012\015\012", $self->{timeout}) if $use_chunked;
            };
    }
}

# returns value returned by $cb, or undef on timeout or network error
sub do_io {
    my ($self, $is_write, $sock, $buf, $len, $off, $timeout) = @_;
    my $ret;
    unless ($is_write || delete $self->{_is_deferred_accept}) {
        goto DO_SELECT;
    }
 DO_READWRITE:
    # try to do the IO
    if ($is_write) {
        $ret = syswrite $sock, $buf, $len, $off
            and return $ret;
    } else {
        $ret = sysread $sock, $$buf, $len, $off
            and return $ret;
    }
    unless ((! defined($ret)
                 && ($! == EINTR || $! == EAGAIN || $! == EWOULDBLOCK))) {
        return;
    }
    # wait for data
 DO_SELECT:
    while (1) {
        my ($rfd, $wfd);
        my $efd = '';
        vec($efd, fileno($sock), 1) = 1;
        if ($is_write) {
            ($rfd, $wfd) = ('', $efd);
        } else {
            ($rfd, $wfd) = ($efd, '');
        }
        my $start_at = time;
        my $nfound = select($rfd, $wfd, $efd, $timeout);
        $timeout -= (time - $start_at);
        last if $nfound;
        return if $timeout <= 0;
    }
    goto DO_READWRITE;
}

# returns (positive) number of bytes read, or undef if the socket is to be closed
sub read_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout) = @_;
    $self->do_io(undef, $sock, $buf, $len, $off, $timeout);
}

# returns (positive) number of bytes written, or undef if the socket is to be closed
sub write_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout) = @_;
    $self->do_io(1, $sock, $buf, $len, $off, $timeout);
}

# writes all data in buf and returns number of bytes written or undef if failed
sub write_all {
    my ($self, $sock, $buf, $timeout) = @_;
    my $off = 0;
    while (my $len = length($buf) - $off) {
        my $ret = $self->write_timeout($sock, $buf, $len, $off, $timeout)
            or return;
        $off += $ret;
    }
    return length $buf;
}

1;
