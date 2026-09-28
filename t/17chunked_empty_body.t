use strict;
use warnings;
use Test::More;
use Test::TCP qw(test_tcp);
use IO::Socket::INET;
use Plack::Loader;

my %cases = (
    '/empty' => {
        body     => [''],
        expected => <<"EOT",
0\015
\015
EOT
    },
    '/hello' => {
        body     => ['hello'],
        expected => <<"EOT",
5\015
hello\015
0\015
\015
EOT
    },
);

test_tcp(
    client => sub {
        my $port = shift;
        for my $path (sort keys %cases) {
            my $sock = IO::Socket::INET->new(
                PeerAddr => "localhost:$port",
                Proto => 'tcp',
            );
            my $req = "GET $path HTTP/1.1\015\012\015\012";
            $sock->syswrite($req, length $req);

            my $resp = "";
            while ($sock->sysread($resp, 65536, length $resp)) {}

            my $expected_header = <<"EOT";
HTTP/1.1 200 OK\015
Date: Mon, 28 Sep 2026 00:00:00 GMT\015
Server: Starlet\015
Content-Type: text/plain\015
Transfer-Encoding: chunked\015
Connection: close\015
\015
EOT

            is $resp, $expected_header . $cases{$path}{expected}, $path;
        }
    },
    server => sub {
        my $port = shift;
        my $loader = Plack::Loader->load('Starlet', port => $port);
        $loader->run(sub {
            my $env = shift;
            [
                200,
                [
                    'Date'         => 'Mon, 28 Sep 2026 00:00:00 GMT',
                    'Server'       => 'Starlet',
                    'Content-Type' => 'text/plain',
                ],
                $cases{$env->{PATH_INFO}}{body},
            ];
        });
        exit;
    },
);

done_testing;
