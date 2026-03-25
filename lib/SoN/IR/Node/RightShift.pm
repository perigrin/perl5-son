# ABOUTME: Right bit shift operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and shifting the first right by the second.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::RightShift :isa(SoN::IR::Node) {
    method operation () { 'RightShift' }
}

1;
