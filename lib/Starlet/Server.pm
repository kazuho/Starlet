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

use Try::Tiny;
use Time::HiRes qw(time);

use constant MAX_REQUEST_SIZE => 131072;
use constant MSWin32          => $^O eq 'MSWin32';

my $null_io = do { open my $io, "<", \""; $io };

sub new {
    my($class, %args) = @_;

    my $self = bless {
        host                 => $args{host} || 0,
        port                 => $args{port} || 8080,
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
    $self->{listen_sock} ||= IO::Socket::INET->new(
        Listen    => SOMAXCONN,
        LocalPort => $self->{port},
        LocalAddr => $self->{host},
        Proto     => 'tcp',
        ReuseAddr => 1,
    ) or die "failed to listen to port $self->{port}:$!";

    # set defer accept
    if ($^O eq 'linux') {
        setsockopt($self->{listen_sock}, IPPROTO_TCP, 9, 1)
            and $self->{_using_defer_accept} = 1;
    }

    $self->{server_ready}->($self);
}

sub accept_loop {
    # TODO handle $max_reqs_per_child
    my($self, $app, $max_reqs_per_child) = @_;
    my $proc_req_count = 0;

    while (! defined $max_reqs_per_child || $proc_req_count < $max_reqs_per_child) {
        local $SIG{PIPE} = 'IGNORE';
        if (my $conn = $self->{listen_sock}->accept) {
            $self->{_is_deferred_accept} = $self->{_using_defer_accept};
            $conn->blocking(0)
                or die "failed to set socket to nonblocking mode:$!";
            $conn->setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
                or die "setsockopt(TCP_NODELAY) failed:$!";
            my $req_count = 0;
            while (1) {
                ++$req_count;
                ++$proc_req_count;
                my $env = {
                    SERVER_PORT => $self->{port},
                    SERVER_NAME => $self->{host},
                    SCRIPT_NAME => '',
                    REMOTE_ADDR => $conn->peerhost,
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
                };

                # no need to take care of pipelining since this module is a HTTP/1.0 server
                my $may_keepalive = $req_count < $self->{max_keepalive_reqs};
                if ($may_keepalive && $max_reqs_per_child && $proc_req_count >= $max_reqs_per_child) {
                    $may_keepalive = undef;
                }

                my $use_keepalive = $self->handle_connection($env, $conn, $app, $may_keepalive, $req_count != 1);

                if ($env->{'psgix.harakiri.commit'}) {
                    $conn->close;
                    return;
                }

                $use_keepalive or last;
                # TODO add special cases for clients with broken keep-alive support, as well as disabling keep-alive for HTTP/1.0 proxies
            }
            $conn->close;
        }
    }
}

sub handle_connection {
    my($self, $env, $conn, $app, $use_keepalive, $is_keepalive) = @_;
    
    my $buf = '';
    my $res = [ 400, [ 'Content-Type' => 'text/plain' ], [ 'Bad Request' ] ];
    
    my $can_exit = 1;
    my $term_received = 0;
    local $SIG{TERM} = sub {
        $term_received++;
        exit 0
            if ($is_keepalive && $can_exit) || $term_received > 1;
        # warn "server termination delayed while handling current HTTP request";
    };
    
    while (1) {
        my $rlen = $self->read_timeout(
            $conn, \$buf, MAX_REQUEST_SIZE - length($buf), length($buf),
            $is_keepalive ? $self->{keepalive_timeout} : $self->{timeout},
        ) or return;
        undef $can_exit;
        my $reqlen = parse_http_request($buf, $env);
        if ($reqlen >= 0) {
            # handle request
            if ($use_keepalive) {
                if (my $c = $env->{HTTP_CONNECTION}) {
                    $use_keepalive = undef
                        unless $c =~ /^\s*keep-alive\s*/i;
                } else {
                    $use_keepalive = undef;
                }
            }
            $buf = substr $buf, $reqlen;
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
            } else {
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
        $self->_handle_response($res, $conn, \$use_keepalive);
    } elsif (ref $res eq 'CODE') {
        $res->(sub {
            $self->_handle_response($_[0], $conn, \$use_keepalive);
        });
    } else {
        die "Bad response $res";
    }

    if ($term_received) {
        exit 0;
    }
    
    return $use_keepalive;
}

sub _handle_response {
    my($self, $res, $conn, $use_keepalive_r) = @_;
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
    if ($$use_keepalive_r) {
        if (defined $send_headers{'content-length'}
                || defined $send_headers{'transfer-encoding'}) {
            # ok
        } elsif (! Plack::Util::status_with_no_entity_body($status_code)
                    && defined(my $cl = Plack::Util::content_length($body))) {
            push @lines, "Content-Length: $cl\015\012";
        } else {
            $$use_keepalive_r = undef
        }
        push @lines, "Connection: keep-alive\015\012"
            if $$use_keepalive_r;
    }
    unshift @lines, "HTTP/1.0 $status_code @{[ HTTP::Status::status_message($status_code) ]}\015\012";
    push @lines, "\015\012";
    
    if (defined $body && ref $body eq 'ARRAY' && @$body == 1
            && length $body->[0] < 1024) {
        # combine response header and small request body
        $self->write_all(
            $conn, join('', @lines, $body->[0]), $self->{timeout},
        );
        return;
    }
    $self->write_all($conn, join('', @lines), $self->{timeout})
        or return;

    if (defined $body) {
        my $failed;
        Plack::Util::foreach(
            $body,
            sub {
                unless ($failed) {
                    $self->write_all($conn, $_[0], $self->{timeout})
                        or $failed = 1;
                }
            },
        );
    } else {
        return Plack::Util::inline_object
            write => sub { $self->write_all($conn, $_[0], $self->{timeout}) },
            close => sub { };
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
