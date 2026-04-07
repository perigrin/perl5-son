# ABOUTME: Defined check operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking one input and testing whether it is defined.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::Defined :isa(SoN::IR::Node::UnaryOp) {
    method operation () { 'Defined' }

    method op_str () { 'defined' }
}

1;
