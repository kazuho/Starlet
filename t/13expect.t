use strict;
use warnings;
use Test::More;
use Test::TCP;
use LWP::UserAgent;
use Plack::Loader;

test_tcp(
    client => sub {
        my $port = shift;
        sleep 1;
        my $ua  = LWP::UserAgent->new;
        my $res = $ua->post(
            "http://localhost:$port/",
            { blah => 1 },
            Expect => '100-continue'
        );
        ok( $res->is_success );
        is( $res->content, 'HELLO', 'Expect header in standard case works' );


        $res = $ua->post(
            "http://localhost:$port/",
            { blah => 1 },
            Expect => '100-Continue'
        );
        ok( $res->is_success );
        is( $res->content, 'HELLO', 'Expect header is case insensitive' );
    },
    server => sub {
        my $port   = shift;
        my $loader = Plack::Loader->load(
            'Starlet',
            port        => $port,
            max_workers => 5,
        );
        $loader->run(
            sub {
                my $env = shift;
                [ 200, [], ['HELLO'] ];
            }
        );
        exit;
    },
);

done_testing;

