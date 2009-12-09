use inc::Module::Install;

all_from 'lib/Plack/Server/Standalone/Prefork/Server/Starter.pm';
readme_from 'lib/Plack/Server/Standalone/Prefork/Server/Starter.pm';

requires 'Plack' => 0.9020;
requires 'Server::Starter' => 0.05;
test_requires 'Test::TCP' => 0.15;

WriteAll;
