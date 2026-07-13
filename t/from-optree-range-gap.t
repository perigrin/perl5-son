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

subtest 'a runtime range (non-constant bound) in list context refuses loudly' => sub {
    like(translate_dies('sub { my $n = 4; my @q = (1 .. $n); scalar @q }'),
        qr/GAP.*range/i, 'my @q = (1..$n) dies with a GAP message');
    like(translate_dies('sub { my $lo = 2; my @q = ($lo .. 5); scalar @q }'),
        qr/GAP.*range/i, 'a non-constant LOW bound also dies with a GAP');
};

subtest 'a constant range still translates (the GAP does not over-fire)' => sub {
    # (1..4) constant-folds to a const[AV]; no runtime range op is emitted, so the
    # range GAP must not fire on it (019f5942 expands the folded AV).
    is(translate_ok('sub { my @q = (1 .. 4); scalar @q }'), undef,
        'a constant range (1..4) translates cleanly, no range GAP');
};

done_testing();
