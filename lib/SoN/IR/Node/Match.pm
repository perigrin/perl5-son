# ABOUTME: Regex match binding operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs representing target and pattern.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::Match :isa(SoN::IR::Node::BinOp) {
    method operation () { 'Match' }

    method op_str () { '=~' }
}

1;
