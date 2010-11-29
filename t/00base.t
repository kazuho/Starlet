use strict;
use warnings;

use File::Basename ();
use List::Util qw(first);
use LWP::UserAgent ();
use Test::TCP ();

use Test::More;

BEGIN {
    use_ok('Server::Starter');
};

sub findprog {
    my $prog = shift;
    first { -x $_ } map { "$_/$prog" } (
        File::Basename::dirname($^X),
        split /:/, $ENV{PATH},
    );
}

my $start_server = findprog('start_server');
my $plackup = findprog('plackup');

sub doit {
    my $pkg = shift;
    my $port = Test::TCP::empty_port();
    my $server_pid = fork();
    die "fork failed:$!"
        unless defined $server_pid;
    if ($server_pid == 0) {
        # child == server
        exec(
            $start_server,
            "--port=$port",
            '--',
            $plackup,
            '--server',
            $pkg,
            't/00base-hello.psgi',
        );
        die "failed to launch server using start_server:$!";
    }
    sleep 1;
    
    my $ua = LWP::UserAgent->new;
    my $response = $ua->get("http://127.0.0.1:$port/");
    ok($response->is_success, "request successfull");
    is($response->content, 'hello', 'content is hello');
    
    kill 'TERM', $server_pid;
    while (wait == -1) {}
}

if ($start_server) {
    doit('Starlet');
    doit('Standalone::Prefork::Server::Starter');
} else {
    warn "could not find `start_server' next to $^X nor from \$PATH, skipping tests";
}

done_testing;
