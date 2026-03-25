# ABOUTME: Class field access node in the SoN IR graph.
# ABOUTME: Hash-consed data node identifying a field by its index and stash.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::FieldAccess :isa(SoN::IR::Node) {
    field $field_index :param :reader;
    field $field_stash :param :reader;

    method operation () { 'FieldAccess' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "FieldAccess|field_index=" . $field_index
             . "|field_stash=" . $field_stash
             . "|" . CORE::join('|', @input_ids);
    }
}

1;
