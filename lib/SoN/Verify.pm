# ABOUTME: Checks a B::SoN wire (v2) against the memory-chain rules of the wire v2 plan
# ABOUTME: (section 8.1), and names each violation: node, kind, rule, graph.
package SoN::Verify;
use v5.42.0;
use B::SoN::EffectTable ();

# WHAT THIS IS. The audit of 2026-11-19 (docs/research/son-ir-audit-2026-11-19)
# found the memory model sound -- one chain from MemStart, each effectful node
# the next version, Phis where paths meet -- and unchecked: a write that is on
# the chain is there because one of ~120 hand-written sites put it there, and a
# write that is not is silently lost. This module is the check. It reads the
# decoded JSON wire, not the producer's graph objects and not a consumer's
# loaded graph: a consumer's loader has already dropped what floats.
#
# THE WIRE IS VERSION 2 (docs/plans/2026-11-20-wire-v2.md, section 3): memory is
# named -- a node's `mem_in` is the version it reads or follows, `mem_out` says
# it is a version -- not positional. Wire v1, and the rules only it needed
# (write-floating, effect-rides-value, fault-floating,
# package-scalar-loop-value, the place-or-read guess by input position), went
# with it in stage 6; a wire of another version is refused by name. The rules
# are section 8.1's, listed at _graph_v2 below.
#
# THE CLASSES OF read-unversioned:C, where the state a read sees lives:
# package, field, cell, through-ref, args, my-aggregate, my-shared,
# object-class (RefType, blessed), package-aggregate-literal (a package
# @x/%x flattened through its named literal), external (time, rand, -e,
# pos ...).
#
# ALLOWED, AND COUNTED (`allowed` in the result): a record Assign (V7's) whose
# targets are all SSA `my` scalars (`record`), or `my` aggregates bound from @_
# (`param-bind`).

# WHAT A BUILTIN WRITES, AND WHAT STATE ITS VALUE IS OF, is B::SoN::EffectTable's
# to say: the table the producer places by. This module kept lists of its own
# while the producer had none; two lists is one too many (and this one said
# `printf` where the wire says `prtf`, so a floating printf was never seen).

