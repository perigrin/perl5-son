# ABOUTME: Ternary conditional expression node in the Chalk IR.
# ABOUTME: Represents condition ? true_expr : false_expr. Lowered to If+Proj+Region+Phi in a future pass.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use SoN::IR::Value;

class SoN::IR::Node::TernaryExpr :isa(SoN::IR::Value) {
    method operation() { 'TernaryExpr' }
}
