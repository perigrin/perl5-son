# ABOUTME: A runtime range (1..$n, non-constant bound) refuses loudly rather than
# ABOUTME: silently building a 1-element array (zhi 019f5b4b).

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# A constant range (1..4) constant-folds to a const[AV] and is expanded to its N
# elements (zhi 019f5942). A range with a NON-constant bound (1..$n) does NOT
# fold -- perl emits the runtime range/flip/flop operators, which have no
# FromOptree handler and were silently SKIPPED as generic branch ops, so the list
# collapsed to 1 element (`my @q=(1..$n); scalar @q` gave 1, oracle 4 -- a silent
# miscompile). Until a runtime range is lowered (a counted expansion), GAP loudly.

sub translate_dies ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return dies { SoN::FromOptree->translate($cv) };
}

sub translate_ok ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return dies { SoN::FromOptree->translate($cv) };   # returns undef on success
}

# THE REFUSAL IS LIFTED. A list-context runtime range now lowers to a Range
# node -- see t/from-optree-runtime-range.t, which carries the round trips.
# This subtest pinned the LIMITATION, and a refusal test encodes a limitation
# rather than a fact about perl ([[a-refusal-test-must-name-its-cause]]), so it
# becomes the positive assertion it was always heading for.
#
# What the original defect was, kept because it is the reason the node has to
# hold both bounds: the range's list value was DROPPED and the enclosing
# aassign saw a 1-element stack, so `my @q=(1..$n); scalar @q` gave 1 where
# perl gives 4 (zhi 019f5b4b).
subtest 'a runtime range in list context translates' => sub {
    is(translate_ok('sub { my $n = 4; my @q = (1 .. $n); scalar @q }'), undef,
        'my @q = (1..$n) translates');
    is(translate_ok('sub { my $lo = 2; my @q = ($lo .. 5); scalar @q }'), undef,
        'a non-constant LOW bound translates too');
};

# THE SCALAR FORM IS A DIFFERENT CONSTRUCT and still refuses, under its own
# name. `range`/`flip`/`flop` are three op names over two constructs, split by
# the context flag.
subtest 'a scalar-context flip-flop still refuses, naming itself' => sub {
    like(translate_dies('sub { my $x = 3; my $r = (($x==1)..($x==5)) ? 1 : 0; $r }'),
        qr/flip-flop/, 'the refusal names the flip-flop');
};

subtest 'a constant range still translates (the GAP does not over-fire)' => sub {
    # (1..4) constant-folds to a const[AV]; no runtime range op is emitted, so the
    # range GAP must not fire on it (019f5942 expands the folded AV).
    is(translate_ok('sub { my @q = (1 .. 4); scalar @q }'), undef,
        'a constant range (1..4) translates cleanly, no range GAP');
};

done_testing();
