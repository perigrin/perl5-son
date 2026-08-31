# ABOUTME: print statement node in the Chalk IR: a control-pinned statement effect
# ABOUTME: emitting its value inputs to a filehandle, yielding print's boolean 1.
use 5.42.0;
use utf8;
use experimental 'class';

class SoN::IR::Node::Print :isa(SoN::IR::Node) {
    # An explicit handle (`print $fh ...`, `print STDERR ...`) is INPUT 0, and
    # this says so. Inputs are positional, so a consumer that had to guess
    # would print the handle and write to the string.
    #
    # A FLAG, NOT A HANDLE FIELD: the handle is a VALUE -- a lexical, a glob, a
    # thing an expression produced -- so it belongs in the graph as an operand
    # where it can be typed and traced, not stringified into a field.
    #
    # Whether a target can honor it is T2's question. T1 states the operation.
    field $has_filehandle :param :reader = 0;

    method operation() { 'Print' }

    method content_hash() {
        return join('|', 'Print', "fh=$has_filehandle",
            $self->_serialize_inputs());
    }
}
