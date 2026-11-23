# ABOUTME: ModSets: `$_[1] =~ /a/` binds a match to its target and stores nothing there; only
# ABOUTME: an op-assign's OPf_STACKED means a store (a match is a PMOP, which B makes a BINOP).
use v5.42.0;
use Test2::V0;
use B;
use B::SoN;
use SoN::FromOptree::ModSets;

package O { sub isn { $_[1] =~ /a/ } sub dbl { $_[1] *= 2 } }

sub locs ($code) { [ sort map { $_->{loc} } SoN::FromOptree::ModSets::summary(B::svref_2object($code))->@* ] }

# A MATCH WAS AN OP-ASSIGN: `match` with OPf_STACKED isa B::BINOP, so the op=
# rule read it as a store to $_[1] -- and a grep calling such a method was
# refused as one whose callee may write its element.
is locs(\&O::isn), [], 'a match through an argument stores nothing';
is locs(\&O::dbl), ['P'], 'an op-assign through one stores the argument';

done_testing;
