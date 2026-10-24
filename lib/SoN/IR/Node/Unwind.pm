# ABOUTME: CFG exceptional-exit node for a Chalk computation graph.
# ABOUTME: inputs[0] is the exception-args arrayref; control flows via control_in.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::Unwind :isa(SoN::IR::Node) {
    method operation() { 'Unwind' }

    # THE BLOCK EVAL THAT LEXICALLY HOLDS THIS DIE in its graph (the same
    # eval_id is on that eval's Region), or undef: one not in an eval here
    # is caught by whichever eval is running when it fires.
    field $eval_id :reader = undef;

    method set_eval_id($id) {
        $eval_id = $id;
        return;
    }

    # The exception arguments (an arrayref). Control flows through the
    # control_in decoration (set via set_control_in), not through inputs.
    method value() { return $self->inputs->[0] }
}
