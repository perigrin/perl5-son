# ABOUTME: String or array length operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking one input and producing its length.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Length :isa(SoN::IR::Node) {
    # Operand-repr contract for a backend lowering this node:
    #   Str      -> byte length of the string
    #   Array/ArrayRef -> element count (`scalar @a`)
    #   Hash/HashRef   -> KEY count (`scalar %h`, perl 5.26+), NOT key+value
    #                     slots and NOT the old bucket ratio.
    method operation () { 'Length' }
}

1;
