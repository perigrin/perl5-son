# ABOUTME: String/list repetition operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs representing value and count.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::Repeat :isa(SoN::IR::Node::BinOp) {
    method operation () { 'Repeat' }

    method op_str () { 'x' }
}

1;
