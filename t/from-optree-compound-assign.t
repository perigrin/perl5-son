# ABOUTME: Tests SoN::FromOptree numeric compound assignment (+= -= *= etc.).
# ABOUTME: Canonical ops: a binop over an lvalue pad read rebinds the variable.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

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

done_testing();
