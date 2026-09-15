# ABOUTME: CFG merge node for a Chalk computation graph.
# ABOUTME: Joins multiple control-flow paths into one; inputs are Proj or other control nodes.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::Region :isa(SoN::IR::Node) {
    # Back-pointer to the CFG node whose control flow this Region
    # merges (an If for if/else joins, a Loop for loop-exit joins).
    # Set by that node's set_region() side-effect. The scheduler
    # uses this to traverse past a Region in the effect chain:
    # `Return.inputs[0] = Region`, but Region has no single chain
    # predecessor (its inputs are Projs from divergent branches), so
    # the scheduler reads $region->head() and continues from
    # $head->control_in().
    field $head :reader = undef;

    # A BLOCK EVAL'S ENTRY -- the control node the protected body began after.
    #
    # The Region records where an eval JOINS; without this, nothing records
    # where it BEGAN, and the statements it protects are indistinguishable
    # from those before it. Measured on
    # `our $g=0; our $h=0; $h=5; if (eval { $g = 1; 1 })`:
    #
    #     Region(23) in=[12]
    #     chain back: EntryWrite 12, 11, 10, 9, Start
    #
    # Four stores chain to Start and only the LAST is inside the eval. A
    # consumer cannot delimit the body, and a block eval's whole meaning is
    # WHICH statements it protects.
    #
    # Unset for a string eval, whose Region's input IS the eval -- one node,
    # nothing to delimit.
    field $eval_entry :reader = undef;

    method operation() { 'Region' }

    method set_eval_entry($node) {
        $eval_entry = $node;
        return;
    }

    method set_head($node) {
        $head = $node;
        return;
    }
}
