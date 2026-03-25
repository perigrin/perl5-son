# ABOUTME: Numeric three-way comparison (spaceship) in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing -1, 0, or 1.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::NumCmp :isa(SoN::IR::Node) {
    method operation () { 'NumCmp' }
}

1;
