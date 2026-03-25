# ABOUTME: Division operation in the SoN IR graph.
# ABOUTME: Hash-consed data node taking two inputs and producing their quotient.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Divide :isa(SoN::IR::Node) {
    method operation () { 'Divide' }
}

1;
