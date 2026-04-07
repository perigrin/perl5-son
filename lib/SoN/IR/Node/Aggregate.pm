# ABOUTME: Abstract base class for aggregate (multi-input) nodes in the SoN IR graph.
# ABOUTME: Provides an elements() method returning all inputs as a list.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Aggregate :isa(SoN::IR::Node) {
    method elements () { $self->inputs }
}

1;
