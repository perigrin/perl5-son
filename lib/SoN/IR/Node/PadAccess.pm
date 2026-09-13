# ABOUTME: IR node for accessing a lexical pad slot by target index and variable name.
# ABOUTME: Used to represent $x, @arr, %hash style variable reads in the Sea of Nodes graph.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Access;

class SoN::IR::Node::PadAccess :isa(SoN::IR::Node::Access) {
    field $targ    :param :reader;
    # THE PARTS, NOT THE BLOB. This carried the whole spelling as one string
    # ('@a'), which forced every consumer to re-parse it -- two hand-rolled
    # parsers existed for the same string, `substr($v, 0, 1)` in the producer
    # and `s/\A[\@\%]//` in the deparse emitter.
    #
    # perl's own terms (Symbol.pm): `qualify` turns "symbol names" into
    # qualified "variable names", and `qualify("x")` is "main::x" -- NO SIGIL,
    # because the symbol table is sigil-free. The sigil selects a slot WITHIN
    # the glob, which is why $x and @x share one entry.
    field $sigil  :param :reader = undef;
    field $symbol :param :reader = undef;

    method operation() { 'PadAccess' }

    method content_hash() {
        # Identity is the variable name plus inputs. `targ` (the pad-slot index)
        # is CV-local and unstable across compilation units, so it is NOT
        # identity-bearing: two semantically identical reads at different pad
        # indices must hash-cons together. `targ` is retained as a field for
        # diagnostics / round-trip only (no consumer reads it behaviorally;
        # PadAccess resolves to its VarDecl via inputs[0]).
        return join('|', 'PadAccess', "sigil=$sigil", "symbol=$symbol",
            $self->_serialize_inputs());
    }
}
