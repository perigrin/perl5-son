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
        my $body = eval { $self->_emit_control_chain($graph) };
        if (!defined $body) { $gap = $@ || 'render failed with no reason'; return undef }
        return $out . $body;
    }

    # A named sub. Its body is the same control-chain walk the program body
    # gets; only the wrapper differs.
    method _emit_sub ($name, $graph) {
        my $save_nodes = $nodes;
        my %save_rendered = %rendered;
        $nodes = { map { $_->{id} => $_ } ($graph->{nodes} // [])->@* };
        %rendered = ();

        my $body = eval { $self->_emit_control_chain($graph) };
        my $err = $@;
        $nodes = $save_nodes;
        %rendered = %save_rendered;
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
        my $prologue = '';
        for my $n (sort { $a->{id} <=> $b->{id} } values $nodes->%*) {
            next unless $n->{op} eq 'Assign';
            next if defined $n->{control_in};   # already emitted in the chain
            $prologue .= $self->_emit_statement($n, \%next_of);
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

            $out .= $self->_emit_statement($n, $next_of);
            $cur = $n->{id};
        }
        return $out;
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
        die "GAP: an If with " . scalar(@projs) . " Proj arms is not yet"
          . " rendered\n" unless @projs == 2;
        die "GAP: an If arm that is not a Proj is not yet rendered\n"
            if grep { $_->{op} ne 'Proj' } @projs;

        my %arm = map { ($_->{fields}{index} // 0) => $_ } @projs;
        die "GAP: an If whose Projs are not indexed 0 and 1 is not yet"
          . " rendered\n" unless exists $arm{0} && exists $arm{1};

        # WHERE THE ARMS CONVERGE. A Region's inputs are the arms' last control
        # nodes, so it is the join. Find it by looking for the Region that both
        # arms reach.
        my $join = $self->_join_region($arm{0}, $arm{1}, $next_of);

        my $t = $self->_emit_from($arm{0}{id}, $next_of, $join);
        my $f = $self->_emit_from($arm{1}{id}, $next_of, $join);

        my $text = sprintf("if (%s) {\n%s}\n", $cond, _indent($t));
        $text = sprintf("if (%s) {\n%s} else {\n%s}\n",
            $cond, _indent($t), _indent($f)) if length $f;

        return ($text, $join);
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
        if ($op eq 'Print') {
            my @args = map { $self->_expr($_) } (($n->{inputs} // [])->@*);
            return sprintf("print join('', %s);\n", join(', ', @args));
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
                die "GAP: an element store into a literal container has no"
                  . " variable to name -- the graph kept the aggregate's VALUE"
                  . " but not its name, and `(1,2,3)[0] = 7` is not"
                  . " assignable\n"
                    if $agg && ($agg->{op} // '') =~ /Literal\z/;
            }

            die "GAP: an Assign with no target slots is not yet rendered\n"
                unless $t;
            my @lhs = map { $self->_expr($_) } @in[0 .. $t-1];
            my @rhs = map { $self->_expr($_) } @in[$t .. $#in];
            die "GAP: an Assign with no values is not yet rendered\n"
                unless @rhs;
            # `my` is what puts a lexical in scope; the producer does not record
            # declaration separately from binding, so the first write to a pad
            # slot declares it.
            my $decl = (grep { /^\$/ } @lhs) == @lhs ? 'my ' : '';
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
    method _slot_name ($n) {
        die "GAP: expected an EntryDef, got `$n->{op}`\n"
            unless $n->{op} eq 'EntryDef';
        my $f = $n->{fields} // {};
        my $sigil = $f->{sigil} // '$';
        my $stash = $f->{stash_name} // 'main';
        my $name  = $f->{var_name};
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
    method _expr ($id) {
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
            my @a = map { $self->_expr($_) } (($n->{inputs} // [])->@*);
            $text = sprintf("print(join('', %s))", join(', ', @a));
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
            my $pat = $f->{pattern};
            die "GAP: a RegexSubst with no pattern is not yet rendered\n"
                unless defined $pat;
            my $rep = $f->{replacement};
            die "GAP: a RegexSubst with no replacement is not yet rendered\n"
                unless defined $rep;
            ( my $flags = $f->{flags} // '' ) =~ s/r//g;
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
            # REFUSED rather than spelled around. Binding a temporary would
            # emit a program that substitutes into a DIFFERENT variable from
            # the one the source named, and whether the original is modified is
            # the observable difference between s/// and s///r. The graph has
            # lost the target here; that is a finding, not a rendering problem.
            my $subj = $nodes->{ ($sub->{inputs} // [])->[0] // -1 };
            die "GAP: a counted s/// whose subject is a `"
              . (($subj->{op} // '?')) . "` has no lvalue to modify -- the"
              . " graph names a value, not the variable the source"
              . " substituted into\n"
                if $subj && $subj->{op} eq 'Constant';

            # Counted, so NOT /r: the destructive form is what returns a count.
            $text = sprintf('(%s =~ s{%s}{%s}%s)',
                $self->_expr(($sub->{inputs} // [])->[0]),
                $f->{pattern}, $f->{replacement}, $flags);
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
                # A list slice over the literal: `(1,2,3)[1]`. For a hash
                # literal the key must be LOOKED UP, not positionally indexed,
                # so those two are not the same operation.
                $text = $kind eq 'ArrayLiteral'
                    ? sprintf('(%s)[%s]', $self->_expr($in[0]) =~ s/\A\((.*)\)\z/$1/rs, $idx)
                    : sprintf('{%s}->{%s}', $self->_expr($in[0]) =~ s/\A\((.*)\)\z/$1/rs, $idx);
            }
            else {
                $text = sprintf('%s->[%s]', $self->_expr($in[0]), $idx);
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
            # A LIST, spelled as one. The producer distinguishes the two by
            # what it BUILT; in an expression both are a parenthesised list,
            # and the consumer (keys, a list assign) decides what it means.
            $text = sprintf('(%s)',
                join(', ', map { $self->_expr($_) } @in));
        }
        elsif ($op eq 'ArgsSource') {
            # THE SUB'S ARGUMENT ARRAY. `my ($x,$y) = @_` binds from it, so it
            # renders as @_ and the emitted sub reads the same arguments.
            $text = '@_';
        }
        elsif ($op eq 'PadAccess') {
            # A LEXICAL READ. SSA has no variable names, but the producer keeps
            # the source spelling in `varname` -- so the name survives the round
            # trip and the emitted program reads the same slot the original did.
            my $v = ($n->{fields} // {})->{varname};
            die "GAP: a PadAccess with no varname is not yet rendered\n"
                unless defined $v && length $v;
            $text = $v;
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
        elsif ($op eq 'Not') {
            die "GAP: a Not with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 1;
            $text = sprintf('(!%s)', $self->_expr($in[0]));
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
    method _call_expr ($n) {
        my $f    = $n->{fields} // {};
        my $kind = $f->{dispatch_kind} // '';
        my $name = $f->{name};
        my @args = map { $self->_expr($_) } (($n->{inputs} // [])->@*);

        die "GAP: a Call with no name is not yet rendered\n"
            unless defined $name && length $name;

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
            if ($name =~ /\A(?:keys|values|each)\z/) {
                my $arg = $nodes->{ ($n->{inputs} // [])->[0] // -1 };
                die "GAP: `$name` over a literal aggregate has no container to"
                  . " name -- see docs/plans/2026-09-06-keys-values-each-do-"
                  . "not-observe-stores.md\n"
                    if $arg && ($arg->{op} // '') =~ /Literal\z/;
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

        die "GAP: no rule for a `$t` Constant\n";
    }
}

1;
