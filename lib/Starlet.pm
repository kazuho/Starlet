package Starlet;

use 5.008_001;

our $VERSION = '0.24';

1;
__END__

=head1 NAME

Starlet - a simple, high-performance PSGI/Plack HTTP server

=head1 SYNOPSIS

  % start_server --port=80 -- plackup -s Starlet [options] your-app.psgi

  or if you do not need hot deploy,

  % plackup -s Starlet --port=80 [options] your-app.psgi

=head1 DESCRIPTION

Starlet is a standalone HTTP/1.1 web server, formerly known as L<Plack::Server::Standalone::Prefork> and L<Plack::Server::Standalone::Prefork::Server::Starter>.

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

=head2 --min-reqs-per-child=#

if set, randomizes the number of requests handled by a single worker process between the value and that supplied by C<--max-reqs-per-chlid> (default: none)

=head2 --spawn-interval=#

if set, worker processes will not be spawned more than once than every given seconds.  Also, when SIGHUP is being received, no more than one worker processes will be collected every given seconds.  This feature is useful for doing a "slow-restart".  See http://blog.kazuhooku.com/2011/04/web-serverstarter-parallelprefork.html for more information. (dedault: none)

=head1 NOTES

L<Starlet> is designed and implemented to be simple, secure and fast, especially for running as a HTTP application server running behind a reverse proxy.  It only depends on a minimal number of well-designed (and well-focused) modules.

On the other hand if you are looking for a standalone preforking HTTP server that receives HTTP requests directly from the Internet, then you should look at L<Starman>.

=head1 SEE ALSO

L<Parallel::Prefork>
L<Starman>
L<Server::Starter>

=head1 AUTHOR

Kazuho Oku

miyagawa

kazeburo

Tomohiro Takezawa

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
