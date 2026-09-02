# ABOUTME: Virtual stack state machine for optree translation.
# ABOUTME: Tracks SoN node references to reconstruct data flow from stack operations.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::FromOptree::StackSim 0.01 {
    field @stack;
    field @marks;
    field %scope;
    field $control :param :reader;
    # The current aggregate-memory value (memory-SSA): MemStart at entry, a store
    # node after an element store, a Phi at a merge. An element read takes this as
    # its memory input so pre-store and post-store reads are distinct nodes.
    field $memory :param :reader = undef;
    # The most recent regex match node; $N capture reads resolve to it.
    field $last_match :reader;

    method push_node ($node) {
        push @stack, $node;
    }

    method pop_node () {
        die "Stack underflow" unless @stack;
        return pop @stack;
    }

    # The top-of-stack node without removing it (undef if empty). Lets a handler
    # inspect the operand shape before deciding to consume it.
    method peek_node () {
        return @stack ? $stack[-1] : undef;
    }

    method pop_to_mark () {
        die "No mark on mark stack" unless @marks;
        my $mark = pop @marks;
        my @args;
        while (@stack > $mark) {
            unshift @args, pop @stack;
        }
        return \@args;
    }

    method push_mark () {
        push @marks, scalar @stack;
    }

    method has_mark () {
        return scalar @marks;
    }

    # Set the mark positions (stack indices) verbatim, for copying state in snapshot.
    method restore_marks ($positions) {
        @marks = $positions->@*;
    }

    # The stack position of the innermost mark, or 0 when there is none.
    #
    # READ-ONLY, unlike pop_to_mark: a handler that wants the values ABOVE the
    # current mark without claiming the mark itself needs this. Consuming a
    # mark that belongs to an enclosing construct leaves a later handler with
    # none, which surfaces as "No mark on mark stack" -- an internal error
    # rather than an honest GAP.
    method mark_depth () {
        return @marks ? $marks[-1] : 0;
    }

    method stack_depth () {
        return scalar @stack;
    }

    method set_control ($node) {
        $control = $node;
    }

    method set_memory ($node) {
        $memory = $node;
    }

    method set_last_match ($node) {
        $last_match = $node;
    }

    # Scope: immutable-style variable bindings
    method define ($targ, $node) {
        $scope{$targ} = $node;
    }

    method lookup ($targ) {
        return $scope{$targ};
    }

    method scope_bindings () {
        return {%scope};
    }

    # Create a snapshot for branching. Copies the stack values, mark POSITIONS
    # (verbatim -- push_mark would re-record them at the copy's final depth and
    # collapse them all to the top), scope bindings, and last-match reference.
    method snapshot () {
        my $copy = SoN::FromOptree::StackSim->new(control => $control, memory => $memory);
        $copy->push_node($_) for @stack;
        $copy->restore_marks([@marks]);
        for my $targ (keys %scope) {
            $copy->define($targ, $scope{$targ});
        }
        $copy->set_last_match($last_match);
        return $copy;
    }

    # Merge two states at a convergence point, creating Phi nodes. $owner,
    # when given, is the If/Loop node this Region merges the arms of;
    # set_region wires BOTH the forward pointer (owner.region -> this
    # Region, read by the backend's merge-Phi placement) and the back-
    # pointer (Region.head -> owner, read by the control-chain walk) at
    # produce time, so the loader never has to re-derive them from the
    # control_in chain.
    # Walk a control node back to the Proj its arm hangs off, or undef.
    #
    # The Region input records what ran LAST on an arm (the control-chain
    # link); this recovers what the arm STARTED from (its identity). Doing it
    # once here, at construction, replaces a search in every consumer.
    #
    # Bounded by a seen-set: an arm's control chain is acyclic, but a loop
    # back-edge elsewhere in the graph must not turn a shape this cannot
    # classify into a hang -- the failure mode that made an earlier
    # producer-side descent recurse forever on `perl -MO=SoN -e 'sub foo {42}'`.
    #
    # Exposed as SoN::FromOptree::StackSim::arm_proj so FromOptree's
    # single-exit merge can use the SAME walk rather than keeping its own copy.
    # It had one inline (a hand-written "while not Proj, follow control_in"),
    # which is the fourth place this search had been written.
    sub arm_proj ($node) { return _arm_proj($node) }

    sub _arm_proj ($node) {
        my %seen;
        while (defined $node && ref $node) {
            my $id = eval { $node->id };
            last if defined $id && $seen{$id}++;
            my $op = $node->can('operation') ? $node->operation : '';
            return $node if $op eq 'Proj';

            # A NESTED MERGE. Do NOT descend into its arms -- those belong to
            # the inner branch and picking one would attribute this slot to the
            # wrong side. But the merge itself sits on exactly one arm of the
            # OUTER branch, and that arm is recoverable: Region.head is the
            # inner If, whose control_in is the outer Proj. Step THROUGH the
            # merge to its head rather than stopping.
            #
            # Stopping here was correct for a flat branch and wrong for a nested
            # one: the outer Phi's arm IS the inner Region, so the walk returned
            # undef and merge()'s all-or-nothing guard dropped predecessors for
            # the outer merge entirely. The backend then fell back to the Region
            # search, which paired the arms backwards and emitted a phi naming a
            # value defined in the merge block as arriving from the else block --
            # rejected by lli as "Instruction does not dominate all uses!".
            if ($op eq 'Region') {
                my $head = $node->can('head') ? $node->head : undef;
                last unless defined $head && ref $head;
                $node = $head->can('control_in') ? $head->control_in : undef;
                next;
            }

            $node = $node->can('control_in') ? $node->control_in : undef;
        }
        return undef;
    }

    method merge ($other, $factory, $owner = undef) {
        # The Region input stays the arm's LAST control node -- it is the
        # control-chain link, and substituting the Proj here severs the effects
        # behind it (measured: dropped a Print, broke
        # t/from-optree-bare-block.t).
        my $region = $factory->make_cfg('Region',
            inputs => [$control, $other->control]);
        $owner->set_region($region) if defined $owner;

        # Arm IDENTITY, recorded separately so the consumer does not have to
        # search for it. Supplied only when BOTH arms resolve to a Proj: a
        # partial list would be worse than none, since the consumer pairs by
        # position and a missing entry would silently mis-pair.
        my $mine_proj   = _arm_proj($control);
        my $theirs_proj = _arm_proj($other->control);
        my @preds = (defined $mine_proj && defined $theirs_proj)
            ? ($mine_proj, $theirs_proj)
            : ();

        # Create Phi nodes for scope variables that differ
        my $other_scope = $other->scope_bindings;
        for my $targ (keys %scope) {
            if (exists $other_scope->{$targ}
                && $scope{$targ} != $other_scope->{$targ}) {
                my $phi = $factory->make('Phi',
                    inputs => [$scope{$targ}, $other_scope->{$targ}],
                    region => $region,
                    (@preds ? (predecessors => [@preds]) : ()),
                );
                $scope{$targ} = $phi;
            }
        }

        # Merge stack: create Phi for differing stack positions
        # (for expressions on the stack at branch point)
        if (@stack && $other->stack_depth) {
            my $other_top = $other->pop_node;
            my $my_top = pop @stack;
            if ($my_top != $other_top) {
                my $phi = $factory->make('Phi',
                    inputs => [$my_top, $other_top],
                    region => $region,
                    (@preds ? (predecessors => [@preds]) : ()),
                );
                push @stack, $phi;
            } else {
                push @stack, $my_top;
            }
        }

        # Merge memory (memory-SSA): if the two arms' memory differs (a store
        # happened in one arm), create a memory Phi over the region, mirroring the
        # scope-var merge. Straight-line code never reaches here. NOTE (phase 2a):
        # the producer builds the memory Phi, but its BACKEND lowering is phase
        # 2b -- a branch-with-store read that reaches a memory Phi is an honest
        # backend GAP until then, never a miscompile.
        my $other_memory = $other->memory;
        if (defined $memory && defined $other_memory && $memory != $other_memory) {
            $memory = $factory->make('Phi',
                inputs => [$memory, $other_memory],
                region => $region,
                (@preds ? (predecessors => [@preds]) : ()),
            );
        }

        $control = $region;
        return $region;
    }
}

1;
