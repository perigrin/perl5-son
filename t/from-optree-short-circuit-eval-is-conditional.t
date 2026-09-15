# ABOUTME: `eval A and eval B` runs B only if A was true; the graph must say so.
# ABOUTME: Pinning both on one predecessor loses the short circuit entirely.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    my $d = eval { JSON::PP->new->decode($j) } or return undef;
    return $d->{methods}{'main::__PROGRAM__'};
}

# CONTROL IS A TOTAL ORDER OVER EFFECTS, so two effects naming the same
# predecessor is a fork -- and a fork with no If says nothing about which runs.
#
# Measured on `my $r = (eval q{bump(); 0} and eval q{bump(); 1})`, where perl
# runs the FIRST eval only (n=1, r=0):
#
#     fork at 14 -> [Coerce(17), Print(26)]
#
# The second eval and the statement after the expression both claim node 14.
# Nothing marks the second eval conditional, so a consumer is free to run it --
# and comp/colon.t has the same shape three deep, where FOUR nodes share one
# predecessor.
#
# THE COUNT IS THE CHECK. A graph that runs both evals still produces a value;
# only the side effect separates them.
sub forks ($g) {
    my %succ;
    for my $n ($g->{nodes}->@*) {
        push $succ{ $n->{control_in} }->@*, $n
            if defined $n->{control_in};
    }
    return grep { $succ{$_}->@* > 1 } sort { $a <=> $b } keys %succ;
}

subtest 'a short-circuited eval is conditional' => sub {
    todo 'both evals are pinned on one predecessor' => sub {
    my $src = <<'SRC';
our $n = 0;
sub bump { $n++; 1 }
my $r = (eval q{bump(); 0} and eval q{bump(); 1});
print "n=$n\n";
SRC
    is run_perl($src), "n=1\n", 'perl runs only the first' or return;

    my $g = graph_of($src);
    ok $g, 'it translates' or return;
    is [forks($g)], [],
        'no two effects claim the same control predecessor';
    };
};

# AN UNCONDITIONAL SEQUENCE MUST STAY CHAINED -- measured, three plain evals
# chain 13 -> 14 -> 15 -> 16 -> 17, which is what makes the `and` case the
# defect rather than eval in general.
subtest 'sequential evals chain' => sub {
    my $src = <<'SRC';
our $n = 0;
sub bump { $n++; 1 }
eval q{bump()};
eval q{bump()};
eval q{bump()};
print "n=$n\n";
SRC
    is run_perl($src), "n=3\n", 'perl runs all three' or return;

    my $g = graph_of($src);
    ok $g, 'it translates' or return;
    is [forks($g)], [], 'each effect names a distinct predecessor';
};

done_testing;
