# ABOUTME: Perl compiler backend that dumps SoN IR graphs.
# ABOUTME: Usage: perl -MO=SoN file.pm (text) or perl -MO=SoN,json file.pm (JSON).

package B::SoN;

use v5.42.0;
use utf8;

use B qw(svref_2object);
use JSON::PP ();
use SoN::FromOptree;
use SoN::Render::Text;
use SoN::Serialize::JSON qw(to_json);
use SoN::OptSuppress;
use SoN::ClassAux;
use SoN::FieldInfo;
use SoN::IR::NodeFactory;
use SoN::IR::Graph;
use B::SoN::TypeLibrary;
use SoN::IR::Stamp;

# Suppress the peephole optimizer for the duration of the target program's
# compilation. B::SoN loads via -MO=SoN at BEGIN, before the target body
# compiles, so installing the no-op rpeep here keeps element access, list
# intro, and similar in canonical, unfused form (aelem/helem/pushmark+padsv
# rather than aelemfast/multideref/padrange) -- which map directly to the IR.
# rpeep is an optimization, not a correctness pass: the optree still executes.
BEGIN { SoN::OptSuppress::suppress_peep(); }

# _make_package_filter(\%include, \@exclude_prefixes) -> coderef
#
# One predicate answering "emit this package?". An INCLUDE list, when
# non-empty, is authoritative and exact -- preserving package=NAME's existing
# meaning exactly. Otherwise every package is emitted except those under an
# excluded prefix.
#
# Both may be given: the include list narrows first, then exclusions subtract.
# That combination is unusual but well-defined, and it keeps the two options
# from needing to know about each other at the call sites.
sub _make_package_filter {
    my ( $include, $exclude ) = @_;
    my @prefixes = @$exclude;
    my $has_include = %$include ? 1 : 0;

    return sub {
        my ($pkg) = @_;
        return 0 if $has_include && !exists $include->{$pkg};
        for my $prefix (@prefixes) {
            return 0 if rindex( $pkg, $prefix, 0 ) == 0;
        }
        return 1;
    };
}

# _emit_package($filter, $pkg) -> bool
#
# The single question every filter site asks. A filter of undef means no
# filtering was requested, so everything is emitted.
sub _emit_package {
    my ( $filter, $pkg ) = @_;
    return 1 unless $filter;
    return $filter->($pkg) ? 1 : 0;
}

# compile(\@opts) — called by O.pm; returns a CODE ref that O.pm invokes
# after the program has been compiled and the full optree is available.
sub compile {
    my @opts   = @_;
    my $format = 'text';
    $format    = 'json' if grep { $_ eq 'json' } @opts;

    # Two filters, and the difference is which way they fail.
    #
    # package=NAME is INCLUSION, exact match, multiple allowed. It emits only
    # what it is told about, which is right for a caller that KNOWS its input's
    # shape -- a corpus case whose classes are parsed out of the source. It is
    # wrong for a caller consuming arbitrary real files: anything it was not
    # told about vanishes silently, and a call into the vanished package then
    # arrives with no resolved callee and no return type, GAPping downstream
    # with a message that names the wrong layer.
    #
    # not_package=PREFIX is EXCLUSION, prefix match, multiple allowed. It emits
    # everything except the named trees. It fails toward NOISE (an
    # unanticipated internal leaks into the wire) rather than toward SILENCE
    # (an unanticipated user package disappears), which is the right direction
    # when the input's shape is not known in advance.
    #
    # PREFIX rather than exact, because the use case is "drop the SoN:: tree"
    # -- ~90 classes -- and enumerating them is not maintainable. Exclusion
    # also catches namespaces no source scan would find: perl's own
    # t/base/lex.t creates `xyz` via `sub xyz::foo {...}` with no `package`
    # statement anywhere.
    my ( %pkg_filter, @pkg_exclude );
    for my $opt (@opts) {
        if    ( $opt =~ /^package=(.+)$/ )     { $pkg_filter{$1} = 1 }
        elsif ( $opt =~ /^not_package=(.+)$/ ) { push @pkg_exclude, $1 }
    }

    # Resolved to ONE predicate so the three call sites stay a single question
    # ("emit this package?") rather than growing a second one. undef means
    # emit everything, preserving the no-filter path exactly.
    my $filter;
    if ( %pkg_filter || @pkg_exclude ) {
        $filter = _make_package_filter( \%pkg_filter, \@pkg_exclude );
    }

    return sub {
        my ( $graphs, $classes ) = _discover_and_translate($filter);

        if ( $format eq 'json' ) {
            print to_json( $graphs, $classes );
        }
        else {
            for my $name ( sort keys $graphs->%* ) {
                print "=== $name ===\n";
                my $renderer = SoN::Render::Text->new();
                print $renderer->render( $graphs->{$name} );
                print "\n";
            }
        }
    };
}

# _discover_and_translate() — walk all package stashes, translating CVs to SoN
# graphs and collecting feature-class structure. Returns ($graphs, $classes):
# $graphs is fully-qualified name => graph; $classes is class name => declarative
# class structure (parent, fields, methods) for the MOP replay.
sub _discover_and_translate {
    my ($filter) = @_;
    my %graphs;
    my %classes;
    _walk_package( \%graphs, \%classes, 'main', \%main::, $filter );

    # The bare file's own top-level statements (main_root/main_start/main_cv)
    # are not a CV in any stash, so _walk_package never sees them -- translate
    # them separately into main::__PROGRAM__, the entry protocol's exit graph
    # (t/bootstrap/corpus/executable-gate.t in the chalk repo looks for this
    # key first). Respect package=main the same way a CV emission would; an
    # empty main_root (nothing at top level) is common (a library file with
    # no top-level statements) and not an error.
    my $emit_program = _emit_package($filter, q{main});
    if ( $emit_program && ${ B::main_root() } ) {
        try {
            $graphs{'main::__PROGRAM__'} = SoN::FromOptree->translate_root();
        }
        catch ($e) {
            # Same discipline as _walk_package: a GAP refusal is the
            # translator speaking (surface it loudly); a non-GAP exception is
            # an internal producer bug and must not be silently swallowed.
            if ($e =~ /^GAP:/) {
                warn "B::SoN: skipped main::__PROGRAM__: $e";
            }
            else {
                warn "B::SoN: INTERNAL ERROR translating main::__PROGRAM__ (masked as "
                   . "a silent skip -- fix or convert to a clean GAP): $e";
            }
        }
    }

    # Under a package= filter, a class referenced from an emitted sub (e.g.
    # `Counter->new` / `$c->get` inside main::) is not itself in the filter, so
    # its MOP + method graphs were skipped -- leaving the method Call with no
    # return repr to infer from. Transitively emit the MOP of every class
    # actually referenced (via a method Call's class_name) from the graphs we
    # have, and only those classes: the whole stash would leak every internal
    # SoN class. A newly-emitted method graph may reference further classes, so
    # fixpoint until no new class appears.
    _emit_referenced_classes( \%graphs, \%classes, $filter ) if $filter;

    _resolve_deferred_stamps( \%graphs, \%classes );

    return ( \%graphs, \%classes );
}

# _resolve_deferred_stamps(\%graphs, \%classes) -- answer, once every graph
# exists, the stamp questions a single-CV walk could not.
#
# WHY A POST-PASS AT ALL. The walk translates one CV at a time in stash order.
# A Call is built while translating its CALLER, so the callee's graph may not
# exist yet -- and for a recursive call no order helps. A class field's declared
# type is recorded by _wire_field_defaults during class extraction, which for a
# method walked first has not run. Both answers exist once the walk is done.
# This is the same late-decoration shape as Call::set_resolved_graph and the
# loop-header Phi patch in Node::set_stamp: build first, then fill in what only
# the completed set knows.
#
# ORDER IS LOAD-BEARING, and it is a dependency chain, not a preference:
#
#   field type -> FieldAccess stamp -> method return type -> Call stamp
#
# `method val { return $n }` returns a FieldAccess. Until that read is typed,
# _graph_return_type reports Unknown for the method, and a callsite reading that
# record learns nothing. Stamping fields first and RE-deriving the method return
# types is what turns one root fix into the whole chain. Run in the other order
# and every step still reads the value from before the step below it landed.
#
# The literal-subscript pass runs last and joins the chain rather than starting
# it: an aggregate's elements may themselves be calls or field reads, so it wants
# those already stamped.
sub _resolve_deferred_stamps {
    my ( $graphs, $classes ) = @_;

    # BEFORE THE LOOP, and once. It rewrites node KINDS rather than filling
    # stamps, so it has nothing to converge to -- and running it first lets
    # _stamp_field_reads type the FieldAccess it produces on the very next
    # line, instead of needing a second path to type it.
    _readers_read_fields( $graphs, $classes );

    # TO A FIXPOINT, because the passes FEED EACH OTHER and no hand-ordering
    # resolves that. Measured: backward inference types `$x` in
    # `sub add1 { my ($x) = @_; return $x + 1 }`, but the Add above it is typed
    # by _stamp_derived, which runs LATER -- so the return type was re-derived
    # from a still-Unknown Add and stayed Unknown, and every callsite with it.
    # Reordering only moves which pass is starved: the true dependency is a
    # cycle (backward -> arithmetic -> return type -> callsite -> arithmetic).
    #
    # Terminating because every pass only ever writes a stamp to a node that
    # had `Unknown`, and never widens one. The lattice has finite height and the
    # untyped set shrinks monotonically, so the sweep count is bounded by it.
    # The cap is a backstop against a pass that violates that, not a schedule.
    my $ROUNDS = 8;
    for my $round ( 1 .. $ROUNDS ) {
        my $before = _count_unknown_stamps($graphs);

        # BACKWARD INFERENCE RUNS LAST. A forward pass derives an ACTUAL
        # type (the field record says Int; the callee return type says Str).
        # Backward inference derives only a CONSTRAINT: `*` requires Num, which
        # Int already satisfies and is strictly weaker than. Run it first and it
        # PREEMPTS the better answer -- measured, `field $val :param = 0` has
        # type Int on its record, but backward inference stamped the FieldAccess
        # Num from the `*` above it, and _stamp_field_reads then skipped the node
        # because its own only-fill-Unknown guard saw a stamp already there.
        # Both guards are correct; the ORDER was wrong. Int * Int came out Num.
        _stamp_field_reads( $graphs, $classes );
        _stamp_reader_accessors( $graphs, $classes );
        _rederive_method_return_types( $graphs, $classes );
        _rederive_sub_return_types( $graphs, $classes );
        _stamp_calls_from_callees( $graphs, $classes );
        _stamp_literal_subscripts($graphs);
        _stamp_merges($graphs);
        _stamp_derived($graphs);
        _infer_backward($graphs);

        last if _count_unknown_stamps($graphs) == $before;
    }

    # AFTER THE FIXPOINT, NOT INSIDE IT. The floor answers `Scalar`, which is
    # the weakest possible answer, and every narrowing pass above guards on
    # only-fill-Unknown. Run inside the loop it stamps on round 1 and each
    # narrowing pass then SKIPS the node -- measured: `field $items = [10,20,30];
    # method first { $items->[0] }` came out `Scalar` where `Int` is provable,
    # and chalk's loader refused the graph over the disagreement with its own
    # derivation. Same ordering rule the loop comment states for backward
    # inference, one step weaker.
    _floor_subscripts($graphs);
    _floor_element_removals($graphs);
    _floor_param_fields( $graphs, $classes );
    _floor_package_globals($graphs);
    _floor_list_assigns($graphs);


    # AND RE-RUN THE CHAIN ABOVE IT. A Return whose value is floored must carry
    # the floor too, or the wire contradicts itself: the node says Scalar while
    # its method's return_type record still says Unknown.
    #
    # A FLOORED NODE IS NOT A LEAF. A floored Subscript is one -- it takes no
    # Unknown input it could have inherited from -- but a floored `shift` sits
    # at the BOTTOM OF A CHAIN: it retypes its sub's return type, which retypes
    # every CALL to that sub, which retypes whatever those calls feed. Running
    # only the two return-type passes left `sub f { my $n = shift; return $n }`
    # with `return_type: Scalar` on its record and `Unknown` on its callsite --
    # the same contradiction one level up. So the dependent chain runs to a
    # fixpoint of its own, bounded the same way the main loop is.
    #
    # COERCION INSERTION RUNS INSIDE THAT FIXPOINT, because the dependency goes
    # BOTH WAYS and neither order alone terminates it:
    #
    #   insertion needs the chain   a coercion is decided from the operand's
    #                               TYPE, and `$p->left + $p->right` has Calls
    #                               that are Unknown until the chain types them
    #                               from their callee. Asked first, the pass
    #                               correctly declines and never returns.
    #
    #   the chain needs insertion   inserting a Coerce re-derives the consuming
    #                               node, which invalidates its sub's
    #                               return_type and every callsite reading it.
    #
    # Measured: with insertion ahead of the chain, 4 positions across
    # classes-013/014 wanted a Coerce and never got one -- exactly the
    # `:param`-field Calls the chain types on its own next round. Inside the
    # loop they are typed, then coerced, then re-derived.
    for my $round ( 1 .. $ROUNDS ) {
        my $before = _count_unknown_stamps($graphs);
        _rederive_method_return_types( $graphs, $classes );
        _rederive_sub_return_types( $graphs, $classes );
        _stamp_calls_from_callees( $graphs, $classes );
        _stamp_derived($graphs);
        my $coerced = _insert_type_coercions( $graphs, $classes );
        # The Unknown count alone cannot see this pass: a Str -> Num repair
        # moves no node off Unknown. So a round that inserted anything is a
        # round that changed something, and the loop must go again.
        last if !$coerced && _count_unknown_stamps($graphs) == $before;
    }

    return;
}

