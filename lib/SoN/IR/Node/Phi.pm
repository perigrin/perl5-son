# ABOUTME: IR Phi node for merging values at CFG join points (Sea of Nodes).
# ABOUTME: Holds a region reference and supports set_backedge for loop back-edge wiring.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

class SoN::IR::Node::Phi :isa(SoN::IR::Value) {
    field $region :param :reader;

    # WHICH PREDECESSOR EACH INCOMING VALUE ARRIVES FROM.
    #
    # inputs[i] pairs with predecessors[i]. Mirrors Chalk::IR::Node::Phi and
    # rides the wire as node indices alongside `region`.
    #
    # A Region's control input cannot answer this: it is the arm's LAST
    # CONTROL NODE, which is the arm's Proj only when the arm is empty of
    # effects. That input is ALSO the control-chain link, so it cannot simply
    # be changed to hold the Proj -- doing so severs the effects behind it
    # (measured: dropped a Print off the chain, broke
    # t/from-optree-bare-block.t). Recording identity here leaves that role
    # untouched.
    #
    # OPTIONAL: a loop Phi pairs with the loop's entry and back edges rather
    # than a predecessor list, so absent reads as "not recorded".
    field $predecessors :param :reader = undef;

    method operation() { 'Phi' }

    method content_hash() {
        return join('|', 'Phi', "region=" . $region->id(), $self->_serialize_inputs());
    }

    method set_backedge($value) {
        my $old = $self->inputs()->[1];
        $old->remove_consumer($self) if defined $old;
        $self->inputs()->[1] = $value;
        $value->add_consumer($self) if defined $value;
    }
}
