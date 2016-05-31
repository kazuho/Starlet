use strict;
use warnings;

use Test::More;
use Plack::Loader;
use Plack::Runner;

$SIG{CONT} = sub { pass('child_finish has been executed.') };

subtest 'child_finish' => sub {
    plan tests => 1;
    my $main_pid = $$;
    my $pid = fork;
    if ( $pid == 0 ) {
        my $loader = Plack::Loader->load(
            'Starlet',
            max_workers => 1,
            child_finish  => sub { kill 'CONT', $main_pid },
        );
        $loader->run(sub{
            my $env = shift;
            [200, ['Content-Type'=>'text/html'], ["HELLO"]];
        });
        exit 0;
    }

    sleep 1;

    kill 'TERM', $pid;
    waitpid($pid, 0);
};

subtest 'hook_module' => sub {
    plan tests => 1;
    our $main_pid = $$;
    my $pid = fork;
    if ( $pid == 0 ) {
        {
            package ChildFinishHook;
            sub child_finish_hook { kill 'CONT', $main_pid }
        }
        my $runner = Plack::Runner->new;
        $runner->parse_options(
            qw(--server Starlet --max-workers 1
               --hook-module ChildFinishHook --child-finish-hook child_finish_hook)
        );
        $runner->run(sub{
            my $env = shift;
            [200, ['Content-Type'=>'text/html'], ["HELLO"]];
        });
        exit 0;
    }

    sleep 1;

    kill 'TERM', $pid;
    waitpid($pid, 0);
};

done_testing();
