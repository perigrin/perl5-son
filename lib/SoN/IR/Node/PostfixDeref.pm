# ABOUTME: Postfix dereference node in the Chalk IR.
# ABOUTME: Carries the sigil (@, %, $) indicating the dereference type.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

class SoN::IR::Node::PostfixDeref :isa(SoN::IR::Value) {
    field $sigil :param :reader;
    # A COPY: `my %p = %$h` bound to the dereference reads the referent as
    # it was at this version, whatever is stored through $h after it. A
    # foreach's dereference, unmarked, is the live array it walks.
    field $copy :param :reader = 0;

    # A SCALAR DEREF MAY DIE (no SCALAR reference there): like a may-die
    # division it names its block eval, its statement's file and line, and
    # whether `strict refs` holds there (without it a string is a name).
    field $eval_id :param :reader = undef;
    field $file    :param :reader = undef;
    field $line    :param :reader = undef;
    field $strict  :param :reader = 0;
    # ...and the package it is in: without strict refs a string there names
    # that package's variable.
    field $package :param :reader = undef;

    method operation() { 'PostfixDeref' }

    method content_hash() {
        return join('|', 'PostfixDeref', "sigil=$sigil", ($copy ? 'copy' : ()), ( defined $line ? ( 'site', $eval_id // '', $file, $line, $strict ? 'strict' : '', $package // '' ) : () ), $self->_serialize_inputs());
    }
}
