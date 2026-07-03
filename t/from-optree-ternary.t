# ABOUTME: Tests SoN::FromOptree ternary (cond_expr) arm ordering (RC4 correctness).
# ABOUTME: TernaryExpr(cond, TRUE_arm, FALSE_arm) -- inputs[1] is the true value.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# `$cond ? A : B` lowers to TernaryExpr(cond, A, B) where inputs[1] is the
# value taken when cond is TRUE and inputs[2] when FALSE (the backend reads
# inputs[1] as the true branch). In Perl's cond_expr optree, op->other is the
# true arm and op->next is the false arm -- do NOT confuse them.

sub ternary_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    my $g = SoN::FromOptree->translate($cv);
    my ($t) = grep { $_->operation eq 'TernaryExpr' } $g->nodes->@*;
    return $t;
}

subtest 'ternary arm order: inputs[1]=true, inputs[2]=false' => sub {
    my $t = ternary_of('sub { my $n = 5; $n > 0 ? 1 : 2 }');
    ok(defined $t, 'has a TernaryExpr');
    my ($cond, $true_arm, $false_arm) = $t->inputs->@*;
    is($true_arm->value,  1, 'inputs[1] is the TRUE arm (1)');
    is($false_arm->value, 2, 'inputs[2] is the FALSE arm (2)');
};

subtest 'distinct values confirm the order is not accidental' => sub {
    my $t = ternary_of('sub { my $n = 5; $n > 0 ? 10 : 20 }');
    my (undef, $true_arm, $false_arm) = $t->inputs->@*;
    is($true_arm->value,  10, 'true arm is 10');
    is($false_arm->value, 20, 'false arm is 20');
};

# Regression guard: a dor arm containing a return (EXPR // return X --
# ubiquitous in real lib/) must still translate without leaking the return's
# pushmark and underflowing the mark stack. A cond_expr arm containing a
# return, by contrast, now refuses LOUDLY: the old walk stepped through the
# exit and silently dropped it (the function returned the merge instead), and
# a one-sided arm exit needs real control threading to lower. The GAP die is
# also mark-balanced -- the point of the original underflow guard.
sub translate_result ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    my $g = eval { SoN::FromOptree->translate($cv) };
    return ($g, $@);
}

subtest 'return inside a dor or ternary arm' => sub {
    my ($dor_g, $dor_err) = translate_result(
        'sub { my %M = (a=>1); my $x = $M{b} // return "f"; $x }');
    ok(defined $dor_g, 'EXPR // return X translates (no mark underflow)')
        or diag($dor_err);
    my ($tern_g, $tern_err) = translate_result(
        'sub { my $n = 5; $n > 0 ? (return 1) : 2 }');
    ok(!defined $tern_g, 'a ternary arm containing return refuses');
    like($tern_err, qr/GAP/, 'and the refusal is a GAP die, not a crash');
};

done_testing();
