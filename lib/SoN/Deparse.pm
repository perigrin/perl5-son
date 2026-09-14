# ABOUTME: Renders a SoN graph back to Perl source, as a differential oracle for the producer.
# ABOUTME: The criterion is observational equivalence per program, never a spelling per node.
use v5.42.0;
use utf8;
use experimental 'class';

# WHY THIS EXISTS. Every correctness check on the producer is otherwise
# STRUCTURAL -- read the graph and reason about whether it says what perl says.
# Every defect found that way was a WRONG ANSWER from a structurally plausible
# graph, with the test suite green throughout. Running the rendering and
# diffing it against the original catches that class mechanically.
# See docs/plans/2026-09-12-deparse-target-as-a-differential-oracle.md.
#
# THE CRITERION IS OBSERVATIONAL EQUIVALENCE, PROGRAM BY PROGRAM: same output,
# same effects, same order where order is observable. The obligation is on the
# PROGRAM, not the node -- a memory-Phi, a Proj, a Region and Start are
# structure, discharged by WHERE things are emitted rather than by what they
# translate to. Not every node needs a spelling; no input semantics may be lost.
#
# WHAT ORDER IS OBSERVABLE is what the graph already encodes: `control_in` is
# what is ordered, data edges are what is not. So the emitted program may differ
# from the input in the unordered parts. It is allowed to be UGLY. It is not
# allowed to be WRONG.
#
# DELIBERATELY DUMB, and this is the load-bearing design rule. If this emitter
# reproduces a fold the walker made, the round-trip agrees with itself and the
# miscompile stays invisible -- `@$r` is the shape to fear: flatten on the way
# in, flatten on the way out, output matches, bug survives. So this emits what
# the node SAYS, never what the source probably meant, and it imports NOTHING
# from FromOptree.pm. Shared code is shared assumptions.
#
# It reads the JSON wire format rather than producer internals: the wire is what
# chalk consumes too, so a rendering defect here is a wire defect, not an
# artefact of reaching into the producer.
class SoN::Deparse 0.01 {
    # ONE TABLE, ONE SPELLING EACH. These are not interchangeable: `==` for
    # `eq` agrees on numbers and disagrees on strings, which is exactly the
    # Int/Str confusion the stamp lattice tracks. A wrong entry here is a wrong
    # ANSWER, and the round-trip is what catches it.
    my %BINOP = (
        NumEq => '==',  NumNe => '!=',  NumLt => '<',   NumGt => '>',
        NumLe => '<=',  NumGe => '>=',  NumCmp => '<=>',
        StrEq => 'eq',  StrNe => 'ne',  StrLt => 'lt',  StrGt => 'gt',
        StrLe => 'le',  StrGe => 'ge',  StrCmp => 'cmp',
        Add => '+',     Subtract => '-', Multiply => '*', Divide => '/',
        Modulo => '%',  Power => '**',
        Concat => '.',  Repeat => 'x',
        BitAnd => '&',  BitOr => '|',   BitXor => '^',
        LeftShift => '<<', RightShift => '>>',
    );

    field $nodes;      # id => node hash

    # Effects on the control chain whose value some other node reads: id =>
    # the variable the emitter binds them to. See _emit_control_chain.
    field %bound;

    # Pad bindings whose value is a chain-bound effect: effect id => [nodes to
    # emit right after it]. See _emit_control_chain.
    field %after_effect;

    # NODES THAT CARRY A TRAILING MEMORY EDGE, and the number of real operands
    # that precede it. A node of this kind with MORE inputs than its operand
    # count has a memory edge last; anything else does not, however much its
    # last input looks like one.
    #
    # Taken from the producer's construction sites rather than guessed:
    # FromOptree.pm builds Call with [args..., memory] at three sites
    # (keys/values/each, push/unshift/splice, shift/pop), and the aggregate
    # readers and writers each append one the same way.
    our %MEM_MIN_INPUTS = (
        Call         => 1,   # [arg, ..., memory]
        EntryWrite   => 2,   # [slot, value, memory]
        Assign       => 2,   # [target, value, memory]
        Delete       => 2,   # [container, key, memory]
        Subscript    => 2,   # [container, index, memory]
        Count        => 1,   # [aggregate, memory]
        PostfixDeref => 1,   # [container, memory]
        EntryDef     => 0,   # [memory] -- ordering only
    );
    field %rendered;   # id => Perl expression text

    # The reason the last render() refused, for a caller that wants to report it
    # rather than just see undef.
    field $gap :reader = undef;

