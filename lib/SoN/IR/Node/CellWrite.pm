# ABOUTME: Writes a value into a capture cell, yielding a new memory version.
# ABOUTME: This is what makes a closure's write visible to the outer scope.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

# inputs are [cell, value, memory]. The node becomes the new memory version, so
# a later CellRead -- in this closure, in a sibling closure, or in the
# enclosing scope -- observes the write. Measured: `$inc->(); $inc->();` then
# `$rd->()` is 2, and that is only expressible if the two closures' reads and
# writes are ordered on one chain.
#
# NEVER HASH-CONSED, for the same reason MakeCell is not: two writes of the
# same value to the same cell are two distinct events.
class SoN::IR::Node::CellWrite :isa(SoN::IR::Value) {
    my $write_counter = 0;
    field $write_id :reader;

    ADJUST { $write_id = $write_counter++; }

    method operation() { 'CellWrite' }

    method content_hash() {
        return join('|', 'CellWrite', "write_id=$write_id",
            $self->_serialize_inputs());
    }
}
