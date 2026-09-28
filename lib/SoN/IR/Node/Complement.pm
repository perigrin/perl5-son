# ABOUTME: Bitwise complement operation node in the Chalk IR.
# ABOUTME: Unary data node producing the bitwise NOT of its operand.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::Complement :isa(SoN::IR::Node::UnaryOp) {
    # WHICH OPERATOR, when the `bitwise` feature says: 'numeric' (& | ^ ~ under
    # `use v5.28`), 'string' (&. |. ^. ~.), or undef for the dual operator that
    # reads its operands. In the content hash, so the three are three nodes.
    field $flavor :param :reader = undef;

    method content_hash() {
        return join('|', $self->operation(),
            (defined $flavor ? "flavor=$flavor" : ()),
            $self->_serialize_inputs());
    }

    method operation() { 'Complement' }
    method op_str()    { '~' }
}
