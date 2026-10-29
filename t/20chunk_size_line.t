use strict;
use Test::TCP;
use Plack::Loader;
use Test::More;
use IO::Socket::INET;
use Digest::MD5;

$ENV{PLACK_SERVER} = 'Starlet';

my $app = sub {
    my $env = shift;
    $env->{'psgi.input'}->read(my $body, $env->{CONTENT_LENGTH});
    return [ 200, [ 'Content-Type', 'text/plain', 'X-MD5', Digest::MD5::md5_hex($body) ], [ 'ok' ] ];
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
print {$sock} "POST / HTTP/1.1\015\012Transfer-Encoding: chunked\015\012\015\012", 'f' x 5000;
shutdown $sock, 1;
my $res_str = do { local $/; <$sock> };
like $res_str, qr{^HTTP/1\.1 400 }, 'overlong unterminated chunk-size line is rejected';

$sock = IO::Socket::INET->new(
    PeerAddr => '127.0.0.1',
    PeerPort => $server->port,
    Proto => 'tcp',
);
print {$sock} "POST / HTTP/1.1\015\012Transfer-Encoding: chunked\015\012\015\012",
    '5;', 'x' x 5000, "\015\012hello\015\0120\015\012\015\012";
$res_str = do { local $/; <$sock> };
like $res_str, qr{^HTTP/1\.1 400 }, 'overlong complete chunk-size line is rejected';

my $data = join '', map { chr($_ % 251) } 1 .. 300000;
$sock = IO::Socket::INET->new(
    PeerAddr => '127.0.0.1',
    PeerPort => $server->port,
    Proto => 'tcp',
);
print {$sock} "POST / HTTP/1.1\015\012Transfer-Encoding: chunked\015\012\015\012",
    sprintf("%x\015\012", length $data), $data, "\015\012", "0\015\012\015\012";
$res_str = do { local $/; <$sock> };
like $res_str, qr{^X-MD5: @{[ Digest::MD5::md5_hex($data) ]}\015$}m, 'one chunk larger than a read is decoded';

done_testing;
