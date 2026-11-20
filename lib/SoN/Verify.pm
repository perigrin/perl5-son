# ABOUTME: Checks a B::SoN wire against the memory-chain rules, as the CURRENT wire
# ABOUTME: encodes them, and names each violation: node, kind, rule, graph.
package SoN::Verify;
use v5.42.0;
use SoN::Deparse ();    # %MEM_MIN_INPUTS: where each kind's memory input stands
use B::SoN::EffectTable ();

# WHAT THIS IS. The audit of 2026-11-19 (docs/research/son-ir-audit-2026-11-19)
# found the memory model sound -- one chain from MemStart, each effectful node
# the next version, Phis where paths meet -- and unchecked: a write that is on
# the chain is there because one of ~120 hand-written sites put it there, and a
# write that is not is silently lost. This module is the check. It reads the
# decoded JSON wire, not the producer's graph objects and not a consumer's
# loaded graph: a consumer's loader has already dropped what floats.
#
# HOW THE CURRENT WIRE ENCODES MEMORY (REPORT.md 2.1), which is what the rules
# below are written against:
#   - a WRITE is a version by being pinned: its `control_in` names the node it
#     follows. Assign, sub calls and Return carry no memory input.
#   - EntryWrite, CellWrite, Delete, ElemRestore, MakeCell and builtin calls
#     flagged `memory_input` ALSO carry the version they follow as an input.
#   - a READ names its version as a positional input, per kind
#     (%SoN::Deparse::MEM_MIN_INPUTS; a Call's is its last input when flagged).
#   - a pinned read is itself a version (later reads may name it).
#
# THE RULES. Each violation's `rule` is one of:
#
#   write-floating       a memory-writing node with no control_in and no
#                        consumer: nothing reaches it, it is lost.
#   effect-rides-value   the same, but something reads its value: it runs at
#                        first use, or (if that use is dropped) never.
#   write-off-chain      pinned, but its control chain does not lead back to
#                        Start.
#   return-off-chain     a Return that is not on the chain from Start.
#   read-unversioned:C   a read of changeable state with no memory input and
#                        no control_in, whose value is used. C is where the
#                        state lives: package, field, cell, through-ref, args,
#                        my-aggregate, my-shared, object-class (RefType,
#                        blessed), package-aggregate-literal (a package @x/%x
#                        flattened through its named literal), external
#                        (time, rand, -e, pos ...).
#   phi-arity            a Phi's inputs do not pair with its Region's control
#                        inputs (a Loop's Phi has two: way in, way round).
#   phi-arity:eval-join  the known class of that: an `eval` join has one
#                        control input and Phis with one more (the catch edge
#                        the wire lacks).
#   phi-no-region        a Phi whose `region` is no Region or Loop.
#   memory-input-not-version  a memory input (or a memory Phi's input) names
#                        a node that is no version: not MemStart, a memory
#                        Phi, a MakeCell or a pinned node.
#   memory-order-disagrees    the two orderings differ: a pinned node's
#                        memory input is not the nearest version back along
#                        its control chain.
#   control-fork         a node other than an If or a Loop has more than one
#                        control successor: two things claim to run next,
#                        and nothing says which (wire v2's rule V9). An If
#                        has its Projs; a Loop its Projs and, on this wire,
#                        the test pinned to it.
#   fault-floating       a Divide/Modulo with no control_in whose divisor is
#                        not a non-zero constant: a fault with no place.
#   package-scalar-loop-value  a Loop's VALUE Phi both of whose inputs are
#                        values stored to one package scalar: the scalar is
#                        carried round the loop where no callee's write can
#                        reach it (audit W1). A heuristic -- see below.
#
# ALLOWED, AND COUNTED (`allowed` in the result), because the wire has
# floating Assigns that are not stores and no flag to say so:
#   record       an unpinned Assign whose targets are all SSA `my` scalars.
#   param-bind   an unpinned Assign of @_ into `my` aggregates.
#
# WHAT THE CURRENT WIRE CANNOT EXPRESS, so nothing here checks it (each is an
# argument for wire v2's named edges):
#   - "reached backwards from Return". Return takes no memory, and a Loop has
#     no back edge, so a walk back from Return never enters a loop body. The
#     chain is checked FORWARD from Start instead (write-off-chain), which
#     cannot see a pinned write on a path that never rejoins the Return's.
#   - which version an Assign or a sub call FOLLOWS: only control says, so
#     memory-order-disagrees covers the kinds that carry both, no others.
#   - the memory input of RegexSubst and Transliterate: its position depends
#     on optional operands, so it is not located and not checked.
#   - whether a value-numbered read of a `my` aggregate is of changeable
#     state: decided here by "does this graph write that name" (_mutated), a
#     re-derivation of the producer's own trigger list, not a wire fact.
#   - place versus value: an unversioned Subscript is a place when every use
#     is a store target, a container, or an argument, and a read otherwise;
#     the roles are listed in _is_place_use, by kind and position.
#   - may-die reads other than Divide/Modulo, `local` restores on every exit,
#     DESTROY, autovivifying reads, and the missing catch edge of an eval
#     whose Phis happen to have one input.
#   - package-scalar-loop-value cannot see whether the loop holds a call, nor
#     tell `$g = $x` (a lexical also stored to $g) from $g itself.

