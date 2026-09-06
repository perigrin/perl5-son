# ABOUTME: IR node for `delete` -- remove a key or index from a container, yielding its value.
# ABOUTME: Mutates, so it advances the memory chain rather than merely reading it.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

# DELETE MUTATES AND YIELDS. It removes the key and returns the value that was
# there, so it is both a store and a load, and the graph has to say both.
#
# INPUTS ARE [container, key, memory], the same three `exists` carries and for
# the same reason: the container is what the removal is ABOUT, and the memory
# input orders it against other accesses. The OpMap gave `delete` a pop_count of
# 1, so it took the KEY alone -- the container stayed on the stack and the node
# reached the wire with neither container nor memory:
#
#     my %h=(a=>1,b=>2); delete $h{a}; print defined($h{a}) ? "y" : "n"
#       perl : n
#       before: Call(delete, Constant "a"), and the later read still threaded
#               to MemStart, so the graph computed "y"
#
# `exists` had exactly this defect (mapped onto Defined, and onto the key rather
# than the slot) and its fix is the template this follows.
#
# IT ADVANCES MEMORY, which is what separates it from Exists. A later read must
# thread to the Delete, not past it, or the removal is invisible -- the silent
# miscompile the refusal here existed to prevent. The same contract
# push/unshift/splice are held to.
#
# THE STAMP IS THE ELEMENT TYPE, NOT Boolean. `delete` yields the value removed,
# so `my $v = delete $h{a}` binds that value; a missing key yields undef, which
# is why a caller that cannot narrow the element type leaves this Unknown rather
# than guessing.
class SoN::IR::Node::Delete :isa(SoN::IR::Value) {
    # Never hash-consed: two deletes of the same key from the same container are
    # DIFFERENT removals (the second finds nothing), so they must stay distinct
    # nodes even with identical inputs. The counter is what keeps them apart,
    # the same device CellWrite and EntryWrite use.
    my $delete_counter = 0;
    field $delete_id :reader;

    ADJUST { $delete_id = $delete_counter++; }

    method operation() { 'Delete' }

    method content_hash() {
        return join('|', 'Delete', "delete_id=$delete_id",
            $self->_serialize_inputs());
    }
}

1;
