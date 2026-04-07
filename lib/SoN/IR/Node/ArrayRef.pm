# ABOUTME: Anonymous array constructor in the SoN IR graph.
# ABOUTME: Aggregate node whose inputs are the array elements.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::Aggregate;

class SoN::IR::Node::ArrayRef :isa(SoN::IR::Node::Aggregate) {
    method operation () { 'ArrayRef' }
}

1;