# WHAT A BUILTIN WRITES, AND WHAT STATE ITS VALUE IS OF, is B::SoN::EffectTable's
# to say: the table the producer places by. This module kept lists of its own
# while the producer had none; two lists is one too many (and this one said
# `printf` where the wire says `prtf`, so a floating printf was never seen).

my %STATEMENT = map { $_ => 1 } qw(
    EntryWrite CellWrite Delete ElemRestore LocalAlias RegexSubst Transliterate
    Chomp Print Unwind BacktickExpr
);

# verify($wire) -> { violations => [ { graph, node, op, rule, detail } ... ],
#                    allowed => { record => N, 'param-bind' => N }, graphs => N }
sub verify ($wire) {
    my %res = ( violations => [], allowed => {}, graphs => 0 );
    my $v2 = ( $wire->{version} // 1 ) == 2;
    for my $name ( sort keys( ( $wire->{methods} // {} )->%* ) ) {
        $res{graphs}++;
        $v2 ? _graph_v2( $name, $wire->{methods}{$name}, \%res, { map { $_ => 1 } ( $wire->{profile} // [] )->@* } )
            : _graph( $name, $wire->{methods}{$name}, \%res );
    }
    return \%res;
}

sub _fields ($n) { $n->{fields} // {} }

# The index of a node's memory input, or undef.
sub _memidx ($n) {
    my ( $op, $in ) = ( $n->{op}, $n->{inputs} // [] );
    return _fields($n)->{memory_input} && @$in ? $#$in : undef if $op eq 'Call' || $op eq 'Unwind';
    return undef if $op eq 'RegexSubst' || $op eq 'Transliterate';    # not locatable by position
    my $min = $SoN::Deparse::MEM_MIN_INPUTS{$op} // return undef;
    return @$in > $min ? $min : undef;
}

# The nodes control reaches $n from: a Region's every input; the first input
# of If, Loop and Proj; anything else's control_in.
sub _control_preds ($n) {
    my $in = $n->{inputs} // [];
    return grep { defined } @$in if $n->{op} eq 'Region';
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
        return 'my-scalar-in-memory' if ( $t->{inputs} // [] )->@* || $f->{shared};
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

sub _graph ( $name, $g, $res ) {
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
    my %reach;
    my @q = map { $_->{id} } grep { $_->{op} eq 'Start' } @nodes;
    while ( defined( my $x = shift @q ) ) { next if $reach{$x}++; push @q, ( $succ{$x} // [] )->@* }

    my $bad = sub ( $n, $rule, $detail ) {
        push $res->{violations}->@*,
            { graph => $name, node => $n->{id}, op => $n->{op}, rule => $rule, detail => $detail };
    };

    # (0) ONE CONTROL SUCCESSOR, except for the two kinds that branch.
    for my $n (@nodes) {
        next if $n->{op} eq 'If' || $n->{op} eq 'Loop';
        my %s = map { $_ => 1 } ( $succ{ $n->{id} } // [] )->@*;
        next if keys %s < 2;
        $bad->( $n, 'control-fork', scalar( keys %s ) . ' successors: '
                . join( ', ', map { "$by{$_}{op}#$_" } sort { $a <=> $b } keys %s ) );
    }
    my $pinned = sub ($n) { defined $n->{control_in} };

    # THE NAMES THIS GRAPH WRITES: a `my` aggregate ("@a") some node stores
    # into, hands to a sub, takes a reference to, or captures.
    my $name_of = sub ($n) {
        return undef unless $n && $n->{op} =~ /^(?:PadAccess|ArrayLiteral|HashLiteral)$/;
        my $f = _fields($n);
        return defined $f->{symbol} ? ( $f->{sigil} // '' ) . $f->{symbol} : undef;
    };
    my $container = sub ($n) { $by{ ( $n->{op} eq 'Slice' ? $n->{inputs}[-1] : $n->{inputs}[0] ) // '' } };
    my %mutated;
    for my $n (@nodes) {
        my ( $op, $f, $in ) = ( $n->{op}, _fields($n), $n->{inputs} // [] );
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

    # WHERE THE STATE A READ LOOKS AT LIVES, or undef when it is an SSA value
    # no write can change.
    my $place_class;
    $place_class = sub ($n) {
        return undef unless $n;
        my ( $op, $f ) = ( $n->{op}, _fields($n) );
        return 'package'     if $op eq 'EntryDef';
        return 'field'       if $op eq 'FieldAccess';
        return 'cell'        if $op =~ /^(?:CellRead|CellParam|MakeCell)$/;
        return 'through-ref' if $op eq 'PostfixDeref';
        return 'args'        if $op eq 'ArgsSource';
        if ( $op eq 'PadAccess' && ( $f->{sigil} // '$' ) eq '$' ) { return $f->{shared} ? 'my-shared' : undef }
        if ( defined( my $k = $name_of->($n) ) ) {
            return 'package' if $op ne 'PadAccess' && $f->{symbol} =~ /::/;
            return $mutated{$k} ? 'my-aggregate' : undef;
        }
        return undef if $op =~ /^(?:ArrayLiteral|HashLiteral|Constant|Range)$/;
        if ( $op =~ /^(?:Subscript|Slice|Count)$/ ) {
            my $c = $container->($n) or return undef;
            # An element of an element, or of a scalar: through a reference.
            return 'through-ref' if $c->{op} =~ /^(?:Subscript|Slice)$/;
            return 'through-ref' if $c->{op} eq 'PadAccess' && ( _fields($c)->{sigil} // '$' ) eq '$';
            return $place_class->($c);
        }
        # Any other value: a list is a value, anything else may be a reference.
        return ( $n->{stamp} // '' ) =~ /^(?:Array|List|Hash)$/ ? undef : 'through-ref';
    };

    # Is consumer $c's use of its input $i a use of a PLACE (a store target, a
    # path, an alias, or an operand read at the consumer's own version)?
    my $is_place_use = sub ( $c, $i ) {
        my ( $op, $f ) = ( $c->{op}, _fields($c) );
        return $i < ( $f->{targets} // 1 ) if $op eq 'Assign';
        return $i == $#{ $c->{inputs} } if $op eq 'Slice';
        return 1 if $op eq 'Call' && ( ( $f->{dispatch_kind} // '' ) ne 'builtin' || $f->{memory_input} );
        return 1 if $op =~ /^(?:AnonSub|RegexSubst|Transliterate|Chomp)$/;
        return $i == 0
            if $op =~ /^(?:Subscript|Exists|Delete|Count|PostfixDeref|ElemRestore|Ref|LocalAlias|VarDecl|MakeCell|CellRead|EntryWrite|CellWrite)$/;
        return 0;
    };
    my $value_used = sub ($n) {
        scalar grep { !$is_place_use->(@$_) } ( $cons{ $n->{id} } // [] )->@*;
    };

    my ( %memphi, %is_version );
    for my $n (@nodes) {
        my ( $op, $f, $in ) = ( $n->{op}, _fields($n), $n->{inputs} // [] );
        my $on_chain = $pinned->($n) && $reach{ $n->{id} };

        # (a) WRITES ARE ON THE CHAIN.
        my $effect;
        if ( $op eq 'Assign' ) {
            my %c = map { _target_class( $by{ $_ // '' } ) => 1 } @$in[ 0 .. ( $f->{targets} // 1 ) - 1 ];
            my @mem   = grep { $_ ne 'ssa-scalar' && $_ ne 'skip' } sort keys %c;
            my $args  = ( ( $by{ $in->[-1] // '' } // {} )->{op} // '' ) eq 'ArgsSource';
            my $class = !@mem ? 'record' : $args && "@mem" eq 'my-aggregate' ? 'param-bind' : undef;
            if   ( $class && !$pinned->($n) ) { $res->{allowed}{$class}++ }
            else                              { $effect = 'Assign to ' . ( join( '+', @mem ) || 'ssa-scalar' ) }
        }
        elsif ( $op eq 'Call' ) {
            my $dk = $f->{dispatch_kind} // '?';
            if    ( $dk ne 'builtin' )               { $effect = "Call:$dk" . ( length( $f->{name} // '' ) ? " $f->{name}" : '' ) }
            elsif ( B::SoN::EffectTable::writes( $f->{name} ) )    { $effect = "builtin $f->{name}" }
            elsif ( ( $f->{name} // '' ) eq 'substr' && @$in >= 4 ) { $effect = 'builtin substr (4-arg)' }
        }
        # s///r and tr///r make a value and store nothing.
        elsif ( $STATEMENT{$op} && !( $op =~ /^(?:RegexSubst|Transliterate)$/ && ( $f->{flags} // "" ) =~ /r/ ) ) { $effect = $op }
        if ( defined $effect && !$on_chain ) {
            $bad->(
                $n,
                $pinned->($n) ? 'write-off-chain' : $cons{ $n->{id} } ? 'effect-rides-value' : 'write-floating',
                $effect
            );
        }
        $bad->( $n, 'return-off-chain', $pinned->($n) ? 'pinned, not reachable from Start' : 'no control_in' )
            if $op eq 'Return' && !$on_chain;

        # (b) READS NAME A VERSION.
        my $mi = _memidx($n);
        if ( !defined $mi && !$pinned->($n) ) {
            my $class;
            if ( $op =~ /^(?:Subscript|Slice|Count|PostfixDeref|CellRead|EntryDef|PadAccess|FieldAccess)$/ ) {
                $class = $place_class->($n);
            }
            elsif ( $op eq 'RefType' ) { $class = 'object-class' }
            elsif ( $op eq 'Call' && ( $f->{dispatch_kind} // '' ) eq 'builtin' ) {
                $class = B::SoN::EffectTable::reads_state( $f->{name} );
            }
            $bad->( $n, "read-unversioned:$class", _describe( $n, \%by ) ) if $class && $value_used->($n);
        }
        if ( $op =~ /^(?:ArrayLiteral|HashLiteral)$/ && ( $f->{symbol} // '' ) =~ /::/ ) {
            my @uses = grep { !( $_->[0]{op} eq "EntryWrite" && $_->[1] == 1 ) && !$is_place_use->(@$_) }
                ( $cons{ $n->{id} } // [] )->@*;
            $bad->(
                $n, 'read-unversioned:package-aggregate-literal',
                "$f->{symbol} read by " . join( ',', map { "$_->[0]{op}#$_->[0]{id}" } @uses )
            ) if @uses;
        }

        # (c) PHIS PAIR WITH THEIR REGION.
        if ( $op eq 'Phi' ) {
            my $r = $by{ $f->{region} // '' };
            if ( !$r || $r->{op} !~ /^(?:Region|Loop)$/ ) { $bad->( $n, 'phi-no-region', 'region=' . ( $f->{region} // 'none' ) ) }
            else {
                my $want = $r->{op} eq 'Loop' ? 2 : scalar grep { defined } $r->{inputs}->@*;
                $bad->(
                    $n, defined _fields($r)->{eval_id} ? 'phi-arity:eval-join' : 'phi-arity',
                    scalar(@$in) . " inputs for $want ways into $r->{op}#$r->{id}" . ( $f->{memory} ? ' (memory)' : '' )
                ) if @$in != $want;
                $memphi{ $r->{id} } //= $n if $f->{memory};
            }
        }

        # (d) A MEMORY INPUT NAMES A VERSION.
        for my $m ( $op eq 'Phi' && $f->{memory} ? @$in : defined $mi ? ( $in->[$mi] ) : () ) {
            next unless defined $m;
            my $mn = $by{$m};
            $is_version{$m} = 1 if defined $mi;
            next if $mn && ( $mn->{op} =~ /^(?:MemStart|MakeCell)$/ || $pinned->($mn) || ( $mn->{op} eq 'Phi' && _fields($mn)->{memory} ) );
            $bad->( $n, 'memory-input-not-version', 'memory at ' . ( $mn ? "$mn->{op}#$m" : "missing node $m" ) );
        }

        if ( $op =~ /^(?:Divide|Modulo)$/ && !$pinned->($n) && $cons{ $n->{id} } ) {
            my $d = $by{ $in->[1] // '' };
            $d = $by{ $d->{inputs}[0] // "" } while $d && $d->{op} eq "Coerce";
            my $safe = $d && $d->{op} eq 'Constant' && ( _fields($d)->{value} // 0 ) =~ /^-?(?:\d*\.)?\d+$/ && _fields($d)->{value} != 0;
            $bad->( $n, 'fault-floating', 'divisor ' . ( $d ? "$d->{op}#$d->{id}" : '?' ) ) unless $safe;
        }

        if ( $op eq 'Phi' && !$f->{memory} && @$in == 2 && ( ( $by{ $f->{region} // '' } // {} )->{op} // '' ) eq 'Loop' ) {
            # The package scalars each input is stored to (or is a read of).
            my $slots = sub ($v) {
                my %s;
                my $vn = $by{ $v // '' } or return \%s;
                $vn = $by{ $vn->{inputs}[0] // '' } // $vn if $vn->{op} eq 'Coerce';
                my @defs = $vn->{op} eq 'EntryDef' ? ($vn) : ();
                push @defs, map { $by{ $_->[0]{inputs}[0] // '' } }
                    grep { $_->[0]{op} eq 'EntryWrite' && $_->[1] == 1 } ( $cons{$v} // [] )->@*;
                for my $d ( grep { $_ && $_->{op} eq 'EntryDef' } @defs ) {
                    my $df = _fields($d);
                    $s{"$df->{sigil}$df->{package}::$df->{symbol}"} = 1 if ( $df->{sigil} // '' ) eq '$';
                }
                return \%s;
            };
            my ( $a, $b ) = map { $slots->($_) } @$in;
            my @both = grep { $b->{$_} } sort keys %$a;
            $bad->( $n, 'package-scalar-loop-value', "carries @both round Loop#$f->{region}" ) if @both;
        }
    }

    # THE TWO ORDERINGS AGREE (audit tools/memcheck.pl, check D): a pinned
    # node that also carries a memory input names the nearest version back
    # along its control chain.
    my $is_ver = sub ($p) {
        $p->{op} =~ /^(?:Assign|EntryWrite|CellWrite|Delete|ElemRestore|Call|RegexSubst|LocalAlias|Transliterate)$/
            || $is_version{ $p->{id} };
    };
    my $back = sub ($p) {
        for ( 1 .. 5000 ) {
            my $pn = $by{ $p // '' } or return undef;
            my $op = $pn->{op};
            return 'MemStart' if $op eq 'Start';
            if ( $op eq 'Region' || $op eq 'Loop' ) {
                return $memphi{$p}{id} if $memphi{$p};
                $p = $pn->{inputs}[0];
            }
            elsif ( $op eq 'Proj' ) { $p = $pn->{inputs}[0] }
            elsif ( $op eq 'If' )   { $p = $pn->{control_in} // $pn->{inputs}[0] }
            elsif ( $is_ver->($pn) ) { return $p }
            else                     { $p = $pn->{control_in} }
        }
        return undef;
    };
    my $norm = sub ($id) { ( $by{$id}{op} // '' ) eq 'MemStart' ? 'MemStart' : $id };
    for my $n (@nodes) {
        next unless $pinned->($n);
        my $mi  = _memidx($n) // next;
        my $mid = $n->{inputs}[$mi];
        next unless defined $mid && $by{$mid};
        my $exp = $back->( $n->{control_in} ) // next;
        my $got = $norm->($mid);
        # An unpinned MakeCell standing between: compare through it.
        my $thru = $got;
        while ( $thru ne 'MemStart' && $by{$thru} && $by{$thru}{op} eq 'MakeCell' && defined $by{$thru}{inputs}[1] ) {
            $thru = $norm->( $by{$thru}{inputs}[1] );
        }
        next if $got eq $exp || $thru eq $exp;
        my $say = sub ($x) { $x eq 'MemStart' ? 'MemStart' : "$by{$x}{op}#$x" };
        $bad->( $n, 'memory-order-disagrees', 'input says ' . $say->($got) . ', control says ' . $say->($exp) );
    }
    return;
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
# `version` is 2: memory is named (`mem_in`, `mem_out`), not positional, so
# what v1 could only guess is read here.
#
#   mem-in-not-version   V1: a mem_in, or an input of a memory Phi, names no
#                        version (MemStart, a memory Phi, a node with mem_out).
#   version-off-chain    V2: a node with mem_out lacks mem_in or control_in;
#                        or a Return, an Unwind, a sub Call or an Assign that
#                        is no record has no mem_in.
#   write-unreachable    V3: a node with mem_out the backward walk over
#                        mem_in and memory Phi inputs does not visit, from the
#                        roots (V4): each Return's and Unwind's mem_in, and
#                        the memory Phi of a Loop no exit Region names.
#   control-sink         V4: a pinned node no control follows that is no root
#                        (a Return, an Unwind) and no part of a loop's test.
#   memory-order-disagrees  V5: a pinned node's mem_in is not the nearest
#                        version back along its control chain.
#   read-unversioned:C   V6: as on v1, with mem_in for the memory input.
#   record               V7: a record Assign on a chain, or one whose targets
#                        are not `my` scalars (or `my` aggregates bound from @_).
#   phi-arity, phi-arity:eval-join, phi-no-region   V8, as on v1.
#   phi:memory-as-value  V8: a memory Phi used as a value input.
#   control-fork         V9, as on v1.
sub _graph_v2 ( $name, $g, $res, $profile = {} ) {
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
        elsif ( !defined $n->{mem_in} && !$record->($n)
            && ( $op =~ /^(?:Return|Unwind|Assign)$/ || $op eq 'Call' && ( $f->{dispatch_kind} // '' ) ne 'builtin' ) ) {
            $bad->( $n, 'version-off-chain', "a $op that follows no memory" . ( $op eq 'Assign' ? ' and is no record' : '' ) );
        }
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
    # A pinned node nothing follows is an end: a root -- or, on a wire
    # without the `loop` profile, the end of a loop's test or of its body,
    # which has no back edge to follow it (stage 9a gives it one): its walk
    # back reaches the Loop itself or the Loop's body Proj.
    my $in_a_loop = sub ($n) {
        my ( $c, %seen ) = ( $by{ $n->{control_in} // '' } );
        while ( $c && !$seen{ $c->{id} }++ ) {
            my $op = $c->{op};
            return 1 if $op eq 'Loop';
            return 0 if $op eq 'Start';
            if ( $op eq 'Proj' ) {
                my $h = $by{ $c->{inputs}[0] // '' };
                return 1 if $h && $h->{op} eq 'Loop' && ( _fields($c)->{index} // 0 ) == 0;
                $c = $h && $h->{op} eq 'Loop' ? $by{ $h->{control_in} // $h->{inputs}[0] // '' } : $h;
            }
            elsif ( $op eq 'Region' ) { $c = $by{ $c->{inputs}[0] // '' } }
            elsif ( $op eq 'If' )     { $c = $by{ $c->{control_in} // $c->{inputs}[0] // '' } }
            else                      { $c = $by{ $c->{control_in} // '' } }
        }
        return 0;
    };
    my $loop_profile = $profile->{loop};
    for my $n ( grep { defined $_->{control_in} && $_->{op} !~ /^(?:Return|Unwind)$/ } @nodes ) {
        next if ( $succ{ $n->{id} } // [] )->@*;
        next if !$loop_profile && $in_a_loop->($n);
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
    my $is_place_use = sub ( $c, $i ) {
        my ( $op, $f ) = ( $c->{op}, _fields($c) );
        return $i < ( $f->{targets} // 1 ) if $op eq 'Assign';
        return $i == $#{ $c->{inputs} } if $op eq 'Slice';
        return 1 if $op eq 'Call' && ( ( $f->{dispatch_kind} // '' ) ne 'builtin' || defined $c->{mem_in} );
        return 1 if $op =~ /^(?:AnonSub|RegexSubst|Transliterate|Chomp)$/;
        return $i == 0
            if $op =~ /^(?:Subscript|Exists|Delete|Count|PostfixDeref|ElemRestore|Ref|LocalAlias|VarDecl|MakeCell|CellRead|EntryWrite|CellWrite)$/;
        return 0;
    };
    my %mutated;
    for my $n (@nodes) {
        my ( $op, $f, $in ) = ( $n->{op}, _fields($n), $n->{inputs} // [] );
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
    my $place_class;
    $place_class = sub ($n) {
        return undef unless $n;
        my ( $op, $f ) = ( $n->{op}, _fields($n) );
        return 'package'     if $op eq 'EntryDef';
        return 'field'       if $op eq 'FieldAccess';
        return 'cell'        if $op =~ /^(?:CellRead|CellParam|MakeCell)$/;
        return 'through-ref' if $op eq 'PostfixDeref';
        return 'args'        if $op eq 'ArgsSource';
        if ( $op eq 'PadAccess' && ( $f->{sigil} // '$' ) eq '$' ) { return $f->{shared} ? 'my-shared' : undef }
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
    for my $n ( grep { !defined $_->{mem_in} } @nodes ) {
        my ( $op, $f ) = ( $n->{op}, _fields($n) );
        my $class;
        if    ( $op =~ /^(?:Subscript|Slice|Count|PostfixDeref|CellRead|EntryDef|PadAccess|FieldAccess)$/ ) { $class = $place_class->($n) }
        elsif ( $op eq 'RefType' ) { $class = 'object-class' }
        elsif ( $op eq 'Call' && ( $f->{dispatch_kind} // '' ) eq 'builtin' ) { $class = B::SoN::EffectTable::reads_state( $f->{name} ) }
        next unless $class && grep { !$is_place_use->(@$_) } ( $cons{ $n->{id} } // [] )->@*;
        $bad->( $n, "read-unversioned:$class", _describe( $n, \%by ) );
    }
    for my $n ( grep { $_->{op} =~ /^(?:ArrayLiteral|HashLiteral)$/ && ( _fields($_)->{symbol} // '' ) =~ /::/ } @nodes ) {
        my @uses = grep { !( $_->[0]{op} eq "EntryWrite" && $_->[1] == 1 ) && !$is_place_use->(@$_) } ( $cons{ $n->{id} } // [] )->@*;
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

    # (V8) PHIS PAIR WITH THEIR REGION; MEMORY AND VALUES DO NOT MIX.
    for my $n ( grep { $_->{op} eq 'Phi' } @nodes ) {
        my $f = _fields($n);
        my $r = $by{ $f->{region} // '' };
        if ( !$r || $r->{op} !~ /^(?:Region|Loop)$/ ) { $bad->( $n, 'phi-no-region', 'region=' . ( $f->{region} // 'none' ) ); next }
        my $want = $r->{op} eq 'Loop' ? 2 : scalar grep { defined } $r->{inputs}->@*;
        my $have = scalar( $n->{inputs}->@* );
        $bad->( $n, defined _fields($r)->{eval_id} ? 'phi-arity:eval-join' : 'phi-arity',
            "$have inputs for $want ways into $r->{op}#$r->{id}" . ( $f->{memory} ? ' (memory)' : '' ) )
            if $have != $want;
        if ( $f->{memory} ) {
            my @v = grep { !$memphi->( $_->[0] ) } ( $cons{ $n->{id} } // [] )->@*;
            $bad->( $n, 'phi:memory-as-value', 'used by ' . join( ',', map { "$_->[0]{op}#$_->[0]{id}" } @v ) ) if @v;
        }
    }
    return;
}

1;
