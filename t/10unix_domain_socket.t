use strict;
use Test::More;
use Plack::Loader;
use File::Temp;
use IO::Socket::UNIX;
use Socket;

my ($fh, $filename) = File::Temp::tempfile(UNLINK=>0);
close($fh);
unlink($filename);

my $sock = IO::Socket::UNIX->new(
    Listen => Socket::SOMAXCONN(),
    Local  => $filename,
) or die "failed to listen to socket $filename:$!";
$ENV{SERVER_STARTER_PORT} = $filename.'='.$sock->fileno;

my $pid = fork;
if ( $pid == 0 ) {
    # server
    my $loader = Plack::Loader->load(
        'Starlet',
        max_workers => 5,
    );
    $loader->run(sub{
        my $env = shift;
        my $remote = $env->{REMOTE_ADDR};
        $remote = 'UNIX' if ! defined $remote;
        [200, ['Content-Type'=>'text/html'], ["HELLO $remote"]];
    });
    exit;
}

sleep 1;

my $client = IO::Socket::UNIX->new(
    Peer  => $filename,
    timeout => 3,
) or die "failed to listen to socket $filename:$!";

$client->syswrite("GET / HTTP/1.0\015\012\015\012");
$client->sysread(my $buf, 1024);
like $buf, qr/Starlet/;
like $buf, qr/HELLO UNIX/;

done_testing();

kill 'TERM',$pid;
waitpid($pid,0);
unlink($filename);

