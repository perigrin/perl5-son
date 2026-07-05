# ABOUTME: The ref() type-reader operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking a reference and producing its type/class name (a Str).

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::RefType :isa(SoN::IR::Node::UnaryOp) {
    method operation () { 'RefType' }

    method op_str () { 'ref' }
}

1;
