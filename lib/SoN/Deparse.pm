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

    # Bindings pinned to the Region that joins a loop's exit: they read a loop
    # Phi, which only settles once the loop has closed, and the prologue would
    # hoist them above it. Keyed by Region id, flushed when the walk reaches it.
    field %after_region;

    # The whole `methods` map, and the name of the sub being emitted. A body
    # does not name its own cells -- a CellParam indexes into the enclosing
    # AnonSub's captures, which live in the CALLER's graph.
    field $all_methods = {};
    field $current_sub;

    # Variables already declared as cells, so the chain does not re-declare
    # them: a second `my` would shadow the captured lexical.
    field %cell_slots;

    # Join-Phi variables needing a declaration at the top of the sub, because
    # a join can outlive the branch that assigns into it.
    field %hoisted;

    # _is_memory's answer per node. Per-sub, since node ids are.
    field %mem_cache;

    # True while emitting a block eval's body, so the walk does not re-claim
    # the eval whose entry it starts from. See _emit_eval.
    our $in_eval_body = 0;

    # NODES THAT CARRY A TRAILING MEMORY EDGE, and the number of real operands
    # that precede it. A node of this kind with MORE inputs than its operand
    # count has a memory edge last; anything else does not, however much its
    # last input looks like one.
    #
    # Taken from the producer's construction sites rather than guessed:
    # FromOptree.pm builds Call with [args..., memory] at three sites
    # (keys/values/each, push/unshift/splice, shift/pop), and the aggregate
    # readers and writers each append one the same way.
    # An op name to its Perl spelling, for ops perl does not name after the
    # keyword that produced them. A plain string is a function name; a coderef
    # spells an OPERATOR, which takes no parens.
    #
    # Only the ops that actually reach the wire are here. The `prototype`
    # check beside this table catches any that do not, so a name missing from
    # here refuses rather than emitting an undefined sub call -- the failure
    # this table exists to stop.
    our %BUILTIN_SPELLING = (
        prtf   => 'printf',
        # `times` is the op `tms`. Four values (user/system, and the same for
        # children), so the same op-name-vs-keyword trap one builtin over.
        tms    => 'times',
        # `do EXPR` runs a file. It is a named unary operator, so it takes no
        # parens around a parenthesised expression the way a function would --
        # `dofile($f)` is a call to a sub that does not exist.
        dofile => sub { sprintf('do %s', $_[0]) },
        # schomp/schop are not here because they no longer reach this table:
        # the producer builds a Chomp node for them, which carries the kind
        # and whose store back to the target the graph records. They were
        # refused here while that node did not exist, because spelling them
        # `chomp` would have turned a loud "Undefined subroutine &main::schomp"
        # into a silent wrong answer.
        # A FILETEST IS AN OPERATOR: `-e $f`, not `ftis($f)`.
        ftis   => sub { sprintf('(-e %s)', $_[0]) },
        ftchr  => sub { sprintf('(-c %s)', $_[0]) },
        ftdir  => sub { sprintf('(-d %s)', $_[0]) },
        ftfile => sub { sprintf('(-f %s)', $_[0]) },
        ftlink => sub { sprintf('(-l %s)', $_[0]) },
        ftzero => sub { sprintf('(-z %s)', $_[0]) },
    );

    our %MEM_MIN_INPUTS = (
        Call         => 1,   # [arg, ..., memory]
        EntryWrite   => 2,   # [slot, value, memory]
        Assign       => 2,   # [target, value, memory]
        Delete       => 2,   # [container, key, memory]
        # THE SAME SHAPE AS Delete, one operator over, and it was missing --
        # so `exists $h{k}` counted its memory edge as a VALUE, bound the
        # EntryWrite that produced it, and then asked to render a store as an
        # expression: "no rule for value node `EntryWrite`" on comp/require.t.
        # t/deparse-memory-table-matches-producer.t scrapes FromOptree for the
        # construction sites so this table cannot drift from it again.
        Exists       => 2,   # [container, key, memory]
        Subscript    => 2,   # [container, index, memory]
        Count        => 1,   # [aggregate, memory]
        PostfixDeref => 1,   # [container, memory]
        EntryDef     => 0,   # [memory] -- ordering only
        # A pad slot that is address-taken lives in memory, so its READ
        # carries a memory version too -- measured, `my $x=1; my $r=\$x`
        # gives `PadAccess(6) in=[Assign]`, the store it observes. Counting
        # that as a value bound the Assign and asked to render it as one.
        PadAccess    => 0,   # [memory] -- ordering only
        # A destructive s/// stores into its target, so it advances the chain
        # and carries it. Its optional slots make the operand count vary, so
        # the table cannot express it -- _subst_operands resolves those from
        # `pattern_is_input` and the `replacement` field, and the memory edge
        # is whatever is left. Listed at 1 so the reads scan drops a trailing
        # memory input; the renderer never consults this entry.
        RegexSubst   => 1,
        # A destructive tr/// stores into its target, so it advances the
        # memory chain and carries the version it supersedes. Without this the
        # trailing memory edge counted as a VALUE, which bound the EntryWrite
        # that produced it and then asked to render a store as an expression
        # -- "no rule for value node `EntryWrite`".
        Transliterate => 1,
        MakeCell     => 1,   # [init_value, memory]
        CellRead     => 1,   # [cell, memory]
        CellWrite    => 2,   # [cell, value, memory]
    );
    field %rendered;   # id => Perl expression text

    # A COUNTED s/// BOUND AT ITS STORE. The destructive form yields the
    # count, so the store emits it once and records the variable holding that
    # number here. Kept apart from %bound, which holds the substituted STRING
    # for the same node -- one substitution, two different results, and a
    # single map would hand a reader whichever was written last.
    field %subst_count_var;   # RegexSubst id => variable holding its count

    # THE ENCLOSING LOOP'S EXIT REGION, while its body is being emitted.
    #
    # A mid-body `last` reaches the graph as an extra PREDECESSOR of that
    # Region -- the producer's @break_projs -- so an If inside the body whose
    # arm lands there is a BREAK, not a local diamond. Without knowing which
    # Region that is, _emit_if treated the loop exit as an ordinary join and
    # emitted the continuation inline, inside the loop.
    #
    # This is the dominance test every structured-output compiler uses
    # (Relooper, Stackifier): a forward edge whose source is inside the loop
    # and whose target is outside is a break. Here the target is known
    # exactly, so no dominance computation is needed -- see
    # docs/plans/2026-09-18-how-other-son-implementations-emit-a-break.md.
    field $loop_exit_region;

    # THE ASSIGNMENT A BREAK OWES ITS EXIT PHI, keyed on the Phi's id.
    # _emit_loop computes it before walking the body (the `last` is emitted
    # during that walk), and the break arm emits it immediately before the
    # `last` -- the only point on that path where the value is in scope.
    field %break_assign;

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
        $all_methods = $methods;

        # CELLS FIRST, before any sub. A named sub emitted above the program
        # body can only close over a lexical already in scope, and the cell is
        # exactly that shared lexical.
        my $out = $self->_emit_cell_declarations;

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
        %after_region = ();
        %hoisted  = ();
        %mem_cache = ();
        %subst_count_var = ();
        my $body = eval { $self->_emit_control_chain($graph) };
        if (!defined $body) { $gap = $@ || 'render failed with no reason'; return undef }
        # A FEATURE-GATED OPERATOR NEEDS ITS GATE. `isa` is a syntax error
        # without `use v5.36` -- measured, `$o isa Foo` gives "Bareword found
        # where operator expected". The source had the gate; the emission must
        # too, or a graph that translated correctly emits Perl that does not
        # compile.
        #
        # Emitted only when a gated node is present, so the common case keeps
        # its current output byte-for-byte and no existing round trip moves.
        my $needs_gate = grep {
            ( $_->{op} // '' ) eq 'IsaOp'
        } values $nodes->%*;
        return ( $needs_gate ? "use v5.36;\n" : '' ) . $out . $body;
    }

    # A named sub. Its body is the same control-chain walk the program body
    # gets; only the wrapper differs.
    # A SUB NAME AS A PERL IDENTIFIER.
    #
    # THE WIRE NAME IS NOT ONE. An anon sub's body is keyed by its DEFINITION
    # SITE -- measured, `main::__PROGRAM__::__ANON__:1:2` -- because that is
    # what makes two `sub { 7 }` at different lines two subs. Emitted verbatim
    # it does not parse: "Invalid separator character '1' in attribute list".
    #
    # Mangled the same way at every site that spells a name -- the definition,
    # a direct call, and a reference -- because a reference that does not match
    # its definition is a call to a sub nothing defined.
    #
    # THE MANGLING MUST BE INJECTIVE, since two distinct bodies collapsing to
    # one name would silently call the wrong one: every illegal character
    # becomes its hex code, which no legal name can produce.
    # A CELL'S VARIABLE. A captured lexical is a cell -- measured,
    # `my $n = 0; my $inc = sub { $n = $n+1 }` gives
    # `MakeCell captured_written=1 cell_name='$n'` with each closure's body
    # holding CellParam/CellRead/CellWrite over it.
    #
    # THE BODIES ARE SEPARATE `methods` ENTRIES, emitted as named subs, so the
    # cell cannot be a `my` inside either of them: it has to be one variable
    # they both close over. Perl's own closures capture exactly that way, so
    # the spelling is a lexical declared before the subs -- which the emitter
    # already does, since every sub is written out before the program body.
    #
    # NAMED FROM THE NODE ID, not from cell_name. Two `my $n` in different
    # scopes are two cells with the same source name, and sharing a variable
    # between them would make one closure see the other's writes.
    #
    # THE CELL IS THE PAD SLOT, NOT A COPY OF IT. Measured on
    # `my $k = 7; my $get = sub { $k }`:
    #
    #      3 PadAccess  sigil='$' symbol='k'
    #      5 Assign     in=[3, 4]  ci=0        the `my $k = 7`
    #     11 MakeCell   in=[1, 5]  cell_name='$k'
    #
    # MakeCell's input 0 is the UNDEF constant and input 1 is that Assign as
    # MEMORY -- so the cell holds no value of its own, and the value lives in
    # the pad slot the Assign bound. Declaring a separate `my $cell11` gave a
    # variable nothing ever wrote, and the closure returned undef.
    #
    # So the cell is SPELLED as the slot it shadows, and the sub closes over
    # the same lexical perl's own closure would. The declaration then comes
    # from the Assign already in the chain, and nothing needs hoisting.
    # TAKES THE NODE, NOT AN ID. A CellParam resolves to a MakeCell in the
    # CALLER's graph, and looking that id up in the body's `$nodes` found a
    # different node or none -- so the body spelled `$cell11` while the
    # program spelled `$k`, and the closure read a variable nothing wrote.
    # An element's Perl spelling: `$a[$i]`, `$h{k}`, or `$r->[$i]`.
    #
    # SHARED BY Subscript, Exists AND Delete, which all take
    # [container, key, memory] and all face the same question -- is the
    # container an aggregate or a reference, and which bracket does it take.
    # Three copies of that decision is how one operator ends up meaning two
    # things; see the Subscript rule for the measurements behind each branch.
    method _element ($container_id, $key) {
        my $agg  = $nodes->{$container_id};
        my $af   = ($agg->{fields} // {});
        my $kind = $agg->{op} // '';

        my $st = $agg->{stamp} // '';
        $kind = '' if $st eq 'ArrayRef' || $st eq 'HashRef';

        if ($kind =~ /\A(?:Array|Hash)Literal\z/) {
            # NAMED: index the variable. `$a[0]` reads and assigns; a list
            # slice does neither. The SYMBOL is already the bare identifier --
            # no stripping, which is the point of carrying the parts rather
            # than the blob.
            # A PACKAGE AGGREGATE'S SYMBOL IS NOT BARE. It records the whole
            # qualified spelling (`@main::E`), so prefixing `$` gave
            # `$@main::E[0]`, which does not parse. An ELEMENT takes `$`
            # whatever the container's sigil, so strip the one the symbol
            # carries rather than adding a second.
            if (defined $af->{symbol}) {
                ( my $bare = $af->{symbol} ) =~ s/\A[\$\@%]//;
                $bare = $self->_spell_name($bare);
                return $kind eq 'ArrayLiteral'
                    ? sprintf('$%s[%s]', $bare, $key)
                    : sprintf('$%s{%s}', $bare, $key);
            }

            # ANONYMOUS: a list slice over the literal. For a hash literal the
            # key is LOOKED UP, not positionally indexed, so the two are not
            # the same operation.
            my $body = $self->_expr($container_id) =~ s/\A\((.*)\)\z/$1/rs;
            return $kind eq 'ArrayLiteral'
                ? sprintf('(%s)[%s]', $body, $key)
                : sprintf('{%s}->{%s}', $body, $key);
        }

        my $sg = $af->{sigil} // '';
        $st = $sg eq '@' ? 'Array' : $sg eq '%' ? 'Hash' : $st;
        my $spelling = $self->_expr($container_id);

        if ($st eq 'Array' || $st eq 'Hash') {
            die "GAP: an element of a `$kind` spelled `$spelling` has no"
              . " aggregate sigil to switch\n"
                unless $spelling =~ s/\A[\@\%]/\$/;
            return $st eq 'Array' ? sprintf('%s[%s]', $spelling, $key)
                                  : sprintf('%s{%s}', $spelling, $key);
        }

        # A LIST IS NOT A REFERENCE. `->[...]` dereferences, and a
        # list-valued CALL has nothing to dereference: measured,
        # `split(/\n/,$p)->[1]` dies ("Can't use string as an ARRAY ref")
        # while `(split(/\n/,$p))[1]` gives the element.
        #
        # The arrow fallback was right for a REF and silently wrong for a
        # list -- and comp/retainedlines.t indexes a split inside a loop
        # body, so the emitted program died there every iteration. That file
        # is why a deparse of it had been spinning for 28 hours.
        return sprintf('(%s)[%s]', $spelling, $key)
            if $st eq 'List';

        # THE REFERENCE IS PARENTHESIZED for the same reason the List branch
        # above parenthesizes: `\@a->[0]` does not mean "element 0 of the
        # reference", it means a reference TO `@a->[0]`, and perl rejects it
        # with "Can't use an array as a reference". Measured on
        # `my @a=(10,20); my $s=\@a; print "$$s[0]"`, whose graph is correct --
        # `Ref/ArrayRef` over `ArrayLiteral` with a `Subscript` into it -- and
        # whose emission died. `(\@a)->[0]` is the same node spelled so perl
        # reads it as the graph says.
        #
        # A bare variable needs no parens and gets them anyway. That is the
        # emitter being ugly rather than wrong, which is the trade its own
        # design records: ugly and faithful is the product.
        my $ref = ( $spelling =~ /\A\$?[A-Za-z_]\w*\z/ )
            ? $spelling : sprintf('(%s)', $spelling);
        return $st eq 'HashRef' ? sprintf('%s->{%s}', $ref, $key)
                                : sprintf('%s->[%s]', $ref, $key);
    }

    method _cell_var ($cell) {
        my $nm = $cell ? (($cell->{fields} // {})->{cell_name}) : undef;
        return $nm if defined $nm && $nm =~ /\A[\$\@\%][A-Za-z_]\w*\z/;
        return sprintf('$cell%d', ($cell->{id} // 0));
    }

    # The MakeCell a CellParam refers to, resolved through the AnonSub that
    # names this body.
    #
    # A BODY DOES NOT NAME ITS OWN CELLS. CellParam carries an INDEX into the
    # enclosing AnonSub's captures, so the answer lives in the CALLER's graph
    # -- which is why this reads $all_methods rather than $nodes.
    method _cell_for_param ($p) {
        my $idx = ($p->{fields} // {})->{index} // 0;
        return undef unless defined $current_sub;

        for my $m (sort keys $all_methods->%*) {
            for my $n (($all_methods->{$m}{nodes} // [])->@*) {
                next unless ($n->{op} // '') eq 'AnonSub';
                next unless (($n->{fields} // {})->{name} // '') eq $current_sub;
                my @in = ($n->{inputs} // [])->@*;
                next unless defined $in[$idx];
                for my $c (($all_methods->{$m}{nodes} // [])->@*) {
                    return $c if $c->{id} == $in[$idx]
                              && ($c->{op} // '') eq 'MakeCell';
                }
            }
        }
        return undef;
    }

    # Every cell in the program, declared before the subs that close over it.
    #
    # A NAMED SUB IS EMITTED ABOVE THE PROGRAM BODY and can only close over a
    # lexical already in scope, so the declaration is hoisted here while the
    # ASSIGNMENT stays where the chain puts it. A cell allocated inside a loop
    # is a new cell per iteration, and hoisting its value would share one
    # across all of them.
    #
    # EVERY CELL IS DECLARED HERE, including one spelled as the pad slot it
    # shadows -- the sub is emitted ABOVE the program body, so a `my $k` left
    # in the chain comes too late and the closure captures nothing. Measured:
    # the body returned $k correctly and the program still printed nothing,
    # because the sub closed over a $k that did not yet exist.
    #
    # The chain's own `my` for that slot is suppressed in turn (see
    # %cell_slots), since re-declaring it would shadow the captured one and
    # the closure's writes would stop being visible.
    method _emit_cell_declarations () {
        my $out = '';
        %cell_slots = ();
        my $save = $nodes;
        for my $m (sort keys $all_methods->%*) {
            $nodes = { map { $_->{id} => $_ }
                       (($all_methods->{$m}{nodes} // [])->@*) };
            for my $n (sort { $a->{id} <=> $b->{id} }
                       (($all_methods->{$m}{nodes} // [])->@*)) {
                next unless ($n->{op} // '') eq 'MakeCell';
                my $v = $self->_cell_var($n);
                next if $cell_slots{$v}++;
                $out .= sprintf("my %s;\n", $v);
            }
        }
        $nodes = $save;
        return $out;
    }


    method _sub_ident ($name) {
        ( my $short = $name ) =~ s/^main:://;

        # A REAL PACKAGE SUB KEEPS ITS PACKAGE. `xyz::new` is already a legal
        # fully-qualified name, and flattening it to `xyz__new` defined the
        # sub in main:: while the CALL site still emitted `xyz->new()` --
        # which dispatches to the real `xyz` package and found nothing there.
        # Measured on comp/package.t: five packages collapsed into one and
        # `xyz->new` died with "Can't locate object method".
        #
        # The mangling exists for names perl cannot spell as identifiers: an
        # anon sub arrives as `main::__PROGRAM__::__ANON__:1:2`, whose `1:2`
        # tail is not a legal package or sub name. Those still mangle -- the
        # test is whether every segment is an identifier, not whether a `::`
        # is present.
        return $short
            if $short =~ /\A[A-Za-z_]\w*(?:::[A-Za-z_]\w*)+\z/;

        $short =~ s/::/__/g;
        $short =~ s/([^A-Za-z0-9_])/sprintf('_%02x', ord $1)/ge;
        return $short;
    }

    method _emit_sub ($name, $graph) {
        my $save_nodes = $nodes;
        my %save_rendered = %rendered;
        # NODE IDS ARE PER-SUB, so the bindings are too -- node 3 in one sub is
        # a different node from node 3 in another. Carrying them over emitted
        # `my shift(@_) = shift(@_)`, the caller's binding read as this sub's.
        my %save_bound = %bound;
        my %save_after = %after_effect;
        my %save_region = %after_region;
        my %save_hoist = %hoisted;
        my %save_mem   = %mem_cache;
        my $save_sub = $current_sub;
        $current_sub = $name;
        $nodes = { map { $_->{id} => $_ } ($graph->{nodes} // [])->@* };
        %rendered = ();
        %bound    = ();
        %after_effect = ();
        %after_region = ();
        %hoisted  = ();
        %mem_cache = ();
        %subst_count_var = ();

        my $body = eval { $self->_emit_control_chain($graph) };
        my $err = $@;
        $current_sub = $save_sub;
        $nodes = $save_nodes;
        %rendered = %save_rendered;
        %bound    = %save_bound;
        %after_effect = %save_after;
        %after_region = %save_region;
        %hoisted  = %save_hoist;
        %mem_cache = %save_mem;
        die $err unless defined $body;

        return sprintf("sub %s {\n%s}\n", $self->_sub_ident($name), $body);
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
            my $vn = $self->_agg_name($n);

            # AN AGGREGATE WHOSE CONTENTS ARE A CHAIN-BOUND EFFECT CANNOT
            # FLOAT EITHER. `my @got = <R>` builds ArrayLiteral(sym=got)
            # holding the readline's value -- measured -- and hoisting the
            # declaration put `my @got = ($eff21)` above the line declaring
            # $eff21. Same rule as the pad bindings below, same reason.
            # THE LAST BOUND INPUT, NOT THE FIRST. Attaching to the first one
            # and stopping places the literal after that binding and BEFORE
            # every later one. Measured on two list-returning calls in one
            # list:
            #
            #     sub two { return (1, 2) }
            #     my @r = (two(0), two(0));   perl: scalar(@r) is 4
            #
            #     my @eff3 = two(0);
            #     my @r = (@eff3, @eff4);     <- the empty PACKAGE array
            #     my @eff4 = two(0);
            #
            # It COMPILES without strict, `perl -w` says only "Name
            # "main::eff4" used only once", and the program printed 2. A silent
            # wrong answer in the path that does not refuse.
            #
            # The literal must follow EVERY binding it reads, so the latest one
            # is the only safe anchor.
            my $defer;
            for my $in (($n->{inputs} // [])->@*) {
                next unless defined $in && exists $bound{$in};
                $defer = $in;
            }
            if (defined $defer) {
                push $after_effect{$defer}->@*, $n;
                next;
            }

            # A PACKAGE AGGREGATE IS NOT DECLARED WITH `my`. `my @main::EST`
            # is a syntax error -- "can't be in a package" -- and the package
            # variable needs no declaration to exist. Same rule the Assign
            # branch applies to EntryDef targets, one node kind over.
            $prologue .= sprintf("%s%s = (%s);\n",
                ($self->_agg_is_package($n) ? '' : 'my '), $vn,
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
            # THE LAST BOUND INPUT, for the reason spelled out at the
            # ArrayLiteral loop above: an Assign reading TWO bound effects must
            # follow BOTH, and anchoring to the first places it between them.
            # Same rule, same loop shape, kept identical so the two cannot
            # drift -- this file has lost a day to "one operator, two
            # declaration sites" more than once.
            my $deferred;
            for my $in (($n->{inputs} // [])->@*) {
                next unless defined $in && exists $bound{$in};
                $deferred = $in;
            }
            if (defined $deferred) {
                push $after_effect{$deferred}->@*, $n;
                next;
            }

            # A BINDING OF A LOOP PHI CANNOT FLOAT EITHER, and a loop Phi is
            # not in %bound -- it gets its variable from _emit_loop, not from
            # the chain walker, so the rule above does not see it.
            #
            # `@_ = map { "rhu$_" } "barb2"` is Assign(ArgsSource, Phi) over
            # the map's accumulator. Hoisted, it emitted `@_ = (@phi27);`
            # ABOVE the while loop that fills @phi27, so @_ took the empty
            # initial value and the program printed nothing where perl prints
            # `rhubarb2`.
            #
            # A Phi whose `region` names a Loop settles only when the loop
            # ends, so the binding belongs immediately after it -- NOT at the
            # end of the body. A later read is still on the chain: the `print
            # "@_"` here follows the loop, and an end-of-body epilogue put the
            # assignment after the print, which printed nothing just the same.
            #
            # The loop's exit Proj leads to the Region that joins it, and that
            # Region is walked like any other chain node. Attaching the
            # binding there places it exactly where the loop has closed and
            # nothing has read the target yet.
            my $join;
            for my $in (($n->{inputs} // [])->@*) {
                my $src = defined $in ? $nodes->{$in} : undef;
                next unless $src && ($src->{op} // '') eq 'Phi';
                my $r = ($src->{fields} // {})->{region} // $src->{region};
                next unless defined $r;
                my $rn = $nodes->{$r};
                next unless $rn && ($rn->{op} // '') eq 'Loop';
                $join = $self->_loop_join($r);
                last;
            }
            if (defined $join) {
                push $after_region{$join}->@*, $n;
                next;
            }

            $prologue .= $self->_emit_statement($n, \%next_of);
        }

        # A deferred binding is emitted where its effect was placed, so the
        # chain has to be walked again now that %after_effect is populated.
        # Cheap, and it keeps the placement rule in one direction: the chain
        # decides, the prologue only takes what the chain cannot order.
        # %after_region is populated by the same pass and needs the same
        # re-walk: the first walk ran before the entry existed, so without
        # this the binding was silently DROPPED rather than merely misplaced.
        if (keys %after_effect || keys %after_region) {
            %rendered = ();
            $body = $self->_emit_from($start->{id}, \%next_of, undef);
        }

        # JOIN-PHI DECLARATIONS FIRST. They are discovered while walking, so
        # they can only be emitted once the walk is done -- and they must come
        # before it, because a join outlives the branch that assigns into it.
        my $decls = join '',
            map { "my $hoisted{$_};\n" }
            sort keys %hoisted;

        return $decls . $prologue . $body;
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
            # CLAIMED AT THE ENTRY, NOT AT THE JOIN. A block eval's body is
            # ordinary chain between the two, so by the time the walk ARRIVES
            # at the Region those statements are already emitted -- measured,
            # they appeared both before the `eval {` and inside it, and a
            # `die` among them escaped.
            #
            # So the eval is recognised when the walk is standing ON its
            # entry: the whole construct is emitted, and the walk resumes at
            # the join. A string eval has no entry and is still claimed at its
            # Region, where its one-node body needs no delimiting.
            if (!$in_eval_body
                    && (my $join = $self->_eval_join_entered_at($cur, $next_of))) {
                $out .= $self->_emit_eval($join, $cur, $next_of);
                $cur = $join->{id};
                next;
            }

            if ($n->{op} eq 'Region' && $self->_is_eval_join($n)) {
                $out .= $self->_emit_eval($n, $cur, $next_of);
                $cur = $n->{id};
                next;
            }

            # A JOIN THE CHAIN PASSES THROUGH. An early return inside a
            # NESTED branch leaves a Region the walk reaches as a plain
            # statement -- measured on
            # `if ($g) { if ($g>1) { print "a"; return 1 } } return 0`:
            #
            #      7 If     Proj 8 (true) / Proj 14 (false)
            #     11 If     Proj 12 (true) / Proj 15 (false)
            #     16 Region in=[14, 15]      the two FALSE arms
            #     17 Region in=[13, 16]      the function exit
            #     18 Phi    predecessors=[12, 16] region=17
            #
            # The outer If's arms never converge at a Region BETWEEN them: the
            # true arm runs into the inner If and only rejoins at 16, where
            # the outer false arm also lands. So _emit_if resumes at 16 and
            # the chain then meets 17, which nothing claimed.
            #
            # IT NEEDS NO SPELLING, only passing through: the arms were
            # already emitted by the Ifs that own them, and any value merging
            # here is a Phi those Ifs' _join_phis already bound. Emitting
            # anything would duplicate an arm.
            #
            # A MEMORY Region IS ALSO NOTHING TO SAY -- chains merge, and the
            # ordering is the placement.
            if ($n->{op} eq 'Region') {
                # A binding pinned to this Region goes here -- the loop it
                # reads from has closed. This branch returns early, so the
                # flush at the bottom of the walk never sees a Region.
                $out .= $self->_emit_statement($_, $next_of)
                    for (delete($after_region{ $n->{id} }) // [])->@*;
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
                # A binding that reads this loop's Phi goes HERE -- right
                # after the closing brace, where the accumulator has settled
                # and nothing has read the target yet. Pinned to the loop's
                # join Region, which _emit_loop steps over rather than
                # walking, so the Region branch below never sees it.
                my $join = $self->_loop_join($n->{id});
                $out .= $self->_emit_statement($_, $next_of)
                    for (delete($after_region{ $join // -1 }) // [])->@*;
                last unless defined $after;
                last if defined $stop && $after == $stop;
                $cur = $after;
                next;
            }

            # A BOUND EFFECT BINDS AT ITS CHAIN POSITION. `_emit_statement`
            # would emit it bare, and the reads would then have nothing to
            # name -- so the value is captured here, once, where it happens.
            if (exists $bound{ $n->{id} }) {
                # A COUNTED DESTRUCTIVE s/// ON A LEXICAL RUNS EXACTLY ONCE.
                # The RegexSubst has two consumers -- the binding here, and the
                # RegexSubstCount over it -- and rendering each independently
                # runs the substitution twice. The second sees the already-
                # substituted string. Measured on
                # `my $s="aaa"; my $n = ($s =~ s/a/b/g); print "$s $n"`:
                #
                #     perl   bbb 3
                #     before " "     -- both halves lost
                #
                # The DESTRUCTIVE form does both jobs: it mutates the slot in
                # place and yields the count. So emit it here, bound to the
                # count temporary, and let the count read that binding while
                # later reads of the subject name the variable itself.
                #
                # THE SAME SPLIT `EntryWrite` MAKES for a package scalar, one
                # binding mechanism over. A pad has no EntryWrite -- the rebind
                # IS the mechanism -- so the arm has to live here, where a pad
                # binding is emitted.
                if (my $c = $self->_counted_lexical_subst($n)) {
                    $out .= $c;
                    $out .= $self->_emit_statement($_, $next_of)
                        for (($after_effect{ $n->{id} } // [])->@*);
                    $out .= $self->_emit_statement($_, $next_of)
                        for (delete($after_region{ $n->{id} }) // [])->@*;
                    $cur = $n->{id};
                    next;
                }

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
            # A binding pinned to this Region goes here: the loop it reads
            # from has closed, and nothing after it has read the target yet.
            $out .= $self->_emit_statement($_, $next_of)
                for (delete($after_region{ $n->{id} }) // [])->@*;
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

        # NO PROJS IS `while (1)`. There is no header condition to test, so
        # the producer emits no arms and the EXIT LIVES INSIDE THE BODY as an
        # If hanging off the Loop -- measured on
        # `my $x=0; while (1) { $x = $x+1; last if $x == 3 }`:
        #
        #      4 Loop  in=[0]      ci=0        NO Projs
        #      5 Phi   in=[3, 7]   region=4    the induction
        #     14 If    in=[4, 13]  ci=4        the exit test
        #     15 Proj  in=[14] index=0         LEAVES, to the continuation
        #     19 Proj  in=[14] index=1         ITERATES
        #
        # So the If's index-0 arm is what FOLLOWS the loop, not an arm of a
        # branch within it -- which is why this cannot be left to _emit_if:
        # it would emit the continuation inside the loop body and run it every
        # iteration.
        return $self->_emit_endless_loop($n, $next_of) unless @projs;

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
        die "GAP: a Loop with no condition node is not yet rendered\n"
            unless @cond;

        # Effects pinned on the loop that are not the test: they run once per
        # iteration, before it.
        my @pre_cond;

        # MORE THAN ONE PINNED NODE IS AN EFFECT PLUS A TEST, not two tests.
        # Measured on `while (my $line = <R>) { ... }`:
        #
        #     Loop 22
        #       cond: 30 Call    [9]   name=readline
        #       cond: 31 Defined [30]
        #
        # The readline is an EFFECT that must run once per iteration -- it
        # advances the handle -- and the Defined OVER it is the test. They are
        # one expression, and rendering the test alone re-runs the effect
        # wherever its value is read.
        #
        # THE TEST IS THE ONE NOTHING ELSE PINNED HERE CONSUMES. Ordering by
        # id would be a guess; this is the graph saying which is the root of
        # the expression.
        if (@cond > 1) {
            my %consumed;
            for my $c (@cond) {
                $consumed{$_} = 1 for (($c->{inputs} // [])->@*);
            }
            my @root = grep { !$consumed{ $_->{id} } } @cond;
            die "GAP: a Loop with " . scalar(@cond) . " pinned nodes and "
              . scalar(@root) . " of them unconsumed is not yet rendered\n"
                unless @root == 1;

            # THE EFFECT RUNS ONCE PER ITERATION, INSIDE THE LOOP. It is
            # bound to a variable (an effect whose value is read always is),
            # and that binding has to be emitted where the effect happens --
            # at the TOP of the body, before the test reads it.
            #
            # Emitting `while (defined($eff30))` with the binding left to the
            # chain walk gave a condition over a variable nothing assigned,
            # and the loop never ran.
            #
            # A `do { } while` shape, testing at the BOTTOM, would run the
            # body once before the first test -- which is a different program.
            # So the effect is emitted at the top and the test is negated into
            # a `last`, which runs it before every iteration including the
            # first.
            @pre_cond = grep { $_->{id} != $root[0]{id} } @cond;
            @cond = @root;
        }

        # A MEMORY PHI CARRIES THE CHAIN, NOT A VALUE. Measured on
        # comp/retainedlines.t, three nested loops each with one:
        #
        #     13 MemStart
        #     14 Phi in=[13, 14] region=4     region 4 is a Loop
        #     15 Phi in=[14, 15] region=7
        #     16 Phi in=[15, 16] region=10
        #
        # The second input is the Phi ITSELF -- correct SSA for a back edge,
        # since at the header memory is either the entry value or what the body
        # left. Declaring a variable for it asked for a MemStart as an
        # expression, and a MemStart has no spelling.
        #
        # _join_phis already skips these at a branch join; a loop header is the
        # same question. A VALUE Phi still gets its variable, which is what
        # makes a loop-carried counter work.
        my @phis = sort { $a->{id} <=> $b->{id} }
                   grep { ($_->{op} // '') eq 'Phi'
                       && (($_->{fields}{region} // -1) == $n->{id})
                       && !$self->_is_memory($_->{id}) }
                   values $nodes->%*;
        for my $p (@phis) {
            die "GAP: a loop Phi with " . scalar(($p->{inputs} // [])->@*)
              . " inputs is not yet rendered\n"
                unless ($p->{inputs} // [])->@* == 2;
        }

        my $init = '';
        $init .= sprintf("my %s = %s;\n", $self->_phi_var($_),
                         $self->_expr($_->{inputs}[0])) for @phis;

        # A LOOP-INVARIANT PART OF THE TEST IS COMPUTED ONCE, AT ENTRY.
        #
        # `foreach $t ($c .. $c+3)` iterates a list perl builds when the loop
        # is ENTERED, so its bound is fixed even if the body assigns to $c.
        # The graph says so: the bound hangs off the EntryDef naming the
        # version of $c that existed at entry, and nothing in it comes from
        # this loop's Phis.
        #
        # An EntryDef renders as the variable's NAME, though, not as the
        # version it stands for. Re-rendering the test each iteration therefore
        # re-READ a global the body increments, and on base/rs.t
        # `while ((($main::test_count + 3) + 1) > $phi226)` advanced its bound
        # in step with its counter: the file spun at 97% CPU printing
        # `ok 2106390 # skipped on non-VMS system` where perl prints four
        # lines.
        #
        # Binding the maximal Phi-free subtrees of the test to temporaries
        # emitted before the loop pins them to their entry values, and _expr
        # returns the temporary everywhere the test is rendered afterwards.
        #
        # THE BINDING IS SCOPED TO THE LOOP. %bound is read by every later
        # _expr, and an `$inv` temporary is only in scope between this loop's
        # `my` and its closing brace. Leaving the binding behind spelled a
        # node as `$inv26` in a statement AFTER the loop -- and, on a second
        # loop over the same node, produced `my $inv26 = $inv26;`.
        # HOISTING IS FORM-DEPENDENT, and the Loop says which form it is.
        # A foreach fixes its bound at entry, so pinning it to a temporary is
        # what makes `foreach my $i (1..$n) { $n = 10 }` iterate twice rather
        # than chase the counter. A `while` or C-style `for` RE-READS its
        # condition every pass, and the same hoist never terminates --
        # measured, `for ($i=0; $i<3; $i++)` emitted
        # `my $inv = $main::i; while ($inv <= 3)` and spun forever.
        #
        # Three graph-derived discriminators were tried and none separated
        # the forms (see SoN::IR::Node::Loop's `bound`), so the producer
        # marks it.
        my @invariant =
            ( ( $n->{fields} // {} )->{bound} // 'each' ) eq 'entry'
            ? $self->_loop_invariant_roots($cond[0], $n->{id})
            : ();
        my %save_inv;
        for my $inv (@invariant) {
            my $var  = sprintf('$inv%d', $inv->{id});
            my $text = $self->_expr($inv->{id});
            $init .= sprintf("my %s = %s;\n", $var, $text);
            $save_inv{ $inv->{id} } = $bound{ $inv->{id} };
            $bound{ $inv->{id} } = $var;
        }

        # SCOPED TO THIS LOOP'S BODY, and saved/restored so a nested loop's
        # break does not read the outer loop's exit as its own.
        # THE REGION, NOT THE PROJ. Both the header-false Proj and any break
        # Proj feed the SAME exit Region -- measured, Proj 8 and Proj 16 are
        # both consumed by Region 17 -- so the Region is what a break arm
        # lands on and what identifies one.
        my ($exit_rgn) = grep { ( $_->{op} // '' ) eq 'Region' }
            ( $next_of->{ $arm{1}{id} } // [] )->@*;
        my $save_exit = $loop_exit_region;
        $loop_exit_region = $exit_rgn ? $exit_rgn->{id} : undef;

        # AN EXIT PHI IS THE VALUE FROM WHICHEVER EXIT RAN. A loop with a
        # mid-body `last` has TWO exits, and a slot whose value differs
        # between them gets a Phi regioned on the exit Region -- the
        # producer's _bind_break_exit_phis, over [header-Phi, break-binding],
        # paired positionally with the Region's predecessors (header-false
        # first, then each break).
        #
        # IT READS AS THE LOOP VARIABLE. Input 0 IS the loop's header Phi, and
        # that Phi already owns a variable holding the header-false value when
        # the loop falls out the bottom. So only the BREAK path is missing:
        # assign the break's value to that same variable just before the
        # `last`, and every later read is right on both paths with no new
        # declaration.
        #
        # COMPUTED BEFORE THE BODY WALK because the `last` is emitted during
        # it. Without this the Phi reached _expr, found no variable for a
        # non-Loop-regioned Phi, and refused.
        %break_assign = ();
        if ($exit_rgn) {
            for my $ph (values $nodes->%*) {
                next unless ($ph->{op} // '') eq 'Phi';
                next unless (($ph->{fields} // {})->{region} // -1)
                            == $exit_rgn->{id};
                my @pin = ($ph->{inputs} // [])->@*;
                next unless @pin == 2;
                my $header = $nodes->{ $pin[0] // -1 } or next;

                # A LOOP-CARRIED SLOT REUSES ITS OWN VARIABLE. When input 0 is
                # the loop's header Phi, that Phi already owns a variable and
                # it already holds the right value on the fall-out path, so
                # only the break needs to assign.
                #
                # A SLOT WRITTEN ONLY ON THE BREAK PATH HAS NO HEADER PHI.
                # `my $found = 0; foreach (..) { if (C) { $found = 1; last } }`
                # never touches $found in the body, so its exit Phi is
                # [Constant 0, Constant 1] and input 0 is not a Phi at all.
                # That one needs a variable of its own, declared before the
                # loop and seeded with input 0 -- which is exactly the
                # fall-out value.
                my $var;
                if (($header->{op} // '') eq 'Phi') {
                    $var = $self->_phi_var($header);
                }
                else {
                    $var = sprintf('$exit%d', $ph->{id});
                    $init .= sprintf("my %s = %s;\n",
                        $var, $self->_expr($pin[0]));
                }
                $bound{ $ph->{id} }        = $var;
                $break_assign{ $ph->{id} } = sprintf("%s = %s;\n",
                    $var, $self->_expr($pin[1]));
            }
        }

        my $body = $self->_emit_from($arm{0}{id}, $next_of, undef);
        $loop_exit_region = $save_exit;

        # Next values into temporaries first, then assign: see above.
        my $step = '';
        if (@phis) {
            $step .= sprintf("my %s_next = %s;\n", $self->_phi_var($_),
                             $self->_expr($_->{inputs}[1])) for @phis;
            $step .= sprintf("%s = %s_next;\n", $self->_phi_var($_),
                             $self->_phi_var($_)) for @phis;
        }

        # A PER-ITERATION EFFECT TURNS THE HEADER TEST INTO A `last`. The
        # effect must run before each test, including the first, so it cannot
        # sit in a `while (COND)` header -- and a bottom-tested loop would run
        # the body once before testing, a different program.
        my $text;
        if (@pre_cond) {
            my $pre = '';
            for my $e (@pre_cond) {
                my $var = $bound{ $e->{id} };
                $pre .= defined $var
                    ? sprintf("my %s = %s;\n", $var,
                              $self->_expr_uncached($e->{id}))
                    : sprintf("%s;\n", $self->_expr_uncached($e->{id}));
            }
            $text = $init . sprintf("while (1) {\n%s}\n",
                _indent($pre
                      . sprintf("last unless %s;\n",
                                $self->_expr($cond[0]{id}))
                      . $body . $step));
        }
        else {
            $text = $init . sprintf("while (%s) {\n%s}\n",
                $self->_expr($cond[0]{id}), _indent($body . $step));
        }

        for my $id (keys %save_inv) {
            if (defined $save_inv{$id}) { $bound{$id} = $save_inv{$id} }
            else                        { delete $bound{$id} }
        }

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

    # _loop_invariant_roots($test, $loop_id) -- the maximal subtrees of a
    # loop's test whose value is fixed when the loop is entered.
    #
    # Maximal, so one temporary covers a whole bound rather than one per
    # operand. The test itself is never a root: a test that depended on
    # nothing in the loop would never change, and hoisting it would turn the
    # loop into `while ($tmp)`.
    #
    # NOT-INVARIANT IS REACHING A PHI OF THIS LOOP. That is the graph's own
    # statement of what the iteration carries; anything else was computed
    # before the Loop node and cannot change while it runs.
    #
    # ONLY SUBTREES CONTAINING AN EntryDef ARE HOISTED. An EntryDef is the one
    # node whose rendering is a NAME rather than a value -- it spells the
    # variable, so it reads whatever that variable holds NOW, while the node
    # stands for the version at entry. A subtree of constants renders the same
    # text every iteration, and giving it a temporary would add a variable
    # that buys nothing.
    method _loop_invariant_roots ($test, $loop_id) {
        my %carried;
        my $carries; $carries = sub ($id, $seen) {
            return $carried{$id} if exists $carried{$id};
            return 0 if $seen->{$id}++;
            my $n = $nodes->{$id} or return 0;
            return $carried{$id} = 1
                if ($n->{op} // '') eq 'Phi'
                && ($n->{fields}{region} // -1) == $loop_id;
            my $any = 0;
            $any ||= $carries->($_, $seen) for ($n->{inputs} // [])->@*;
            return $carried{$id} = $any;
        };

        my %has_entry;
        my $names; $names = sub ($id, $seen) {
            return $has_entry{$id} if exists $has_entry{$id};
            return 0 if $seen->{$id}++;
            my $n = $nodes->{$id} or return 0;
            return $has_entry{$id} = 1 if ($n->{op} // '') eq 'EntryDef';
            my $any = 0;
            $any ||= $names->($_, $seen) for ($n->{inputs} // [])->@*;
            return $has_entry{$id} = $any;
        };

        my @roots;
        my %seen;
        my @queue = (($test->{inputs} // [])->@*);
        while (@queue) {
            my $id = shift @queue;
            next if $seen{$id}++;
            my $n = $nodes->{$id} or next;
            if ( !$carries->($id, {}) ) {
                push @roots, $n if $names->($id, {});
                next;
            }
            push @queue, ($n->{inputs} // [])->@*;
        }
        return @roots;
    }

    # A loop Phi's variable. Named from the node id because SSA has no name for
    # it -- the source's `$i` is gone by the time a Phi exists, and inventing a
    # readable one risks colliding with a pad slot the program still uses.
    # A LIST-VALUED PHI NEEDS AN ARRAY. A map's accumulator is a Phi over
    # ListAppend -- measured, `Phi(7) stamp=Array` beside the index
    # `Phi(21) stamp=Int` -- and binding a list to a SCALAR collapses it to
    # the last element: `my $phi7 = ()` then `map { $_*2 } (1,2,3)` printed
    # `6` instead of `2 4 6`.
    # _agg_name($node) -- an Array/HashLiteral's Perl spelling, or undef when
    # it is anonymous.
    #
    # THE SYMBOL SOMETIMES ALREADY CARRIES THE SIGIL. A PAD aggregate records
    # a bare name (`EST`) beside sigil `@`; a PACKAGE one records the whole
    # qualified spelling (`@main::EST`) and sets the sigil as well.
    # Concatenating both gave `@@main::EST`, which does not parse -- measured
    # on `our @EST = ("foo","bar")`, and base/lex.t's emitted program died at
    # compile time on exactly that.
    #
    # Whether the symbol is already spelled is what separates them, so ask the
    # symbol rather than guessing from the node.
    method _agg_name ($n) {
        my $af  = $n->{fields} // {};
        my $sym = $af->{symbol};
        return undef unless defined $sym && length $sym;

        my ($sigil, $bare) = $sym =~ /\A([\$\@%])(.*)\z/s
            ? ($1, $2) : (($af->{sigil} // '@'), $sym);
        return $sigil . $self->_spell_name($bare);
    }

    # A PUNCTUATION VARIABLE IS STORED AS ITS CONTROL CHARACTER, package
    # qualifier and all: `%{^TEST}` is `%main::\x14EST` in the symbol table,
    # and emitting that raw byte gives perl "Unrecognized character \x14".
    # The caret form is the spelling that parses, and it is the same variable.
    #
    # SHARED WITH _slot_name, which had this for scalars only -- base/lex.t
    # reaches it through `%{^TEST}` and `@{^TEST}`, which the scalar path
    # never saw.
    method _spell_name ($name) {
        my $pkg = '';
        if ($name =~ /\A(.*::)(.*)\z/s) { ($pkg, $name) = ($1, $2) }
        if ($name =~ /\A([\x00-\x1f])(.*)\z/s) {
            # Caret variables live in main:: only, and a qualifier on one is a
            # syntax error, so the package part is dropped rather than kept.
            #
            # BRACED WHEN THE NAME IS MORE THAN THE CARET LETTER. `%^TEST`
            # does not parse -- perl reads `^T` and then a bareword `EST` --
            # so a multi-character caret name needs `%{^TEST}`. Measured:
            # `%{^TEST} = (a=>1)` is accepted, `%^TEST = (a=>1)` is a syntax
            # error.
            my $caret = sprintf('^%s%s', chr(ord($1) + 64), $2);
            return length($2) ? "{$caret}" : $caret;
        }
        return $pkg . $name;
    }

    # Whether an aggregate is a PACKAGE variable rather than a pad slot.
    # `my @main::EST` is a syntax error -- "can't be in a package" -- so the
    # reconstructed declaration must leave the `my` off for these.
    method _agg_is_package ($n) {
        my $sym = ($n->{fields} // {})->{symbol} // '';
        return $sym =~ /::/ ? 1 : 0;
    }

    # _loop_join($loop_id) -- the Region that joins a Loop's exit, or undef.
    #
    # Found by following the loop's EXIT Proj to the Region naming it, rather
    # than by adjacency: the two Projs are the continue and exit arms, and
    # which index is which is not fixed. A Region that names a Proj of this
    # loop is the join whichever arm it came from, since only the exit arm
    # reaches code after the loop.
    method _loop_join ($loop_id) {
        my %proj = map { $_->{id} => 1 }
            grep { ($_->{op} // '') eq 'Proj'
                   && (($_->{inputs} // [])->[0] // -1) == $loop_id }
            values $nodes->%*;
        return undef unless keys %proj;
        for my $n (sort { $a->{id} <=> $b->{id} } values $nodes->%*) {
            next unless ($n->{op} // '') eq 'Region';
            for my $in (($n->{inputs} // [])->@*) {
                return $n->{id} if defined $in && $proj{$in};
            }
        }
        return undef;
    }

    # _feeds_list_assign($id) -- does this node's value reach an Assign with
    # more than one target?
    #
    # Such a node is evaluated in LIST context by the assignment. A pinned
    # effect cannot be: it binds to a scalar temporary at its chain position,
    # and the assignment then sees one value where the source had many.
    #
    # One hop through an ArrayLiteral counts -- `my @c = caller` builds the
    # array from the Call, and `my ($p,$f) = caller` reaches the Assign
    # directly.
    method _feeds_list_assign ($id) {
        my @seen = ($id);
        my %done;
        while (@seen) {
            my $cur = shift @seen;
            next if $done{$cur}++;
            for my $n (values $nodes->%*) {
                my @in = ($n->{inputs} // [])->@*;
                next unless grep { ($_ // -1) == $cur } @in;
                my $op = $n->{op} // '';
                return 1 if $op eq 'Assign' && @in >= 3;
                push @seen, $n->{id} if $op =~ /\A(?:Array|Hash)Literal\z/;
            }
        }
        return 0;
    }

    method _phi_var ($p) {
        my $st = $p->{stamp} // '';
        return sprintf('@phi%d', $p->{id})
            if $st eq 'Array' || $st eq 'List';
        return sprintf('%%phi%d', $p->{id}) if $st eq 'Hash';
        return sprintf('$phi%d', $p->{id});
    }

    # Whether a Region is an eval's join rather than a branch's.
    #
    # ONE CONTROL INPUT AND A Phi(value, undef). A branch join has one input
    # per arm; this has one, because an eval's failure path produces no
    # separate control -- only the value forks. The Phi over it is what says
    # so, and requiring BOTH is what keeps this from claiming a Region that
    # merely happens to have one predecessor.
    # The eval join whose ENTRY is $id, or undef.
    #
    # A block eval's Region names the control node its protected body began
    # after. Finding it from the entry is what lets the walk emit the whole
    # construct in one piece instead of running into the body first.
    method _eval_join_entered_at ($id, $next_of) {
        return undef unless defined $id;
        for my $n (values $nodes->%*) {
            next unless ($n->{op} // '') eq 'Region';
            my $entry = ($n->{fields} // {})->{eval_entry};
            next unless defined $entry && $entry == $id;
            return $n if $self->_is_eval_join($n);
        }
        return undef;
    }

    method _is_eval_join ($n) {
        my @in = ($n->{inputs} // [])->@*;
        return 0 unless @in == 1;

        # A VOID EVAL HAS NO VALUE PHI. `eval { die "x\n"; };` discards the
        # result and reads only $@ afterwards, so there is nothing for a Phi
        # to merge -- and requiring one meant this Region was not recognised
        # as an eval at all. The emitted program then had NO eval: the die
        # propagated and killed it.
        #
        #     eval { die "x\n" }; print "caught\n" if $@; print "end\n";
        #       perl : caught / end
        #       emit : died with "x"
        #
        # That is a silent miscompile of exception handling, not merely a
        # missing value. The Region ITSELF says so -- `eval_entry` is on the
        # wire for exactly this -- so trust the field rather than inferring
        # the shape from a Phi that a void eval never has.
        return 1 if defined(($n->{fields} // {})->{eval_entry});

        my ($phi) = grep { ($_->{op} // '') eq 'Phi'
                        && ((($_->{fields} // {})->{region} // -1) == $n->{id}) }
                    values $nodes->%*;
        return 0 unless $phi;
        my @pin = ($phi->{inputs} // [])->@*;
        return 0 unless @pin == 2;

        # THE SECOND INPUT IS ALWAYS THE undef, in both eval forms: that is
        # what "or it died" means.
        my $undef = $nodes->{ $pin[1] // -1 } or return 0;
        return 0 unless ($undef->{op} // '') eq 'Constant'
            && ((($undef->{fields} // {})->{const_type} // '') eq 'undef');

        # THE FIRST INPUT DIFFERS BY FORM, and requiring it to BE the Region's
        # control input recognised only the string form:
        #
        #   eval "..."       Phi[Coerce(->Code), undef]   the Coerce IS the
        #                                                 Region's input
        #   eval { ...; 1 }  Phi[Constant 1, undef]       the Region's input is
        #                                                 the block's last EFFECT
        #
        # Measured on `if (eval { $g = 1; 1 })`: `Region(16) in=[EntryWrite(10)]`
        # with `Phi(17) in=[Constant 6, Constant 1]`. So the block's VALUE is
        # unrelated to its last effect, and the shape is identified by the
        # undef alone plus the single-input Region.
        return 1;
    }

    # The `eval { }` an eval join stands for, binding its value where the Phi
    # is read. The Phi IS the eval's value -- `eval` already yields undef on
    # failure -- so one variable serves both.
    # _emit_eval($region, $from, $next_of) -> source
    #
    # TWO FORMS SHARE THIS JOIN, and they differ in where the eval's value
    # comes from:
    #
    #   eval "..."       Region[Coerce(->Code)]   Phi[that Coerce, undef]
    #   eval { ...; 1 }  Region[last EFFECT]      Phi[Constant 1, undef]
    #
    # Measured on `if (eval { $g = 1; 1 })`: `Region(16) in=[EntryWrite(10)]`
    # with `Phi(17) in=[Constant 6, Constant 1]`. So for a BLOCK the Region's
    # input is the last statement of the body, not a value -- rendering it as
    # an expression asked for an `EntryWrite` as one.
    method _emit_eval ($region, $from, $next_of) {
        my $eff = $nodes->{ $region->{inputs}[0] };
        my ($phi) = grep { ($_->{op} // '') eq 'Phi'
                        && ((($_->{fields} // {})->{region} // -1)
                            == $region->{id}) }
                    values $nodes->%*;

        my $inner;
        if (($eff->{op} // '') eq 'Coerce'
                && ((($eff->{fields} // {})->{to_repr} // '') eq 'Code')) {
            # A STRING EVAL: the operand is the source text, which is what
            # `eval EXPR` takes.
            $inner = sprintf('eval(%s)',
                             $self->_expr(($eff->{inputs} // [])->[0]));
        }
        else {
            # A BLOCK EVAL'S BODY RUNS FROM THE ENTRY TO THE JOIN, and the
            # Region names the entry -- without it the protected statements
            # are indistinguishable from those before, and guessing left a
            # `die` outside the block (measured: the emitted program died
            # where perl printed "died g=1").
            my $entry = ($region->{fields} // {})->{eval_entry};
            die "GAP: a block eval whose Region does not name its entry"
              . " cannot be delimited -- the statements it protects are"
              . " indistinguishable from those before it\n"
                unless defined $entry;

            # The block's VALUE is the Phi's first input, unrelated to its
            # last effect, so it is emitted after the statements rather than
            # instead of them.
            # THE FLAG STOPS THE BODY WALK RE-CLAIMING THIS EVAL. It starts
            # at the entry, which is exactly the node that identifies the
            # construct, so without it _emit_from recognises the same eval
            # again and recurses forever.
            my $body = do {
                local $in_eval_body = 1;
                $self->_emit_from($entry, $next_of, $region->{id});
            };
            my $val  = $phi ? $self->_expr(($phi->{inputs} // [])->[0]) : '';
            $inner = length $val
                ? sprintf("eval {\n%s%s}", _indent($body), _indent("$val;\n"))
                : sprintf("eval {\n%s}", _indent($body));
        }

        return "$inner;\n" unless $phi;

        # The Phi is bound, so every later read names the variable. Registering
        # it here rather than in the %reads scan keeps that scan about VALUES;
        # this binding exists because the eval was placed, not because someone
        # read it.
        $bound{ $phi->{id} } = sprintf('$eval%d', $phi->{id});

        # A CONDITIONAL eval's VALUE OUTLIVES ITS BLOCK. `A and B and C`
        # renders as nested ifs -- each eval happening only if the previous
        # succeeded -- but the final expression reads ALL of them:
        #
        #     my $eval10 = eval("1");
        #     if ($eval10) { my $eval20 = eval("2"); }
        #     ... $eval20 ...        <- out of scope, undef
        #
        # so a `my` at the eval's own position scopes it to the arm. Measured
        # on comp/colon.t, whose every test is an `and` chain of evals: all 11
        # came out `not ok` because each later eval read an undef.
        #
        # DECLARED AT THE TOP, ASSIGNED HERE -- the same mechanism a join Phi
        # uses, and for the same reason: the value outlives the branch that
        # produces it. %hoisted emits the declarations before the body.
        $hoisted{ $bound{ $phi->{id} } } //= $bound{ $phi->{id} };
        return sprintf("%s = %s;\n", $bound{ $phi->{id} }, $inner);
    }

    # _emit_endless_loop($n, $next_of) -> (source, id to resume from)
    #
    # `while (1) { BODY; last if C; MORE }` -- a Loop with no arms, whose exit
    # is an If inside the body. Emitted as an endless loop with an explicit
    # `last`, which is what the source said and keeps the exit where the graph
    # put it: statements after the `last` must not run on the pass that exits.
    method _emit_endless_loop ($n, $next_of) {
        # THE EXIT IS THE FIRST If ON THE CHAIN, not necessarily the node
        # pinned directly on the Loop. A body that does work before testing
        # puts that work first -- measured on base/while.t,
        # `Loop(31)` is followed by `EntryWrite(32)` and only then the If.
        my $exit;
        my $cur = $n->{id};
        for (1 .. 10_000) {
            my $succ = $next_of->{$cur} // [];
            last unless $succ->@*;
            my ($nx) = grep { ($_->{op} // '') ne 'Proj' } $succ->@*;
            $nx //= $succ->[0];
            if (($nx->{op} // '') eq 'If') { $exit = $nx; last }
            last if ($nx->{op} // '') =~ /\A(?:Loop|Region)\z/;
            $cur = $nx->{id};
        }
        die "GAP: a Loop with no Proj arms and no exit If is not yet"
          . " rendered\n" unless $exit;

        my @projs = grep { ($_->{op} // '') eq 'Proj' }
                    (($next_of->{ $exit->{id} } // [])->@*);
        my %arm = map { ($_->{fields}{index} // 0) => $_ } @projs;
        die "GAP: an endless loop whose exit If lacks both arms is not yet"
          . " rendered\n" unless exists $arm{0} && exists $arm{1};

        my @phis = sort { $a->{id} <=> $b->{id} }
                   grep { ($_->{op} // '') eq 'Phi'
                       && (($_->{fields}{region} // -1) == $n->{id})
                       && !$self->_is_memory($_->{id}) }
                   values $nodes->%*;

        my $init = '';
        $init .= sprintf("my %s = %s;\n", $self->_phi_var($_),
                         $self->_expr($_->{inputs}[0])) for @phis;

        # THE BODY IS WHAT PRECEDES THE EXIT TEST, and it is reached from the
        # Loop itself rather than through a Proj -- the effects between the
        # loop header and the If are chained on control_in.
        my $body = $self->_emit_from($n->{id}, $next_of, $exit->{id});

        # THE ITERATING ARM IS INDEX 1, and whatever it holds runs after the
        # `last` on every pass that does not exit.
        my $more = $self->_emit_from($arm{1}{id}, $next_of, undef);

        my $step = '';
        if (@phis) {
            $step .= sprintf("my %s_next = %s;\n", $self->_phi_var($_),
                             $self->_expr($_->{inputs}[1])) for @phis;
            $step .= sprintf("%s = %s_next;\n", $self->_phi_var($_),
                             $self->_phi_var($_)) for @phis;
        }

        my $text = $init . sprintf("while (1) {\n%s}\n",
            _indent($body
                  . sprintf("last if %s;\n", $self->_expr($exit->{inputs}[1]))
                  . $more . $step));

        # RESUME ON THE LEAVING ARM. Index 0 is the continuation after the
        # loop, so emission carries on from there -- through its Region when
        # it has one, as every other join does.
        my $after = $arm{0}{id};
        my ($region) = grep { ($_->{op} // '') eq 'Region' }
                       (($next_of->{ $arm{0}{id} } // [])->@*);
        $after = $region->{id} if $region;

        return ($text, $after);
    }

    # _emit_if($n, $next_of) -> (source, join id)
    #
    # THE DIAMOND IS DISCHARGED BY PLACEMENT. `If` has two `Proj` successors --
    # index 0 is the true arm, index 1 the false -- and each arm's control runs
    # until both reach the `Region` that joins them. Rendering the arms as
    # if/else blocks and resuming after the Region is what makes the arms'
    # effects conditional and everything after unconditional. Neither the Proj
    # nor the Region needs a spelling of its own.
    # _reaches_region($proj, $region_id, $next_of) -> bool
    #
    # Does this arm land on $region_id without passing through another Region?
    # Used to spot a break: the arm's control chain ends at the LOOP'S EXIT
    # rather than at a join inside the body.
    #
    # Bounded by the first Region encountered, because a nested diamond inside
    # the arm converges at its own join and anything past that is no longer
    # this arm's edge.
    method _reaches_region ($proj, $region_id, $next_of) {
        return 0 unless defined $proj && defined $region_id;
        my %seen;
        my @todo = ( $proj );
        while (@todo) {
            my $n = shift @todo;
            next unless $n && !$seen{ $n->{id} }++;
            return 1 if $n->{id} == $region_id;
            next if ( $n->{op} // '' ) eq 'Region' && $n->{id} != $region_id;
            # BOUNDED BY A NESTED `If` TOO. Reaching the exit THROUGH another
            # branch is that branch's break, not this arm's -- measured on
            # `next if $i==2; last if $i==4`, where the next-guard's arm
            # Proj 15 -> If 18 -> Proj 19 -> Region 20 found the exit
            # transitively and the `next` was emitted as `last`.
            next if ( $n->{op} // '' ) eq 'If' && $n->{id} != $proj->{id};
            push @todo, ( $next_of->{ $n->{id} } // [] )->@*;
        }
        return 0;
    }

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

        # AN ARM THAT LANDS ON THE LOOP'S EXIT IS A `last`, NOT A JOIN.
        #
        # A mid-body break reaches the graph as an extra predecessor of the
        # loop's exit Region, so the two arms do NOT converge inside the body:
        # one continues, one leaves. Treated as an ordinary diamond, the
        # leaving arm's continuation was emitted INSIDE the loop and again at
        # the exit -- measured on
        # `while ($i<5) { $i++; last if $i==4; $s += $i }`, perl prints 6 and
        # the emitted program printed 615.
        #
        # `last` IS THE WHOLE ARM. Everything the break path would do after
        # leaving belongs to the code after the loop, which the exit walk
        # already emits -- so the arm is exactly the loop control, and the
        # other arm carries the rest of the body.
        if ( defined $loop_exit_region ) {
            for my $ix ( 0, 1 ) {
                next unless $self->_reaches_region( $arm{$ix}, $loop_exit_region,
                                                    $next_of );
                my $rest_ix = 1 - $ix;
                my $rest = $self->_emit_from( $arm{$rest_ix}{id}, $next_of,
                                              $loop_exit_region );
                # The condition is written so the BREAKING arm is the one that
                # runs: an index-1 break means the loop leaves when the test is
                # FALSE, so the spelling negates.
                # THE EXIT PHIS ARE PAID HERE. Each records what the loop
                # variable must hold on this path; assigning before the `last`
                # is what makes a post-loop read correct on both exits.
                my $pay = join '', map { $break_assign{$_} }
                                   sort { $a <=> $b } keys %break_assign;
                my $text = $ix == 0
                    ? sprintf("if (%s) {\n%s}\n", $cond, _indent($pay . "last;\n"))
                    : sprintf("if (!(%s)) {\n%s}\n", $cond, _indent($pay . "last;\n"));

                # THE REST ARM MAY STILL REACH A BODY MERGE. With a `next`
                # earlier in the same body, the bottom of the body is a Region
                # joining the next-taken arm with this break's not-taken arm --
                # measured on `next if $i==2; last if $i==4`:
                #
                #     Proj 27 = If 14 (next)  index 0
                #     Proj 28 = If 18 (break) index 1
                #     Region 29 in=[27, 28]
                #     Phi 30   in=[4, 26] pred=[27, 28]
                #
                # Returning undef left Phi 30 unbound, and reading it refused.
                # Only the REST arm is a predecessor of that Region: the break
                # arm leaves. That is the lone-arm shape _join_phis already
                # handles -- the predecessor with no arm seeds the declaration
                # and the present arm assigns.
                my $bjoin = $self->_lone_arm_join( $arm{$rest_ix}, $next_of );
                if ( defined $bjoin && $bjoin != $loop_exit_region ) {
                    my ($bdecl, %bassign)
                        = $self->_join_phis( $bjoin, { $rest_ix => $arm{$rest_ix} } );
                    return ( $bdecl . $text . ( $bassign{$rest_ix} // '' ) . $rest,
                             $bjoin );
                }
                return ( $text . $rest, undef );
            }
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

            # DECLARED AT THE TOP OF THE SUB, NOT BEFORE THIS `if`. A join
            # can OUTLIVE the branch that assigns into it -- measured on a
            # nested early return, `Phi(18) region=17` is the FUNCTION EXIT's
            # join, bound while emitting the inner If. Declaring it there put
            # `my $phi18 = 0` inside the outer `if`, so the trailing
            # `return $phi18` was out of scope and the sub returned undef.
            #
            # The ASSIGNMENTS stay in their arms; only the declaration moves.
            $hoisted{$var} //= $var;

            # Seed with whichever input has no arm to assign in: the lone
            # case's absent arm, or the first input when every arm is present
            # (overwritten either way, and a declared-but-unset variable would
            # warn).
            # THE SEED GOES WITH THE DECLARATION, not into this branch. It
            # is the input from a predecessor with no block to assign in, so
            # the path that reaches the join WITHOUT entering the branch is
            # exactly the path it is for -- measured, `$phi18 = 0` emitted
            # inside the outer `if` left f(0) returning undef, because f(0)
            # never enters it.
            my ($seed) = grep { !exists $proj_arm{ $pred[$_] } } 0 .. $#in;
            $seed //= 0;
            $hoisted{$var} = sprintf('%s = %s', $var,
                                     $self->_expr($in[$seed]));

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
        # A CELL WRITE IS AN ASSIGNMENT TO THE SHARED VARIABLE. inputs are
        # [cell, value, memory]; the node becomes the new memory version,
        # which is what makes a sibling closure's read observe it.
        # A DELETE REMOVES A KEY, and advances memory so a later `exists`
        # sees it gone. Same [container, key, memory] shape as Exists.
        if ($op eq 'Delete') {
            my @din = ($n->{inputs} // [])->@*;
            die "GAP: a Delete with " . scalar(@din) . " inputs is not yet"
              . " rendered\n" unless @din >= 2;
            return sprintf("delete(%s);\n",
                $self->_element($din[0], $self->_expr($din[1])));
        }

        if ($op eq 'CellWrite') {
            my @cin = ($n->{inputs} // [])->@*;
            die "GAP: a CellWrite with " . scalar(@cin) . " inputs is not yet"
              . " rendered\n" unless @cin >= 2;
            return sprintf("%s = %s;\n",
                $self->_expr($cin[0]), $self->_expr($cin[1]));
        }

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

            # A COUNTED s/// MUST RUN EXACTLY ONCE. The RegexSubst has two
            # consumers -- this store, and the RegexSubstCount over it -- and
            # each rendered the substitution independently, so the emitted
            # program ran it twice. The second run saw the already-substituted
            # string and counted zero. Measured on
            # `our $s="aaa"; my $n = ($s =~ s/a/b/g); print "$n $s"`:
            #
            #     perl  : 3 bbb
            #     before: " bbb" -- right string, count lost
            #
            # The destructive form does BOTH jobs: it mutates the slot in
            # place and yields the count. So emit it here, bound, and let the
            # count read the binding instead of substituting again.
            my $val = $nodes->{ $n->{inputs}[1] // -1 };
            if ($val && ($val->{op} // '') eq 'RegexSubst'
                && !exists $bound{ $val->{id} }
                && $self->_counted_subst($val->{id})) {
                my $lv = $self->_subst_lvalue($val);
                if (defined $lv && $lv eq $self->_slot_name($slot)) {
                    my $f = $val->{fields} // {};
                    ( my $flags = $f->{flags} // '' ) =~ s/r//g;
                    my ($pat, $rep) = $self->_subst_operands($val);
                    my $var = sprintf('$subst%d', $val->{id});
                    $bound{ $val->{id} }            = $lv;
                    $subst_count_var{ $val->{id} }  = $var;
                    return sprintf("my %s = (%s =~ s{%s}{%s}%s);\n",
                        $var, $lv, $pat, $rep, $flags);
                }
            }

            # A BINDING IS RENDERED AS A GLOB ASSIGNMENT, because that is the
            # only Perl spelling that ALIASES a name rather than storing into
            # it. Emitted as a store it is a wrong answer, not an imprecise
            # one -- measured on `our @SRC=(1,2,3); *crackers=\@SRC;`:
            #
            #     perl      prints "1 2 3"
            #     as store  `@main::crackers = \(@main::SRC);` prints nothing
            #
            # The sigil on the target entry says WHICH slot the binding picked
            # (the RHS's type selected it), and the glob spelling drops the
            # sigil because `*name = REF` re-derives the slot from the
            # reference's kind -- the same dispatch perl itself does.
            if ( $n->{fields} && $n->{fields}{binds} ) {
                my $name = $self->_slot_name($slot);
                $name =~ s/\A[\$\@\%\&]//;
                return sprintf( "*%s = %s;\n",
                    $name, $self->_expr( $n->{inputs}[1] ) );
            }

            return sprintf("%s = %s;\n",
                $self->_slot_name($slot), $self->_expr($n->{inputs}[1]));
        }

        # A LIST ASSIGN binds N targets from N values: inputs are the targets
        # followed by the values. `my ($a,$b) = (2,3)` is one statement, and
        # emitting it as one is what puts the slots in scope for later reads.
        if ($op eq 'Assign') {
            my @in = ($n->{inputs} // [])->@*;

            # A COUNTED s/// STORED THROUGH AN Assign STILL RUNS TWICE. The
            # foreach form writes back through an Assign rather than an
            # EntryWrite -- `for my $s (@w)` aliases the iterator to the
            # element, so the store is `Assign($w[$i], RegexSubst)` -- and the
            # store/count pair double-evaluates exactly as the EntryWrite case
            # did before the fix above.
            #
            # NOT FIXED THE SAME WAY. By the time this branch runs, the
            # generic chain walker has already bound the RegexSubst to an
            # `$effN` holding the substituted STRING, and emitting the
            # destructive form here ADDS a statement rather than replacing
            # that one -- measured, the emitted loop carried the substitution
            # three times. Suppressing the earlier binding is a change to the
            # chain walker, not to this branch.
            #
            # OBSERVATIONALLY EQUIVALENT TODAY, including on non-idempotent
            # patterns -- measured on `s/a/ab/g`, `s/x/xx/g` and `s/b/bb/g`
            # over a foreach element, all three agreeing with perl. The store
            # renders the /r form, which does NOT mutate, so the destructive
            # run in the count position still sees the original subject and
            # the store's own write-back lands last.
            #
            # It stops being equivalent the moment the replacement has a side
            # effect, since that would run twice. `s///e` in a foreach is a
            # producer GAP today (measured: no __PROGRAM__ in the graph), so
            # the shape is not reachable -- but this is a latent hazard, not a
            # settled correctness argument.

            # TARGETS FIRST, THEN VALUES -- and the counts need not match. An
            # even split was wrong: `my ($x,$y) = @_` is TWO targets from ONE
            # source (the ArgsSource), and `my ($a,$b) = (2,3)` is two from
            # two. The targets are the leading slot nodes; everything after
            # them is the value list.
            # A PostfixDeref IS A TARGET TOO. `$$r = 7` stores through a
            # reference, and leaving it off this list made the Assign report
            # ZERO targets and refuse -- an allow-list missing the one form
            # nobody had written a test for yet.
            #
            # AN ArgsSource IS A TARGET ONLY IN FIRST POSITION. `@_ = LIST`
            # assigns into the argument array, which is an ordinary lvalue --
            # but `my ($a,$b) = @_` has an ArgsSource as its VALUE, and both
            # spell the same node kind.
            #
            # POSITION IS THE DISCRIMINATING PROPERTY, not the kind. Adding
            # ArgsSource to the kind list outright made `my ($where,$num) = @_`
            # in base/lex.t's `sub T` consume its own RHS: three inputs, all
            # "targets", no values left, and the Assign refused.
            #
            # A PostfixDeref IS AMBIGUOUS THE SAME WAY. `$$r = 7` makes it a
            # target, but `my ($a,$b) = @$r` makes it the SOURCE -- and both
            # spell the same node kind. Measured on comp/require.t:
            #
            #     Assign in=[PadAccess x5, PostfixDeref]
            #
            # which is `my (...) = @$ref`. Walking it as a sixth target left
            # NO values and refused.
            #
            # A TRAILING PostfixDeref AFTER A PAD TARGET IS THE SOURCE. It
            # cannot be a target there: a list assign's targets are all
            # lvalues, and perl writes `($$r, $$s) = ...` with the derefs
            # FIRST, never one deref after five pad slots.
            my $t = 0;
            $t++ while $t < @in
                && (($nodes->{ $in[$t] }{op} // '')
                      =~ /\A(?:PadAccess|EntryDef|Subscript)\z/
                    || ($t == 0
                        && ($nodes->{ $in[$t] }{op} // '') eq 'ArgsSource')
                    || (($nodes->{ $in[$t] }{op} // '') eq 'PostfixDeref'
                        && ($t == 0 || $t < $#in))
                    # `undef` IS A LEGAL PLACEHOLDER IN A TARGET LIST.
                    # `my (undef, $b) = @_` discards the first value, and
                    # comp/parser.t uses it as `my (undef, $f, $l) = caller`.
                    # It reaches the wire as an undef Constant, which is not a
                    # slot -- so the walk stopped at it and either refused (a
                    # leading undef) or, worse, took the whole list as VALUES
                    # and emitted nothing at all for a trailing one.
                    #
                    # Only in a list: a lone `undef = $x` is a perl error, and
                    # a single-input Assign has no target list to be part of.
                    || (@in > 2
                        && ($nodes->{ $in[$t] }{op} // '') eq 'Constant'
                        && (($nodes->{ $in[$t] }{fields} // {})->{const_type}
                            // '') eq 'undef'));

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

            die "GAP: an Assign (id $n->{id}) with no target slots is not yet"
              . " rendered -- its first input is a `"
              . ($nodes->{ $in[0] // -1 }{op} // '?') . "`\n"
                unless $t;
            my @lhs = map { $self->_expr($_) } @in[0 .. $t-1];
            my @rhs = map { $self->_expr($_) } @in[$t .. $#in];
            die "GAP: an Assign (id $n->{id}) with no values is not yet"
              . " rendered -- its " . scalar(@in) . " inputs all read as"
              . " targets\n"
                unless @rhs;
            # `my` DECLARES A SLOT; AN ELEMENT STORE WRITES ONE. The producer
            # does not record declaration separately from binding, so a write
            # to a pad slot is taken as its declaration -- but an element
            # target is an existing container's slot, and `my $a[0] = 7` is a
            # syntax error. Only a whole-slot target declares.
            # A PACKAGE VARIABLE IS NEVER DECLARED WITH `my`. An EntryDef
            # spells as `$main::x`, which starts with `$` like a pad slot --
            # so a check on the SPELLING emitted `my ($main::x, $main::y)`,
            # which perl rejects outright: `"my" variable $main::x can't be
            # in a package`. The node kind is what separates them.
            my $all_slots = 1;
            for my $i (0 .. $t-1) {
                $all_slots = 0, last
                    unless ($nodes->{ $in[$i] }{op} // '') eq 'PadAccess';
            }
            # A CELL SLOT IS ALREADY DECLARED, at the top, because the subs
            # that close over it are emitted above this chain. A second `my`
            # here would shadow the captured lexical and the closure's writes
            # would stop being visible.
            my $decl = ($all_slots && (grep { /^\$/ } @lhs) == @lhs
                        && !(grep { $cell_slots{$_} } @lhs))
                ? 'my ' : '';
            return sprintf("%s(%s) = (%s);\n",
                $decl, join(', ', @lhs), join(', ', @rhs))
                if @lhs > 1;

            # ONE TARGET STILL TAKES EVERY VALUE when it is list-valued.
            # `@_ = ("a","b")` is a single target over TWO values, and
            # emitting only $rhs[0] dropped the rest -- measured, it produced
            # `@_ = "a"` and printed `a` where perl prints `a b`.
            #
            # Keyed on the target's SPELLING rather than its node kind: `@`
            # and `%` take a list, `$` takes one scalar, and that is true
            # however the container was named. A scalar target keeps the
            # single-value form, so `$x = 1` does not become `$x = (1)`.
            return sprintf("%s%s = (%s);\n",
                $decl, $lhs[0], join(', ', @rhs))
                if $lhs[0] =~ /\A[\@%]/;

            # A SCALAR TARGET FROM A LIST SOURCE STILL NEEDS THE PARENS.
            # `my ($a) = @_` binds the FIRST ELEMENT; `my $a = @_` binds the
            # COUNT, and they are different programs. The Assign is a list
            # assign either way -- the graph does not distinguish one target
            # from several -- so the parens that make it one must survive.
            #
            # Measured: `sub U { my ($a) = @_; print $a }` called as U("z")
            # printed `1` instead of `z`.
            #
            # Only when the source is list-valued. `my $x = 1` must not become
            # `my ($x) = (1)`: harmless here, but it would turn a scalar
            # assignment's VALUE from the right-hand side into a count
            # wherever the source is an aggregate.
            my $src = $nodes->{ $in[$t] // -1 };
            return sprintf("%s(%s) = (%s);\n", $decl, $lhs[0], $rhs[0])
                if @rhs == 1 && $src
                && (($src->{op} // '') eq 'ArgsSource'
                    || ($src->{stamp} // '') =~ /\A(?:List|Array)\z/);

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

    # _counted_subst($id) -- is this RegexSubst read by a RegexSubstCount?
    # Two consumers over one substitution is the double-evaluation hazard: the
    # store wants the string, the count wants the number, and rendering each
    # separately runs the s/// twice.
    method _counted_subst ($id) {
        for my $n (values $nodes->%*) {
            next unless ($n->{op} // '') eq 'RegexSubstCount';
            my $in = ($n->{inputs} // [])->[0];
            return 1 if defined $in && $in == $id;
        }
        return 0;
    }

    # _counted_lexical_subst($n) -- the one-run emission for a destructive
    # s/// or tr/// on a LEXICAL, or undef when this is not that shape.
    #
    # Returns the whole statement rather than a spelling, because the binding
    # it emits is the count temporary while the SUBJECT stays the variable --
    # two different names for what the generic path would give one.
    #
    # BOTH OPERATORS, ONE PLACE. s/// and tr/// have the identical defect and
    # the identical fix: two consumers (the mutated subject and the count) over
    # one mutating node, each rendering it independently, so the emitted program
    # runs it twice and the second sees the already-changed string. Splitting
    # this into two helpers is how the project's recurring "one operator, N
    # declaration sites" drift starts.
    method _counted_lexical_subst ($n) {
        my $op = $n->{op} // '';
        return undef unless $op eq 'RegexSubst' || $op eq 'Transliterate';

        # COUNTED OR NOT, THE MUTATION MUST HAPPEN. An uncounted destructive
        # s/// (`$s =~ s/a/z/;` with nothing reading the count) is bound here
        # too, and the generic path renders a bound value with `/r` -- which
        # substitutes into a COPY and leaves the variable alone. Measured on
        # `my $s = "abc"; $s =~ s/a/z/; print "$s"`:
        #
        #     perl   zbc
        #     /r     abc   -- the substitution happened to nothing
        #
        # so the count is what decides whether a TEMPORARY is needed, not
        # whether the destructive form is. Requiring a count here regressed five
        # corpus cases from correct to silently wrong.
        my $counted = $op eq 'RegexSubst'
            ? $self->_counted_subst( $n->{id} )
            : $self->_counted_trans( $n->{id} );

        # ONLY WHEN THE SUBJECT IS ITSELF AN LVALUE. A value subject is the
        # package-scalar path's business (it recovers the name through the
        # EntryWrite) and rendering a destructive form over one does not
        # compile.
        my $subj = $nodes->{ ( $n->{inputs} // [] )->[0] // -1 };
        return undef unless $subj && ( $subj->{op} // '' ) eq 'PadAccess';

        my $lv = $self->_subst_lvalue($n);
        return undef unless defined $lv;

        my $f = $n->{fields} // {};
        ( my $flags = $f->{flags} // '' ) =~ s/r//g;
        my $var  = sprintf( '$subst%d', $n->{id} );
        my $text = $op eq 'RegexSubst'
            ? do {
                my ( $pat, $rep ) = $self->_subst_operands($n);
                sprintf( '(%s =~ s{%s}{%s}%s)', $lv, $pat, $rep, $flags );
            }
            : sprintf( '(%s =~ tr[%s][%s]%s)',
                $lv, $f->{from} // '', $f->{to} // '', $flags );

        # The SUBJECT reads as the variable from here on; the COUNT, when there
        # is one, reads the temporary. Both are recorded so neither consumer
        # re-renders it.
        $bound{ $n->{id} } = $lv;
        return "$text;\n" unless $counted;

        $subst_count_var{ $n->{id} } = $var;
        return sprintf( "my %s = %s;\n", $var, $text );
    }

    # _counted_trans($id) -- is this Transliterate read by a TransliterateCount?
    # The tr/// half of _counted_subst, and the same hazard: two consumers over
    # one mutation.
    method _counted_trans ($id) {
        for my $n ( values $nodes->%* ) {
            next unless ( $n->{op} // '' ) eq 'TransliterateCount';
            my $in = ( $n->{inputs} // [] )->[0];
            return 1 if defined $in && $in == $id;
        }
        return 0;
    }

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

        # AN ELEMENT IS AN LVALUE TOO. `for my $s (@w) { $s =~ s/a/b/g }`
        # aliases the iterator to the array element, so the subject arrives as
        # `Subscript(@w, $i)` -- and `$w[$i] =~ s///` is perfectly assignable.
        # Refusing it here sent a renderable shape to the GAP.
        return $self->_expr($root->{id})
            if ($root->{op} // '') eq 'Subscript';

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
        # BRACED WHEN THE NAME IS MORE THAN THE CARET LETTER. `$^XY` does not
        # parse -- perl reads `$^X` and then a bareword `Y` -- so a
        # multi-character caret name needs `${^XY}`. base/lex.t reaches this
        # through `${^TEST}`; the single-letter `$^O` that this branch was
        # written for takes no braces and keeps its old spelling.
        #
        # Shared with the aggregate path via _spell_name, which had to solve
        # exactly this for `%{^TEST}`.
        if ($name =~ /\A[\x00-\x1f]/) {
            return $sigil . $self->_spell_name($name);
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
        elsif ($op eq 'Chomp') {
            # chomp AND chop MUTATE, so the value form needs a copy: perl has
            # no `/r` for these. Rendered as a do-block over a temporary so
            # the expression yields the TRIMMED string while leaving the
            # subject expression untouched -- the store back to the variable
            # is the graph's separate business, exactly as it is for s///.
            die "GAP: a Chomp with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 1;
            my $kind = ($n->{fields} // {})->{kind} // 'chomp';
            $text = sprintf('do { my $c = %s; %s($c); $c }',
                $self->_expr($in[0]), $kind);
        }
        elsif ($op eq 'Transliterate') {
            # SAME SHAPE AS RegexSubst, same reason: the graph threads the
            # result to whatever binds it, so this yields a value rather than
            # mutating in place -- which is what `tr///r` means.
            #
            # DELIMITED WITH BRACKETS so the sets need no escaping: they are
            # the source spelling, and a `/` inside one would close a
            # slash-delimited form.
            my $f = $n->{fields} // {};
            ( my $flags = $f->{flags} // '' ) =~ s/r//g;
            $text = sprintf('(%s =~ tr[%s][%s]%sr)',
                $self->_expr($in[0]), $f->{from} // '', $f->{to} // '',
                $flags);
        }
        elsif ($op eq 'TransliterateCount') {
            # THE COUNT IS NOT THE STRING, the same split RegexSubstCount
            # makes for s///. The destructive form is what returns a count, so
            # this renders WITHOUT /r -- and it needs an lvalue, which the
            # Transliterate's own subject supplies.
            die "GAP: a TransliterateCount with " . scalar(@in) . " inputs is"
              . " not yet rendered\n" unless @in == 1;
            my $tr = $nodes->{ $in[0] };
            die "GAP: a TransliterateCount over `" . ($tr->{op} // '?')
              . "` is not yet rendered\n"
                unless $tr && $tr->{op} eq 'Transliterate';

            # THE DESTRUCTIVE tr/// MAY ALREADY HAVE RUN. When its subject is a
            # lexical, `_counted_lexical_subst` emits it once at its chain
            # position and records the temporary holding the count. Rendering
            # the transliteration again here would run it a second time, and
            # the second run sees the already-transliterated string. Same split
            # RegexSubstCount makes, for the same reason.
            if (exists $subst_count_var{ $tr->{id} }) {
                $text = $subst_count_var{ $tr->{id} };
                return $text;
            }
            my $tf = $tr->{fields} // {};
            ( my $tflags = $tf->{flags} // '' ) =~ s/r//g;
            $text = sprintf('(%s =~ tr[%s][%s]%s)',
                $self->_expr(($tr->{inputs} // [])->[0]),
                $tf->{from} // '', $tf->{to} // '', $tflags);
        }
        elsif ($op eq 'RegexSubst') {
            # A SUBSTITUTION YIELDS THE MODIFIED STRING here rather than
            # mutating in place -- the producer threads the result to whatever
            # binds it. So it renders as a match-and-replace over a COPY, which
            # is what `s///r` means, and the binding is the caller's job.
            my $f = $n->{fields} // {};
            ( my $flags = $f->{flags} // '' ) =~ s/r//g;
            my ($pat, $rep) = $self->_subst_operands($n);
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

            # ALREADY RUN AT ITS STORE. When the substitution also feeds an
            # EntryWrite, that store emitted the destructive form and bound
            # its COUNT -- substituting again here would run the s/// a second
            # time over the already-modified string and count zero.
            #
            # ONLY THAT BINDING HOLDS A COUNT. A RegexSubst inside a loop gets
            # an ordinary `$effN` binding from the generic chain walker, and
            # that one holds the SUBSTITUTED STRING. Reading it here emitted
            # the string where a number belonged -- measured on
            # `for my $s (@w) { my $n = ($s =~ s/a/b/g) }`, which printed
            # "bbb bbb" instead of "3 bbb". So the count binding is tracked
            # separately rather than inferred from the presence of any binding.
            if (exists $subst_count_var{ $sub->{id} }) {
                $text = $subst_count_var{ $sub->{id} };
                return $rendered{$id} = $text;
            }

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
            #
            # SAME RESOLVER AS THE VALUE FORM: one operator, one place that
            # decides which inputs are operands.
            my ($cpat, $crep) = $self->_subst_operands($sub);
            $text = sprintf('(%s =~ s{%s}{%s}%s)',
                $lv, $cpat, $crep, $flags);
        }
        elsif ($op eq 'Subscript') {
            # AN ELEMENT READ, and its third input is the MEMORY it observes.
            # A read threaded to a store sees the stored value; one threaded
            # past it sees the old one. That ordering is the whole question
            # this oracle exists to check.
            die "GAP: a Subscript with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" if @in < 2;
            $text = $self->_element($in[0], $self->_expr($in[1]));
        }
        elsif ($op eq 'Count') {
            # scalar(@a) -- the element count, and a memory-dependent read like
            # any other: inputs are [aggregate, memory].
            die "GAP: a Count with no aggregate is not yet rendered\n"
                unless @in;
            # AN AGGREGATE NEEDS NO DEREFERENCE; a REFERENCE does. The rule
            # was "is it a Literal", which missed every other list-valued node
            # -- measured, `scalar(keys %seen)` after a sort emitted
            # `scalar(@{sort(keys(%seen))})`, dereferencing a LIST, which
            # counts nothing.
            #
            # The stamp answers it, and the sigil answers it for a pad-bound
            # aggregate that arrives unstamped. Same question the element read
            # one path over asks, same two properties.
            my $agg = $nodes->{ $in[0] };
            my $st  = $agg->{stamp} // '';
            my $sg  = ($agg->{fields} // {})->{sigil} // '';
            $st = $sg eq '@' ? 'Array' : $sg eq '%' ? 'Hash' : $st;

            # `scalar(LIST)` IS NOT A COUNT. Perl's `scalar` imposes scalar
            # context rather than counting: `scalar(sort keys %h)` is
            # undefined behaviour and returned nothing, where the source meant
            # "how many". An ARRAY in scalar context IS its count, but a list
            # expression has to be counted explicitly.
            #
            # `scalar(() = LIST)` IS NOT THAT IDIOM FOR split. Assigning to an
            # EMPTY list tells split how many fields are wanted -- none -- and
            # it optimises to that, so the count comes back 1 however many
            # fields there are. Measured:
            #
            #     scalar(() = split(/,/,"a,b,c"))          1
            #     scalar(() = split(/,/,"a,b,c", -1))      3
            #     do { my @t = split(/,/,"a,b,c"); scalar(@t) }   3
            #     scalar(() = (1,2,3))                     3   (right, by luck)
            #
            # So the old idiom was right for an ordinary list and silently
            # wrong for split -- and a `while` bound built from it never
            # catches up. Found by a deparsed comp/retainedlines.t that had
            # been spinning at 99% CPU for 28 hours.
            #
            # A NAMED TEMPORARY IS CORRECT FOR ALL OF THEM, because split
            # sizes itself to a real array the way the source's own target
            # does. It costs one copy, which is the price of asking the
            # question at all.
            # AN ANONYMOUS LITERAL IS A LIST, NOT AN ARRAY, however it is
            # stamped. `scalar((1,2,3))` is the COMMA OPERATOR in scalar
            # context -- it yields the LAST ELEMENT, not the count. Measured:
            #
            #     scalar((1,2,3))   3    right by coincidence
            #     scalar((5,2,9))   9    the last element
            #     scalar(@a)        3    the count
            #
            # A `for (LIST)` loop bounded by that ran forever or stopped
            # early, silently -- and the (1,2,3) case looked correct.
            my $named = ($agg->{op} // '') =~ /Literal\z/
                     && defined(($agg->{fields} // {})->{symbol});

            $text = $named || (($agg->{op} // '') !~ /Literal\z/
                               && ($st eq 'Array' || $st eq 'Hash'))
                ? sprintf('scalar(%s)', $self->_expr($in[0]))
                : $st eq 'List' || ($agg->{op} // '') =~ /Literal\z/
                ? sprintf('do { my @c%d = %s; scalar(@c%d) }',
                          $id, $self->_expr($in[0]), $id)
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
            my $vn = $self->_agg_name($n);
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
        elsif ($op eq 'MakeCell') {
            # THE CELL ITSELF, as a value: an AnonSub names it to say what it
            # captures. The declaration is emitted separately (see
            # _emit_cell_declarations), because the cell has to exist before
            # the subs that close over it.
            $text = $self->_cell_var($n);
        }
        elsif ($op eq 'CellParam') {
            # INSIDE A BODY, the captured variable is in scope by closure --
            # perl needs no parameter for it. The index/name identify WHICH
            # cell, and the enclosing AnonSub's `captures` already said.
            #
            # Resolved through the AnonSub that names this body, so a sub
            # capturing two cells reads the right one.
            my $cell = $self->_cell_for_param($n);
            die "GAP: a CellParam whose cell cannot be resolved is not yet"
              . " rendered\n" unless defined $cell;
            $text = $self->_cell_var($cell);
        }
        elsif ($op eq 'CellRead') {
            # READING THE CELL IS READING THE VARIABLE. Its memory input
            # orders the read against writes and is not an operand.
            die "GAP: a CellRead with no cell is not yet rendered\n"
                unless @in;
            $text = $self->_expr($in[0]);
        }
        elsif ($op eq 'AnonSub') {
            # A REFERENCE TO ITS BODY. The body is already its own `methods`
            # entry, emitted as a named sub, so `\&that` is the value --
            # measured, an AnonSub and the Call that invokes it name the SAME
            # body, which is why one mangling has to serve both.
            my $nm = ($n->{fields} // {})->{name};
            die "GAP: an AnonSub with no name is not yet rendered\n"
                unless defined $nm && length $nm;
            $text = sprintf('\\&%s', $self->_sub_ident($nm));
        }
        elsif ($op eq 'Delete') {
            # DELETE YIELDS THE REMOVED VALUE, so it is reached as a value as
            # well as a statement -- and when it is, the removal still has to
            # happen. Same expression either way; only the trailing semicolon
            # differs, which the statement arm adds.
            die "GAP: a Delete with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in >= 2;
            $text = sprintf('delete(%s)',
                $self->_element($in[0], $self->_expr($in[1])));
        }
        elsif ($op eq 'Exists') {
            # MEMBERSHIP, NOT DEFINEDNESS -- the node's own ABOUTME records
            # the miscompile that created it: `exists $h{u}` is TRUE for a key
            # whose value is undef, and `defined $h{u}` is false. Inputs are
            # [container, key, memory], the memory ordering the question
            # against stores.
            die "GAP: an Exists with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in >= 2;
            $text = sprintf('exists(%s)',
                $self->_element($in[0], $self->_expr($in[1])));
        }
        elsif ($op eq 'Assign') {
            # AN ASSIGNMENT USED AS A VALUE. Measured on base/lex.t's
            # `my ($p,$f,$l) = caller` reached as an operand:
            #
            #     14 Assign  in=[10,11,12,13]  stamp=List
            #     15 Coerce  in=[14]           Unknown -> Str
            #
            # so the assignment's VALUE is read, not only its effect. A list
            # assign in scalar context is the RHS ELEMENT COUNT -- not the
            # last value and not the number of targets -- and writing it as
            # the assignment lets perl decide that, rather than the emitter
            # guessing a number that would still look plausible.
            #
            # PARENTHESISED, because `my $n = $a = $b, 1` binds the comma
            # before the assignment.
            my $t = 0;
            $t++ while $t < @in
                && ($nodes->{ $in[$t] }{op} // '')
                     =~ /\A(?:PadAccess|EntryDef|Subscript|PostfixDeref)\z/;
            die "GAP: an Assign value with no target slots is not yet"
              . " rendered\n" unless $t && $t < @in;

            my @lhs = map { $self->_expr($_) } @in[0 .. $t-1];
            my @rhs = map { $self->_expr($_) } @in[$t .. $#in];

            # THE TARGET LIST KEEPS ITS PARENS. `($a,$b) = LIST` is a list
            # assign and `$a = LIST` is a scalar one -- they yield different
            # values, so the shape of the left side is load-bearing.
            $text = @lhs > 1
                ? sprintf('((%s) = (%s))', join(', ', @lhs), join(', ', @rhs))
                : sprintf('(%s = %s)', $lhs[0], join(', ', @rhs));
        }
        elsif ($op eq 'ListAppend') {
            # THE LOOP-CARRIED LIST OF A map/grep. inputs[0] is the list so
            # far and inputs[1..] are this iteration's contribution --
            # measured on `map { $_ * 2 } (1,2,3)`, `ListAppend(27) in=[7, 26]`
            # where 7 is the accumulator Phi.
            #
            # THE CONTRIBUTION COUNT IS NOT ONE. `map { ($_,$_) }` contributes
            # two per element and `map { () }` contributes none, which is why
            # this node exists rather than the foreach lowering being reused.
            die "GAP: a ListAppend with no accumulator is not yet rendered\n"
                unless @in;
            my $coll = ($n->{fields} // {})->{collector} // '';
            die "GAP: a ListAppend that does not say which collector built it"
              . " is not yet rendered\n" unless length $coll;

            if ($coll eq 'grep') {
                # [acc, ELEMENT, PREDICATE] -- the element is appended IF the
                # predicate holds. Appending both gave `6 [1  2  3 ]` where
                # perl gives `2 [2 3]`: every element kept, plus its predicate.
                die "GAP: a grep ListAppend with " . scalar(@in) . " inputs is"
                  . " not yet rendered\n" unless @in == 3;
                $text = sprintf('(%s, (%s) ? (%s) : ())',
                    $self->_expr($in[0]), $self->_expr($in[2]),
                    $self->_expr($in[1]));
            }
            else {
                # [acc, CONTRIBUTION...] -- every input after the first is
                # appended, and NONE is `map { () }` rather than an error.
                $text = sprintf('(%s)',
                    join(', ', map { $self->_expr($_) } @in));
            }
        }
        elsif ($op eq 'EnvRead') {
            # `$ENV{KEY}` -- the key is a compile-time literal on the node,
            # which is why env reads hash-cons: the read is constant per
            # process because env WRITES are not modelled.
            my $k = ($n->{fields} // {})->{key};
            die "GAP: an EnvRead with no key is not yet rendered\n"
                unless defined $k;
            ( my $q = $k ) =~ s/(['\\])/\\$1/g;
            $text = sprintf("\$ENV{'%s'}", $q);
        }
        elsif ($op eq 'Ref') {
            # `\EXPR` -- a unary whose op_str is already the backslash.
            # Parenthesised because `\$x . "y"` takes a reference to the
            # CONCATENATION, a different value.
            die "GAP: a Ref with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 1;

            # AN AGGREGATE OPERAND MUST NOT BE PARENTHESISED. `\(@a)` is not
            # `\@a`: the parens make it a LIST of references to each element,
            # so it yields the last one in scalar context. Measured:
            #
            #     our @SRC=(1,2,3); *c = \(@SRC);  ->  $c is 3, @c is empty
            #     our @SRC=(1,2,3); *c = \@SRC;    ->  @c is 1 2 3
            #
            # The parens above exist for a real reason -- `\$x . "y"` would
            # take a reference to the CONCATENATION -- but that hazard is a
            # binary operator binding looser than `\`, which a bare aggregate
            # read cannot be. So they are dropped exactly where they change
            # the meaning and kept everywhere else.
            my $inner = $self->_expr($in[0]);
            $text = $inner =~ /\A[\@%][\w:]+\z/
                ? sprintf('\\%s', $inner)
                : sprintf('\\(%s)', $inner);
        }
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
            # A LIST SLICE HAS NO CONTAINER. `(qw(p q r))[1]` slices a flat
            # list of values rather than a named aggregate, so `index_count`
            # says where the inputs split: [indices..., values...]. It is
            # absent (0) for the container form, where every input but the
            # last is an index.
            #
            # Rendered as `(VALUES)[INDICES]`, which is the source spelling
            # and needs no name for anything.
            my $f  = $n->{fields} // {};
            my $ix = $f->{index_count} // 0;
            if ($ix) {
                die "GAP: a list Slice claiming $ix indices has only "
                  . scalar(@in) . " inputs\n" if $ix >= @in;
                my @idx = map { $self->_expr($_) } @in[0 .. $ix - 1];
                my @val = map { $self->_expr($_) } @in[$ix .. $#in];
                $text = sprintf('(%s)[%s]',
                    join(', ', @val), join(', ', @idx));
            }
            else {
                # THE CONTAINER IS LAST and there is exactly one; every input
                # before it is an index. Measured on `@a[0,2]`, which gives
                # Slice(0, 2, ArrayLiteral) -- three inputs, so the old
                # `@in == 2` refusal turned a renderable multi-index slice
                # into a GAP.
                die "GAP: a Slice with no container is not yet rendered\n"
                    unless @in >= 2;
                my $agg = $nodes->{ $in[-1] };
                my $af  = ($agg->{fields} // {});
                die "GAP: a Slice over an anonymous `" . ($agg->{op} // '?')
                  . "` has no container to name\n"
                    unless defined $af->{symbol};
                # A HASH SLICE SUBSCRIPTS WITH BRACES. `@h{'k1','k2'}` and
                # `@a[0,2]` are both Slice nodes with an `@` sigil of their
                # own; only the CONTAINER's sigil says which brackets to use,
                # and emitting `@h[...]` would index the array `@h` -- a
                # different variable that need not even exist.
                #
                # A SLICE ALWAYS TAKES `@`, whatever the container's sigil, so
                # the symbol's own sigil is stripped rather than kept: a
                # package aggregate records the qualified spelling and
                # `@@main::E` does not parse.
                my ($open, $close)
                    = ($af->{sigil} // '@') eq '%' ? ('{', '}') : ('[', ']');
                ( my $bare = $af->{symbol} ) =~ s/\A[\$\@%]//;
                $bare = $self->_spell_name($bare);
                $text = sprintf('@%s%s%s%s', $bare, $open,
                    join(', ', map { $self->_expr($_) } @in[0 .. $#in - 1]),
                    $close);
            }
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
        # UNARY ARITHMETIC. Both reach the wire from ordinary Perl and
        # neither had a rule, so any graph containing one refused -- measured
        # on pvm's adjacency-04_operators, "no rule for value node `Negate`".
        # t/op-coverage.t already had fixtures PRODUCING both, which is that
        # gate's stated limit as a defect: observing a node kind is not
        # verifying it.
        #
        # THE OPERAND IS PARENTHESIZED because these bind tighter than the
        # arithmetic that may be inside them: `-$a + $b` is `(-$a) + $b`, so
        # emitting `-` against an unparenthesized sum would change the answer.
        # A RANGE IS A LIST, spelled with its two bounds. Reached only from
        # the list-context form: perl folds a constant range to a const[AV]
        # and optimises the range op away entirely inside a `foreach`, so this
        # is the `my @q = (1..$n)` shape. The bounds are parenthesized because
        # `..` binds loosely -- looser than the arithmetic that may produce a
        # bound.
        # `$o isa Foo` -- an infix operator, in=[object, class name]. The
        # class arrives as a Constant string, and `isa` wants a BAREWORD or a
        # string expression on its right; a string works for both spellings and
        # does not have to know whether the source wrote one.
        elsif ($op eq 'IsaOp') {
            die "GAP: an IsaOp with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 2;
            $text = sprintf('(%s isa %s)',
                $self->_expr($in[0]), $self->_expr($in[1]));
        }
        # A SIGNATURE PARAMETER IS A READ OF `@_` BY INDEX, which is what perl
        # itself lowers a signature to. Emitting `$_[0]` rather than
        # reconstructing `sub f ($a, $b)` keeps this a value rule: the node
        # carries index/name/sigil, and only the index is load-bearing for the
        # VALUE. A default (`$b = 3`) is a separate Constant the producer
        # already wired through a DefinedOr, so it needs nothing here.
        #
        # Ugly and faithful rather than pretty and reconstructed -- the same
        # trade the emitter's own design records.
        elsif ($op eq 'Parameter') {
            my $ix  = ( $n->{fields} // {} )->{index} // 0;
            my $sig = ( $n->{fields} // {} )->{sigil} // '$';
            die "GAP: a Parameter with sigil `$sig` is not yet rendered"
              . " -- only a scalar parameter reads as one \@_ element\n"
                unless $sig eq '$';
            $text = sprintf('$_[%d]', $ix);
        }
        elsif ($op eq 'Range') {
            die "GAP: a Range with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 2;
            $text = sprintf('((%s) .. (%s))',
                $self->_expr($in[0]), $self->_expr($in[1]));
        }
        elsif ($op eq 'Negate') {
            die "GAP: a Negate with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 1;
            $text = sprintf('(-(%s))', $self->_expr($in[0]));
        }
        elsif ($op eq 'Complement') {
            die "GAP: a Complement with " . scalar(@in) . " inputs is not yet"
              . " rendered\n" unless @in == 1;
            $text = sprintf('(~(%s))', $self->_expr($in[0]));
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
            # THE ID IS PART OF THE DIAGNOSIS. Without it this refusal names
            # a KIND, and a graph with 1400 nodes may hold dozens of that kind
            # -- finding which one required editing the message by hand every
            # time. A refusal that cannot be acted on is only half honest.
            die "GAP: no rule for value node `$op` (id $id)\n";
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
    # Whether a node is a point in the memory chain rather than a value.
    #
    # THESE ARE THE NODES A MEMORY EDGE CAN NAME: the chain starts at MemStart
    # and advances through every effect that stores -- a package write, an
    # element assign, a delete, an aggregate-mutating builtin -- plus a Phi
    # where two chains merge. A Call qualifies only when it is one of the
    # mutators, which is exactly a Call that itself carries a memory edge.
    #
    # ITERATIVE AND MEMOISED, not recursive. A Phi merges two CHAINS and the
    # arms can end in different kinds of effect -- measured on comp/require.t,
    # `Phi(1190) in=[Call(require), EntryWrite]`, one arm a global-state call
    # and the other a store -- so every input has to be asked, not just the
    # first. That fan-out over a chain thousands of nodes long recursed past
    # perl's warning depth and did not finish; a worklist with a cache does it
    # in one pass, and a node already on the stack contributes no evidence
    # (a loop-carried Phi names itself across the back edge).
    method _is_memory ($id) {
        return $mem_cache{$id} if exists $mem_cache{$id};

        my (@stack, %pending) = ($id);
        @stack = ($id);
        while (@stack) {
            my $cur = $stack[-1];
            if (exists $mem_cache{$cur}) { pop @stack; next }

            my $n = $nodes->{$cur};
            unless ($n) { $mem_cache{$cur} = 0; pop @stack; next }
            my $op = $n->{op} // '';

            if ($op =~ /\A(?:MemStart|EntryWrite|CellWrite|Delete|Assign)\z/) {
                $mem_cache{$cur} = 1; pop @stack; next;
            }

            # The inputs that could make THIS node a memory point: every one
            # for a Phi, the last for a memory-carrying Call, none otherwise.
            my @in = ($n->{inputs} // [])->@*;
            my @ask = $op eq 'Phi'  ? @in
                    : $op eq 'Call' ? (@in > 1 ? ($in[-1]) : ())
                    :                 ();
            unless (@ask) { $mem_cache{$cur} = 0; pop @stack; next }

            # Anything not yet decided goes on the stack first. A node already
            # pending is a cycle and answers 0 for this question.
            my @todo = grep { defined $_ && $_ != $cur
                           && !exists $mem_cache{$_} && !$pending{$_} } @ask;
            if (@todo) { $pending{$cur} = 1; push @stack, @todo; next }

            $mem_cache{$cur} = (grep { $mem_cache{$_} } grep { defined } @ask)
                ? 1 : 0;
            delete $pending{$cur};
            pop @stack;
        }
        return $mem_cache{$id} // 0;
    }

    # A RegexSubst's operands, by position: (pattern_text, replacement_text).
    #
    # ITS INPUTS ARE [target, pattern?, replacement?, memory?] AND THE ARITY IS
    # RECOVERABLE from two fields already on the node:
    #
    #   pattern present     IFF `pattern_is_input`
    #   replacement present IFF the `replacement` string is empty
    #
    # Measured across all four shapes:
    #
    #     s/a/X/          in=[target]           pattern='a' replacement='X'
    #     s/a/x${y}y/     in=[target, repl]     pattern='a' replacement=''
    #     s/a/ 1+1 /e     in=[target]           pattern='a' replacement=2
    #     s/$p b$/X/      in=[target, pattern]  pattern=''  pattern_is_input=1
    #
    # THE MEMORY EDGE IS LAST AND IS NOT AN OPERAND. A destructive s/// stores
    # into its target, so it advances the chain and carries it -- rendering it
    # emits the memory node where the replacement belongs.
    #
    # A COMPUTED PATTERN IS WRAPPED IN (?:...): the value is a whole pattern
    # and the text around it is not, so `a|z` would bind past its own extent
    # and swallow what follows.
    method _subst_operands ($n) {
        my $f   = $n->{fields} // {};
        my @in  = ($n->{inputs} // [])->@*;
        shift @in;                       # the target

        my $pat;
        if ($f->{pattern_is_input}) {
            die "GAP: a RegexSubst says its pattern is an input but has none\n"
                unless @in;
            $pat = sprintf('(?:${\ (%s) })', $self->_expr(shift @in));
        }
        else {
            $pat = $f->{pattern};
            die "GAP: a RegexSubst with no pattern is not yet rendered\n"
                unless defined $pat;
        }

        my $rep = $f->{replacement};
        die "GAP: a RegexSubst with no replacement is not yet rendered\n"
            unless defined $rep;

        # An EMPTY replacement field means the replacement is a computed value
        # on inputs -- interpolated, or an /e result. Distinguishing it from a
        # genuinely empty replacement (`s/a//`) is the input's presence, once
        # the pattern and the memory edge are accounted for.
        if (!length $rep && @in && !$self->_is_memory($in[0])) {
            $rep = sprintf('${\ (%s) }', $self->_expr(shift @in));
        }

        return ($pat, $rep);
    }

    method _call_expr ($n) {
        my $f    = $n->{fields} // {};
        my $kind = $f->{dispatch_kind} // '';
        my $name = $f->{name};

        # AN INDIRECT CALL HAS NO NAME BY CONSTRUCTION -- its callee is a
        # value on inputs, which is the whole point of the kind. A
        # `dynamic_method` is the same situation one step over: `$o->$m` has a
        # name, but it is a VALUE the runtime computes, so it rides on inputs
        # too and the `name` field would be a lie. Every other kind names its
        # callee and an empty name there is a real gap.
        die "GAP: a Call with no name is not yet rendered\n"
            unless $kind eq 'indirect'
                || $kind eq 'dynamic_method'
                || (defined $name && length $name);

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
            # A SUB NAMED AFTER AN OPERATOR NEEDS THE AMPERSAND. comp/opsubs.t
            # defines subs called `s`, `tr`, `y`, `q`, `m`, `qq` and friends,
            # and `s("main")` parses as the SUBSTITUTION OPERATOR -- measured,
            # "syntax error ... near \"my \"" where the emitted line was
            # `my $eff114 = s("main");`.
            #
            # `&s(...)` is unambiguous and calls the sub, so it is used for
            # any name perl would otherwise read as a quote-like operator.
            # The parens stay: `&s` without them passes the CALLER's @_.
            # A CALLEE THE GRAPH DOES NOT CONTAIN CANNOT BE CALLED. Every sub
            # is its own `methods` entry on the wire, and a sub the PRODUCER
            # refused is simply absent -- while its CALLSITE survives, because
            # that lives in __PROGRAM__, which translated fine.
            #
            # Rendering the call anyway emitted a program that died:
            #
            #     Undefined subroutine &main::test_string called at ... line 168
            #
            # Measured on base/rs.t, whose test_string/test_record are refused
            # for assigning to a glob -- perl prints 44 lines, the emitted
            # program printed 2 and died. That reads as a successful render,
            # which is the one outcome worse than a GAP.
            #
            # ANONYMOUS BODIES AND BUILTINS ARE NOT THIS CASE: an anon sub is
            # reached through a reference rather than a name, and a builtin has
            # no `methods` entry by construction. Only a name that LOOKS like a
            # user sub and is absent is a call into nothing.
            die "GAP: a call to `$name`, which is not in the graph, cannot be"
              . " rendered -- the emitted program would die calling it\n"
                if $name =~ /\A\w+(?:::\w+)*\z/
                && !exists $all_methods->{$name};

            my $ident = $self->_sub_ident($name);
            return sprintf('&%s(%s)', $ident, join(', ', @args))
                if $ident =~ /\A(?:s|m|y|tr|q|qq|qw|qr)\z/;

            return sprintf('%s(%s)', $ident, join(', ', @args));
        }

        if ($kind eq 'builtin') {
            # `caller` CANNOT BE LOWERED TO PERL IDENTICALLY, whatever it is
            # rendered as. It reports the CALL STACK, and the deparsed program
            # is a different program: a sub emitted here sits at a different
            # depth, is called from a different line of a different file, and
            # `(caller)[0..2]` answers accordingly. Even a perfect spelling
            # gives a different -- correct -- answer.
            #
            # THIS DEPARSER IS A T2 CONSUMER, and refusing is what a T2 does
            # with an operation it cannot lower faithfully. T1 records that
            # the stack read HAPPENED (it is pinned to the control chain, see
            # %STACK_READ_BUILTIN in FromOptree) so a backend that CAN lower
            # it has everything it needs; this one cannot, and says so.
            #
            # NARROWED TO THE SHAPE THAT CANNOT BE SPELLED. A blanket refusal
            # cost nine corpus files, and measurement says it was refusing the
            # wrong thing: with the GAP removed, `comp/our.t` dies on
            # TIESCALAR and `comp/opsubs.t` differs from test 2 -- neither
            # because of `caller`. In four of them it sits in a
            # `sub failed { ... }` diagnostic that emits ZERO lines on a
            # passing run, and the emitted program agreed with perl exactly.
            #
            # What CANNOT round-trip is a caller BOUND TO A LIST. `my
            # ($p,$f,$l) = caller` needs the Call evaluated in list context by
            # the assignment, and a pinned Call binds to a scalar `$effN`
            # first -- `my $eff1 = caller(); my ($p,$f,$l) = ($eff1)` -- which
            # hands two targets undef. That is a wrong ANSWER, not merely a
            # different stack, so it refuses.
            #
            # The other shapes render. They will report this program's stack
            # rather than the original's, which is the honest T2 answer for a
            # construct whose meaning is its frame; a consumer that needs the
            # original's frame cannot get it from any deparse.
            if ($name eq 'caller' && $self->_feeds_list_assign($n->{id})) {
                die "GAP: a `caller` bound to a list cannot be rendered --"
                  . " the Call binds to a scalar temporary first, so the"
                  . " remaining targets would take undef\n";
            }

            # AN OP NAME IS NOT ALWAYS THE PERL SPELLING. The producer takes
            # `name` from the OP, and perl's op names do not all match the
            # keyword that produced them -- `printf` is the op `prtf`, and
            # emitting that verbatim gave "Undefined subroutine &main::prtf"
            # on comp/bproto.t, which died on its first test.
            #
            # A FILETEST IS AN OPERATOR, not a function: `-e $f`, whose op is
            # `ftis`. `ftis($f)` is a call to a sub that does not exist.
            #
            # THE TEST IS PERL'S OWN. `prototype("CORE::$name")` throws for a
            # name that is not a keyword, so the check does not depend on a
            # list of names anyone has to keep current -- which is how the
            # unspellable ones got here in the first place.
            if (my $spelling = $BUILTIN_SPELLING{$name}) {
                return sprintf('%s(%s)', $spelling, join(', ', @args))
                    unless ref $spelling;
                return $spelling->(@args);
            }
            die "GAP: the builtin op `$name` has no Perl spelling -- emitting"
              . " it verbatim would call a sub that does not exist\n"
                unless eval { my $p = prototype("CORE::$name"); 1 };

            # ONE-ARGUMENT `bless` BLESSES INTO THE CURRENT PACKAGE, and the
            # graph does not record which that was -- perl resolves it at
            # compile time from the enclosing `package` statement, so the node
            # carries only the referent.
            #
            # The SUB'S OWN NAME carries it. `xyz::new` runs in `xyz`, and the
            # emitted sub is now defined there too, but a `bless []` inside it
            # would still bless into whatever package the emitted file is in
            # at that point. Naming the class explicitly makes the emitted
            # program independent of that -- measured on
            # `package xyz; sub new { bless [] }`, where `ref($o)` came back
            # `main` instead of `xyz`.
            if ($name eq 'bless' && @args == 1) {
                # A package name is a bare identifier chain, so a single-quoted
                # literal needs no escaping.
                my $pkg = ($current_sub // '') =~ /\A(.*)::[^:]+\z/ ? $1 : 'main';
                return sprintf("bless(%s, '%s')", $args[0], $pkg);
            }

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
            # THE INVOCANT IS INPUT 0, AND class_name IS NOT IT. Measured on
            # `my $o = Thing->new; $o->greet("bob"); Thing->greet("amy")`:
            #
            #      4 Call name=new   class=Thing  in=[]
            #      6 Call name=greet class=Thing  in=[Call(4), "bob"]
            #     10 Call name=greet class=Thing  in=[Constant "Thing", "amy"]
            #
            # BOTH carry class_name=Thing -- it records where the method was
            # RESOLVED, not who it is called on. Input 0 is the invocant: the
            # object for an instance call, the class name itself for a class
            # call.
            #
            # Rendering `class_name->name(ALL inputs)` did two wrong things at
            # once: `$o->name` became `Thing->name($o)` -- the method called
            # on the CLASS with the instance as an argument -- and
            # `Thing->new("inst")` became `Thing->new("Thing", "inst")`,
            # passing the class twice.
            #
            # SO class_name IS NOT USED FOR THE SPELLING AT ALL. A call with
            # no class_name (an invocant in a variable, which is what
            # comp/opsubs.t holds) needs no special case: the invocant is in
            # the same place either way.
            # A CLASS CALL SOMETIMES HAS NO INPUTS AT ALL. Measured, the
            # invocant of `Thing->new` is a `Constant "Thing"` in one program
            # and absent in another -- so class_name is the FALLBACK when
            # input 0 is missing, not the primary spelling. Without an
            # invocant and without a class_name there is nothing to call the
            # method on.
            my $invocant;
            if (@args) { $invocant = shift @args }
            elsif (defined $f->{class_name}) {
                $invocant = $f->{class_name};
            }
            die "GAP: a method Call with no invocant and no class_name is"
              . " not yet rendered\n" unless defined $invocant;

            return sprintf('%s->%s(%s)',
                $invocant, $name, join(', ', @args));
        }

        if ($kind eq 'indirect') {
            # THE CALLEE IS INPUT 0, because it is a VALUE and cannot be a
            # name -- a code ref from a parameter, an element, a field. The
            # other three kinds all name their callee; this one is the case
            # that cannot, which is what the field distinguishes.
            #
            # Before it existed, such a call carried `dispatch_kind='direct'`
            # with the literal name 'unknown' and NO inputs, so the callee was
            # dropped and the emitted program called a sub nothing defines.
            die "GAP: an indirect Call with no callee is not yet rendered\n"
                unless @args;
            my $callee = shift @args;

            # `->` BINDS TIGHTER THAN `\`, so a callee that is an EXPRESSION
            # needs its own parens or the arrow lands inside it. Measured,
            # perl's own deparse of `\(&twice)->(21)`:
            #
            #     my $x = \&twice->(21);
            #
            # which calls `&twice` with no arguments -- the `&` form inherits
            # an empty @_ -- and then calls the RESULT as a code ref:
            #
            #     Undefined subroutine &main::0 called
            #
            # Two corpus cases died exactly that way, and it read as a missing
            # sub rather than as a precedence defect. The reference is fine on
            # its own: `\(&twice)` IS a CODE ref and `(\(&twice))->(21)` is 42.
            #
            # A SIMPLE VARIABLE NEEDS NO PARENS, and must not grow any: `$ref`,
            # `$self->{cb}` and `$h{k}` are already tighter than `->`, so
            # wrapping them would be noise in every ordinary call. The test is
            # the spelling rather than the node kind -- what matters is whether
            # `->` can bind to part of it, which is a question about the TEXT.
            $callee = "($callee)"
                unless $callee =~ /\A\$[\w:]+ (?: (?:->)? [\[{] .* [\]}] )* \z/x;
            return sprintf('%s->(%s)', $callee, join(', ', @args));
        }

        # `$o->$m` -- THE NAME IS INPUT 1, a value only the runtime knows.
        # Input 0 is the invocant, input 1 the method name, the rest arguments.
        # perl accepts a scalar holding a name directly in the method slot, so
        # the emission is the same shape as the source.
        #
        # Distinct from `indirect`, where input 0 is a CODE REF and there is no
        # name at all: here the name exists and is computed. Emitting this as
        # indirect produced `$o->()` and dropped the name, which died with
        # "Can't use an undefined value as a subroutine reference".
        if ($kind eq 'dynamic_method') {
            die "GAP: a dynamic method Call needs an invocant and a name\n"
                unless @args >= 2;
            my $invocant = shift @args;
            my $meth     = shift @args;
            # `->${\ EXPR}` takes a scalar ref to the name, which perl
            # accepts in the method slot for ANY expression -- verified, where
            # a bare `->$expr` only accepts a simple scalar variable and would
            # refuse a computed one.
            return sprintf('%s->${\\ %s}(%s)',
                $invocant, $meth, join(', ', @args));
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
            # THE REFERENT NEEDS ITS OWN SPELLING. `\2` and `\"x\n"` are both
            # folded to a ref Constant holding the REFERENT, and only the
            # numeric one is legal bare. Emitted raw, a string referent became
            #
            #     open($fh, "<", \x
            #     );
            #
            # which COMPILES -- bareword `x` followed by a literal newline --
            # and opens a handle on the string "x" rather than on "x\n". A
            # wrong answer that passes a compile check, which is why the
            # corpus's in-memory handles read nothing rather than refusing.
            #
            # Numeric stays bare: `$/ = \2` reads fixed-size records, and
            # `\"2"` would set the separator to the STRING and read different
            # ones.
            return sprintf('\\%s', $v) if $v =~ /\A-?[0-9]+(?:\.[0-9]+)?\z/;
            return sprintf('\\%s',
                $self->_constant({ fields =>
                    { const_type => 'string', value => $v } }));
        }

        if ($t eq 'glob') {
            die "GAP: a glob Constant whose name is `$v` is not a bareword\n"
                unless $v =~ /\A[A-Za-z_]\w*\z/;
            return $v;
        }

        # A CV NAMED AS A REFERENT. `\&foo` puts the SUB where a value goes,
        # and the producer records that as a `code` Constant holding the name
        # (there is no address at compile time, so the name is the only handle
        # on which sub it is) -- the same shape a `glob` Constant has for
        # `\*STDOUT`.
        #
        # SPELLED WITH THE AMPERSAND, which is what makes it the sub rather
        # than a bareword string: the enclosing Ref renders `\` and this
        # supplies `&foo`, so the pair comes back as `\&foo`. A package-
        # qualified name is as valid here as a plain one, unlike the bareword
        # handle above, because `&` already forces the sub interpretation.
        if ($t eq 'code') {
            die "GAP: a code Constant whose name is `$v` is not a sub name\n"
                unless $v =~ /\A[A-Za-z_]\w*(?:::\w+)*\z/;
            return '&' . $v;
        }

        die "GAP: no rule for a `$t` Constant\n";
    }
}

1;
