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
    _emit_referenced_classes( \%graphs, \%classes ) if $filter;

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
sub _resolve_deferred_stamps {
    my ( $graphs, $classes ) = @_;

    _stamp_field_reads( $graphs, $classes );
    _rederive_method_return_types( $graphs, $classes );
    _stamp_calls_from_callees( $graphs, $classes );

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
sub _referenced_class_names {
    my ( $graphs, $scanned ) = @_;
    my %names;
    for my $key ( keys $graphs->%* ) {
        next if $scanned->{$key}++;
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
    if ( $emit_cvs && SoN::ClassAux::is_class($stash) ) {
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
