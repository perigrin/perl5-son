# ABOUTME: Multiplication operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing their product.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Multiply :isa(SoN::IR::Node) {
    method operation () { 'Multiply' }
}

1;
