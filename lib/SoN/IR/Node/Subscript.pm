# ABOUTME: IR node for array or hash subscript operations in the Sea of Nodes graph.
# ABOUTME: inputs->[0] is the container, inputs->[1] is the index or key.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Access;

class SoN::IR::Node::Subscript :isa(SoN::IR::Node::Access) {
    method operation() { 'Subscript' }
}
