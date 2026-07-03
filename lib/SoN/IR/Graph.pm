# ABOUTME: Container for a complete SoN computation graph.
# ABOUTME: Holds Start/Return nodes and provides topological iteration.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Graph 0.01 {
    field $start   :param :reader;
    field $returns :param :reader = [];
    field $source  :param :reader = undef;

    # Topological sort: visit all nodes reachable from returns,
    # ordered so that all inputs of a node are visited before it.
    method nodes () {
        my @order;
        my %visited;
        my @worklist;

        # Collect all return nodes and start
        push @worklist, $start;
        push @worklist, $returns->@*;

        # BFS to find all reachable nodes
        my @all;
        my %seen;
        while (my $node = shift @worklist) {
            next if $seen{$node->id}++;
            push @all, $node;
            push @worklist, $node->inputs->@*;
            push @worklist, $node->consumers->@*;
        }

        # Topological sort via DFS post-order
        my %temp;
        my $visit;
        $visit = sub ($n) {
            return if $visited{$n->id};
            return if $temp{$n->id}; # cycle (loops)
            $temp{$n->id} = 1;
            my @ins = $n->inputs->@*;
            # A loop header Phi's back-edge (inputs[1]) is the cycle-closing
            # edge. Cutting exactly it here makes this order a true
            # topological order of the backedge-cut DAG, so the serializer's
            # only forward references are the sanctioned Phi backedges (which
            # the Chalk loader defer-patches). Merge Phis (Region region)
            # keep their full input order.
            if ($n->operation eq 'Phi' && $n->region->operation eq 'Loop') {
                @ins = grep { defined } $ins[0];
            }
            for my $input (@ins) {
                $visit->($input);
            }
            delete $temp{$n->id};
            $visited{$n->id} = 1;
            push @order, $n;
        };

        for my $node (@all) {
            $visit->($node);
        }

        return \@order;
    }

    # Lookup a node by id
    method node_by_id ($target_id) {
        for my $node ($self->nodes->@*) {
            return $node if $node->id eq $target_id;
        }
        return undef;
    }
}

1;
