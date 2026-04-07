# ABOUTME: Yada-yada (unimplemented stub) operation in the SoN IR graph.
# ABOUTME: Hash-consed data node representing a placeholder for unimplemented functionality.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::Yada :isa(SoN::IR::Node::BinOp) {
    method operation () { 'Yada' }

    method op_str () { '...' }
}

1;
