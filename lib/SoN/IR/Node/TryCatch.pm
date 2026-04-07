# ABOUTME: Try/catch block in the SoN IR graph.
# ABOUTME: Pre-lowering node for try/catch (later expanded to CFG nodes).

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::TryCatch :isa(SoN::IR::Node) {
    method operation () { 'TryCatch' }
}

1;
