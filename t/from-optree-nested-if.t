# ABOUTME: Tests cond_expr (if/else, ternary) translation: arm walks stop at the
# ABOUTME: join op, void statements merge pad effects, and nesting recurses.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# An if/else statement is a VOID cond_expr whose effect is the pad rebinds its
# arms make; the merge is TernaryExpr(cond, true_binding, false_binding) per
# changed slot -- the same strategy the statement-modifier and/or path proved.
# Arms converge at the JOIN op (the first op the two arms' op_next chains
# share; cond_expr's own op_next is the FALSE arm, not the continuation), so
# the walk must stop there instead of consuming the rest of the sub. A nested
# cond_expr inside an arm recurses -- previously it stopped the arm walk as
# 'unhandled', degrading the arm value to the inner CONDITION and silently
# dropping the inner assignments (corpus D7/D9).

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub nodes_of ($g, $want_op) {
    return grep { $_->operation eq $want_op } $g->nodes->@*;
}

sub return_value ($g) {
    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    return $ret->inputs->[0];
}

subtest 'nested if/else merges recursively (corpus D7 shape)' => sub {
    my $g = graph_of(
        'sub { my $n = 5; my $x; if ($n > 0) { if ($n > 3) { $x = 3 } else { $x = 1 } } else { $x = 0 } $x }');
    my $rv = return_value($g);
    is($rv->operation, 'TernaryExpr', 'the final $x read is the outer merge');
    my ($cond, $true, $false) = $rv->inputs->@*;
    is($cond->operation, 'NumGt', 'outer condition is $n > 0');
    is($false->value, 0, 'outer false arm is the else assignment (0)');
    is($true->operation, 'TernaryExpr',
        'outer true arm is the INNER MERGE, not the inner condition');
    my ($icond, $itrue, $ifalse) = $true->inputs->@*;
    is($icond->operation, 'NumGt', 'inner condition is $n > 3');
    is($itrue->value,  3, 'inner true arm is 3');
    is($ifalse->value, 1, 'inner false arm is 1');

    # The arms determine the merge's type (the condition does not) -- the
    # backend requires an explicit repr on a ternary consumed as an arm.
    ok(defined $true->stamp, 'inner merge carries a stamp');
    is($true->stamp->type, 'Int', 'inner merge stamp is the arm join (Int)');
    ok(defined $rv->stamp, 'outer merge carries a stamp');
    is($rv->stamp->type, 'Int', 'outer merge stamp is the arm join (Int)');
};

subtest 'statements after an if/else are not consumed by the arm walk' => sub {
    my $g = graph_of(
        'sub { my $n = 5; my $x; if ($n > 0) { $x = 1 } else { $x = 2 } my $y = $x + 10; $y }');
    my $rv = return_value($g);
    is($rv->operation, 'Add', 'the trailing statement survives ($x + 10)');
    is($rv->inputs->[0]->operation, 'TernaryExpr', 'Add reads the if/else merge');
    is($rv->inputs->[1]->value, 10, 'Add reads the literal 10');
};

subtest 'flat if/else still merges (corpus D1 shape)' => sub {
    my $g = graph_of(
        'sub { my $n = 5; my $x; if ($n > 0) { $x = 1 } else { $x = 2 } $x }');
    my $rv = return_value($g);
    is($rv->operation, 'TernaryExpr', 'final $x read is the merge');
    my ($cond, $true, $false) = $rv->inputs->@*;
    is($true->value,  1, 'true arm is 1');
    is($false->value, 2, 'false arm is 2');
};

subtest 'rvalue nested ternary recurses (filed 019f1bff)' => sub {
    my $g = graph_of(
        'sub { my $a = 1; my $b = 0; $a ? ($b ? 1 : 2) : 3 }');
    my $rv = return_value($g);
    is($rv->operation, 'TernaryExpr', 'outer ternary');
    my ($cond, $true, $false) = $rv->inputs->@*;
    is($false->value, 3, 'outer false arm is 3');
    is($true->operation, 'TernaryExpr', 'true arm is the nested ternary');
    is($true->inputs->[1]->value, 1, 'nested true arm is 1');
    is($true->inputs->[2]->value, 2, 'nested false arm is 2');
};

subtest 'one-armed if merges against the prior binding' => sub {
    my $g = graph_of(
        'sub { my $n = 5; my $x = 9; if ($n > 0) { $x = 1 } $x }');
    my $rv = return_value($g);
    is($rv->operation, 'TernaryExpr', 'final $x read is a merge');
    my ($cond, $true, $false) = $rv->inputs->@*;
    is($true->value,  1, 'true arm is the assignment');
    is($false->value, 9, 'false arm is the prior binding');
};

