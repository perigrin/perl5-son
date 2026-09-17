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
            # WHAT A FOLDED `sort` COMPARES. Emitted only for sort, where perl
            # folded the comparator into flags and the block is therefore
            # absent -- without these, `sort {$a<=>$b}`, `sort {$b<=>$a}` and a
            # bare `sort` are byte-identical while perl gives three answers.
            ( defined $node->sort_cmp
                ? ( sort_cmp => $node->sort_cmp )
                : () ),
            ( defined $node->sort_order
                ? ( sort_order => $node->sort_order )
                : () ),
            # The `methods` key of an unfoldable comparator's body. Present
            # INSTEAD OF sort_cmp/sort_order, never beside them: a stacked
            # sort's private bits describe no fold and reading them as one is
            # wrong (measured: a numeric descending comparator carries
            # private=0x0, which reads as "string ascending").
            ( defined $node->sort_cmp_body
                ? ( sort_cmp_body => $node->sort_cmp_body )
                : () ),
            # The callsite's context ('void'|'scalar'|'list'). A list-returning
            # callee carries every value AND its scalar reading; this is how a
            # consumer knows which one this callsite asked for.
            ( defined $node->want
                ? ( want => $node->want )
                : () ),
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
    # A PAD-BOUND AGGREGATE CARRIES THE NAME IT WAS BOUND TO, so a consumer can
    # WRITE the container. Without it an element store is unrenderable: the
    # aggregate is represented by the literal that initialised it, and
    # `(1,2,3)[0] = 7` is not assignable. Absent for an anonymous aggregate,
    # where there is no variable to name -- the stamp already separates the two
    # (Array/Hash vs ArrayRef/HashRef).
    if ($op eq 'ArrayLiteral' || $op eq 'HashLiteral') {
        return {
            ( defined $node->sigil  ? ( sigil  => $node->sigil )  : () ),
            ( defined $node->symbol ? ( symbol => $node->symbol ) : () ),
        };
    }

    if ($op eq 'AnonSub') {
        # The `methods` key holding this sub's body -- same field name Call
        # uses for the same purpose, so a consumer reads one spelling.
        return {
            ( defined $node->name ? ( name => $node->name ) : () ),
            # The captured variable names, POSITIONAL with the value inputs:
            # input N is the cell for captures[N], which the body reads as
            # CellParam(index => N). The body is a separate graph, so this
            # correspondence has to be on the wire -- there is no shared pad
            # to imply it.
            ( defined $node->captures && $node->captures->@*
                ? ( captures => $node->captures )
                : () ),
        };
    }
    if ($op eq 'MakeCell') {
        return {
            ( defined $node->cell_name ? ( cell_name => $node->cell_name ) : () ),
            # WHETHER ANY CLOSURE OVER THIS CELL WRITES IT. False lets a
            # consumer skip the cell and pass the value directly; true means
            # the indirection is load-bearing. JSON::PP booleans so the
            # consumer reads true/false rather than 1/"".
            captured_written =>
                ( $node->captured_written ? JSON::PP::true : JSON::PP::false ),
        };
    }
    if ($op eq 'CellParam') {
        # `index` is the position in the enclosing AnonSub's inputs; `name` is
        # the source variable, for diagnostics.
        return {
            index => $node->index,
            ( defined $node->name ? ( name => $node->name ) : () ),
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
    # NO PAD INDEX. `targ` is perl's scratchpad slot -- an artifact of how perl
    # stores a lexical in one CV, meaningless to a consumer, and unstable across
    # compilation units by the producer's own account (PadAccess::content_hash
    # excludes it for exactly that reason). Shipping it invited a consumer to
    # key on a number we tell them not to trust.
    #
    # Identity does not need it: two shadowed `my $x` stay distinct on the wire
    # because their MEMORY inputs differ, not because of the slot number.
    if ($op eq 'PadAccess') {
        return {
            ( defined $node->sigil  ? ( sigil  => $node->sigil )  : () ),
            ( defined $node->symbol ? ( symbol => $node->symbol ) : () ),
        };
    }
    if ($op eq 'FieldAccess') {
        return {
            field_index => $node->field_index,
            field_stash => $node->field_stash,
        };
    }
    if ($op eq 'Parameter') {
        return {
            # The INDEX is the identity: a parameter is a value identified by
            # POSITION, and two reads of parameter 0 are one node. The name is
            # debug information; the sigil is what types it ($ scalar, @ array,
            # % hash), and a slurpy is NOT always an array -- `sub f(%h)` is a
            # hash.
            index => $node->index,
            name  => $node->name,
            sigil => $node->sigil,
        };
    }
    # A BINDING IS NOT A STORE. `*g = \@a` aliases the NAME; `$g = \@a` stores a
    # reference. Emitted only when true, so an ordinary store is unchanged on
    # the wire.
    if ($op eq 'EntryWrite') {
        return $node->binds ? { binds => JSON::PP::true } : undef;
    }
    if ($op eq 'EntryDef') {
        return {
            package => $node->package,
            # The sigil is part of the variable's IDENTITY, not decoration:
            # `$_` and `@_` share the glob name `_` and are DIFFERENT
            # variables. Dropping it here would re-merge on the loader side
            # exactly what the producer just kept apart.
            sigil      => $node->sigil,
            symbol => $node->symbol,
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
    # A Print states whether its operand 0 is an explicit filehandle. Emitted
    # only when true, so a plain print's node is byte-identical to before.
    if ($op eq 'Print') {
        return $node->has_filehandle ? { has_filehandle => JSON::PP::true } : undef;
    }
    if ($op eq 'RegexSubst') {
        return {
            pattern     => $node->pattern,
            replacement => $node->replacement,
            flags       => $node->flags,
            # Emitted only when true, so a literal-pattern node's wire is
            # byte-identical to before. Same rule as Print's has_filehandle.
            ($node->pattern_is_input
                ? (pattern_is_input => JSON::PP::true) : ()),
        };
    }
    # A ListAppend's inputs do not say whether the last one is a contribution
    # (map) or a predicate (grep), and the stamps cannot separate them.
    # A block eval's Region names where the protected body began. Emitted only
    # when set, so every other Region's wire is unchanged.
    if ($op eq 'Region') {
        my $entry = $node->can('eval_entry') ? $node->eval_entry : undef;
        # As a node INDEX, like `region` and `predecessors`. An entry outside
        # the emitted set is dropped rather than referenced by a hash the
        # consumer cannot resolve.
        return undef unless defined $entry
                         && defined $id_remap->{ $entry->id };
        return { eval_entry => $id_remap->{ $entry->id } };
    }
    # tr///'s character sets and flags. `d` is not recoverable from an empty
    # `to` -- `tr/x//` maps x to itself, `tr/x//d` removes it -- so the flags
    # ride alongside rather than being inferred.
    # chomp and chop are different operations over the same shape, and the
    # inputs do not say which.
    if ($op eq 'Chomp') {
        return { kind => $node->kind };
    }
    if ($op eq 'Transliterate') {
        return {
            from  => $node->from,
            to    => $node->to,
            flags => $node->flags,
        };
    }
    if ($op eq 'ListAppend') {
        return { collector => $node->collector };
    }
    # A LIST slice's inputs are [indices..., values...] and neither length is
    # recoverable from the other, so the split point rides on the node. The
    # CONTAINER form (aslice/hslice) leaves it 0 and keeps its wire
    # byte-identical: every input but the last is an index there.
    if ($op eq 'Slice') {
        my $n = $node->can('index_count') ? $node->index_count : 0;
        return $n ? { index_count => $n } : undef;
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
        # (mirrors the chalk-side loader's expectation) so the loader can
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
    #
    # THE MODEL DOES NOT SPEAK JSON. These flags are built as plain 0/1 by
    # B::SoN, and the encoder's boolean type is applied HERE, at the boundary,
    # where it belongs -- a record that reached for JSON::PP::true while being
    # constructed made the producer's data model depend on its serializer.
    #
    # The conversion is not cosmetic: this section is emitted RAW (there is no
    # _extract_fields pass over it), so a plain 1 would reach the wire as `1`
    # where chalk's loader declared a boolean. t/wire-booleans-are-json-booleans.t
    # pins the emitted text for exactly that reason -- a decoded comparison
    # cannot tell `true` from `1`, because JSON::PP decodes them equal.
    $data->{classes} = _json_booleans($classes)
        if defined $classes && %$classes;

    # ->utf8 BECAUSE THE WIRE IS BYTES AND THE VALUES ARE CHARACTERS.
    # Without it `encode` returns a character string, and printing that to a
    # non-`:utf8` handle writes each character's low byte -- so a string
    # Constant holding anything above U+007F reached the wire as a raw byte,
    # inside JSON every consumer assumes is UTF-8. Measured: 4 of 34 corpus
    # files emitted a wire Python's json.load refuses outright, while perl's
    # decoder accepted it, which is why the producer writing and reading its
    # own wire never noticed.
    #
    # The values here are ALREADY CHARACTERS -- measured, both a "café"
    # literal and a high-byte string arrive with utf8_flag=ON -- so this
    # encodes once rather than twice, and the round trip returns the original
    # string exactly.
    #
    # NOT ->ascii, which is equally correct and optimises for the pathological
    # case: it escapes every non-ASCII character, so "café" becomes
    # "caf\u00e9" and the wire grows ~60% for any program containing ordinary
    # Unicode. Four corpus files carry raw high bytes; far more will one day
    # carry text. See docs/plans/2026-09-13-the-wire-is-not-valid-utf8.md,
    # which also records the measurement I first got backwards.
    return JSON::PP->new->canonical->pretty->utf8->encode($data);
}

# _json_booleans($data) -- copy a structure, re-typing the known boolean keys
# as the encoder's booleans.
#
# KEYED ON THE FIELD NAME, not on the value's shape. Perl cannot tell a boolean
# 1 from the integer 1, so "looks like 0 or 1" would also convert `fieldix => 0`
# and any count that happened to be 1. The producer knows which fields ARE
# booleans; that list is the fact, and it lives here rather than in the model.
my %BOOLEAN_FIELD = map { $_ => 1 } qw(
    uses_args is_reader invocant has_default is_param
);

sub _json_booleans ($data) {
    if (ref $data eq 'HASH') {
        return { map {
            my $v = $data->{$_};
            $_ => ( $BOOLEAN_FIELD{$_} && !ref $v
                    ? ( $v ? JSON::PP::true : JSON::PP::false )
                    : _json_booleans($v) )
        } keys %$data };
    }
    return [ map { _json_booleans($_) } @$data ] if ref $data eq 'ARRAY';
    return $data;
}

1;
