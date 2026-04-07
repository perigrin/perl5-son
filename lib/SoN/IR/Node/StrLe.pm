# ABOUTME: String less-than-or-equal comparison in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing a boolean result.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::StrLe :isa(SoN::IR::Node::BinOp) {
    method operation () { 'StrLe' }

    method op_str () { 'le' }
}

1;
