# ABOUTME: Subroutine, method, or builtin call operation in the SoN IR graph.
# ABOUTME: Hash-consed data node carrying dispatch kind and callee name alongside its inputs.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Call :isa(SoN::IR::Node) {
    field $dispatch_kind :param :reader;
    field $name          :param :reader;

    method operation () { 'Call' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "Call|dispatch_kind=" . $dispatch_kind
             . "|name=" . $name
             . "|" . CORE::join('|', @input_ids);
    }
}

1;
