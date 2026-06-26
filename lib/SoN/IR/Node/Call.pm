# ABOUTME: Subroutine, method, or builtin call operation in the SoN IR graph.
# ABOUTME: Hash-consed data node carrying dispatch kind and callee name alongside its inputs.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Call :isa(SoN::IR::Node) {
    field $dispatch_kind :param :reader;
    field $name          :param :reader;
    # The statically-known class for a method dispatch (e.g. Class->new). undef
    # for direct/builtin calls and for method calls whose class is inferred from
    # the invocant. Part of identity: two calls differing only by class differ.
    field $class_name    :param :reader = undef;

    method operation () { 'Call' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "Call|dispatch_kind=" . $dispatch_kind
             . "|name=" . $name
             . "|class_name=" . ( $class_name // '' )
             . "|" . CORE::join('|', @input_ids);
    }
}

1;
