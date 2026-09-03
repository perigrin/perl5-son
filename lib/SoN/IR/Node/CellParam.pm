# ABOUTME: The cell a closure body receives for one captured variable.
# ABOUTME: A DISTINCT node from Parameter, which means a positional argument.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Access;

# NOT `Parameter` WITH A FLAG, and the reason is a consumer-side one. Parameter
# means "positional argument N of this sub's signature" and lowers to that. A
# capture is not positional, comes from no argument list, and has no declared
# index.
#
# A FLAG WOULD MAKE ONE SPELLING MEAN TWO THINGS, so every existing consumer of
# Parameter would need a check it does not currently do -- and the ones that
# forget get a capture where they expect an argument, silently. A distinct node
# kind makes that same consumer fail on an unknown op instead. Refusal over
# miscompile.
#
# `index` orders the captures within one closure so the caller's cell list and
# the body's reads agree; `name` is the source variable, for diagnostics.
class SoN::IR::Node::CellParam :isa(SoN::IR::Node::Access) {
    field $index :param :reader = 0;
    field $name  :param :reader = undef;

    method operation() { 'CellParam' }

    method content_hash() {
        return join('|', 'CellParam', "index=$index",
            (defined $name ? "name=$name" : ()),
            $self->_serialize_inputs());
    }
}
