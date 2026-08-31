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

# A case that used to GAP and now LOWERS needs the graph, not the exception.
sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

subtest 'last inside a loop body refuses loudly' => sub {
    # Was: last silently dropped -> Int:15 instead of Int:1.
    like(translate_dies(
        'sub { my $s = 0; my $n = 5; while ($n > 0) { $s = $s + $n; last; } $s }'),
        qr/GAP.*loop control/i, 'bare last dies with a GAP message');
};

subtest 'cond_expr inside a loop body now lowers (was a GAP)' => sub {
    # A cond_expr (ternary / if-else) in a loop body is dispatched to the shared
    # _handle_cond_expr, which builds the same select construction the main walk
    # uses -- it no longer GAPs. This if/else statement stores to a pad slot in
    # each arm, so it takes the pad-rebind merge path (a conditional per-slot
    # TernaryExpr) and lowers to the correct Int:102 (n=3:+1, n=2:+100, n=1:+1).
    # Was: cond_expr silently skipped -> wrong answer; then a loud GAP.
    my $cv = do {
        SoN::OptSuppress::suppress_peep();
        my $c = eval 'sub { my $n = 3; my $s = 0; while ($n > 0) { if ($n == 2) { $s = $s + 100 } else { $s = $s + 1 } $n = $n - 1 } $s }';
        SoN::OptSuppress::restore_peep();
        $c;
    };
    ok(lives { SoN::FromOptree->translate($cv) },
        'if/else in a loop body translates without a GAP die');
    my $graph = SoN::FromOptree->translate($cv);
    my @nodes = $graph->nodes->@*;
    ok((grep { $_->operation eq 'Loop' } @nodes), 'has a Loop node');
    ok((grep { $_->operation eq 'TernaryExpr' } @nodes),
        'the arm-select lowered to a TernaryExpr');
};

subtest 'a FIRST-statement `last if` in a while(1) body now lowers (hoisted)' => sub {
    # `while (1) { last if COND; BODY }` == `while (!COND) { BODY }`: the folded-away
    # `1` header means the conditional break IS the loop's continuation, negated.
    # The producer hoists the guard into the header (NumGe -> NumLt over the same
    # operands, control-wired to the Loop) and walks the false arm as the body.
    SoN::OptSuppress::suppress_peep();
    my $cv = eval 'sub { my $i = 0; my $s = 0; while (1) { last if $i >= 3; $s = $s + $i; $i = $i + 1 } $s }';
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;

    my $graph = SoN::FromOptree->translate($cv);
    ok($graph, 'the first-statement `last if` loop translates cleanly (no GAP)');
    ok((grep { $_->operation eq 'Loop' } $graph->nodes->@*), 'has a Loop node');

    # Exactly one node carries control_in pointed at a Loop, and it is the
    # NEGATED comparison (NumLt, the continuation `$i < 3`) -- not the
    # original NumGe guard.
    my @wired = grep {
        $_->can('control_in') && defined $_->control_in
            && $_->control_in->operation eq 'Loop'
    } $graph->nodes->@*;
    is(scalar @wired, 1, 'exactly one condition is control-wired to the Loop');
    is($wired[0] && $wired[0]->operation, 'NumLt',
        'the wired continuation is the negated guard (NumGe last-if -> NumLt continue)');
    is($wired[0] && $wired[0]->control_in && $wired[0]->control_in->operation, 'Loop',
        'it points at the Loop node');
};

subtest 'a `last if` deeper in the body now lowers (mid-body exit split)' => sub {
    # A `last if` that is NOT the first body statement is a genuine mid-body exit:
    # the producer builds a real If(C) at the break position whose taken arm
    # routes to the loop's exit Region (an extra predecessor) and whose other arm
    # continues the body. No hoist (that would reorder the check ahead of the
    # earlier statements). Was a GAP; now lowers to a Loop + If + exit Region.
    my $cv = do {
        SoN::OptSuppress::suppress_peep();
        my $c = eval 'sub { my $i = 0; my $s = 0; while ($i < 5) { $i = $i + 1; last if $i == 3; $s = $s + $i } $s }';
        SoN::OptSuppress::restore_peep();
        $c;
    };
    ok(lives { SoN::FromOptree->translate($cv) },
        'a mid-body `last if` translates without a GAP die');
    my @nodes = SoN::FromOptree->translate($cv)->nodes->@*;
    ok((grep { $_->operation eq 'Loop' } @nodes), 'has a Loop node');
    ok((grep { $_->operation eq 'If' } @nodes),
        'the mid-body break lowered to a real If split');
};

subtest 'a `next if` inside a loop body now lowers (guard on the remainder)' => sub {
    # `next if C` at position P is `if (!C) { REST-OF-BODY }`: the taken arm skips
    # the rest of the body this pass, the other arm runs it, and merge() Phis the
    # accumulator into the back-edge. No loop-control edge is needed. Was a GAP;
    # now lowers to a Loop + If + a merge Region.
    my $cv = do {
        SoN::OptSuppress::suppress_peep();
        my $c = eval 'sub { my $s = 0; for my $i (1..3) { next if $i == 2; $s = $s + $i } $s }';
        SoN::OptSuppress::restore_peep();
        $c;
    };
    ok(lives { SoN::FromOptree->translate($cv) },
        'a `next if` in a loop body translates without a GAP die');
    my @nodes = SoN::FromOptree->translate($cv)->nodes->@*;
    ok((grep { $_->operation eq 'Loop' } @nodes), 'has a Loop node');
    ok((grep { $_->operation eq 'If' } @nodes),
        'the `next if` lowered to a real If split');
};

