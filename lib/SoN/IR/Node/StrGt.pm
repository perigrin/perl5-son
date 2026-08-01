# ABOUTME: String greater-than comparison node in the Chalk IR.
# ABOUTME: Binary data node wrapping the gt operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::StrGt :isa(SoN::IR::Node::BinOp) {
    method operation() { 'StrGt' }
    method op_str()    { 'gt' }
}
