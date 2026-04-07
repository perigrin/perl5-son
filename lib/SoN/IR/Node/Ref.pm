# ABOUTME: Reference constructor operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking one input and producing a reference to it.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::Ref :isa(SoN::IR::Node::UnaryOp) {
    method operation () { 'Ref' }

    method op_str () { '\\' }
}

1;
