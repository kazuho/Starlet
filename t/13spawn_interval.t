use strict;
use warnings;

use File::Basename ();
use List::Util qw(first);
use Test::TCP ();
use File::Temp qw(tmpnam);

use Test::More;

BEGIN {
    use_ok('Server::Starter');
};

sub findprog {
    my $prog = shift;
    first { -x $_ } map { "$_/$prog" } (
        File::Basename::dirname($^X),
        split /:/, $ENV{PATH},
    );
}

sub read_status_file {
    my $path = shift;
    open my $fh, $path or die "failed to open status file $path";
    my $contents = do { local $/; <$fh> };
    close $fh;
    my @pids = map { (split /:/, $_)[1] } split /\n/, $contents;
    return @pids;
}

my $start_server = findprog('start_server');
my $plackup = findprog('plackup');

sub doit {
    my $pkg = shift;
    my $port = Test::TCP::empty_port();
    my $status_file_path = tmpnam();
    my $server_pid = fork();
    die "fork failed:$!"
        unless defined $server_pid;
    if ($server_pid == 0) {
        # child == server
        exec(
            $start_server,
            "--port=$port",
            "--status-file=$status_file_path",
            "--signal-on-hup=USR1",
            '--',
            $plackup,
            '--server',
            $pkg,
            '--max-workers=5',  # just for finish test fast
            '--spawn-interval=1',
            't/00base-hello.psgi',
        );
        die "failed to launch server using start_server:$!";
    }
    # wait until all workers spawn
    sleep 5;
    my @pids = read_status_file($status_file_path);
    my $sent_num_before_hup = kill 0, $pids[0];

    kill 'HUP', $server_pid;

    sleep 4;
    my $sent_num_after_hup = kill 0, $pids[0];
    is $sent_num_before_hup, 1, "process still alive before HUP signal";
    is $sent_num_after_hup, 1, "old generation process still alive for a while after HUP signal";
    sleep 1;
    kill 'TERM', $server_pid;
    while (wait == -1) {}
}

if ($start_server) {
    doit('Starlet');
} else {
    warn "could not find `start_server' next to $^X nor from \$PATH, skipping tests";
}

done_testing;
