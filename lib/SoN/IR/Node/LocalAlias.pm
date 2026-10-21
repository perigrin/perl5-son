# ABOUTME: A foreach pass aliasing a package scalar to its element for the pass: `\local $_ = \$a[$i]`.
# ABOUTME: Lets a callee read or write the topic by name; restored where the pass's block ends.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

class SoN::IR::Node::LocalAlias :isa(SoN::IR::Value) {
    # inputs: [reference to the element, or undef over a hole]. Never
    # hash-consed: each pass's alias is its own statement.
    my $alias_counter = 0;
    field $alias_id :reader;
    field $name :param :reader = '_';

    ADJUST { $alias_id = $alias_counter++; }

    method operation() { 'LocalAlias' }

    method content_hash() {
        return join('|', 'LocalAlias', "alias_id=$alias_id", "name=$name",
            $self->_serialize_inputs());
    }
}

1;
