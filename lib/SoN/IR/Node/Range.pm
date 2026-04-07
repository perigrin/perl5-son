# ABOUTME: Range operator in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs representing the start and end of a range.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::Range :isa(SoN::IR::Node::BinOp) {
    method operation () { 'Range' }

    method op_str () { '..' }
}

1;
