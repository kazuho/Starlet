package Plack::Handler::Starlet;

use strict;
use warnings;

use Parallel::Prefork;
use Server::Starter ();
use base qw(Starlet::Server);

sub new {
    my ($klass, %args) = @_;
    
    # setup before instantiation
    if (defined $ENV{SERVER_STARTER_PORT}) {
        $args{listens} = [];
        my $server_ports = Server::Starter::server_ports();
        for my $hostport (keys %$server_ports) {
            my $fd = $server_ports->{$hostport};
            my $listen = {};
            if ($hostport =~ /(.*):(\d+)/) {
                $listen->{host} = $1;
                $listen->{port} = $2;
            } else {
                $listen->{port} = $hostport;
            }
            $listen->{sock} = IO::Socket::INET->new(
                Proto => 'tcp',
            ) or die "failed to create socket:$!";
            $listen->{sock}->fdopen($fd, 'w')
                or die "failed to bind to listening socket:$!";
            unless (@{$args{listens}}) {
                $args{host} = $listen->{host};
                $args{port} = $listen->{port};
            }
            $args{listens}[$fd] = $listen;
        }
    }
    my $max_workers = 10;
    for (qw(max_workers workers)) {
        $max_workers = delete $args{$_}
            if defined $args{$_};
    }
    
    # instantiate and set the variables
    my $self = $klass->SUPER::new(%args);
    $self->{is_multiprocess} = 1;
    $self->{max_workers} = $max_workers;
    
    $self;
}

sub run {
    my($self, $app) = @_;
    $self->setup_listener();
    if ($self->{max_workers} != 0) {
        # use Parallel::Prefork
        my %pm_args = (
            max_workers => $self->{max_workers},
            trap_signals => {
                TERM => 'TERM',
                HUP  => 'TERM',
            },
        );
        if (defined $self->{spawn_interval}) {
            $pm_args{trap_signals}{USR1} = [ 'TERM', $self->{spawn_interval} ];
            $pm_args{spawn_interval} = $self->{spawn_interval};
        }
        if (defined $self->{err_respawn_interval}) {
            $pm_args{err_respawn_interval} = $self->{err_respawn_interval};
        }
        my $pm = Parallel::Prefork->new(\%pm_args);
        while ($pm->signal_received !~ /^(TERM|USR1)$/) {
            $pm->start and next;
            $self->accept_loop($app, $self->_calc_reqs_per_child());
            $pm->finish;
        }
        $pm->wait_all_children;
    } else {
        # run directly, mainly for debugging
        local $SIG{TERM} = sub { exit 0; };
        while (1) {
            $self->accept_loop($app, $self->_calc_reqs_per_child());
        }
    }
}

sub _calc_reqs_per_child {
    my $self = shift;
    my $max = $self->{max_reqs_per_child};
    if (my $min = $self->{min_reqs_per_child}) {
        srand((rand() * 2 ** 30) ^ $$ ^ time);
        return $max - int(($max - $min + 1) * rand);
    } else {
        return $max;
    }
}

1;
