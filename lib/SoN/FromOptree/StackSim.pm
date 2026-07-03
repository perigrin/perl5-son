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
    # The most recent regex match node; $N capture reads resolve to it.
    field $last_match :reader;

    method push_node ($node) {
        push @stack, $node;
    }

    method pop_node () {
        die "Stack underflow" unless @stack;
        return pop @stack;
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

    method stack_depth () {
        return scalar @stack;
    }

    method set_control ($node) {
        $control = $node;
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

    # Create a snapshot for branching (deep copy)
    method snapshot () {
        my $copy = SoN::FromOptree::StackSim->new(control => $control);
        $copy->push_node($_) for @stack;
        $copy->push_mark() for @marks;  # approximate
        for my $targ (keys %scope) {
            $copy->define($targ, $scope{$targ});
        }
        $copy->set_last_match($last_match);
        return $copy;
    }

    # Merge two states at a convergence point, creating Phi nodes
    method merge ($other, $factory) {
        my $region = $factory->make_cfg('Region',
            inputs => [$control, $other->control]);

        # Create Phi nodes for scope variables that differ
        my $other_scope = $other->scope_bindings;
        for my $targ (keys %scope) {
            if (exists $other_scope->{$targ}
                && $scope{$targ} != $other_scope->{$targ}) {
                my $phi = $factory->make('Phi',
                    inputs => [$scope{$targ}, $other_scope->{$targ}],
                    region => $region,
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
                );
                push @stack, $phi;
            } else {
                push @stack, $my_top;
            }
        }

        $control = $region;
        return $region;
    }
}

1;
