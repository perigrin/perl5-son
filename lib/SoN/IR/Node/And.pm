# ABOUTME: Logical and operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing their logical conjunction.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::And :isa(SoN::IR::Node::BinOp) {
    method operation () { 'And' }

    method op_str () { '&&' }
}

1;
