# ABOUTME: Optimizer-promoted field read on a struct in the SoN IR graph.
# ABOUTME: Accesses a named field on a StructRef node without hash lookup overhead.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::StructFieldAccess :isa(SoN::IR::Node) {
    method operation () { 'StructFieldAccess' }
}

1;
