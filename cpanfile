requires 'perl', '5.008001';
requires 'Parallel::Prefork', '0.18';
requires 'Plack', '0.992';
requires 'Server::Starter', '0.06';

on test => sub {
    requires 'LWP::UserAgent', '5.8';
    requires 'Test::More', '0.88';
    requires 'Test::TCP', '2.1';
};
