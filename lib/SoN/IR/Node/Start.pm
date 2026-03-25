# ABOUTME: CFG entry point node for a SoN computation graph.
# ABOUTME: Has no inputs; produces the initial control token.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Start :isa(SoN::IR::Node) {
}

1;
