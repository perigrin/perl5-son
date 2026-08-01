# ABOUTME: The ref() type-reader operation node in the Chalk IR.
# ABOUTME: Unary data node taking a reference and producing its type/class name (a Str).
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::RefType :isa(SoN::IR::Node::UnaryOp) {
    method operation() { 'RefType' }
    method op_str()    { 'ref' }
}
