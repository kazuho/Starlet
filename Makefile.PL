use inc::Module::Install;

all_from 'lib/Plack/Server/Standalone/Prefork/Server/Starter.pm';
readme_from 'lib/Plack/Server/Standalone/Prefork/Server/Starter.pm';

requires 'Plack' => 0.9020;
requires 'Server::Starter' => 0.05;

WriteAll;
