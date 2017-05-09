use strict;
use Test::TCP;
use Plack::Test;
use HTTP::Request;
use Test::More;
use Digest::MD5;


$Plack::Test::Impl = "Server";
$ENV{PLACK_SERVER} = 'Starlet';

my $file = "t/assets/baybridge.jpg";

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

test_psgi $app, sub {
    my $cb = shift;

    open my $fh, "<:raw", $file;
    local $/ = \1024;

    my $req = HTTP::Request->new(POST => "http://localhost/");
    $req->content(sub { scalar <$fh> });

    my $res = $cb->($req);

    is $res->header('X-Content-Length'), 14750;
    is Digest::MD5::md5_hex($res->content), '70546a79c7abb9c497ca91730a0686e4';
};

done_testing;
