# ABOUTME: Count operation node -- the number of ELEMENTS in an aggregate.
# ABOUTME: Distinct from Length, which is the number of characters in a string.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

# AN ELEMENT COUNT IS NOT A STRING LENGTH. Perl keeps them apart and so does
# this IR: `length` is its own op that only ever takes a string, while
# `scalar(@a)` compiles to a bare padav in scalar context with no length op
# anywhere. The producer synthesises this node at the four places an aggregate
# is read in scalar context -- scalar(@a)/scalar(%h), `my $n = @a`, `$#a`
# (which is Count - 1), and a foreach bound.
#
# ONE NODE FOR ARRAYS AND HASHES. scalar(%h) is the key count in modern perl,
# so it is the same operation over the other aggregate kind and the T1 answer
# is Int either way.
class SoN::IR::Node::Count :isa(SoN::IR::Node::UnaryOp) {
    method operation() { 'Count' }
    method op_str()    { 'count' }
}
