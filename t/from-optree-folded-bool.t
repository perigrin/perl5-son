# ABOUTME: Tests SoN::FromOptree fidelity for constant-folded boolean comparisons.
# ABOUTME: 1 < 2 folds to PL_sv_yes; it must emit a Boolean Constant, not a string.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# Perl constant-folds 1 < 2 to the shared boolean SV PL_sv_yes (and 2 < 1 to
# PL_sv_no). At the const op these surface as a B::SPECIAL resolved through the
# pad (idx 2 = yes, idx 3 = no). B::SoN previously classified them as a string
# Constant with stamp Unknown, losing is_bool and a lowerable representation.

sub const_node ($coderef) {
    my $graph = SoN::FromOptree->translate($coderef);
    my @hits  = grep { $_->operation eq 'Constant' } $graph->nodes->@*;
    return @hits ? $hits[0] : undef;
}

subtest 'true comparison folds to a Boolean Constant' => sub {
    my $c = const_node(sub { 1 < 2 });
    ok(defined $c, 'has a Constant node');
    ok(defined $c->stamp, 'Constant carries a stamp');
    is($c->stamp->type, 'Boolean', 'folded (1<2) is stamped Boolean');
    ok($c->value, 'true boolean has a truthy value');
};

subtest 'false comparison folds to a Boolean Constant' => sub {
    my $c = const_node(sub { 2 < 1 });
    ok(defined $c, 'has a Constant node');
    ok(defined $c->stamp, 'Constant carries a stamp');
    is($c->stamp->type, 'Boolean', 'folded (2<1) is stamped Boolean');
    ok(!$c->value, 'false boolean has a falsy value');
};

done_testing();
