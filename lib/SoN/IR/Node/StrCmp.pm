# ABOUTME: String three-way comparison (cmp) in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing -1, 0, or 1.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::StrCmp :isa(SoN::IR::Node) {
    method operation () { 'StrCmp' }
}

1;
