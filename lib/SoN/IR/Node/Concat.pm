# ABOUTME: String concatenation operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing their concatenation.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Concat :isa(SoN::IR::Node) {
    method operation () { 'Concat' }
}

1;
