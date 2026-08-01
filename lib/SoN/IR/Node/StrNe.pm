# ABOUTME: String inequality comparison node in the Chalk IR.
# ABOUTME: Binary data node wrapping the ne operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::StrNe :isa(SoN::IR::Node::BinOp) {
    method operation() { 'StrNe' }
    method op_str()    { 'ne' }
}
