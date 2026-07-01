# ABOUTME: Tests SoN::FromOptree lowers && and || to And/Or operand-returning nodes (RC2).
# ABOUTME: $a && $b -> And($a, $b); $a || $b -> Or($a, $b), matching the corpus L1/L2 contract.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Per corpus/mdtest/logical.md L1/L2, `$a && $b` lowers to a single operand-
# returning node `And(%a, %b)` and `$a || $b` to `Or(%a, %b)` -- NOT an
# If/Region/Phi in the producer. The Chalk LLVM backend expands And/Or into the
# short-circuit br+phi at lowering time (the same division of labour DefinedOr
# uses for `//`). The two inputs are the LEFT operand ($a, already on the stack
# when the branch op fires) and the RIGHT operand ($b, reached via op->other).

sub node_of ($code, $want_op) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    my $g = SoN::FromOptree->translate($cv);
    my ($node) = grep { $_->operation eq $want_op } $g->nodes->@*;
    return $node;
}

# Distinct constants so the operands can't pass by accident.
subtest '&& lowers to And($a, $b) with both operands' => sub {
    my $node = node_of('sub { my $a = 3; my $b = 7; $a && $b }', 'And');
    ok(defined $node, 'has an And node');
    my @vals = map { $_->can('value') ? ($_->value // '-') : '-' } $node->inputs->@*;
    is(\@vals, [3, 7], "And inputs are [lhs=3, rhs=7] (got: @vals)");
    ok(!(grep { $_->operation eq 'Phi' } SoN::FromOptree->translate(eval 'sub { my $a = 3; my $b = 7; $a && $b }')->nodes->@*),
        'no Phi in the producer graph (backend synthesizes the merge)');
};

subtest '|| lowers to Or($a, $b) with both operands' => sub {
    my $node = node_of('sub { my $a = 3; my $b = 7; $a || $b }', 'Or');
    ok(defined $node, 'has an Or node');
    my @vals = map { $_->can('value') ? ($_->value // '-') : '-' } $node->inputs->@*;
    is(\@vals, [3, 7], "Or inputs are [lhs=3, rhs=7] (got: @vals)");
};

done_testing();
