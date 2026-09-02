# ABOUTME: IR node for `wantarray` -- the CALLSITE's context, read inside the callee.
# ABOUTME: Resolved per-call from the Call node's `want`, not folded at translation.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Access;

# WANTARRAY REPORTS THE CALLER'S CONTEXT, and that is an edge the graph HAS.
# perl makes it a runtime function because an interpreter compiles a sub once
# and cannot see its callers -- a fact about the interpreter, not about a
# graph. Every callsite already carries its own context: entersub's OPf_WANT
# reaches the wire as the Call node's `want` field, and two calls to the same
# sub in different contexts are DISTINCT nodes.
#
# So this is the same shape the multi-value return already uses
# (_list_return_value): the callee carries what it cannot decide, and the
# CALLSITE picks. There the callee emits both readings of its return value;
# here it emits the question, and `want` answers it per call.
#
# MEASURED ON 5.42.0, all three contexts:
#
#     my @l = f()   wantarray is "1"     is_bool TRUE
#     my $s = f()   wantarray is ""      is_bool TRUE
#     f()           wantarray is undef
#
# NO FIELDS AND NO INPUTS. The value depends on the CALL EDGE, not on anything
# in the callee -- there is exactly one `wantarray` question per invocation, so
# hash-consing one per graph is correct rather than a collision. This is the
# same reasoning ArgsSource records for `@_`, and for the same reason: both are
# properties the caller supplies.
class SoN::IR::Node::Wantarray :isa(SoN::IR::Node::Access) {
    method operation() { 'Wantarray' }

    method content_hash() {
        return join('|', 'Wantarray', $self->_serialize_inputs());
    }
}
