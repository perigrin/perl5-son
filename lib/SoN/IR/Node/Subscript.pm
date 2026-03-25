# ABOUTME: Array/hash element access operation in the SoN IR graph.
# ABOUTME: Hash-consed binary data node taking a container and index, producing the element at that index.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Subscript :isa(SoN::IR::Node) {
    method operation () { 'Subscript' }
}

1;
