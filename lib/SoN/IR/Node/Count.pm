# ABOUTME: Count operation node -- the number of ELEMENTS in an aggregate.
# ABOUTME: Distinct from Length, which is the number of characters in a string.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Access;

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
# MEMORY-DEPENDENT, like every other read of something that lives in memory.
# It extended UnaryOp -- ONE input, no memory slot -- and that arity was the
# whole bug: a whole-aggregate read could not observe a mutation no matter how
# well the mutation was threaded. Measured before the change:
#
#     my @a=(1,2,3); shift @a; print scalar(@a);
#       perl:  2
#       graph: Count[ArrayLiteral], reading the PRE-shift array and BUILT
#              BEFORE the shift. Says 3, silently.
#
# The mutation was ALREADY the new memory version; only the read was blind.
# That is why `push` refused (it produced the same shape) while `shift`
# shipped -- an inconsistency in one class, not two different problems.
#
# THE MEMORY INPUT IS OPTIONAL, and its absence is meaningful rather than lazy.
# `scalar(map {...} @xs)` counts a value the graph just computed, which lives
# in no memory at all; threading it would assert a dependency that does not
# exist and order a read that is genuinely free to float. So inputs are
# [aggregate] for a computed list and [aggregate, memory] for one that lives
# in memory.
class SoN::IR::Node::Count :isa(SoN::IR::Node::Access) {
    method operation() { 'Count' }
    method op_str()    { 'count' }
}
