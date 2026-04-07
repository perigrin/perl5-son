# ABOUTME: Modulo/remainder operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing their remainder.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::Modulo :isa(SoN::IR::Node::BinOp) {
    method operation () { 'Modulo' }

    method op_str () { '%' }
}

1;
