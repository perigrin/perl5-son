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

    method operation() { 'PostfixDeref' }

    method content_hash() {
        return join('|', 'PostfixDeref', "sigil=$sigil", ($copy ? 'copy' : ()), $self->_serialize_inputs());
    }
}