# verify($wire) -> { violations => [ { graph, node, op, rule, detail } ... ],
#                    allowed => { record => N, 'param-bind' => N }, graphs => N }
sub verify ($wire) {
    my %res = ( violations => [], allowed => {}, graphs => 0 );
    die "SoN::Verify: wire version " . ( $wire->{version} // 'none' ) . ": the rules are wire v2's\n"
        unless ( $wire->{version} // 0 ) == 2;
    # NO PROFILE (stage 10): it named the parts of v2 a wire obeyed while the
    # migration ran. Every part is v2; a wire that lists them is from before.
    die 'SoN::Verify: wire v2 `profile` ' . ( ref $wire->{profile} eq 'ARRAY' ? "[$wire->{profile}->@*]" : $wire->{profile} // 'null' )
        . ": a wire from before wire v2 closed (stage 10); every rule holds on every wire\n" if exists $wire->{profile};
    for my $name ( sort keys( ( $wire->{methods} // {} )->%* ) ) {
        $res{graphs}++;
        _graph_v2( $name, $wire->{methods}{$name}, \%res );
    }
    _alias_private( $wire, \%res );
    _promoted_private( $wire, \%res );
    return \%res;
}

# (V12) AN ALIAS CARRIED AS A VALUE IS PRIVATE (docs/plans/2026-11-24-aliases-as-places.md):
# a sub call's argument that is a read of a named variable at a version (not
# a `place`) must not be stored, in any callee the wire holds, before that
# callee reads @_ -- by its own store, or by a call whose subs (closed over
# the wire) store it or cannot be told. A call of no sub known here (a code
# value) is not checked. Alias-list items of a named variable are places
# always (B::SoN refuses a body that stores a scalar its list holds).
sub _alias_private ( $wire, $res ) {
    my $m = $wire->{methods} // {};
    my %by = map { my $g = $_; ( $g => { map { $_->{id} => $_ } ( $m->{$g}{nodes} // [] )->@* } ) } keys $m->%*;
    # src($g, $node) -> the variable an access names (an element: any of its container's), or undef
    my $src;
    $src = sub ( $g, $n ) {
        return undef unless $n;
        my ( $op, $f ) = ( $n->{op}, _fields($n) );
        return '$' . ( $f->{package} // 'main' ) . "::$f->{symbol}" if $op eq 'EntryDef' && ( $f->{sigil} // '' ) eq '$';
        return 'agg:' . ( $f->{sigil} // '' ) . ( $f->{package} ? "$f->{package}::" : '' ) . $f->{symbol} if $op eq 'EntryDef';
        return 'my:' . ( $f->{sigil} // '' ) . $f->{symbol} if $op eq 'PadAccess' && $f->{shared};
        return 'agg:' . ( $f->{sigil} // '' ) . $f->{symbol} if $op =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && defined $f->{symbol};
        if ( $op eq 'Subscript' ) { my $c = $src->( $g, $by{$g}{ $n->{inputs}[0] // '' } ); return defined $c ? "elem:$c" : undef }
        return undef;
    };
    # what each graph's own stores name, and the subs it calls (undef: one not known here)
    my $callees = sub ( $g, $c ) {
        my ( $k, $name ) = ( _fields($c)->{dispatch_kind} // '', _fields($c)->{name} // '' );
        return [ grep { $m->{$_} } $name ] if $k eq 'direct' && $m->{$name};
        if ( $k eq 'method' ) { my @t = grep { /::\Q$name\E\z/ } keys $m->%*; return @t ? \@t : undef }
        return undef;
    };
    # (A `local` IS A SAVE AND A RESTORE, by shape: a store to X that a later
    # store puts back with X read at the version before it. Both are of
    # another variable than the one $_[N] was bound to. shortcut: a value saved
    # and put back by hand has the same shape and is skipped too -- V12 then
    # misses a store the producer's own rule (ModSets::_is_local, by the op)
    # counts; upgrade when the wire marks a local's store.)
    my %localish;
    for my $g ( keys $m->%* ) {
        my @w = grep { $_->{op} eq 'EntryWrite' } values $by{$g}->%*;
        for my $r (@w) {
            my $v = $by{$g}{ $r->{inputs}[1] // '' } or next;
            my $k = $src->( $g, $by{$g}{ $r->{inputs}[0] // '' } ) // next;
            next unless $v->{op} eq 'EntryDef' && defined $v->{mem_in} && ( $src->( $g, $v ) // '' ) eq $k;
            my @save = grep { ( $_->{mem_in} // -1 ) == $v->{mem_in} && ( $src->( $g, $by{$g}{ $_->{inputs}[0] // '' } ) // '' ) eq $k } @w;
            next unless @save;
            $localish{$g}{ $_->{id} } = 1 for $r, @save;
        }
    }
    my %own;
    for my $g ( keys $m->%* ) {
        for my $n ( values $by{$g}->%* ) {
            # (a `local`'s save and its restore make and put back another
            # variable: $_[N] still names the one passed)
            next if _fields($n)->{local} || _fields($n)->{restore} || $n->{op} eq 'ElemRestore' || $localish{$g}{ $n->{id} };
            my @t = $n->{op} eq 'Assign' && !_fields($n)->{record} ? $n->{inputs}->@[ 0 .. ( _fields($n)->{targets} // 1 ) - 1 ]
                  : $n->{op} =~ /\A(?:EntryWrite|CellWrite|Delete|ElemRestore)\z/ ? ( $n->{inputs}[0] ) : ();
            for my $t ( grep { defined && !ref } @t ) { my $k = $src->( $g, $by{$g}{$t} ); $own{$g}{$k} = 1 if defined $k }
        }
    }
    my %writes;    # graph -> { key => 1 } transitively, or 'any'
    my $writes;
    $writes = sub ( $g, $seen = {} ) {
        return $writes{$g} if $writes{$g};
        return {} if $seen->{$g}++;
        my %w = ( $own{$g} // {} )->%*;
        for my $c ( grep { $_->{op} eq 'Call' && ( _fields($_)->{dispatch_kind} // '' ) ne 'builtin' } values $by{$g}->%* ) {
            my $t = $callees->( $g, $c ) or return $writes{$g} = { any => 1 };
            for my $h ( $t->@* ) { my $hw = $writes->( $h, $seen ); return $writes{$g} = { any => 1 } if $hw->{any}; %w = ( %w, $hw->%* ) }
        }
        return $writes{$g} = \%w;
    };
    # stores($g, $v, $key) -> the version $v of graph $g may store $key
    my $stores = sub ( $g, $v, $key ) {
        my $n = $by{$g}{$v} or return 0;
        if ( $n->{op} eq 'Call' && ( _fields($n)->{dispatch_kind} // '' ) ne 'builtin' ) {
            my $t = $callees->( $g, $n ) or return 1;
            return scalar grep { my $w = $writes->($_); $w->{any} || $w->{$key} } $t->@*;
        }
        return 0 if _fields($n)->{local} || _fields($n)->{restore} || $n->{op} eq 'ElemRestore' || $localish{$g}{$v};
        my @t = $n->{op} eq 'Assign' ? $n->{inputs}->@[ 0 .. ( _fields($n)->{targets} // 1 ) - 1 ]
              : $n->{op} =~ /\A(?:EntryWrite|CellWrite|Delete|ElemRestore)\z/ ? ( $n->{inputs}[0] ) : ();
        return scalar grep { defined && !ref && ( $src->( $g, $by{$g}{$_} ) // '' ) eq $key } @t;
    };
    for my $g ( sort keys $m->%* ) {
        for my $c ( sort { $a->{id} <=> $b->{id} } grep { $_->{op} eq 'Call' && ( _fields($_)->{dispatch_kind} // '' ) ne 'builtin' } values $by{$g}->%* ) {
            my $t = $callees->( $g, $c ) or next;
            for my $i ( 0 .. $#{ $c->{inputs} } ) {
                my $a = $by{$g}{ $c->{inputs}[$i] // '' } or next;
                next if _fields($a)->{place} || !defined $a->{mem_in};
                my $key = $src->( $g, $a ) // next;
                for my $h ( $t->@* ) {
                    my %args = map { $_->{id} => 1 } grep { $_->{op} eq 'ArgsSource' } values $by{$h}->%*;
                    # (each read of @_ at a version: $_[N], a shift, a list assign of it)
                    for my $r ( grep { defined $_->{mem_in} && grep { defined && !ref && $args{$_} } ( $_->{inputs} // [] )->@* } values $by{$h}->%* ) {
                        my ( @q, %seen ) = ( $r->{mem_in} );
                        while ( defined( my $v = shift @q ) ) {
                            next if $seen{$v}++;
                            my $vn = $by{$h}{$v} or next;
                            last if $vn->{op} eq 'MemStart' && !@q;
                            if ( $stores->( $h, $v, $key ) ) {
                                push $res->{violations}->@*, { graph => $g, node => $c->{id}, op => 'Call', rule => 'alias-not-private',
                                    detail => "argument $i ($key) is read by $h after $vn->{op}#$v may store it" };
                                @q = ();
                                last;
                            }
                            push @q, $vn->{op} eq 'Phi' ? grep { defined && !ref } $vn->{inputs}->@* : grep { defined } $vn->{mem_in};
                        }
                    }
                }
            }
        }
    }
    # THE ALIAS-LIST HALF (audit 2, K3): a foreach, map or grep's item read
    # per pass -- `Subscript [list, i]` at the loop's memory Phi, not a place
    # -- carried as a value must not be used after a store in that pass that
    # may reach the list (its own, or a call's whose subs store it or cannot
    # be told). Walked back along control from each use to the loop.
    for my $g ( sort keys $m->%* ) {
        my %cons;
        for my $n ( values $by{$g}->%* ) {
            push $cons{$_}->@*, $n for grep { defined && !ref } ( $n->{inputs} // [] )->@*;
        }
        for my $r ( sort { $a->{id} <=> $b->{id} } grep { $_->{op} eq 'Subscript' && !_fields($_)->{place} && defined $_->{mem_in} && !defined $_->{control_in} } values $by{$g}->%* ) {
            # (a pinned read is made where it stands, not carried)
            my $mphi = $by{$g}{ $r->{mem_in} } or next;
            my $loop = $by{$g}{ _fields($mphi)->{region} // '' } or next;
            next unless $mphi->{op} eq 'Phi' && _fields($mphi)->{memory} && $loop->{op} eq 'Loop';
            my $iphi = $by{$g}{ $r->{inputs}[1] // '' } or next;
            next unless $iphi->{op} eq 'Phi' && ( _fields($iphi)->{region} // -1 ) == $loop->{id};
            # (THE LOOP'S OWN ITEM: its test is `Count(list) > i` over this list
            # and index -- a foreach, map or grep. `$a[$i]` in a counted loop
            # over a range is an element read made where it stands.)
            next unless grep {
                my $t = $by{$g}{ $_->{inputs}[1] // '' } // {};
                my $cnt = $by{$g}{ $t->{inputs}[0] // '' } // {};
                $t->{op} eq 'NumGt' && ( $t->{inputs}[1] // -1 ) == $iphi->{id}
                    && $cnt->{op} eq 'Count' && ( $cnt->{inputs}[0] // -1 ) == ( $r->{inputs}[0] // -2 )
            } grep { $_->{op} eq 'If' && ( $_->{control_in} // -1 ) == $loop->{id} } values $by{$g}->%*;
            my $key = $src->( $g, $r ) // next;
            # (A `my` ARRAY OF THIS SUB'S OWN that it hands nothing a call
            # could reach it by -- no reference, not a call's argument -- no
            # call can store: only the graph's own stores are asked of it, as
            # the producer's _list_is_private answers)
            my $list = $by{$g}{ $r->{inputs}[0] // '' } // {};
            my $private = $list->{op} =~ /^(?:ArrayLiteral|HashLiteral)$/ && defined _fields($list)->{symbol}
                && _fields($list)->{symbol} !~ /::/ && !_fields($list)->{shared}
                && !grep { $_->{op} eq 'Ref' || $_->{op} eq 'Call' && ( _fields($_)->{dispatch_kind} // '' ) ne 'builtin' }
                       ( $cons{ $list->{id} } // [] )->@*;
            # (the uses that run: through pure values to a node on a chain)
            my ( @anchor, %seen );
            my @q = ( $cons{ $r->{id} } // [] )->@*;
            while ( my $u = shift @q ) {
                next if $seen{ $u->{id} }++;
                if ( defined $u->{control_in} || $u->{op} =~ /\A(?:Return|If|Region|Phi|Unwind)\z/ ) { push @anchor, $u; next }
                push @q, ( $cons{ $u->{id} } // [] )->@*;
            }
            ANCHOR: for my $u (@anchor) {
                # (a value Phi is used where control enters its region: at a
                # loop, by the pass's end, its back edge)
                my $rg = $u->{op} eq 'Phi' ? $by{$g}{ _fields($u)->{region} // '' } : undef;
                my ( @c, %cs ) = !$rg ? _control_preds($u)
                    : $rg->{op} eq 'Loop' ? grep { defined } $rg->{inputs}[1]
                    : _control_preds($rg);
                while ( defined( my $v = shift @c ) ) {
                    next if $cs{$v}++ || $v == $loop->{id};
                    my $vn = $by{$g}{$v} or next;
                    my $call = $vn->{op} eq 'Call' && ( _fields($vn)->{dispatch_kind} // '' ) ne 'builtin';
                    if ( !( $private && $call ) && ( $stores->( $g, $v, $key ) || $stores->( $g, $v, $key =~ s/\Aelem://r ) ) ) {
                        push $res->{violations}->@*, { graph => $g, node => $r->{id}, op => 'Subscript', rule => 'alias-not-private',
                            detail => "the per-pass item of $key is used by $u->{op}#$u->{id} after $vn->{op}#$v may store it" };
                        last ANCHOR;
                    }
                    push @c, _control_preds($vn);
                }
            }
        }
    }
    return;
}

# (V13) A PROMOTED NODE IS PRIVATE (design B, docs/plans/2026-11-25-places-everywhere.md):
# SoN::Promote made it from a place or a late read, and the proof it made it
# by is asked again here, of the wire as it left -- the pass is not trusted.
# P1: a call's argument is private (SoN::AliasProof::arg_private).
sub _promoted_private ( $wire, $res ) {
    require SoN::AliasProof;
    my $p = SoN::AliasProof->new($wire);
    for my $g ( $p->graphs ) {
        for my $c ( grep { SoN::AliasProof::is_sub_call($_) } $p->nodes($g) ) {
            for my $i ( 0 .. $#{ $c->{inputs} // [] } ) {
                my $a = $p->node( $g, $c->{inputs}[$i] ) or next;
                next unless ( $a->{fields} // {} )->{promoted};
                my $why = ( defined $a->{mem_in} && defined $c->{mem_in} && $a->{mem_in} == $c->{mem_in} ) ? $p->arg_private( $g, $c, $i )
                    : "read at another version than its call's";
                push $res->{violations}->@*, { graph => $g, node => $c->{id}, op => 'Call', rule => 'promoted-not-private',
                    detail => "argument $i: $why" } if defined $why;
            }
        }
    }
    return;
}

sub _fields ($n) { $n->{fields} // {} }

# _may_fault($n, \%by) -> a Divide or Modulo whose divisor is not a constant
# known not to be zero (through its coercions): perl dies there.
sub _may_fault ( $n, $by ) {
    my $d = $by->{ ( $n->{inputs} // [] )->[1] // '' } or return 1;
    $d = $by->{ $d->{inputs}[0] // '' } // return 1 while $d->{op} eq 'Coerce';
    return 1 unless $d->{op} eq 'Constant' && ( _fields($d)->{const_type} // '' ) =~ /\A(?:integer|number)\z/;
    my $v = _fields($d)->{value} // 0;
    return ( $n->{op} eq 'Modulo' ? int($v) : $v ) == 0 ? 1 : 0;
}

# The kinds that store whenever they run (the plan's 3.3: each a version).
# LocalAlias among them: after it a store to `$_` -- a callee's too -- is a
# store to the element it aliases (audit 2026-11-22: held out, it hid
# `for (@l) { f() } sub f { $_ = 9 }` leaving @l as it was).
my %WRITE = map { $_ => 1 } qw(EntryWrite CellWrite Delete ElemRestore MakeCell LocalAlias);


# The nodes control reaches $n from: a Region's every input; the first input
# of If, Loop and Proj; anything else's control_in.
sub _control_preds ($n) {
    my $in = $n->{inputs} // [];
    return grep { defined } @$in if $n->{op} eq 'Region';
    # (a Loop's back input is the pass's end: the Loop follows it)
    return grep { defined } @$in if $n->{op} eq 'Loop';
    my @p = $n->{op} =~ /^(?:If|Loop|Proj)$/ ? ( $in->[0] ) : ();
    push @p, $n->{control_in};
    return grep { defined } @p;
}

# What kind of place an Assign target is (the audit census's classes).
sub _target_class ($t) {
    return 'skip' unless $t;
    my ( $op, $f ) = ( $t->{op}, _fields($t) );
    return 'element' if $op eq 'Subscript';
    return 'slice'   if $op eq 'Slice';
    if ( $op eq 'PadAccess' ) {
        return 'my-aggregate' if ( $f->{sigil} // '$' ) ne '$';
        # (on v2 one kept in memory follows it: a mem_in, here or on another
        # read of it -- a record flag is B::SoN's claim, checked here, not trusted)
        return 'my-scalar-in-memory' if ( $t->{inputs} // [] )->@* || $f->{shared} || defined $t->{mem_in};
        return 'ssa-scalar';
    }
    return 'package-var'     if $op eq 'EntryDef';
    return 'through-ref'     if $op eq 'PostfixDeref';
    return 'field'           if $op eq 'FieldAccess';
    return 'capture-cell'    if $op =~ /^(?:MakeCell|CellRead|CellParam)$/;
    return 'named-aggregate' if $op =~ /^(?:ArrayLiteral|HashLiteral)$/;
    return 'skip'            if $op eq 'Constant';                           # `undef` in a list
    return "other:$op";
}

# A read, for a violation's detail: what it reads, as far as the wire names it.
sub _describe ( $n, $by ) {
    my $f = _fields($n);
    my $s = $n->{op};
    $s .= " $f->{name}" if $n->{op} eq 'Call';
    $s .= ' ' . ( $f->{sigil} // '' ) . $f->{symbol} if defined $f->{symbol};
    my $c = $by->{ ( $n->{op} eq 'Slice' ? $n->{inputs}[-1] : $n->{inputs}[0] ) // '' };
    $s .= ' of ' . $c->{op} . ( defined _fields($c)->{symbol} ? ' ' . ( _fields($c)->{sigil} // '' ) . _fields($c)->{symbol} : '' )
        if $c && $n->{op} ne 'Call';
    return $s;
}

# ---------------------------------------------------------------- wire v2
#
# THE RULES OF docs/plans/2026-11-20-wire-v2.md, section 8.1, on a wire whose
# `version` is 2: memory is named (`mem_in`, `mem_out`), not positional.
#
#   mem-in-not-version   V1: a mem_in, or an input of a memory Phi, names no
#                        version (MemStart, a memory Phi, a node with mem_out).
#   version-off-chain    V2: a node with mem_out lacks mem_in or control_in;
#                        or a Return, an Unwind, a sub Call or an Assign that
#                        is no record has no mem_in; or a write (a node of a
#                        kind that stores, a builtin EffectTable calls a
#                        version) is no version (no mem_out).
#   write-unreachable    V3: a node with mem_out the backward walk over
#                        mem_in and memory Phi inputs does not visit, from the
#                        roots (V4): each Return's and Unwind's mem_in, and
#                        the memory Phi of a Loop no exit Region names.
#   control-sink         V4: a pinned node no control follows that is no root
#                        (a Return, an Unwind) and no part of a loop's test.
#   memory-order-disagrees  V5: a pinned node's mem_in is not the nearest
#                        version back along its control chain.
#   read-unversioned:C   V6: a read of changeable state with no mem_in whose
#                        value is used -- by a node that runs, or one whose
#                        value reaches one (C: the classes above).
#   record               V7: a record Assign on a chain, or one whose targets
#                        are not `my` scalars (or `my` aggregates bound from @_).
#   phi-arity            V8: a Phi's inputs do not pair with its Region's
#                        control inputs (a Loop's Phi has two: way in, way round).
#                        An eval's join too: since stage 8 its catch is a
#                        way in like the body's end.
#   phi-no-region        a Phi whose `region` is no Region or Loop.
#   phi:memory-as-value  V8: a memory Phi used as a value input.
#   memory-as-value      (inputs are values only) MemStart used as a value
#                        input.
#   control-fork         V9: a node other than an If or a Loop has more than
#                        one control successor: two things claim to run next.
#   phi-trivial          V8 (stage 9b): a loop's Phi whose
#                        inputs other than itself are all one node.
#   loop                 V11 (stage 9a): a Loop has one or two inputs
#                        and one control successor, and no Proj takes it; a
#                        Phi at it has one input per input of it.
sub _graph_v2 ( $name, $g, $res ) {
    my @nodes = ( $g->{nodes} // [] )->@*;
    my %by    = map { $_->{id} => $_ } @nodes;
    my ( %cons, %succ );
    for my $n (@nodes) {
        my $in = $n->{inputs} // [];
        for my $i ( 0 .. $#$in ) {
            push $cons{$_}->@*, [ $n, $i ] for grep { defined } ref $in->[$i] ? $in->[$i]->@* : $in->[$i];
        }
        push $succ{$_}->@*, $n->{id} for _control_preds($n);
    }
    my $bad = sub ( $n, $rule, $detail ) {
        push $res->{violations}->@*,
            { graph => $name, node => $n->{id}, op => $n->{op}, rule => $rule, detail => $detail };
    };
    my $say = sub ($id) { my $x = $by{ $id // '' }; $x ? "$x->{op}#$id" : 'nothing' };
    my $memphi = sub ($n) { $n && $n->{op} eq 'Phi' && _fields($n)->{memory} };
    my $is_version = sub ($id) {
        my $x = $by{ $id // '' } or return 0;
        return $x->{op} eq 'MemStart' || $memphi->($x) || $x->{mem_out};
    };
    my $record = sub ($n) { $n->{op} eq 'Assign' && _fields($n)->{record} };
    # The `my` scalars this graph keeps in memory: some read of them names a
    # version, and no record binds the name (one kept in memory on one path
    # and bound as a value on another -- `($min, $max) = ...` in each arm of
    # an if, one of them a store -- is read either way; the wire has no pad
    # slot to tell two `my`s of one name apart, so such a name is left out).
    my %bound = map { my $n = $_; map { ( '$' . ( _fields( $by{$_} // {} )->{symbol} // '' ) => 1 ) } grep { defined && !ref } ( $n->{inputs} // [] )->@[ 0 .. ( _fields($n)->{targets} // 1 ) - 1 ] }
        grep { $record->($_) } @nodes;
    my %in_memory = map { ( '$' . _fields($_)->{symbol} => 1 ) }
        grep { $_->{op} eq 'PadAccess' && ( _fields($_)->{sigil} // '$' ) eq '$' && defined $_->{mem_in} && defined _fields($_)->{symbol} && !$bound{ '$' . _fields($_)->{symbol} } } @nodes;

    # (V9) ONE CONTROL SUCCESSOR, except for the two kinds that branch.
    for my $n (@nodes) {
        next if $n->{op} eq 'If' || $n->{op} eq 'Loop';
        my %s = map { $_ => 1 } ( $succ{ $n->{id} } // [] )->@*;
        next if keys %s < 2;
        $bad->( $n, 'control-fork', scalar( keys %s ) . ' successors: '
                . join( ', ', map { $say->($_) } sort { $a <=> $b } keys %s ) );
    }

    # (V1, V2) EDGES NAME VERSIONS; VERSIONS ARE ON BOTH CHAINS.
    for my $n (@nodes) {
        my ( $op, $f ) = ( $n->{op}, _fields($n) );
        $bad->( $n, 'mem-in-not-version', 'mem_in ' . $say->( $n->{mem_in} ) )
            if defined $n->{mem_in} && !$is_version->( $n->{mem_in} );
        if ( $memphi->($n) ) {
            $bad->( $n, 'mem-in-not-version', 'memory Phi input ' . $say->($_) )
                for grep { !$is_version->($_) } grep { defined } ( $n->{inputs} // [] )->@*;
        }
        if ( $n->{mem_out} ) {
            $bad->( $n, 'version-off-chain', 'a version with no ' . join ' or ', grep { !defined $n->{$_} } qw(mem_in control_in) )
                if !defined $n->{mem_in} || !defined $n->{control_in};
        }
        # (an :lvalue call an Assign stores through is that Assign's place:
        # the Assign is the version -- t/wire-v2-an-lvalue-call-target-is-no-version.t)
        elsif ( defined $n->{mem_in} && !$record->($n)
            && ( $op eq 'Assign' || $op eq 'Call' && ( $f->{dispatch_kind} // '' ) ne 'builtin'
                 && !grep { $_->[0]{op} eq 'Assign' && $_->[1] == 0 } ( $cons{ $n->{id} } // [] )->@* ) ) {
            $bad->( $n, 'version-off-chain', "a $op that follows memory and is no version" );
        }
        elsif ( !defined $n->{mem_in} && !$record->($n)
            && ( $op =~ /^(?:Return|Unwind|Assign)$/ || $op eq 'Call' && ( $f->{dispatch_kind} // '' ) ne 'builtin' ) ) {
            $bad->( $n, 'version-off-chain', "a $op that follows no memory" . ( $op eq 'Assign' ? ' and is no record' : '' ) );
        }
        # (a builtin that writes the world -- printf, unlink, srand -- is
        # ordered by control, as Print is, and follows memory: its
        # EffectTable `version` column says whether it is a version)
        elsif ( $WRITE{$op} || $op eq 'Call' && ( $f->{dispatch_kind} // '' ) eq 'builtin' && B::SoN::EffectTable::is_version( $f->{name} ) ) {
            $bad->( $n, 'version-off-chain', 'a write that is no memory version' . ( $op eq 'Call' ? " ($f->{name})" : '' ) );
        }
    }

    # (V2b) AN EFFECT RUNS WHERE IT STANDS: on the control chain. A Print, a
    # builtin the EffectTable pins in every context (or does not know: it may
    # write), a division that may fault. (v1's effect-rides-value and
    # fault-floating, deleted in stage 6 with nothing in their place: audit
    # 2026-11-22, M3, M6, M7, M11.)
    # (a place -- `pos($s) = 0`, an Assign's target -- is not run; nor is a
    # division whose value only an arm's merge takes: it runs in that arm)
    my $place = sub ($n) { grep { $_->[0]{op} eq 'Assign' && $_->[1] < ( _fields( $_->[0] )->{targets} // 1 ) } ( $cons{ $n->{id} } // [] )->@* };
    my $in_arm;
    $in_arm = sub ( $n, $d = 0 ) {
        $d < 8 && grep { $_->[0]{op} eq 'Phi' || $_->[0]{op} =~ /^(?:TernaryExpr|And|Or|DefinedOr)$/ && $_->[1] > 0
                         || $_->[0]{op} eq 'Coerce' && $in_arm->( $_->[0], $d + 1 ) } ( $cons{ $n->{id} } // [] )->@*;
    };
    for my $n ( grep { !defined $_->{control_in} } @nodes ) {
        next if $place->($n);
        my ( $op, $f ) = ( $n->{op}, _fields($n) );
        next if $op =~ /^(?:Divide|Modulo)$/ && $in_arm->($n);
        my $why = $op =~ /^(?:Print|Unwind|Return)$/ ? $op
            : $op eq 'Call' && ( $f->{dispatch_kind} // '' ) eq 'builtin'
                && ( B::SoN::EffectTable::on_chain( $f->{name} ) || B::SoN::EffectTable::is_version( $f->{name} )
                     || !B::SoN::EffectTable::known( $f->{name} ) ) ? "the builtin $f->{name}"
            : $op =~ /^(?:Divide|Modulo)$/ && _may_fault( $n, \%by ) ? "a $op that may fault"
            : undef;
        $bad->( $n, 'effect-floating', "$why on no control chain" ) if defined $why;
    }

    # (V3, V4) EVERY VERSION IS REACHED BACKWARDS FROM A ROOT.
    my @roots = map { $_->{mem_in} } grep { $_->{op} =~ /^(?:Return|Unwind)$/ && defined $_->{mem_in} } @nodes;
    my %exit_head = map { ( $_->{head} // -1 ) => 1 } grep { $_->{op} eq 'Region' } @nodes;
    for my $loop ( grep { $_->{op} eq 'Loop' && !$exit_head{ $_->{id} } } @nodes ) {
        push @roots, map { $_->{id} } grep { $memphi->($_) && ( _fields($_)->{region} // -1 ) == $loop->{id} } @nodes;
    }
    my %seen;
    my @q = grep { defined } @roots;
    while ( defined( my $id = shift @q ) ) {
        next if $seen{$id}++;
        my $x = $by{$id} or next;
        push @q, $x->{mem_in} if defined $x->{mem_in};
        push @q, grep { defined } ( $x->{inputs} // [] )->@* if $memphi->($x);
    }
    $bad->( $_, 'write-unreachable', 'no Return or Unwind reaches it backwards' ) for grep { $_->{mem_out} && !$seen{ $_->{id} } } @nodes;
    # A pinned node nothing follows is an end: a root, or a fault.
    for my $n ( grep { defined $_->{control_in} && $_->{op} !~ /^(?:Return|Unwind)$/ } @nodes ) {
        next if ( $succ{ $n->{id} } // [] )->@*;
        $bad->( $n, 'control-sink', 'nothing follows it' );
    }

    # (V5) THE TWO ORDERINGS AGREE: a pinned node's mem_in is the nearest
    # version back along its control chain (at a Region or a Loop, its memory
    # Phi, else the way in's).
    my %region_mem;
    for my $p ( grep { $memphi->($_) } @nodes ) { $region_mem{ _fields($p)->{region} // -1 } //= $p->{id} }
    my $back = sub ($p) {
        for ( 1 .. 100000 ) {
            my $pn = $by{ $p // '' } or return undef;
            my $op = $pn->{op};
            if ( $op eq 'Start' ) {
                my ($ms) = grep { $_->{op} eq 'MemStart' } @nodes;
                return $ms ? $ms->{id} : undef;
            }
            return $p if $pn->{mem_out};
            if    ( $op eq 'Region' || $op eq 'Loop' ) { return $region_mem{$p} if exists $region_mem{$p}; $p = $pn->{inputs}[0] }
            elsif ( $op eq 'Proj' )                    { $p = $pn->{inputs}[0] }
            elsif ( $op eq 'If' )                      { $p = $pn->{control_in} // $pn->{inputs}[0] }
            else                                       { $p = $pn->{control_in} }
        }
        return undef;
    };
    for my $n ( grep { defined $_->{control_in} && defined $_->{mem_in} } @nodes ) {
        my $exp = $back->( $n->{control_in} ) // next;
        next if $exp == $n->{mem_in};
        $bad->( $n, 'memory-order-disagrees', 'mem_in ' . $say->( $n->{mem_in} ) . ', control says ' . $say->($exp) );
    }

    # (V6) READS NAME A VERSION, unless every use is a place use.
    my $name_of = sub ($n) {
        return undef unless $n && $n->{op} =~ /^(?:PadAccess|ArrayLiteral|HashLiteral)$/;
        my $f = _fields($n);
        return defined $f->{symbol} ? ( $f->{sigil} // '' ) . $f->{symbol} : undef;
    };
    my $container = sub ($n) { $by{ ( $n->{op} eq 'Slice' ? $n->{inputs}[-1] : $n->{inputs}[0] ) // '' } };
    # WHAT IS USED: a value reaches something that runs -- a node on the
    # control chain, a control node, a Return -- through inputs, mem_in and a
    # Phi's region. A read only a dead node takes (a loop scout's leftover
    # condition) is not used.
    my %live;
    {
        # (A RECORD IS USED WHERE ITS TARGET IS: `my ($p) = @_` fills $p, and
        # a read of $p reads what the record read -- audit 2, K1.)
        my %record_of;
        for my $r ( grep { $record->($_) } @nodes ) {
            push $record_of{$_}->@*, $r->{id} for grep { defined && !ref } ( $r->{inputs} // [] )->@[ 0 .. ( _fields($r)->{targets} // 1 ) - 1 ];
        }
        my @q = map { $_->{id} } grep { defined $_->{control_in} || $_->{op} =~ /^(?:Start|Return|Unwind|Region|If|Loop|Proj)$/ } @nodes;
        while ( defined( my $id = shift @q ) ) {
            next if $live{$id}++;
            push @q, ( $record_of{$id} // [] )->@*;
            my $x = $by{$id} or next;
            push @q, grep { defined && !ref } ( $x->{inputs} // [] )->@*;
            push @q, map { ref $_ ? @$_ : () } ( $x->{inputs} // [] )->@*;
            push @q, grep { defined } $x->{mem_in}, $x->{control_in}, _fields($x)->{region};
        }
    }
    # AN ALIAS LIST -- the list a foreach, map or grep walks, whose items are
    # the variables or elements themselves -- is used only as a container
    # (its per-pass Subscript, its Count): an item of it is a place too.
    # Only the ITEM is excused: the per-pass read of it names its version.
    my ( %alias_list, $is_place_use );
    $is_place_use = sub ( $c, $i ) {
        my ( $op, $f ) = ( $c->{op}, _fields($c) );
        # (so is a merge of an aggregate's bindings -- `@l = @n` in an arm, a
        # Phi or a ?: of the two -- that is only a container after the join)
        if ( $op eq 'ArrayLiteral' && !defined $f->{symbol} || $op eq 'Phi' && !$f->{memory} || $op eq 'TernaryExpr' && $i > 0 ) {
            return $alias_list{ $c->{id} } if exists $alias_list{ $c->{id} };
            $alias_list{ $c->{id} } = 0;
            my @u = grep { $live{ $_->[0]{id} } } ( $cons{ $c->{id} } // [] )->@*;
            return $alias_list{ $c->{id} } = ( @u && !grep { !$is_place_use->(@$_) } @u ) ? 1 : 0;
        }
        return $i < ( $f->{targets} // 1 ) if $op eq 'Assign';
        # (a control node's control predecessor -- an alias list made where it
        # stands, as one that makes an element exist is -- is no value use)
        return 1 if $op =~ /^(?:Loop|Region|Proj)$/ || $op eq 'If' && $i == 0;
        return $i == $#{ $c->{inputs} } if $op eq 'Slice';
        return 1 if $op eq 'Call' && ( ( $f->{dispatch_kind} // '' ) ne 'builtin' || defined $c->{mem_in} );
        # (pos() names the variable whose position it is, not its value)
        return 1 if $op eq 'Call' && ( B::SoN::EffectTable::reads_state( $f->{name} ) // '' ) eq 'variable';
        return 1 if $op =~ /^(?:AnonSub|RegexSubst|Transliterate|Chomp)$/;
        return $i == 0
            if $op =~ /^(?:Subscript|Exists|Delete|Count|PostfixDeref|ElemRestore|Ref|LocalAlias|VarDecl|MakeCell|CellRead|EntryWrite|CellWrite)$/;
        return 0;
    };
    my %mutated;
    for my $n (@nodes) {
        my ( $op, $f, $in ) = ( $n->{op}, _fields($n), $n->{inputs} // [] );
        # (a record is a binding -- a `my (...) = @_` filling its targets as
        # the sub starts -- not a store a read could be on either side of)
        next if $record->($n);
        my @written =
              $op eq 'Assign' ? @$in[ 0 .. ( $f->{targets} // 1 ) - 1 ]
            : $op eq 'Call' ? ( ( $f->{dispatch_kind} // '' ) ne 'builtin' || B::SoN::EffectTable::writes( $f->{name} ) ? @$in : () )
            : $op =~ /^(?:Ref|LocalAlias|Delete|ElemRestore|MakeCell|EntryWrite|CellWrite|Chomp)$/ ? ( $in->[0] )
            : $op =~ /^(?:AnonSub|RegexSubst|Transliterate)$/ ? @$in
            :                                                   ();
        for my $t ( map { $by{$_} } grep { defined && !ref } @written ) {
            $t = $container->($t) while $t && $t->{op} =~ /^(?:Subscript|Slice)$/;
            my $k = $name_of->($t);
            $mutated{$k} = 1 if defined $k;
        }
    }
    # (A GRAPH THAT STORES INTO AN ELEMENT OF @_ -- a caller's variable --
    # changes what @_ holds after a copy of it: there a record of @_ has no
    # version to be made at -- audit 2, K1. Whether a caller hands a sub
    # places otherwise (it reads @_ after a store, or a call no one sees into
    # may be its call) is the producer's question, ModSets::args_may_be_places;
    # a wire does not say.)
    my $stores_beyond_own = grep {
        my ( $op, $f, $in ) = ( $_->{op}, _fields($_), $_->{inputs} // [] );
        $_->{mem_out} && !$record->($_) && grep {
            my ( $t, $elem ) = ( $by{$_}, 0 );
            ( $t, $elem ) = ( $container->($t), 1 ) while $t && $t->{op} =~ /^(?:Subscript|Slice)$/;
            $elem && $t && $t->{op} eq 'ArgsSource'
        } grep { defined && !ref } ( $op eq 'Assign' ? @$in[ 0 .. ( $f->{targets} // 1 ) - 1 ] : $op eq 'Call' ? @$in : () );
    } @nodes;
    my $place_class;
    $place_class = sub ($n) {
        return undef unless $n;
        my ( $op, $f ) = ( $n->{op}, _fields($n) );
        return 'package'     if $op eq 'EntryDef';
        return 'field'       if $op eq 'FieldAccess';
        return 'cell'        if $op =~ /^(?:CellRead|CellParam|MakeCell)$/;
        return 'through-ref' if $op eq 'PostfixDeref';
        return 'args'        if $op eq 'ArgsSource';
        if ( $op eq 'PadAccess' && ( $f->{sigil} // '$' ) eq '$' ) {
            return 'my-shared' if $f->{shared};
            # (a `my` scalar another read of names a version is kept in memory)
            return $in_memory{ '$' . ( $f->{symbol} // '' ) } ? 'my-in-memory' : undef;
        }
        if ( defined( my $k = $name_of->($n) ) ) {
            return 'package' if $op ne 'PadAccess' && $f->{symbol} =~ /::/;
            return $mutated{$k} ? 'my-aggregate' : undef;
        }
        return undef if $op =~ /^(?:ArrayLiteral|HashLiteral|Constant|Range)$/;
        if ( $op =~ /^(?:Subscript|Slice|Count)$/ ) {
            my $c = $container->($n) or return undef;
            return 'through-ref' if $c->{op} =~ /^(?:Subscript|Slice)$/;
            return 'through-ref' if $c->{op} eq 'PadAccess' && ( _fields($c)->{sigil} // '$' ) eq '$';
            return $place_class->($c);
        }
        return ( $n->{stamp} // '' ) =~ /^(?:Array|List|Hash)$/ ? undef : 'through-ref';
    };
    # (a place -- fields.place, aliases-as-places -- is storage, not a read:
    # L10 and V12 hold it)
    for my $n ( grep { !defined $_->{mem_in} && !_fields($_)->{place} } @nodes ) {
        my ( $op, $f ) = ( $n->{op}, _fields($n) );
        my $class;
        # (a list slice, `(f())[0]`, picks from values: index_count says so)
        next if $op eq 'Slice' && defined $f->{index_count};
        if    ( $op =~ /^(?:Subscript|Slice|Count|PostfixDeref|CellRead|EntryDef|PadAccess|FieldAccess)$/ ) { $class = $place_class->($n) }
        elsif ( $op eq 'RefType' ) { $class = 'object-class' }
        # (@_ WHOLE, COPIED BY A RECORD: the record has no version, so its
        # targets take @_ whenever they are first read -- audit 2, K1. Other
        # whole reads of @_ are a consumer's that names its own version.)
        elsif ( $op eq 'ArgsSource' ) {
            $class = 'args' if $stores_beyond_own && grep { $live{ $_->[0]{id} } && $record->( $_->[0] ) } ( $cons{ $n->{id} } // [] )->@*;
        }
        elsif ( $op eq 'Call' && ( $f->{dispatch_kind} // '' ) eq 'builtin' ) { $class = B::SoN::EffectTable::reads_state( $f->{name} ) }
        # (A PACKAGE SCALAR IN AN ALIAS LIST is no place: the list is made
        # where it stands, and the variable is read there -- final audit 4.7,
        # class E. Its item names the version, as any read does.)
        my $scalar_entry = $op eq 'EntryDef' && ( $f->{sigil} // '' ) eq '$';
        next unless $class && grep {
            $live{ $_->[0]{id} } && ( !$is_place_use->(@$_)
                || $scalar_entry && $_->[0]{op} =~ /^(?:ArrayLiteral|Phi|TernaryExpr)$/ )
        } ( $cons{ $n->{id} } // [] )->@*;
        # (a list assign's target is the node later reads are: its value is
        # that Assign's, a version -- `my ($b, $d) = f(); length $b`)
        next if $class eq 'my-in-memory' && grep { $_->[0]{op} eq 'Assign' && $_->[1] < ( _fields( $_->[0] )->{targets} // 1 ) && $_->[0]{mem_out} } ( $cons{ $n->{id} } // [] )->@*;
        $bad->( $n, "read-unversioned:$class", _describe( $n, \%by ) );
    }
    for my $n ( grep { $_->{op} =~ /^(?:ArrayLiteral|HashLiteral)$/ && ( _fields($_)->{symbol} // '' ) =~ /::/ } @nodes ) {
        my @uses = grep { $live{ $_->[0]{id} } && !( $_->[0]{op} eq "EntryWrite" && $_->[1] == 1 ) && !$is_place_use->(@$_) } ( $cons{ $n->{id} } // [] )->@*;
        $bad->( $n, 'read-unversioned:package-aggregate-literal',
            _fields($n)->{symbol} . ' read by ' . join( ',', map { "$_->[0]{op}#$_->[0]{id}" } @uses ) ) if @uses;
    }

    # (V7) A RECORD IS A BINDING: on no chain, of `my` variables.
    for my $n ( grep { $record->($_) } @nodes ) {
        my $f = _fields($n);
        if ( grep { defined $n->{$_} } qw(control_in mem_in mem_out) ) {
            $bad->( $n, 'record', 'a record on a chain' );
            next;
        }
        my $in = $n->{inputs} // [];
        my %c = map { _target_class( $by{ $_ // '' } ) => 1 } @$in[ 0 .. ( $f->{targets} // 1 ) - 1 ];
        my @mem = grep { $_ ne 'ssa-scalar' && $_ ne 'skip' } sort keys %c;
        my $args = ( ( $by{ $in->[-1] // '' } // {} )->{op} // '' ) eq 'ArgsSource';
        if    ( !@mem )                                  { $res->{allowed}{record}++ }
        elsif ( $args && "@mem" eq 'my-aggregate' )      { $res->{allowed}{'param-bind'}++ }
        else                                             { $bad->( $n, 'record', 'a record of ' . join( '+', @mem ) ) }
    }

    # (V11) A LOOP IS ENTERED ONCE AND GOES ROUND ONCE; ITS TEST IS AN If.
    for my $L ( grep { $_->{op} eq 'Loop' } @nodes ) {
        my $k = scalar( ( $L->{inputs} // [] )->@* );
        $bad->( $L, 'loop', "$k inputs (one or two)" ) if $k < 1 || $k > 2;
        my %u;
        my @s = grep { $by{$_}{op} ne 'Proj' && !$u{$_}++ } ( $succ{ $L->{id} } // [] )->@*;
        $bad->( $L, 'loop', scalar(@s) . ' control successors' ) if @s > 1;
        $bad->( $L, 'loop', 'a Proj of it: ' . join ', ', map { $say->($_) } @{ [ grep { $by{$_}{op} eq 'Proj' } ( $succ{ $L->{id} } // [] )->@* ] } )
            if grep { $by{$_}{op} eq 'Proj' } ( $succ{ $L->{id} } // [] )->@*;
    }

    # (V8) PHIS PAIR WITH THEIR REGION; MEMORY AND VALUES DO NOT MIX.
    for my $n ( grep { $_->{op} eq 'Phi' } @nodes ) {
        my $f = _fields($n);
        my $r = $by{ $f->{region} // '' };
        if ( !$r || $r->{op} !~ /^(?:Region|Loop)$/ ) { $bad->( $n, 'phi-no-region', 'region=' . ( $f->{region} // 'none' ) ); next }
        my $want = $r->{op} eq 'Loop' ? scalar $r->{inputs}->@* : scalar grep { defined } $r->{inputs}->@*;
        my $have = scalar( $n->{inputs}->@* );
        $bad->( $n, 'phi-arity',
            "$have inputs for $want ways into $r->{op}#$r->{id}" . ( $f->{memory} ? ' (memory)' : '' ) )
            if $have != $want;
        # (stage 9b, Braun: a loop's Phi the pass never wrote -- its inputs
        # but itself all one node -- is forwarded, not written)
        if ( $r->{op} eq 'Loop' ) {
            my %v = map { ( $_ => 1 ) } grep { defined && $_ != $n->{id} } $n->{inputs}->@*;
            $bad->( $n, 'phi-trivial', 'a loop Phi of ' . ( keys %v ? $say->( ( keys %v )[0] ) : 'nothing' ) . ' alone' )
                if keys %v < 2;
        }
        if ( $f->{memory} ) {
            my @v = grep { !$memphi->( $_->[0] ) } ( $cons{ $n->{id} } // [] )->@*;
            $bad->( $n, 'phi:memory-as-value', 'used by ' . join( ',', map { "$_->[0]{op}#$_->[0]{id}" } @v ) ) if @v;
        }
    }
    # (V10) AN EVAL'S WAYS OUT. Each thing in an eval's body that may die --
    # a sub call, a die, what B::SoN pinned because it may fault -- has its
    # Exc, and the way out from it puts back every `local` the body's own end
    # puts back that was made before it. (Never written in stage 8: audit
    # 2026-11-22, M8, M9.)
    {
        my %join = map { ( _fields($_)->{eval_id} => $_ ) }
            grep { $_->{op} eq 'Region' && defined _fields($_)->{eval_id} && !_fields($_)->{catch} } @nodes;
        my %exc_of = map { ( $_->{inputs}[0] // -1 ) => $_ } grep { $_->{op} eq 'Exc' } @nodes;
        for my $t (@nodes) {
            my $e = _fields($t)->{eval_id};
            next unless defined $e && $join{$e} && defined $t->{control_in};
            next unless $t->{op} eq 'Unwind' || $t->{op} eq 'Call' && ( _fields($t)->{dispatch_kind} // '' ) ne 'builtin';
            $bad->( $t, 'exc', "it may die in eval $e and has no way out to its catch" ) unless $exc_of{ $t->{id} };
        }
        # (the nodes a control path from $from reaches before a catch, or before $stop)
        my $path = sub ( $from, $stop ) {
            my ( @q, %s ) = ($from);
            while ( defined( my $id = shift @q ) ) {
                next if $s{$id}++ || $id == $stop;
                my $x = $by{$id} or next;
                next if $x->{op} eq 'Region' && ( _fields($x)->{catch} || defined _fields($x)->{eval_id} );
                push @q, ( $succ{$id} // [] )->@*;
            }
            return \%s;
        };
        my $sym = sub ($x) { my $f = _fields( $x // {} ); join ':', map { $_ // '' } $f->@{qw(package sigil symbol)} };
        # A RESTORE: an EntryWrite storing back the value its target held -- an
        # EntryDef of the same name read at an earlier version (the save).
        # (or, design B section 4, binding the name back to the scalar it had:
        # a Ref of that read, the save of a `local` of a named scalar)
        my $in = sub ($x) { $x && $x->{op} eq 'Ref' ? $by{ $x->{inputs}[0] // '' } : $x };
        my @restores = grep {
            my $s = $in->( $by{ $_->{inputs}[1] // '' } );
            $_->{op} eq 'EntryWrite' && $s && $s->{op} eq 'EntryDef' && defined $s->{mem_in}
                && $sym->( $by{ $_->{inputs}[0] // '' } ) eq $sym->($s)
        } @nodes;
        # (V10, design B1) A WAY OUT WITH NO EVAL: outside every eval of the
        # graph, a sub call or what B::SoN pinned because it may fault, made
        # where a `local` is live (its store reached back along control before
        # its restore), has an Exc whose edge puts that local back and ends in
        # an Unwind marked rethrow; every such Exc ends so, and every rethrow
        # is of its own edge's Exc.
        {
            my %pred;    # control predecessors
            for my $y (@nodes) {
                my @p = defined $y->{control_in} ? ( $y->{control_in} ) : ();
                push @p, grep { defined && !ref } $y->{inputs}->@* if $y->{op} =~ /^(?:Region|Loop)$/;
                push @p, $y->{inputs}[0] if $y->{op} =~ /^(?:If|Proj)$/ && defined $y->{inputs}[0];
                $pred{ $y->{id} } = \@p;
            }
            my %edge_node = map { %{ $path->( $_->{id}, -1 ) } } values %exc_of;
            my @pairs;    # [ local store, its save, its restore ] off every edge
            for my $r ( grep { !$edge_node{ $_->{id} } } @restores ) {
                my $save = $by{ $r->{inputs}[1] };
                my ($local) = grep { $_->{op} eq 'EntryWrite' && ( $_->{mem_in} // -1 ) == $in->($save)->{mem_in} && $sym->( $by{ $_->{inputs}[0] // '' } ) eq $sym->( $in->($save) ) } @nodes;
                push @pairs, [ $local, $save, $r ] if $local;
            }
            my $in_eval = sub ($t) { my $e = _fields($t)->{eval_id}; defined $e && $join{$e} };
            # (an Exc is an eval's by where its edge goes, into a catch: a die
            # in a sort block inlined in an eval carries no eval_id)
            my %into_catch = map { ( $_ => 1 ) } grep { defined && !ref } map { $_->{inputs}->@* }
                grep { $_->{op} eq 'Region' && _fields($_)->{catch} } @nodes;
            my $to_catch = sub ($x) { grep { $into_catch{$_} } keys %{ $path->( $x->{id}, -1 ) } };
            my $may_die = sub ($t) {
                return 0 unless defined $t->{control_in} && !$in_eval->($t) && !$edge_node{ $t->{id} };
                return 0 if $exc_of{ $t->{id} } && $to_catch->( $exc_of{ $t->{id} } );
                return 1 if $t->{op} eq 'Call' && ( _fields($t)->{dispatch_kind} // '' ) ne 'builtin';
                return $t->{op} =~ /^(?:Divide|Modulo|PostfixDeref|Ref)$/ && defined _fields($t)->{line} ? 1 : 0;
            };
            for my $t ( grep { $may_die->($_) } @nodes ) {
                my @live;
                for my $pr (@pairs) {
                    my ( $local, $save, $r ) = @$pr;
                    # (back to the local, not through a restore of it: the
                    # one paired, or another -- a loop pass's end, an arm's)
                    my %put_back = map { ( $_->{id} => 1 ) } grep { ( $_->{inputs}[1] // -1 ) == $save->{id} } @restores;
                    my ( @q, %s ) = ( $pred{ $t->{id} }->@* );
                    while ( defined( my $id = shift @q ) ) {
                        next if $s{$id}++ || $put_back{$id};
                        if ( $id == $local->{id} ) { push @live, $save; last }
                        push @q, ( $pred{$id} // [] )->@*;
                    }
                }
                next unless @live;
                my $x = $exc_of{ $t->{id} };
                my $p = $x ? $path->( $x->{id}, -1 ) : {};
                $bad->( $t, 'exc', 'it may die under a live local, outside an eval, and has no way out' ), next unless $x;
                for my $save (@live) {
                    $bad->( $x, 'exc', 'its way out does not put back the local of ' . $sym->( $in->($save) ) )
                        unless grep { $p->{ $_->{id} } && ( $_->{inputs}[1] // -1 ) == $save->{id} } @restores;
                }
            }
            for my $x ( grep { !$to_catch->($_) } values %exc_of ) {
                my $p = $path->( $x->{id}, -1 );
                $bad->( $x, 'exc', 'an Exc outside an eval whose way out ends in no rethrow' )
                    unless grep { $p->{ $_->{id} } && $_->{op} eq 'Unwind' && _fields($_)->{rethrow} && ( $_->{inputs}[0] // -1 ) == $x->{id} } @nodes;
            }
            for my $u ( grep { $_->{op} eq 'Unwind' && _fields($_)->{rethrow} } @nodes ) {
                my $x = $by{ $u->{inputs}[0] // '' };
                $bad->( $u, 'exc', 'a rethrow not of its own edge\'s Exc' )
                    unless $x && $x->{op} eq 'Exc' && $path->( $x->{id}, -1 )->{ $u->{id} };
            }
        }
        for my $e ( sort keys %join ) {
            my $j = $join{$e};
            my $entry = _fields($j)->{eval_entry} // next;
            my @exc = grep { ( _fields( $by{ $_->{inputs}[0] // '' } // {} )->{eval_id} // '' ) eq $e } values %exc_of;
            my %on_exc = map { %{ $path->( $_->{id}, -1 ) } } @exc;
            my $body = $path->( $entry, $j->{id} );
            for my $r ( grep { $body->{ $_->{id} } && !$on_exc{ $_->{id} } } @restores ) {
                my $save = $by{ $r->{inputs}[1] };
                my ($local) = grep { $_->{op} eq 'EntryWrite' && ( $_->{mem_in} // -1 ) == $in->($save)->{mem_in} && $sym->( $by{ $_->{inputs}[0] // '' } ) eq $sym->( $in->($save) ) } @nodes;
                next unless $local;
                # (a restore of it met first, going back, put it back: an inner
                # block's local, closed before the thrower -- audit 2, un75)
                my %put_back = map { ( $_->{id} => 1 ) } grep { ( $_->{inputs}[1] // -1 ) == $save->{id} } @restores;
                for my $x (@exc) {
                    # (the thrower comes after the local: back along memory from it)
                    my ( $m, $after ) = ( $by{ $x->{inputs}[0] }{mem_in}, 0 );
                    for ( 1 .. 100000 ) { last if !defined $m || $put_back{$m}; if ( $m == $local->{id} ) { $after = 1; last } $m = ( $by{$m} // {} )->{mem_in} }
                    next unless $after;
                    my $p = $path->( $x->{id}, -1 );
                    $bad->( $x, 'exc', 'its way out does not put back the local of ' . $sym->( $in->($save) ) )
                        unless grep { $p->{ $_->{id} } && ( $_->{inputs}[1] // -1 ) == $save->{id} } @restores;
                }
            }
        }
    }

    # (INPUTS ARE VALUES ONLY: MemStart is a version and no value)
    for my $n ( grep { $_->{op} eq 'MemStart' } @nodes ) {
        my @v = grep { !$memphi->( $_->[0] ) } ( $cons{ $n->{id} } // [] )->@*;
        $bad->( $n, 'memory-as-value', 'used by ' . join( ',', map { "$_->[0]{op}#$_->[0]{id}" } @v ) ) if @v;
    }
    return;
}

1;
