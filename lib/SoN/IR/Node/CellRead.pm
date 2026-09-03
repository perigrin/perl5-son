# ABOUTME: Reads the current value out of a capture cell.
# ABOUTME: Memory-dependent: a later CellWrite changes what an identical read returns.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Access;

# inputs are [cell, memory]. The memory input is what makes this
# program-point-dependent: two CellReads of the same cell at different points
# are different values, because a CellWrite between them changes the answer.
# That is the same property PadAccess, Subscript and FieldAccess already have.
#
# THREADED EVEN WHEN THE CELL IS READ-ONLY. Whether the read can be elided
# needs the whole program, which the consumer has and the producer does not --
# and captured_written on the MakeCell already grants permission to elide it.
class SoN::IR::Node::CellRead :isa(SoN::IR::Node::Access) {
    method operation() { 'CellRead' }

    method content_hash() {
        return join('|', 'CellRead', $self->_serialize_inputs());
    }
}
