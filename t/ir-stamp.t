# ABOUTME: Tests for SoN::IR::Stamp type lattice.
# ABOUTME: Verifies subtyping, meet/join operations per the formal Perl type paper.

use v5.42.0;
use Test2::V0;

use SoN::IR::Stamp;

subtest 'All lattice types representable' => sub {
    for my $type (qw(Unknown Scalar Str Num Int Boolean Undef Ref
                      ScalarRef ArrayRef HashRef CodeRef Object DualVar None)) {
        my $stamp = SoN::IR::Stamp->new(type => $type);
        is($stamp->type, $type, "$type stamp created");
    }
};

subtest 'Subtyping: Int < Num < Str < Scalar' => sub {
    my $int    = SoN::IR::Stamp->new(type => 'Int');
    my $num    = SoN::IR::Stamp->new(type => 'Num');
    my $str    = SoN::IR::Stamp->new(type => 'Str');
    my $scalar = SoN::IR::Stamp->new(type => 'Scalar');

    ok($int->is_subtype_of($num),    'Int < Num');
    ok($int->is_subtype_of($str),    'Int < Str');
    ok($int->is_subtype_of($scalar), 'Int < Scalar');
    ok($num->is_subtype_of($str),    'Num < Str');
    ok($num->is_subtype_of($scalar), 'Num < Scalar');
    ok($str->is_subtype_of($scalar), 'Str < Scalar');

    ok(!$num->is_subtype_of($int),    'Num is not < Int');
    ok(!$scalar->is_subtype_of($str), 'Scalar is not < Str');
};

subtest 'DualVar is in Scalar but NOT in Str or Num' => sub {
    my $dualvar = SoN::IR::Stamp->new(type => 'DualVar');
    my $scalar  = SoN::IR::Stamp->new(type => 'Scalar');
    my $str     = SoN::IR::Stamp->new(type => 'Str');
    my $num     = SoN::IR::Stamp->new(type => 'Num');

    ok($dualvar->is_subtype_of($scalar), 'DualVar < Scalar');
    ok(!$dualvar->is_subtype_of($str),   'DualVar is not < Str');
    ok(!$dualvar->is_subtype_of($num),   'DualVar is not < Num');
};

subtest 'Unknown is top, None is bottom' => sub {
    my $unknown = SoN::IR::Stamp->new(type => 'Unknown');
    my $none    = SoN::IR::Stamp->new(type => 'None');
    my $int     = SoN::IR::Stamp->new(type => 'Int');

    ok($int->is_subtype_of($unknown),  'Int < Unknown');
    ok($none->is_subtype_of($int),     'None < Int');
    ok($none->is_subtype_of($unknown), 'None < Unknown');
    ok(!$unknown->is_subtype_of($int), 'Unknown is not < Int');
};

subtest 'Meet (greatest lower bound)' => sub {
    my $int = SoN::IR::Stamp->new(type => 'Int');
    my $num = SoN::IR::Stamp->new(type => 'Num');
    my $str = SoN::IR::Stamp->new(type => 'Str');

    is(SoN::IR::Stamp::meet($int, $num)->type, 'Int',  'meet(Int, Num) = Int');
    is(SoN::IR::Stamp::meet($num, $str)->type, 'Num',  'meet(Num, Str) = Num');
    is(SoN::IR::Stamp::meet($int, $str)->type, 'Int',  'meet(Int, Str) = Int');

    my $dualvar = SoN::IR::Stamp->new(type => 'DualVar');
    is(SoN::IR::Stamp::meet($dualvar, $num)->type, 'None',
        'meet(DualVar, Num) = None (no common subtype)');
};

subtest 'Join (least upper bound)' => sub {
    my $int = SoN::IR::Stamp->new(type => 'Int');
    my $num = SoN::IR::Stamp->new(type => 'Num');
    my $str = SoN::IR::Stamp->new(type => 'Str');

    is(SoN::IR::Stamp::join($int, $num)->type, 'Num',    'join(Int, Num) = Num');
    is(SoN::IR::Stamp::join($num, $str)->type, 'Str',    'join(Num, Str) = Str');
    is(SoN::IR::Stamp::join($int, $str)->type, 'Str',    'join(Int, Str) = Str');

    my $dualvar = SoN::IR::Stamp->new(type => 'DualVar');
    is(SoN::IR::Stamp::join($dualvar, $num)->type, 'Scalar',
        'join(DualVar, Num) = Scalar');
};

subtest 'New types: Void, List, Regex, Glob are representable' => sub {
    for my $type (qw(Void List Regex Glob)) {
        my $stamp = SoN::IR::Stamp->new(type => $type);
        is($stamp->type, $type, "$type stamp created");
    }
};

subtest 'Void and List are siblings of Scalar under Unknown' => sub {
    my $void    = SoN::IR::Stamp->new(type => 'Void');
    my $list    = SoN::IR::Stamp->new(type => 'List');
    my $unknown = SoN::IR::Stamp->new(type => 'Unknown');
    my $scalar  = SoN::IR::Stamp->new(type => 'Scalar');

    ok($void->is_subtype_of($unknown),   'Void < Unknown');
    ok($list->is_subtype_of($unknown),   'List < Unknown');
    ok(!$void->is_subtype_of($scalar),   'Void is not < Scalar (sibling)');
    ok(!$list->is_subtype_of($scalar),   'List is not < Scalar (sibling)');
    ok(!$scalar->is_subtype_of($void),   'Scalar is not < Void');
};

subtest 'Regex and Glob are subtypes of Ref' => sub {
    my $regex = SoN::IR::Stamp->new(type => 'Regex');
    my $glob  = SoN::IR::Stamp->new(type => 'Glob');
    my $ref   = SoN::IR::Stamp->new(type => 'Ref');

    ok($regex->is_subtype_of($ref),  'Regex < Ref');
    ok($glob->is_subtype_of($ref),   'Glob < Ref');
};

subtest 'None is subtype of new types' => sub {
    my $none  = SoN::IR::Stamp->new(type => 'None');
    my $regex = SoN::IR::Stamp->new(type => 'Regex');
    my $glob  = SoN::IR::Stamp->new(type => 'Glob');

    ok($none->is_subtype_of($regex), 'None < Regex');
    ok($none->is_subtype_of($glob),  'None < Glob');
};

subtest 'Meet with new types' => sub {
    my $regex   = SoN::IR::Stamp->new(type => 'Regex');
    my $coderef = SoN::IR::Stamp->new(type => 'CodeRef');
    my $void    = SoN::IR::Stamp->new(type => 'Void');
    my $scalar  = SoN::IR::Stamp->new(type => 'Scalar');

    is(SoN::IR::Stamp::meet($regex, $coderef)->type, 'None',
        'meet(Regex, CodeRef) = None (siblings under Ref)');
    is(SoN::IR::Stamp::meet($void, $scalar)->type, 'None',
        'meet(Void, Scalar) = None (no common subtype)');
};

subtest 'Join with new types' => sub {
    my $regex   = SoN::IR::Stamp->new(type => 'Regex');
    my $coderef = SoN::IR::Stamp->new(type => 'CodeRef');
    my $void    = SoN::IR::Stamp->new(type => 'Void');
    my $scalar  = SoN::IR::Stamp->new(type => 'Scalar');

    is(SoN::IR::Stamp::join($regex, $coderef)->type, 'Ref',
        'join(Regex, CodeRef) = Ref');
    is(SoN::IR::Stamp::join($void, $scalar)->type, 'Unknown',
        'join(Void, Scalar) = Unknown');
};

done_testing;
