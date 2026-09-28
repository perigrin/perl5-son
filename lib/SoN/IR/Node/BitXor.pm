# ABOUTME: Bitwise XOR operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the ^ operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::BitXor :isa(SoN::IR::Node::BinOp) {
    # WHICH OPERATOR, when the `bitwise` feature says: 'numeric' (& | ^ ~ under
    # `use v5.28`), 'string' (&. |. ^. ~.), or undef for the dual operator that
    # reads its operands. In the content hash, so the three are three nodes.
    field $flavor :param :reader = undef;

    method content_hash() {
        return join('|', $self->operation(),
            (defined $flavor ? "flavor=$flavor" : ()),
            $self->_serialize_inputs());
    }

    method operation() { 'BitXor' }
    method op_str()    { '^' }
}
