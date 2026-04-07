# ABOUTME: Addition operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing their sum.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::Add :isa(SoN::IR::Node::BinOp) {
    method operation () { 'Add' }

    method op_str () { '+' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "Add|" . CORE::join('|', @input_ids);
    }
}

1;
