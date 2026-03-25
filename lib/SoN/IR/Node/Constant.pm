# ABOUTME: Compile-time constant value in the SoN IR graph.
# ABOUTME: Hash-consed data node carrying a value and type stamp.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Constant :isa(SoN::IR::Node) {
    field $value :param :reader;

    method operation () { 'Constant' }

    method content_hash () {
        return "Constant|value=" . (defined $value ? $value : 'undef');
    }
}

1;
