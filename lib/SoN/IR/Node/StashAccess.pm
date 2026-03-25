# ABOUTME: Package variable access node in the SoN IR graph.
# ABOUTME: Hash-consed data node identifying a stash entry by package and variable name.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::StashAccess :isa(SoN::IR::Node) {
    field $stash_name :param :reader;
    field $var_name   :param :reader;

    method operation () { 'StashAccess' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "StashAccess|stash_name=" . $stash_name
             . "|var_name=" . $var_name
             . "|" . CORE::join('|', @input_ids);
    }
}

1;
