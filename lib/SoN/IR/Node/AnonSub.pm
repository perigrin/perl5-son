# ABOUTME: Anonymous sub/closure in the SoN IR graph.
# ABOUTME: Represents a sub { } expression that captures lexical variables.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::AnonSub :isa(SoN::IR::Node) {
    method operation () { 'AnonSub' }
}

1;
