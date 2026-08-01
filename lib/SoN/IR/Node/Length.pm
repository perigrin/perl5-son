# ABOUTME: Length operation node in the Chalk IR.
# ABOUTME: Unary data node producing the length of its operand (string or array).
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::Length :isa(SoN::IR::Node::UnaryOp) {
    method operation() { 'Length' }
    method op_str()    { 'length' }
}
