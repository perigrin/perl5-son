# ABOUTME: CFG exit point node for a SoN computation graph.
# ABOUTME: Carries the control token and return value.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Return :isa(SoN::IR::Node) {
}

1;
