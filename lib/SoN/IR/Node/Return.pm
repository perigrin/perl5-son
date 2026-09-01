# ABOUTME: CFG normal-exit node for a Chalk computation graph.
# ABOUTME: inputs[0] is the return value, inputs[1] the scalar reading of a
# ABOUTME: list return; the control predecessor lives in control_in.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::Return :isa(SoN::IR::Node) {
    # Marks a Return synthesized by _finalize_body_graph for the
    # implicit fall-through case (the source had a bare trailing
    # expression). Codegen emits a synthetic Return as a bare value;
    # an explicit-source Return emits `return EXPR;`.
    field $synthetic :param :reader = false;

    method operation() { 'Return' }

    # The returned value. Control flows through the control_in decoration
    # (set via set_control_in), not through an inputs slot.
    method value() { return $self->inputs->[0] }

    # The SCALAR READING of a multi-value list return, or undef.
    #
    # A perl sub is compiled once and cannot see its caller's context, so a
    # list-returning sub carries both faces: value() is every value flattened,
    # and this is what a scalar-context callsite takes. Which one applies is
    # the calling Call node's `want`.
    #
    # NAMED, because the alternative is every consumer knowing an index. Three
    # sites in chalk and one here read a Return's LAST input for its value --
    # correct while a Return had exactly one, and silently the scalar face once
    # it had two. `inputs->[-1]` was an arity assumption nothing recorded.
    method scalar_value() { return $self->inputs->[1] }
}
