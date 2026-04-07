# ABOUTME: String interpolation segments node in the SoN IR graph.
# ABOUTME: Aggregate node whose inputs are the literal and variable segments.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::Aggregate;

class SoN::IR::Node::Interpolate :isa(SoN::IR::Node::Aggregate) {
    method operation () { 'Interpolate' }
}

1;
