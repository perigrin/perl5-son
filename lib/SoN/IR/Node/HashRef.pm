# ABOUTME: Anonymous hash constructor in the SoN IR graph.
# ABOUTME: Aggregate node whose inputs are key-value pairs.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::Aggregate;

class SoN::IR::Node::HashRef :isa(SoN::IR::Node::Aggregate) {
    method operation () { 'HashRef' }
}

1;
