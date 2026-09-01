# ABOUTME: Tests SoN::FromOptree GAPs a multi-value list return instead of
# ABOUTME: silently dropping all-but-one value (F4 callee side, zhi 019f5e41).

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# `return (10,20,30)` in a list-context caller (`my @x = f()`) must yield all
# three values. The stack simulator's _exit_record kept only $args->[-1] (the
# last value) -- correct for scalar/comma-operator context, a silent drop for
# list context. The producer cannot know the caller's runtime wantarray, so a
# >1-value list return cannot be soundly represented by a single scalar Return.
# Per GAP-not-miscompile: refuse loudly rather than drop values.
#
# A LIST RETURN IS NOT AN ARRAY RETURN, which is the trap in "just wrap the N
# values in the container `return @a` already uses". Measured in SCALAR context:
#
#     sub f { return (10,20,30) }        my $s = f();  -> 30  (the last value)
#     sub f { my @a=(10,20,30); return @a }  my $s=f() ->  3  (the COUNT)
#
# So that wrapper makes a list return behave like an array return. Tried, and
# it miscompiled exactly there: `my $s = f(); print $s` produced
# Print <- Call(:Array) -- the whole container -- where perl prints 30.
#
# Lowering this needs the CALLSITE's OPf_WANT threaded into the callee's return
# shape, since one sub can be called both ways in one program. That is real
# work, not a missing wrapper, and until it exists the refusal is correct.

subtest 'multi-value list return GAPs loudly (not silent drop)' => sub {
    my $sub = eval 'sub { return (10,20,30) }';
    my $err;
    ok(!lives { SoN::FromOptree->translate($sub) },
        'translate dies on a multi-value list return')
        or diag('expected a GAP, got a graph');
    $err = $@;
    like($err, qr/GAP.*multi-value|GAP.*list return/i,
        'the die is a loud GAP naming the multi-value list return')
        or diag("actual: $err");
};

subtest 'a single-value return still lowers (not over-GAPped)' => sub {
    my $sub = eval 'sub { return 42 }';
    my $graph;
    ok(lives { $graph = SoN::FromOptree->translate($sub) },
        'a single-value return does not GAP')
        or diag($@);
    ok(defined $graph, 'got a graph');
};

subtest 'a bare `return;` (empty) still lowers' => sub {
    my $sub = eval 'sub { return }';
    my $graph;
    ok(lives { $graph = SoN::FromOptree->translate($sub) },
        'an empty return does not GAP')
        or diag($@);
    ok(defined $graph, 'got a graph');
};

done_testing;
