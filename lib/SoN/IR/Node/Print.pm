# ABOUTME: print statement in the SoN IR graph: emits its list of value inputs
# ABOUTME: to stdout as a control-pinned statement effect; yields print's 1.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Print :isa(SoN::IR::Node) {
    # A bare print is OPf_WANT_VOID, so it is always control-pinned: inputs[0]
    # is the control token and inputs[1..N] are the list arguments.
    field $is_stmt_effect :param :reader = undef;

    method operation () { 'Print' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "Print|stmt_effect=" . ( $is_stmt_effect ? 1 : 0 ) . '|'
             . CORE::join('|', @input_ids);
    }
}

1;
