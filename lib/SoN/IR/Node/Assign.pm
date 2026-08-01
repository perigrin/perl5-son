# ABOUTME: Assignment operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the = operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::Assign :isa(SoN::IR::Node::BinOp) {
    method operation() { 'Assign' }
    method op_str()    { '=' }
}
