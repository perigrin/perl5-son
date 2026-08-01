# ABOUTME: String equality comparison node in the Chalk IR.
# ABOUTME: Binary data node wrapping the eq operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::StrEq :isa(SoN::IR::Node::BinOp) {
    method operation() { 'StrEq' }
    method op_str()    { 'eq' }
}
