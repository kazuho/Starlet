use strict;
use File::Temp qw(tempfile);
use IO::Socket::UNIX;
use Plack::Loader;
use Socket;
use Test::More;

(undef, my $sockfile) = tempfile(UNLINK => 0);
unlink $sockfile;

sub doit {
    my $create_loader = shift;

    my $pid = fork;
    die "fork failed:$!"
        unless defined $pid;
    if ($pid == 0) {
        # server
        my $loader = $create_loader->();
        $loader->run(sub {
            my $env = shift;
            my $remote = $env->{REMOTE_ADDR};
            $remote = 'UNIX' if ! defined $remote;
            return [
                200,
                ['Content-Type'=>'text/html'],
                ["HELLO $remote"],
            ];
        });
        exit;
    }

    sleep 1;

    my $client = IO::Socket::UNIX->new(
        Peer  => $sockfile,
        timeout => 3,
    ) or die "failed to listen to socket $sockfile:$!";

    $client->syswrite("GET / HTTP/1.0\015\012\015\012");
    $client->sysread(my $buf, 1024);
    like $buf, qr/Starlet/;
    like $buf, qr/HELLO UNIX/;

    kill 'TERM', $pid;
    waitpid($pid, 0);
    unlink($sockfile);
}

subtest 'direct' => sub {
    doit(sub {
        return Plack::Loader->load(
            'Starlet',
            max_workers => 5,
            socket => $sockfile,
        );
    });
};

subtest 'server-starter' => sub {
    doit(sub {
        my $sock = IO::Socket::UNIX->new(
            Listen => Socket::SOMAXCONN(),
            Local  => $sockfile,
        ) or die "failed to listen to socket $sockfile:$!";
        $ENV{SERVER_STARTER_PORT} = "$sockfile=@{[$sock->fileno]}";
        return Plack::Loader->load(
            'Starlet',
            max_workers => 5,
        );
    });
};


done_testing();
