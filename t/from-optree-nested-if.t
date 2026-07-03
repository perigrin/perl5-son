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
    return $ret->inputs->[1];
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

done_testing();
