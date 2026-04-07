# ABOUTME: Scalar assignment operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs representing target and value.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::Assign :isa(SoN::IR::Node::BinOp) {
    method operation () { 'Assign' }

    method op_str () { '=' }
}

1;
