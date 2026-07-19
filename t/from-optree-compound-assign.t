# ABOUTME: Tests SoN::FromOptree numeric compound assignment (+= -= *= etc.).
# ABOUTME: Canonical ops: a binop over an lvalue pad read rebinds the variable.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;
use SoN::FromOptree::EffectMeta;

# A compound assignment INTO A CLASS FIELD ($n += 1 in a method) is a memory
# store, not an SSA rebind: the field lives in the object struct, so the new
# value must be written back via an Assign(FieldAccess-lvalue). Unlike a pad
# `my $x += 1` (which rebinds the SSA value and needs no store), a bare-field
# `$n += 1` optree targets a temp (padsv add[t] leavesub) and DROPS the write
# unless the field-slot store is emitted -- the same store the `$n = $n + 1`
# TARGMY form emits.
class FieldCounter {
    field $n :param = 0;
    method inc_compound { $n += 1 }
    method inc_assign   { $n = $n + 1 }
}

# `$x += 2` is a read-modify-write: the arithmetic op reads $x's current value,
# computes the result, and rebinds $x so a later read sees it. The distinguishing
# signal is OPf_MOD on the op's first (pad) operand; a plain `$y = $x + 2` does
# not rebind $x.

sub canonical_graph ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub return_value ($graph) {
    my ($ret) = grep { $_->operation eq 'Return' } $graph->nodes->@*;
    return $ret->inputs->[-1];
}

subtest 'numeric += rebinds to the computed value' => sub {
    my $g  = canonical_graph('sub { my $x = 1; $x += 2; $x }');
    my $rv = return_value($g);
    is($rv->operation, 'Add', 'return value is the Add result (read-modify-write)');
    # The lvalue read resolved to the bound value, so the op carries a stamp.
    ok(defined $rv->stamp, 'compound-assign result carries a stamp (Int+Int)');
    is($rv->stamp->type, 'Int', 'result stamp is Int');
};

subtest 'compound assign reads the bound value (not a bare PadAccess)' => sub {
    my $g  = canonical_graph('sub { my $x = 1; $x += 2; $x }');
    my $rv = return_value($g);
    is($rv->inputs->[0]->operation, 'Constant',
        'the += read resolved to the bound Constant(1), not an unstamped PadAccess');
};

subtest 'chained compound assigns each rebind' => sub {
    my $g  = canonical_graph('sub { my $x = 5; $x += 3; $x -= 1; $x }');
    my $rv = return_value($g);
    is($rv->operation, 'Subtract', 'final value is the last op (Subtract)');
};

subtest 'plain $y = $x + 2 does NOT rebind $x' => sub {
    # Regression guard: a non-modify read must not trigger the compound path.
    my $g = canonical_graph('sub { my $x = 1; my $y = $x + 2; $x }');
    my $rv = return_value($g);
    is($rv->operation, 'Constant', '$x is unchanged');
    is($rv->value, 1, '$x is still 1 (the y assignment did not rebind it)');
};

subtest 'compound assign into a class field emits an Assign store (B4)' => sub {
    SoN::OptSuppress::suppress_peep();
    my $g = SoN::FromOptree->translate(\&{'FieldCounter::inc_compound'});
    SoN::OptSuppress::restore_peep();
    my ($assign) = grep { $_->operation eq 'Assign' } $g->nodes->@*;
    ok(defined $assign, '$n += 1 emits a field-store Assign (not a dropped temp)')
        or return;
    ok(SoN::FromOptree::EffectMeta::is_stmt_effect($assign),
        'the field store is a threaded statement effect');
    # TODO(019f7b38-2317): Chalk::IR::Node::Assign inherits BinOp's generic
    # left/right (inputs[0]/inputs[1]), but a memory-SSA field store is built
    # with 3 inputs [control, lvalue, value] (control leads). The old
    # SoN::IR::Node::Assign overrode left/right to inputs[-2]/inputs[-1] to
    # handle exactly this leading-control-token shape; Chalk::IR::Node::Assign
    # has no such override. Blocked on 019f7b38-2317 (same design fork as the
    # Graph reachability issue -- both are flattened-wire seams).
    todo 'blocked on 019f7b38-2317: Chalk::IR::Node::Assign left/right has no leading-control override' => sub {
        is($assign->left->operation, 'FieldAccess',
            'the store target is the field lvalue (FieldAccess)');
        is($assign->right->operation, 'Add',
            'the stored value is the += result (Add)');
    };
};

subtest 'compound += store matches the = TARGMY store shape (B4 parity)' => sub {
    SoN::OptSuppress::suppress_peep();
    my $g_pe = SoN::FromOptree->translate(\&{'FieldCounter::inc_compound'});
    my $g_eq = SoN::FromOptree->translate(\&{'FieldCounter::inc_assign'});
    SoN::OptSuppress::restore_peep();
    my ($a_pe) = grep { $_->operation eq 'Assign' } $g_pe->nodes->@*;
    my ($a_eq) = grep { $_->operation eq 'Assign' } $g_eq->nodes->@*;
    ok(defined $a_pe && defined $a_eq, 'both forms emit an Assign') or return;
    is($a_pe->left->operation, $a_eq->left->operation,
        '+= and = store to the same lvalue kind (FieldAccess)');
};

done_testing();
