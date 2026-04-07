# ABOUTME: Backtick/qx command execution in the SoN IR graph.
# ABOUTME: Represents shell command execution that captures output as a string.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::BacktickExpr :isa(SoN::IR::Node) {
    method operation () { 'BacktickExpr' }
}

1;
