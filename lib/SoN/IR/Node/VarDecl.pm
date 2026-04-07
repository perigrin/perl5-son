# ABOUTME: Variable declaration node in the SoN IR graph.
# ABOUTME: Represents my/local/our declarations with an explicit scope qualifier.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::VarDecl :isa(SoN::IR::Node) {
    field $scope :param :reader;

    method operation () { 'VarDecl' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "VarDecl|scope=$scope|" . CORE::join('|', @input_ids);
    }
}

1;
