# ABOUTME: &&, || and // return an OPERAND, not a Boolean, so they join.
# ABOUTME: The join comes from the lattice; these rows must not hardcode it.
use 5.42.0;
use utf8;
use Test::More;
use B::SoN::TypeLibrary;
use SoN::IR::Stamp;

my $r = \&B::SoN::TypeLibrary::result_for;

sub lub ( $a, $b ) {
    return SoN::IR::Stamp::join(
        SoN::IR::Stamp->new( type => $a ),
        SoN::IR::Stamp->new( type => $b ),
    )->type;
}

# THE DEFECT. `$@ || "Zombie Error"` in perl's t/base/rs.t reached the wire as
# Or:Unknown with BOTH operands stamped -- EntryDef:Scalar and Constant:Str.
# Nothing was unknowable about it; And/Or/DefinedOr were simply never declared,
# so `result_for` had nothing to answer with. Same shape as `abs`: the fact
# existed, the table was never asked.
#
# These are NOT Boolean ops. perl returns one of the OPERANDS:
#     0 || "hello"  is "hello"      5 && "hello" is "hello"
#     "x" && 7      is 7            undef // 5   is 5
# so the result is the join of the two arms, exactly like Add or Negate.
subtest 'a short-circuit yields the join of its arms' => sub {
    is $r->( 'Or',        'Scalar', 'Str' ), lub( 'Scalar', 'Str' ),
        '$@ || "Zombie Error" is join(Scalar,Str)';
    is $r->( 'And',       'Int',    'Str' ), lub( 'Int',    'Str' ),
        '&& joins its arms too';
    is $r->( 'DefinedOr', 'Undef',  'Int' ), lub( 'Undef',  'Int' ),
        '// joins its arms too';
};

# Two arms of ONE type stay that type -- the join is not a widening step.
subtest 'matching arms are not widened' => sub {
    is $r->( 'Or',  'Str', 'Str' ), 'Str', 'Str || Str is Str';
    is $r->( 'And', 'Int', 'Int' ), 'Int', 'Int && Int is Int';
};

# An unknowable arm makes the whole thing unknowable. An honest undef, not a
# guess at the arm that happened to be typed.
subtest 'an Unknown arm is not papered over' => sub {
    is $r->( 'Or', 'Unknown', 'Str' ), undef, 'one Unknown arm yields undef';
};

done_testing;
