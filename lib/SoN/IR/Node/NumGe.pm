# ABOUTME: Numeric greater-or-equal comparison node in the Chalk IR.
# ABOUTME: Binary data node wrapping the >= operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::NumGe :isa(SoN::IR::Node::BinOp) {
    method operation() { 'NumGe' }
    method op_str()    { '>=' }
}
