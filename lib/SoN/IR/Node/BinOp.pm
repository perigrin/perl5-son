# ABOUTME: Intermediate base class for binary operation IR nodes.
# ABOUTME: Provides left(), right(), and abstract op_str() accessors.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::BinOp :isa(SoN::IR::Node) {
    field $left  :param :reader = undef;
    field $right :param :reader = undef;

    ADJUST {
        $left  //= $self->inputs()->[0];
        $right //= $self->inputs()->[1];
    }

    method op_str() {
        die "Subclass must implement op_str()";
    }
}
