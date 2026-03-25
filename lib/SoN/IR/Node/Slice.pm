# ABOUTME: Array/hash slice operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking a container and list of indices, producing a slice.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Slice :isa(SoN::IR::Node) {
    method operation () { 'Slice' }
}

1;
