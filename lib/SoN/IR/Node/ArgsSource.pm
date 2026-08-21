# ABOUTME: IR node for `@_`, the argument list a caller passes to a sub.
# ABOUTME: Distinct from EntryDef: an argument list, not a name defined outside.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Access;

# `@_` is the ARGUMENT LIST. It is created by the CALLER, and it is dynamically
# scoped to the innermost enclosing sub call -- a bare block or an `if` inside
# the sub sees the same one, and `goto &f` hands the caller's onward.
#
# It rode on StashAccess(main, '_') because `@_` is reachable as the package
# array *main::_. That was true and useless: EntryDef's job after the
# package-scalar SSA migration is the ENTRY DEFINITION -- naming a value defined
# outside this unit, carrying no value of its own. An argument list is not that.
#
# Sharing the node cost a real defect: with identity keyed on name alone, `$_`
# and `@_` hash-consed into ONE node feeding both a `shift @_` and a RegexMatch
# subject. The sigil closed that hazard; this closes the conflation, so
# EntryDef can mean one thing (and be renamed to EntryDef).
#
# NO FIELDS. There is exactly one `@_` per sub invocation, so the node needs no
# name, no stash, and no sigil to distinguish it -- and hash-consing one per
# graph is correct rather than a collision.
class SoN::IR::Node::ArgsSource :isa(SoN::IR::Node::Access) {
    method operation() { 'ArgsSource' }

    method content_hash() {
        return join('|', 'ArgsSource', $self->_serialize_inputs());
    }
}
