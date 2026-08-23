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
# THE STAMP IS REQUIRED, AND `Unknown` IS THE WAY TO SAY "UNKNOWN". A Value
# node exists to define a value, and a value has a type, so an undef stamp is
# not a state a Value node may be in. A construction site that omits it dies
# in ADJUST rather than quietly producing an untyped value node -- the same
# loud-failure property the class split itself has.
#
# The check is an ADJUST rather than a redeclared `field $stamp :param` here.
# `stamp` already lives on SoN::IR::Node (control nodes accept the param on
# the deserialization path, and set_stamp patches loop-header Phis after the
# back-edge is known). Redeclaring it in this subclass would create a SECOND
# field of the same name: set_stamp would mutate the parent's copy while a
# reader resolved to the child's, and the two would silently diverge. One
# field, one reader, one setter; the CONSTRAINT is what belongs to Value.
#
# This closes meaning (2) above. What remains is `Unknown`, which is an ANSWER
# ("asked, genuinely cannot tell") rather than an absence: a real member of
# the lattice with defined join and meet, so downstream inference can compute
# with it instead of having to special-case a hole. Subscript and Call are the
# honest cases -- what an index yields or what a callee returns is not
# knowable at construction, and `Unknown` says exactly that.
#
# `Unknown` must not become the lazy default at a site that KNOWS. Measured
# before this was enforced, 19% of constructed Value nodes carried no stamp,
# and the set was not arbitrary: ArrayRef, HashRef, RefType, Defined and
# RegexMatch all have a type fixed by the node kind alone. Those were defects.
# Stamping them `Unknown` would be non-undef and still wrong.
#
# IT IS A STAMP, NOT A TYPE, AND THE NAME IS DELIBERATE. A stamp is an
# abstract-interpretation fact ABOUT a value (C2's and Graal's sense), of
# which the type is one component. Graal's stamps also carry non-null, exact
# type, and integer bounds/known-bits, and a stamp is where its refinement
# passes accumulate what they prove -- narrowing along a branch, folding a
# guard's implication back into the value, joining to empty to show a branch
# is dead.
#
# Today SoN::IR::Stamp holds only `type`, because no pass here produces the
# other components yet -- stamps come from the optree walk reading SV flags
# and are joined at Phis. So the object currently IS a type object, and
# `SoN::IR::Type` would be the accurate name for what exists. It is called
# Stamp anyway: that machinery is intended, and renaming twice (to Type now,
# back to Stamp when refinement lands) costs more than naming it for what it
# is meant to become. Do not "correct" this to Type.
#
# The practical consequence is that a predicate over a stamp should be named
# for the QUESTION, not for typedness -- see _is_narrowed in FromOptree. Once
# a stamp can be informative while its type is still Unknown, "is it typed"
# stops being the same question as "does it tell us anything".
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

    ADJUST {
        die ref($self) . ": a Value node must carry a stamp"
            . " (use 'Unknown' when the type is genuinely not known)\n"
            unless defined $self->stamp;
    }
}

1;
