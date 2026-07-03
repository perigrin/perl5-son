# ABOUTME: Tests SoN::FromOptree lowers void-context statement modifiers (`$x = 1 if $c`)
# ABOUTME: as TernaryExpr rebinds of the arm's pad effects, not operand-returning And/Or.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# `EXPR if COND` compiles to `and(cond, arm)` in VOID context -- the same op
# as value-context `$a && $b` (sK). The arm's result value is discarded; what
# matters is the pad rebinding it performs, which must only take effect when
# the condition holds. The producer merges each binding the arm changed as
# TernaryExpr(cond, arm_value, base_value) -- arm on the false side for
# `unless` (or) -- reusing the value-node strategy the cond_expr handler
# proved (backend expands the merge to br+phi). No And/Or node is emitted.

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
    return unless $ret;
    return $ret->inputs->[1];
}

subtest 'postfix if merges the assignment as TernaryExpr(cond, arm, base)' => sub {
    my $g = graph_of('sub { my $n = 5; my $x = 0; $x = 1 if $n > 0; $x }');
    my ($tern) = nodes_of($g, 'TernaryExpr');
    ok(defined $tern, 'has a TernaryExpr node');
    my ($cond, $true, $false) = $tern->inputs->@*;
    is($cond->operation, 'NumGt', 'condition is the guard comparison');
    is($true->value,  1, 'true arm is the assigned value (arm ran)');
    is($false->value, 0, 'false arm is the prior binding (arm skipped)');
    is([nodes_of($g, 'And')], [], 'no And node (void context, not a value)');
    my $rv = return_value($g);
    is($rv->id, $tern->id, 'the final $x read returns the merged value');
};

subtest 'postfix unless puts the arm on the false side' => sub {
    my $g = graph_of('sub { my $n = 5; my $x = 0; $x = 1 unless $n > 0; $x }');
    my ($tern) = nodes_of($g, 'TernaryExpr');
    ok(defined $tern, 'has a TernaryExpr node');
    my ($cond, $true, $false) = $tern->inputs->@*;
    is($cond->operation, 'NumGt', 'condition is the guard comparison');
    is($true->value,  0, 'true arm keeps the prior binding (guard held)');
    is($false->value, 1, 'false arm is the assigned value (arm ran)');
    is([nodes_of($g, 'Or')], [], 'no Or node (void context, not a value)');
};

subtest 'chained modifiers: the second reads the first\'s merged value' => sub {
    my $g = graph_of(
        'sub { my $n = 5; my $x = 0; $x = 1 if $n > 0; my $y = 0; $y = $x + 1 if $n > 1; $y }');
    my @terns = nodes_of($g, 'TernaryExpr');
    is(scalar @terns, 2, 'two TernaryExpr merges');
    my ($add) = nodes_of($g, 'Add');
    ok(defined $add, 'the second arm computes $x + 1');
    my @add_in_ops = map { $_->operation } $add->inputs->@*;
    ok((grep { $_ eq 'TernaryExpr' } @add_in_ops),
        'the Add consumes the first merge (not a stale binding)');
};

subtest 'read-modify arm: $x += 1 if $cond' => sub {
    my $g = graph_of('sub { my $n = 5; my $x = 3; $x += 1 if $n > 0; $x }');
    my ($tern) = nodes_of($g, 'TernaryExpr');
    ok(defined $tern, 'has a TernaryExpr node');
    my ($cond, $true, $false) = $tern->inputs->@*;
    is($true->operation, 'Add', 'true arm is the read-modify Add');
    is($false->value, 3, 'false arm is the prior binding');
};

subtest 'value context still emits And when assigned' => sub {
    # `my $c = $a && $b` is scalar (sK) context: the operand-returning And
    # contract from logical.md L1 applies, and the binding of $c must be the
    # And node itself -- the arm walk must stop at the convergence op and NOT
    # consume the rest of the sub.
    my $g = graph_of('sub { my $a = 3; my $b = 7; my $c = $a && $b; $c }');
    my ($and) = nodes_of($g, 'And');
    ok(defined $and, 'has an And node (scalar context)');
    is([nodes_of($g, 'TernaryExpr')], [], 'no TernaryExpr (not a void modifier)');
    my $rv = return_value($g);
    is($rv->id, $and->id, 'the final $c read returns the And');
};

subtest 'postfix while refuses loudly (loop lowering is separate work)' => sub {
    # `$s += $n-- while $n > 0` is the same void `and` op but its arm loops
    # back (unstack->next re-enters the condition). Until the loop machinery
    # handles it, the producer must DIE (honest GAP), never emit a straight-
    # line merge that silently computes one iteration.
    like(
        dies {
            graph_of('sub { my $n = 3; my $s = 0; $s += $n-- while $n > 0; $s }')
        },
        qr/GAP/,
        'non-converging void arm dies with a GAP message'
    );
};

done_testing();
