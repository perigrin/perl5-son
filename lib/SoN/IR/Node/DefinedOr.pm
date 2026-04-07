# ABOUTME: Defined-or short circuit operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs, returning left if defined, else right.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::DefinedOr :isa(SoN::IR::Node::BinOp) {
    method operation () { 'DefinedOr' }

    method op_str () { '//' }
}

1;
