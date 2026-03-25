# ABOUTME: Lexical variable access node in the SoN IR graph.
# ABOUTME: Hash-consed data node identifying a pad slot by targ index and variable name.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::PadAccess :isa(SoN::IR::Node) {
    field $targ    :param :reader;
    field $varname :param :reader;

    method operation () { 'PadAccess' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "PadAccess|targ=" . $targ
             . "|varname=" . $varname
             . "|" . CORE::join('|', @input_ids);
    }
}

1;
