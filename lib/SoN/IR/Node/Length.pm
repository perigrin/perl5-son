# ABOUTME: Length operation node in the Chalk IR.
# ABOUTME: Unary data node producing the CHARACTER length of a string operand.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

# STRINGS ONLY. An aggregate's element count is a Count node; wrapping a
# non-aggregate in one (or an aggregate in this) is a miscompile.
class SoN::IR::Node::Length :isa(SoN::IR::Node::UnaryOp) {
    # UNDER `use bytes` the length is of the encoded bytes, not characters.
    field $bytes :param :reader = 0;

    method operation() { 'Length' }
    method op_str()    { 'length' }

    method content_hash() {
        return join('|', 'Length', ($bytes ? 'bytes' : ()), $self->_serialize_inputs());
    }
}
