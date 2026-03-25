# ABOUTME: Bitwise XOR operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing their bitwise XOR.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::BitXor :isa(SoN::IR::Node) {
    method operation () { 'BitXor' }
}

1;
