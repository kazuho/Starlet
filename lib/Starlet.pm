package Starlet;

use 5.008_001;

our $VERSION = '0.08';

1;
__END__

=head1 NAME

Starlet

=head1 SYNOPSIS

  % start_server --port=80 -- plackup -s Starlet [options] your-app.psgi

  or if you do not need hot deploy,

  % plackup -s Starlet --port=80 [options] your-app.psgi

=head1 DESCRIPTION

Starlet is a standalone HTTP/1.0 server formerly known as L<Plack::Server::Standalone::Prefork> and L<Plack::Server::Standalone::Prefork::Server::Starter>.

The server supports following features, and is suitable for running HTTP application servers behind a reverse proxy.

- prefork and graceful shutdown using L<Parallel::Prefork>

- hot deploy using L<Server::Starter>

- fast HTTP processing using L<HTTP::Parser::XS> (optional)

=head1 COMMAND LINE OPTIONS

In addition to the options supported by L<plackup>, Starlet accepts following options(s).

=head2 --max-workers=#

number of worker processes (default: 10)

=head2 --timeout=#

seconds until timeout (default: 300)

=head2 --keepalive-timeout=#

timeout for persistent connections (default: 2)

=head2 --max-keepalive-reqs=#

max. number of requests allowed per single persistent connection.  If set to one, persistent connections are disabled (default: 1)

=head2 --max-reqs-per-child=#

max. number of requests to be handled before a worker process exits (default: 100)

=head1 NOTES

If you are looking for a standalone preforking HTTP server, then you should really look at L<Starman>.  However if your all want is a simple HTTP server that runs behind a reverse proxy, this good old module still does what it used to.

=head1 SEE ALSO

L<Parallel::Prefork>
L<Starman>
L<Server::Starter>

=head1 AUTHOR

Kazuho Oku

miyagawa

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
