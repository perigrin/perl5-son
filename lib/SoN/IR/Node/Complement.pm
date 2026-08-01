# ABOUTME: Bitwise complement operation node in the Chalk IR.
# ABOUTME: Unary data node producing the bitwise NOT of its operand.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::Complement :isa(SoN::IR::Node::UnaryOp) {
    method operation() { 'Complement' }
    method op_str()    { '~' }
}
