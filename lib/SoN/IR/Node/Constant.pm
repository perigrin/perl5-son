# ABOUTME: Compile-time constant value in the SoN IR graph.
# ABOUTME: Hash-consed data node carrying a value and type stamp.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Constant :isa(SoN::IR::Node) {
    field $value      :param :reader;
    field $const_type :param :reader = 'string';

    method operation () { 'Constant' }

    method content_hash () {
        my $val_str = defined $value ? $value : 'undef';
        return "Constant|const_type=$const_type|value=$val_str";
    }
}

1;
