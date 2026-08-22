# ABOUTME: IR node for a declared signature parameter, identified by position.
# ABOUTME: Pure and zero-input: a parameter is a value, not a load or an event.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Access;

# A PARAMETER IS A VALUE, NOT A SLOT.
#
# `argelem` previously minted a PadAccess -- perl's STORAGE for the parameter
# rather than the parameter itself -- discarding the position and the sigil that
# the op carries. That is the same layering leak as reading a lexical through
# its pad index: it re-implements perl's implementation instead of expressing
# perl's semantics.
#
# Modelled on TurboFan's Parameter (common-operator.cc, verified verbatim):
#
#     IrOpcode::kParameter, Operator::kPure,     // opcode
#     "Parameter",                               // name
#     1, 0, 0, 1, 0, 0,                          // counts
#     ParameterInfo(index, debug_name));
#
# PURE. Both V8 pipelines agree (TurboFan `Operator::kPure`, Turboshaft
# `OpEffects()`). A parameter read floats, CSEs and hoists. It takes NO inputs:
# it is not a load, and unlike TurboFan's it is not projected off Start either
# -- Turboshaft's ParameterOp is likewise arity 0, with V8's own comment "on the
# callee side a parameter doesn't have an input".
#
# HASH-CONSED BY INDEX. TurboFan's `hash_value(ParameterInfo p)` returns
# `p.index()`, so two reads of parameter 0 are ONE node. Chalk gets the same
# result by putting index (and only index) in the content hash: the NAME is
# debug information and must not split identity, and the SIGIL is a function of
# the index within one signature.
#
# TYPED FROM ITS SIGIL, per parameter, read from `argelem`'s `private` field
# (0 scalar, 2 array, 4 hash). A slurpy is NOT always an array -- `sub f(%h)` is
# a hash. That is the same rule that fixed EntryDef, where `$_` and `@_`
# hash-consed into one node because identity was keyed on name without a sigil.
class SoN::IR::Node::Parameter :isa(SoN::IR::Node::Access) {
    field $index :param :reader;
    field $name  :param :reader = undef;
    field $sigil :param :reader = '$';

    method operation() { 'Parameter' }

    # INDEX ONLY. Two reads of the same parameter must be one node; a name would
    # not change that here, but including it would make identity depend on debug
    # information, and a synthesized parameter with no pad name would then fail
    # to cons with its named twin.
    method content_hash() {
        return join( '|', 'Parameter', "index=$index" );
    }
}
