# ABOUTME: IR node for `exists` -- is this key or index PRESENT in the container?
# ABOUTME: Membership, which is a different question from definedness.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Access;

# MEMBERSHIP IS NOT DEFINEDNESS, and conflating them is a miscompile rather
# than an imprecision. Measured on 5.42.0:
#
#     my %h = (a => 1, u => undef);
#     exists $h{u}    TRUE     the key is present
#     defined $h{u}   false    its value is not
#     exists $h{zz}   false
#
# `exists` was mapped onto the Defined node -- and onto the KEY rather than the
# slot -- so `exists $h{zz}` asked whether the string "zz" is defined, which it
# always is. perl prints the empty string for a missing key; the graph meant 1.
#
# INPUTS ARE [container, key, memory], the same three a Subscript carries. The
# container is what the question is ABOUT and the old mapping could not see it.
# The memory input orders the test against stores, so a preceding delete or
# assignment is observed.
#
# STAMPED Boolean: `is_bool(exists $h{a})` is true, and unlike `print` or
# `open` there is no failure path yielding undef -- exists always answers. So
# Boolean rather than the join(Boolean, Undef) = Scalar those two need.
class SoN::IR::Node::Exists :isa(SoN::IR::Node::Access) {
    method operation() { 'Exists' }

    method content_hash() {
        return join('|', 'Exists', $self->_serialize_inputs());
    }
}
