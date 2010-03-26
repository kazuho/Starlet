package Starlet;

use 5.008_001;

our $VERSION = '0.05';

1;
__END__

=head1 NAME

Starlet

=head1 SYNOPSIS

  % start_server --port=80 -- plackup -s Starlet [options] your-app.psgi

  or if you do not need hot deploy,

  % plackup -s Starlet --port=80 [options] your-app.psgi

=head1 DESCRIPTION

Starlet is a standalone HTTP/1.0 server formerly known as L<Plack::Server::Standalone::Prefork::Server::Starter>, a wrapper of L<HTTP::Server::PSGI> using L<Server::Starter>.

The server supports following features, and is suitable for running HTTP application servers behind a reverse proxy.

- prefork and graceful shutdown using L<Parallel::Prefork>

- hot deploy using L<Server::Starter>

- fast HTTP processing using L<HTTP::Parser::XS> (optional)

=head1 COMMAND LINE OPTIONS

In addition to the options supported by L<HTTP::Server::PSGI>, Starlet accepts following options(s).

--num-workers=#  number of worker processes (default: 10)

=head1 NOTES

If you are looking for a standalone preforking HTTP server, then you should really look at L<Starman>.  However if your all want is a simple HTTP server that runs behind a reverse proxy, this good old module still does what it used to.

=head1 SEE ALSO

L<Parallel::Prefork>
L<Starman>
L<Server::Starter>

=head1 AUTHOR

Kazuho Oku

=head1 THANKS TO

miyagawa

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
