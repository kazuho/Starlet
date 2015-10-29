use inc::Module::Install;

all_from 'lib/Starlet.pm';
readme_from 'lib/Starlet.pm';

requires 'Plack' => 0.9920;
requires 'Parallel::Prefork' => 0.17;

requires 'Server::Starter' => 0.06;
test_requires 'Test::More' => 0.88;
test_requires 'Test::TCP'  => 2.10;
test_requires 'LWP::UserAgent' => 5.80;

WriteAll;
