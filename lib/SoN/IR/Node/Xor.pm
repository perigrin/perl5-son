# ABOUTME: Logical exclusive or operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the xor operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::Xor :isa(SoN::IR::Node::BinOp) {
    method operation() { 'Xor' }
    method op_str()    { 'xor' }
}
