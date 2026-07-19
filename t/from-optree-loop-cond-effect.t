# ABOUTME: A while whose CONDITION mutates a pad slot ($i-- > 0) runs the condition N+1 times;
# ABOUTME: the failing (N+1)th eval's side effect must land -- post-loop reads the AT-EXIT value, not the header Phi.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Perl evaluates a while CONDITION N+1 times: the final, FAILING evaluation still
# applies its side effects. `my $i=3; while ($i-- > 0) {} $i` decrements $i on the
# failing pass too, so the post-loop $i is -1, not 0 (the header Phi's exit value).
# The two-phase loop translation models a condition mutation as the header Phi's
# back-edge; the post-loop read must therefore observe the back-edge (the value
# after the failing pass), NOT the Phi itself (its value on the pass that failed).
# A BODY mutation is different -- the body does not run on the exit pass, so a
# body-carried slot still reads the header Phi post-loop.

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

subtest 'block while with a condition-only mutation reads the AT-EXIT value post-loop' => sub {
    # my $i=3; while ($i-- > 0) {} $i  -> Int:-1
    my $g = graph_of('sub { my $i = 3; while ($i-- > 0) {} $i }');

    my ($loop) = nodes_of($g, 'Loop');
    ok(defined $loop, 'has a Loop node');
    is([nodes_of($g, 'If')], [], 'no If -- the Loop IS the header');

    my @phis = nodes_of($g, 'Phi');
    is(scalar @phis, 1, 'one header Phi for $i');
    my ($i_phi) = @phis;
    is($i_phi->inputs->[0]->value, 3, '$i Phi init is 3');
    is($i_phi->inputs->[1]->operation, 'Subtract', '$i Phi back-edge is the decrement');

    # The condition reads the Phi (the pre-decrement value on this pass).
    my ($cmp) = nodes_of($g, 'NumGt');
    ok(defined $cmp, 'has the loop condition NumGt');
    is($cmp && $cmp->inputs->[0]->id, $i_phi->id, 'condition compares the $i Phi');

    # THE FIX: the post-loop read of $i is the AT-EXIT decrement (the Phi back-edge
    # `Subtract($i_phi, 1)`, reading the header Phi's exit value), NOT the header
    # Phi itself. The backend lowers this back-edge in the loop header so it
    # dominates the exit.
    my ($ret) = nodes_of($g, 'Return');
    is($ret->inputs->[1]->operation, 'Subtract',
        'Return value is the condition decrement (AT-EXIT value), not the Phi');
    is($ret->inputs->[1]->id, $i_phi->inputs->[1]->id,
        'the post-loop read IS the Phi back-edge (the AT-EXIT decrement)');
    is($ret->inputs->[1]->inputs->[0]->id, $i_phi->id,
        'the AT-EXIT decrement reads the header Phi exit value');
};

subtest 'block while: a NON-mutating condition still reads the Phi post-loop' => sub {
    # my $n=3; my $s=0; while ($n > 0) { $s += $n; $n-- } $n  -> $n reads the Phi (0),
    # because $n is mutated in the BODY (not the condition): the body does not run on
    # the exit pass, so post-loop $n is the value that failed the condition.
    my $g = graph_of('sub { my $n = 3; my $s = 0; while ($n > 0) { $s += $n; $n-- } $n }');
    my @phis = nodes_of($g, 'Phi');
    my ($n_phi) = grep { ($_->inputs->[0]->value // '') == 3 } @phis;
    ok(defined $n_phi, 'found the $n Phi (init 3)');
    my ($ret) = nodes_of($g, 'Return');
    is($ret->inputs->[1]->id, $n_phi->id,
        'a body-mutated slot reads the header Phi post-loop (unchanged behavior)');
};

subtest 'postfix while with a condition-only mutation reads the AT-EXIT value' => sub {
    # my $n=3; my $t=0; $t=$t+$n while $n-- > 0; $t  -> Int:3, with $n condition-mutated.
    # The postfix first-walk must not leak a pre-evaluation into the Phi inits.
    my $g = graph_of('sub { my $n = 3; my $t = 0; $t = $t + $n while $n-- > 0; $t }');

    my @phis = nodes_of($g, 'Phi');
    my ($n_phi) = grep { ($_->inputs->[0]->value // '') == 3 } @phis;
    my ($t_phi) = grep { ($_->inputs->[0]->value // '') == 0 } @phis;
    ok(defined $n_phi, 'found the $n Phi with init 3 (no pre-eval leak into the init)');
    ok(defined $t_phi, 'found the $t Phi with init 0');
    is($n_phi->inputs->[1]->operation, 'Subtract', '$n back-edge is the condition decrement');

    # $t is body-mutated so the Return reads the $t Phi (the accumulator's exit value).
    my ($ret) = nodes_of($g, 'Return');
    is($ret->inputs->[1]->id, $t_phi->id, 'Return value is the $t Phi (accumulator)');
};

subtest 'block while with a non-empty body and a condition mutation' => sub {
    # Bilateral: the condition mutates $i AND the body mutates $s. Post-loop $i is
    # the back-edge (AT-EXIT), $s is the Phi (body did not run on the exit pass).
    my $g = graph_of('sub { my $i = 3; my $s = 0; while ($i-- > 0) { $s = $s + 1 } $i }');
    my @phis = nodes_of($g, 'Phi');
    my ($i_phi) = grep { ($_->inputs->[0]->value // '') == 3 } @phis;
    ok(defined $i_phi, 'found the $i Phi (init 3)');
    my ($ret) = nodes_of($g, 'Return');
    is($ret->inputs->[1]->operation, 'Subtract',
        'post-loop $i is the condition decrement (AT-EXIT), not the Phi');
    is($ret->inputs->[1]->id, $i_phi->inputs->[1]->id,
        'the post-loop read IS the Phi back-edge (the AT-EXIT decrement)');
    is($ret->inputs->[1]->inputs->[0]->id, $i_phi->id,
        'the AT-EXIT decrement reads the header Phi');
};

done_testing();
