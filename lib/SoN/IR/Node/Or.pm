# ABOUTME: Logical or operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing their logical disjunction.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::Or :isa(SoN::IR::Node::BinOp) {
    method operation () { 'Or' }

    method op_str () { '||' }
}

1;
