# ABOUTME: Multiplication operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the * operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::Multiply :isa(SoN::IR::Node::BinOp) {
    method operation() { 'Multiply' }
    method op_str()    { '*' }
}
