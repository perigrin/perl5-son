# ABOUTME: Subtraction operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing their difference.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::Subtract :isa(SoN::IR::Node::BinOp) {
    method operation () { 'Subtract' }

    method op_str () { '-' }
}

1;
