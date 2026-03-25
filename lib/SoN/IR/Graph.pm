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
            for my $input ($n->inputs->@*) {
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
