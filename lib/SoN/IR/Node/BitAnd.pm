# ABOUTME: Bitwise AND operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing their bitwise AND.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::BitAnd :isa(SoN::IR::Node) {
    method operation () { 'BitAnd' }
}

1;
