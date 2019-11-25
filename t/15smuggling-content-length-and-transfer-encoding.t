use strict;
use Test::TCP;
use Plack::Test;
use HTTP::Request;
use HTTP::Message::PSGI;
use Test::More;
use Digest::MD5;
use Plack::Test::Server;
use Test::TCP;
use IO::Socket::INET;

$ENV{PLACK_SERVER} = 'Starlet';

my $app = sub {
    my $env = shift;
    my $body;
    my $clen = $env->{CONTENT_LENGTH};
    while ($clen > 0) {
        $env->{'psgi.input'}->read(my $buf, $clen) or last;
        $clen -= length $buf;
        $body .= $buf;
    }
    return [ 200, [ 'Content-Type', 'text/plain', 'Content-Length', $env->{CONTENT_LENGTH} ], [ $body ] ];
};

my $server = Test::TCP->new(
    code => sub {
        my $sock_or_port = shift;
        my $server = Plack::Loader->auto(
            port => $sock_or_port,
            host => '127.0.0.1'
        );
        $server->run($app);
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
    . "content-length: 12\015\012"
    . "Transfer-Encoding: chunked\015\012"
    . "\015\012"
    . "5\015\012"
    . "hello\015\012"
    . "0\015\012"
    . "\015\012"
    . "world"
);

my $res_str = do { local $/; <$sock> };
like $res_str, qr{^HTTP/1\.1 200 .*\015\012\015\012hello$}s;

done_testing;
