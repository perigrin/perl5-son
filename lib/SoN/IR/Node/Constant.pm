# ABOUTME: IR node representing a constant value in the Chalk Sea of Nodes graph.
# ABOUTME: Holds a typed literal (string, integer, etc.) with a stable content_hash.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

class SoN::IR::Node::Constant :isa(SoN::IR::Value) {
    field $value      :param :reader;
    field $const_type :param :reader = 'string';
    # A qr// literal's modifiers (`ix`, and a charset when not perl's default).
    field $flags      :param :reader = undef;

    method operation() { 'Constant' }

    method content_hash() {
        return join('|', 'Constant',
            "const_type=$const_type",
            "value=" . (defined $value ? $value : 'undef'),
            (defined $flags ? "flags=$flags" : ()));
    }
}
