# ABOUTME: CFG exception/die flow node for a SoN computation graph.
# ABOUTME: Carries the control token when an exception unwinds the stack.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Unwind :isa(SoN::IR::Node) {
}

1;
