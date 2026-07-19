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
    return $ret->inputs->[0];
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

subtest 'postfix while lowers as a real loop (D2-identical shape)' => sub {
    # `$s += $n-- while $n > 0` is the same void `and` op but its arm loops
    # back (unstack->next re-enters the condition head). Per the corpus,
    # postfix while is a pre-test loop with a graph byte-identical to the
    # block while: Loop header, one Phi per carried variable, condition on
    # the Phi, exit Region -- and NO And/TernaryExpr merge.
    my $g = graph_of('sub { my $n = 3; my $s = 0; $s += $n-- while $n > 0; $s }');

    my @loops = nodes_of($g, 'Loop');
    is(scalar @loops, 1, 'exactly one Loop node');
    is([nodes_of($g, 'And')], [], 'no And node');
    is([nodes_of($g, 'TernaryExpr')], [], 'no TernaryExpr merge');

    my @phis = grep { $_->region->id eq $loops[0]->id } nodes_of($g, 'Phi');
    is(scalar @phis, 2, 'two loop Phis ($s, $n)');
    my ($s_phi) = grep { $_->inputs->[1]->operation eq 'Add' } @phis;
    my ($n_phi) = grep { $_->inputs->[1]->operation eq 'Subtract' } @phis;
    ok(defined $s_phi, '$s Phi backedge is the sum');
    ok(defined $n_phi, '$n Phi backedge is the decrement');

    # The loop-mode condition reads the $n Phi, not the pre-loop constant.
    my ($cmp) = grep { $_->inputs->[0]->id eq $n_phi->id } nodes_of($g, 'NumGt');
    ok(defined $cmp, 'a NumGt condition consumes the $n Phi');

    my ($ret) = nodes_of($g, 'Return');
    is($ret->control_in->operation, 'Region', 'Return control is the exit Region');
    is($ret->inputs->[0]->id, $s_phi->id, 'Return value is the $s Phi');
};

subtest 'a postfix-while ships NO dead pre-evaluation orphans (zhi 019f29ed)' => sub {
    # The main-walk condition pass and arm walk build real nodes against the
    # pre-loop constants BEFORE back-edge detection re-walks against the Phis;
    # those orphans (a NumGt/Add/Subtract consuming a constant, not a Phi) used
    # to ship into the serialized graph. A dead orphan is an unconsumed data node
    # (cons == 0) that is not a control terminal (Return/Proj) and not a loop
    # condition (control_in pointed at a Loop). The loop's REAL condition is
    # unconsumed too but carries control_in -> Loop, so it is not an orphan.
    my $g = graph_of(
        'sub { my $n = 3; my $t = 0; $t = $t + $n, $n = $n - 1 while $n > 0; $t }');
    my %terminal = (Return => 1, Proj => 1, Start => 1, Loop => 1, Region => 1);
    my @orphans = grep {
        !$terminal{ $_->operation }
            && !( $_->can('control_in') && defined $_->control_in
                && $_->control_in->operation eq 'Loop' )
            && $_->consumers->@* == 0
    } $g->nodes->@*;
    is(scalar @orphans, 0, 'no dead pre-evaluation orphan nodes')
        or diag('orphans: ' . join(', ', map { $_->operation } @orphans));
};

done_testing();
