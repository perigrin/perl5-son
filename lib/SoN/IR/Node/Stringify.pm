# ABOUTME: String coercion operation node in the Chalk IR.
# ABOUTME: Takes one input and produces its string representation.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::Stringify :isa(SoN::IR::Node) {
    method operation() { 'Stringify' }
}
