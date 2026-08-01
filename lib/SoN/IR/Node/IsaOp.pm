# ABOUTME: Type check operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the isa operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::IsaOp :isa(SoN::IR::Node::BinOp) {
    method operation() { 'IsaOp' }
    method op_str()    { 'isa' }
}
