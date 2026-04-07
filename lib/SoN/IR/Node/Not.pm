# ABOUTME: Logical not operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking one input and producing its logical negation.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::Not :isa(SoN::IR::Node::UnaryOp) {
    method operation () { 'Not' }

    method op_str () { '!' }
}

1;
