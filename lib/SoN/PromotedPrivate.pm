# ABOUTME: V14's own rule: a promoted argument or parameter record is private, by a check simpler
# ABOUTME: than SoN::AliasProof's and sharing none of it. Used by SoN::Verify and asked by SoN::Promote.
package SoN::PromotedPrivate;
use v5.42.0;

# ITS OWN MODULE, not SoN::Verify's: B::SoN compiles a program in its own
# process, and a program that loads another tree's SoN::Verify (probe r/v
# does) must not take this rule away from SoN::Promote.

sub _fields ($n) { $n->{fields} // {} }

# (V14) A PROMOTED NODE IS PRIVATE (design B, docs/plans/2026-11-25-places-everywhere.md):
# SoN::Promote made it from a place or a late read, and the wire as it left
# is checked here -- the pass is not trusted.
#
# BY A RULE OF ITS OWN (audit 4, X5). V14 used to ask SoN::AliasProof, the
# pass's own proof, again: it passed all 16 wrong answers that proof made. A
# checker earns trust by sharing nothing with what it checks, so this one is
# simpler and stricter, and asks nothing of SoN::AliasProof or of the effect
# table. P1, a call's promoted argument, is private when all of:
#   - every sub the call may run is one the wire holds, and its @_ is only
#     read: no store, reference or hand-on of @_ or of an element (an element
#     handed to another call is a place, or is checked at that call);
#   - the argument is read at the call's version, or at one the call follows
#     with nothing between that may store it (a `my` of the caller: nothing
#     between that names it, but a call handed it as a value or as a place
#     its callees only read; anything else: every version between QUIET);
#   - it is a `my` scalar of the caller no Ref, closure or other sub reaches
#     (only its own graph can name it), or every version on every way from
#     each callee's start to each of its reads of @_ is QUIET for it.
# A QUIET version stores nothing the argument may be: a read pinned where it
# stands, a Ref, a cell made, a print, a store whose every target is a named
# variable V14 names otherwise (by its own names, below), a `local`, a push,
# or a call of subs the wire holds that are QUIET throughout. Anything
# through a reference, a cell or @_ is not. SoN::Promote asks this rule of
# itself too, so a promotion it rejects is not made. Upgrade to a finer rule
# only with mutation cases that break it.
my %QUIET_OP = map { ( $_ => 1 ) } qw(Subscript PostfixDeref PadAccess EntryDef FieldAccess CellRead Exists Count RefType Keys Slice
    Coerce Ref MakeCell ArrayLiteral HashLiteral MemStart Phi Loop Region Start);
my %QUIET_BUILTIN = map { ( $_ => 1 ) } qw(print say prtf warn);
my $STORE_OP = qr/\A(?:EntryWrite|CellWrite|Delete|ElemRestore|LocalAlias|Unwind)\z/;

# private_checker($wire) -> ( $private, $args_read_only, $add ):
#   $private->($g, $call, $i): undef where the call's input $i, a value, is
#     private by V14's rule, else why not;
#   $args_read_only->($sub): the sub's @_ is only read;
#   $add->($g, $node): a node made after the checker was (SoN::Promote's).
sub private_checker ($wire) {
    my $m = all_graphs($wire);
    my %by = map { my $g = $_; ( $g => { map { ( $_->{id} => $_ ) } ( $m->{$g}{nodes} // [] )->@* } ) } keys $m->%*;
    my %cons;
    for my $g ( keys %by ) {
        for my $n ( values $by{$g}->%* ) { push $cons{$g}{$_}->@*, $n for grep { defined && !ref } ( $n->{inputs} // [] )->@* }
    }
    my $sub_call = sub ($n) { $n->{op} eq 'Call' && ( _fields($n)->{dispatch_kind} // '' ) ne 'builtin' };
    my $callees  = sub ($c) {
        my ( $k, $name ) = ( _fields($c)->{dispatch_kind} // '', _fields($c)->{name} // '' );
        return $m->{$name} ? [$name] : undef if $k eq 'direct';
        if ( $k eq 'method' ) { my @t = grep { /::\Q$name\E\z/ } keys $m->%*; return @t ? \@t : undef }
        return undef;
    };
    # (V14'S OWN NAMES for what a node accesses: a package variable by its
    # full name, a lexical one by its symbol whatever graph names it (two
    # subs' `my $x` are taken for one: the safe side), an element by its
    # container and constant index or `*`; undef for anything else -- through
    # a reference, @_, a field, a cell)
    my $name_of;
    $name_of = sub ( $g, $n ) {
        return undef unless $n;
        my $f = _fields($n);
        my ( $op, $sig, $sym ) = ( $n->{op}, $f->{sigil} // '', $f->{symbol} );
        if ( $op eq 'Subscript' ) {
            my $c = $name_of->( $g, $by{$g}{ $n->{inputs}[0] // '' } ) // return undef;
            return undef unless $c =~ /\A(?:my)?[\@%]/;
            my $ix = $by{$g}{ $n->{inputs}[1] // '' };
            return "$c#" . ( $ix && $ix->{op} eq 'Constant' && defined _fields($ix)->{value} ? _fields($ix)->{value} : '*' );
        }
        return undef unless defined $sym && $sig =~ /\A[\$\@%]\z/;
        return $sig . ( $f->{package} // 'main' ) . "::$sym" if $op eq 'EntryDef';
        return "my$sig$sym" if $op eq 'PadAccess';
        if ( $op =~ /\A(?:ArrayLiteral|HashLiteral)\z/ ) {
            return $sym =~ /::/ ? ( $sym =~ /\A[\@%]/ ? $sym : "$sig$sym" ) : "my$sig$sym";
        }
        return undef;
    };
    # (two names that cannot be one storage: an element and its own
    # container, or two elements of one container at an index not known, may)
    my $differ = sub ( $t, $s ) {
        return 0 if $t eq $s;
        my ( $tc, $ti ) = $t =~ /\A(.*)#([^#]*)\z/;
        my ( $sc, $si ) = $s =~ /\A(.*)#([^#]*)\z/;
        return !( $tc eq $sc && ( $ti eq '*' || $si eq '*' ) ) if defined $tc && defined $sc;
        return $s ne $tc if defined $tc;
        return $t ne $sc if defined $sc;
        return 1;
    };
    # QUIET for $s (a name, or undef for any variable): the version stores
    # nothing, or only named variables other than $s -- a `local` or a glob
    # assignment binds a new scalar to a name, a push or unshift leaves the
    # elements there are -- through every call it makes.
    my ( %quiet_sub, $quiet, $quiet_sub );
    $quiet_sub = sub ( $h, $s, $seen ) {
        my $k = $h . "\0" . ( $s // '' );
        return $quiet_sub{$k} if exists $quiet_sub{$k};
        return 1 if $seen->{$k}++;
        my $ok = 1;
        for my $n ( values $by{$h}->%* ) { $ok = 0, last unless $quiet->( $h, $n, $s, $seen ) }
        return $quiet_sub{$k} = $ok;
    };
    $quiet = sub ( $g, $n, $s = undef, $seen = {} ) {
        if ( $sub_call->($n) ) {
            my $t = $callees->($n) or return 0;
            return !grep { !$quiet_sub->( $_, $s, $seen ) } @$t;
        }
        return 1 unless $n->{mem_out} || $n->{op} =~ $STORE_OP;
        return 1 if $n->{op} eq 'Call' && $QUIET_BUILTIN{ _fields($n)->{name} // '' };
        return 1 if $QUIET_OP{ $n->{op} };
        return 0 unless defined $s;
        return 1 if $n->{op} eq 'EntryWrite' && ( _fields($n)->{local} || _fields($n)->{binds} );
        return 1 if $n->{op} eq 'Call' && ( _fields($n)->{dispatch_kind} // '' ) eq 'builtin' && ( _fields($n)->{name} // '' ) =~ /\A(?:push|unshift)\z/;
        my @t = $n->{op} eq 'Assign' && !_fields($n)->{record} ? $n->{inputs}->@[ 0 .. ( _fields($n)->{targets} // 1 ) - 1 ]
              : $n->{op} eq 'EntryWrite' ? ( $n->{inputs}[0] ) : return 0;
        for my $t (@t) {
            my $tn = $name_of->( $g, defined $t && !ref $t ? $by{$g}{$t} : undef ) // return 0;
            next if $differ->( $tn, $s );
            # (a store by the name after a `local` of it, straight back along
            # the chain with no merge, call or rebinding between: the new scalar)
            return 0 unless $n->{op} eq 'EntryWrite';
            my ( $v, $k, $new ) = ( $n->{mem_in}, 0, 0 );
            while ( defined $v && $k++ < 100000 ) {
                my $vn = $by{$g}{$v} or last;
                last if $vn->{op} =~ /\A(?:Phi|MemStart)\z/ || $vn->{op} eq 'Call';
                if ( $vn->{op} eq 'EntryWrite' && ( _fields($vn)->{local} || _fields($vn)->{binds} ) ) {
                    $new = _fields($vn)->{local} && ( $name_of->( $g, $by{$g}{ $vn->{inputs}[0] // '' } ) // '' ) eq $tn;
                    last;
                }
                $v = $vn->{mem_in};
            }
            return 0 unless $new;
        }
        return 1;
    };
    # (a sub's @_ only read: each element read as a value, @_ counted, or bound by a record)
    my %read_only;
    my $args_read_only = sub ($h) {
        return $read_only{$h} //= do {
            my $ok = !grep { $_->{op} eq 'Call' && _fields($_)->{shares_args} } values $by{$h}->%*;
            for my $s ( grep { $_->{op} eq 'ArgsSource' } values $by{$h}->%* ) {
                for my $u ( ( $cons{$h}{ $s->{id} } // [] )->@* ) {
                    next if $u->{op} eq 'Count' || $u->{op} eq 'Assign' && _fields($u)->{record};
                    $ok = 0, last unless $u->{op} eq 'Subscript' && ( $u->{inputs}[0] // -1 ) == $s->{id} && !_fields($u)->{place};
                    for my $v ( ( $cons{$h}{ $u->{id} } // [] )->@* ) {
                        my @at = grep { ( $v->{inputs}[$_] // -1 ) eq $u->{id} } 0 .. $#{ $v->{inputs} };
                        my $target = $v->{op} eq 'Assign' && !_fields($v)->{record} && grep { $_ < ( _fields($v)->{targets} // 1 ) } @at;
                        $ok = 0 if $v->{op} eq 'Ref' || $target || _fields($v)->{vivify}
                            || ( $v->{mem_out} || $v->{op} =~ $STORE_OP )
                               && !( $v->{op} eq 'Assign' || $sub_call->($v) || $QUIET_OP{ $v->{op} } || $v->{op} eq 'RegexMatch'
                                     || $v->{op} eq 'Call' && $QUIET_BUILTIN{ _fields($v)->{name} // '' } );
                    }
                }
            }
            $ok ? 1 : 0;
        };
    };
    # (every way back along the memory chain from $from to $to -- to the
    # start where $to is undef: undef where each version on it passes $ok,
    # else the one that does not)
    my $between = sub ( $g, $from, $to, $ok ) {
        my ( @q, %seen ) = ($from);
        while (@q) {
            my $v = shift @q;
            next if $seen{$v}++ || defined $to && $v == $to;
            my $vn = $by{$g}{$v} or return "a version #$v not on the wire";
            next if $vn->{op} eq 'MemStart';
            return "$vn->{op}#$v" unless $ok->($vn);
            my @back = $vn->{op} eq 'Phi' ? grep { defined && !ref } $vn->{inputs}->@* : $vn->{mem_in};
            return "$vn->{op}#$v, with no way back" if grep { !defined } @back;
            push @q, @back;
        }
        return undef;
    };
    # (a `my` scalar of graph $g that only $g names: not shared with a named
    # sub, no Ref takes it, no closure captures it)
    my $own_my = sub ( $g, $a ) {
        my $f = _fields($a);
        return 0 unless $a->{op} eq 'PadAccess' && ( $f->{sigil} // '' ) eq '$' && !$f->{shared} && defined $f->{symbol};
        my $name = '$' . $f->{symbol};
        for my $n ( values $by{$g}->%* ) {
            if ( $n->{op} eq 'Ref' ) {
                my $t = $by{$g}{ $n->{inputs}[0] // '' } or return 0;
                # (only a reference to another variable, named by its node, is harmless)
                return 0 unless $t->{op} =~ /\A(?:PadAccess|EntryDef|Subscript|FieldAccess|ArrayLiteral|HashLiteral|CellRead)\z/;
                return 0 if $t->{op} eq 'PadAccess' && ( _fields($t)->{symbol} // '' ) eq $f->{symbol};
            }
            return 0 if $n->{op} eq 'MakeCell' && ( _fields($n)->{cell_name} // '' ) eq $name;
            return 0 if $n->{op} eq 'AnonSub' && grep { $_ eq $name } ( _fields($n)->{captures} // [] )->@*;
        }
        return 1;
    };
    # (SoN::Promote asks before it rewrites: of the place, read at $at)
    my $private = sub ( $g, $c, $i, $at = undef ) {
        my $a = $by{$g}{ $c->{inputs}[$i] // '' } or return 'no input';
        $at //= $a->{mem_in};
        return 'read at no version' unless defined $at && defined $c->{mem_in};
        my $t = $callees->($c) or return 'a call of no sub the wire holds';
        for my $h (@$t) { return "$h hands \@_ on, takes a reference into it or stores through it" unless $args_read_only->($h) }
        my $mine = $own_my->( $g, $a );
        my $sym  = _fields($a)->{symbol} // '';
        my $s    = $name_of->( $g, $a );
        # (where perl pushed it, before the call: on the call's way back, with
        # nothing between that may store it)
        if ( $at != $c->{mem_in} ) {
            my ( $v, $k ) = ( $c->{mem_in}, 0 );
            $v = ( $by{$g}{$v} // {} )->{mem_in} while defined $v && $v != $at && $k++ < 100000;
            return 'read at a version its call does not follow' unless defined $v;
            my $why = $between->( $g, $c->{mem_in}, $at, $mine
                ? sub ($vn) {
                    my @named = grep { my $x = $by{$g}{$_}; !$x || $x->{op} eq 'PadAccess' && ( _fields($x)->{symbol} // '' ) eq $sym }
                        grep { defined && !ref } ( $vn->{inputs} // [] )->@*;
                    return 1 unless @named;
                    # (a sub call stores it only through a place it is handed,
                    # where a callee may store @_; a value handed is a copy)
                    return 0 unless $sub_call->($vn);
                    return 1 unless grep { !$by{$g}{$_} || _fields( $by{$g}{$_} )->{place} } @named;
                    my $t = $callees->($vn) or return 0;
                    return !grep { !$args_read_only->($_) } @$t;
                  }
                : sub ($vn) { $quiet->( $g, $vn, $s ) } );
            return "read before $why, which may store it" if defined $why;
        }
        return undef if $mine;
        for my $h (@$t) {
            my %args = map { ( $_->{id} => 1 ) } grep { $_->{op} eq 'ArgsSource' } values $by{$h}->%*;
            for my $r ( grep { defined $_->{mem_in} && grep { defined && !ref && $args{$_} } ( $_->{inputs} // [] )->@* } values $by{$h}->%* ) {
                my $why = $between->( $h, $r->{mem_in}, undef, sub ($vn) { $quiet->( $h, $vn, $s ) } );
                return "$h reads \@_ after $why, which may store it" if defined $why;
            }
        }
        return undef;
    };
    # (SoN::Promote hands each node it makes to the checker as it makes it:
    # a call's input it rewrote must name a node the checker knows -- one it
    # did not know read as nothing, and the pass and V14 answered differently)
    my $add = sub ( $g, $n ) { $by{$g}{ $n->{id} } = $n };
    return ( $private, $args_read_only, $add );
}

# all_graphs($wire) -> { name => graph }: the subs, and the BEGIN and END
# blocks (which call subs too), as SoN::Promote reads them.
sub all_graphs ($wire) {
    my %g = ( $wire->{methods} // {} )->%*;
    my $i = 0;
    $g{ 'phase#' . $i++ } = $_ for ( $wire->{phase_blocks} // [] )->@*;
    return \%g;
}


1;
