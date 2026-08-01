# ABOUTME: Yada-yada (unimplemented) operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the ... operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::Yada :isa(SoN::IR::Node::BinOp) {
    method operation() { 'Yada' }
    method op_str()    { '...' }
}
