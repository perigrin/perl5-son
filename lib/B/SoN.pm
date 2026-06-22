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
        $classes->{$pkg_name} = _extract_class( $pkg_name, $stash );
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

# _extract_class($pkg_name, $stash) — build the declarative class structure for
# a feature-class package: name, parent (:isa), fields (name, fieldix, param),
# and method-name → graph-ref map. Field DEFAULTS and ADJUST bodies are NOT
# emitted here (they require initfield-aux decoding; a follow-up stage).
sub _extract_class {
    my ( $pkg_name, $stash ) = @_;

    no strict 'refs';

    my %class = (
        name    => $pkg_name,
        parent  => SoN::ClassAux::superclass_name($stash),
        fields  => _extract_fields( $pkg_name, $stash ),
        methods => {},
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

    return \%class;
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
