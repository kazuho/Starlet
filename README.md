# NAME

Starlet - a simple, high-performance PSGI/Plack HTTP server

# SYNOPSIS

    % start_server --port=80 -- plackup -s Starlet [options] your-app.psgi

    or if you do not need hot deploy,

    % plackup -s Starlet --port=80 [options] your-app.psgi

# DESCRIPTION

Starlet is a standalone HTTP/1.1 web server, formerly known as [Plack::Server::Standalone::Prefork](https://metacpan.org/pod/Plack%3A%3AServer%3A%3AStandalone%3A%3APrefork) and [Plack::Server::Standalone::Prefork::Server::Starter](https://metacpan.org/pod/Plack%3A%3AServer%3A%3AStandalone%3A%3APrefork%3A%3AServer%3A%3AStarter).

The server supports following features, and is suitable for running HTTP application servers behind a reverse proxy.

\- prefork and graceful shutdown using [Parallel::Prefork](https://metacpan.org/pod/Parallel%3A%3APrefork)

\- hot deploy using [Server::Starter](https://metacpan.org/pod/Server%3A%3AStarter)

\- fast HTTP processing using [HTTP::Parser::XS](https://metacpan.org/pod/HTTP%3A%3AParser%3A%3AXS) (optional)

# COMMAND LINE OPTIONS

In addition to the options supported by [plackup](https://metacpan.org/pod/plackup), Starlet accepts following options(s).

## --max-workers=#

number of worker processes (default: 10)

## --timeout=#

seconds until timeout (default: 300)

## --keepalive-timeout=#

timeout for persistent connections (default: 2)

## --max-keepalive-reqs=#

max. number of requests allowed per single persistent connection.  If set to one, persistent connections are disabled (default: 1)

## --max-reqs-per-child=#

max. number of requests to be handled before a worker process exits (default: 100)

## --min-reqs-per-child=#

if set, randomizes the number of requests handled by a single worker process between the value and that supplied by `--max-reqs-per-chlid` (default: none)

## --spawn-interval=#

if set, worker processes will not be spawned more than once than every given seconds.  Also, when SIGHUP is being received, no more than one worker processes will be collected every given seconds.  This feature is useful for doing a "slow-restart".  See http://blog.kazuhooku.com/2011/04/web-serverstarter-parallelprefork.html for more information. (default: none)

## --child-exit=s

the subroutine code to be executed right before a child process exits. e.g. `--child-exit='sub { POSIX::_exit(0) }'`. (default: none)

# Extensions to PSGI

## psgix.informational

Starlets exposes a callback named `psgix.informational` that can be used for sending an informational response.
The callback accepts two arguments, the first argument being the status code and the second being an arrayref of the headers to be sent.
Example below sends an 103 response before processing the request to build a final response.  

    sub {
        my $env = shift;
        $env["psgix.informational"}->(103, [
          'link' => '</style.css>; rel=preload'
        ]);
        my $resp = ... application logic ...
        $resp;
    }

# NOTES

[Starlet](https://metacpan.org/pod/Starlet) is designed and implemented to be simple, secure and fast, especially for running as an HTTP application server running behind a reverse proxy.  It only depends on a minimal number of well-designed (and well-focused) modules.

# SEE ALSO

[Parallel::Prefork](https://metacpan.org/pod/Parallel%3A%3APrefork)
[Starman](https://metacpan.org/pod/Starman)
[Server::Starter](https://metacpan.org/pod/Server%3A%3AStarter)

# AUTHOR

Kazuho Oku

miyagawa

kazeburo

Tomohiro Takezawa

# LICENSE

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See [http://www.perl.com/perl/misc/Artistic.html](http://www.perl.com/perl/misc/Artistic.html)
