# ABOUTME: Tests the loop translator refuses loudly (GAP die) on shapes it cannot
# ABOUTME: lower correctly yet -- every case here previously MISCOMPILED silently.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# The producer's contract is refuse-or-lower: a graph that lowers and runs to
# the WRONG value is the worst outcome (Phase 4 trusts "divergence = producer
# bug", which is only sound with no known silent miscompiles). Each subtest
# pins a case the RC2b review reproduced as a silent wrong answer.

my %ICMP_OP = map { $_ => 1 } qw(NumEq NumLt NumGt NumLe NumGe NumNe);

sub translate_dies ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return dies { SoN::FromOptree->translate($cv) };
}

subtest 'last inside a loop body refuses loudly' => sub {
    # Was: last silently dropped -> Int:15 instead of Int:1.
    like(translate_dies(
        'sub { my $s = 0; my $n = 5; while ($n > 0) { $s = $s + $n; last; } $s }'),
        qr/GAP.*loop control/i, 'bare last dies with a GAP message');
};

subtest 'if/else inside a loop body refuses loudly' => sub {
    # Was: cond_expr silently skipped -> Int:0 instead of Int:103.
    like(translate_dies(
        'sub { my $n = 3; my $s = 0; while ($n > 0) { if ($n == 2) { $s = $s + 100 } else { $s = $s + 1 } $n = $n - 1 } $s }'),
        qr/GAP/, 'cond_expr in a body dies with a GAP message');
};

subtest 'nested loop inside a loop body refuses loudly' => sub {
    # Was: inner loop minted Projs on the OUTER Loop, truncated the body walk,
    # and one variant ran to Int:3 instead of Int:6 silently.
    like(translate_dies(
        'sub { my $s = 0; my $i = 2; while ($i > 0) { my $j = 2; while ($j > 0) { $s = $s + 1; $j = $j - 1 } $i = $i - 1 } $s }'),
        qr/GAP/, 'nested while dies with a GAP message');
};

subtest 'nested and/or inside a loop body refuses loudly (zhi 019f26a5)' => sub {
    # _walk_loop_body treats the FIRST and/or with stack_depth>0 as the loop
    # condition (mints the header Projs). A nested value-context and/or in the
    # body (`my $x = $i && 1`) would mint a SECOND Proj pair on the Loop and
    # corrupt the loop shape. $condition_fired++ refuses the second one loudly.
    like(translate_dies(
        'sub { my $i=0; my $r=0; while ($i<3) { my $x = ($i && 1); $r=$r+$x; $i=$i+1 } $r }'),
        qr/GAP: nested and.or inside a loop body/, 'nested && in the body dies with a GAP');
    like(translate_dies(
        'sub { my $i=0; my $r=0; while ($i<3) { my $x = ($i || 5); $r=$r+$x; $i=$i+1 } $r }'),
        qr/GAP: nested and.or inside a loop body/, 'nested || in the body dies with a GAP');
    # A COMPOUND loop condition (`while (A && B)`) is a nested and/or too --
    # single-comparison recovery cannot express short-circuit; GAP not miscompile.
    like(translate_dies(
        'sub { my $i=0; my $j=0; my $r=0; while ($i<3 && $j<5) { $r=$r+1; $i=$i+1; $j=$j+1 } $r }'),
        qr/GAP: nested and.or inside a loop body/, 'compound && condition dies with a GAP');
};

subtest 'postfix if/unless modifier inside a FOREACH body refuses loudly (zhi 019f5a27)' => sub {
    # A foreach has NO and/or loop condition (the range iterator drives it), so
    # the FIRST and/or the body walk sees is a postfix MODIFIER guard, not the
    # condition. _walk_loop_body mistook it for the loop condition, consumed it,
    # and never emitted the guard's If -- the guarded statement fired every
    # iteration (silent miscompile: `$s = $s + $i unless $i == 2` over 1..3 gave
    # 106, oracle 104). GAP loudly until the nested guard is lowered in a loop.
    like(translate_dies(
        'sub { my $s = 100; for my $i (1..3) { $s = $s + $i unless $i == 2; } $s }'),
        qr/GAP: nested and.or \(postfix modifier\) inside a foreach body/i,
        'unless-modifier in a foreach body dies with a GAP');
    like(translate_dies(
        'sub { my $s = 100; for my $i (1..3) { $s = $s + $i if $i != 2; } $s }'),
        qr/GAP: nested and.or \(postfix modifier\) inside a foreach body/i,
        'if-modifier in a foreach body dies with a GAP');
};

subtest 'a plain FOREACH body with no modifier still translates (the GAP does not over-fire)' => sub {
    # The foreach modifier GAP must not sweep up a plain foreach body.
    my $err = translate_dies(
        'sub { my $s = 0; for my $i (1..3) { $s = $s + $i } $s }');
    is($err, undef, 'a plain foreach with no body modifier translates cleanly');
};

subtest 'a plain loop body still translates (the GAP does not over-fire)' => sub {
    # The nested-and/or GAP must not sweep up a legitimate single-condition loop
    # with no body logical -- that is the working memory-SSA loop path.
    my $err = translate_dies(
        'sub { my $i=0; my $r=0; while ($i<3) { $r=$r+$i; $i=$i+1 } $r }');
    is($err, undef, 'a plain while loop with no body and/or translates cleanly');
};

