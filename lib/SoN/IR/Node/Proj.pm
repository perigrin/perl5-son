# ABOUTME: CFG projection node for a Chalk computation graph.
# ABOUTME: Selects one control output (by index) from a multi-output node such as If.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::Proj :isa(SoN::IR::Node) {
    field $index :param :reader;

    method operation() { 'Proj' }

    method content_hash() {
        return join('|', 'Proj', "index=$index", $self->_serialize_inputs());
    }
}
