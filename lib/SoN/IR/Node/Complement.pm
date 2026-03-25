# ABOUTME: Bitwise complement operation in the SoN IR graph.
# ABOUTME: Hash-consed unary data node taking one input and producing its bitwise complement.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Complement :isa(SoN::IR::Node) {
    method operation () { 'Complement' }
}

1;
