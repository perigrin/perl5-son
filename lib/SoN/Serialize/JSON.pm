# ABOUTME: Serialize Chalk::IR::Graph instances (built by B::SoN's FromOptree)
# ABOUTME: to the B::SoN wire JSON format. Provides to_json(\%named_graphs).

package SoN::Serialize::JSON;

use v5.42.0;
use utf8;
use Exporter 'import';

our @EXPORT_OK = qw(to_json);

use JSON::PP ();
use Scalar::Util qw(blessed);
use SoN::FromOptree::EffectMeta;
use Chalk::IR::Serialize::JSON ();

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
            # Chalk::IR::Node::Call has no is_stmt_effect field (the merged
            # type carries per-call identity via the factory instead), so
            # this knowledge lives in the producer-side EffectMeta table.
            ( SoN::FromOptree::EffectMeta::is_stmt_effect($node)
                ? ( is_stmt_effect => JSON::PP::true )
                : () ),
        };
    }
    if ($op eq 'Assign' && SoN::FromOptree::EffectMeta::is_stmt_effect($node)) {
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
    if ($op eq 'Print') {
        # A void Print leads with its control token (inputs[0]); flag it so the
        # loader demotes that leading input to control_in (the void-call
        # contract), leaving inputs = the printed list.
        return (
            SoN::FromOptree::EffectMeta::is_stmt_effect($node)
                ? { is_stmt_effect => JSON::PP::true }
                : undef
        );
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
    # $graph is a Chalk::IR::Graph, but FromOptree builds it by wrapping
    # start+returns at the very end of translate() rather than incrementally
    # merge()-ing every node in as Chalk's own Actions.pm does -- so the
    # Graph's own ->nodes (cache-gated on that membership set) silently
    # drops a node reachable ONLY via consumers() of an already-included
    # node: a while-loop's false-exit Proj (a consumer of Loop with no
    # downstream input reference) or a loop condition (a consumer of the
    # header Phi via EffectMeta's loop_control, not an inputs[] edge).
    # Do the full inputs+consumers BFS ourselves (the pre-unification
    # SoN::IR::Graph::nodes contract), then hand the reachable set to
    # Chalk's shared topo-sort (which also fixes up Phi-region ordering)
    # rather than reimplementing that half.
    my @worklist = ($graph->start, $graph->returns->@*);
    my %seen;
    my @reachable;
    while (my $n = shift @worklist) {
        next unless blessed($n);
        next if $seen{ $n->id }++;
        push @reachable, $n;
        for my $input ($n->inputs->@*) {
            if (ref($input) eq 'ARRAY') {
                push @worklist, $input->@*;
            }
            else {
                push @worklist, $input;
            }
        }
        push @worklist, $n->consumers->@* if $n->can('consumers');
    }
    my $topo_nodes = Chalk::IR::Serialize::JSON::_all_nodes_topo(\@reachable);

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
        # Chalk::IR::Node has no loop_control field, so this knowledge lives
        # in the producer-side EffectMeta table (see is_stmt_effect above).
        my $loop_owner = SoN::FromOptree::EffectMeta::loop_control_of($node);
        if (defined $loop_owner) {
            $entry{loop_control} = $id_remap{ $loop_owner->id };
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

1;
