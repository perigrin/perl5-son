# ABOUTME: Serialize SoN::IR::Graph instances (built by B::SoN's FromOptree)
# ABOUTME: to the B::SoN wire JSON format. Provides to_json(\%named_graphs).

package SoN::Serialize::JSON;

use v5.42.0;
use utf8;
use Exporter 'import';

our @EXPORT_OK = qw(to_json);

use JSON::PP ();
use Scalar::Util qw(blessed);

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
        };
    }
    if ($op eq 'Phi') {
        # predecessors[i] is the Proj that inputs[i] arrives along. It rides
        # the wire as node INDICES, like region, and is omitted when the Phi
        # does not record it (a loop Phi pairs with the loop's entry and back
        # edges rather than a predecessor list).
        #
        # This is what lets the consumer answer "which slot is the then arm?"
        # by reading a field instead of searching the graph. The search it
        # replaces took three fixes and shipped an inverted merge in both
        # polarities -- see
        # docs/research/2026-08-18-phi-pairing-should-not-be-a-search.md in the
        # chalk repo.
        my $preds = $node->can('predecessors') ? $node->predecessors : undef;
        my @pred_ids;
        if (defined $preds && ref $preds eq 'ARRAY') {
            for my $p (@$preds) {
                # A predecessor outside the emitted set cannot be referenced by
                # index. Drop the whole list rather than emit a partial one the
                # consumer would silently mis-pair.
                unless (defined $p && defined $id_remap->{ $p->id }) {
                    @pred_ids = ();
                    last;
                }
                push @pred_ids, $id_remap->{ $p->id };
            }
        }
        return {
            region => $id_remap->{ $node->region->id },
            (@pred_ids ? (predecessors => \@pred_ids) : ()),
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
    if ($op eq 'EntryDef') {
        return {
            stash_name => $node->stash_name,
            # The sigil is part of the variable's IDENTITY, not decoration:
            # `$_` and `@_` share the glob name `_` and are DIFFERENT
            # variables. Dropping it here would re-merge on the loader side
            # exactly what the producer just kept apart.
            sigil      => $node->sigil,
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
    if ($op eq 'Coerce') {
        # from_repr/to_repr are part of Coerce's content hash. Without emitting
        # them the chalk loader rebuilds Coerce with UNDEF reprs, so the backend
        # cannot pick the right coercion arm.
        return {
            from_repr => $node->from_repr,
            to_repr   => $node->to_repr,
        };
    }
    return undef;
}

# -----------------------------------------------------------------------
# This is the cross-repo walk-order contract; the corpus gate enforces it.
# This function is a deliberate DUPLICATE of chalk-side IR Serialize JSON
# copy (the repos are divorced); the gate keeps them honest.
#
# _all_nodes_topo($graph_or_nodes) — return all nodes in topological order.
# Accepts either a SoN::IR::Graph (calls ->nodes) or a plain arrayref of
# already-reachable nodes (a caller that computed its own reachable set via
# a full inputs+consumers BFS, e.g. a producer whose graph was never
# incrementally merge()'d into a Graph's own membership cache). Graph->nodes
# does a DFS over inputs[] only; Phi nodes reference a region via a separate
# field (not inputs[]), so Region may appear after Phi in the base list.
# This function re-sorts to ensure Phi region references are always
# serialized before their Phi nodes.
# -----------------------------------------------------------------------
sub _all_nodes_topo ($graph_or_nodes) {
    my $base = ref($graph_or_nodes) eq 'ARRAY'
        ? $graph_or_nodes
        : $graph_or_nodes->nodes;

    # Collect any Phi region nodes AND control_in-linked nodes not already in
    # the base list. Graph::nodes()'s membership cache is seeded by
    # merge()/_seed() and its consumer walk is filtered to cached members
    # (Graph.pm's `in_cache` check) -- a node reachable ONLY via a control_in
    # edge (produce-time control: set_control_in registers the use-def edge
    # via add_consumer, but never merge()s the node into the graph's own
    # cache) is invisible to that walk and would silently vanish from the
    # serialized output. Two distinct shapes need adding:
    #   (a) a node whose control predecessor is missing (walk control_in
    #       BACKWARD from every base node -- e.g. a void statement-effect
    #       Call reached only via a Return's control_in); and
    #   (b) a node that is itself missing because its only inbound edge is
    #       ITS OWN control_in pointing at an already-reachable node (e.g. a
    #       loop condition whose control_in is the Loop, but nothing's
    #       inputs() reference the condition) -- walk FORWARD via consumers()
    #       and keep any consumer whose control_in points back at the node
    #       being walked.
    # Fixpoint both directions together (an added node can itself expose
    # further control_in-only neighbors) until nothing new is found.
    my %seen = map { $_->id => 1 } $base->@*;
    my @extra;
    my @frontier = $base->@*;
    while (@frontier) {
        my @next_frontier;
        for my $node (@frontier) {
            if ($node->operation eq 'Phi') {
                my $region = $node->region;
                if (defined $region && !$seen{ $region->id }++) {
                    push @extra, $region;
                    push @next_frontier, $region;
                }
            }
            # (a) backward: this node's own control predecessor.
            if ($node->can('control_in') && defined $node->control_in) {
                my $ctrl = $node->control_in;
                if (!$seen{ $ctrl->id }++) {
                    push @extra, $ctrl;
                    push @next_frontier, $ctrl;
                }
            }
            # (b) forward: a consumer whose control_in IS this node.
            if ($node->can('consumers')) {
                for my $c ($node->consumers->@*) {
                    next unless blessed($c);
                    next unless $c->can('control_in') && defined $c->control_in
                        && $c->control_in->id eq $node->id;
                    next if $seen{ $c->id }++;
                    push @extra, $c;
                    push @next_frontier, $c;
                }
            }
        }
        @frontier = @next_frontier;
    }

    # Always re-sort via DFS post-order so that Phi regions are guaranteed
    # to precede their Phi nodes (region is a predecessor, not in inputs[]).
    my @all = grep { blessed($_) } ($base->@*, @extra);
    my %visited;
    my %in_progress;
    my @order;

    # Predecessors of a node are its inputs plus, for Phi, its region, plus
    # (control-aware topo) its control_in edge when it has one. A node whose
    # ONLY inbound edge is control_in (e.g. a void statement-effect Call with
    # no data consumer) has no ordering constraint from inputs() alone and
    # could otherwise be emitted AFTER whatever reads it via control_in (e.g.
    # a Return whose control_in it is) -- a genuine forward reference the
    # loader would reject. Adding control_in as a predecessor here forces it
    # to be visited (and thus emitted) before its control_in consumer,
    # exactly like any other producer edge. control_in never closes a cycle
    # back through itself the way a loop Phi's backedge does (it is a
    # straight-line control chain: Start -> effect -> effect -> ... ->
    # Return/Loop), so no cycle-cut exclusion is needed here.
    #
    # A LOOP header Phi's second input (inputs[1], the back-edge value) is
    # the cycle-closing edge: it necessarily forward-references in any
    # serialization order (the loader defer-patches it via set_backedge once
    # every node exists). Treating it as an ordinary predecessor to visit
    # eagerly picks whichever side of the Phi<->backedge cycle the caller's
    # (unordered) input list happens to reach first: if the Phi is visited
    # before the value that reads it (e.g. an Add computing the next
    # iteration), descending into the backedge hits that Add's in-progress
    # cycle guard and lets the Add finish -- and get appended -- BEFORE the
    # Phi, producing a genuine (non-sanctioned) forward reference. Exclude
    # the backedge from a loop Phi's predecessors so only its init input
    # (inputs[0]) and region are visited eagerly, mirroring the
    # pre-unification SoN::IR::Graph::nodes() cycle-cut. A MERGE Phi (region
    # is a Region, not a Loop) has no such cycle and keeps both inputs.
    my $predecessors = sub ($n) {
        my @in = $n->inputs->@*;
        if ($n->operation eq 'Phi' && defined $n->region
                && $n->region->operation eq 'Loop') {
            @in = ($in[0]);
        }
        # An input may itself be an arrayref of nodes rather than a bare node
        # (e.g. Unwind's exception-args list). Its elements are still
        # producer edges -- omitting them here (as a plain `blessed($_)`
        # filter would) lets a node reachable ONLY through that arrayref be
        # ordered AFTER the node referencing it, a forward reference the
        # loader rejects.
        my @preds = map {
            ref($_) eq 'ARRAY'
                ? grep { defined && blessed($_) } $_->@*
                : (defined $_ && blessed($_) ? $_ : ())
        } @in;
        if ($n->operation eq 'Phi' && defined $n->region) {
            push @preds, $n->region;
        }
        if ($n->can('control_in') && defined $n->control_in) {
            push @preds, $n->control_in;
        }
        return @preds;
    };

    my $visit;
    $visit = sub ($n) {
        return unless blessed($n);
        return if $visited{ $n->id };
        return if $in_progress{ $n->id };   # cycle guard
        $in_progress{ $n->id } = 1;
        for my $pred ($predecessors->($n)) {
            $visit->($pred);
        }
        delete $in_progress{ $n->id };
        $visited{ $n->id } = 1;
        push @order, $n;
    };

    for my $node (@all) {
        $visit->($node);
    }

    return \@order;
}

# -----------------------------------------------------------------------
# _serialize_graph($graph) — returns a Perl data structure for one graph.
# -----------------------------------------------------------------------
sub _serialize_graph ($graph) {
    # $graph is a SoN::IR::Graph, but FromOptree builds it by wrapping
    # start+returns at the very end of translate() rather than incrementally
    # merge()-ing every node in as Chalk's own Actions.pm does -- so the
    # Graph's own ->nodes (cache-gated on that membership set) silently
    # drops a node reachable ONLY via consumers() of an already-included
    # node: a while-loop's false-exit Proj (a consumer of Loop with no
    # downstream input reference), a loop condition (attached to its Loop
    # via control_in, not an inputs[] edge), or a void statement-effect Call/
    # Assign/Print reachable only via a downstream node's control_in (e.g. a
    # Return whose control_in is the effect). Do the full inputs+consumers+
    # control_in BFS ourselves (the pre-unification SoN::IR::Graph::nodes
    # contract, extended for produce-time control), then hand the reachable
    # set to Chalk's shared topo-sort (which also fixes up Phi-region
    # ordering and control_in predecessor ordering) rather than
    # reimplementing that half.
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
        push @worklist, $n->control_in
            if $n->can('control_in') && defined $n->control_in;
    }
    my $topo_nodes = _all_nodes_topo(\@reachable);

    # Build positional ID remap: node->id => positional index (0, 1, 2, ...)
    my %id_remap;
    for my ($pos, $node) (indexed $topo_nodes->@*) {
        $id_remap{ $node->id } = $pos;
    }

    # Emit each node
    my @nodes;
    for my $node ($topo_nodes->@*) {
        my $pos    = $id_remap{ $node->id };
        # An input may be an arrayref of nodes rather than a bare node (e.g.
        # Unwind's exception-args list) -- expand it the same way the
        # reachability walk above already does, rather than assuming every
        # element is blessed.
        my @inputs = map {
            ref($_) eq 'ARRAY'
                ? map { $id_remap{ $_->id } } $_->@*
                : $id_remap{ $_->id }
        } $node->inputs->@*;
        my $fields = _extract_fields($node, \%id_remap);

        my %entry = (
            id     => $pos,
            op     => $node->operation,
            inputs => \@inputs,
        );
        $entry{fields} = $fields if defined $fields;
        if (defined $node->stamp) {
            $entry{stamp} = $node->stamp->type;
        }
        # Produce-time control: emit the control_in edge as its own wire key
        # (mirrors SoN::IR::Serialize::JSON::to_json) so the loader can
        # decode it back onto control_in directly. Covers both a void
        # statement-effect's control predecessor and a loop-header
        # condition's structural edge to its Loop -- both are control_in at
        # produce time now, with no separate transitional marker table. Only
        # emit when the predecessor is itself part of the serialized set
        # (guaranteed here whenever the node itself is, by
        # _all_nodes_topo's control-aware membership walk).
        if ($node->can('control_in') && defined $node->control_in
                && exists $id_remap{ $node->control_in->id }) {
            $entry{control_in} = $id_remap{ $node->control_in->id };
        }
        # Region.head -> the owning If/Loop, set at produce time by
        # StackSim::merge / _build_single_exit / the Loop exit-Region
        # sites. An If/Loop is always a control predecessor of the Region
        # it owns, so it is always already in the topo order (and hence
        # in %id_remap) by the time the Region itself is emitted -- no
        # forward-ref defer-patch needed (unlike the loop-Phi backedge).
        if ($node->operation eq 'Region' && defined $node->head
                && exists $id_remap{ $node->head->id }) {
            $entry{head} = $id_remap{ $node->head->id };
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
