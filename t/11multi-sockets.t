use strict;
use warnings;

use Test::More;
use Plack::Loader;
use File::Temp;
use IO::Socket::INET;
use Net::EmptyPort qw(empty_port);
use Socket;

my $PORT_NUM   = 3;
my $UDS_NUM    = 4;
my $WORKER_NUM = 2;

my @tcp_socks = map {
    IO::Socket::INET->new(
        Listen    => Socket::SOMAXCONN(),
        Proto     => 'tcp',
        LocalPort => empty_port(),
        LocalAddr => '127.0.0.1',
        ReuseAddr => 1,
    ) or die "failed to listen:$!";
} (1..$PORT_NUM);

my @uds_socks = map {
    my ($fh, $filename) = File::Temp::tempfile(UNLINK=>0);
    close($fh);
    unlink($filename);
    IO::Socket::UNIX->new(
        Listen => Socket::SOMAXCONN(),
        Local  => $filename,
    ) or die "failed to listen to socket $filename:$!";
} (1..$UDS_NUM);

$ENV{SERVER_STARTER_PORT} = join ';', (
    map($_->sockport.'='.$_->fileno, @tcp_socks),
    map($_->hostpath.'='.$_->fileno, @uds_socks),
);

my $pid = fork;
if ( $pid == 0 ) {
    # server
    my $loader = Plack::Loader->load(
        'Starlet',
        max_workers => $WORKER_NUM,
    );
    $loader->run(sub{
        my $env = shift;
        [200, ['Content-Type'=>'text/html'], ["HELLO $env->{SERVER_PORT}"]];
    });
    exit;
}

sleep 1;

for my $listen_sock (@tcp_socks, @uds_socks) {
    my ($client, $port);
    if ($listen_sock->sockdomain == AF_INET) {
        $port = $listen_sock->sockport;
        $client = IO::Socket::INET->new(
            Proto    => 'tcp',
            PeerAddr => '127.0.0.1',
            PeerPort => $listen_sock->sockport,
            timeout  => 3,
        ) or die "failed to connect to socket $port:$!";
    }
    elsif ($listen_sock->sockdomain == AF_UNIX) {
        $port = $listen_sock->hostpath;
        $client = IO::Socket::UNIX->new(
            Peer    => $port,
            timeout => 3,
        ) or die "failed to connect to socket $port:$!";
    }
    else {
        die "unknown socket";
    }

    $client->syswrite("GET / HTTP/1.0\015\012\015\012");
    $client->sysread(my $buf, 1024);
    like $buf, qr/Starlet/;
    like $buf, qr/HELLO $port/;
}

done_testing();

kill 'TERM', $pid;
waitpid($pid,0);
