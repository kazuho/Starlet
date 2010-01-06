use strict;
use warnings;

use File::Basename ();
use LWP::Simple ();
use Test::TCP ();

use Test::More;

BEGIN {
    use_ok('Server::Starter');
};

my ($start_server) = grep { -x $_ } map { "$_/start_server" } (
    File::Basename::dirname($^X),
    split /:/, $ENV{PATH},
);

if ($start_server) {
    my $port = Test::TCP::empty_port();
    my $server_pid = fork();
    die "fork failed:$!"
        unless defined $server_pid;
    if ($server_pid == 0) {
        # child == server
        exec(
            $start_server,
            "--port=$port",
            qw(-- plackup -s Standalone::Prefork::Server::Starter t/00base-hello.psgi),
        );
        die "failed to launch server using start_server:$!";
    }
    sleep 1;
    
    is(LWP::Simple::get("http://127.0.0.1:$port/"), 'hello');
    
    kill 'TERM', $server_pid;
    while (wait == -1) {}
} else {
    warn "could not find `start_server' next to $^X nor from \$PATH, skipping tests";
}

done_testing;
