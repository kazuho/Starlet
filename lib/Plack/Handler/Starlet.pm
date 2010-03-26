package Plack::Handler::Starlet;

use strict;
use warnings;

use Server::Starter ();
use base qw(HTTP::Server::PSGI);

sub new {
    my ($klass, %args) = @_;
    
    my ($hostport, $fd) = %{Server::Starter::server_ports()};
    if ($hostport =~ /(.*):(\d+)/) {
        $args{host} = $1;
        $args{port} = $2;
    } else {
        $args{port} = $hostport;
    }
    
    $args{max_workers} ||= 10;
    
    my $self = $klass->SUPER::new(%args);
    
    $self->{listen_sock} = IO::Socket::INET->new(
        Proto => 'tcp',
    ) or die "failed to create socket:$!";
    $self->{listen_sock}->fdopen($fd, 'w')
        or die "failed to bind to listening socket:$!";
    
    $self;
}

1;
