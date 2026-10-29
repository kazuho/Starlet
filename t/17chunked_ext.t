use strict;
use Test::TCP;
use Plack::Loader;
use Test::More;
use IO::Socket::INET;

$ENV{PLACK_SERVER} = 'Starlet';

my $app = sub {
    my $env = shift;
    $env->{'psgi.input'}->read(my $body, $env->{CONTENT_LENGTH});
    return [ 200, [ 'Content-Type', 'text/plain', 'Content-Length', length $body ], [ $body ] ];
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
    "POST / HTTP/1.1\015\012"
    . "Transfer-Encoding: chunked\015\012"
    . "\015\012"
    . "5;name=value\015\012"
    . "hello\015\012"
    . "6;ext=a\015b\015\012"
    . " world\015\012"
    . "0\015\012"
    . "\015\012"
);

my $res_str = do { local $/; <$sock> };
like $res_str, qr{^HTTP/1\.1 200 .*\015\012\015\012hello world$}s, 'chunk extensions, including a bare CR, are skipped';

done_testing;
