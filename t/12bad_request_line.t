use strict;
use warnings;
use Test::More;
use Test::TCP qw(test_tcp);
use IO::Socket::INET;
use Plack::Loader;

test_tcp(
    client => sub {
        my $port = shift;
        my $sock = IO::Socket::INET->new(
            PeerAddr => "localhost:$port",
            Proto => 'tcp',
        );
        my $req = "GET /bad request header/ HTTP/1.0\015\012\015\012";
        $sock->syswrite($req, length $req);
        $sock->sysread(my $buf, 1024);
        like $buf, qr/\b400\b/;
        note $buf;
    },
    server => sub {
        my $port = shift;
        local $SIG{__WARN__} = sub {
            ok 0, "No warnings";
            diag @_;
        };
        my $loader = Plack::Loader->load('Starlet', port => $port);
        $loader->run(sub { [200, ['Content-Type' => 'text/plain'], ['OK']] });
        exit;
    },
);

done_testing;
