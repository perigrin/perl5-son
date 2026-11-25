# ABOUTME: Whether an alias may be carried as a value, decided over the whole wire: what each
# ABOUTME: node and each sub (through its calls) may store. Shared by SoN::Promote and SoN::Verify.
package SoN::AliasProof;
use v5.42.0;

# WHY ONE MODULE. The promotion pass (SoN::Promote) rewrites a place into a
# value where this says the alias is private, and the verifier (SoN::Verify,
# V13) asks the same question of every node the pass marked `promoted`. The
# proof is over the wire alone -- every graph of the program is there -- and
# never over how a store is spelled in the optree (audit 3, risk 1: `tr`
# where `=` was listed). A store is what the wire says writes memory: a node
# with `mem_out`, by its targets; a sub call, by what its subs store, closed
# over the wire; a call of no sub the wire holds, everything.
#
# A SOURCE is the storage an access names:
#   '$P::x'           a package scalar
#   'my:G:$x'         a `my` scalar in memory, of graph G (only G names it)
#   'cell:G:N'        a captured variable's cell (any call may store it)
#   'F:$x'            a class field
#   'agg:@P::a' 'agg:@G:a'   an aggregate, package or `my`
#   'elem:<agg>'      an element of it (any element: keys are not compared)
#   'R:scalar' 'R:array' 'R:hash'   one reached through a reference
#   'P'               an element of this sub's own @_ (an alias of the caller's)
# An EFFECT is a source a store may write, or 'any'.

