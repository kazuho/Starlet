use strict;
use Test::TCP;
use Plack::Loader;
use Test::More;
use IO::Socket::INET;

$ENV{PLACK_SERVER} = 'Starlet';

my $app = sub {
    my $env = shift;
    return [ 204, [ 'Content-Type', 'text/plain' ], [ 'body' ] ] if $env->{PATH_INFO} eq '/204';
    return [ 101, [ 'Upgrade', 'x-test', 'Connection', 'Upgrade' ], [ 'raw' ] ] if $env->{PATH_INFO} eq '/101';
    $env->{REQUEST_METHOD} = 'HEAD' if $env->{PATH_INFO} eq '/rewrite';
    return [ 200, [ 'Content-Type', 'text/plain' ], [ 'hello' ] ];
};

my $server = Test::TCP->new(
    code => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port, host => '127.0.0.1')->run($app);
        exit;
    },
);

my $sock = IO::Socket::INET->new(
    PeerAddr => '127.0.0.1',
    PeerPort => $server->port,
    Proto => 'tcp',
);

print {$sock} (
    "HEAD / HTTP/1.1\015\012\015\012"
    . "GET /204 HTTP/1.1\015\012\015\012"
    . "GET / HTTP/1.1\015\012Connection: close\015\012\015\012"
);

my $res_str = do { local $/; <$sock> };
my @res = split /(?=HTTP\/1\.1 )/, $res_str;
is +(split /\015\012\015\012/, $res[0], 2)[1], '', 'no body after a HEAD response';
is +(split /\015\012\015\012/, $res[1], 2)[1], '', 'no body after a 204 response';
like $res[2], qr{^HTTP/1\.1 200 .*\015\012\015\012.*hello}s, 'GET still has its body';

$sock = IO::Socket::INET->new(
    PeerAddr => '127.0.0.1',
    PeerPort => $server->port,
    Proto => 'tcp',
);
print {$sock} "GET /101 HTTP/1.1\015\012Upgrade: x-test\015\012Connection: Upgrade\015\012\015\012";
$res_str = do { local $/; <$sock> };
like $res_str, qr{^HTTP/1\.1 101 .*\015\012\015\012raw\z}s, 'bytes after a 101 are still sent';

$sock = IO::Socket::INET->new(
    PeerAddr => '127.0.0.1',
    PeerPort => $server->port,
    Proto => 'tcp',
);
print {$sock} "POST /rewrite HTTP/1.1\015\012Content-Length: 0\015\012\015\012";
$res_str = do { local $/; <$sock> };
like $res_str, qr{\015\012\015\012.*hello}s, 'the parsed method decides, not one the app rewrote';

done_testing;
