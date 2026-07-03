# ABOUTME: Regex capture-group read ($1, $2, ...) in the SoN IR graph.
# ABOUTME: inputs = [match node]; n selects the capture group.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::RegexCapture :isa(SoN::IR::Node) {
    field $n :param :reader;

    method operation () { 'RegexCapture' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "RegexCapture|n=$n|" . CORE::join('|', @input_ids);
    }
}

1;
