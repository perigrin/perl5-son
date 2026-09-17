# ABOUTME: Writes a value into a package (stash) variable, yielding a new memory version.
# ABOUTME: This is what makes one sub's write to a global visible to another sub's read.

use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

# inputs are [entry, value, memory]. The node becomes the new memory version,
# so a later EntryDef read -- in this sub, in another sub, or at program level
# -- observes the write.
#
# A PAD SLOT DOES NOT NEED THIS AND A PACKAGE VARIABLE DOES. A lexical is
# private to its sub, so rebinding the SSA scope key IS the semantics. A
# package variable is reachable from every sub in the program, so a write here
# and a read there are ordered only if they share a memory chain. Measured
# before this node existed:
#
#     our $g = "a";
#     sub peek { return $g }
#     sub poke { $g = "changed" }
#     print peek(); poke(); print peek();
#       perl : a then changed
#       graph: main::poke was Start, Constant, Return -- no store at all, and
#              main::peek returned a bare EntryDef with no memory input, so
#              both peek() calls were the same node.
#
# Modelled on CellWrite, which solved this exact problem for closure captures.
# The aggregate side never needed it: `push @a, 1` is a Call over
# [EntryDef, value, memory] and the push IS the store. A scalar assignment has
# no builtin op to carry it.
#
# NEVER HASH-CONSED, for CellWrite's reason: two writes of the same value to
# the same variable are two distinct events.
# A BINDING IS NOT A STORE, and the wire has to say which. `$g = \@a` puts a
# REFERENCE in the scalar slot; `*g = \@a` makes the NAME `@g` refer to `@a`.
# Both advance the memory chain over a stash entry, so the node kind alone
# cannot separate them -- and rendered as a store, a binding is a wrong answer
# rather than an imprecise one: measured, `*crackers = \@SRC; print "@crackers"`
# printed nothing where perl prints "1 2 3".
#
# The flag rides on the WRITE rather than the entry because it describes the
# EVENT, not the variable: the same `@crackers` can be bound once and stored
# into afterwards, and the entry must stay one hash-consed node for both.
class SoN::IR::Node::EntryWrite :isa(SoN::IR::Value) {
    my $write_counter = 0;
    field $write_id :reader;
    field $binds :param :reader = 0;

    ADJUST { $write_id = $write_counter++; }

    method operation() { 'EntryWrite' }

    method content_hash() {
        return join('|', 'EntryWrite', "write_id=$write_id",
            $self->_serialize_inputs());
    }
}
