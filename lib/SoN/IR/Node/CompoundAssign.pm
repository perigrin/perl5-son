# ABOUTME: Compound assignment operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs with an operator field (e.g. +=, -=, *=).

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::CompoundAssign :isa(SoN::IR::Node::BinOp) {
    field $op :param :reader;

    method operation () { 'CompoundAssign' }

    method op_str () { '=' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "CompoundAssign|op=$op|" . CORE::join('|', @input_ids);
    }
}

1;
