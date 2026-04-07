# ABOUTME: String three-way comparison (cmp) in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing -1, 0, or 1.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::StrCmp :isa(SoN::IR::Node::BinOp) {
    method operation () { 'StrCmp' }

    method op_str () { 'cmp' }
}

1;
