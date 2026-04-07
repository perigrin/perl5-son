# ABOUTME: Regex substitution operation in the SoN IR graph.
# ABOUTME: Carries pattern, replacement, and flags for s/// binding against an input node.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::RegexSubst :isa(SoN::IR::Node) {
    field $pattern     :param :reader;
    field $replacement :param :reader;
    field $flags       :param :reader = '';

    method operation () { 'RegexSubst' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "RegexSubst|pattern=$pattern|replacement=$replacement|flags=$flags|"
             . CORE::join('|', @input_ids);
    }
}

1;
