# ABOUTME: Scalar/element assignment operation in the SoN IR graph.
# ABOUTME: Target/value inputs; an element STORE also threads control (is_stmt_effect).

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';
use SoN::IR::Node::BinOp;

class SoN::IR::Node::Assign :isa(SoN::IR::Node::BinOp) {
    # An element/aggregate store ($a[0] = 42) is a statement-level EFFECT: it is
    # threaded onto the control chain (control leads inputs) so it is ordered and
    # reachable, rather than being an orphan data node whose side effect is lost.
    # A pure scalar rebind ($x = 2) is NOT a stmt effect -- it propagates via the
    # scope binding and carries no control.
    field $is_stmt_effect :param :reader = undef;

    method operation () { 'Assign' }

    method op_str () { '=' }

    # target/value are always the LAST two inputs. For a stmt-effect store the
    # control token leads inputs, so override BinOp's left/right (which bind to
    # inputs[0]/[1]) to name target/value regardless of a leading control input.
    method left  () { $self->inputs->[-2] }
    method right () { $self->inputs->[-1] }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return 'Assign|stmt_effect=' . ( $is_stmt_effect ? 1 : 0 )
             . '|' . CORE::join('|', @input_ids);
    }
}

1;