subtest 'return inside an if/else arm refuses loudly' => sub {
    # Pre-existing hole surfaced by review discipline: the arm walk ran with
    # no exit accumulator, so `return 9` in an arm was silently dropped and
    # the function returned the merge instead (wrong value, no error). The
    # one-sided-exit merge needs real control threading; refuse until then.
    SoN::OptSuppress::suppress_peep();
    my $cv = eval
        'sub { my $n = 5; my $x = 0; if ($n > 0) { return 9 } else { $x = 1 } $x }';
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    like(dies { SoN::FromOptree->translate($cv) }, qr/GAP/,
        'function exit inside a cond_expr arm dies with a GAP message');
};

subtest 'unhandled op inside an arm refuses loudly (no silent truncation)' => sub {
    # An arm stopping anywhere other than the join marked its stop op
    # visited, so the MAIN walk terminated there too: everything after the
    # if/else (including the real return value) was silently dropped and the
    # function returned stack garbage (e.g. Int:0 vs perl Int:1/Int:100).
    SoN::OptSuppress::suppress_peep();
    my $mod = eval 'sub { my $c = 0; my $d = 1; my $x = 0; if ($c) { $x = 5 if $d } else { $x = 1 } $x }';
    my $vp  = eval 'sub { my $c = 1; my $x = 0; if ($c) { print "hi\n" if $x < 10 } else { $x = 1 } $x }';
    my $die = eval 'sub { my $c = 1; my $x = 0; if ($c) { die "boom" } else { $x = 1 } $x }';
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    # A PURE pad-rebind statement modifier inside an arm now LOWERS: the arm
    # recurses into the same void-context and/or pad-rebind merge the main walk
    # uses, so the modifier's guarded store becomes TernaryExpr(guard, body,
    # base) and the arm reaches the join. It previously GAPped as an
    # "untranslatable op inside an arm" (chalk T9 / perl5-son stmt-modifier-in-arm).
    ok(lives { SoN::FromOptree->translate($mod) },
        'a pure-rebind statement modifier inside an arm now lowers, no longer a GAP');
    # A modifier body with a statement EFFECT that rebinds no scope slot (a void
    # print) is not a simple rebind, so the value-only merge could not carry it
    # and it GAPped rather than drop the unpinned Print. It now LOWERS: the
    # handler builds the same If/Proj/Region the main walk's &&/|| handler
    # builds, so the Print is pinned on its own Proj and a Region merges the
    # arms. Verified behaviourally on BOTH polarities before this assertion was
    # changed -- c=1 gives "hi\nx=0\n", c=0 gives "x=1\n", both matching perl.
    #
    # A void CALL in the same position still GAPs: a Call is both a value and an
    # effect, and routing it through this build emitted it on BOTH paths
    # ("helped" printed twice where perl printed it once). That refusal is
    # asserted in t/from-optree-void-direct-call.t.
    ok(lives { SoN::FromOptree->translate($vp) },
        'a void-PRINT statement modifier inside an arm now lowers, no longer a GAP');
    # A die inside an arm now LOWERS (via an Unwind CFG node -> exit+unreachable
    # in the backend); it no longer GAPs. The taken-die aborts, the not-taken
    # arm's value is returned. This test previously asserted the GAP that the
    # die-in-arm feature (chalk T2 / perl5-son die-in-arm commit) removed.
    ok(lives { SoN::FromOptree->translate($die) },
        'a die inside an arm now lowers (Unwind), no longer a GAP');
};

subtest 'value-context ternary merges arm pad rebinds' => sub {
    # `my $y = $c ? ($x = 1) : 2; $x + $y` -- the assignment inside the arm
    # must rebind $x conditionally, exactly as the void form does; it was
    # discarded with the arm snapshot (lli Int:1 vs perl Int:2).
    my $g = graph_of(
        'sub { my $c = 1; my $x = 0; my $y = $c ? ($x = 1) : 2; $x + $y }');
    my ($add) = nodes_of($g, 'Add');
    ok(defined $add, 'has the final Add');
    is($add->inputs->[0]->operation, 'TernaryExpr',
        '$x reads a conditional merge, not the pre-binding');
};

subtest 'list-context ternary refuses loudly' => sub {
    # `my @a = $c ? (1,2) : (3,4)` -- the scalar value path pops exactly one
    # value per arm and silently mistranslated the list (Int:0 vs Int:2).
    SoN::OptSuppress::suppress_peep();
    my $cv = eval 'sub { my $c = 1; my @a = $c ? (1, 2) : (3, 4); $a[1] }';
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    like(dies { SoN::FromOptree->translate($cv) }, qr/GAP.*list/i,
        'list-context cond_expr dies with a GAP message');
};

done_testing();
