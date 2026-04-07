# ABOUTME: Optimizer-promoted hash-to-struct reference in the SoN IR graph.
# ABOUTME: Represents a hash that the optimizer has determined has a fixed field layout.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::StructRef :isa(SoN::IR::Node) {
    method operation () { 'StructRef' }
}

1;
