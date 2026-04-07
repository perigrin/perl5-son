# ABOUTME: Postfix dereference operation in the SoN IR graph (->@*, ->%*, ->$*, ->&*).
# ABOUTME: Hash-consed unary node with a sigil field distinguishing array/hash/scalar/code deref.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::PostfixDeref :isa(SoN::IR::Node::UnaryOp) {
    field $sigil :param :reader;

    method operation () { 'PostfixDeref' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "PostfixDeref|sigil=$sigil|" . CORE::join('|', @input_ids);
    }
}

1;