subtest 'side-effecting loop condition now lowers (block form)' => sub {
    # Was a GAP: the failing (final) condition evaluation's mutation was lost, so
    # $i read Int:0 instead of Int:-1. Now the post-loop read binds to the Phi
    # back-edge (the AT-EXIT decrement). Full graph + E2E coverage lives in
    # t/from-optree-loop-cond-effect.t; here we only assert it no longer GAPs.
    is(translate_dies('sub { my $i = 3; while ($i-- > 0) { } $i }'), undef,
        'while ($i-- > 0) lowers, does not GAP');
};

subtest 'side-effecting loop condition now lowers (postfix form)' => sub {
    # Was a GAP: the postfix path leaked a pre-evaluation into the Phi init, so
    # $t read Int:1 instead of Int:3. Now the enter-path delegation to the
    # two-phase translation lowers it cleanly.
    is(translate_dies('sub { my $n = 3; my $t = 0; $t = $t + $n while $n-- > 0; $t }'),
        undef, 'postfix $n-- condition lowers, does not GAP');
};

subtest 'a side-effecting condition that ALSO stores to memory still GAPs' => sub {
    # The exit-path rebind models pad slots only; a condition that advances the
    # memory chain on the failing pass (an lvalue element `$a[$i]++`) is not
    # lowered -- it must still refuse loudly, not silently drop the memory effect.
    like(translate_dies('sub { my @a=(1,2,3); my $i=0; while ($a[$i]++ < 2) { } $i }'),
        qr/GAP.*condition/i, 'a memory-storing condition dies with a GAP message');
};

subtest 'loop condition with a body decoy comparison wires structurally (zhi 019f29ed)' => sub {
    # Was: a decoy body comparison consuming a header Phi could be picked as
    # the loop condition by the backend fallback -> one extra iteration. Now the
    # header condition carries a control edge to the Loop (set_loop_control), so
    # the backend recovers it structurally regardless of body comparisons.
    SoN::OptSuppress::suppress_peep();
    my $cv = eval
        'sub { my $n = 4; my $s = 0; while ($n > 0) { my $c = $n > -1; $s = $s + 1; $n = $n - 1 } $s }';
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;

    my $graph = SoN::FromOptree->translate($cv);
    ok($graph, 'the decoy-comparison loop translates cleanly (no GAP)');

    # Exactly one node carries loop_control, and it is the header condition
    # (NumGt(phi, 0)) -- not the body decoy (NumGt(phi, -1)).
    my @wired = grep { defined $_->loop_control } $graph->nodes->@*;
    is(scalar @wired, 1, 'exactly one condition is control-wired to the Loop');
    is($wired[0]->loop_control->operation, 'Loop',
        'the wired condition points at the Loop node');
    ok($ICMP_OP{ $wired[0]->operation },
        'the wired node is a comparison (the header condition, not the decoy)');
};

subtest 'bare-truthiness loop condition synthesizes a comparison (zhi 019f29ed)' => sub {
    # Was: `while ($n) { my $c = $n > 2; ... }` -- a bare-truthiness header whose
    # popped condition is the loop-carried Phi (not a comparison). set_loop_control
    # landed on the Phi, but the backend's strategy 1 only accepts icmp consumers,
    # so it fell to strategy 2 and picked the body decoy $n>2 -> silent miscompile
    # (Int:2 for oracle 4). Now the producer synthesizes NumNe($cond, 0) and wires
    # loop_control onto THAT, so an icmp is always the control-wired condition.
    SoN::OptSuppress::suppress_peep();
    my $cv = eval
        'sub { my $n = 4; my $s = 0; while ($n) { my $c = $n > 2; $s = $s + 1; $n = $n - 1 } $s }';
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;

    my $graph = SoN::FromOptree->translate($cv);
    ok($graph, 'the bare-truthiness loop translates cleanly (no GAP)');

    my @wired = grep { defined $_->loop_control } $graph->nodes->@*;
    is(scalar @wired, 1, 'exactly one condition is control-wired to the Loop');
    ok($ICMP_OP{ $wired[0]->operation },
        'the wired node is a synthesized comparison, not the bare Phi');
    is($wired[0]->operation, 'NumNe', 'the synthesized truthiness test is NumNe(cond, 0)');
};

subtest 'unstamped back-edge refuses loudly' => sub {
    # Was: the Phi was silently unstamped but body nodes kept stamps derived
    # from its optimistic init stamp, contaminating sibling Phi joins.
    like(translate_dies(
        'sub { my $x = 1; my $y = 0; my $n = 2; while ($n > 0) { $y = $x + 1; $x = shift; $n = $n - 1 } $y }'),
        qr/GAP/, 'loop-carried value losing its stamp dies with a GAP message');
};

subtest 'foreach range bound at IV_MAX refuses loudly' => sub {
    # Was: high+1 overflowed to an NV, wrapped to INT64_MIN in the .ll ->
    # zero iterations, Int:0 instead of Int:2.
    like(translate_dies(
        'sub { my $c = 0; for my $i (9223372036854775806..9223372036854775807) { $c = $c + 1 } $c }'),
        qr/GAP.*IV_MAX/i, 'IV_MAX upper bound dies with a GAP message');
};

subtest 'non-lexical foreach iterator gets a truthful GAP message' => sub {
    # Was: refused by ACCIDENT with a misleading "non-constant integer bounds"
    # message (the iterator gv rides the mark stack and trips the count check).
    like(translate_dies(
        'sub { my $s = 0; for (1..3) { $s = $s + 1 } $s }'),
        qr/GAP.*non-lexical/i, 'implicit $_ foreach names the real gap');
};

done_testing();
