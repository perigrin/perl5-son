# ABOUTME: Length operation node in the Chalk IR.
# ABOUTME: Unary data node producing the CHARACTER length of a string operand.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

# STRINGS ONLY. An aggregate's element count is a Count node; wrapping a
# non-aggregate in one (or an aggregate in this) is a miscompile.
class SoN::IR::Node::Length :isa(SoN::IR::Node::UnaryOp) {
    method operation() { 'Length' }
    method op_str()    { 'length' }
}
