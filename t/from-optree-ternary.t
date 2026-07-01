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

# Regression guard: the ternary arm walk stops before a function exit only for
# cond_expr's own arms. Other branch idioms whose arm contains a return/die
# (EXPR // return X -- ubiquitous in real lib/) must still translate; a naive
# stop-before-exit leaks the return's pushmark and underflows the mark stack.
sub translates_ok ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return defined eval { SoN::FromOptree->translate($cv) };
}

subtest 'return inside a dor or ternary arm still translates' => sub {
    ok(translates_ok('sub { my %M = (a=>1); my $x = $M{b} // return "f"; $x }'),
        'EXPR // return X translates (no mark underflow)');
    ok(translates_ok('sub { my $n = 5; $n > 0 ? (return 1) : 2 }'),
        'a ternary arm containing return translates (no mark underflow)');
};

done_testing();
