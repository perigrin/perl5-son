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
use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use SoN::IR::Stamp;

# Suppress the peephole optimizer for the duration of the target program's
# compilation. B::SoN loads via -MO=SoN at BEGIN, before the target body
# compiles, so installing the no-op rpeep here keeps element access, list
# intro, and similar in canonical, unfused form (aelem/helem/pushmark+padsv
# rather than aelemfast/multideref/padrange) -- which map directly to the IR.
# rpeep is an optimization, not a correctness pass: the optree still executes.
BEGIN { SoN::OptSuppress::suppress_peep(); }

# compile(\@opts) — called by O.pm; returns a CODE ref that O.pm invokes
# after the program has been compiled and the full optree is available.
sub compile {
    my @opts   = @_;
    my $format = 'text';
    $format    = 'json' if grep { $_ eq 'json' } @opts;

    # Collect package= filters (exact match, multiple allowed)
    my %pkg_filter;
    for my $opt (@opts) {
        if ( $opt =~ /^package=(.+)$/ ) {
            $pkg_filter{$1} = 1;
        }
    }
    my $filter = %pkg_filter ? \%pkg_filter : undef;

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

    # Under a package= filter, a class referenced from an emitted sub (e.g.
    # `Counter->new` / `$c->get` inside main::) is not itself in the filter, so
    # its MOP + method graphs were skipped -- leaving the method Call with no
    # return repr to infer from. Transitively emit the MOP of every class
    # actually referenced (via a method Call's class_name) from the graphs we
    # have, and only those classes: the whole stash would leak every internal
    # SoN class. A newly-emitted method graph may reference further classes, so
    # fixpoint until no new class appears.
    _emit_referenced_classes( \%graphs, \%classes ) if $filter;

    return ( \%graphs, \%classes );
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
            $added++;
        }
        last unless $added;   # fixpoint: no new class this round
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
            warn "B::SoN: skipped $full_name: $e" if $e =~ /^GAP:/;
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
    my $emit_cvs = !$filter || exists $filter->{$pkg_name};

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
        my $is_method = $cv->CvFLAGS & 0x1;    # CVf_METHOD
        if ( !$is_method && ( my $f = $field_by_short{$name} ) ) {
            $f->{is_reader} = JSON::PP::true;
            next;
        }

        $class{methods}{$name} = "${pkg_name}::${name}";
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
        my $g = eval { SoN::FromOptree->translate( $adj_cvs[$i] ) };
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

    my $factory = Chalk::IR::NodeFactory->new;
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
        # flattened into inputs -- Chalk::IR::Node::Return's contract is
        # inputs=[value], control_in=predecessor.
        my $ret = $factory->make_cfg('Return', inputs => [ $value_node ] );
        $ret->set_control_in($start);

        my $key = "${pkg_name}::__DEFAULT_${fix}";
        $graphs->{$key} = Chalk::IR::Graph->new( start => $start, returns => [$ret] );
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
