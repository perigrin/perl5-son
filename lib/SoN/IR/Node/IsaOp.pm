# ABOUTME: Type check operator in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs representing value and class name.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::IsaOp :isa(SoN::IR::Node::BinOp) {
    method operation () { 'IsaOp' }

    method op_str () { 'isa' }
}

1;
