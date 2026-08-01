# ABOUTME: Postfix dereference node in the Chalk IR.
# ABOUTME: Carries the sigil (@, %, $) indicating the dereference type.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::PostfixDeref :isa(SoN::IR::Node) {
    field $sigil :param :reader;

    method operation() { 'PostfixDeref' }

    method content_hash() {
        return join('|', 'PostfixDeref', "sigil=$sigil", $self->_serialize_inputs());
    }
}
