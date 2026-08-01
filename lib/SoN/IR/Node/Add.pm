# ABOUTME: Addition operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the + operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::Add :isa(SoN::IR::Node::BinOp) {
    method operation() { 'Add' }
    method op_str()    { '+' }
}
