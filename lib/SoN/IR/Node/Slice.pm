# ABOUTME: Slice operation node in the Chalk IR.
# ABOUTME: Aggregate data node taking indices then a container, producing a slice.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Aggregate;

class SoN::IR::Node::Slice :isa(SoN::IR::Node::Aggregate) {
    # INPUTS ARE [indices..., container], container LAST and exactly one --
    # measured on aslice (`@a[0,2]` -> Slice(0, 2, ArrayLiteral)) and hslice
    # (`@h{'k1','k2'}` -> Slice('k1', 'k2', HashLiteral)).
    #
    # A LIST SLICE HAS NO CONTAINER NODE. `(qw(p q r))[1]` slices a flat list
    # of values rather than a named aggregate, so its inputs are
    # [indices..., values...] and NEITHER length is recoverable from the
    # other. index_count says where the split falls.
    #
    # Zero means the container form: every input but the last is an index.
    # That keeps an aslice/hslice node's wire byte-identical to before.
    field $index_count :param :reader = 0;

    method operation() { 'Slice' }
}
