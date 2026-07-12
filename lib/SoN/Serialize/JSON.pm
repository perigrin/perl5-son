# ABOUTME: Serialize/deserialize SoN::IR::Graph instances to/from JSON.
# ABOUTME: Provides to_json(\%named_graphs) and from_json($json_string) as exportable subs.

package SoN::Serialize::JSON;

use v5.42.0;
use utf8;
use Exporter 'import';

our @EXPORT_OK = qw(to_json from_json);

use JSON::PP ();
use SoN::IR::Graph;
use SoN::IR::NodeFactory;

# CFG node operations — these carry control tokens and are never hash-consed.
my %CFG_OPS = map { $_ => 1 } qw(Start Return Unwind If Proj Region Loop);

# -----------------------------------------------------------------------
# _is_cfg($node) — true if the node is a CFG node
# -----------------------------------------------------------------------
sub _is_cfg ($node) {
    return exists $CFG_OPS{ $node->operation };
}

# -----------------------------------------------------------------------
# _extract_fields($node, \%id_remap) — returns a hashref of extra fields
# for nodes that carry them, or undef if no extra fields.
# id_remap is needed for Phi whose region field holds a node reference.
# -----------------------------------------------------------------------
sub _extract_fields ($node, $id_remap) {
    my $op = $node->operation;

    if ($op eq 'Constant') {
        return {
            const_type => $node->const_type,
            value      => defined $node->value ? "${\$node->value}" : undef,
        };
    }
    if ($op eq 'Call') {
        return {
            dispatch_kind => $node->dispatch_kind,
            name          => $node->name,
            # The statically-known class for a method dispatch (Class->new).
            ( defined $node->class_name
                ? ( class_name => $node->class_name )
                : () ),
            # Constructor :param keys parallel to the value inputs.
            ( defined $node->param_names
                ? ( param_names => $node->param_names )
                : () ),
            # A void statement-effect call leads with its control input.
            ( $node->is_stmt_effect
                ? ( is_stmt_effect => JSON::PP::true )
                : () ),
        };
    }
    if ($op eq 'Assign' && $node->is_stmt_effect) {
        # An element-store Assign is a statement effect and leads with its
        # control input (mirrors the void-call contract).
        return { is_stmt_effect => JSON::PP::true };
    }
    if ($op eq 'Phi') {
        return {
            region => $id_remap->{ $node->region->id },
        };
    }
    if ($op eq 'Proj') {
        return { index => $node->index };
    }
    if ($op eq 'PadAccess') {
        return {
            targ    => $node->targ,
            varname => $node->varname,
        };
    }
    if ($op eq 'FieldAccess') {
        return {
            field_index => $node->field_index,
            field_stash => $node->field_stash,
        };
    }
    if ($op eq 'StashAccess') {
        return {
            stash_name => $node->stash_name,
            var_name   => $node->var_name,
        };
    }
    if ($op eq 'CompoundAssign') {
        return { op => $node->op };
    }
    if ($op eq 'PostfixDeref') {
        return { sigil => $node->sigil };
    }
    if ($op eq 'RegexMatch') {
        return {
            pattern => $node->pattern,
            flags   => $node->flags,
        };
    }
    if ($op eq 'RegexSubst') {
        return {
            pattern     => $node->pattern,
            replacement => $node->replacement,
            flags       => $node->flags,
        };
    }
    if ($op eq 'RegexCapture') {
        return { n => $node->n };
    }
    if ($op eq 'EnvRead') {
        return { key => $node->key };
    }
    if ($op eq 'VarDecl') {
        return { scope => $node->scope };
    }
    return undef;
}

# -----------------------------------------------------------------------
# _serialize_graph($graph) — returns a Perl data structure for one graph.
# -----------------------------------------------------------------------
sub _serialize_graph ($graph) {
    my $topo_nodes = $graph->nodes;

    # Build positional ID remap: node->id => positional index (0, 1, 2, ...)
    my %id_remap;
    for my ($pos, $node) (indexed $topo_nodes->@*) {
        $id_remap{ $node->id } = $pos;
    }

    # Emit each node
    my @nodes;
    for my $node ($topo_nodes->@*) {
        my $pos    = $id_remap{ $node->id };
        my @inputs = map { $id_remap{ $_->id } } $node->inputs->@*;
        my $fields = _extract_fields($node, \%id_remap);

        my %entry = (
            id     => $pos,
            op     => $node->operation,
            inputs => \@inputs,
        );
        $entry{cfg}    = JSON::PP::true  if _is_cfg($node);
        $entry{fields} = $fields         if defined $fields;
        if (defined $node->stamp) {
            $entry{stamp} = $node->stamp->type;
        }
        # A loop-header condition carries a control edge to its Loop (op-agnostic,
        # emitted as a node-id reference the loader demotes to control_in).
        if (defined $node->loop_control) {
            $entry{loop_control} = $id_remap{ $node->loop_control->id };
        }

        push @nodes, \%entry;
    }

    # Find start node positional ID
    my $start_pos = $id_remap{ $graph->start->id };

    # Find return node positional IDs
    my @return_pos = map { $id_remap{ $_->id } } $graph->returns->@*;

    return {
        nodes   => \@nodes,
        start   => $start_pos,
        returns => \@return_pos,
    };
}

