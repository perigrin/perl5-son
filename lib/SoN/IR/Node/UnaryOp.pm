# ABOUTME: Abstract base class for unary operation nodes in the SoN IR graph.
# ABOUTME: Provides operand accessor and a default op_str for subclasses to override.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::UnaryOp :isa(SoN::IR::Node) {
    field $operand :reader;

    ADJUST {
        $operand = $self->inputs->[0];
    }

    method op_str () { '' }
}

1;
