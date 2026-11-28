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

# private_checker($wire) -> ( $private, $args_read_only, $add, $stores_nothing ):
#   $private->($g, $call, $i): undef where the call's input $i, a value, is
#     private by V14's rule, else why not;
#   $args_read_only->($sub): the sub's @_ is only read;
#   $add->($g, $node): a node made after the checker was (SoN::Promote's).
#   $stores_nothing->($sub): the sub stores nothing but its own `my` scalars.
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
            # (V14's own rule, Q10: an array index names an element only as
            # an Int literal >= 0, written as perl writes it -- `-2`, `0.5`,
            # `"0"` and `!1` may be element 0 -- a hash key only as a Str)
            my $v = $ix && $ix->{op} eq 'Constant' ? _fields($ix)->{value} : undef;
            my $st = $ix ? $ix->{stamp} // '' : '';
            my $named = !defined $v ? 0
                : $c =~ /\A(?:my)?%/ ? $st eq 'Str'
                : $st eq 'Int' && $v =~ /\A(?:0|[1-9][0-9]*)\z/;
            return "$c#" . ( $named ? $v : '*' );
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
    # $stores_nothing->($sub): V14'S RULE FOR A PARAMETER RECORD (fifth final
    # audit, vt59). The record binds each `my` to the argument as passed, an
    # alias; a store by the sub may reach one before the `my` is read. True
    # only where the sub stores nothing but its own `my` scalars, and calls
    # no sub and no builtin that is a version.
    # (a named scalar as an argument: a store of the sub reaches it only
    # through a reference or a closure, or, a package one, by its name --
    # V14's own reading of the whole wire)
    my %reachable;
    my $named_reachable = sub ($a) {
        my $f = _fields($a);
        return 1 if ( $f->{sigil} // '' ) ne '$' || $f->{shared};
        my $sym = $f->{symbol} // return 1;
        my $pkg = $a->{op} eq 'EntryDef' ? ( $f->{package} // 'main' ) : undef;
        return $reachable{ ( $pkg // 'my' ) . "\0$sym" } //= do {
            my $hit = 0;
            for my $g ( keys %by ) {
                for my $n ( values $by{$g}->%* ) {
                    if ( $n->{op} eq 'MakeCell' ) { $hit = 1 if ( _fields($n)->{cell_name} // '' ) =~ /\Q$sym\E\z/; next }
                    next unless $n->{op} eq 'Ref' || defined $pkg && $n->{op} =~ /\A(?:EntryWrite|Assign)\z/;
                    my $t = $by{$g}{ $n->{inputs}[0] // '' } or next;
                    $hit = 1 if ( _fields($t)->{symbol} // '' ) eq $sym && ( $n->{op} eq 'Ref' || $t->{op} eq 'EntryDef' );
                }
                last if $hit;
            }
            $hit;
        };
    };
    # (a sub's body stores: anything but its own `my` scalars, a call to a
    # sub whose body stores, or to code the wire cannot see; a cycle is
    # taken as storing nothing more than its members do)
    my %quiet_body;
    my $quiet_body;
    # (only an answer asked first is kept: one made inside a cycle assumed
    # its members quiet -- M36)
    $quiet_body = sub ( $h, $seen = undef ) {
        my $top = !$seen;
        $seen //= {};
        return $quiet_body{$h} if $top && defined $quiet_body{$h};
        return 1 if $seen->{$h}++;
        my $q = 1;
        for my $n ( values $by{$h}->%* ) {
            my $t = $n->{op} eq 'Assign' ? $by{$h}{ $n->{inputs}[0] // '' } : undef;
            next if $n->{op} eq 'Assign' && _fields($n)->{record};
            if ( $sub_call->($n) ) {
                my $t = $callees->($n);
                $q = 0, last unless $t && @$t && !grep { !$m->{$_} || !$quiet_body->( $_, $seen ) } @$t;
                next;
            }
            $q = 0, last
                if $n->{op} eq 'Assign' && !( $t && $t->{op} eq 'PadAccess' && ( _fields($t)->{sigil} // '' ) eq '$'
                                              && !_fields($t)->{place} && !_fields($t)->{shared} )
                || $n->{op} =~ $STORE_OP || $n->{op} eq 'Call' && $n->{mem_out};
        }
        return $top ? ( $quiet_body{$h} = $q ) : $q;
    };
    # (an element of a `my` aggregate of the caller's: reached by another
    # sub only through a reference to the aggregate or to an element, or a
    # closure -- an element of anything else may be)
    my $elem_reachable = sub ( $g, $a ) {
        my $c = $by{$g}{ $a->{inputs}[0] // '' } or return 1;
        my $f = _fields($c);
        return 1 unless $c->{op} =~ /\A(?:PadAccess|ArrayLiteral|HashLiteral)\z/ && defined $f->{symbol} && $f->{symbol} !~ /::/ && !$f->{shared};
        my $sym = $f->{symbol} =~ s/\A[\@%]//r;
        for my $h ( keys %by ) {
            for my $n ( values $by{$h}->%* ) {
                return 1 if $n->{op} eq 'MakeCell' && ( _fields($n)->{cell_name} // '' ) =~ /\Q$sym\E\z/;
                next unless $n->{op} eq 'Ref' || _fields($n)->{place};
                my $t = $n->{op} eq 'Ref' ? $by{$h}{ $n->{inputs}[0] // '' } : $n;
                $t = $by{$h}{ $t->{inputs}[0] // '' } if $t && $t->{op} =~ /\A(?:Subscript|Slice)\z/ && $n->{op} eq 'Ref';
                next unless $t;
                $t = $by{$h}{ $t->{inputs}[0] // '' } if $t->{op} eq 'Subscript';
                return 1 if $t && ( ( _fields($t)->{symbol} // '' ) =~ s/\A[\@%]//r ) eq $sym && $t->{op} =~ /\A(?:PadAccess|ArrayLiteral|HashLiteral)\z/;
            }
        }
        return 0;
    };
    my %stores_nothing;
    my $stores_nothing = sub ($h) {
        return $stores_nothing{$h} //= $quiet_body->($h)
            # (OR NO CALL HANDS IT AN ALIAS: every argument a value made at
            # the call -- a literal, a reference, arithmetic -- or a named
            # scalar nothing refers to, not an element, a dereference or a
            # choice among them)
            || ( !grep {
                my $g = $_;
                grep {
                    my $c = $_;
                    ( grep { $_ eq $h } ( $callees->($c) // [] )->@* )
                        && grep { my $a = $by{$g}{$_}; !$a || $a->{op} =~ /\A(?:PostfixDeref|TernaryExpr|Phi|CellRead|FieldAccess|Slice|ArgsSource)\z/
                               || $a->{op} =~ /\A(?:PadAccess|EntryDef)\z/ && $named_reachable->($a)
                               || $a->{op} eq 'Subscript' && $elem_reachable->( $g, $a ) }
                           grep { defined && !ref } ( $c->{inputs} // [] )->@*
                } grep { $sub_call->($_) } values $by{$g}->%*
            } keys %by ) ? 1 : 0;
    };
    return ( $private, $args_read_only, $add, $stores_nothing );
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
