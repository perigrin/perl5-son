# ABOUTME: Base class for IR nodes that DEFINE a value, mirroring Chalk::IR::Value.
# ABOUTME: Control nodes stay on SoN::IR::Node and have no value to be asked about.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use SoN::IR::Node;

# A node either defines a value or it does not, and that is a STRUCTURAL fact
# about the node kind, not a property to be filled in.
#
# This is the producer half of the split chalk makes in Chalk::IR::Value. The
# consumer already distinguishes value nodes from control nodes by class; the
# producer could not, so `undef` on a value-carrying field meant three
# unrelated things with no way to tell them apart:
#
#   1. this node produces no value at all   (correct, permanent)
#   2. inference has not run yet            (temporary)
#   3. inference ran and could not decide   (a bug)
#
# Splitting the hierarchy removes meaning (1) from those fields entirely, so an
# undef stamp or representation can only ever be an inference question.
#
# THE PREDICATE IS `$node isa SoN::IR::Value`, never `->can('stamp')`. `can` is
# duck-typing over a NAME and answers true for any class that happens to define
# a `stamp` method for unrelated reasons; `isa` asks the actual question. It is
# also CLOSED -- there is no opt-in-by-defining-a-method escape hatch -- so a
# value node nobody reparents fails by not being recognised as a value, which
# is loud, rather than by silently carrying an untyped field.
#
# THE SPLIT IS NOT ON THE WIRE, AND MUST NOT BE. The serialized form carries
# `op`, and both sides map that name to a class independently. Value-ness is
# therefore DERIVED identically at both ends from data already present. A wire
# field would add a second source of truth for the same fact, turning a
# producer/consumer disagreement from a loud class-structure mismatch into a
# silent data mismatch. The class hierarchy is the mirror; the wire stays as
# it is.
#
# ORTHOGONAL TO EFFECTS. Value-ness and control-reachability are independent
# axes. Assign and CompoundAssign carry effects AND produce values (an
# assignment's result is the stored value, so `$x = $y = 5` works). Being a
# statement does not stop a node being a value.
#
# This split does NOT by itself catch a construct that builds no value AND no
# control -- `goto` is the filed instance, where only the missing control is
# the bug. See docs/plans/2026-08-23-goto-silently-dropped.md in chalk. The
# explicit refusal list in FromOptree's %UNBUILT_OP_GAP remains load-bearing.
class SoN::IR::Value :isa(SoN::IR::Node) {
}

1;
