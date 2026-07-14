# ABOUTME: Tests SoN::FromOptree GAPs splice (array length-mutating) instead of
# ABOUTME: silently reading the pre-splice length. zhi 019f5ed3.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# `splice(@a, 1, 1)` removes an element, shrinking @a, but like push/unshift the
# generic builtin Call built for splice is NOT threaded onto @a's memory version
# (only shift/pop are memory-SSA modeled). A later `scalar @a` reads the
# PRE-splice binding and returns the old length -- a silent miscompile
# (`my @a=(1,2,3); splice(@a,1,1); scalar @a` -> 3, not 2). GAP loudly per
# GAP-not-miscompile until the length mutation is memory-modeled.

subtest 'splice GAPs loudly (not a silent length miscompile)' => sub {
    my $sub = sub { my @a=(1,2,3); splice(@a,1,1); scalar @a };
    ok(!lives { SoN::FromOptree->translate($sub) },
        'translate dies on a splice') or diag('expected a GAP, got a graph');
    like($@, qr/GAP.*splice/i, 'the die is a loud GAP naming splice')
        or diag("actual: $@");
};

# A 4-arg replacing splice (splice @a,$o,$l,@repl) also mutates length; same GAP.
subtest 'replacing splice also GAPs' => sub {
    my $sub = sub { my @a=(1,2,3); splice(@a,1,1,9,9); scalar @a };
    ok(!lives { SoN::FromOptree->translate($sub) }, 'replacing splice GAPs')
        or diag('expected a GAP, got a graph');
    like($@, qr/GAP.*splice/i, 'the die is a loud GAP') or diag("actual: $@");
};

done_testing;
