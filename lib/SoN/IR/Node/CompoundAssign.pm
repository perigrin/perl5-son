# ABOUTME: Compound assignment node in the Chalk IR.
# ABOUTME: Carries the operator (+=, -=, .=, etc.) for the combined read-modify-write.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::CompoundAssign :isa(SoN::IR::Node) {
    field $op :param :reader;

    method operation() { 'CompoundAssign' }

    method content_hash() {
        return join('|', 'CompoundAssign', "op=$op", $self->_serialize_inputs());
    }
}
