# ABOUTME: CFG loop header node for a Chalk computation graph.
# ABOUTME: Holds the entry control and a mutable backedge slot set after the loop body is built.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::Loop :isa(SoN::IR::Node) {
    # Post-construct merge point. The loop-statement actions
    # (WhileStatement / ForeachStatement / PostfixModifier loop form)
    # construct a Region from the exit Proj after the loop body is
    # done; storing the reference here lets Block's control-chain
    # fixup advance past the Loop without rediscovering it from
    # annotations.
    field $region :reader = undef;

    # WHEN THE LOOP'S BOUND IS EVALUATED: 'entry' or 'each'.
    #
    # perl's loop forms disagree, and the difference is observable --
    # measured on 5.42.0:
    #
    #     $n=2; foreach my $i (1..$n) { $n = 10; ... }    2 iterations
    #     $n=2; for ($i=0; $i<$n; $i++) { $n = 4; ... }   4 iterations
    #
    # A foreach evaluates its endpoints ONCE, when the loop is entered, and
    # iterates the fixed list that produces. A `while` and a C-style `for`
    # run their condition every pass.
    #
    # A CONSUMER CANNOT DERIVE THIS. Three derivations were tried and none
    # separated the forms: reaching a loop Phi (blind to package variables,
    # whose updates ride the memory chain rather than SSA), whether the body
    # writes the variable (true of both), and which memory version the
    # condition reads (both read the pre-loop write). The producer knows --
    # _translate_foreach_range and the C-style path through
    # _translate_while_loop are separate translators -- so it says.
    #
    # It matters because hoisting the bound to a temporary is CORRECT for
    # 'entry' and a non-terminating loop for 'each'.
    field $bound :param :reader = 'each';

    method operation() { 'Loop' }

    # CFG nodes carry their control input in inputs[0] (entry_ctrl
    # for Loop), not in the base $control_in field. Override the
    # reader so a walker that calls $node->control_in() gets a
    # consistent answer across node types. Without this override,
    # the base reader would return the unset $control_in field
    # (undef) even though the Loop's entry control is live at
    # inputs[0].
    method control_in() { return $self->inputs->[0] }

    method set_backedge_ctrl($ctrl) {
        my $old = $self->inputs()->[1];
        $old->remove_consumer($self) if defined $old;
        $self->inputs()->[1] = $ctrl;
        $ctrl->add_consumer($self) if defined $ctrl;
    }

    # Late-binding setter for the post-Loop merge Region. Also
    # installs the back-pointer Region.head → this Loop so the
    # scheduler can jump past the Region in the effect chain.
    method set_region($r) {
        $region = $r;
        $r->set_head($self) if defined $r && $r->can('set_head');
        return;
    }

    # Late-binding setter for the entry control input (inputs[0]).
    # Mirrors If::set_control_in. Called by Block's control-chain
    # fixup pass to rewire the Loop's entry to the actual chain
    # predecessor at statement-list position.
    method set_control_in($ctrl) {
        my $old = $self->inputs()->[0];
        $old->remove_consumer($self) if defined $old;
        $self->inputs()->[0] = $ctrl;
        $ctrl->add_consumer($self) if defined $ctrl;
        return;
    }
}
