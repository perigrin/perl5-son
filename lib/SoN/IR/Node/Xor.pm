# ABOUTME: Logical exclusive or operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing their logical XOR.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::Xor :isa(SoN::IR::Node::BinOp) {
    method operation () { 'Xor' }

    method op_str () { 'xor' }
}

1;
