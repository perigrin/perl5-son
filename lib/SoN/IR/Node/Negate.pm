# ABOUTME: Arithmetic negation operation node in the Chalk IR.
# ABOUTME: Unary data node producing the numeric negation of its operand.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::Negate :isa(SoN::IR::Node::UnaryOp) {
    method operation() { 'Negate' }
    method op_str()    { '-' }
}