    # render($data) -- the decoded JSON wire, to Perl source for main::__PROGRAM__.
    #
    # Returns undef when the graph holds a node this emitter has no rule for,
    # and sets ->gap to say WHICH. A REFUSAL IS SCAFFOLDING, not a resting
    # state: every one is a live question about whether that node's meaning
    # survives the round trip. An UNNAMED refusal is worse than none -- it is
    # the silent-drop shape this whole tool exists to catch, so the reason is
    # always recorded.
    method render ($data) {
        $gap = undef;
        my $methods = $data->{methods} // {};
        my $graph = $methods->{'main::__PROGRAM__'};
        unless ($graph) { $gap = 'no main::__PROGRAM__ in the graph'; return undef }

        # EVERY SUB IS ITS OWN GRAPH on the wire, so a direct call names a
        # `methods` entry that must ALSO be emitted -- calling a sub the
        # emitted program never defines is a runtime death, not a wrong value.
        my $out = '';
        for my $name (sort keys $methods->%*) {
            next if $name eq 'main::__PROGRAM__';
            my $sub = eval { $self->_emit_sub($name, $methods->{$name}) };
            if (!defined $sub) { $gap = $@ || "failed to render $name"; return undef }
            $out .= $sub;
        }

        $nodes = { map { $_->{id} => $_ } ($graph->{nodes} // [])->@* };
        %rendered = ();
        %bound    = ();
        %after_effect = ();
        my $body = eval { $self->_emit_control_chain($graph) };
        if (!defined $body) { $gap = $@ || 'render failed with no reason'; return undef }
        return $out . $body;
    }

    # A named sub. Its body is the same control-chain walk the program body
    # gets; only the wrapper differs.
    method _emit_sub ($name, $graph) {
        my $save_nodes = $nodes;
        my %save_rendered = %rendered;
        # NODE IDS ARE PER-SUB, so the bindings are too -- node 3 in one sub is
        # a different node from node 3 in another. Carrying them over emitted
        # `my shift(@_) = shift(@_)`, the caller's binding read as this sub's.
        my %save_bound = %bound;
        my %save_after = %after_effect;
        $nodes = { map { $_->{id} => $_ } ($graph->{nodes} // [])->@* };
        %rendered = ();
        %bound    = ();
        %after_effect = ();

        my $body = eval { $self->_emit_control_chain($graph) };
        my $err = $@;
        $nodes = $save_nodes;
        %rendered = %save_rendered;
        %bound    = %save_bound;
        %after_effect = %save_after;
        die $err unless defined $body;

        ( my $short = $name ) =~ s/^main:://;
        return sprintf("sub %s {\n%s}\n", $short, $body);
    }

    # THE CONTROL CHAIN IS THE STATEMENT ORDER. Measured: `control_in` is a
    # total order over effects, with pure values hanging off it as a DAG. So
    # there is no scheduling pass -- walk the chain, and emit each effect's
    # operand tree as an expression.
    method _emit_control_chain ($graph) {
        # CONTROL FLOWS BY TWO MECHANISMS and the index must see both.
        # An EFFECT names its predecessor in `control_in`; a CFG node names
        # its predecessor as a DATA input -- measured, a Proj carries
        # inputs=[If] with control_in absent, and a Region carries
        # inputs=[arm, arm]. Indexing only control_in found an If with "0 Proj
        # arms", because the Projs hang off the data edge.
        my %next_of;
        my %is_cfg = map { $_ => 1 } qw(Proj Region);
        for my $n (($graph->{nodes} // [])->@*) {
            my $ci = $n->{control_in};
            push $next_of{$ci}->@*, $n if defined $ci;
            next unless $is_cfg{ $n->{op} };
            push $next_of{$_}->@*, $n for (($n->{inputs} // [])->@*);
        }

        my ($start) = grep { $_->{op} eq 'Start' } values $nodes->%*;
        die "no Start node\n" unless $start;

        # AN EFFECT IS RUN ONCE, AND ITS VALUE IS READ, NOT RE-RUN. A node on
        # the control chain happens where the chain puts it; inlining it again
        # at a use runs it a SECOND time. Measured on `sub foo { my $s = shift }`:
        #
        #     sub foo { shift(@_); return (shift(@_) + 1) }
        #
        # two shifts off a one-element @_, so the answer was 1 instead of 42.
        # The `Return` case of this was already special-cased; the general one
        # is any effect whose value another node reads.
        #
        # SSA HAS NO NAME FOR IT, so the emitter makes one: the effect is bound
        # at its chain position and every read renders the variable. That is
        # the same device _emit_loop uses for a Phi, and for the same reason --
        # Perl needs a place to put a value that SSA keeps in an edge.
        #
        # ONLY WHEN SOMETHING READS IT. An effect nobody reads stays a bare
        # statement, so the common case emits exactly as before.
        my %reads;
        for my $n (values $nodes->%*) {
            # A CFG NODE NAMES CONTROL AS A DATA INPUT, not a value. Proj and
            # Region take only predecessors; an If takes [predecessor,
            # condition] and a Loop takes [predecessor] -- measured on
            # base/if.t, `If(11) in=[9,10]` where 9 is the EntryWrite it
            # follows. Counting input 0 bound that effect and then asked for
            # an `EntryWrite` as an expression.
            #
            # _emit_if already reads inputs[1] for the condition, so the
            # condition is still counted; only the control edge is skipped.
            my $cfg = ($n->{op} // '');
            if ($cfg =~ /\A(?:Proj|Region|Loop)\z/) { next }

            # A MEMORY PHI MERGES CHAINS, NOT VALUES. Where a branch stores on
            # both arms the two memory chains join, and every input is an
            # effect -- measured on base/num.t, `Phi(603) in=[577,591]` with
            # both an EntryWrite. Counting those bound the writes and then
            # asked for an `EntryWrite` as an expression.
            #
            # A VALUE Phi still counts, which is what makes a loop-carried
            # variable work; _is_memory is what separates them.
            next if $cfg eq 'Phi' && $self->_is_memory($n->{id});
            if ($cfg eq 'If') {
                my @cin = ($n->{inputs} // [])->@*;
                $reads{ $cin[1] }++ if @cin > 1;
                next;
            }

            # A MEMORY EDGE IN THE LAST POSITION IS NOT A READ. Counting one
            # binds the effect it names, and something then tries to render
            # that effect as a value -- measured, `EntryDef $main::"` carries
            # inputs=[Assign] purely to order the read of `$"` against an
            # element store, and counting it asked for `Assign` as an
            # expression.
            #
            # ONLY THE NODES THE PRODUCER GIVES ONE. Asking "is the last input
            # a memory node" of EVERY node is too broad: a Coerce over a
            # `shift` has exactly that shape and its one input IS the value.
            # These are the kinds that take a memory edge, from the producer.
            my @in = ($n->{inputs} // [])->@*;
            pop @in if @in > ($MEM_MIN_INPUTS{ $n->{op} // '' } // 99)
                    && $self->_is_memory($in[-1]);

            $reads{$_}++ for @in;
        }
        for my $id (keys %reads) {
            my $n = $nodes->{$id} or next;
            next unless defined $n->{control_in};
            next if ($n->{op} // '') =~ /\A(?:Proj|Region|Loop|If|Start)\z/;

            # THE BINDING MUST NOT IMPOSE A CONTEXT. `my $x = readline(FH)`
            # reads ONE line; the same call in list context reads them all,
            # and the graph says which -- measured, `my @got = <R>` gives the
            # readline Call stamp=List feeding an ArrayLiteral. Binding it to
            # a scalar silently dropped every line after the first.
            $bound{$id} = (($n->{stamp} // '') eq 'List')
                ? sprintf('@eff%d', $id) : sprintf('$eff%d', $id);
        }

        my $body = $self->_emit_from($start->{id}, \%next_of, undef);

        # A PAD BINDING IS NOT ON THE CONTROL CHAIN. Measured: `my ($a,$b) =
        # (2,3)` builds an Assign with control_in ABSENT, so a chain walk never
        # reaches it and the emitted program read two undefs. Under SSA a pad
        # binding needs no ordering -- the reads name the same node either way
        # -- but PERL needs the `my` to have happened, so the emitter must
        # place it.
        #
        # Emitted as a PROLOGUE, before the chain. That is sound here because
        # these bindings have no control edge to order them against; a binding
        # that DID need ordering would carry one, and would already be in the
        # chain.
        # A NAMED AGGREGATE MUST EXIST BEFORE IT IS INDEXED. The graph has no
        # node for "declare @a" -- the literal IS the array, holding both its
        # identity and its initial contents -- so the declaration is
        # reconstructed here from the node that carries the name.
        #
        # Emitted before the chain for the same reason the pad bindings are:
        # these carry no control edge, so nothing orders them, and Perl needs
        # the `my` to have happened.
        my $prologue = '';
        for my $n (sort { $a->{id} <=> $b->{id} } values $nodes->%*) {
            next unless ($n->{op} // '') =~ /\A(?:Array|Hash)Literal\z/;
            my $af = $n->{fields} // {};
            next unless defined $af->{symbol};
            my $vn = ($af->{sigil} // '@') . $af->{symbol};

            # AN AGGREGATE WHOSE CONTENTS ARE A CHAIN-BOUND EFFECT CANNOT
            # FLOAT EITHER. `my @got = <R>` builds ArrayLiteral(sym=got)
            # holding the readline's value -- measured -- and hoisting the
            # declaration put `my @got = ($eff21)` above the line declaring
            # $eff21. Same rule as the pad bindings below, same reason.
            my $defer = 0;
            for my $in (($n->{inputs} // [])->@*) {
                next unless defined $in && exists $bound{$in};
                push $after_effect{$in}->@*, $n;
                $defer = 1;
                last;
            }
            next if $defer;

            $prologue .= sprintf("my %s = (%s);\n", $vn,
                join(', ', map { $self->_expr($_) } (($n->{inputs} // [])->@*)));
        }

        for my $n (sort { $a->{id} <=> $b->{id} } values $nodes->%*) {
            next unless $n->{op} eq 'Assign';
            next if defined $n->{control_in};   # already emitted in the chain

            # A BINDING OF A CHAIN-BOUND EFFECT CANNOT FLOAT. The prologue is
            # sound for a pad binding whose value has no control edge -- there
            # is nothing to order it against. But `my @got = <TRY>` binds a
            # READ, which is pinned and bound to a variable at its chain
            # position, so hoisting the binding put `my @got = ($eff21)` above
            # the line that declares $eff21.
            #
            # Deferred to the chain instead, emitted right after the effect it
            # names. Whether it is a `my` is the same question either way; only
            # the PLACE changes.
            my $deferred = 0;
            for my $in (($n->{inputs} // [])->@*) {
                next unless defined $in && exists $bound{$in};
                push $after_effect{$in}->@*, $n;
                $deferred = 1;
                last;
            }
            next if $deferred;

            $prologue .= $self->_emit_statement($n, \%next_of);
        }

        # A deferred binding is emitted where its effect was placed, so the
        # chain has to be walked again now that %after_effect is populated.
        # Cheap, and it keeps the placement rule in one direction: the chain
        # decides, the prologue only takes what the chain cannot order.
        if (keys %after_effect) {
            %rendered = ();
            $body = $self->_emit_from($start->{id}, \%next_of, undef);
        }

        return $prologue . $body;
    }

    # Walk forward from $id, emitting a statement per control successor, until
    # the chain ends or reaches $stop (the Region that joins branch arms).
    method _emit_from ($id, $next_of, $stop) {
        my $out = '';
        my $cur = $id;
        while (defined $cur) {
            my $succ = $next_of->{$cur} // [];
            last unless $succ->@*;
            die "GAP: a control node with " . scalar($succ->@*)
              . " successors is not yet rendered\n" if $succ->@* > 1;
            my $n = $succ->[0];
            last if defined $stop && $n->{id} == $stop;

            # AN `If` IS A DIAMOND, not a statement in the chain. Emit it whole
            # -- both arms and the join -- and resume at the Region, which is
            # where the two arms' control converges.
            if ($n->{op} eq 'If') {
                my ($text, $join) = $self->_emit_if($n, $next_of);
                $out .= $text;
                last unless defined $join;
                last if defined $stop && $join == $stop;
                $cur = $join;
                next;
            }

            # AN EVAL IS A JOIN WITH ONE CONTROL EDGE. `eval "..."` either
            # yielded its value or caught and returned undef, so the VALUE
            # forks while control does not -- measured on `my $v = eval "1+1"`:
            #
            #     4 Coerce  in=[3]   ci=0  Str->Code   the eval itself
            #     5 Region  in=[4]                     one control input
            #     6 Phi     in=[4,1] region=5          [value, undef]
            #
            # The producer's own words at the construction site: "the eval
            # either yielded its value or caught and returned undef. Two arms
            # merging is the same shape block eval builds."
            #
            # Discharged by placement like every other join: the effect is
            # wrapped in `eval { }` and the Region needs no spelling, because
            # the closing brace IS the merge. Emission resumes after it.
            if ($n->{op} eq 'Region' && $self->_is_eval_join($n)) {
                my $eff = $nodes->{ $n->{inputs}[0] };
                $out .= $self->_emit_eval($eff);
                $cur = $n->{id};
                next;
            }

            # A LOOP IS A DIAMOND THAT COMES BACK. Same discharge-by-placement
            # as `If`: two Projs, one for the body and one for the exit, and
            # emission resumes after the exit. The difference is the BACK EDGE,
            # which is what the loop-carried Phis express.
            if ($n->{op} eq 'Loop') {
                my ($text, $after) = $self->_emit_loop($n, $next_of);
                $out .= $text;
                last unless defined $after;
                last if defined $stop && $after == $stop;
                $cur = $after;
                next;
            }

            # A BOUND EFFECT BINDS AT ITS CHAIN POSITION. `_emit_statement`
            # would emit it bare, and the reads would then have nothing to
            # name -- so the value is captured here, once, where it happens.
            if (exists $bound{ $n->{id} }) {
                # THE VARIABLE IS READ OUT FIRST. Passing `$bound{...}` to
                # sprintf passes the hash element as an ALIAS, and
                # _expr_uncached deletes and restores that very element -- so
                # the alias resolved to the restored value and the binding
                # emitted `my shift(@_) = shift(@_)`.
                my $var  = $bound{ $n->{id} };
                my $expr = $self->_expr_uncached($n->{id});
                $out .= sprintf("my %s = %s;\n", $var, $expr);
                $out .= $self->_emit_statement($_, $next_of)
                    for (($after_effect{ $n->{id} } // [])->@*);
            }
            else {
                $out .= $self->_emit_statement($n, $next_of);
            }
            $cur = $n->{id};
        }
        return $out;
    }

    # _emit_loop($n, $next_of) -> (source, id to resume from)
    #
    # A LOOP'S PIECES ARE ALL IN THE GRAPH. Measured on `while ($i < 3) {...}`:
    #
    #     3 Loop    in=[0]     ci=0
    #     4 Proj    in=[3]     index=1      the EXIT
    #    12 Proj    in=[3]     index=0      the BODY
    #     9 Phi     in=[8,18]  region=3     [on entry, at the bottom]
    #    11 NumLt   in=[9,10]  ci=3         the condition, pinned on the Loop
    #
    # so the condition is whatever the Loop controls, the body is Proj 0's
    # chain, and the exit is Proj 1's.
    #
    # A PHI BECOMES A VARIABLE, which is the whole reason a loop needs more
    # than `If` does. In a diamond both arms' values can be inlined at the
    # join; across a back edge they cannot, because the value at the top of an
    # iteration is the value the PREVIOUS one left. The Phi's first input is
    # its value on entry -- emitted before the loop -- and its second is the
    # value at the bottom, assigned at the end of the body.
    #
    # THE PHIS ARE ASSIGNED TOGETHER, AT THE BOTTOM, and that is not a style
    # choice. Measured on two carried values:
    #
    #     14 Phi  in=[3,19]   $i     19 = Add(14, 1)
    #      5 Phi  in=[3,23]   $sum   23 = Add(5, 14)    reads $i's PHI
    #
    # `$sum`'s next value reads `$i`'s phi, not `$i`'s next value. Updating $i
    # first would feed the already-incremented value into $sum -- an
    # off-by-one that still prints a plausible number. Computing every next
    # value into temporaries before assigning any of them is what preserves the
    # simultaneity SSA means by a Phi.
    #
    # A PHI OUTLIVES THE LOOP. Measured, `print "final $sum"` after the loop
    # reads the Phi node itself, so the variable is declared BEFORE the loop
    # rather than inside it -- a `my` in the body would go out of scope exactly
    # where the graph still needs it.
    method _emit_loop ($n, $next_of) {
        my @projs = ($next_of->{ $n->{id} } // [])->@*;
        @projs = grep { $_->{op} eq 'Proj' } @projs;
        die "GAP: a Loop with " . scalar(@projs) . " Proj arms is not yet"
          . " rendered\n" unless @projs == 2;

        my %arm = map { ($_->{fields}{index} // 0) => $_ } @projs;
        die "GAP: a Loop whose Projs are not indexed 0 and 1 is not yet"
          . " rendered\n" unless exists $arm{0} && exists $arm{1};

        # THE CONDITION IS WHAT THE LOOP CONTROLS. It is pinned on the Loop
        # rather than reached through a Proj, so it is found by control_in --
        # and it is the only such node, because the body hangs off Proj 0.
        my @cond = grep { ($_->{control_in} // -1) == $n->{id}
                       && $_->{op} ne 'Proj' } values $nodes->%*;
        die "GAP: a Loop with " . scalar(@cond) . " condition nodes is not yet"
          . " rendered\n" unless @cond == 1;

        my @phis = sort { $a->{id} <=> $b->{id} }
                   grep { ($_->{op} // '') eq 'Phi'
                       && (($_->{fields}{region} // -1) == $n->{id}) }
                   values $nodes->%*;
        for my $p (@phis) {
            die "GAP: a loop Phi with " . scalar(($p->{inputs} // [])->@*)
              . " inputs is not yet rendered\n"
                unless ($p->{inputs} // [])->@* == 2;
        }

        my $init = '';
        $init .= sprintf("my %s = %s;\n", $self->_phi_var($_),
                         $self->_expr($_->{inputs}[0])) for @phis;

        my $body = $self->_emit_from($arm{0}{id}, $next_of, undef);

        # Next values into temporaries first, then assign: see above.
        my $step = '';
        if (@phis) {
            $step .= sprintf("my %s_next = %s;\n", $self->_phi_var($_),
                             $self->_expr($_->{inputs}[1])) for @phis;
            $step .= sprintf("%s = %s_next;\n", $self->_phi_var($_),
                             $self->_phi_var($_)) for @phis;
        }

        my $text = $init . sprintf("while (%s) {\n%s}\n",
            $self->_expr($cond[0]{id}), _indent($body . $step));

        # RESUME AT THE EXIT'S REGION, not at the Proj. `If` resumes at the
        # Region that joins its arms and never emits it; a loop's exit Proj
        # feeds a Region of its own, and returning the Proj would leave that
        # Region to be reached as a STATEMENT, which has no spelling. A
        # one-input Region here is the loop's exit join.
        my $after = $arm{1}{id};
        my ($exit_region) = grep { ($_->{op} // '') eq 'Region' }
                            (($next_of->{ $arm{1}{id} } // [])->@*);
        $after = $exit_region->{id} if $exit_region;

        return ($text, $after);
    }

    # A loop Phi's variable. Named from the node id because SSA has no name for
    # it -- the source's `$i` is gone by the time a Phi exists, and inventing a
    # readable one risks colliding with a pad slot the program still uses.
    method _phi_var ($p) { sprintf('$phi%d', $p->{id}) }

    # Whether a Region is an eval's join rather than a branch's.
    #
    # ONE CONTROL INPUT AND A Phi(value, undef). A branch join has one input
    # per arm; this has one, because an eval's failure path produces no
    # separate control -- only the value forks. The Phi over it is what says
    # so, and requiring BOTH is what keeps this from claiming a Region that
    # merely happens to have one predecessor.
    method _is_eval_join ($n) {
        my @in = ($n->{inputs} // [])->@*;
        return 0 unless @in == 1;
        my ($phi) = grep { ($_->{op} // '') eq 'Phi'
                        && ((($_->{fields} // {})->{region} // -1) == $n->{id}) }
                    values $nodes->%*;
        return 0 unless $phi;
        my @pin = ($phi->{inputs} // [])->@*;
        return 0 unless @pin == 2 && defined $pin[0] && $pin[0] == $in[0];
        my $undef = $nodes->{ $pin[1] } or return 0;
        return 0 unless ($undef->{op} // '') eq 'Constant'
            && ((($undef->{fields} // {})->{const_type} // '') eq 'undef');
        return 1;
    }

    # The `eval { }` an eval join stands for, binding its value where the Phi
    # is read. The Phi IS the eval's value -- `eval` already yields undef on
    # failure -- so one variable serves both.
    method _emit_eval ($eff) {
        my ($phi) = grep { ($_->{op} // '') eq 'Phi'
                        && (($_->{inputs} // [])->[0] // -1) == $eff->{id} }
                    values $nodes->%*;

        # THE EFFECT IS RENDERED INSIDE THE BLOCK, and its value is the
        # block's. A string eval is a Coerce(Str->Code) whose operand is the
        # source text, which is what `eval EXPR` takes; anything else pinned
        # here is an ordinary effect that may die, and `eval { ... }` is the
        # honest wrapper for it either way.
        my $inner;
        if (($eff->{op} // '') eq 'Coerce'
                && ((($eff->{fields} // {})->{to_repr} // '') eq 'Code')) {
            $inner = sprintf('eval(%s)',
                             $self->_expr(($eff->{inputs} // [])->[0]));
        }
        else {
            $inner = sprintf('eval { %s }', $self->_expr_uncached($eff->{id}));
        }

        return "$inner;\n" unless $phi;

        # The Phi is bound, so every later read names the variable. Registering
        # it here rather than in the %reads scan keeps that scan about VALUES;
        # this binding exists because the eval was placed, not because someone
        # read it.
        $bound{ $phi->{id} } = sprintf('$eval%d', $phi->{id});
        return sprintf("my %s = %s;\n", $bound{ $phi->{id} }, $inner);
    }

    # _emit_if($n, $next_of) -> (source, join id)
    #
    # THE DIAMOND IS DISCHARGED BY PLACEMENT. `If` has two `Proj` successors --
    # index 0 is the true arm, index 1 the false -- and each arm's control runs
    # until both reach the `Region` that joins them. Rendering the arms as
    # if/else blocks and resuming after the Region is what makes the arms'
    # effects conditional and everything after unconditional. Neither the Proj
    # nor the Region needs a spelling of its own.
    method _emit_if ($n, $next_of) {
        my $cond = $self->_expr($n->{inputs}[1]);

        my @projs = ($next_of->{ $n->{id} } // [])->@*;
        die "GAP: an If arm that is not a Proj is not yet rendered\n"
            if grep { $_->{op} ne 'Proj' } @projs;
        die "GAP: an If with " . scalar(@projs) . " Proj arms is not yet"
          . " rendered\n" unless @projs == 1 || @projs == 2;

        my %arm = map { ($_->{fields}{index} // 0) => $_ } @projs;
        die "GAP: an If whose Projs are not indexed 0 and 1 is not yet"
          . " rendered\n" if @projs == 2
                          && !(exists $arm{0} && exists $arm{1});

        # ONE PROJ MEANS THE OTHER ARM IS EMPTY. `&&` and `||` in a condition
        # compile to NESTED Ifs on the same operand, and the inner one keeps
        # only the arm that acts -- measured on
        # `if (defined $a && $a > $b) { ... }`:
        #
        #      9 If    in=[0, 8]    8 = And(Defined, NumGt)
        #     10 Proj  index=0      13 Proj index=1
        #     14 If    in=[13, 8]   a SECOND If on the same And
        #     15 Proj  index=1      and only THIS one
        #
        # If(14) has no index-0 Proj because nothing happens there; control
        # falls straight through to the join. Requiring two Projs refused a
        # shape that is complete.
        #
        # WHICH ARM GOES MISSING VARIES, so this cannot assume. Measured
        # across the three files that refused: comp/our.t and comp/multiline.t
        # keep index 1, base/translate.t keeps index 0. A fix keyed on one
        # would have passed two files and failed the third.
        if (@projs == 1) {
            my ($idx)  = keys %arm;
            my $present = $arm{$idx};
            my $join    = $self->_lone_arm_join($present, $next_of);
            my $body    = $self->_emit_from($present->{id}, $next_of, $join);

            # THE EMPTY ARM IS NOT AN `else {}`. It is the absence of one, and
            # the CONDITION must be negated when the arm that acts is the
            # FALSE one -- emitting `if (c) {body}` for an index-1 Proj would
            # run the body exactly when perl does not.
            # THE EMPTY ARM STILL CONTRIBUTES A PHI INPUT, so the
            # declaration seeds the variable with it and the present arm
            # overwrites -- the empty arm has no block to assign in.
            my ($decl, %assign) = $self->_join_phis($join, { $idx => $present },
                                                    $idx);
            $body .= $assign{$idx} // '';

            my $text = $idx == 0
                ? sprintf("if (%s) {\n%s}\n", $cond, _indent($body))
                : sprintf("if (!(%s)) {\n%s}\n", $cond, _indent($body));
            return ($decl . $text, $join);
        }

        # WHERE THE ARMS CONVERGE. A Region's inputs are the arms' last control
        # nodes, so it is the join. Find it by looking for the Region that both
        # arms reach.
        my $join = $self->_join_region($arm{0}, $arm{1}, $next_of);

        my $t = $self->_emit_from($arm{0}{id}, $next_of, $join);
        my $f = $self->_emit_from($arm{1}{id}, $next_of, $join);

        # A VALUE PHI AT THE JOIN IS A VARIABLE EACH ARM ASSIGNS. `if (c) {
        # return 1 } ... return 0` merges two values at the Region, and SSA
        # has no name for the result -- so the emitter declares one before the
        # branch and each arm writes its own input.
        #
        # WHICH INPUT BELONGS TO WHICH ARM IS ON THE NODE. The Phi carries
        # `predecessors`, the Proj ids in the same order as its inputs --
        # measured, `Phi(18) in=[1,2] predecessors=[10,15]`. Pairing by
        # position against %arm would be a guess; this is the graph saying so.
        my ($decl, %assign) = $self->_join_phis($join, \%arm);
        $t .= $assign{0} // '';
        $f .= $assign{1} // '';

        my $text = sprintf("if (%s) {\n%s}\n", $cond, _indent($t));
        $text = sprintf("if (%s) {\n%s} else {\n%s}\n",
            $cond, _indent($t), _indent($f)) if length $f;

        return ($decl . $text, $join);
    }

    # The join a lone arm falls through to: the first Region it reaches that
    # ALSO names the If's own predecessor, because the empty arm's control is
    # the If's control unchanged.
    #
    # _join_region cannot be used -- it needs two arms to intersect. Here the
    # empty arm contributes no nodes at all, so the join is identified by the
    # arm that does exist reaching a Region.
    method _lone_arm_join ($present, $next_of) {
        for my $id ($self->_control_reachable($present->{id}, $next_of)) {
            my $n = $nodes->{$id} or next;
            return $id if ($n->{op} // '') eq 'Region';
        }
        return undef;
    }

    # _join_phis($join, \%arm, $lone_idx) -> ($declaration, %per_arm_assignment)
    #
    # The VALUE Phis merging at $join, as a variable each arm assigns. A Phi's
    # `predecessors` field lists the Proj ids in the same order as its inputs,
    # so each input is matched to its arm by the graph rather than by position
    # -- measured, `Phi(18) in=[1,2] predecessors=[10,15]`.
    #
    # MEMORY PHIS ARE SKIPPED. They merge chains, not values, and are
    # discharged by placement like the Region itself.
    #
    # WITH A LONE ARM the absent one has no block to assign in, so the
    # declaration is seeded with ITS input and the present arm overwrites. The
    # declaration must come BEFORE the `if`, because a `my` inside the block
    # goes out of scope exactly where the join needs it.
    method _join_phis ($join, $arm, $lone_idx = undef) {
        return ('') unless defined $join;

        my @phis = sort { $a->{id} <=> $b->{id} }
                   grep { ($_->{op} // '') eq 'Phi'
                       && ((($_->{fields} // {})->{region} // -1) == $join)
                       && !$self->_is_memory($_->{id}) }
                   values $nodes->%*;
        return ('') unless @phis;

        my %proj_arm = map { $arm->{$_}{id} => $_ } keys $arm->%*;

        my ($decl, %assign) = ('');
        for my $p (@phis) {
            my @in   = ($p->{inputs} // [])->@*;
            my @pred = ((($p->{fields} // {})->{predecessors}) // [])->@*;
            die "GAP: a join Phi with " . scalar(@in) . " inputs and "
              . scalar(@pred) . " predecessors is not yet rendered\n"
                unless @in == @pred && @in;

            my $var = sprintf('$phi%d', $p->{id});

            # Seed with whichever input has no arm to assign in: the lone
            # case's absent arm, or the first input when every arm is present
            # (overwritten either way, and a declared-but-unset variable would
            # warn).
            my ($seed) = grep { !exists $proj_arm{ $pred[$_] } } 0 .. $#in;
            $seed //= 0;
            $decl .= sprintf("my %s = %s;\n", $var, $self->_expr($in[$seed]));

            for my $i (0 .. $#in) {
                my $a = $proj_arm{ $pred[$i] };
                next unless defined $a;
                $assign{$a} .= sprintf("%s = %s;\n", $var,
                                       $self->_expr($in[$i]));
            }
            $bound{ $p->{id} } = $var;
        }
        return ($decl, %assign);
    }

    # The Region both arms converge on, or undef when they do not rejoin (each
    # arm leaving the program, say). Its inputs ARE the arms' last control
    # nodes, so a Region naming a node reachable from each arm is the join.
    method _join_region ($true_proj, $false_proj, $next_of) {
        my %from_true = map { $_ => 1 } $self->_control_reachable($true_proj->{id}, $next_of);
        for my $id ($self->_control_reachable($false_proj->{id}, $next_of)) {
            my $n = $nodes->{$id} or next;
            next unless $n->{op} eq 'Region';
            my @ins = ($n->{inputs} // [])->@*;
            return $id if (grep { $from_true{$_} } @ins)
                       && (grep { !$from_true{$_} } @ins);
        }
        return undef;
    }

    # Every control node reachable forward from $id, including Region inputs
    # (a Region takes its predecessors as data inputs, not via control_in).
    method _control_reachable ($id, $next_of) {
        my (%seen, @queue, @out);
        @queue = ($id);
        while (@queue) {
            my $cur = shift @queue;
            next if $seen{$cur}++;
            push @out, $cur;
            push @queue, map { $_->{id} } ($next_of->{$cur} // [])->@*;
            # A Region consumes the arm's last control node as an input, so it
            # is a forward step the control_in index does not record.
            for my $n (values $nodes->%*) {
                next unless $n->{op} eq 'Region';
                push @queue, $n->{id}
                    if grep { $_ == $cur } (($n->{inputs} // [])->@*);
            }
        }
        return @out;
    }

    # INDENTATION IS COSMETIC AND MUST STAY THAT WAY. Splitting the emitted
    # source on every newline also splits newlines INSIDE string literals, so
    # "ok 1\n" came out as "ok 1\n    " -- the indent became part of the
    # program's OUTPUT. Emit statements as a list instead of re-splitting text,
    # and a literal is never touched.
    sub _indent ($text) {
        return $text;
    }

    method _emit_statement ($n, $next_of) {
        my $op = $n->{op};

        # `print (EXPR)` IS NOT `print EXPR`. Perl parses a leading open paren
        # as the complete argument list and discards whatever follows -- the
        # classic gotcha -- so `print ($c ? "y" : "n"), "\n"` prints only the
        # ternary. Measured: the emitted program printed "y\n" where the
        # original printed "n\n". Interposing `join('')` keeps the argument
        # list a list without ever starting it with a paren.
        # A DEFERRED AGGREGATE DECLARATION, placed after the effect it holds
        # rather than in the prologue. See _emit_control_chain.
        if ($op =~ /\A(?:Array|Hash)Literal\z/) {
            my $af = $n->{fields} // {};
            die "GAP: an anonymous $op reached as a statement is not yet"
              . " rendered\n" unless defined $af->{symbol};
            return sprintf("my %s%s = (%s);\n",
                ($af->{sigil} // '@'), $af->{symbol},
                join(', ', map { $self->_expr($_) } (($n->{inputs} // [])->@*)));
        }

        # AN Unwind IS A `die`. Measured across the three corpus files that
        # refused -- twelve nodes, uniform: no fields, control_in the chain
        # predecessor, inputs either one value node or nothing. The producer
        # builds it at two sites and both comments say `die`.
        #
        # TWO SHAPES HID BEHIND THE ONE MESSAGE, and one spelling covers both
        # because it is the node's own semantics:
        #
        #   arm terminator   control_in is an If's Proj, and the Unwind is
        #                    consumed as a Region input (the join). 11 of 12.
        #   body terminator  control_in is Start, no Region names it, and a
        #                    Return follows. 1 of 12: `sub v5 { die }`.
        #
        # THE CHAIN WALKS PAST IT, which is harmless: control does not
        # continue past a die, so whatever follows is unreachable and stays
        # observationally equivalent. Measured, what follows is the undef
        # Constant Return that _emit_statement already suppresses.
        #
        # ZERO INPUTS IS A BARE `die`, 3 of the 12. Indexing inputs[0]
        # unconditionally would render `die undef`, a different message.
        #
        # NOT AN ARRAYREF, whatever Unwind.pm's comment says: on the wire all
        # twelve carry a flat single value or nothing.
        if ($op eq 'Unwind') {
            my @in = ($n->{inputs} // [])->@*;
            return "die;\n" unless @in;
            return sprintf("die %s;\n", $self->_expr($in[0]));
        }

        if ($op eq 'Print') {
            my ($fh, @args) = $self->_print_parts($n);
            return sprintf("print %sjoin('', %s);\n", $fh, join(', ', @args));
        }

        # A package scalar store. The EntryDef names the slot; emitting the
        # assignment in chain order is what makes later reads observe it.
        if ($op eq 'EntryWrite') {
            my $slot = $nodes->{ $n->{inputs}[0] };
            return sprintf("%s = %s;\n",
                $self->_slot_name($slot), $self->_expr($n->{inputs}[1]));
        }

        # A LIST ASSIGN binds N targets from N values: inputs are the targets
        # followed by the values. `my ($a,$b) = (2,3)` is one statement, and
        # emitting it as one is what puts the slots in scope for later reads.
        if ($op eq 'Assign') {
            my @in = ($n->{inputs} // [])->@*;

            # TARGETS FIRST, THEN VALUES -- and the counts need not match. An
            # even split was wrong: `my ($x,$y) = @_` is TWO targets from ONE
            # source (the ArgsSource), and `my ($a,$b) = (2,3)` is two from
            # two. The targets are the leading slot nodes; everything after
            # them is the value list.
            my $t = 0;
            $t++ while $t < @in
                && ($nodes->{ $in[$t] }{op} // '')
                     =~ /\A(?:PadAccess|EntryDef|Subscript)\z/;

            # AN ELEMENT STORE NEEDS A NAMED CONTAINER. `my @a = (1,2,3)`
            # leaves NO variable in the graph -- measured, the array exists
            # only as an ArrayLiteral value and `@a` is gone -- so
            # `$a[0] = 7` arrives as
            #
            #     Assign(Subscript(ArrayLiteral, 0), 7)
            #
            # which says "store into element 0 of this literal". There is no
            # Perl for that: `(1,2,3)[0] = 7` is not assignable.
            #
            # REFUSED rather than given a fresh temporary. A temporary would be
            # a DIFFERENT container from the one every other read in the graph
            # names, so the store would land somewhere the reads never look --
            # and "does the read observe the store" is the question this whole
            # tool exists to answer. Same loss as keys/values/each
            # (docs/plans/2026-09-06), from the store side.
            for my $i (0 .. $t-1) {
                my $tgt = $nodes->{ $in[$i] };
                next unless ($tgt->{op} // '') eq 'Subscript';
                my $agg = $nodes->{ ($tgt->{inputs} // [])->[0] // -1 };
                # ONLY THE NAMELESS CASE REFUSES. A pad-bound aggregate now
                # carries the variable it was bound to, so the store has
                # something to assign through; an ANONYMOUS one still does not,
                # and `(1,2,3)[0] = 7` is not assignable.
                die "GAP: an element store into an anonymous container has no"
                  . " variable to name -- `(1,2,3)[0] = 7` is not"
                  . " assignable\n"
                    if $agg && ($agg->{op} // '') =~ /Literal\z/
                    && !defined(($agg->{fields} // {})->{symbol});
            }

            die "GAP: an Assign with no target slots is not yet rendered\n"
                unless $t;
            my @lhs = map { $self->_expr($_) } @in[0 .. $t-1];
            my @rhs = map { $self->_expr($_) } @in[$t .. $#in];
            die "GAP: an Assign with no values is not yet rendered\n"
                unless @rhs;
            # `my` DECLARES A SLOT; AN ELEMENT STORE WRITES ONE. The producer
            # does not record declaration separately from binding, so a write
            # to a pad slot is taken as its declaration -- but an element
            # target is an existing container's slot, and `my $a[0] = 7` is a
            # syntax error. Only a whole-slot target declares.
            my $all_slots = 1;
            for my $i (0 .. $t-1) {
                $all_slots = 0, last
                    unless ($nodes->{ $in[$i] }{op} // '')
                             =~ /\A(?:PadAccess|EntryDef)\z/;
            }
            my $decl = ($all_slots && (grep { /^\$/ } @lhs) == @lhs)
                ? 'my ' : '';
            return sprintf("%s(%s) = (%s);\n",
                $decl, join(', ', @lhs), join(', ', @rhs))
                if @lhs > 1;
            return sprintf("%s%s = %s;\n", $decl, $lhs[0], $rhs[0]);
        }

        # A VOID CALL IS AN EFFECT: dropping it loses whatever the sub did.
        return sprintf("%s;\n", $self->_call_expr($n)) if $op eq 'Call';

        # THE PROGRAM BODY'S Return CARRIES NOTHING OBSERVABLE -- it is the
        # implicit fall-off-the-end. A SUB's Return is a real `return` and
        # carries its value.
        if ($op eq 'Return') {
            my @in = ($n->{inputs} // [])->@*;
            return '' unless @in;
            my $v = $nodes->{ $in[0] };

            # The undef Constant every program body ends with is not a value
            # the source returned.
            return '' if $v && $v->{op} eq 'Constant'
                      && (($v->{fields} // {})->{const_type} // '') eq 'undef';

            # AN EFFECT IS NOT RE-RUN TO RETURN IT. A sub whose last statement
            # is a `print` returns print's value (1), and the Return names that
            # same node -- so emitting `return <expr>` ran the print A SECOND
            # TIME. Measured: `sub shout { print "loud\n" }` printed "loud"
            # twice. An effect already placed in the chain is returned by
            # falling off the end, exactly as perl does.
            return '' if $v && defined $v->{control_in};

            return sprintf("return %s;\n", $self->_expr($in[0]));
        }

        die "GAP: no rule for control node `$op`\n";
    }

    # A package variable's Perl spelling, from the fields the wire carries.
    # THE LVALUE A DESTRUCTIVE s/// MODIFIES, or undef when nothing names one.
    #
    # A destructive s/// needs a variable, and the producer hands the node a
    # VALUE -- either the Constant the variable was initialised from, or the
    # previous RegexSubst in a chain. Two steps recover the name:
    #
    #   1. Walk the subject back through any RegexSubst chain to its ROOT.
    #      Each link substituted into the same storage; only the first names a
    #      value that some EntryWrite bound.
    #   2. Find the EntryWrite whose written value IS that root, and take its
    #      slot. `$w = "aXbY"` emits EntryWrite(EntryDef $w, Constant "aXbY"),
    #      so the Constant identifies the variable unambiguously.
    #
    # A subject that already IS an EntryDef or PadAccess is its own lvalue and
    # needs no lookup -- that is the `sub mangle { $main::g =~ s/a/b/g }` shape,
    # where the producer never forwarded the binding.
    #
    # AMBIGUITY REFUSES. Two variables initialised from the same literal
    # hash-cons to one Constant, so a single value can be named by several
    # EntryWrites. Picking one would substitute into a variable the source did
    # not name, which is exactly the miscompile the old refusal existed to
    # prevent -- so more than one match is still a GAP.
    method _subst_lvalue ($sub) {
        my $root = $nodes->{ ($sub->{inputs} // [])->[0] // -1 };
        return undef unless $root;

        my %seen;
        while (($root->{op} // '') eq 'RegexSubst') {
            last if $seen{ $root->{id} // '' }++;
            my $next = $nodes->{ ($root->{inputs} // [])->[0] // -1 };
            last unless $next;
            $root = $next;
        }

        return $self->_slot_name($root) if ($root->{op} // '') eq 'EntryDef';
        return $self->_expr($root->{id})
            if ($root->{op} // '') eq 'PadAccess';

        my @slot;
        for my $n (values $nodes->%*) {
            next unless ($n->{op} // '') eq 'EntryWrite';
            my @in = ($n->{inputs} // [])->@*;
            next unless @in >= 2 && defined $in[1] && $in[1] == ($root->{id} // -1);
            push @slot, $nodes->{ $in[0] };
        }
        return undef unless @slot == 1;
        return undef unless ($slot[0]{op} // '') eq 'EntryDef';
        return $self->_slot_name($slot[0]);
    }

    method _slot_name ($n) {
        die "GAP: expected an EntryDef, got `$n->{op}`\n"
            unless $n->{op} eq 'EntryDef';
        my $f = $n->{fields} // {};
        my $sigil = $f->{sigil} // '$';
        my $stash = $f->{package} // 'main';
        my $name  = $f->{symbol};
        die "GAP: an EntryDef with no var_name is not yet rendered\n"
            unless defined $name;

        # A PUNCTUATION VARIABLE IS STORED AS ITS CONTROL CHARACTER. `$^O` is
        # literally ${"\x0f"} in the symbol table, and emitting that raw byte
        # gives perl "Unrecognized character \x0F" -- measured on base/num.t,
        # which reads $^O to skip OS-specific cases. The caret form is the
        # spelling that parses, and it is the same variable.
        #
        # These live in main:: only, and a package qualifier on one is a syntax
        # error, so they are emitted bare.
        if ($name =~ /\A([\x00-\x1f])(.*)\z/s) {
            my ($ctrl, $rest) = ($1, $2);
            return sprintf('%s^%s%s', $sigil, chr(ord($ctrl) + 64), $rest);
        }

        # `$_`, `$0`, `$1` and friends are also main-only and take no
        # qualifier: `$main::_` is legal but `$main::1` is not.
        return sprintf('%s%s', $sigil, $name)
            if $name !~ /\A[A-Za-z_]\w*\z/;

        return sprintf('%s%s::%s', $sigil, $stash, $name);
    }

    # _expr($id) -- a value node as a Perl expression.
    # Render a node as an expression, IGNORING its binding. Used exactly once
    # per bound effect -- at the chain position where the binding is made --
    # because `_expr` there would return the variable being defined.
    method _expr_uncached ($id) {
        my $save = delete $bound{$id};
        my $text = eval { $self->_expr($id) };
        my $err  = $@;
        $bound{$id} = $save if defined $save;
        die $err if $err;
        return $text;
    }

    method _expr ($id) {
        # A BOUND EFFECT IS READ, NOT RE-RUN. It already happened at its place
        # in the chain, and the variable holds what it produced.
        return $bound{$id} if exists $bound{$id};
        return $rendered{$id} if exists $rendered{$id};
        my $n = $nodes->{$id} or die "GAP: dangling input $id\n";
        my $op = $n->{op};
        my @in = ($n->{inputs} // [])->@*;

        my $text;
        if ($op eq 'Constant') {
            $text = $self->_constant($n);
        }
        elsif ($op eq 'Call') { $text = $self->_call_expr($n) }
        elsif ($op eq 'Print') {
            # A Print reached as a VALUE is one whose result is reused -- print
            # returns 1 on success. Emit it as the expression it is.
            my ($fh, @a) = $self->_print_parts($n);
            $text = $fh eq ''
                ? sprintf("print(join('', %s))", join(', ', @a))
                # NO PARENTHESISED FORM WITH A HANDLE. `print(FH LIST)` is a
                # syntax error; the handle-and-list form takes no parens, so
                # the whole thing is wrapped instead.
                : sprintf("(print %sjoin('', %s))", $fh, join(', ', @a));
        }
        elsif ($op eq 'RegexMatch') {
            # THE PATTERN AND FLAGS ARE THE PROGRAM. /i changes what matches,
            # /g how many times -- a dropped flag is a different program, not a
            # cosmetic loss, so both ride on the node and both are emitted.
            #
            # The pattern is emitted RAW between delimiters: it is already a
            # regex, and escaping it would turn metacharacters into literals.
            my $f = $n->{fields} // {};
            my $pat = $f->{pattern};
            die "GAP: a RegexMatch with no pattern is not yet rendered\n"
                unless defined $pat;
            die "GAP: a RegexMatch with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 1;
            $text = sprintf('(%s =~ m{%s}%s)',
                $self->_expr($in[0]), $pat, $f->{flags} // '');
        }
        elsif ($op eq 'RegexSubst') {
            # A SUBSTITUTION YIELDS THE MODIFIED STRING here rather than
            # mutating in place -- the producer threads the result to whatever
            # binds it. So it renders as a match-and-replace over a COPY, which
            # is what `s///r` means, and the binding is the caller's job.
            my $f = $n->{fields} // {};
            my $rep = $f->{replacement};
            die "GAP: a RegexSubst with no replacement is not yet rendered\n"
                unless defined $rep;
            ( my $flags = $f->{flags} // '' ) =~ s/r//g;

            # A COMPUTED PATTERN IS INPUT 1, and the node says so. Interpolating
            # the value is what makes it a pattern again: perl compiles the
            # string, which is exactly what the source `s/$P b$/X/` did.
            #
            # WRAPPED IN (?:...) because the value is a whole pattern and the
            # text around it is not. Without the group `s/$P b$/` would let a
            # value like `a|z` bind past its own extent -- the alternation
            # would swallow ` b$`, which the source never wrote.
            my $pat;
            if ($f->{pattern_is_input}) {
                die "GAP: a RegexSubst says its pattern is an input but has "
                  . scalar(@in) . " inputs\n" unless @in >= 2;
                $pat = sprintf('(?:${\ (%s) })', $self->_expr($in[1]));
            }
            else {
                $pat = $f->{pattern};
                die "GAP: a RegexSubst with no pattern is not yet rendered\n"
                    unless defined $pat;
            }
            $text = sprintf('(%s =~ s{%s}{%s}%sr)',
                $self->_expr($in[0]), $pat, $rep, $flags);
        }
        elsif ($op eq 'RegexSubstCount') {
            # THE COUNT IS NOT THE STRING. A destructive s/// in scalar context
            # yields how many substitutions happened, and the producer splits
            # that into its own node over the RegexSubst. Rendering it as the
            # subst would return the modified string instead of a number.
            die "GAP: a RegexSubstCount with " . scalar(@in) . " inputs is not"
              . " yet rendered\n" unless @in == 1;
            my $sub = $nodes->{ $in[0] };
            die "GAP: a RegexSubstCount over `" . ($sub->{op} // '?')
              . "` is not yet rendered\n"
                unless $sub && $sub->{op} eq 'RegexSubst';
            my $f = $sub->{fields} // {};
            ( my $flags = $f->{flags} // '' ) =~ s/r//g;

            # A COUNTED s/// MUST MODIFY SOMETHING. The destructive form is
            # what returns a count, and it needs an LVALUE -- but the producer
            # resolved the subject to the value it was bound to, so the graph
            # hands this a Constant. `"aaa" =~ s{a}{b}g` is a compile error
            # ("Can't modify constant item in substitution").
            #
            # THE GRAPH HAS NOT LOST THE TARGET -- an earlier revision of this
            # comment said it had. The producer resolves a package scalar's
            # read to the SSA VALUE it was bound to, so the subject is a
            # Constant or a previous RegexSubst. But the EntryWrite that bound
            # it still names the slot, so the lvalue is recoverable by walking
            # the subst chain to its root and finding what was written there.
            #
            # WITHOUT IT, A CHAIN IS UNSPELLABLE. SSA threads each destructive
            # s/// to the one before, which is the right graph -- the second
            # observes the first. Rendered literally that is
            #
            #     (($w =~ s{X}{}r) =~ s{Y}{})
            #
            # and perl refuses: "Can't modify substitution (s///) in
            # substitution (s///)". A destructive s/// needs an lvalue, and
            # only the variable is one. comp/redef.t is this shape twenty
            # times over.
            my $lv = $self->_subst_lvalue($sub);
            die "GAP: a counted s/// whose subject is a `"
              . (($nodes->{ ($sub->{inputs} // [])->[0] // -1 }{op}) // '?')
              . "` has no lvalue to modify -- the graph names a value, and no"
              . " EntryWrite names the variable it was bound to\n"
                unless defined $lv;

            # Counted, so NOT /r: the destructive form is what returns a count.
            # A COMPUTED PATTERN INTERPOLATES HERE TOO, wrapped the same way
            # and for the same reason. Reading the string field blindly would
            # emit an EMPTY pattern, which matches at every position -- a
            # substitution the source never wrote.
            my $cpat = $f->{pattern};
            if ($f->{pattern_is_input}) {
                my @sin = ($sub->{inputs} // [])->@*;
                die "GAP: a counted s/// says its pattern is an input but has "
                  . scalar(@sin) . " inputs\n" unless @sin >= 2;
                $cpat = sprintf('(?:${\ (%s) })', $self->_expr($sin[1]));
            }
            $text = sprintf('(%s =~ s{%s}{%s}%s)',
                $lv, $cpat, $f->{replacement}, $flags);
        }
        elsif ($op eq 'Subscript') {
            # AN ELEMENT READ, and its third input is the MEMORY it observes.
            # A read threaded to a store sees the stored value; one threaded
            # past it sees the old one. That ordering is the whole question
            # this oracle exists to check.
            #
            # THE CONTAINER MAY HAVE NO NAME. `my @a = (1,2,3)` leaves no
            # variable in the graph at all -- measured, the array exists only
            # as an ArrayLiteral value and `@a` is gone. A literal container is
            # indexed as a list slice, which is what the graph says; a named
            # one is indexed normally.
            die "GAP: a Subscript with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" if @in < 2;
            my $agg = $nodes->{ $in[0] };
            my $idx = $self->_expr($in[1]);
            my $kind = $agg->{op} // '';

            if ($kind eq 'ArrayLiteral' || $kind eq 'HashLiteral') {
                my $bare = ($agg->{fields} // {})->{symbol};
                if (defined $bare) {
                    # NAMED: index the variable. `$a[0]` reads and assigns;
                    # a list slice does neither. The SYMBOL is already the bare
                    # identifier -- no stripping, which is the point of
                    # carrying the parts rather than the blob.
                    $text = $kind eq 'ArrayLiteral'
                        ? sprintf('$%s[%s]', $bare, $idx)
                        : sprintf('$%s{%s}', $bare, $idx);
                }
                else {
                    # ANONYMOUS: a list slice over the literal. For a hash
                    # literal the key is LOOKED UP, not positionally indexed,
                    # so the two are not the same operation.
                    $text = $kind eq 'ArrayLiteral'
                        ? sprintf('(%s)[%s]', $self->_expr($in[0]) =~ s/\A\((.*)\)\z/$1/rs, $idx)
                        : sprintf('{%s}->{%s}', $self->_expr($in[0]) =~ s/\A\((.*)\)\z/$1/rs, $idx);
                }
            }
            else {
                # AN AGGREGATE IS NOT A REFERENCE. `@_` and `$r` both reach
                # here, and only one of them takes an arrow -- `@_->[0]` is a
                # syntax error ("Can't use an array as a reference"). The
                # STAMP separates them: Array/Hash is the container itself,
                # anything else is a ref to one.
                my $st = $agg->{stamp} // '';
                my $spelling = $self->_expr($in[0]);
                if ($st eq 'Array' || $st eq 'Hash') {
                    # Indexing a named aggregate switches the sigil to `$`:
                    # one element of `@_` is `$_[0]`.
                    die "GAP: an element of a `$kind` spelled `$spelling`"
                      . " has no aggregate sigil to switch\n"
                        unless $spelling =~ s/\A[\@\%]/\$/;
                    $text = $st eq 'Array'
                        ? sprintf('%s[%s]', $spelling, $idx)
                        : sprintf('%s{%s}', $spelling, $idx);
                }
                else {
                    $text = sprintf('%s->[%s]', $spelling, $idx);
                }
            }
        }
        elsif ($op eq 'Count') {
            # scalar(@a) -- the element count, and a memory-dependent read like
            # any other: inputs are [aggregate, memory].
            die "GAP: a Count with no aggregate is not yet rendered\n"
                unless @in;
            my $agg = $nodes->{ $in[0] };
            $text = ($agg->{op} // '') =~ /Literal\z/
                ? sprintf('scalar(%s)', $self->_expr($in[0]))
                : sprintf('scalar(@{%s})', $self->_expr($in[0]));
        }
        elsif ($op eq 'Length') {
            die "GAP: a Length with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 1;
            $text = sprintf('length(%s)', $self->_expr($in[0]));
        }
        elsif ($op eq 'ArrayLiteral' || $op eq 'HashLiteral') {
            # A NAMED AGGREGATE IS ITS VARIABLE. The node represents the
            # container, and when it was bound to a pad slot the name is the
            # only thing that can WRITE it -- `(1,2,3)[0] = 7` is not
            # assignable, `$a[0] = 7` is.
            #
            # The declaration is emitted separately (see _declare_aggregates),
            # because a Perl variable has to exist before it is indexed and the
            # graph has no node for "declare @a".
            my $af = $n->{fields} // {};
            my $vn = defined $af->{symbol}
                ? ($af->{sigil} // '@') . $af->{symbol} : undef;
            if (defined $vn) { $text = $vn }
            else {
                # ANONYMOUS, AND THE STAMP SAYS WHICH KIND. `[1,2]` is a
                # REFERENCE and `(1,2)` is a list, and the graph distinguishes
                # them -- measured, `my $a=[1,2]` gives ArrayLiteral
                # stamp=ArrayRef while an index list gives stamp=Array.
                #
                # Rendering a ref as a bare list gave `ref((1, 2))`, which
                # perl rejects: "Too many arguments for reference-type
                # operator". The brackets are not decoration; they are what
                # makes it one value.
                my $st = $n->{stamp} // '';
                my $body = join(', ', map { $self->_expr($_) } @in);
                $text = $st eq 'ArrayRef' ? "[$body]"
                      : $st eq 'HashRef'  ? "{$body}"
                      # A list. The consumer (a subscript, a list assign)
                      # decides what it means.
                      :                     "($body)";
            }
        }
        elsif ($op eq 'PostfixDeref') {
            # AN AGGREGATE-WIDE READ THAT OBSERVES STORES. Inputs are
            # [container, memory] and the sigil says which aggregate it is --
            # measured on `push @a, 3; print "@a"`:
            #
            #     10 PostfixDeref in=[4, 7] sigil='@'    4 = ArrayLiteral @a
            #
            # The memory edge is what makes the read see the push; it orders
            # the node and is never an operand.
            #
            # A NAMED container is just its variable: `@a` already means "the
            # elements as they now are". An anonymous one is a REFERENCE, and
            # the postfix deref is how the source spelled it.
            die "GAP: a PostfixDeref with " . scalar(@in) . " inputs is not"
              . " yet rendered\n" unless @in >= 1;
            my $sigil = ($n->{fields} // {})->{sigil} // '@';
            my $agg   = $nodes->{ $in[0] };
            my $af    = ($agg->{fields} // {});

            # AN AGGREGATE IS NOT A REFERENCE, and the stamp says which -- the
            # same distinction an element read needs. An ANONYMOUS aggregate
            # reaches here too: measured on `@foo[1..2]`, the index list is
            # `PostfixDeref(ArrayLiteral stamp=Array, memory)` with no symbol,
            # and `@{(1, 2)}` is not a dereference of anything -- it emitted an
            # empty slice. The literal IS the list.
            my $st = $agg->{stamp} // '';
            $text = ($agg->{op} // '') =~ /Literal\z/ && defined $af->{symbol}
                  ? sprintf('%s%s', $sigil, $af->{symbol})
                  : ($st eq 'Array' || $st eq 'Hash')
                  ? $self->_expr($in[0])
                  : sprintf('%s{%s}', $sigil, $self->_expr($in[0]));
        }
        elsif ($op eq 'ArgsSource') {
            # THE SUB'S ARGUMENT ARRAY. `my ($x,$y) = @_` binds from it, so it
            # renders as @_ and the emitted sub reads the same arguments.
            $text = '@_';
        }
        elsif ($op eq 'PadAccess') {
            # A LEXICAL READ. SSA has no variable names, but the producer
            # keeps the source spelling in parts -- so the name survives the
            # round trip and the emitted program reads the same slot.
            my $f = $n->{fields} // {};
            my $sym = $f->{symbol};
            die "GAP: a PadAccess with no symbol is not yet rendered\n"
                unless defined $sym && length $sym;
            $text = ($f->{sigil} // '') . $sym;
        }
        elsif ($op eq 'EntryDef') {
            # A read of the named slot. NOT folded to whatever was last stored:
            # the point of the oracle is that the RUNTIME decides what a read
            # sees, so the emitted program must read.
            $text = $self->_slot_name($n);
        }
        elsif (my $sym = $BINOP{$op}) { $text = $self->_binop($sym, @in) }
        elsif ($op eq 'TernaryExpr') {
            # cond ? then : else -- a VALUE select, distinct from the If
            # diamond, which is control. The producer builds this when both
            # arms yield a value and neither has an effect.
            die "GAP: a TernaryExpr with " . scalar(@in) . " inputs is not"
              . " yet rendered\n" unless @in == 3;
            $text = sprintf('(%s ? %s : %s)',
                $self->_expr($in[0]), $self->_expr($in[1]), $self->_expr($in[2]));
        }
        elsif ($op eq 'Coerce') {
            # A COERCE IS THE PRODUCER'S OWN NOTE, not something the source
            # said. perl converts between string and number implicitly at the
            # point of use, so the conversion is already carried by the
            # operator this feeds -- `$a + $b` numifies whatever it is given.
            # Emitting a cast would be inventing a step the program does not
            # take; passing the operand through renders what the SOURCE means.
            #
            # This is the one place the emitter is allowed to drop a node, and
            # only because the semantics survive: the round-trip proves it. If
            # a Coerce ever means something an operator does not already do,
            # this is where that shows up as a failing diff.
            die "GAP: a Coerce with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 1;
            $text = $self->_expr($in[0]);
        }
        # `&&`, `||` AND `//` YIELD AN OPERAND, not a boolean -- `0 || "x"` is
        # "x", not 1. Rendering them as a boolean test would agree on
        # truthiness and disagree on the value, the same class of defect as
        # `==` for `eq`.
        #
        # These are the VALUE forms. When the producer lowers a short-circuit
        # to control flow instead (an If/Region diamond), the diamond emission
        # handles it and no node reaches here -- measured, all four
        # short-circuit effect cases round-trip without these rules.
        elsif ($op eq 'And') { $text = $self->_binop('&&', @in) }
        elsif ($op eq 'Or')  { $text = $self->_binop('||', @in) }
        elsif ($op eq 'DefinedOr') { $text = $self->_binop('//', @in) }
        elsif ($op eq 'Xor') { $text = $self->_binop('xor', @in) }
        elsif ($op eq 'RefType') {
            # `ref EXPR` -- a unary whose op_str is already `ref`.
            # Parenthesised because `ref $x . "y"` parses as `ref($x . "y")`,
            # a different question.
            die "GAP: a RefType with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 1;
            $text = sprintf('ref(%s)', $self->_expr($in[0]));
        }
        elsif ($op eq 'RegexCapture') {
            # ONE GROUP OF A MATCH. inputs[0] is the match node and the `n`
            # field is the group number -- a rule that ignored `n` would
            # return the same group for $1 and $2.
            #
            # THE MATCH IS NOT RE-RUN HERE. It is already in the chain (a
            # capture is only meaningful after its match), and $1 reads
            # perl's own capture state rather than a value the graph carries.
            my $g = ($n->{fields} // {})->{n};
            die "GAP: a RegexCapture with no group number is not yet"
              . " rendered\n" unless defined $g;
            $text = sprintf('$%d', $g);
        }
        elsif ($op eq 'BacktickExpr') {
            # A SHELL COMMAND, capturing its output. qx{} rather than
            # backticks so the command text needs no backtick escaping.
            die "GAP: a BacktickExpr with " . scalar(@in) . " inputs is not"
              . " yet rendered\n" unless @in == 1;
            $text = sprintf('qx{${\ (%s) }}', $self->_expr($in[0]));
        }
        elsif ($op eq 'Slice') {
            # AN ARRAY SLICE, and its operands are [indices, container] --
            # measured on comp/term.t's `"@foo[0..1]b"`:
            #
            #     Slice(158) in=[157:PostfixDeref, 141:ArrayLiteral @main::foo]
            #
            # the container SECOND, which is the opposite of Subscript's order
            # and exactly what a positional guess gets backwards.
            #
            # THE SIGIL IS `@`, not the container's. `$a[0]` is one element;
            # `@a[0,1]` is a list of them, and the slice is the list form
            # however the container was spelled.
            die "GAP: a Slice with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 2;
            my $agg = $nodes->{ $in[1] };
            my $af  = ($agg->{fields} // {});
            die "GAP: a Slice over an anonymous `" . ($agg->{op} // '?')
              . "` has no container to name\n"
                unless defined $af->{symbol};
            $text = sprintf('@%s[%s]', $af->{symbol}, $self->_expr($in[0]));
        }
        elsif ($op eq 'Match') {
            # `=~` WITH A RUNTIME PATTERN. RegexMatch carries its pattern as a
            # string field; Match is the binop that takes a COMPUTED one --
            # measured on `$s =~ /${p}c/` with an unfoldable $p:
            #
            #     11 Concat  in=[9, 10]   stamp=Str
            #     12 Match   in=[2, 11]   stamp=Boolean
            #
            # so input 1 is the pattern value. Interpolating it back is what
            # makes it a pattern again: perl compiles the string.
            #
            # WRAPPED IN (?:...), for the reason the computed s/// pattern is:
            # the value is a whole pattern and the text around it is not, so
            # `a|z` would bind past its own extent and swallow what follows.
            die "GAP: a Match with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 2;
            # THE RIGHT-HAND SIDE MUST BE A PATTERN, not an expression that
            # happens to spell one -- `$s =~ (?:...)` is a syntax error. m{}
            # is the delimiter that needs no escaping of the value's text,
            # since the value is interpolated rather than written inline.
            $text = sprintf('(%s =~ m{(?:${\ (%s) })})',
                $self->_expr($in[0]), $self->_expr($in[1]));
        }
        elsif ($op eq 'Defined') {
            # A unary definedness test. Parenthesised because `defined $x + 1`
            # parses as `defined($x + 1)`, which is a different question.
            die "GAP: a Defined with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 1;
            $text = sprintf('defined(%s)', $self->_expr($in[0]));
        }
        elsif ($op eq 'Not') {
            die "GAP: a Not with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 1;
            $text = sprintf('(!%s)', $self->_expr($in[0]));
        }
        elsif ($op eq 'Phi') {
            # READING A LOOP PHI IS READING ITS VARIABLE. _emit_loop declares
            # one per Phi before the loop and assigns it at the bottom of the
            # body, so every read -- inside the body, in the condition, or
            # after the loop -- is that variable.
            #
            # A Phi whose region is NOT a Loop is a diamond join, and those are
            # inlined at the join rather than named. Reaching one here means a
            # merge the emitter has not placed, so it refuses rather than
            # naming a variable nothing declares.
            my $region = $nodes->{ ($n->{fields} // {})->{region} // -1 };
            die "GAP: a Phi whose region is a `"
              . (($region->{op}) // 'missing') . "` rather than a Loop is not"
              . " yet rendered\n"
                unless $region && ($region->{op} // '') eq 'Loop';
            $text = $self->_phi_var($n);
        }
        else {
            die "GAP: no rule for value node `$op`\n";
        }

        return $rendered{$id} = $text;
    }

    # _call_expr($n) -- a Call in whichever of its three dispatch kinds.
    #
    # Measured across the corpus files this unblocks: 105 direct, 19 builtin,
    # 8 method, and the wire discriminates them consistently -- a direct call
    # always carries `want` and never `class_name`, a method always carries
    # `class_name`, a builtin carries neither.
    # Whether a node is a point in the memory chain rather than a value.
    #
    # THESE ARE THE NODES A MEMORY EDGE CAN NAME: the chain starts at MemStart
    # and advances through every effect that stores -- a package write, an
    # element assign, a delete, an aggregate-mutating builtin -- plus a Phi
    # where two chains merge. A Call qualifies only when it is one of the
    # mutators, which is exactly a Call that itself carries a memory edge.
    method _is_memory ($id) {
        my $n = $nodes->{$id} or return 0;
        my $op = $n->{op} // '';
        return 1 if $op =~ /\A(?:MemStart|EntryWrite|CellWrite|Delete)\z/;
        return 1 if $op eq 'Assign';
        return 1 if $op eq 'Phi' && $self->_is_memory(($n->{inputs} // [])->[0] // -1);
        return 0 unless $op eq 'Call';
        my @in = ($n->{inputs} // [])->@*;
        return @in > 1 && $self->_is_memory($in[-1]) ? 1 : 0;
    }

    method _call_expr ($n) {
        my $f    = $n->{fields} // {};
        my $kind = $f->{dispatch_kind} // '';
        my $name = $f->{name};

        die "GAP: a Call with no name is not yet rendered\n"
            unless defined $name && length $name;

        # A MEMORY INPUT IS AN ORDERING EDGE, NOT AN ARGUMENT. The builtins
        # that read or mutate a whole container carry one so they observe
        # stores; rendering it emits the memory node as an extra operand, and
        # a MemStart has no spelling at all.
        #
        # THE DISCRIMINATOR IS STRUCTURAL, NOT A NAME LIST. This filtered on
        # `keys|values|each`, and the producer appends memory at THREE sites
        # covering more names than that:
        #
        #     FromOptree.pm:5981   keys values each
        #     FromOptree.pm:6027   push unshift splice
        #     FromOptree.pm:6060   shift pop
        #
        # so `shift` rendered its edge as a second argument and refused --
        # measured on comp/package.t, `Call(shift, [ArgsSource, MemStart])`.
        # A name list fails asymmetrically: it silently drops whichever name
        # nobody thought of, and the next one added would fail the same way.
        # What every site shares is the POSITION and the KIND -- a memory node
        # appended last -- so that is what this asks.
        my @in = (($n->{inputs} // [])->@*);
        pop @in if @in > ($MEM_MIN_INPUTS{Call} // 99)
                && $self->_is_memory($in[-1]);
        my @args = map { $self->_expr($_) } @in;

        if ($kind eq 'direct') {
            # PARENTHESISED ALWAYS. `f $x` is a syntax error unless f was
            # predeclared, and the emitted program defines its subs in whatever
            # order `sort` gives -- so never rely on the callee being visible.
            ( my $short = $name ) =~ s/^main:://;
            return sprintf('%s(%s)', $short, join(', ', @args));
        }

        if ($kind eq 'builtin') {
            # `keys`, `values` and `each` TAKE A CONTAINER, not a list --
            # `keys(("a",1))` is a compile error ("Type of arg 1 to keys must
            # be hash or array"). The operand here is a HashLiteral/ArrayLiteral
            # with no variable to name, so there is nothing to hand them.
            #
            # REFUSED rather than spelled around: binding a temporary would
            # emit a program whose aggregate is a DIFFERENT container from the
            # one the graph names, and the defect this tool exists to catch
            # (docs/plans/2026-09-06, keys/values/each do not observe stores)
            # is exactly about which container a read sees. A spelled-around
            # round-trip would agree with itself and hide it.
            # AN AGGREGATE-WIDE READ TAKES ITS CONTAINER, AND ITS MEMORY IS
            # NOT AN ARGUMENT. `keys` now carries [container, memory] so it can
            # observe stores; the memory edge orders the read and must not be
            # emitted as a second operand.
            #
            # A NAMED container renders as its variable. An ANONYMOUS one still
            # cannot: `keys(("a",1))` is a compile error, and binding a
            # temporary would name a DIFFERENT container from the one the graph
            # reads -- which is the whole question these ops were wrong about.
            if ($name =~ /\A(?:keys|values|each)\z/) {
                my $arg = $nodes->{ ($n->{inputs} // [])->[0] // -1 };
                die "GAP: `$name` over an anonymous aggregate has no container"
                  . " to name -- `keys((\"a\",1))` is not valid Perl\n"
                    if $arg && ($arg->{op} // '') =~ /Literal\z/
                    && !defined(($arg->{fields} // {})->{symbol});
                # THE STAMP CARRIES THE CONTEXT. `keys %h` in scalar context
                # is the COUNT and the producer stamps it Int; in list context
                # it is the keys and the stamp is a List kind. Emitting the
                # list form for a counted read printed the keys themselves --
                # measured, "ba" where perl printed 2.
                my $st = $n->{stamp} // '';
                my $call = sprintf('%s(%s)', $name, $args[0] // '');
                return $st eq 'Int' ? "scalar($call)" : $call;
            }
            return sprintf('%s(%s)', $name, join(', ', @args));
        }

        if ($kind eq 'method') {
            my $cls = $f->{class_name};
            die "GAP: a method Call with no class_name is not yet rendered\n"
                unless defined $cls;
            return sprintf('%s->%s(%s)', $cls, $name, join(', ', @args));
        }

        die "GAP: a Call with dispatch_kind `$kind` is not yet rendered\n";
    }

    method _binop ($perl_op, $l, $r) {
        return sprintf('(%s %s %s)',
            $self->_expr($l), $perl_op, $self->_expr($r));
    }

    # A Constant's Perl literal. The wire carries `value` as a string plus a
    # `const_type`, so the spelling is decided here rather than guessed from
    # the text -- "1" as a Str and 1 as an Int are different programs.
    # A Print's filehandle (already spelled, with its trailing space) and its
    # arguments.
    #
    # THE HANDLE IS OPERAND 0 WHEN THE NODE SAYS SO. `has_filehandle` is on the
    # wire precisely because operand 0 is otherwise an ordinary argument --
    # measured on comp/multiline.t, `Print(37) in=[14, 9] has_filehandle=1`
    # where 14 is the bareword glob Constant. Ignoring it printed the handle's
    # NAME to stdout and left the file empty: a program that runs and silently
    # writes nowhere.
    #
    # NO COMMA AFTER THE HANDLE. `print FH, LIST` passes the handle as a value
    # and prints to the default handle; only `print FH LIST` selects it.
    method _print_parts ($n) {
        my @in = ($n->{inputs} // [])->@*;
        return ('', map { $self->_expr($_) } @in)
            unless ($n->{fields} // {})->{has_filehandle};

        die "GAP: a Print says it has a filehandle but has no inputs\n"
            unless @in;
        my $h = shift @in;
        return ($self->_expr($h) . ' ', map { $self->_expr($_) } @in);
    }

    method _constant ($n) {
        my $f = $n->{fields} // {};
        my $t = $f->{const_type} // '';
        my $v = $f->{value};

        return 'undef' if $t eq 'undef' || !defined $v;
        return $v      if $t eq 'integer' || $t eq 'number';
        if ($t eq 'string') {
            # DOUBLE-QUOTED WITH EXPLICIT ESCAPES. A single-quoted literal
            # cannot carry a newline as \n, and these constants routinely hold
            # one ("ok 1 - if eq\n"). Escape the metacharacters rather than
            # relying on the shape of the text.
            my $s = $v;
            $s =~ s/\\/\\\\/g;
            $s =~ s/"/\\"/g;
            $s =~ s/\$/\\\$/g;
            $s =~ s/\@/\\\@/g;
            $s =~ s/\n/\\n/g;
            $s =~ s/\t/\\t/g;
            $s =~ s/\r/\\r/g;
            return '"' . $s . '"';
        }
        # A qr// LITERAL. The producer records the compiled pattern's text, and
        # it is emitted as a pattern rather than as a string -- the two are
        # different values, and only one of them matches.
        if ($t eq 'regex') {
            return sprintf('qr{%s}', $v);
        }

        # A BAREWORD FILEHANDLE, and the bareword IS the spelling. Measured on
        # comp/line_debug.t and comp/multiline.t, a `glob` Constant holds the
        # bare name and is an operand of open, close, readline and a
        # filehandle-Print -- so quoting it would open a file NAMED "TRY"
        # rather than use the handle, a program that runs and does the wrong
        # thing.
        #
        # Only a plain identifier is emitted bare: anything else is not a
        # bareword and would parse as something other than a handle.
        # A REFERENCE TO A CONSTANT. base/rs.t sets `$/ = \2`, the
        # record-separator form that reads fixed-size records -- measured,
        # `Constant const_type=ref value=2` read by an EntryWrite into $/.
        #
        # THE VALUE IS THE REFERENT, so the backslash is not decoration:
        # dropping it assigns the NUMBER to $/, which sets the separator to
        # that string and reads different records.
        if ($t eq 'ref') {
            return sprintf('\\%s', $v);
        }

        if ($t eq 'glob') {
            die "GAP: a glob Constant whose name is `$v` is not a bareword\n"
                unless $v =~ /\A[A-Za-z_]\w*\z/;
            return $v;
        }

        die "GAP: no rule for a `$t` Constant\n";
    }
}

1;
