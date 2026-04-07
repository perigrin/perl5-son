# ABOUTME: Ternary conditional expression in the SoN IR graph.
# ABOUTME: Pre-lowering node for ? : (later becomes If/Proj/Region/Phi).

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::TernaryExpr :isa(SoN::IR::Node) {
    method operation () { 'TernaryExpr' }
}

1;
