# ABOUTME: Numeric coercion (unary plus) operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking one input and producing its numeric coercion.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::UnaryPlus :isa(SoN::IR::Node::UnaryOp) {
    method operation () { 'UnaryPlus' }

    method op_str () { '+' }
}

1;
