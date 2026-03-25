# ABOUTME: Projects one output from a multi-output node (e.g. true/false from If).
# ABOUTME: Carries an index indicating which output it selects.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Proj :isa(SoN::IR::Node) {
    field $index :param :reader;
}

1;
