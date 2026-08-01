# ABOUTME: String less-or-equal comparison node in the Chalk IR.
# ABOUTME: Binary data node wrapping the le operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::StrLe :isa(SoN::IR::Node::BinOp) {
    method operation() { 'StrLe' }
    method op_str()    { 'le' }
}
