# ABOUTME: Bitwise OR operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing their bitwise OR.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::BitOr :isa(SoN::IR::Node) {
    method operation () { 'BitOr' }
}

1;
