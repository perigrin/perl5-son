# ABOUTME: Numeric less-than-or-equal comparison in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing a boolean result.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::NumLe :isa(SoN::IR::Node) {
    method operation () { 'NumLe' }
}

1;
