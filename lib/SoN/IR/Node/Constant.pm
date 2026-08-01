# ABOUTME: IR node representing a constant value in the Chalk Sea of Nodes graph.
# ABOUTME: Holds a typed literal (string, integer, etc.) with a stable content_hash.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::Constant :isa(SoN::IR::Node) {
    field $value      :param :reader;
    field $const_type :param :reader = 'string';

    method operation() { 'Constant' }

    method content_hash() {
        return join('|', 'Constant',
            "const_type=$const_type",
            "value=" . (defined $value ? $value : 'undef'));
    }
}
