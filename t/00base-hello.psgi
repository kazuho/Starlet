my $handler = sub {
    return [ 200, [ "Content-Type" => "text/plain", "Content-Length" => 5 ], [ "hello" ] ];
};
