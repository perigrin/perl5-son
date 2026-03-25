# ABOUTME: String or array length operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking one input and producing its length.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Length :isa(SoN::IR::Node) {
    method operation () { 'Length' }
}

1;
