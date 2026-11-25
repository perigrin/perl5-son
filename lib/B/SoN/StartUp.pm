# ABOUTME: An O backend run on a followed module's FILE as a program: says what its file-level code
# ABOUTME: does beyond setting its package data, which B::SoN cannot put on the wire (audit 3, N9).

use v5.42.0;

package B::SoN::StartUp;
use B ();

# WHY A FILE IS COMPILED AGAIN, IN ANOTHER PROCESS. A followed module's file
# runs at `use` time and perl frees its code: only the package data it left
# is there at CHECK (B::SoN::_module_start_state). Anything else its file
# did -- printed, stored into another package, set a file lexical its subs
# close over, made a reference two variables share -- is not on the wire,
# and the program ran from a guess (third final audit, N9). Compiled again
# (compile only, as `perl -c` does), its main line is in hand, and this says
# what in it is more than plain package data.
#
#   perl -MO=-q,SoN::StartUp FILE   ->  prints `STARTUP <kind> <op>` lines
#
# <kind>: `effect` (output, a die or an exit, a store into a variable of
# another package: seen whether or not the program reads the module) or
# `code` (anything else beyond `our` data of literals: a call, a `my`, a
# reference, a require -- what the module's own state may depend on).

# Ops of plain package data: structure, literals, fresh aggregates of them,
# and the package's own variables assigned them.
my %DATA = map { $_ => 1 } qw(
    leave enter nextstate dbstate null pushmark list lineseq stub const
    sassign aassign anonlist anonhash negate undef gv gvsv rv2sv rv2av rv2hv
    srefgen refgen
);
my %EFFECT = map { $_ => 1 } qw(print say prtf syswrite send warn die exit);

sub compile {
    my $pkg_of = sub ($cop) { eval { $cop->stashpv } // 'main' };
    return sub {
        my %seen;
        my $pkg = 'main';
        # (the packages the file declares are its own: POSIX.pm stores
        # %POSIX::... under `package POSIX::SigRt`)
        my %own;
        my $scan;
        $scan = sub ($o) {
            return unless $o && $$o;
            $own{ $pkg_of->($o) } = 1 if $o->name =~ /\A(?:next|db)state\z/;
            if ( $o->flags & B::OPf_KIDS() ) { for ( my $k = $o->first; $k && $$k; $k = $k->sibling ) { $scan->($k) } }
        };
        $scan->( B::main_root() );
        undef $scan;
        my $walk;
        $walk = sub ($o) {
            return unless $o && $$o;
            my $n = $o->name;
            $pkg = $pkg_of->($o) if $n eq 'nextstate' || $n eq 'dbstate';
            if ( $EFFECT{$n} ) { $seen{"effect $n"} = 1 }
            elsif ( $n eq 'gv' || $n eq 'gvsv' ) {
                # (a variable of another package, stored: an effect on it)
                my $gv = eval { $o->isa('B::PADOP') ? ( B::main_cv()->PADLIST->ARRAYelt(1)->ARRAY )[ $o->padix ] : $o->gv };
                my $stash = eval { $gv->STASH->NAME } // '';
                # (its place: the ex-rv2sv over a gvsv, the rv2Xv over a gv)
                my $place = $o->parent;
                $place = $o if $n eq 'gvsv' && !( $$place && $place->name eq 'null' );
                my $mod = ( $o->flags | $place->flags ) & B::OPf_MOD();
                # (a variable of a name: `@_` and `$_` are main's by spelling;
                # a `local` saves and puts back)
                $seen{"effect store-into-$stash"} = 1 if $mod && length $stash && $stash ne $pkg && !$own{$stash}
                    && ( eval { $gv->NAME } // '' ) =~ /\A[A-Za-z]/ && !( ( $o->private | $place->private ) & B::OPpLVAL_INTRO() );
            }
            elsif ( $n eq 'srefgen' || $n eq 'refgen' ) { $seen{'code reference'} = 1 }
            elsif ( !$DATA{$n} ) { $seen{"code $n"} = 1 }
            if ( $o->flags & B::OPf_KIDS() ) { for ( my $k = $o->first; $k && $$k; $k = $k->sibling ) { $walk->($k) } }
        };
        $walk->( B::main_root() );
        undef $walk;
        print "STARTUP $_\n" for sort keys %seen;
    };
}

1;
