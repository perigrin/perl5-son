# ABOUTME: String greater-than comparison in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing a boolean result.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::StrGt :isa(SoN::IR::Node::BinOp) {
    method operation () { 'StrGt' }

    method op_str () { 'gt' }
}

1;
