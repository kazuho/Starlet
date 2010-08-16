package Plack::Handler::Starlet;

use strict;
use warnings;

use Parallel::Prefork;
use Server::Starter ();
use base qw(Starlet::Server);

sub new {
    my ($klass, %args) = @_;
    
    # setup before instantiation
    my $listen_sock;
    if (defined $ENV{SERVER_STARTER_PORT}) {
        my ($hostport, $fd) = %{Server::Starter::server_ports()};
        if ($hostport =~ /(.*):(\d+)/) {
            $args{host} = $1;
            $args{port} = $2;
        } else {
            $args{port} = $hostport;
        }
        $listen_sock = IO::Socket::INET->new(
            Proto => 'tcp',
        ) or die "failed to create socket:$!";
        $listen_sock->fdopen($fd, 'w')
            or die "failed to bind to listening socket:$!";
    }
    my $max_workers = 10;
    for (qw(max_workers workers)) {
        $max_workers = delete $args{$_}
            if defined $args{$_};
    }
    
    # instantiate and set the variables
    my $self = $klass->SUPER::new(%args);
    $self->{is_multiprocess} = 1;
    $self->{listen_sock} = $listen_sock
        if $listen_sock;
    $self->{max_workers} = $max_workers;
    
    $self;
}

sub run {
    my($self, $app) = @_;
    $self->setup_listener();
    if ($self->{max_workers} != 0) {
        # use Parallel::Prefork
        my $pm = Parallel::Prefork->new({
            max_workers => $self->{max_workers},
            trap_signals => {
                TERM => 'TERM',
                HUP  => 'TERM',
            },
        });
        while ($pm->signal_received ne 'TERM') {
            $pm->start and next;
            $self->accept_loop($app, $self->{max_reqs_per_child});
            $pm->finish;
        }
        $pm->wait_all_children;
    } else {
        # run directly, mainly for debugging
        local $SIG{TERM} = sub { exit 0; };
        while (1) {
            $self->accept_loop($app, $self->{max_reqs_per_child});
        }
    }
}

1;
