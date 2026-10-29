use strict;
use Test::TCP;
use Plack::Loader;
use Test::More;
use IO::Socket::INET;

$ENV{PLACK_SERVER} = 'Starlet';

my $app = sub {
    return [ 200, [ 'Content-Type', 'text/plain' ], [ 'ok' ] ];
};

my $server = Test::TCP->new(
    code => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port, host => '127.0.0.1', max_workers => 0)->run($app);
        exit;
    },
);

my $sock = IO::Socket::INET->new(
    PeerAddr => '127.0.0.1',
    PeerPort => $server->port,
    Proto => 'tcp',
);
print {$sock} "POST / HTTP/1.0\015\012Content-Length: 1000000000000000000\015\012\015\012x=1";
shutdown $sock, 1;
my $res_str = do { local $/; <$sock> };

$sock = IO::Socket::INET->new(
    PeerAddr => '127.0.0.1',
    PeerPort => $server->port,
    Proto => 'tcp',
);
print {$sock} "GET / HTTP/1.0\015\012\015\012" if $sock;
$res_str = $sock ? do { local $/; <$sock> } : '';
like $res_str, qr{^HTTP/1\.1 200 }, 'server still answers after a huge Content-Length';

done_testing;
