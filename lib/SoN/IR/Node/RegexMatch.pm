# ABOUTME: Regex match operation in the SoN IR graph.
# ABOUTME: Carries pattern and flags for m// binding against an input node.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::RegexMatch :isa(SoN::IR::Node) {
    field $pattern :param :reader;
    field $flags   :param :reader = '';

    method operation () { 'RegexMatch' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "RegexMatch|pattern=$pattern|flags=$flags|" . CORE::join('|', @input_ids);
    }
}

1;