subtest 'an UNCONDITIONAL bare last inside a loop body still refuses loudly' => sub {
    # Only the CONDITIONAL `last if C` / `next if C` (an `and(other->last/next)`)
    # lowers. A bare unconditional `last`/`next` reached directly is not a guard
    # -- it must still GAP loudly, not miscompile.
    like(translate_dies(
        'sub { my $i = 0; my $s = 0; while (1) { $s = $s + $i; last; $i = $i + 1 } $s }'),
        qr/GAP.*loop control \(last\)/i, 'a bare unconditional `last` dies with a GAP message');
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

# THE FOREACH MODIFIER GAP IS NOW A FEATURE (zhi 019f5a27 closed). It refused
# because _walk_loop_body mistook the guard for the loop condition, dropped its
# If, and fired the guarded statement every iteration -- `$s = $s + $i unless
# $i == 2` over 1..3 gave 106 where perl gives 104. The guard now splits into a
# real If, so the assertion moves from "it refuses" to "it computes the right
# thing": the accumulator MUST merge through a Phi whose arms are the updated
# and the unchanged value. That Phi is precisely what was missing when the
# answer was 106.
subtest 'a postfix modifier in a FOREACH body lowers to a guarded merge' => sub {
    for my $src (
        'sub { my $s = 100; for my $i (1..3) { $s = $s + $i unless $i == 2; } $s }',
        'sub { my $s = 100; for my $i (1..3) { $s = $s + $i if $i != 2; } $s }',
    ) {
        my $g = graph_of($src);
        my @if = grep { $_->operation eq 'If' } $g->nodes->@*;
        is(scalar(@if), 1, 'the guard builds exactly one If');

        # The accumulator's merge Phi: one arm is the Add, the other is the
        # value that skipped it. Without this Phi the add is unconditional --
        # the 106 shape.
        my ($add) = grep { $_->operation eq 'Add' && $_->stamp && $_->stamp->type eq 'Int'
                           && grep { $_->operation eq 'Phi' } $_->inputs->@* } $g->nodes->@*;
        ok($add, 'the guarded add exists') or next;
        my $merged = grep {
            $_->operation eq 'Phi'
                && grep { defined $_ && $_->id eq $add->id } $_->inputs->@*
        } $g->nodes->@*;
        ok($merged, 'the guarded add flows through a merge Phi -- it is conditional');
    }
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

    # Exactly one node carries control_in pointed at a Loop, and it is the
    # header condition (NumGt(phi, 0)) -- not the body decoy (NumGt(phi, -1)).
    my @wired = grep {
        $_->can('control_in') && defined $_->control_in
            && $_->control_in->operation eq 'Loop'
    } $graph->nodes->@*;
    is(scalar @wired, 1, 'exactly one condition is control-wired to the Loop');
    is($wired[0] && $wired[0]->control_in && $wired[0]->control_in->operation, 'Loop',
        'the wired condition points at the Loop node');
    ok($wired[0] && $ICMP_OP{ $wired[0]->operation },
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

    my @wired = grep {
        $_->can('control_in') && defined $_->control_in
            && $_->control_in->operation eq 'Loop'
    } $graph->nodes->@*;
    is(scalar @wired, 1, 'exactly one condition is control-wired to the Loop');
    ok($wired[0] && $ICMP_OP{ $wired[0]->operation },
        'the wired node is a synthesized comparison, not the bare Phi');
    is($wired[0] && $wired[0]->operation, 'NumNe',
        'the synthesized truthiness test is NumNe(cond, 0)');
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

subtest 'an implicit $_ foreach gets a truthful GAP message' => sub {
    # Was: refused by ACCIDENT with a misleading "non-constant integer bounds"
    # message (the iterator gv rides the mark stack and trips the count check).
    #
    # The message used to say "non-lexical", lumping implicit $_ together with
    # a PACKAGE-variable iterator. Those are no longer the same case: a package
    # iterator is keyed by `stash::$name` and lowers, while implicit $_ has no
    # name on the stack to key at all. The refusal now names only what is
    # genuinely unbuilt.
    like(translate_dies(
        'sub { my $s = 0; for (1..3) { $s = $s + 1 } $s }'),
        qr/GAP.*implicit \$_/i, 'implicit $_ foreach names the real gap');
};

# THE PACKAGE FORM IS NOT REFUSED, which is the other half of the distinction
# above -- without this, narrowing the message could hide a regression that
# re-refused it.
subtest 'a package-variable foreach iterator is not refused' => sub {
    # `dies {}` returns undef when nothing died -- not the empty string. The
    # iterator is package-QUALIFIED because this file runs under v5.42 (hence
    # strict), and a bare `$t` would fail to compile inside the eval rather
    # than exercise the translator.
    is(translate_dies(
        'sub { my $s = 0; for $main::t (1..3) { $s = $s + 1 } $s }'),
        undef, 'foreach $t (...) lowers');
};

done_testing();
