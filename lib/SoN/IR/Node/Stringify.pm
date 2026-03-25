# ABOUTME: String coercion operation in the SoN IR graph.
# ABOUTME: Hash-consed unary data node taking one input and producing its string representation.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Stringify :isa(SoN::IR::Node) {
    method operation () { 'Stringify' }
}

1;
