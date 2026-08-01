# ABOUTME: Logical negation operation node in the Chalk IR.
# ABOUTME: Unary data node producing the logical inverse of its operand.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::Not :isa(SoN::IR::Node::UnaryOp) {
    method operation() { 'Not' }
    method op_str()    { '!' }
}
