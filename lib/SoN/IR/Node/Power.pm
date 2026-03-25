# ABOUTME: Exponentiation operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and raising the first to the power of the second.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Power :isa(SoN::IR::Node) {
    method operation () { 'Power' }
}

1;
