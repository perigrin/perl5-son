# ABOUTME: Negated regex match operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs representing target and pattern.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::NotMatch :isa(SoN::IR::Node::BinOp) {
    method operation () { 'NotMatch' }

    method op_str () { '!~' }
}

1;
