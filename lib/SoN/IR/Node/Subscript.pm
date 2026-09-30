# ABOUTME: IR node for array or hash subscript operations in the Sea of Nodes graph.
# ABOUTME: inputs->[0] is the container, inputs->[1] is the index or key.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Access;

class SoN::IR::Node::Subscript :isa(SoN::IR::Node::Access) {
    # `hash` for a helem, `array` for an aelem -- which the op says and the
    # container, a scalar holding some reference, often cannot: `$s->{k}`
    # over `shift`'s result was emitted as `$s->[k]`. Part of the identity:
    # `$r->{0}` and `$r->[0]` over the same inputs are different elements.
    field $kind :param :reader = undef;

    method operation() { 'Subscript' }

    method content_hash() {
        return join('|', 'Subscript', (defined $kind ? "kind=$kind" : ()),
            $self->_serialize_inputs());
    }
}
