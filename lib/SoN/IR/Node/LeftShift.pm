# ABOUTME: Left bit shift operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and shifting the first left by the second.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::LeftShift :isa(SoN::IR::Node) {
    method operation () { 'LeftShift' }
}

1;
