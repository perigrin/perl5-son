# ABOUTME: Ternary conditional expression node in the Chalk IR.
# ABOUTME: Represents condition ? true_expr : false_expr. Lowered to If+Proj+Region+Phi in a future pass.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use SoN::IR::Value;

class SoN::IR::Node::TernaryExpr :isa(SoN::IR::Value) {
    # A STATEMENT THAT CONDITIONALLY REBINDS A LEXICAL -- `$s .= $q if C` --
    # merges as this node, and says which input holds the arm's new value:
    # 1 (`if`) or 2 (`unless`); the other is the value it had before. Undef
    # for a ternary the source wrote. Such a node is pinned where the
    # statement stood, and a consumer may spell it as that statement.
    field $rebind_arm :param :reader = undef;

    method operation() { 'TernaryExpr' }
}
