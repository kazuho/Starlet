use strict;
use warnings;

use Plack::Loader;
use Test::More;
use Test::TCP qw(empty_port);

my $starlet = Plack::Loader->load(
    'Starlet',
    min_reqs_per_child => 5,
    max_reqs_per_child => 10,
);

my ($min, $max) = (7, 7);
for (my $i = 0; $i < 10000; $i++) {
    my $n = $starlet->_calc_reqs_per_child();
    $min = $n
        if $n < $min;
    $max = $n
        if $n > $max;
}

is $min, 5, "min";
is $max, 10, "max";

done_testing;
