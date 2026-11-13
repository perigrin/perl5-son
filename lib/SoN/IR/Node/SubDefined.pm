# ABOUTME: SubDefined node -- `defined &NAME` asked where the program runs: the answer
# ABOUTME: as compiled, and the graphs whose run may change it (the backend decides).
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

class SoN::IR::Node::SubDefined :isa(SoN::IR::Value) {
    # The sub's full name (Stash::name).
    field $name   :param :reader;
    # Whether it is defined as the program compiled (1 or '').
    field $answer :param :reader;
    # The graphs (subs, main::__PROGRAM__) holding an `undef &`, a glob bind
    # or a string eval that may change it: the answer holds unless one runs.
    field $unless :param :reader = [];

    method operation() { 'SubDefined' }

    method content_hash() {
        return join('|', 'SubDefined', "name=$name", 'answer=' . ( $answer ? 1 : 0 ),
            'unless=' . join(',', @$unless), $self->_serialize_inputs());
    }
}
