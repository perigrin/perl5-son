# ABOUTME: Structural comparison of two SoN IR graphs.
# ABOUTME: Produces diffs by matching data nodes by hash and CFG nodes by topology.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::Compare 0.01 {

    # Compare two graphs structurally
    method diff ($graph_a, $graph_b) {
        my @nodes_a = $graph_a->nodes->@*;
        my @nodes_b = $graph_b->nodes->@*;
        my @diffs;

        # Build topology maps: position in topological order
        my %topo_a = map { $nodes_a[$_]->id => $_ } 0 .. $#nodes_a;
        my %topo_b = map { $nodes_b[$_]->id => $_ } 0 .. $#nodes_b;

        # For data nodes: match by content hash
        # For CFG nodes: match by topological position + operation
        my %matched_b;

        for my $i (0 .. $#nodes_a) {
            my $a = $nodes_a[$i];
            my $found = false;

            if ($i <= $#nodes_b) {
                my $b = $nodes_b[$i];
                if ($a->operation eq $b->operation) {
                    $found = true;
                    $matched_b{$i} = 1;

                    # Check inputs match (by position)
                    my @a_inputs = $a->inputs->@*;
                    my @b_inputs = $b->inputs->@*;
                    if (scalar @a_inputs != scalar @b_inputs) {
                        push @diffs, {
                            type   => 'input_count',
                            pos    => $i,
                            op     => $a->operation,
                            a_count => scalar @a_inputs,
                            b_count => scalar @b_inputs,
                        };
                    }

                    # Check stamps match
                    my $sa = $a->stamp;
                    my $sb = $b->stamp;
                    if (defined $sa && defined $sb && $sa->type ne $sb->type) {
                        push @diffs, {
                            type    => 'stamp',
                            pos     => $i,
                            op      => $a->operation,
                            a_stamp => $sa->type,
                            b_stamp => $sb->type,
                        };
                    } elsif (defined $sa != defined $sb) {
                        push @diffs, {
                            type    => 'stamp',
                            pos     => $i,
                            op      => $a->operation,
                            a_stamp => defined $sa ? $sa->type : 'none',
                            b_stamp => defined $sb ? $sb->type : 'none',
                        };
                    }
                }
            }

            unless ($found) {
                push @diffs, {
                    type => 'missing_in_b',
                    pos  => $i,
                    op   => $a->operation,
                };
            }
        }

        # Check for extra nodes in B
        for my $j (0 .. $#nodes_b) {
            unless ($matched_b{$j}) {
                push @diffs, {
                    type => 'missing_in_a',
                    pos  => $j,
                    op   => $nodes_b[$j]->operation,
                };
            }
        }

        return SoN::Compare::Diff->new(diffs => \@diffs);
    }
}

class SoN::Compare::Diff {
    field $diffs :param :reader;

    method is_empty () { return scalar $diffs->@* == 0 }

    method to_text () {
        my @lines;
        for my $d ($diffs->@*) {
            if ($d->{type} eq 'missing_in_b') {
                push @lines, "Missing in B at position $d->{pos}: $d->{op}";
            }
            elsif ($d->{type} eq 'missing_in_a') {
                push @lines, "Extra in B at position $d->{pos}: $d->{op}";
            }
            elsif ($d->{type} eq 'input_count') {
                push @lines, "Input count differs at position $d->{pos} ($d->{op}): "
                    . "$d->{a_count} vs $d->{b_count}";
            }
            elsif ($d->{type} eq 'stamp') {
                push @lines, "Stamp differs at position $d->{pos} ($d->{op}): "
                    . "$d->{a_stamp} vs $d->{b_stamp}";
            }
        }
        return CORE::join("\n", @lines) . "\n";
    }
}

1;
