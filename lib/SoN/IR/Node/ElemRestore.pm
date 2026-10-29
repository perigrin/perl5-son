# ABOUTME: The restore a `local` on a hash or array element makes at its block's exit.
# ABOUTME: Puts back the saved value, or deletes a key that did not exist; a memory version.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

class SoN::IR::Node::ElemRestore :isa(SoN::IR::Value) {
    # inputs: [container, key, saved value, existed, memory]. Never
    # hash-consed: two restores of one element are two writes, as two
    # Deletes are (see Delete).
    my $restore_counter = 0;
    field $restore_id :reader;
    field $kind :param :reader = undef;
    # Made on a `return`'s path: perl's return puts the element back itself.
    field $at_return :param :reader = 0;

    ADJUST { $restore_id = $restore_counter++; }

    method operation() { 'ElemRestore' }

    method content_hash() {
        return join('|', 'ElemRestore', "restore_id=$restore_id",
            (defined $kind ? "kind=$kind" : ()),
            $self->_serialize_inputs());
    }
}

1;
