# ABOUTME: Tests SoN::FromOptree stamping of computed nodes (Add, comparisons, etc).
# ABOUTME: Result stamps are derived from input stamps via the SoN::IR::Stamp lattice.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# B::SoN stamps leaf Constants, but a computed node (Add of two ints, a
# comparison, a concat) was left unstamped, so the value reached Chalk's
# backend with no representation and GAPed. When every input carries a stamp,
# the result node's stamp is derivable: arithmetic joins its inputs, division
# is Num, comparisons are Boolean, concat is Str, length is Int.

sub computed ($coderef, $op) {
    my $graph = SoN::FromOptree->translate($coderef);
    my @hits  = grep { $_->operation eq $op } $graph->nodes->@*;
    return @hits ? $hits[0] : undef;
}

subtest 'Add of two Int constants is stamped Int' => sub {
    my $add = computed(sub { my $x = 1; my $y = 2; $x + $y }, 'Add');
    ok(defined $add, 'has an Add node');
    ok(defined $add->stamp, 'Add carries a stamp');
    is($add->stamp->type, 'Int', 'Add(Int, Int) result stamp is Int');
};

subtest 'Multiply of Int and Num is stamped Num' => sub {
    my $mul = computed(sub { my $x = 2; my $y = 1.5; $x * $y }, 'Multiply');
    ok(defined $mul, 'has a Multiply node');
    ok(defined $mul->stamp, 'Multiply carries a stamp');
    is($mul->stamp->type, 'Num', 'Multiply(Int, Num) result stamp is Num (lattice join)');
};

subtest 'Divide is always Num' => sub {
    my $div = computed(sub { my $x = 6; my $y = 2; $x / $y }, 'Divide');
    ok(defined $div, 'has a Divide node');
    ok(defined $div->stamp, 'Divide carries a stamp');
    is($div->stamp->type, 'Num', 'Divide result stamp is Num (Perl / is float)');
};

subtest 'numeric comparison is stamped Boolean' => sub {
    my $cmp = computed(sub { my $x = 3; my $y = 5; $x < $y }, 'NumLt');
    ok(defined $cmp, 'has a NumLt node');
    ok(defined $cmp->stamp, 'NumLt carries a stamp');
    is($cmp->stamp->type, 'Boolean', 'comparison result stamp is Boolean');
};

subtest 'concat is stamped Str' => sub {
    my $cat = computed(sub { my $a = 'x'; my $b = 'y'; $a . $b }, 'Concat');
    ok(defined $cat, 'has a Concat node');
    ok(defined $cat->stamp, 'Concat carries a stamp');
    is($cat->stamp->type, 'Str', 'Concat result stamp is Str');
};

subtest 'Not is stamped Boolean' => sub {
    # Perl ! always yields a genuine primitive boolean (is_bool(!5) is true),
    # so Not is a fixed-result rule: Boolean regardless of input stamps.
    my $not = computed(sub { my $a = 5; !$a }, 'Not');
    ok(defined $not, 'has a Not node');
    ok(defined $not->stamp, 'Not carries a stamp');
    is($not->stamp->type, 'Boolean', 'Not result stamp is Boolean');
};

subtest 'Not of an unstamped operand is still Boolean' => sub {
    my $not = computed(sub ($x) { !$x }, 'Not');
    ok(defined $not, 'has a Not node');
    ok(defined $not->stamp, 'Not carries a stamp even over unstamped input');
    is($not->stamp->type, 'Boolean', 'fixed-result rule ignores input stamps');
};

subtest 'unstamped inputs leave the result unstamped (honest GAP)' => sub {
    # Signature params have no type annotation, so their PadAccess carries no
    # stamp; the Add result must NOT be invented -- it stays unstamped so the
    # backend reports an honest GAP rather than a guessed representation.
    my $add = computed(sub ($x, $y) { $x + $y }, 'Add');
    ok(defined $add, 'has an Add node');
    ok(!defined $add->stamp, 'Add over unstamped inputs stays unstamped');
};

done_testing();
