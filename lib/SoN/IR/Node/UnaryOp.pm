# ABOUTME: Intermediate base class for unary operation IR nodes.
# ABOUTME: Provides operand() and abstract op_str() accessors.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::UnaryOp :isa(SoN::IR::Node) {
    field $operand :param :reader = undef;

    ADJUST {
        $operand //= $self->inputs()->[0];
    }

    method op_str() {
        die "Subclass must implement op_str()";
    }
}
