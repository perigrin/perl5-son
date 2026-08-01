# ABOUTME: CFG entry point node for a Chalk computation graph.
# ABOUTME: Has no inputs; produces the initial control token.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::Start :isa(SoN::IR::Node) {
    method operation() { 'Start' }
}
