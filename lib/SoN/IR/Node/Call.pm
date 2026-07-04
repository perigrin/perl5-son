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
    # For a constructor dispatch (name eq 'new'), the :param keys parallel to
    # the value inputs -- param_names->[i] names the field that inputs->[i]
    # binds. undef for non-constructor calls. Part of identity.
    field $param_names   :param :reader = undef;
    # True for a call in void statement position: its result is discarded and
    # its only purpose is its side effect. Such a call leads with the current
    # control node (input[0]) and must be threaded into the effect chain rather
    # than DCE'd. Part of identity -- a stmt-effect call carries a control edge
    # a value call does not, so they must not hash-cons together.
    field $is_stmt_effect :param :reader = undef;

    method operation () { 'Call' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "Call|dispatch_kind=" . $dispatch_kind
             . "|name=" . $name
             . "|class_name=" . ( $class_name // '' )
             . "|param_names=" . ( defined $param_names ? CORE::join(',', $param_names->@*) : '' )
             . "|stmt_effect=" . ( $is_stmt_effect ? 1 : 0 )
             . "|" . CORE::join('|', @input_ids);
    }
}

1;