sub new ( $class, $wire ) {
    my $m = $wire->{methods} // {};
    my %g = map { ( $_ => $m->{$_} ) } keys $m->%*;
    # (the BEGIN and END blocks call subs too)
    my $i = 0;
    $g{ 'phase#' . $i++ } = $_ for ( $wire->{phase_blocks} // [] )->@*;
    my $s = bless { wire => $wire, g => \%g, by => {}, cons => {} }, $class;
    for my $name ( keys %g ) {
        my %by = map { ( $_->{id} => $_ ) } ( $g{$name}{nodes} // [] )->@*;
        $s->{by}{$name} = \%by;
        my %cons;
        for my $n ( values %by ) {
            push $cons{$_}->@*, $n for grep { defined && !ref } ( $n->{inputs} // [] )->@*;
        }
        $s->{cons}{$name} = \%cons;
    }
    return $s;
}

sub graphs ($s)            { return sort keys $s->{g}->%* }
sub node ( $s, $g, $id )   { return defined $id && !ref $id ? $s->{by}{$g}{$id} : undef }
sub nodes ( $s, $g )       { return sort { $a->{id} <=> $b->{id} } values $s->{by}{$g}->%* }
sub consumers ( $s, $g, $n ) { return ( $s->{cons}{$g}{ $n->{id} } // [] )->@* }
sub _f ($n)                { return $n->{fields} // {} }
sub is_sub_call ($n)       { return $n->{op} eq 'Call' && ( _f($n)->{dispatch_kind} // '' ) ne 'builtin' }

# src($g, $n) -> the source an access node names (see above), or undef for a value.
sub src ( $s, $g, $n ) {
    return undef unless $n;
    my ( $op, $f ) = ( $n->{op}, _f($n) );
    my $sig = $f->{sigil} // '';
    if ( $op eq 'EntryDef' ) {
        my $name = ( $f->{package} // 'main' ) . "::$f->{symbol}";
        return $sig eq '$' ? '$' . $name : "agg:$sig$name";
    }
    if ( $op eq 'PadAccess' ) {
        return $sig eq q{$} ? "my|$g|\$$f->{symbol}" : "agg:$sig|$g|$f->{symbol}"
            unless $f->{shared};
        return $sig eq '$' ? "my:\$$f->{symbol}" : "agg:$sig$f->{symbol}";
    }
    return "agg:$f->{sigil}|$g|$f->{symbol}" if $op =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && defined $f->{symbol} && $f->{symbol} !~ /::/;
    # (a package aggregate's literal names it `@main::a`, its sigil in it)
    return 'agg:' . ( $f->{symbol} =~ /\A[\@%]/ ? $f->{symbol} : "$f->{sigil}$f->{symbol}" ) if $op =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && defined $f->{symbol};
    return 'cell:' . $g . ':' . ( $n->{inputs}[0] // '' ) if $op eq 'CellRead';
    return 'F:' . $sig . ( $f->{name} // $f->{symbol} // '' ) if $op eq 'FieldAccess';
    return 'P' if $op eq 'ArgsSource';
    if ( $op eq 'Subscript' ) {
        my $c = $s->node( $g, $n->{inputs}[0] );
        return 'P' if $c && $c->{op} eq 'ArgsSource';
        my $cs = $s->_container( $g, $c, $f->{kind} // 'array' );
        return $cs =~ /\AR:/ ? $cs : "elem:$cs";
    }
    if ( $op eq 'PostfixDeref' ) {
        my $r = $s->node( $g, $n->{inputs}[0] );
        return $s->src( $g, $s->node( $g, $r->{inputs}[0] ) ) // 'R:scalar' if $r && $r->{op} eq 'Ref' && $sig eq '$';
        return $sig eq '$' ? 'R:scalar' : $s->_container( $g, $n, $sig eq '%' ? 'hash' : 'array' );
    }
    return undef;
}

# _container($g, $c, $kind) -> an aggregate's source, or the class of one
# through a reference.
sub _container ( $s, $g, $c, $kind ) {
    return "R:$kind" unless $c;
    if ( $c->{op} eq 'Ref' ) { my $t = $s->node( $g, $c->{inputs}[0] ); my $k = $t ? $s->src( $g, $t ) : undef; return $k if defined $k && $k =~ /\Aagg:/ }
    if ( $c->{op} eq 'PostfixDeref' ) {
        my $r = $s->node( $g, $c->{inputs}[0] );
        if ( $r && $r->{op} eq 'Ref' ) { my $k = $s->src( $g, $s->node( $g, $r->{inputs}[0] ) ); return $k if defined $k && $k =~ /\Aagg:/ }
        return "R:$kind";
    }
    my $k = $s->src( $g, $c );
    return defined $k && $k =~ /\Aagg:/ ? $k : "R:$kind";
}

# referenced($g, $source) -> a reference may reach this source: a package or
# field one always; a `my` one where the wire takes a Ref of it, or a cell.
sub referenced ( $s, $source ) {
    return 1 unless $source =~ /\|/;    # (a package, field or shared one: any reference)
    $s->{refd} //= do {
        my %r;
        for my $g ( $s->graphs ) {
            for my $n ( grep { $_->{op} eq 'Ref' } values $s->{by}{$g}->%* ) {
                my $k = $s->src( $g, $s->node( $g, $n->{inputs}[0] ) );
                $r{$k} = 1 if defined $k;
            }
        }
        \%r;
    };
    return $s->{refd}{ $source =~ s/\Aelem://r } ? 1 : 0;
}

# effects($g, $n) -> what the memory version $n may store: [sources], or ['any'].
sub effects ( $s, $g, $n ) {
    return [] unless $n && ( $n->{mem_out} || $n->{op} =~ /\A(?:EntryWrite|CellWrite|Delete|ElemRestore)\z/ );
    if ( is_sub_call($n) ) {
        my $t = $s->callees( $g, $n ) or return ['any'];
        my %w;
        for my $h (@$t) { my $hw = $s->writes($h); return ['any'] if $hw->{any}; %w = ( %w, $hw->%* ) }
        return [ keys %w ];
    }
    my $op = $n->{op};
    my @t = $op eq 'Assign' ? ( _f($n)->{record} ? () : $n->{inputs}->@[ 0 .. ( _f($n)->{targets} // 1 ) - 1 ] )
          : $op =~ /\A(?:EntryWrite|CellWrite|Delete|ElemRestore)\z/ ? ( $n->{inputs}[0] )
          # (memory versions that store nothing a value is read from)
          : $op =~ /\A(?:Ref|MakeCell|Transliterate|RegexSubst|RegexMatch|Bless|Exc|Unwind|Return|MemStart|Phi|Loop|Region|Start|Subscript|PostfixDeref|Exists|Count|EntryDef|PadAccess|FieldAccess|CellRead|RefType|Coerce|Slice|Keys)\z/ ? ()   # (a read pinned where it stands is a version that stores nothing)
          : $op eq 'ArrayLiteral' ? ()
          : $op eq 'Call' && ( _f($n)->{name} // '' ) =~ /\A(?:bless|print|say|prtf|warn|die)\z/ ? ()
          : grep { defined && !ref } ( $n->{inputs} // [] )->@*;
    my @e;
    for my $t ( grep { defined && !ref } @t ) {
        my $tn = $s->node( $g, $t ) or next;
        my $k = $s->src( $g, $tn );
        if ( !defined $k ) {
            # (a captured cell, by its handle: any cell; any other target the
            # wire does not name: anything)
            if ( $tn->{op} =~ /\A(?:CellParam|MakeCell)\z/ ) { push @e, 'cell:'; next }
            next if $tn->{op} eq 'Constant';
            return ['any'];
        }
        push @e, $k;
        # (a store into an aggregate as a whole reaches its elements)
        push @e, "elem:$k" if $k =~ /\Aagg:/;
    }
    return \@e;
}

# callees($g, $call) -> [graph names] the call may run, or undef for one the
# wire cannot tell (a code value, a method of a name no sub has, a dynamic one).
sub callees ( $s, $g, $c ) {
    my ( $k, $name ) = ( _f($c)->{dispatch_kind} // '', _f($c)->{name} // '' );
    return $s->{g}{$name} ? [$name] : undef if $k eq 'direct';
    if ( $k eq 'method' ) { my @t = grep { /::\Q$name\E\z/ } keys $s->{g}->%*; return @t ? \@t : undef }
    return undef;
}

# writes($h) -> { source => 1 } a sub may store, through every call it makes
# (closed over the wire), or { any => 1 }.
sub writes ( $s, $h, $seen = {} ) {
    return $s->{writes}{$h} if $s->{writes}{$h};
    return {} if $seen->{$h}++;
    my %w;
    for my $n ( values $s->{by}{$h}->%* ) {
        if ( is_sub_call($n) ) {
            my $t = $s->callees( $h, $n ) or return $s->{writes}{$h} = { any => 1 };
            for my $c (@$t) { my $cw = $s->writes( $c, $seen ); return $s->{writes}{$h} = { any => 1 } if $cw->{any}; %w = ( %w, $cw->%* ) }
            next;
        }
        for my $e ( $s->effects( $h, $n )->@* ) {
            return $s->{writes}{$h} = { any => 1 } if $e eq 'any';
            # (a `my` of the callee's own is no one else's: not its caller's)
            next if $e =~ /\|\Q$h\E\|/;
            $w{$e} = 1;
        }
    }
    # (a sub's own @_ stores are its caller's variables: P stays P)
    return $s->{writes}{$h} = \%w;
}

# conflict($source, $effect) -> may a store to $effect reach $source?
sub conflict ( $s, $src, $e ) {
    return 1 if $e eq 'any' || $e eq $src || $e eq 'P';
    return 1 if $src =~ /\Acell:/;    # (a captured cell: any store we cannot name)
    my $kind = sub ($k) {
        return 'scalar' if $k =~ /\A(?:\$|my:|cell:|F:\$|R:scalar)/ || $k =~ /\Aelem:/;
        return $1 if $k =~ /\AR:(\w+)/;
        return $k =~ /\Aagg:\@/ ? 'array' : $k =~ /\Aagg:%/ ? 'hash' : '?';
    };
    # an element: its container stored as a whole, or one through a reference of its kind
    if ( $src =~ /\Aelem:(.*)\z/ ) {
        my $c = $1;
        return 1 if $e eq $c;
        return 1 if $c =~ /\AR:(\w+)/ && ( $e =~ /\AR:\Q$1\E/ || $e =~ /\Aelem:/ || $e =~ /\Aagg:/ );
        if ( $e =~ /\AR:(array|hash)\z/ ) {
            my $want = $1;
            return 0 unless ( $c =~ /\Aagg:\@/ ? 'array' : 'hash' ) eq $want;
            return $s->referenced($src);
        }
        return 0;
    }
    if ( $e eq 'R:scalar' ) { return $kind->($src) eq 'scalar' ? $s->referenced($src) : 0 }
    if ( $src eq 'R:scalar' ) { return $kind->($e) eq 'scalar' && $e !~ /\Aelem:/ ? $s->referenced($e) : 0 }
    return 0;
}

# args_escape($h) -> the sub hands @_ on, takes a reference into it, or stores
# through it: an argument it is passed is not private, wherever it reads it.
sub args_escape ( $s, $h ) {
    return $s->{escape}{$h} //= do {
        my $esc = 0;
        for my $n ( values $s->{by}{$h}->%* ) {
            next unless $n->{op} eq 'ArgsSource';
            for my $u ( $s->consumers( $h, $n ) ) {
                if ( $u->{op} eq 'Subscript' && ( $u->{inputs}[0] // -1 ) == $n->{id} ) {
                    # (an element of @_: read, fine; stored, referenced or handed on, not)
                    for my $v ( $s->consumers( $h, $u ) ) {
                        my $tgt = $v->{op} eq 'Assign' && !_f($v)->{record}
                            && grep { defined && !ref && $_ == $u->{id} } $v->{inputs}->@[ 0 .. ( _f($v)->{targets} // 1 ) - 1 ];
                        $esc = 1 if $tgt || $v->{op} =~ /\A(?:Ref|EntryWrite|Delete)\z/ || _f($u)->{place}
                            || $v->{mem_out} && grep { $_ eq 'P' } $s->effects( $h, $v )->@*;
                    }
                    next;
                }
                next if $u->{op} eq 'Assign' && _f($u)->{record};
                next if $u->{op} eq 'Count';
                $esc = 1;
            }
        }
        $s->{writes_args}{$h} = $esc;
        $esc;
    };
}

# arg_private($g, $call, $i) -> undef when the call's input $i, carried as a
# value, is private; else why not (a string). The input names its source.
sub arg_private ( $s, $g, $c, $i, $src = undef ) {
    my $a = $s->node( $g, $c->{inputs}[$i] ) or return 'no input';
    $src //= $s->src( $g, $a ) // return 'names no source';
    my $t = $s->callees( $g, $c ) or return 'a call of no sub the wire holds';
    for my $h (@$t) {
        return "$h hands \@_ on, takes a reference into it or stores through it" if $s->args_escape($h);
        # (each read of @_ at a version: $_[N], a shift, a list assign of it)
        my %args = map { ( $_->{id} => 1 ) } grep { $_->{op} eq 'ArgsSource' } values $s->{by}{$h}->%*;
        for my $r ( grep { defined $_->{mem_in} && grep { defined && !ref && $args{$_} } ( $_->{inputs} // [] )->@* } values $s->{by}{$h}->%* ) {
            my $why = $s->stored_between( $h, $r->{mem_in}, undef, $src );
            return "$h reads \@_ after $why" if $why;
        }
        # (a record of @_ reads it at entry: nothing between)
    }
    return undef;
}

# stored_between($g, $from, $to, $src) -> undef when no version on the memory
# chain back from $from (inclusive) to $to (exclusive; undef: the graph's
# MemStart) may store $src; else the node that may (a string).
sub stored_between ( $s, $g, $from, $to, $src ) {
    my ( @q, %seen ) = ($from);
    while ( defined( my $v = shift @q ) ) {
        next if $seen{$v}++;
        next if defined $to && $v == $to;
        my $vn = $s->node( $g, $v ) or next;
        next if $vn->{op} eq 'MemStart';
        for my $e ( $s->effects( $g, $vn )->@* ) {
            return "$vn->{op}#$v may store it ($e)" if $s->conflict( $src, $e );
        }
        push @q, $vn->{op} eq 'Phi' ? grep { defined && !ref } $vn->{inputs}->@* : grep { defined } $vn->{mem_in};
    }
    return undef;
}

1;