# -----------------------------------------------------------------------
# to_json(\%named_graphs) — serialize named graphs to a JSON string.
# -----------------------------------------------------------------------
sub to_json ($named_graphs, $classes = undef) {
    my %methods;
    for my $name (sort keys $named_graphs->%*) {
        $methods{$name} = _serialize_graph($named_graphs->{$name});
    }

    my $data = {
        version => 1,
        source  => undef,
        methods => \%methods,
    };

    # The declarative class section (4c): name, parent, fields, method-refs.
    # Chalk's loader replays it through the MOP declare_*/seal API.
    $data->{classes} = $classes if defined $classes && %$classes;

    return JSON::PP->new->canonical->pretty->encode($data);
}

# -----------------------------------------------------------------------
# _deserialize_graph($method_data) — rebuild a SoN::IR::Graph from data.
# -----------------------------------------------------------------------
sub _deserialize_graph ($method_data) {
    my $factory   = SoN::IR::NodeFactory->new();
    my @node_data = $method_data->{nodes}->@*;

    # The serializer's topological order guarantees inputs are created
    # before consumers for every edge EXCEPT a loop Phi's back-edge:
    # Graph::nodes cuts exactly that edge (the Phi<->back-edge data cycle
    # forces one forward reference in any order), so a loop Phi's inputs[1]
    # may point forward. Such a Phi is constructed with its init input only
    # and the back-edge is wired via set_backedge once every node exists --
    # the same defer-patch the Chalk loader performs.

    my @nodes;  # positional array of created node objects
    my @backedge_patches;  # [phi_position, backedge_index] deferred wirings

    for my $nd (@node_data) {
        my $op     = $nd->{op};
        my $fields = $nd->{fields} // {};
        my $is_cfg = $nd->{cfg}    // 0;

        # Resolve inputs from already-created nodes
        my @inputs = map { $nodes[$_] } ($nd->{inputs} // [])->@*;

        # Build the argument hash, with inputs and any extra fields
        my %args = (inputs => \@inputs);

        # Merge extra fields based on op type
        if ($op eq 'Constant') {
            $args{value}      = $fields->{value};
            $args{const_type} = $fields->{const_type} if exists $fields->{const_type};
        }
        elsif ($op eq 'Call') {
            $args{dispatch_kind} = $fields->{dispatch_kind};
            $args{name}          = $fields->{name};
            $args{class_name}    = $fields->{class_name}
                if exists $fields->{class_name};
            $args{param_names}   = $fields->{param_names}
                if exists $fields->{param_names};
            $args{is_stmt_effect} = true
                if $fields->{is_stmt_effect};
        }
        elsif ($op eq 'Assign') {
            $args{is_stmt_effect} = true
                if $fields->{is_stmt_effect};
        }
        elsif ($op eq 'Phi') {
            $args{region} = $nodes[ $fields->{region} ];
            my @idx = ($nd->{inputs} // [])->@*;
            if (@idx == 2 && $idx[1] >= @nodes) {
                push @backedge_patches, [ scalar @nodes, $idx[1] ];
                $args{inputs} = [ $inputs[0] ];
            }
        }
        elsif ($op eq 'Proj') {
            $args{index} = $fields->{index};
        }
        elsif ($op eq 'PadAccess') {
            $args{targ}    = $fields->{targ};
            $args{varname} = $fields->{varname};
        }
        elsif ($op eq 'FieldAccess') {
            $args{field_index} = $fields->{field_index};
            $args{field_stash} = $fields->{field_stash};
        }
        elsif ($op eq 'StashAccess') {
            $args{stash_name} = $fields->{stash_name};
            $args{var_name}   = $fields->{var_name};
        }
        elsif ($op eq 'CompoundAssign') {
            $args{op} = $fields->{op};
        }
        elsif ($op eq 'PostfixDeref') {
            $args{sigil} = $fields->{sigil};
        }
        elsif ($op eq 'RegexMatch') {
            $args{pattern} = $fields->{pattern};
            $args{flags}   = $fields->{flags} // '';
        }
        elsif ($op eq 'RegexSubst') {
            $args{pattern}     = $fields->{pattern};
            $args{replacement} = $fields->{replacement};
            $args{flags}       = $fields->{flags} // '';
        }
        elsif ($op eq 'EnvRead') {
            $args{key} = $fields->{key};
        }
        elsif ($op eq 'VarDecl') {
            $args{scope} = $fields->{scope};
        }

        my $node;
        if ($is_cfg) {
            $node = $factory->make_cfg($op, %args);
        }
        else {
            $node = $factory->make($op, %args);
        }

        # Restore a loop condition's control edge to its Loop. The Loop always
        # precedes the condition in topo order (the condition consumes the header
        # Phi that regions the Loop), so this is a backward reference wired inline.
        $node->set_loop_control($nodes[ $nd->{loop_control} ])
            if defined $nd->{loop_control};

        push @nodes, $node;
    }

    # Wire the deferred loop-Phi back-edges now that every node exists.
    for my $patch (@backedge_patches) {
        my ($phi_idx, $val_idx) = @$patch;
        $nodes[$phi_idx]->set_backedge($nodes[$val_idx]);
    }

    my $start   = $nodes[ $method_data->{start} ];
    my @returns = map { $nodes[$_] } $method_data->{returns}->@*;

    return SoN::IR::Graph->new(start => $start, returns => \@returns);
}

# -----------------------------------------------------------------------
# from_json($json_string) — deserialize JSON to named graphs.
# -----------------------------------------------------------------------
sub from_json ($json_string) {
    my $data    = JSON::PP->new->decode($json_string);
    my %graphs;
    for my $name (sort keys $data->{methods}->%*) {
        $graphs{$name} = _deserialize_graph($data->{methods}{$name});
    }
    return \%graphs;
}

1;
