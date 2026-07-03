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
    return ( \%graphs, \%classes );
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
            # A deliberate GAP refusal is the translator speaking, though,
            # not discovery noise: swallowing it turns a loud honest refusal
            # into a sub silently missing from the JSON. Re-emit on stderr.
            warn "B::SoN: skipped $full_name: $e" if $e =~ /^GAP:/;
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

    my $factory = SoN::IR::NodeFactory->new;
    for my $f (@$fields) {
        my $fix = $f->{fieldix};
        my $dop = $defaults[$fix];
        next unless defined $dop;

        my ( $value, $stamp, $const_type ) = _const_op_value( $cv, $dop );
        next unless defined $stamp;

        my $start = $factory->make_cfg('Start');
        my $const = $factory->make('Constant',
            value => $value, stamp => $stamp, const_type => $const_type );
        my $ret = $factory->make_cfg('Return', inputs => [ $start, $const ] );

        my $key = "${pkg_name}::__DEFAULT_${fix}";
        $graphs->{$key} = SoN::IR::Graph->new( start => $start, returns => [$ret] );
        $f->{has_default} = JSON::PP::true;
        $f->{default_ref} = $key;
        $f->{type}        = $stamp->type;
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
        return ( $last && $last->name eq 'const' ) ? $last : undef;
    }
    return ( $child->name eq 'const' ) ? $child : undef;
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
    return ( undef, undef, undef ) unless $sv && $$sv;

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

# _extract_fields($pkg_name, $stash) — collect the class's fields by walking a
# method's padlist for FIELD padnames (via SoN::FieldInfo), deduped by fieldix.
sub _extract_fields {
    my ( $pkg_name, $stash ) = @_;

    no strict 'refs';

    my %by_ix;
    for my $name ( sort keys %$stash ) {
        next if $name =~ /::$/;
        my $gv = eval { svref_2object( \*{"${pkg_name}::${name}"} ) };
        next unless defined $gv && $gv->isa('B::GV');
        my $cv = $gv->CV;
        next unless $$cv && !$cv->isa('B::SPECIAL');
        my $padlist = eval { $cv->PADLIST };
        next unless $padlist && $$padlist;
        my $padnames = $padlist->ARRAYelt(0);
        next unless $padnames && $$padnames;

        for my $i ( 0 .. $padnames->MAX ) {
            my $pn = $padnames->ARRAYelt($i);
            next unless ref $pn eq 'B::PADNAME' && SoN::FieldInfo::is_field($pn);
            my @info     = SoN::FieldInfo::field_info($pn);
            my $fieldix  = $info[0];
            next if exists $by_ix{$fieldix};
            my $varname  = eval { $pn->PV } // '$?';
            $by_ix{$fieldix} = {
                name       => $varname,
                fieldix    => $fieldix,
                is_param   => ( defined $info[2] ? JSON::PP::true : JSON::PP::false ),
                param_name => $info[2],
            };
        }
    }

    return [ map { $by_ix{$_} } sort { $a <=> $b } keys %by_ix ];
}

1;
