# ABOUTME: Assignment operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the = operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::Assign :isa(SoN::IR::Node::BinOp) {
    # STORE ONLY A CHANGED VALUE: a demoted foreach iterator written back to
    # its element after the body. Unconditional, it wrote read-only elements
    # (a sub's @_ of constants) that perl, which only aliases, never wrote.
    field $if_changed :param :reader = false;

    # HOW MANY LEADING INPUTS ARE TARGETS, for a list assign: a value read of
    # a named scalar spells like a target, so the kinds cannot say.
    field $targets :param :reader = undef;

    method operation() { 'Assign' }
    method op_str()    { '=' }
}
