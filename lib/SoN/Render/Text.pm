# ABOUTME: Deterministic text rendering of SoN IR graphs.
# ABOUTME: Produces one-node-per-line output for testing and debugging.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::Render::Text 0.01 {

    method render ($graph) {
        my @nodes = $graph->nodes->@*;
        my @lines;

        # Assign display IDs by topological position
        my %display_id;
        my $next = 0;
        for my $node (@nodes) {
            $display_id{$node->id} = $next++;
        }

        for my $node (@nodes) {
            my $did = $display_id{$node->id};
            my $op  = $node->operation;

            # Format inputs as display IDs
            my @input_strs = map { '%' . $display_id{$_->id} } $node->inputs->@*;

            # Format node-specific attributes
            my @attrs;
            if ($node->isa('SoN::IR::Node::Constant')) {
                push @attrs, $node->value // 'undef';
            }
            elsif ($node->isa('SoN::IR::Node::PadAccess')) {
                push @attrs, "targ: " . $node->targ;
                push @attrs, "name: '" . $node->varname . "'";
            }
            elsif ($node->isa('SoN::IR::Node::FieldAccess')) {
                push @attrs, "index: " . $node->field_index;
                push @attrs, "stash: '" . $node->field_stash . "'";
            }
            elsif ($node->isa('SoN::IR::Node::StashAccess')) {
                push @attrs, "stash: '" . $node->stash_name . "'";
                push @attrs, "name: '" . $node->var_name . "'";
            }
            elsif ($node->isa('SoN::IR::Node::Call')) {
                push @attrs, $node->dispatch_kind . ": " . $node->name;
            }
            elsif ($node->isa('SoN::IR::Node::Proj')) {
                push @attrs, "index: " . $node->index;
            }

            my $detail = '';
            if (@attrs || @input_strs) {
                my @parts;
                push @parts, @attrs;
                push @parts, @input_strs;
                $detail = '(' . CORE::join(', ', @parts) . ')';
            }

            my $stamp_str = '';
            if (defined $node->stamp) {
                $stamp_str = ' [' . $node->stamp->type . ']';
            }

            push @lines, sprintf('%%%d = %s%s%s', $did, $op, $detail, $stamp_str);
        }

        return CORE::join("\n", @lines) . "\n";
    }
}

1;
