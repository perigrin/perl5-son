# ABOUTME: Unary negation operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking one input and producing its arithmetic negation.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Negate :isa(SoN::IR::Node) {
    method operation () { 'Negate' }
}

1;