# _floor_subscripts(\%graphs) -- a Subscript that nothing narrowed is `Scalar`.
#
# A SUBSCRIPT IS NEVER `Unknown`. `$a[...]` and `$h{...}` read ONE slot, and one
# slot of any Perl aggregate holds a scalar. There is no program in which a
# subscript is plural: a slice is a different node kind entirely
# (`Slice :isa(Aggregate)`, against `Subscript :isa(Access)`). So a read nothing
# could narrow still has a TRUE answer, and it is `Scalar`.
#
# WHY THAT IS WORTH EMITTING, given `Scalar` is barely a type. Chalk compiles
# AHEAD OF TIME, so there is no runtime to defer to: an `Unknown` is not a
# missing annotation, it is a HOLE IN THE EMITTED PROGRAM. `Scalar` lowers to
# `%Slot`, the tagged `{i1 defined, i64 payload}` carrier chalk already emits in
# every prologue and object struct. That is slower than an `i64` and it RUNS.
# The ranking is: narrow type > `%Slot` > nothing. An unconverged type costs
# SPEED; a missing representation costs the PROGRAM.
#
# THE FLOOR IS A FLOOR, NOT AN ANSWER. `Scalar` where `Int` is provable is also
# a T1 failure, just a less obvious one. This runs last precisely so it claims
# only what nothing else could.
#
# AN LVALUE SUBSCRIPT IS AN ADDRESS, NOT A VALUE, and stamping one is wrong in
# KIND rather than in width. A store TARGET is built as a 2-input node
# (container, index) with NO memory input, so that it never hash-conses with a
# pre-store rvalue read of the same slot (FromOptree, the aelem/helem handler).
# The input count is the discriminator.
sub _floor_subscripts {
    my ($graphs) = @_;

    for my $gname ( sort keys $graphs->%* ) {
        my $graph = $graphs->{$gname} or next;
        for my $node ( $graph->nodes->@* ) {
            next unless $node->isa('SoN::IR::Node::Subscript');
            next unless ( $node->stamp ? $node->stamp->type : '' ) eq 'Unknown';
            my @in = ( $node->inputs // [] )->@*;

            # ARITY IS NOT THE QUESTION. `$x[0] = 'foo'` compiles to a single
            # `aelemfast[*x] sM` with no separate memory operand, so its
            # Subscript carries only (array, index) -- two inputs. Keying this
            # pass on `@in >= 3` skipped exactly those and left them Unknown on
            # the wire. What makes a floor apply is that the node is an element
            # access whose type nothing narrowed, which is true at either arity.
            #
            # TAKE THE STORE'S TYPE BEFORE FALLING TO THE FLOOR. The third
            # input IS the memory this read is threaded to, and when that is
            # the Assign that put the value there, the stored type is already
            # sitting on it:
            #
            #     Assign     in=(Subscript, Constant:Str)  stamp=Str
            #     Subscript  in=(EntryDef, Constant:Int, Assign:Str)
            #
            # `$a[0] = "foo"; $a[0]` was floored to Scalar with Str on the
            # input. Scalar was not WRONG -- an element is one scalar slot --
            # it was the weakest true answer where a stronger one was present.
            my $mem = @in >= 3 ? $in[2] : undef;
            if ( $mem && $mem->isa('SoN::IR::Node::Assign') ) {
                my $st = $mem->stamp;
                if ( $st && $st->type ne 'Unknown' ) {
                    $node->set_stamp( SoN::IR::Stamp->new( type => $st->type ) );
                    next;
                }
            }

            # Threaded to something that cannot say -- a MemStart, a Phi, or a
            # store whose own type is undetermined. One element is one scalar
            # slot, which stays true whatever it holds.
            $node->set_stamp( SoN::IR::Stamp->new( type => 'Scalar' ) );
        }
    }
    return;
}

# _floor_list_assigns(\%graphs) -- a list assignment says what its two contexts
# agree on.
#
# `my ($a,$b,$c) = @_` yields TWO different things in perl, measured:
#
#     scalar context   ( ($a,$b,$c) = @src )  is 3    -- the COUNT of RHS
#                                                        elements, an Int
#     list context     ( ($a,$b,$c) = @src )  is (7,8,9) -- the assigned LHS
#
# A context-sensitive node is still floorable at the JOIN of its results: sound,
# and vaguer than reading OPf_WANT at the construction site would be, but never
# wrong. The lattice decides what that join is; this pass does not name a type.
#
# A FLOOR, NOT A TABLE ROW, because the two shapes are not equally knowable. A
# two-input scalar assign is already stamped from its RHS by the walker
# (`$a[0] = "foo"` is Assign:Str) -- strictly more precise than any join. A row
# in TypeLibrary would answer for every Assign and overwrite those; a floor
# fills an Unknown and leaves a narrowed node alone. Same discipline as
# _floor_subscripts, which takes the store's type before falling back.
sub _floor_list_assigns {
    my ($graphs) = @_;

    my $lub = SoN::IR::Stamp::join(
        SoN::IR::Stamp->new( type => 'Int' ),
        SoN::IR::Stamp->new( type => 'List' ),
    )->type;

    for my $gname ( sort keys $graphs->%* ) {
        my $graph = $graphs->{$gname} or next;
        for my $node ( $graph->nodes->@* ) {
            next unless $node->isa('SoN::IR::Node::Assign');
            next unless ( $node->stamp ? $node->stamp->type : '' ) eq 'Unknown';

            # ONLY THE LIST SHAPE. A scalar assign carries (target, value) and
            # takes its type from the VALUE -- a narrowing that runs after this
            # pass, so flooring one here would win a race it has no business
            # winning and pin `$a[0] = $n` to List. The list form is the one
            # with several targets and no single RHS operand to echo.
            my @in = ( $node->inputs // [] )->@*;
            next unless @in > 2;

            $node->set_stamp( SoN::IR::Stamp->new( type => $lub ) );
        }
    }
    return;
}

# _floor_package_globals(\%graphs) -- a package global read that nothing
# narrowed is what its SIGIL says it is.
#
# perl guarantees the CONTAINER even when it says nothing about the contents:
# `$x` is one scalar, `@x` an array, `%x` a hash. That is the weakest true
# statement about the node, which is exactly what a floor is. Measured over
# perl's t/base, EntryDef was the largest single source of wire Unknowns (7 of
# 22), and every derived Unknown -- Add, Or, Subscript, Assign -- was Unknown
# only because an operand was.
#
# SCALAR IS THE CONTAINER, NOT THE CONTENTS. A package `$x` holding an arrayref
# is still a scalar: Scalar excludes Array, Hash, Code and Glob but INCLUDES
# references, so the floor stays true for `$x = [1,2]` and for a tied or
# aliased global. It claims nothing about what is inside.
#
# ONLY EntryDef, NOT Call. A Call floored here would carry a stamp into the
# dependent-chain fixpoint below, whose passes all guard on only-fill-Unknown
# -- so the floor would PREEMPT the answer that chain exists to compute. That
# is the failure recorded above for :param fields, and 89b0008 reverted a
# guessed Scalar for the same reason: it launders a missing inference into a
# legitimate-looking annotation. A global has no such chain; a Call does.
sub _floor_package_globals {
    my ($graphs) = @_;

    my %BY_SIGIL = ( '$' => 'Scalar', '@' => 'Array', '%' => 'Hash' );

    for my $gname ( sort keys $graphs->%* ) {
        my $graph = $graphs->{$gname} or next;
        for my $node ( $graph->nodes->@* ) {
            next unless $node->isa('SoN::IR::Node::EntryDef');
            next unless ( $node->stamp ? $node->stamp->type : '' ) eq 'Unknown';

            my $type = $BY_SIGIL{ $node->sigil // '' } or next;
            $node->set_stamp( SoN::IR::Stamp->new( type => $type ) );
        }
    }
    return;
}

# _floor_element_removals(\%graphs) -- `shift`/`pop` that nothing narrowed
# takes the floor B::SoN::TypeLibrary's builtin index states for it.
#
# THE ANSWER MOVED INTO THE TABLE; THE TIMING STAYED HERE. This pass used to
# spell `Scalar` out itself, which made it one row of a builtin result index
# written as a graph walk. The row now lives in TypeLibrary beside every other
# result type, and this asks for it -- but the ASKING still has to happen after
# the fixpoint, for the reason the caller's comment gives: `Scalar` is the
# weakest possible answer, and every narrowing pass guards on only-fill-Unknown,
# so a floor stamped inside the loop is a floor no later pass can lift. Measured
# both ways: inside the loop, `my $u = shift; ... if ($u > 1) { $x = $u }` gave
# the merge Phi `Scalar` instead of leaving it honestly Unknown.
#
# WHAT THE ROW SAYS, and why it is sound: `shift @a` and `pop @a` REMOVE AND
# RETURN ONE element, so whatever the array holds, the result is a scalar --
# in ANY context, unlike `splice`. FromOptree stamps the array's own element
# type where it can read it (`my @q=(1,2,3); shift @q` is `Int`), and that
# narrower answer keeps precedence; this only covers where it declined.
#
# @_ IS THE CASE THAT MATTERS. Bare `shift` is `shift @_`, and an `ArgsSource`
# has no element nodes to read, so the element stamp always declines there. That
# left `my $n = shift` Unknown, which made the sub's `return_type` Unknown, which
# made every CALL to it Unknown: measured over chalk's corpus, `shift` was 5
# roots carrying most of the 21 callee-return cascades behind it.
#
# THE OTHER shift/pop SITES ARE NOT RESULT TYPES and are untouched: FromOptree's
# implicit-@_ argument synthesis, its memory-SSA effect modelling,
# `_body_stores_memory` / `_cond_drains_array`, and `_op_uses_args` all ask what
# shift/pop DO, not what they yield.
sub _floor_element_removals {
    my ($graphs) = @_;

    for my $gname ( sort keys $graphs->%* ) {
        my $graph = $graphs->{$gname} or next;
        for my $node ( $graph->nodes->@* ) {
            next unless $node->isa('SoN::IR::Node::Call');
            next unless ( $node->dispatch_kind // '' ) eq 'builtin';
            my $name = $node->name // '';
            next unless $name eq 'shift' || $name eq 'pop';
            next unless ( $node->stamp ? $node->stamp->type : '' ) eq 'Unknown';

            my $type = B::SoN::TypeLibrary::result_for( [ 'Call', $name ] )
                // next;
            $node->set_stamp( SoN::IR::Stamp->new( type => $type ) );
        }
    }
    return;
}

# _stamp_field_reads(\%graphs, \%classes) -- give each class-field read the type
# its field was declared with.
#
# WHAT WAS WRONG. _wire_field_defaults derives a field's type from its default
# and records it on the class section as `type`. A FieldAccess node carries
# field_stash and field_index, which select exactly that record -- and nothing
# read it back, so every class-field read reached the wire `Unknown`. Measured
# over chalk's 231 corpus cases, 21 of 233 wire Unknowns were this node kind,
# and they fed a further chain of Add/Assign/method-return Unknowns above them.
#
# ONLY PROPAGATES. A field with no default has no derived type, and its reads
# stay Unknown -- the honest answer. Nothing is invented here.
sub _stamp_field_reads {
    my ( $graphs, $classes ) = @_;

    for my $gname ( sort keys $graphs->%* ) {
        my $graph = $graphs->{$gname} or next;
        for my $node ( $graph->nodes->@* ) {
            next unless $node->isa('SoN::IR::Node::FieldAccess');
            next unless ( $node->stamp ? $node->stamp->type : '' ) eq 'Unknown';

            my $cls = $classes->{ $node->field_stash // '' } or next;
            my $fix = $node->field_index;
            next unless defined $fix;

            # Keyed by the DECLARED fieldix, not by array position: the two
            # coincide today, but a field the extractor skips would silently
            # shift every later index and mistype every read above it.
            my ($rec) = grep { ( $_->{fieldix} // -1 ) == $fix }
                        ( $cls->{fields} // [] )->@*;
            next unless $rec && defined $rec->{type} && $rec->{type} ne 'Unknown';

            $node->set_stamp( SoN::IR::Stamp->new( type => $rec->{type} ) );
        }
    }
    return;
}


# _readers_read_fields(\%graphs, \%classes) -- a `:reader` accessor's body reads
# a FIELD, so it is a FieldAccess, exactly like the method it stands in for.
#
# WHAT WAS WRONG. Two methods that do the same thing reached the wire as
# different node kinds:
#
#     class P { field $x :param :reader = 1 }
#       P::x     ->  Start, PadAccess:Scalar,   Return
#     class Q { field $y :param = 1; method get { $y } }
#       Q::get   ->  Start, FieldAccess:Scalar, Return
#
# A PadAccess is a LEXICAL read and the field lives in the object, so the reader
# graph described reading somewhere the value is not. Reported by chalk, which
# never hit it as a miscompile only because its backend SYNTHESISES the accessor
# from the field record rather than lowering this graph -- the wrong-shaped
# graph shipped and was discarded.
#
# THE WALKER WAS NOT GUESSING. perl's own metadata differs between the two.
# Measured on 5.42.0: the pad entry for `$y` in Q::get answers PadnameFIELDINFO
# (is_field true), while `$x` in P::x carries FLAGS 0x0 and answers false --
# perl compiles the generated reader against a REAL pad slot, not a field alias.
# `_make_pad_or_field` asks that question and gets an honest "not a field", so
# the correction cannot come from the pad. It comes from the CLASS RECORD, the
# only place that knows `$x` is a reader and which fieldix it reads.
#
# A KIND REWRITE, NOT A STAMP, which is why it is separate from
# _stamp_reader_accessors and runs before the fixpoint rather than inside it.
sub _readers_read_fields {
    my ( $graphs, $classes ) = @_;
    my $factory = SoN::IR::NodeFactory->new;

    for my $cname ( sort keys $classes->%* ) {
        my $fields = $classes->{$cname}{fields} or next;
        for my $f (@$fields) {
            next unless $f->{is_reader};
            my $fname = $f->{name} // next;          # '$x'
            my $fidx  = $f->{fieldix} // next;
            ( my $bare = $fname ) =~ s/^[\$\@\%]//;  # 'x'

            # `field $x` synthesizes the accessor `Class::x`.
            my $graph = $graphs->{"${cname}::${bare}"} or next;

            # The reader body is one PadAccess of the field's own name. Rewire
            # every consumer of it -- a Return here, but nothing depends on
            # that -- so no stale PadAccess is left reachable.
            my @stale = grep {
                $_->isa('SoN::IR::Node::PadAccess')
                    && ( $_->varname // '' ) eq $fname
            } $graph->nodes->@*;
            next unless @stale;

            my $field_read = $factory->make( 'FieldAccess',
                field_index => $fidx,
                field_stash => $cname,
            );

            for my $node ( $graph->nodes->@* ) {
                my $inputs = $node->inputs or next;
                for my $i ( 0 .. $#$inputs ) {
                    my $in = $inputs->[$i] // next;
                    next unless ref $in;
                    $inputs->[$i] = $field_read
                        if grep { $_ == $in } @stale;
                }
            }
        }
    }
    return;
}

# _stamp_reader_accessors(\%graphs, \%classes) -- a `:reader` accessor returns
# its field's declared type.
#
# WHAT WAS MISSING. The accessor body is synthesized as a `PadAccess` read of
# the field slot, NOT a `FieldAccess` -- so `_stamp_field_reads` never sees it,
# and the accessor reached the wire `Unknown` while the field record beside it
# said `type: Int`. Found while unblocking chalk's vtable ABI probe:
# `class Box { field $v :param :reader = 0 }` put `Box::v` on the wire untyped.
#
# NEITHER OF THE OTHER PASSES CAN DO THIS, and that is the point. Backward
# inference correctly DECLINES -- `return $v` publishes no operator requirement,
# so a use site has nothing to say. `_stamp_field_reads` is looking for the
# wrong node kind. The hole is real and its AUTHORITATIVE SOURCE is the field's
# declared type; this is the connection, not an analysis.
#
# MATCHED ON THE FIELD NAME, not on the graph name. A reader for `field $n` is
# the graph `Class::n` and its body reads `varname => '$n'`, so the sigil-less
# graph name and the sigil-carrying varname both identify it -- but the varname
# is what the NODE carries, and matching the node against the field record it
# actually reads is the honest join. Guarded on is_reader so an ordinary method
# that happens to share a field's name is not caught by it.
#
# ONLY PROPAGATES. A field with no declared `type` (a `:param` with no default
# has none -- its type depends on what a caller passes) leaves its reader
# `Unknown`.
sub _stamp_reader_accessors {
    my ( $graphs, $classes ) = @_;
    my $changed = 0;

    for my $cname ( sort keys $classes->%* ) {
        my $fields = $classes->{$cname}{fields} or next;
        for my $f (@$fields) {
            next unless $f->{is_reader};
            my $ftype = $f->{type};
            next unless defined $ftype && $ftype ne 'Unknown';

            # `field $n` synthesizes the accessor `Class::n`.
            my $fname = $f->{name} // next;          # '$n'
            ( my $bare = $fname ) =~ s/^[\$\@\%]//;  # 'n'
            my $graph = $graphs->{"${cname}::${bare}"} or next;

            # THE BODY IS A FieldAccess, rewritten from the pad read by
            # _readers_read_fields. Matching it by the fieldix it carries is
            # exact where the old varname match was a name coincidence.
            #
            # _stamp_field_reads types the same node from the same record, but
            # only INSIDE the fixpoint -- and a `:param` with no default is not
            # typed until _floor_param_fields, which runs after it. This pass is
            # in the post-floor chain, so it is what closes that case.
            for my $node ( $graph->nodes->@* ) {
                next unless $node->isa('SoN::IR::Node::FieldAccess');
                next unless ( $node->field_index // -1 ) == ( $f->{fieldix} // -2 );
                next unless ( $node->field_stash // '' ) eq $cname;
                next unless ( $node->stamp ? $node->stamp->type : '' ) eq 'Unknown';
                $node->set_stamp( SoN::IR::Stamp->new( type => $ftype ) );
                $changed++;
            }

            # The accessor is synthesized from the field attribute rather than
            # emitted as a method, so `methods` does not list it and
            # _rederive_method_return_types will not reach it. Record the
            # return type here, from the same source.
            $classes->{$cname}{method_return_types}{$bare} = $ftype
                unless ( $classes->{$cname}{method_return_types}{$bare} // 'Unknown' )
                       ne 'Unknown';
        }
    }
    return $changed;
}

# _floor_param_fields(\%graphs, \%classes) -- a `:param` field admits any
# scalar, so one nothing else could type is `Scalar`, not nothing.
#
# THE ANSWER WAS ALREADY WRITTEN DOWN ONE BRANCH AWAY. _extract_fields records
# join(default, Scalar) = Scalar for a `:param` field WITH a default, and its
# comment gives the reason: `:param` lets a caller pass anything, so the default
# types the INITIALISER, not the field --
#
#     Box->new(v => "hello")  ->  hello
#     Box->new(v => [1,2])    ->  an ARRAY ref
#
# A `:param` with NO default admits exactly the same set. Same `Scalar`, reached
# from strictly less evidence. The producer recorded no type at all instead,
# which is the audit's bucket two: the evidence was in hand, the question never
# asked.
#
# `Scalar` IS NOT NOTHING. It excludes Array, Hash, Code and Glob, and it is
# refinable: `field $bal :param; method half { $bal / 2 }` still yields Num,
# because the narrowing passes run BEFORE this one and `/` imposes its own
# requirement.
#
# A FLOOR, NOT A SEED -- and this is the whole reason it lives here rather than
# at extraction time. Written into the field record when the record is BUILT, it
# arrives before the narrowing chain, every pass above guards on
# only-fill-Unknown, and each one then SKIPS the node. Measured, and it broke
# three tests that pin exactly this: `field $n :param; method inc { $n + 1 }`
# came out `Scalar` where `Num` is provable, and the sub-return and callsite
# cascade lost it too. Identical to the ordering rule already stated for
# _floor_subscripts and for backward inference: the weakest answer must speak
# LAST.
#
# ONLY FOR A `:param`. A field with no outside writer keeps whatever narrow type
# its default gives it -- that default is the whole truth about it.
sub _floor_param_fields {
    my ( $graphs, $classes ) = @_;
    my $changed = 0;

    for my $cname ( sort keys $classes->%* ) {
        my $fields = $classes->{$cname}{fields} or next;
        for my $f (@$fields) {
            next unless $f->{is_param};
            next if defined $f->{type} && $f->{type} ne 'Unknown';
            $f->{type} = 'Scalar';
            $changed++;
        }
    }

    # The readers are stamped from the field record, so re-running the pass that
    # reads it is what carries the floor onto the wire -- and it records the
    # method return type from the same source.
    $changed += _stamp_reader_accessors( $graphs, $classes );
    return $changed;
}

# _insert_type_coercions(\%graphs) -- materialise a Coerce wherever an operand's
# TYPE must change to satisfy the position it is used in.
#
# THE PREDICATE IS `meet(from, to) != from`, and the two halves do different
# jobs: the MEET is the test, the REQUIREMENT is the target. If the meet IS the
# source, the source already satisfies the target and nothing changes -- no
# node. Otherwise the value's type genuinely differs from what the position
# needs, and the conversion is `Coerce[from -> to]`.
#
# DIRECTED, THOUGH MEET IS SYMMETRIC. Comparing the result against ONE side is
# what makes it so:
#
#     meet(Str, Num) = Num, and Num ne Str   -> coerce Str to Num
#     meet(Num, Str) = Num, and Num eq Num   -> do not
#
# One direction of each pair fires, so the coercion relation is ACYCLIC and
# cannot oscillate. That matters: a symmetric trigger over Perl's mutually
# convertible Int/Num/Str would admit two coercion paths between the same pair,
# which is the classical ambiguity hazard (Swamy/Hicks/Bierman, ICFP 2009).
#
# NOT `meet == None`. That is the narrower case of two INCOMPARABLE types and
# misses every NARROWING: `Str -> Num` and `Scalar -> Str` both need a real
# conversion and neither meets to None. Measured over chalk's 240-block corpus,
# the ==None rule finds ZERO sites and this one finds 28.
#
# TYPE CHANGES ONLY -- this pass is not the producer's stringification path.
# `Int` in a `Str` position meets to `Int`, so nothing fires: an Int already
# satisfies a Str requirement on the type axis. Rendering it as characters is a
# REPRESENTATION change, a different axis and a different layer's decision.
sub _insert_type_coercions {
    my ( $graphs, $classes ) = @_;
    my $factory  = SoN::IR::NodeFactory->new;
    my $inserted = 0;
    my %restamp;    # graph name => node id => node, for operands replaced

    for my $gname ( sort keys $graphs->%* ) {
        my $graph = $graphs->{$gname} or next;
        for my $node ( $graph->nodes->@* ) {
            my $inputs = $node->inputs or next;
            for my $i ( 0 .. $#$inputs ) {
                my $want = B::SoN::TypeLibrary::operand_type(
                    B::SoN::TypeLibrary::type_key($node), $i ) // next;
                my $operand = $inputs->[$i] or next;
                next unless ref $operand && $operand->isa('SoN::IR::Value');

                # An operand nothing typed cannot be tested. Leave it: the pass
                # reads types, it does not invent them.
                my $from = $operand->stamp ? $operand->stamp->type : 'Unknown';
                next if $from eq 'Unknown';

                # AND NEVER STACK ONE ON A COERCE. Its result is already the
                # target type, so the predicate would decline anyway -- but
                # saying so here keeps a second pass over the same graph from
                # depending on that.
                next if $operand->operation eq 'Coerce';

                my $meet = SoN::IR::Stamp::meet(
                    SoN::IR::Stamp->new( type => $from ),
                    SoN::IR::Stamp->new( type => $want ),
                );
                next if $meet->type eq $from;

                $inputs->[$i] = $factory->make(
                    'Coerce',
                    from_repr => $from,
                    to_repr   => $want,
                    inputs    => [$operand],
                    stamp     => SoN::IR::Stamp->new( type => $want ),
                );
                $inserted++;
                $restamp{$gname}{ $node->id } = $node;
            }
        }
    }

    # RE-DERIVE WHAT THE OLD OPERAND DECIDED. A node's stamp was computed while
    # the graph was built, from the operand that is no longer there -- so a node
    # this pass rewrote is carrying an answer to a superseded question.
    #
    # `my $h = "hello"; $h + 1` is the case: Add takes join(Str, Int) = Str and
    # is stamped Str, which is not merely imprecise but WRONG -- perl returns 1,
    # a number. With the operand converted the join is over Num and Int, and the
    # cap in _derived_type makes it Num.
    #
    # UNCONDITIONALLY, not only-fill-Unknown. Every other pass in this file
    # fills gaps and must not overrule a better answer; this one is REPAIRING a
    # stamp it invalidated itself, so declining to overwrite would leave the
    # wrong value in place.
    my %touched;    # graph name => 1, for graphs whose stamps this pass moved
    for my $gname ( sort keys %restamp ) {
        for my $node ( values $restamp{$gname}->%* ) {
            my $type = _derived_type($node) or next;
            $node->set_stamp( SoN::IR::Stamp->new( type => $type ) );
            $touched{$gname} = 1;
        }
    }

    # AND INVALIDATE THE RECORDS DERIVED FROM THOSE STAMPS. A re-derived node is
    # not a leaf: `sub f { my $h = "hello"; return $h + 1 }` now returns Num, so
    # the sub's `return_type` record -- computed from the Add BEFORE this pass
    # corrected it -- says Str, and every callsite reading that record says Str
    # too. The Return yields Num. That is the wire contradicting itself.
    #
    # CLEARED, NOT RECOMPUTED HERE. _rederive_sub_return_types already knows how
    # to derive it and runs right after this pass; it declines only because it
    # fills gaps and will not overrule an answer that is already present. So the
    # honest move is to remove the answer this pass invalidated and let the pass
    # that owns the question answer it again.
    my %stale_callee;    # callee graph name => 1
    for my $cname ( sort keys $classes->%* ) {
        my $subs = $classes->{$cname}{subs} or next;
        for my $sname ( sort keys $subs->%* ) {
            my $rec = $subs->{$sname} or next;
            next unless $touched{ $rec->{graph} // '' };
            $rec->{return_type} = 'Unknown';
            $stale_callee{"${cname}::${sname}"} = 1;
            $stale_callee{$sname}              = 1;
        }
    }

    # AND THE CALLSITES, one level further out, for the same reason. A Call
    # carries its callee's return type, so a Call to a sub whose record just
    # became stale is stale too -- and _stamp_calls_from_callees fills only
    # `Unknown`, so it will not correct a stamp that is merely wrong. Clear
    # those and let it answer again from the record it owns.
    for my $gname ( sort keys $graphs->%* ) {
        my $graph = $graphs->{$gname} or next;
        for my $node ( $graph->nodes->@* ) {
            next unless $node->isa('SoN::IR::Node::Call');
            my $name = $node->can('name') ? ( $node->name // '' ) : '';
            next unless $stale_callee{$name};
            $node->set_stamp( SoN::IR::Stamp->new( type => 'Unknown' ) );
        }
    }

    return $inserted;
}

# _rederive_method_return_types(\%graphs, \%classes) -- recompute each method's
# return type now that its body's reads are typed.
#
# The first derivation runs during class extraction, before the field reads in
# the body have a type. Re-asking the same question of the same function against
# the now-stamped graph is what carries a field's type out through the method
# that returns it. Only ever narrows: an entry that is already determined is
# left alone, so this cannot widen a type the walk got right.
sub _rederive_method_return_types {
    my ( $graphs, $classes ) = @_;

    for my $cname ( sort keys $classes->%* ) {
        my $rts = $classes->{$cname}{method_return_types} or next;
        for my $mname ( sort keys $rts->%* ) {
            next unless ( $rts->{$mname} // 'Unknown' ) eq 'Unknown';
            my $g = $graphs->{"${cname}::${mname}"} or next;
            $rts->{$mname} = _graph_return_type($g);
        }
    }
    return;
}

# _rederive_sub_return_types(\%graphs, \%classes) -- recompute each sub's return
# type now that its body is typed.
#
# The sibling of _rederive_method_return_types, and needed for the same reason:
# `_record_sub` computes `return_type` during the CV walk, BEFORE any of the
# deferred-stamp passes run. A sub whose body only became typeable by BACKWARD
# inference -- `sub add1 { my ($x) = @_; return $x + 1 }`, where `+` types $x
# from its use -- reports Unknown at record time and would keep it.
#
# Re-asking the same question of the same function against the now-stamped graph
# is what carries a parameter's inferred type out through the sub's signature,
# and from there to every callsite via _stamp_calls_from_callees.
#
# Only ever narrows: an entry already determined is left alone, so this cannot
# widen a type the walk got right.
sub _rederive_sub_return_types {
    my ( $graphs, $classes ) = @_;

    for my $cname ( sort keys $classes->%* ) {
        my $subs = $classes->{$cname}{subs} or next;
        for my $sname ( sort keys $subs->%* ) {
            my $rec = $subs->{$sname} or next;
            next unless ( $rec->{return_type} // 'Unknown' ) eq 'Unknown';
            my $g = $graphs->{ $rec->{graph} // '' } or next;
            $rec->{return_type} = _graph_return_type($g);
        }
    }
    return;
}

# _stamp_calls_from_callees(\%graphs, \%classes) -- give each statically-resolved
# Call the return type its callee already declared.
#
# WHAT WAS WRONG. `return_type` is computed by _graph_return_type and written
# onto the sub record (and method_return_types for methods) -- and nothing read
# it back. The callsite went to the wire stamped `Unknown` while the answer sat
# in the same JSON document on a different record. Measured over chalk's 231
# corpus cases: 60 of 233 wire Unknowns were Calls, and every one of them
# resolved statically (dispatch_kind direct/method/builtin, name known). None
# were runtime-polymorphic.
#
# ONLY PROPAGATES, NEVER INVENTS. A callee whose own return is undetermined
# reports `Unknown`, and the callsite stays `Unknown` -- which is the honest
# answer, not a failure. Builtins are left alone: their result type is a
# property of the builtin, not of a callee graph, and `shift`'s element type is
# the Array[Scalar] wall, still a GAP. Anything not resolved here keeps the
# stamp it was constructed with.
sub _stamp_calls_from_callees {
    my ( $graphs, $classes ) = @_;

    for my $gname ( sort keys $graphs->%* ) {
        my $graph = $graphs->{$gname} or next;
        for my $node ( $graph->nodes->@* ) {
            next unless $node->isa('SoN::IR::Node::Call');
            # Already typed by the walk (a constructor knows it returns its
            # class): a caller that KNOWS still wins, as at the factory default.
            next unless ( $node->stamp ? $node->stamp->type : '' ) eq 'Unknown';

            my $type = _callee_return_type( $node, $classes );
            next unless defined $type && $type ne 'Unknown';

            $node->set_stamp( SoN::IR::Stamp->new( type => $type ) );
        }
    }
    return;
}


# _stamp_literal_subscripts(\%graphs) -- give a subscript of a LITERAL aggregate
# the type of the elements it could select.
#
# WHAT WAS WRONG. An anonymous aggregate's elements are its own input nodes, and
# each already carries a stamp. `$a[1]` where `@a = (1,2,3)` is Int, determined
# entirely by data the producer is holding at the time it builds the Subscript.
# It went to the wire Unknown. Measured over chalk's 231 corpus cases, 27 of 233
# wire Unknowns were subscripts of an aggregate whose operands were both typed.
#
# THREE THINGS MAKE THE OBVIOUS VERSION UNSOUND, and each was reachable in the
# corpus. All three are why this reads more than just the element list:
#
# 1. THE AGGREGATE MUST NOT HAVE BEEN WRITTEN THROUGH. `my @a=(1,2,3); $a[0]="s";
#    say($a[0])` builds the read with the STORE as its memory input, not
#    MemStart. The literal no longer describes the array, and answering Int
#    there is a miscompile -- the value is Str. So this only speaks when memory
#    is still at MemStart (or absent): the aggregate is provably unwritten.
#
# 2. THE ELEMENT TYPES ARE JOINED, NOT INDEXED. Answering with element $i's
#    exact type is more precise and it is WRONG here for the same reason as (1),
#    only harder to see: a later store the walk has not linked would silently
#    invalidate a per-slot claim, while the join over all elements stays true
#    for whichever slot is read. Stamp::join is exactly the safe-supertype
#    operation, so `(1,"x")` reads Str rather than sampling Int from slot 0.
#
# 3. A READ THAT IS NOT THERE YIELDS undef, NOT AN ELEMENT. `(1,2)[5]` is not
#    Int, and neither is `{a=>1}{z}`. This is ONE rule over both container
#    kinds, and having written it for array indices only was a miscompile:
#    hashes had no membership test at all, so `$h{z}` took the value join and
#    printed 0 where perl prints an empty line (chalk's behavioural gate,
#    references.md R10). A provably-absent read is stamped Undef -- a real
#    lattice member, and the true answer. A COMPUTED index or key cannot be
#    decided either way and stays Unknown.
#
# HASH VALUES ONLY. A hash literal interleaves keys and values in its inputs, so
# the values sit at ODD offsets. Joining the keys in too would make `{a=>1}`
# read Str and quietly mistype every integer-valued hash.
sub _stamp_literal_subscripts {
    my ($graphs) = @_;

    for my $gname ( sort keys $graphs->%* ) {
        my $graph = $graphs->{$gname} or next;
        for my $node ( $graph->nodes->@* ) {
            next unless $node->isa('SoN::IR::Node::Subscript');
            next unless ( $node->stamp ? $node->stamp->type : '' ) eq 'Unknown';

            my $type = _literal_element_type($node);
            next unless defined $type;

            $node->set_stamp( SoN::IR::Stamp->new( type => $type ) );
        }
    }
    return;
}

# _literal_element_type($subscript) -- the type this subscript's read could
# yield, or undef when that is not decidable from the literal alone.
#
# MEMBERSHIP IS THE SAME QUESTION FOR BOTH CONTAINER KINDS, and missing that
# for hashes was a MISCOMPILE. The first version bounds-checked array indices
# and read a hash by joining its values with no membership test at all, so
# `my %h=(a=>1,b=>2); say($h{z})` stamped Int and printed 0 where perl prints
# an empty line (caught by chalk's behavioural gate, references.md R10).
#
# A MISSING KEY AND AN OUT-OF-RANGE INDEX ARE ONE FACT: the read yields undef,
# so no element type describes it. The value join was not wrong in R10 -- Int
# really is the join of 1 and 2 -- it simply did not apply, because the key was
# not there. Both are answered UNDEF rather than refused: undef is what the read
# yields, it is a real lattice member, and it is knowable statically here. That
# keeps a fact rather than discarding it, and join(Undef, Int) widens correctly
# to Scalar if the read later merges with a defined arm.
sub _literal_element_type {
    my ($node) = @_;
    my $inputs = $node->inputs // [];
    my ( $agg, $index, $mem ) = $inputs->@[ 0, 1, 2 ];
    return undef unless defined $agg && defined $index;

    # Rule 1: an aggregate that has been stored through is no longer described
    # by its literal. Only an unwritten one (memory still at MemStart, or no
    # memory input at all) may be read this way.
    return undef if defined $mem && !$mem->isa('SoN::IR::Node::MemStart');

    return undef unless $index->isa('SoN::IR::Node::Constant');

    my $is_array = $agg->isa('SoN::IR::Node::ArrayRef');
    my $is_hash  = $agg->isa('SoN::IR::Node::HashRef');
    return undef unless $is_array || $is_hash;

    my @elems = ( $agg->inputs // [] )->@*;
    my @values;

    if ($is_array) {
        my $i = $index->value;
        # Only a plain non-negative integer literal is decidable: a negative
        # index counts from the end, and a non-integer is not an index at all.
        return undef unless defined $i && $i =~ /^[0-9]+$/;
        # Rule 3: past the end yields undef, and that is knowable.
        return 'Undef' if $i > $#elems;
        @values = @elems;
    }
    else {
        # Hash: keys sit at EVEN offsets and values at odd ones.
        #
        # The key must be a literal AND present. A computed key cannot be
        # decided here at all -- not the absent case, so it refuses rather than
        # answering Undef.
        my $want = $index->value;
        return undef unless defined $want;

        my $found = 0;
        my $decidable = 1;
        for my $k ( 0 .. $#elems ) {
            next if $k % 2;
            my $key = $elems[$k];
            # A non-literal key means the key set is not known, so absence
            # cannot be concluded from not matching it.
            unless ( $key && $key->isa('SoN::IR::Node::Constant') ) {
                $decidable = 0;
                last;
            }
            my $kv = $key->value;
            $found = 1 if defined $kv && $kv eq $want;
        }
        return undef unless $decidable;
        return 'Undef' unless $found;

        @values = @elems[ grep { $_ % 2 } 0 .. $#elems ];
    }
    return undef unless @values;

    # Rule 2: join, do not sample.
    my $joined;
    for my $v (@values) {
        my $st = $v ? $v->stamp : undef;
        return undef unless $st;
        $joined = defined $joined ? SoN::IR::Stamp::join( $joined, $st ) : $st;
    }
    return $joined ? $joined->type : undef;
}


# _is_merge_node($node) -- does this node yield one of its inputs unchanged?
#
# The set is deliberately CLOSED and small. A node belongs here only if it
# selects among its operands rather than computing from them: adding one that
# computes (Add, Concat) would stamp a result with an operand's type and be
# wrong. TernaryExpr is absent because its first input is the CONDITION, not a
# candidate value -- joining that in would drag Boolean into every select.
sub _is_merge_node {
    my ($node) = @_;
    return 1 if $node->isa('SoN::IR::Node::Phi');
    return 1 if $node->isa('SoN::IR::Node::And');
    return 1 if $node->isa('SoN::IR::Node::Or');
    return 1 if $node->isa('SoN::IR::Node::DefinedOr');
    return 0;
}

# _stamp_merges(\%graphs) -- stamp every node that YIELDS ONE OF ITS ARMS with
# the join of those arms.
#
# ONE RULE, FOUR NODE KINDS. A Phi yields whichever arm's edge was taken. `&&`
# and `||` yield one operand or the other; so does `//`. None of them computes a
# new value, so in every case the result type is the join of the candidates --
# the same question, and SoN::IR::Stamp::join is the answer to all of it.
# Treating them separately would be four spellings of one rule.
#
# WHAT WAS WRONG. The join was already being applied at TWO construction sites
# -- _patch_loop_phi for a loop-carried slot, and the guarded-loop merge path --
# but nowhere else, so an ordinary if/else merge reached the wire Unknown even
# with both arms Int constants, and `$a // $b` over two Ints did too. Measured
# over chalk's 231 corpus cases: 19 Phis and 8 logical-ops whose inputs were ALL
# already stamped. This generalises what those two sites do rather than adding a
# new rule.
#
# THE LOGICAL OPS ARE WHY THIS RUNS TO FIXPOINT ACROSS KINDS, not just within
# Phi: a `//` feeding a merge leaves the Phi poisoned until the `//` itself is
# typed. Measured -- the corpus's `my $x = $a // 0; if (...) { $x = 1 }` case had
# a correctly-poisoned Phi whose real root was an Unknown DefinedOr.
#
# TO FIXPOINT, because a Phi may feed another Phi -- a merge inside a merge, an
# elsif chain, a merge whose arm is a loop-carried value. One pass stamps the
# innermost, the next stamps what reads it. Iterating until nothing changes is
# what carries a type up a nested chain; a single pass leaves the outer merges
# Unknown, which is the shape the corpus's nested-if cases have.
#
# AN UNKNOWN INPUT POISONS THE RESULT, and must: join(Int, Unknown) is Unknown.
# Taking the typed arm instead would assert a type the other path cannot
# support. That is the same rule _patch_loop_phi's _is_narrowed guard enforces,
# and it is why this only speaks when EVERY input is narrowed.
#
# The bound is a backstop, not a schedule: the lattice has finite height and a
# join only ever moves up it, so this converges in a couple of passes. A run
# that hits the bound means the lattice or an input mutated under it, and
# stopping is better than spinning.
sub _stamp_merges {
    my ($graphs) = @_;

    my $ROUNDS = 10;
    for my $round ( 1 .. $ROUNDS ) {
        my $changed = 0;
        for my $gname ( sort keys $graphs->%* ) {
            my $graph = $graphs->{$gname} or next;
            for my $node ( $graph->nodes->@* ) {
                next unless _is_merge_node($node);
                next unless ( $node->stamp ? $node->stamp->type : '' ) eq 'Unknown';

                my @inputs = ( $node->inputs // [] )->@*;
                next unless @inputs;

                my $joined;
                my $ok = 1;
                for my $in (@inputs) {
                    my $st = $in ? $in->stamp : undef;
                    # Every input must SAY something. An Unknown arm makes the
                    # join Unknown, so there is nothing to record and nothing
                    # gained by writing it back.
                    unless ( defined $st && $st->type ne 'Unknown' ) {
                        $ok = 0;
                        last;
                    }
                    $joined = defined $joined
                        ? SoN::IR::Stamp::join( $joined, $st )
                        : $st;
                }
                next unless $ok && $joined && $joined->type ne 'Unknown';

                $node->set_stamp( SoN::IR::Stamp->new( type => $joined->type ) );
                $changed++;
            }
        }
        last unless $changed;
    }
    return;
}


# _stamp_derived(\%graphs) -- stamps a node can compute from what it already
# holds: its own attributes, or the kind of its single operand.
#
# WHAT WAS WRONG. Three separate one-line answers the producer had in hand:
#
#   \@a          a reference to an array is an ArrayRef -- the operand node is
#                right there as the input, and its kind IS the answer
#   qr/foo/      the producer wrote const_type => 'regex' into this node's OWN
#                attributes and then stamped the node Unknown
#   $n * 2       arithmetic over two stamped operands is decidable
#   $a[0] = 42   an assignment yields the value it STORED, so it takes the RHS
#                type -- the reason `$x = $y = 5` works
#
# ONLY PROPAGATES. An untyped operand leaves the result untyped: arithmetic
# widens what it is given and invents nothing. `f() * 2` where f is untyped
# stays Unknown, and has a test saying so.
sub _stamp_derived {
    my ($graphs) = @_;

    for my $gname ( sort keys $graphs->%* ) {
        my $graph = $graphs->{$gname} or next;
        for my $node ( $graph->nodes->@* ) {
            next unless $node->isa('SoN::IR::Value');
            next unless ( $node->stamp ? $node->stamp->type : '' ) eq 'Unknown';

            my $type = _derived_type($node);
            next unless defined $type;

            $node->set_stamp( SoN::IR::Stamp->new( type => $type ) );
        }
    }
    return;
}

# _derived_type($node) -- the type this node can work out for itself, or undef.
sub _derived_type {
    my ($node) = @_;
    my $op     = $node->operation;
    my @inputs = ( $node->inputs // [] )->@*;

    # A compiled regex says so in its own const_type.
    if ( $op eq 'Constant' ) {
        my $ct = $node->can('const_type') ? $node->const_type : undef;
        return 'Regex' if defined $ct && $ct eq 'regex';
        return undef;
    }

    # \OPERAND: the reference kind follows the operand's kind.
    if ( $op eq 'Ref' ) {
        my $inner = $inputs[0] or return undef;
        my $it = $inner->stamp ? $inner->stamp->type : '';
        return 'ArrayRef'  if $it eq 'ArrayRef'  || $it eq 'Array';
        return 'HashRef'   if $it eq 'HashRef'   || $it eq 'Hash';
        return 'CodeRef'   if $it eq 'CodeRef'   || $it eq 'Code';
        # A reference to a plain scalar is a ScalarRef; anything still Unknown
        # stays Unknown rather than being called a bare Ref, which would claim
        # more than is known about what it points at.
        return 'ScalarRef' if $it ne '' && $it ne 'Unknown';
        return undef;
    }

    # AN ASSIGNMENT YIELDS THE VALUE IT STORED, which is why `$x = $y = 5`
    # works -- SoN::IR::Value's own comment says so ("an assignment's result is
    # the stored value"). So the stamp is the RHS's, NOT the target's: storing a
    # Str into a slot that held an Int yields Str, and taking the lvalue's type
    # would be wrong in exactly that case.
    #
    # inputs are [lvalue, rvalue]. A single-input Assign is a declaration form
    # with no separate stored value, so there is nothing to take.
    if ( $op eq 'Assign' || $op eq 'CompoundAssign' ) {
        return undef unless @inputs == 2;
        my $rhs = $inputs[1] or return undef;
        my $st  = $rhs->stamp or return undef;
        return undef if $st->type eq 'Unknown';
        return $st->type;
    }

    # WHATEVER THE SIGNATURES SAY. TypeLibrary owns the whole rule -- a fixed
    # result outright, a join capped at what the operator can yield -- so this
    # only has to hand it the key and the operand types.
    #
    # ARITY-AGNOSTIC, because result_for is. This arm previously required
    # exactly two operands, which silently made every UNARY join entry DEAD:
    # `Negate` is in the join set and never reached this code, so it agreed
    # with FromOptree's %RESULT_STAMP on paper while being unable to execute.
    #
    # A BUILTIN CALL IS KEYED BY ITS NAME, not by the node ~180 optree ops
    # share. This is where a builtin whose operands were narrowed after the
    # walk gets the answer the walk could not give -- `abs $n` becomes Int once
    # $n does, the same way `-$n` does.
    my $key = $op;
    if ( $op eq 'Call' && ( $node->dispatch_kind // '' ) eq 'builtin' ) {
        my $name = $node->name // return undef;
        $key = [ 'Call', $name ];
    }

    # ONLY WHAT THE OPERANDS DECIDE. This pass fills Unknowns from operand
    # types; a FIXED result is not a fact about operands, and answering one
    # here would stamp inside the fixpoint what a later floor pass deliberately
    # stamps after it (see _floor_element_removals for what that broke).
    #
    # ASKED, NOT REIMPLEMENTED. `result_is_join` used to be public for exactly
    # this test -- a boolean about the CALLER'S algorithm, which its own header
    # calls the wrong shape. result_for already draws the line: an op with a
    # fixed result answers with NO operands, and one whose result is a join
    # cannot. So the question is asked in the vocabulary of answers.
    return undef if defined B::SoN::TypeLibrary::result_for($key);

    my @types = map { $_ && $_->stamp ? $_->stamp->type : undef } @inputs;
    return B::SoN::TypeLibrary::result_for( $key, @types );
}


# The operator signatures live in B::SoN::TypeLibrary -- what each op requires
# of its operands, what it yields, and whether that result varies with the
# operands. This file previously carried a partial copy of the input half as
# `%OPERAND_REQUIRES`, and NodeFactory carries another of the fixed-result half
# as `%SELF_TYPED_OPS`. See that module's header for why the copy exists and
# what obliges it to track chalk's.

# _count_unknown_stamps(\%graphs) -- how many Value nodes are still untyped.
#
# The fixpoint's progress measure. Every pass only ever REPLACES an `Unknown`
# with a narrower type, so this count falls monotonically and reaching a
# steady state means no pass can make further progress.
sub _count_unknown_stamps {
    my ($graphs) = @_;
    my $n = 0;
    for my $gname ( keys $graphs->%* ) {
        my $graph = $graphs->{$gname} or next;
        for my $node ( $graph->nodes->@* ) {
            next unless $node->isa('SoN::IR::Value');
            $n++ if ( $node->stamp ? $node->stamp->type : 'Unknown' ) eq 'Unknown';
        }
    }
    return $n;
}

# _infer_backward(\%graphs) -- type a value from what its USES require.
#
# WHAT WAS MISSING. Every other pass runs FORWARD: operands to result, refusing
# when an operand is Unknown. That leaves a value with NO forward seed untyped
# forever -- a sub parameter, a `:param` field. Nothing flows in, so nothing
# forward can decide it.
#
# But a use site CONSTRAINS its operands. `$x + 1` puts `$x` in numeric context,
# so `$x` is Num -- from the BODY ALONE, with no callsite. That is the
# information the producer was holding and never asked for.
#
# THE MEET IS THE OPERATION. A value carries what its declaration gives it (a
# scalar slot is `Scalar`) and its uses impose a requirement; the type is
# meet(declared, required). meet(Scalar, Num) = Num. This is the first caller of
# Stamp::meet in the codebase -- forward passes join, this one meets.
#
# `Num` AND NOT `Int`, even though the corpus calls `add1(5)`. `add1(0.5)` is
# legal and nothing in the body excludes it, so Int would be unsound. Narrowing
# to Int needs the CALLSITE, which is a separate pass over a different edge.
#
# ONLY VALUES WITH NO FORWARD ANSWER. A node the forward passes already typed
# keeps that type -- this fills gaps, it does not overrule. And a value no
# constraining op consumes stays Unknown: the pass reads requirements, it does
# not invent them.
#
# TO FIXPOINT, because typing a parameter lets the forward passes type the
# expression above it, whose result may then constrain something else. The bound
# is a backstop: the lattice has finite height and meet only moves down it.
sub _infer_backward {
    my ($graphs) = @_;

    my $ROUNDS = 10;
    for my $round ( 1 .. $ROUNDS ) {
        my $changed = 0;
        for my $gname ( sort keys $graphs->%* ) {
            my $graph = $graphs->{$gname} or next;

            # Collect, per value node, the requirements its consumers impose.
            my %required;    # node id => Stamp
            for my $node ( $graph->nodes->@* ) {
                my $op_name = B::SoN::TypeLibrary::type_key($node);
                my @inputs  = ( $node->inputs // [] )->@*;
                for my $i ( 0 .. $#inputs ) {
                    my $want = B::SoN::TypeLibrary::operand_type( $op_name, $i )
                        // next;
                    my $operand = $inputs[$i] or next;
                    next unless $operand->isa('SoN::IR::Value');

                    # A COERCE IS TRANSPARENT TO A REQUIREMENT. The producer
                    # already inserts Coerce(X -> Str) for a string context, so
                    # `$s . "!"` has the Concat consuming a Coerce, not $s --
                    # and the requirement would stop at a node that is already
                    # Str. Descend to the value UNDERNEATH: it is the one with
                    # no forward seed, and the one the requirement is about.
                    # Measured: without this, numeric contexts type their
                    # parameter (Add takes its operand directly) and string
                    # contexts do not.
                    $operand = _thread_through_coerce($operand);
                    next unless $operand && $operand->isa('SoN::IR::Value');

                    my $w = SoN::IR::Stamp->new( type => $want );
                    my $have = $required{ $operand->id };
                    # Two uses of one value both constrain it: meet the
                    # requirements, so the value must satisfy both.
                    $required{ $operand->id }
                        = $have ? SoN::IR::Stamp::meet( $have, $w ) : $w;
                }
            }

            for my $node ( $graph->nodes->@* ) {
                next unless $node->isa('SoN::IR::Value');
                next unless ( $node->stamp ? $node->stamp->type : '' ) eq 'Unknown';
                next unless _is_backward_inferable($node);
                my $want = $required{ $node->id } or next;
                next if $want->type eq 'Unknown';

                # The declared type of a scalar-slot read is `Scalar`; meeting it
                # with the requirement is what narrows. A node whose declaration
                # says nothing takes the requirement directly.
                my $declared = _declared_slot_type($node);
                my $result   = $declared
                    ? SoN::IR::Stamp::meet( $declared, $want )
                    : $want;

                # None means the declaration and the use cannot both hold. That
                # is a COERCION SITE, not a type here -- leave it for the pass
                # that materialises coercions rather than stamping a bottom.
                next if $result->type eq 'None' || $result->type eq 'Unknown';

                $node->set_stamp( SoN::IR::Stamp->new( type => $result->type ) );
                $changed++;
            }
        }
        last unless $changed;
    }
    return;
}

# _is_backward_inferable($node) -- may a USE SITE decide this node's type?
#
# Only where the type is GENUINELY OPEN: a variable or field read, which is a
# slot whose contents nothing else in this graph describes. Everything else has
# an AUTHORITATIVE source elsewhere and must be left for the pass that consults
# it -- a Call's type is its callee's return type, a Subscript's is its
# container's element type, a Phi's is the join of its arms.
#
# THE SET IS CLOSED AND SMALL, and widening it caused a miscompile. Measured on
# chalk's gate (215 -> 199): with no restriction, `$p->left - $p->right` stamped
# both Call nodes Num from Subtract's requirement while the callee methods were
# still Unknown and method_return_types was EMPTY. The wire asserted a return
# type the callee did not have, disagreeing with the vtable ABI, and an i64 was
# reinterpreted as a double -- lli printed 1.48e-323 where perl printed 3.
#
# The rule that generalises: backward inference FILLS A HOLE. If another pass
# owns the answer, a use-site constraint is a weaker second opinion and must not
# preempt it -- the same reason this whole pass runs LAST in the sweep.
sub _is_backward_inferable {
    my ($node) = @_;
    my $op = $node->operation;
    return 1 if $op eq 'PadAccess';
    return 1 if $op eq 'FieldAccess';
    return 1 if $op eq 'Parameter';
    return 0;
}

# _thread_through_coerce($node) -- the value a requirement is really about.
#
# A Coerce is a conversion the producer inserted, not a value with a type of its
# own to constrain. A requirement landing on one belongs to its input. Chases a
# chain (a Coerce over a Coerce) rather than one step, and bounded so a cycle
# cannot spin.
sub _thread_through_coerce {
    my ($node) = @_;
    my $hops = 0;
    while ( $node && $node->operation eq 'Coerce' && $hops++ < 8 ) {
        $node = ( $node->inputs // [] )->[0];
    }
    return $node;
}

# _declared_slot_type($node) -- what the DECLARATION says this read can hold,
# independent of any use. A scalar slot holds a Scalar; that excludes Array,
# Hash, Code and Glob, so it is a real constraint and not a placeholder.
#
# Returns undef when the node kind carries no declaration to speak of, in which
# case the use-site requirement stands alone.
sub _declared_slot_type {
    my ($node) = @_;
    my $op = $node->operation;
    return SoN::IR::Stamp->new( type => 'Scalar' )
        if $op eq 'PadAccess' || $op eq 'FieldAccess';
    return undef;
}

# _callee_return_type($call, \%classes) -- the declared return type of the callee
# this Call names, or undef when it is not a statically-resolved user callee.
#
# Reads the SAME records the wire carries, so the callsite stamp and the callee
# metadata cannot disagree: one source, consulted twice.
sub _callee_return_type {
    my ( $call, $classes ) = @_;
    my $kind = $call->dispatch_kind // '';
    my $name = $call->name          // '';

    # A method call names its class explicitly; the return type rides in the
    # class section's method_return_types, keyed by bare method name.
    if ( $kind eq 'method' ) {
        my $cname = $call->class_name // return undef;
        my $cls   = $classes->{$cname} or return undef;
        return ( $cls->{method_return_types} // {} )->{$name};
    }

    # A direct sub call names the callee fully qualified (main::f). The sub
    # record hangs off its owning class under the BARE name.
    if ( $kind eq 'direct' ) {
        my ( $pkg, $bare )
            = $name =~ /^(.*)::([^:]+)$/ ? ( $1, $2 ) : ( 'main', $name );
        my $cls = $classes->{$pkg} or return undef;
        my $rec = ( $cls->{subs} // {} )->{$bare} or return undef;
        return $rec->{return_type};
    }

    # Builtins are not user callees -- see the note above.
    return undef;
}

# _emit_referenced_classes(\%graphs, \%classes) — walk the emitted graphs for
# method-dispatch Call nodes, collect their class_name, and _extract_class each
# referenced class not yet emitted. _extract_class adds the class's method
# graphs to %graphs, which may reference further classes, so re-scan to a
# fixpoint. The :isa parent of every emitted class is emitted too -- the
# backend requires a class's declared superclass to be present in the same
# graph (and an inherited method resolves through the parent's method graph).
# Emits ONLY referenced classes and their parent chains, never the whole stash.
sub _emit_referenced_classes {
    my ( $graphs, $classes ) = @_;

    no strict 'refs';

    my $filter = $_[2];
    my %scanned;   # graph keys already scanned for class refs
    while (1) {
        # Two roots feed the worklist: classes named by a method Call, and the
        # :isa parent of any class already emitted (the parent may itself carry
        # further parents / referenced classes -- the outer fixpoint closes it).
        my @refs = _referenced_class_names( $graphs, \%scanned );
        push @refs, grep { defined }
            map  { $classes->{$_}{parent} } keys $classes->%*;

        my $added = 0;
        for my $cname (@refs) {
            next if exists $classes->{$cname};

            my $stash = \%{"${cname}::"};
            next unless SoN::ClassAux::is_class($stash);
            $classes->{$cname} =
                _extract_class( $graphs, $cname, $stash );
            # _extract_class records the method-name -> graph-key map but does
            # not translate the method CVs (that is _walk_package's job, which
            # skipped this class because it is outside the package= filter).
            # Translate each referenced method graph now.
            _translate_class_methods( $graphs, $cname, $stash,
                $classes->{$cname}{methods} );
            # ...and its plain SUBS. This path is the ONLY thing that
            # translates CVs for an out-of-filter class (_walk_package skipped
            # it, so _record_sub never ran), and it used to reach them because
            # every non-:reader CV was recorded under {methods}. With a plain
            # sub now classified as a sub, iterating {methods} alone leaves it
            # translated NOWHERE -- measured: MyMod::helper vanished from the
            # graph set while main's Call node still named it. An unresolvable
            # callee, with no GAP and no warning.
            _translate_class_subs( $graphs, $classes, $cname, $stash );
            $added++;
        }
        last unless $added;   # fixpoint: no new class this round
    }
    return;
}

# _translate_class_subs(\%graphs, \%classes, $pkg_name, $stash) -- translate and
# record the plain SUBS of a referenced (out-of-filter) class.
#
# The sibling of _translate_class_methods for the other half of the
# classification. _walk_package handles both for an IN-filter package; a class
# emitted only because it was referenced never passes through that loop, so
# without this its subs have no graph and no record.
#
# _record_sub's user-code guard is satisfied here by an existing class record
# (_extract_class has just populated it), which is what lets a sub from another
# FILE be recorded when that file's class is genuinely part of the program.
sub _translate_class_subs {
    my ( $graphs, $classes, $pkg_name, $stash ) = @_;

    no strict 'refs';

    my $methods = $classes->{$pkg_name}{methods} // {};

    for my $name ( sort keys %$stash ) {
        next if $name =~ /::$/;
        next if $name =~ /^[^a-zA-Z_]/;
        next if exists $methods->{$name};    # already handled as a method

        my $gv = eval { svref_2object( \*{"${pkg_name}::${name}"} ) };
        next unless defined $gv && $gv->isa('B::GV');
        my $cv = $gv->CV;
        next unless $$cv && !$cv->isa('B::SPECIAL');
        my $start = eval { $cv->START };
        next unless defined $start && $$start;

        # Skip imported subs -- their CV belongs to another package.
        my $cv_gv = eval { $cv->GV };
        next unless defined $cv_gv && $$cv_gv;
        my $cv_stash = eval { $cv_gv->STASH->NAME } // '';
        next unless $cv_stash eq $pkg_name || $cv_stash eq '';

        my $full_name = "${pkg_name}::${name}";
        next if exists $graphs->{$full_name};

        try {
            $graphs->{$full_name} =
                SoN::FromOptree->translate( $cv->object_2svref );
            _record_sub( $classes, $pkg_name, $name, $full_name, $cv,
                         $graphs->{$full_name} );
        }
        catch ($e) {
            if ( $e =~ /^GAP:/ ) {
                warn "B::SoN: skipped $full_name: $e";
            }
            else {
                warn "B::SoN: INTERNAL ERROR translating $full_name (masked as "
                   . "a silent skip -- fix or convert to a clean GAP): $e";
            }
        }
    }
    return;
}

# _translate_class_methods(\%graphs, $pkg_name, $stash, $methods) — translate
# each of a referenced class's method CVs into $graphs, keyed by the same
# fully-qualified key _extract_class recorded in $methods. Mirrors the CV
# translation _walk_package performs for in-filter packages; a class emitted
# only because it is referenced never passes through that loop.
sub _translate_class_methods {
    my ( $graphs, $pkg_name, $stash, $methods ) = @_;

    no strict 'refs';

    for my $name ( sort keys $methods->%* ) {
        my $full_name = $methods->{$name};
        next if exists $graphs->{$full_name};

        my $gv = eval { svref_2object( \*{"${pkg_name}::${name}"} ) };
        next unless defined $gv && $gv->isa('B::GV');
        my $cv = $gv->CV;
        next unless $$cv;
        next if $cv->isa('B::SPECIAL');
        my $start = eval { $cv->START };
        next unless defined $start && $$start;

        try {
            $graphs->{$full_name} =
                SoN::FromOptree->translate( $cv->object_2svref );
        }
        catch ($e) {
            # A deliberate GAP refusal is the translator speaking; surface it
            # so the method silently missing is a loud honest refusal, not
            # discovery noise (same policy as _walk_package).
            #
            # A NON-GAP DIE IS NOT A REFUSAL -- it is a bug in us, and the
            # method vanishes from the wire either way. Filtering the warn on
            # /^GAP:/ reported the honest half and swallowed the dishonest
            # half, which is the wrong way round: an unexpected failure is the
            # one nobody is looking for. Both are reported; the message says
            # which kind it is.
            warn $e =~ /^GAP:/
                ? "B::SoN: skipped $full_name: $e"
                : "B::SoN: INTERNAL ERROR translating $full_name (not a GAP "
                . "refusal -- the method is missing from the wire): $e";
        }
    }
    return;
}

# _referenced_class_names(\%graphs, \%scanned) — the class_name of every
# method-dispatch Call in graphs not yet scanned. Marks each scanned so a
# fixpoint loop does not re-walk it.
# _is_producer_graph($key) -- is this graph B::SoN's own code, or a module it
# dragged in, rather than the file under compilation?
#
# Keyed on the graph name's package prefix. These are the namespaces the
# producer itself occupies at CHECK time; a user file compiling into one of
# them is not a case worth supporting and would be indistinguishable anyway.
sub _is_producer_graph {
    my ($key) = @_;
    return $key =~ /^(?:B|SoN|JSON::PP|Carp|Exporter|DynaLoader|Config
                       |Scalar::Util|List::Util|overload|overloading
                       |strict|warnings|utf8|bytes|feature|Test)\b/x ? 1 : 0;
}

sub _referenced_class_names {
    my ( $graphs, $scanned ) = @_;
    my %names;
    for my $key ( keys $graphs->%* ) {
        next if $scanned->{$key}++;

        # A PRODUCER-INTERNAL GRAPH REFERENCES NOTHING THE USER ASKED FOR.
        # %graphs holds every CV reachable at CHECK time, which includes
        # B::SoN's own subs and everything they loaded. Scanning those for
        # method calls pulls the producer's OWN classes onto the wire --
        # measured, `SoN::IR::Stamp` leaked as soon as a stamping pass
        # constructed one, because `SoN::IR::Stamp->new(...)` inside
        # B::SoN::_resolve_deferred_stamps is a method Call carrying that
        # class_name.
        #
        # The package FILTER is not the right guard here: this pass exists
        # precisely to emit a user class that sits OUTSIDE the filter when an
        # emitted graph references it (t/from-optree-referenced-class-mop.t
        # asserts exactly that under package=main). The question is not "is
        # this class in the filter" but "is this graph user code".
        next if _is_producer_graph($key);

        for my $node ( $graphs->{$key}->nodes->@* ) {
            next unless $node->operation eq 'Call';
            next unless ( $node->dispatch_kind // '' ) eq 'method';
            my $cname = $node->class_name // next;
            $names{$cname} = 1;
        }
    }
    return keys %names;
}

# _walk_package(\%graphs, $pkg_name, \%stash) — recursively walk a stash,
# translating every CODE value found into a SoN::IR::Graph.
#
# $pkg_name is the canonical Perl package name (e.g. 'Baz', not 'main::Baz').
# Perl stashes always report their own NAME in canonical form, so we derive
# it from the stash itself rather than constructing it from the parent path.
sub _walk_package {
    my ( $graphs, $classes, $pkg_name, $stash, $filter ) = @_;

    no strict 'refs';

    # If filter is active and this package is not in the filter, skip CVs
    my $emit_cvs = _emit_package($filter, $pkg_name);

    # Record feature-class structure (declarative; methods land in $graphs).
    #
    # SCOPED THE SAME WAY THE SUB WALK IS. The producer declares its own
    # feature-classes (SoN::IR::Node and friends), and extracting one emits a
    # __DEFAULT_n graph per defaulted field -- 11 of them survived on a
    # four-line probe after the sub walk was gated, because they arrive here
    # rather than through that loop. A class is ours to emit when its own code
    # came from the file under compilation.
    if ( $emit_cvs && SoN::ClassAux::is_class($stash)
             && _stash_is_user_code($stash) ) {
        $classes->{$pkg_name} = _extract_class( $graphs, $pkg_name, $stash );
    }

    for my $name ( sort keys %$stash ) {
        # Skip sub-package slots (end with ::) and non-identifier names
        next if $name =~ /::$/;
        next if $name =~ /^[^a-zA-Z_]/;
        next unless $emit_cvs;

        # Obtain the GV for this slot via the canonical package name
        my $gv = eval { svref_2object( \*{"${pkg_name}::${name}"} ) };
        next unless defined $gv && $gv->isa('B::GV');

        my $cv = $gv->CV;
        next unless $$cv;                        # no CV attached to this GV
        next if $cv->isa('B::SPECIAL');

        # Skip imported subs — their CV's stash does not match this package
        my $cv_gv = eval { $cv->GV };
        next unless defined $cv_gv && $$cv_gv;

        my $cv_stash = eval { $cv_gv->STASH->NAME } // '';
        next unless $cv_stash eq $pkg_name || $cv_stash eq '';

        # Skip XS / autoloaded subs that have no optree (START is null)
        my $start = eval { $cv->START };
        next unless defined $start && $$start;

        # ONLY WHAT WE WERE ASKED TO COMPILE. perl has loaded the producer
        # into the same interpreter that is compiling the user's file, so
        # without this the package walk translates B::SoN's and SoN::IR's own
        # subs too -- measured on a four-line probe: 420 graphs / 3150 nodes, of
        # which 294 were ours. A consumer then cannot tell its graphs from the
        # user's, which is not merely untidy: it makes "does a user program
        # still carry Unknown stamps" unmeasurable, and that number scopes
        # chalk's T2 pass.
        #
        # SCOPED BY $0, NOT BY PACKAGE NAME. _cv_is_user_code asks which FILE
        # the CV came from. That keeps a user sub in a user-declared package
        # (`package Foo; sub helper {...}`), and it is what makes self-hosting
        # work: when Chalk compiles B::SoN, $0 IS B::SoN and these graphs are
        # then correctly INCLUDED. Excluding the producer by name would look
        # equivalent here and silently break that.
        next unless _cv_is_user_code($cv);

        my $full_name = "${pkg_name}::${name}";
        next if exists $graphs->{$full_name};

        try {
            my $graph = SoN::FromOptree->translate( $cv->object_2svref );
            $graphs->{$full_name} = $graph;
            # Record the sub's METADATA while the CV is still in hand. See
            # _record_sub: these are facts this walk knows and the emitted
            # graph either loses or spells inconsistently.
            _record_sub( $classes, $pkg_name, $name, $full_name, $cv,
                         $graphs->{$full_name} );
        }
        catch ($e) {
            # Skip subs that fail to translate (builtins, XS, compiler
            # internals, etc.) — not all optrees are representable in SoN yet.
            # A deliberate GAP refusal ("GAP: ...") is the translator speaking:
            # swallowing it turns a loud honest refusal into a sub silently
            # missing from the JSON, so re-emit it. A NON-GAP exception is an
            # INTERNAL producer bug (e.g. a Node built with an undef input, an
            # undef-deref) -- swallowing THAT is worse: it masks a real defect as
            # a silent sub-drop, indistinguishable from an intentional skip. Warn
            # on it LOUDLY with a distinct prefix so it is not lost. Discovery
            # noise (a builtin/XS optree with no chance of lowering) also lands
            # here, so this is a warn, not a die.
            if ($e =~ /^GAP:/) {
                warn "B::SoN: skipped $full_name: $e";
            }
            else {
                warn "B::SoN: INTERNAL ERROR translating $full_name (masked as "
                   . "a silent skip -- fix or convert to a clean GAP): $e";
            }
        }
    }

    # Recurse into sub-packages, avoiding infinite loops back to main.
    # Use the sub-stash's own B::HV NAME (canonical short form, e.g. 'Baz')
    # for the recursive call so that cv_stash comparisons work correctly at
    # any nesting depth.
    for my $name ( sort keys %$stash ) {
        next unless $name =~ /^([A-Za-z_]\w*)::$/;
        my $sub_pkg_short = $1;
        next if $sub_pkg_short eq 'main';

        my $sub_stash      = \%{"${pkg_name}::${sub_pkg_short}::"};
        # B::HV->NAME returns the canonical package name (e.g. 'Baz' not
        # 'main::Baz'), matching what cv->GV->STASH->NAME returns.
        my $canonical_name = eval {
            B::svref_2object($sub_stash)->NAME
        } // "${pkg_name}::${sub_pkg_short}";

        _walk_package( $graphs, $classes, $canonical_name, $sub_stash, $filter );
    }
}

# _stash_is_user_code($stash) -- is this PACKAGE's code ours to emit?
#
# The package-level counterpart of _cv_is_user_code, and it asks the same
# question of the same authority: did any CV in this stash come from $0. A
# feature-class the producer declares (SoN::IR::Node, ...) answers no; the
# user's `class Counter` answers yes, and so does B::SoN itself when Chalk is
# compiling B::SoN -- which is what keeps self-hosting working.
#
# ANY rather than ALL: a class whose methods are all inherited still belongs to
# the file that declared it, and a stash with no CVs at all (fields only) is
# decided by its field-default CVs, which is what this is protecting.
sub _stash_is_user_code {
    my ($stash) = @_;
    no strict 'refs';
    for my $name ( keys %$stash ) {
        next if $name =~ /::$/ || $name =~ /^[^a-zA-Z_]/;
        my $gv = eval { $stash->{$name} };
        next unless defined $gv;
        my $b = eval { svref_2object( \$gv ) };
        next unless $b && $b->isa('B::GV');
        my $cv = eval { $b->CV };
        next unless $cv && $$cv && !$cv->isa('B::SPECIAL');
        return 1 if _cv_is_user_code($cv);
    }
    return 0;
}

# _cv_is_user_code($cv) -- was this sub compiled from the file under
# compilation, rather than from a module perl loaded along the way?
#
# `$0` is the script being compiled. A CV's ->FILE is where its body came from,
# so the two match for the user's own subs (in any package they declare) and
# differ for strict/warnings/Carp/JSON::PP and friends. That is the honest
# boundary for "whose code is this": it does not care whether the package used
# `class`, only whether we are compiling it.
#
# A CV with no ->FILE (XS, a builtin) is not user code.
sub _cv_is_user_code {
    my ($cv) = @_;
    my $file = eval { $cv->FILE };
    return 0 unless defined $file && length $file;
    return $file eq $0;
}

# _empty_class($pkg_name) -- the default class record shape.
#
# ONE definition of the five keys. _extract_class overwrites parent/fields for a
# real feature-class; _record_sub vivifies this for a package that has subs but
# no class declaration (`main`). Two literal copies would have to stay in sync,
# and a sixth key would reach only one of them.
sub _empty_class {
    my ($pkg_name) = @_;
    return {
        name    => $pkg_name,
        parent  => undef,
        fields  => [],
        methods => {},
        adjusts => [],
    };
}

# _graph_return_type($graph) -> a repr name, or 'Unknown'
#
# The declared return type of a sub: the representation of its Return's value.
#
# `Unknown` is the honest answer when the value has no stamp -- a Return whose
# value is a recursive call has nothing to read at producer time. It is a real
# lattice point meaning "inference has not determined this", as opposed to an
# ABSENT field, which is not a type at all and makes every consumer guess.
#
# Multiple Returns join later; this reports the single-Return case and Unknown
# otherwise, leaving the join to the layer that can do it.
sub _graph_return_type {
    my ($graph) = @_;
    return 'Unknown' unless defined $graph;
    my @returns = eval { @{ $graph->returns } };
    return 'Unknown' unless @returns == 1;
    my $value = eval { $returns[0]->inputs->[-1] };
    return 'Unknown' unless defined $value && ref $value;
    # The PRODUCER vocabulary is a Stamp (->stamp->type), not the chalk-side
    #  field. Reading the latter here silently returned undef
    # for every determined type and declared everything Unknown.
    my $stamp = eval { $value->stamp };
    my $type  = $stamp ? eval { $stamp->type } : undef;
    return defined $type ? $type : 'Unknown';
}

# _record_sub($classes, $pkg_name, $name, $full_name, $cv) — record a sub's
# METADATA on the declarative class section.
#
# Every sub belongs to a class: a file-level `sub f` is a sub of class `main`.
# Chalk's MOP seeds an implicit `main` for exactly this reason ("all code
# belongs to a class"), so no special case is needed here or in the loader.
#
# WHY THIS IS RECORDED RATHER THAN DERIVED. The consumer needs to know whether a
# callee touches `@_` (to decide whether to materialise it) and what its arity
# is. Both are known HERE, while walking the CV. Neither survives into the graph
# usefully:
#
#   shift              EntryDef(_)              -- and collides with $_
#   $_[0]              Constant("_") + Subscript
#   my ($a,$b) = @_    NOTHING -- @_ is absent from the graph entirely
#   scalar @_          Constant("_") returned directly
#
# Three spellings for one array, one of them a bare string constant, and one
# shape where it vanishes. A graph scan over that cannot be written reliably,
# and a scan is what this record exists to retire.
# _cv_signature($cv) -> a signature record, always.
#
# EVERY SUB HAS A SIGNATURE. `sub f {}` is exactly `sub f(@_)` -- the implicit
# slurpy -- while `sub f() {}` is arity ZERO and perl ENFORCES it ("Too many
# arguments for subroutine 'main::empty' (got 1; expected 0)"). Those are the
# most permissive and most restrictive declarations respectively, so collapsing
# one into the other inverts the strictest form.
#
# The optree carries the whole thing; this reads it rather than inferring:
#
#   sub two($a,$b)   argcheck aux=[2,0,'']   argelem(0)[$a] argelem(1)[$b]
#   sub ary(@x)      argcheck aux=[0,0,'@']  argelem(0)[@x]
#   sub hsh(%h)      argcheck aux=[0,0,'%']  argelem(0)[%h]
#   sub opt($a,$b=9) argcheck aux=[2,1,'']   argelem + argdefelem
#   sub empty()      argcheck aux=[0,0,'']   (no argelem)
#   sub none         NO argcheck at all
#
# THE THIRD AUX ELEMENT IS LOAD-BEARING. `sub ary(@x)` is [0,0,'@'] -- zero
# mandatory, zero optional, slurpy array. A reader that consults only the first
# two reports it as taking NO arguments, which is the exact inversion of what it
# means.
#
# ABSENT IS THE EMPTY STRING, WHICH IS DEFINED. Measured: `sub two($a,$b)` and
# `sub empty()` both yield '' in that slot, while `sub ary(@x)` yields '@'. So
# `defined` is the wrong test -- it is true for every sub, slurpy or not. The
# discriminator is EMPTINESS: `length`.
#
# Per-parameter sigil comes from argelem's `private` field: 0 scalar, 2 array,
# 4 hash. Typing by sigil is the same rule that fixed EntryDef: `$_` and `@_`
# are different variables sharing one glob name.
sub _cv_signature {
    my ($cv) = @_;

    my ( $argcheck, @argelem );
    my $root = eval { $cv->ROOT };
    if ( defined $root && ref $root && $$root ) {
        my @stack = ($root);
        while ( my $op = shift @stack ) {
            next unless ref $op && $$op;
            my $n = $op->name;
            $argcheck = $op if $n eq 'argcheck' && !defined $argcheck;
            push @argelem, $op if $n eq 'argelem';
            # A nested sub has its own signature; do not read it as ours.
            next if $n eq 'anoncode';
            if ( $op->can('first') && ref( $op->first ) && ${ $op->first } ) {
                my $kid = $op->first;
                while ( ref $kid && $$kid ) {
                    push @stack, $kid;
                    $kid = $kid->sibling;
                }
            }
        }
    }

    # NO argcheck => signature-less => implicitly (@_). One slurpy parameter.
    unless ( defined $argcheck ) {
        return {
            kind      => 'implicit',
            mandatory => 0,
            optional  => 0,
            slurpy    => '@',
            params    => [ { index => 0, name => '@_', sigil => '@' } ],
        };
    }

    my ( $mandatory, $optional, $slurpy ) = eval { $argcheck->aux_list($cv) };
    ( $mandatory, $optional, $slurpy ) = ( 0, 0, '' ) if $@;
    $slurpy = '' unless defined $slurpy;

    my %SIGIL = ( 0 => '$', 2 => '@', 4 => '%' );
    my @params;
    my $i = 0;
    for my $el (@argelem) {
        my $sigil = $SIGIL{ $el->private // 0 } // '$';
        push @params, {
            index => $i,
            name  => _pad_name_for( $cv, $el->targ ) // ( $sigil . "p$i" ),
            sigil => $sigil,
        };
        $i++;
    }

    return {
        kind      => 'declared',
        mandatory => 0 + $mandatory,
        optional  => 0 + $optional,
        ( length $slurpy ? ( slurpy => $slurpy ) : () ),
        params    => \@params,
    };
}

# The declared name of a pad slot, e.g. '$a'. Returns undef when the pad has no
# name for it -- a synthesized slot, or a perl that does not expose one.
sub _pad_name_for {
    my ( $cv, $targ ) = @_;
    return undef unless defined $targ && $targ;
    my $padlist = eval { $cv->PADLIST } or return undef;
    my @pads    = eval { $padlist->ARRAY } or return undef;
    my $names   = $pads[0] or return undef;
    my @n       = eval { $names->ARRAY } or return undef;
    return undef unless defined $n[$targ] && ref $n[$targ];
    my $nm = eval { $n[$targ]->PVX };
    return ( defined $nm && length $nm ) ? $nm : undef;
}

sub _record_sub {
    my ( $classes, $pkg_name, $name, $full_name, $cv, $graph ) = @_;

    # Do not auto-vivify a class record for any package that merely happens to
    # hold a translatable CV. Measured before this guard, an UNFILTERED run
    # produced 22 extra records (strict, warnings, utf8, Carp, Exporter,
    # JSON::PP, B::SoN) because every loaded module has subs.
    #
    # WHAT IS AND IS NOT WRONG WITH THAT. Not much, on inspection: a MOP::Class
    # is a name plus empty lists, nothing downstream iterates all classes
    # expensively, and no downstream misbehaviour was ever demonstrated. And
    # under everything-is-a-class, `strict` genuinely IS a class -- recording it
    # is not a lie. The real objections are hygiene: the count is unbounded and
    # input-dependent (it is whatever the program transitively `use`d), and it
    # silently moved an observable output (95 -> 117) that no test watched.
    #
    # THE LINE IS SCOPE, NOT IDENTITY: what were we ASKED to compile, versus
    # what perl loaded along the way. A CV knows -- ->FILE is the file it was
    # compiled from, and $0 is the file under compilation.
    #
    # That distinction matters BECAUSE Chalk is metacircular. B::SoN showing up
    # in its own output is not the compiler leaking into its artifact; it is the
    # compiler being an ordinary program, which is exactly what self-hosting
    # requires. When Chalk compiles ITSELF, $0 is B::SoN and this guard then
    # correctly INCLUDES it. Do not "fix" this by excluding the compiler by
    # name -- that would break self-hosting, which is the whole point.
    return unless exists $classes->{$pkg_name}
        || _cv_is_user_code($cv);
    $classes->{$pkg_name} //= _empty_class($pkg_name);

    # A METHOD is not a sub. _extract_class records methods separately; without
    # this guard a `method get` was dual-listed under BOTH keys (measured on a
    # feature-class: methods=[get,helper] subs=[get,helper]). The two differ in
    # dispatch and in whether they carry an implicit invocant, so conflating
    # them would hand the loader one callable under two contradictory
    # descriptions.
    return if exists( ( $classes->{$pkg_name}{methods} // {} )->{$name} );

    # A `:reader` accessor is SYNTHESIZED by the backend from the field's
    # attribute -- _extract_class tags the field is_reader and deliberately does
    # NOT emit the CV as a method, precisely so nothing shadows it. That CV is
    # still in the stash, so without this guard it lands here instead and the
    # accessor is declared twice: once synthesized from the field, once as a
    # MOP::Sub over the reader body. Measured on
    # `class Pt { field $x :param :reader; ... }` -- subs came back [util, x].
    for my $f ( ( $classes->{$pkg_name}{fields} // [] )->@* ) {
        next unless $f->{is_reader};
        # Field names carry their sigil ($x); the accessor drops it.
        return if substr( $f->{name} // '', 1 ) eq $name;
    }

    $classes->{$pkg_name}{subs}{$name} = {
        name      => $name,
        graph     => $full_name,
        uses_args => ( _cv_uses_args($cv) ? JSON::PP::true : JSON::PP::false ),
        # THE DECLARED SIGNATURE, read from argcheck/argelem rather than
        # inferred. `params` is kept as the flat positional list for existing
        # consumers; `signature` carries what params alone cannot say -- whether
        # the sub was declared at all (`sub f {}` is implicitly `(@_)`) versus
        # declared empty (`sub f()` is arity ZERO, and perl enforces it).
        signature => _cv_signature($cv),
        params    => [ map { $_->{name} } _cv_signature($cv)->{params}->@* ],
        # DECLARED HERE, at IR construction, for the same reason uses_args is:
        # this walk built the Return and knows its value node. Re-deriving it
        # downstream by walking the graph is the recovery-by-scanning the
        # metadata channel exists to retire.
        #
        # `Unknown` when the value carries no stamp yet -- a recursive call has
        # nothing to read at this point. NOT omitted: an absent field is not a
        # type, and it forces every consumer to invent a meaning.
        return_type => _graph_return_type($graph),
    };

    return;
}

# _cv_uses_args($cv) — does this sub body touch `@_`?
#
# Answered on the OPTREE, walking the whole body including nested blocks: `@_`
# is dynamically scoped to the innermost enclosing sub CALL, so a bare block or
# an `if` inside the sub sees the same one. Walk children as well as siblings,
# or a use inside a nested branch is missed -- the exact defect shape fixed in
# the arm scans earlier today.
#
# Not recursed into nested CVs: an inner `sub { ... }` has its OWN `@_`, so a
# use there says nothing about this one.
sub _cv_uses_args {
    my ($cv) = @_;
    my $root = eval { $cv->ROOT };
    return 0 unless defined $root && $$root;
    return _op_uses_args( $root, $cv );
}

sub _op_uses_args {
    my ( $op, $cv ) = @_;
    return 0 unless defined $op && $$op;

    my $name = $op->name;

    # A nested sub has its own @_; its uses are not ours.
    return 0 if $name eq 'anoncode';

    # THE NAME IS NOT ENOUGH: `$_` and `@_` are DIFFERENT variables that share
    # the glob name `_`, so matching on the name alone reports a sub using `$_`
    # as using `@_`. Measured: `sub f { $_ = "x"; /x/ }` was a false positive,
    # which would materialise an argument array for a sub that never asked for
    # one. The SIGIL is the discriminator and it lives on the OP KIND:
    #
    #   $_    gvsv[*_]                  scalar  -- NOT @_
    #   $_[0] aelemfast[*_]             array element
    #   @_    gv[*_] under rv2av        the array itself
    #
    # So `gvsv` is excluded outright, `aelemfast` is an array element access,
    # and a bare `gv` counts only when its parent dereferences it as an ARRAY
    # (checked by the rv2av arm below, which owns that test).
    # `$_[0]` is REDUNDANTLY covered: the rv2av arm below catches it too, and
    # the tests pass with this arm removed. It stays because the op IS emitted
    # (measured: `aelemfast[*_]` appears for `sub f { $_[0] + 1 }` even with the
    # peephole suppressed), and the two arms fail in opposite directions -- a
    # false NEGATIVE here means @_ is not materialised for a callee that reads
    # it, which is a silent wrong answer rather than a loud one.
    if ( $name eq 'aelemfast' ) {
        my $gv_name = _op_gv_name( $op, $cv ) // '';
        return 1 if $gv_name eq '_';
    }
    # `@_` proper: rv2av over the `_` glob -- covers `scalar @_`,
    # `my (...) = @_`, `$#_`, `foreach (@_)` and a plain `@_` in a list.
    if ( $name eq 'rv2av' && ( $op->flags & B::OPf_KIDS() ) ) {
        my $kid = $op->first;
        if ( defined $kid && $$kid && $kid->name eq 'gv' ) {
            my $gv_name = _op_gv_name( $kid, $cv ) // '';
            return 1 if $gv_name eq '_';
        }
    }
    # A bare `shift`/`pop` with no operand defaults to @_ inside a sub.
    if ( ( $name eq 'shift' || $name eq 'pop' )
        && !( $op->flags & B::OPf_KIDS() ) )
    {
        return 1;
    }
    # `goto &f` passes the CALLER'S @_ through to the target -- an implicit use
    # that names `_` nowhere in the optree (the body is goto/srefgen/rv2cv/gv),
    # so every name-based test above misses it. A false NEGATIVE is the
    # dangerous direction: @_ would not be materialised for a sub that hands it
    # onward. The `&f` form (entersub with no arg list) shares this property and
    # is NOT yet detected -- filed rather than guessed at, since distinguishing
    # it from an ordinary call needs the arg-list shape, not just the op name.
    return 1 if $name eq 'goto';

    if ( $op->flags & B::OPf_KIDS() ) {
        for ( my $kid = $op->first; $kid && $$kid; $kid = $kid->sibling ) {
            return 1 if _op_uses_args( $kid, $cv );
        }
    }
    return 0;
}

# Resolve the GV short name of a gv/gvsv/aelemfast op.
#
# Unthreaded perls store the GV on the op (B::SVOP->sv); threaded perls store it
# in the pad (B::PADOP->padix, or an SVOP whose sv is a B::SPECIAL and whose
# ->targ is the index). The same two-branch shape as
# SoN::FromOptree::_gv_op_slot, which is file-scoped inside a class block there
# and so cannot be shared without exporting it. B core is NOT an option:
# B::PADOP->gv reads PL_curpad, which is unset during static analysis, so it
# returns a null B::SPECIAL.
#
# Deliberately does NOT swallow errors. An eval here would turn a producer bug
# into undef -> uses_args=false -> @_ silently not materialised for a callee
# that reads it. The one caller runs inside _walk_package's try/catch, which
# reports a non-GAP exception LOUDLY as an internal error.
sub _op_gv_name {
    my ( $op, $cv ) = @_;

    my $slot;
    if ( $op->can('sv') ) {
        my $sv = $op->sv;
        $slot = $sv if defined $sv && ref $sv && $$sv;
    }
    if ( !$slot ) {
        my $ix = $op->can('padix') ? $op->padix : $op->targ;
        if ($ix) {
            my $padl = $cv->PADLIST;
            if ( defined $padl && $$padl ) {
                my $s = $padl->ARRAYelt(1)->ARRAYelt($ix);
                $slot = $s if defined $s && ref $s && $$s;
            }
        }
    }
    return undef unless $slot && $slot->isa('B::GV');
    return $slot->NAME;
}

# _extract_class($graphs, $pkg_name, $stash) — build the declarative class
# structure for a feature-class package: name, parent (:isa), fields (name,
# fieldix, param, plus default value + type from initfields_cv), method-name →
# graph-ref map, and ADJUST blocks as graph-refs.
sub _extract_class {
    my ( $graphs, $pkg_name, $stash ) = @_;

    no strict 'refs';

    my %class = (
        name    => $pkg_name,
        parent  => SoN::ClassAux::superclass_name($stash),
        fields  => _extract_fields( $pkg_name, $stash ),
        methods => {},
        adjusts => [],
    );

    # A `:reader` field synthesizes an accessor CV named after the field (sans
    # sigil). That CV is NOT flagged CVf_METHOD and its body reads the field via
    # a pad slot whose padname is NOT is_field-tagged, so it cannot lower as a
    # method graph — the backend instead synthesizes it from the field's :reader
    # attribute. Map each field's short name so a matching non-method CV is
    # recognized as its reader and tagged (is_reader) rather than emitted as a
    # user-method graph that would shadow the synthesized accessor.
    my %field_by_short =
        map { ( substr( $_->{name}, 1 ) => $_ ) } $class{fields}->@*;

    # Map each method name to its per-method graph ref (the fully-qualified key
    # under which _walk_package translated it into $graphs).
    for my $name ( sort keys %$stash ) {
        next if $name =~ /::$/;
        next if $name =~ /^[^a-zA-Z_]/;
        my $gv = eval { svref_2object( \*{"${pkg_name}::${name}"} ) };
        next unless defined $gv && $gv->isa('B::GV');
        my $cv = $gv->CV;
        next unless $$cv && !$cv->isa('B::SPECIAL');
        my $start = eval { $cv->START };
        next unless defined $start && $$start;    # skip the synthesized `new` XSUB

        # A :reader accessor: a non-CVf_METHOD CV whose name matches a declared
        # field. Tag the field :reader (the backend synthesizes the accessor)
        # and do NOT emit its body as a shadowing user-method graph.
        # TWO DIFFERENT FLAGS, and B::CVf_METHOD is the misleading one.
        # Measured on 5.42 (cv.h: CVf_METHOD is a back-compat alias for
        # CVf_NOWARN_AMBIGUOUS, the legacy `:method` ATTRIBUTE; CVf_IsMETHOD is
        # "a real method of a real class"):
        #
        #                        CvFLAGS   &0x1  &0x100000
        #   method get           0x101001    1       1
        #   sub helper           0x001000    0       0
        #   sub attr :method     0x001001    1       0     <- attribute only
        #   :reader accessor     0x101000    0       1
        #
        # NOT interchangeable: `sub attr :method` has no implicit invocant but
        # sets 0x1, and a :reader accessor sets 0x100000 yet must not be treated
        # as a user method. Each test keeps the flag that answers ITS question.
        my $has_method_attr = $cv->CvFLAGS & 0x1;        # legacy :method attr
        my $is_method       = $cv->CvFLAGS & 0x100000;   # CVf_IsMETHOD
        if ( !$has_method_attr && ( my $f = $field_by_short{$name} ) ) {
            $f->{is_reader} = JSON::PP::true;

            # AND RECORD IT AS A METHOD. A `:reader` IS a callable method of
            # this class, and leaving it out of {methods} made it findable
            # nowhere: chalk had to add a MOP::Field->is_reader accessor purely
            # to recover a return type this record should have carried.
            #
            # Safe only NOW THAT THE BODY IS RIGHT. While the reader's graph
            # read a PadAccess, listing it here would have handed consumers a
            # plausible method whose body lowers to the wrong thing -- worse
            # than the absence, because a missing record is visible and a wrong
            # body is not. _readers_read_fields makes the body a FieldAccess,
            # which is what unblocks this half.
            #
            # It stays OUT of {subs}: _record_sub's is_reader guard still holds,
            # and a reader dual-listed under both keys would be one callable
            # under two contradictory descriptions.
            $class{methods}{$name} = "${pkg_name}::${name}";
            next;
        }

        # A `method` carries an implicit invocant; a plain `sub` inside a
        # class block does not. They become DIFFERENT metaobjects downstream
        # (MOP::Method vs MOP::Sub), so the wire must tell them apart.
        # _record_sub fills in {subs} during the CV walk.
        if ($is_method) {
            # THE METHOD VALUE STAYS A GRAPH-NAME STRING. Consumers in BOTH
            # repos use it directly as a key into the top-level {methods} graph
            # map -- `$data->{methods}{ $methods->{val} }` producer-side,
            # `$graphs->{ $methods->{$mname} }` in the chalk loader. Making it a
            # hashref broke three producer tests and would have broken the
            # loader in lockstep, for no gain at this slice.
            #
            # The signature rides in a SIBLING map keyed by the same method
            # name, which is additive: an old consumer ignores it.
            $class{methods}{$name} = "${pkg_name}::${name}";

            # The invocant is NOT a parameter. Perl emits methstart() for it and
            # argcheck counts only the DECLARED params, so the first user
            # parameter is argelem(0) -- no reserved index is needed in either
            # direction (TurboFan reserves negative slots because JS's receiver
            # sits outside `arguments`; that fact does not transfer).
            $class{method_signatures}{$name} = {
                _cv_signature($cv)->%*,
                invocant => JSON::PP::true,
            };

            # The RETURN TYPE rides in its own sibling map, for the same reason
            # and by the same pattern as the signature above: the method value
            # must stay a bare graph-name string, so anything else a consumer
            # needs about a method is keyed by name alongside it.
            #
            # DECLARED HERE for the same reason as the sub path's `return_type`
            # (see _record_sub): this walk built the Return and knows its value
            # node. Without it, a consumer's only recourse is to re-derive the
            # type by walking the method graph -- and for methods that was not
            # merely redundant, it was the ONLY source. Measured before this
            # landed: return_type absent for 9 of 9 class methods, while chalk's
            # loader carried a whole fixpoint (_stamp_method_call_reprs) to
            # reconstruct it.
            #
            # `Unknown` is SENT, never omitted, matching the sub path: an absent
            # field is not a type, and it forces every consumer to invent a
            # meaning.
            #
            # The graph is translated from THIS CV rather than looked up in
            # $graphs: at this point the method's graph is not in there yet.
            # _extract_class records the name -> graph-key map, and the CVs are
            # translated afterwards by _walk_package or _translate_class_methods
            # (see the comment at :201). Looking it up here yielded `Unknown`
            # for every method -- measured, before this was corrected.
            #
            # Reuses an already-translated graph when one exists, so a method
            # walked by _walk_package first is not translated twice.
            # Unlike the two sites above, a failure here DEGRADES rather than
            # deletes: _graph_return_type(undef) yields 'Unknown', so the
            # method still reaches the wire, just untyped. That is a legitimate
            # answer -- but an unexpected die is still a bug worth hearing
            # about, and `eval {}` said nothing. A GAP is expected here (the
            # method genuinely does not translate) and stays quiet, since the
            # walk that owns that method reports it.
            my $g = $graphs->{"${pkg_name}::${name}"};
            unless ($g) {
                try { $g = SoN::FromOptree->translate( $cv->object_2svref ) }
                catch ($e) {
                    warn "B::SoN: INTERNAL ERROR deriving return type for "
                       . "${pkg_name}::${name} (it will read Unknown): $e"
                        unless $e =~ /^GAP:/;
                }
            }
            $class{method_return_types}{$name} = _graph_return_type($g);
        }
    }

    # Field defaults: walk initfields_cv, pair each field (by declaration order)
    # with its default value, and stamp the field type from the default. Each
    # default is emitted as a one-node Constant graph referenced from the field.
    _wire_field_defaults( $graphs, $pkg_name, $stash, $class{fields} );

    # ADJUST blocks: translate each ADJUST CV to a graph and reference it.
    # adjust_cvs is the FLATTENED chain (incl. inherited); emit OWN-only here so
    # the consumer does not double-apply a parent's ADJUST. We approximate
    # own-only by emitting only the blocks beyond the parent's count.
    my @adj_cvs = SoN::ClassAux::adjust_cvs($stash);
    my $parent  = SoN::ClassAux::superclass_name($stash);
    my $inherited = 0;
    if ( defined $parent ) {
        no strict 'refs';
        $inherited = scalar SoN::ClassAux::adjust_cvs( \%{"${parent}::"} );
    }
    my $aix = 0;
    for my $i ( $inherited .. $#adj_cvs ) {
        # adjust_cvs returns coderefs; translate takes a coderef directly.
        #
        # A DROPPED ADJUST IS A MISCOMPILE, NOT A GAP. The block does not reach
        # $class{adjusts}, so the consumer constructs the object WITHOUT
        # running it -- a silently wrong object rather than an honest refusal.
        # A bare `eval {}; next unless $g` said nothing about why, which is how
        # a stale workaround elsewhere (argelem declining to stamp `Array` for
        # a die the lattice stopped throwing) stayed invisible.
        #
        # Same policy as the method walk above: a GAP is the translator
        # speaking; anything else is a bug in us and must not be mistaken for
        # a refusal. Both are reported -- neither is silent.
        my $g;
        try {
            $g = SoN::FromOptree->translate( $adj_cvs[$i] );
        }
        catch ($e) {
            warn "B::SoN: ${pkg_name} ADJUST block $i dropped -- the object "
               . "will be constructed WITHOUT it: $e";
        }
        next unless $g;
        my $key = "${pkg_name}::__ADJUST_${aix}";
        $graphs->{$key} = $g;
        push $class{adjusts}->@*, $key;
        $aix++;
    }

    return \%class;
}

# _wire_field_defaults($graphs, $pkg_name, $stash, $fields) — extract each
# field's default value from the initfields_cv and attach has_default,
# default_ref (a one-node Constant graph), and a type inferred from the default.
sub _wire_field_defaults {
    my ( $graphs, $pkg_name, $stash, $fields ) = @_;

    my $init = SoN::ClassAux::initfields_cv($stash);
    return unless defined $init;
    my $cv = svref_2object($init);

    # Each field produces one initfield op, in declaration (fieldix) order.
    my @defaults;   # fieldix => default const op (or undef)
    my $idx = 0;
    _walk_initfields( $cv->ROOT, sub ($default_op) {
        $defaults[$idx++] = $default_op;
    });

    my $factory = SoN::IR::NodeFactory->new;
    for my $f (@$fields) {
        my $fix = $f->{fieldix};
        my $dop = $defaults[$fix];
        next unless defined $dop;

        my $start = $factory->make_cfg('Start');
        my ($value_node, $field_type);

        # An aggregate default (`field $items = [1,2,3]` / `{a=>1}`) is an
        # anonlist/anonhash of const children: build an ArrayRef/HashRef of
        # Constants, so the field types ArrayRef/HashRef and a read of it lowers
        # (zhi 019f61ad). A scalar default is a single Constant.
        if ( $dop->name eq 'anonlist' || $dop->name eq 'anonhash' ) {
            my @elems;
            my $k = $dop->first;
            while ( $$k ) {
                if ( $k->name eq 'const' ) {
                    my ( $v, $st, $ct ) = _const_op_value( $cv, $k );
                    push @elems, $factory->make('Constant',
                        value => $v, stamp => $st, const_type => $ct )
                        if defined $st;
                }
                $k = $k->sibling;
            }
            my $agg_op = $dop->name eq 'anonlist' ? 'ArrayRef' : 'HashRef';
            $field_type = $agg_op;
            $value_node = $factory->make( $agg_op, inputs => \@elems );
        }
        else {
            my ( $value, $stamp, $const_type ) = _const_op_value( $cv, $dop );
            next unless defined $stamp;
            $field_type = $stamp->type;
            $value_node = $factory->make('Constant',
                value => $value, stamp => $stamp, const_type => $const_type );
        }

        # Produce-time control: control is carried on control_in, never
        # flattened into inputs -- SoN::IR::Node::Return's contract is
        # inputs=[value], control_in=predecessor.
        my $ret = $factory->make_cfg('Return', inputs => [ $value_node ] );
        $ret->set_control_in($start);

        my $key = "${pkg_name}::__DEFAULT_${fix}";
        $graphs->{$key} = SoN::IR::Graph->new( start => $start, returns => [$ret] );
        $f->{has_default} = JSON::PP::true;
        $f->{default_ref} = $key;
        # A DEFAULT TYPES A FIELD ONLY WHEN NOTHING OUTSIDE CAN WRITE IT.
        #
        # `field $v :param = 0` recorded Int from the default. That is a true
        # fact about the INITIALISER and a false one about the FIELD: `:param`
        # lets a caller pass anything, and perl agrees --
        #
        #   Box->new(v => "hello")  ->  hello
        #   Box->new(v => [1,2])    ->  an ARRAY ref
        #
        # So the recorded type is the JOIN of the default with what `:param`
        # admits. Nothing constrains the argument, so that is `Scalar` -- which
        # is not nothing: it excludes Array, Hash, Code and Glob.
        #
        # The same shape as `my $x = 0; sub f() { $x }` -- Int at the
        # assignment, but f's return is the join over every WRITER. A field
        # WITHOUT `:param` has no outside writer, so its default stands.
        #
        # A method body may still narrow this: `$v / 2` meets Scalar with the
        # Num that `/` requires and gets Num, which is how a use site recovers
        # precision the declaration cannot promise.
        if ( $f->{is_param} && defined $field_type ) {
            $field_type = SoN::IR::Stamp::join(
                SoN::IR::Stamp->new( type => $field_type ),
                SoN::IR::Stamp->new( type => 'Scalar' ),
            )->type;
        }
        $f->{type}        = $field_type;
    }
    return;
}

# _walk_initfields($op, $cb) — for each initfield in the initfields optree (in
# order), invoke $cb with the op holding its default value, or undef when the
# field has no constant default. A :param field is
# `initfield -> ... -> helemexistsor(param-lookup, DEFAULT)`; a plain-default
# field is `initfield -> CONST`; a bare field has no usable default.
sub _walk_initfields {
    my ( $op, $cb ) = @_;
    return unless $$op;
    if ( $op->name eq 'initfield' ) {
        $cb->( _initfield_default($op) );
        return;
    }
    if ( $op->can('first') ) {
        my $k = $op->first;
        while ($$k) { _walk_initfields( $k, $cb ); $k = $k->sibling; }
    }
    return;
}

# _initfield_default($initfield_op) — the op node holding the field's default
# value, or undef. Descends through the wrapping null/helemexistsor.
sub _initfield_default {
    my ($op) = @_;
    # initfield's child is the value expression (possibly wrapped in null).
    my $child = $op->can('first') ? $op->first : undef;
    return undef unless $child && $$child;
    $child = $child->first while $child->name eq 'null' && $child->can('first') && ${ $child->first };

    if ( $child->name eq 'helemexistsor' ) {
        # :param field: the OR-else (last child) is the default.
        my $last;
        my $k = $child->first;
        while ($$k) { $last = $k; $k = $k->sibling; }
        return ( $last && ($last->name eq 'const' || $last->name eq 'anonlist'
                        || $last->name eq 'anonhash') ) ? $last : undef;
    }
    # A scalar default is a `const`; an aggregate default (`field $x = [1,2,3]`
    # / `{a=>1}`) is an `anonlist`/`anonhash` (built as a ref).
    return ( $child->name eq 'const' || $child->name eq 'anonlist'
          || $child->name eq 'anonhash' ) ? $child : undef;
}

# _const_op_value($cv, $const_op) — (value, stamp, const_type) for a const op,
# resolving a shared B::SPECIAL through the pad (as the FromOptree const handler
# does). Only simple scalar defaults (Int/Num/Str) are recovered.
sub _const_op_value {
    my ( $cv, $op ) = @_;
    my $sv   = $op->sv;
    my $targ = $op->targ;
    if ( ( !$$sv || $sv->isa('B::SPECIAL') ) && $targ ) {
        my $padl = $cv->PADLIST;
        $sv = $padl->ARRAYelt(1)->ARRAYelt($targ) if $$padl;
    }
    return ( undef, undef, undef ) unless $sv && $$sv && !$sv->isa('B::SPECIAL');

    if ( $sv->isa('B::IV') && !$sv->isa('B::PVIV') ) {
        return ( $sv->int_value, SoN::IR::Stamp->new( type => 'Int' ), 'integer' );
    }
    if ( $sv->isa('B::NV') && !$sv->isa('B::PVNV') ) {
        return ( $sv->NV, SoN::IR::Stamp->new( type => 'Num' ), 'number' );
    }
    if ( $sv->FLAGS & B::SVf_IOK() ) {
        return ( $sv->int_value, SoN::IR::Stamp->new( type => 'Int' ), 'integer' );
    }
    if ( $sv->FLAGS & B::SVf_NOK() ) {
        return ( $sv->NV, SoN::IR::Stamp->new( type => 'Num' ), 'number' );
    }
    if ( $sv->can('PV') ) {
        return ( $sv->PV, SoN::IR::Stamp->new( type => 'Str' ), 'string' );
    }
    return ( undef, undef, undef );
}

# _extract_fields($pkg_name, $stash) — collect ALL of the class's declared
# fields. The authoritative full list comes from the initfields_cv optree, which
# has one `initfield` op per declared field in fieldix order (so it sees fields
# no user method references — a :reader-only field, an ADJUST-only field). The
# initfield op yields the fieldix, :param flag, and param name; the field's
# variable NAME (e.g. `$double`) is not on the op, so it is recovered from a
# FIELD padname in any method or ADJUST CV that references the field, falling
# back to `$` + param_name (or a placeholder) when nothing references it.
sub _extract_fields {
    my ( $pkg_name, $stash ) = @_;

    no strict 'refs';

    # fieldix -> variable name, from the class's OWN field padnames
    # (SoN::ClassAux::class_field_names walks HvAUX(stash)->xhv_class_fields).
    # This is authoritative and independent of whether any method/ADJUST body
    # references the field -- the old code scavenged field padnames from
    # referencing CVs and fell back to `$` + param_name when nothing referenced
    # the field, which yielded the wrong name for a custom `:param(NAME)` where
    # NAME != the variable name (e.g. `$left :param(alpha)` -> `$alpha`, breaking
    # reader detection). The class field list has the real `$left` (zhi 019f4625).
    my %varname;
    my @field_pairs = SoN::ClassAux::class_field_names($stash);
    while ( my ( $name, $fieldix ) = splice @field_pairs, 0, 2 ) {
        $varname{$fieldix} //= $name;
    }

    # The declarative field list, in fieldix order, from the initfields optree.
    my @fields;
    my $init = SoN::ClassAux::initfields_cv($stash);
    if ( defined $init ) {
        my $init_cv = svref_2object($init);
        my $ix      = 0;
        _walk_initfield_ops( $init_cv->ROOT, sub ($op) {
            my ( $is_param, $param_name ) = _initfield_param( $init_cv, $op );
            my $name = $varname{$ix}
                // ( defined $param_name ? "\$$param_name" : "\$field$ix" );
            push @fields, {
                name       => $name,
                fieldix    => $ix,
                is_param   => ( $is_param ? JSON::PP::true : JSON::PP::false ),
                param_name => $param_name,
            };
            $ix++;
        });
    }

    return \@fields;
}

# _walk_initfield_ops($op, $cb) — invoke $cb once per `initfield` op, in optree
# (declaration / fieldix) order. Mirrors _walk_initfields but hands the initfield
# op itself to the callback (that one walks to the default value).
sub _walk_initfield_ops {
    my ( $op, $cb ) = @_;
    return unless $$op;
    if ( $op->name eq 'initfield' ) {
        $cb->($op);
        return;
    }
    if ( $op->can('first') ) {
        my $k = $op->first;
        while ($$k) { _walk_initfield_ops( $k, $cb ); $k = $k->sibling; }
    }
    return;
}

# _initfield_param($cv, $initfield_op) — (is_param, param_name) for a field. A
# :param field's value expression is `helemexistsor(%(params){NAME}, DEFAULT)`;
# the NAME const (the sibling of the params padhv) is the constructor param name.
# A non-:param field has no helemexistsor, so is_param is false.
sub _initfield_param {
    my ( $cv, $op ) = @_;
    my $child = $op->can('first') ? $op->first : undef;
    return ( 0, undef ) unless $child && $$child;
    $child = $child->first
        while $child->name eq 'null' && $child->can('first') && ${ $child->first };
    return ( 0, undef ) unless $child->name eq 'helemexistsor';

    # helemexistsor's first child is the params hash-elem lookup:
    # null? -> (padhv %(params), const PARAMNAME). Descend to the padhv, then
    # its sibling const is the param name.
    my $hx = $child->first;
    $hx = $hx->first
        while $hx->name eq 'null' && $hx->can('first') && ${ $hx->first };
    my $key = $hx->sibling;
    return ( 1, undef ) unless $key && $$key && $key->name eq 'const';

    my $sv   = $key->sv;
    my $targ = $key->targ;
    if ( ( !$$sv || $sv->isa('B::SPECIAL') ) && $targ ) {
        my $padl = $cv->PADLIST;
        $sv = $padl->ARRAYelt(1)->ARRAYelt($targ) if $$padl;
    }
    my $pname = ( $sv && $$sv && $sv->can('PV') ) ? $sv->PV : undef;
    return ( 1, $pname );
}

1;
