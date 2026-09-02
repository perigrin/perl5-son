# ABOUTME: Boolean sits under Scalar, not under Str -- proven by the formal
# ABOUTME: type system's two-factor subtyping test, both factors applied.

use v5.42.0;
use utf8;
use Test2::V0;
use SoN::IR::Stamp;

# THE TEST (perl-type-system-formal.md, "Subtyping Relationship"):
#
#     A <: B  iff  (A subset-of B) and (every op of B holds for values of A)
#
# BOTH factors are required. Factor 2 alone is what put Boolean under Str:
# every string operation works on a boolean uncoerced -- concat, length, uc,
# eq, substr, regex -- so it LOOKS like a Str. That is substitutability, and
# it is only half the test.
#
# FACTOR 1 FAILS. Str membership is the syntactic-preservation round trip:
#
#     Str := {v in Scalar | exists S: (S != Str) and C(v) == id_S(v)}
#
# `exists S` means a NEGATIVE proof must exhaust every admissible reference
# type. Direct Str interpretation of `false` is "". Measured on 5.42.0:
#
#     S=Num        detour "0"   FAILS      "0" ne ""
#     S=Int        detour "0"   FAILS      "0" ne ""
#     S=ScalarRef  detour ""    INADMISSIBLE -- identity on every Str
#                                ("hello" -> "hello"), the vacuous test the
#                                well-formedness note excludes
#     S=Boolean    detour ""    INADMISSIBLE -- circular. The stratification
#                                is Scalar/List -> Str -> Num -> Int, with
#                                "Ref, Boolean, etc. use Scalar"; defining Str
#                                via Boolean inverts that.
#
# No admissible S preserves, so false is not in Str, so Boolean is not a
# subset of Str, so Boolean <: Str is FALSE.
#
# NOTE `true` PASSES via S=Num (1 -> "1" -> "1"). The counterexample is `false`
# specifically, not booleans in general -- which is why testing one value, or
# testing only factor 2, reached the wrong answer.
#
# The formal document states the conclusion independently: "Scalar contains
# values that belong neither to Str nor to Num - including Boolean (true/false),
# Undef (undef), Ref (references), and DualVars", and its hierarchy places
# Boolean as a direct child of Scalar, sibling to Str.

subtest 'Boolean is not a subtype of Str' => sub {
    my $bool = SoN::IR::Stamp->new( type => 'Boolean' );
    ok !$bool->is_subtype_of( SoN::IR::Stamp->new( type => 'Str' ) ),
        'Boolean is NOT <: Str -- `false` fails syntactic preservation';
    ok !$bool->is_subtype_of( SoN::IR::Stamp->new( type => 'Num' ) ),
        '... nor <: Num, which Str would have implied transitively';
};

subtest 'Boolean is a subtype of Scalar, as the formal hierarchy places it' => sub {
    my $bool = SoN::IR::Stamp->new( type => 'Boolean' );
    ok $bool->is_subtype_of( SoN::IR::Stamp->new( type => 'Scalar' ) ),
        'Boolean <: Scalar';
    ok !$bool->is_subtype_of( SoN::IR::Stamp->new( type => 'Undef' ) ),
        'and not <: Undef -- they are siblings, which is why an op that can
         return undef cannot be typed Boolean';
};

# THE CONSEQUENCE FOR JOINS, which is what the wire actually carries. Boolean
# and Int are now siblings-of-siblings rather than lying on one chain, so their
# least upper bound rises to Scalar. That is the honest answer: a boolean and
# an integer have no common type below Scalar, and calling it Str invited a
# consumer to treat `-c $f` and `length $x` as the same kind of thing.
subtest 'joins reflect the corrected placement' => sub {
    my $bool = SoN::IR::Stamp->new( type => 'Boolean' );

    # ALL THREE of the Str branch move, not two. I first reported Str and
    # Int and omitted Num, which chalk caught by enumerating rather than
    # inferring the set from the two I had named. Num sits between them, so
    # it could not have stayed put.
    for my $t (qw( Str Num Int )) {
        is SoN::IR::Stamp::join( $bool, SoN::IR::Stamp->new( type => $t ) )->type,
            'Scalar', "join(Boolean,$t) is Scalar, not Str";
    }
    is SoN::IR::Stamp::join( $bool, SoN::IR::Stamp->new( type => 'Undef' ) )->type,
        'Scalar', 'join(Boolean,Undef) stays Scalar, as the file tests need';
    is SoN::IR::Stamp::join( $bool, $bool )->type,
        'Boolean', 'and a Boolean joined with itself is still Boolean';
};

# THE REST OF THE CHAIN IS UNTOUCHED. Moving one edge must not disturb
# Int <: Num <: Str <: Scalar, which the formal document derives separately.
subtest 'the numeric-string chain is unaffected' => sub {
    my %s = map { $_ => SoN::IR::Stamp->new( type => $_ ) }
        qw( Int Num Str Scalar );
    ok $s{Int}->is_subtype_of( $s{Num} ),    'Int <: Num';
    ok $s{Num}->is_subtype_of( $s{Str} ),    'Num <: Str';
    ok $s{Str}->is_subtype_of( $s{Scalar} ), 'Str <: Scalar';
    is SoN::IR::Stamp::join( $s{Int}, $s{Str} )->type, 'Str',
        'join(Int,Str) is still Str';
};

done_testing;
