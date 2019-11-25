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
    return [ 200, [ 'Content-Type', 'text/plain', 'X-Content-Length', $env->{CONTENT_LENGTH} ], [ $body ] ];
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
    "GET / HTTP/1.1\015\012"
    . "content-length: 3\015\012"
    . "content-length: 9\015\012"
    . "connection: close\015\012"
    . "\015\012"
    . "123456789"
);

my $res_str = do { local $/; <$sock> };
my ($status_line, ) = split /\015\012/, $res_str;
is $status_line, 'HTTP/1.1 400 Bad Request';

done_testing;
