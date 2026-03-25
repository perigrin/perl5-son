# ABOUTME: Value selection node at Region or Loop merge points in the SoN IR graph.
# ABOUTME: Hash-consed data node that selects among incoming values based on control flow.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Phi :isa(SoN::IR::Node) {
    field $region :param :reader;

    method operation () { 'Phi' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "Phi|region=" . $region->id
             . "|" . CORE::join('|', @input_ids);
    }
}

1;
