# ABOUTME: Abstract base class for binary operation nodes in the SoN IR graph.
# ABOUTME: Provides left/right accessors and a default op_str for subclasses to override.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::BinOp :isa(SoN::IR::Node) {
    field $left  :reader;
    field $right :reader;

    ADJUST {
        $left  = $self->inputs->[0];
        $right = $self->inputs->[1];
    }

    method op_str () { '' }
}

1;
