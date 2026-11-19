# ABOUTME: Checks a B::SoN wire against the memory-chain rules, as the CURRENT wire
# ABOUTME: encodes them, and names each violation: node, kind, rule, graph.
package SoN::Verify;
use v5.42.0;
use SoN::Deparse ();    # %MEM_MIN_INPUTS: where each kind's memory input stands

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
#   - a builtin's effect: the producer has no effect table, so %WRITES and
#     %READS_STATE below are this module's own statement of it.
#   - may-die reads other than Divide/Modulo, `local` restores on every exit,
#     DESTROY, autovivifying reads, and the missing catch edge of an eval
#     whose Phis happen to have one input.
#   - package-scalar-loop-value cannot see whether the loop holds a call, nor
#     tell `$g = $x` (a lexical also stored to $g) from $g itself.

# Builtins that write memory or the world. Taken from the audit's census.
my %WRITES = map { $_ => 1 } qw(
    push pop shift unshift splice delete each undef local chomp chop reset
    bless tie untie lock study vec formline write
    open close binmode print printf say syswrite sysread read readline eof seek
    truncate unlink mkdir rmdir rename chdir chmod chown utime link symlink
    opendir readdir closedir sysopen flock select srand
    socket connect bind listen accept send recv shutdown dbmopen dbmclose
    require do eval exit die warn system exec fork wait waitpid kill sleep
    syscall alarm umask setpgrp set_arylen
);

# Builtins whose VALUE is of state a later write may change, by where it lives.
my %READS_STATE = (
    ( map { $_ => 'object-class' } qw(blessed ref reftype reftype_of_ref) ),
    ( map { $_ => 'external' } qw(time rand localtime gmtime glob pos tied
        ftis ftsize ftdir ftfile ftlink ftzero ftchr ftmtime fteread fteexec) ),
);

my %STATEMENT = map { $_ => 1 } qw(
    EntryWrite CellWrite Delete ElemRestore LocalAlias RegexSubst Transliterate
    Chomp Print Unwind BacktickExpr
);

# verify($wire) -> { violations => [ { graph, node, op, rule, detail } ... ],
#                    allowed => { record => N, 'param-bind' => N }, graphs => N }
sub verify ($wire) {
    my %res = ( violations => [], allowed => {}, graphs => 0 );
    for my $name ( sort keys( ( $wire->{methods} // {} )->%* ) ) {
        $res{graphs}++;
        _graph( $name, $wire->{methods}{$name}, \%res );
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
            : $op eq 'Call' ? ( ( $f->{dispatch_kind} // '' ) ne 'builtin' || $WRITES{ $f->{name} // '' } ? @$in : () )
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
            elsif ( $WRITES{ $f->{name} // '' } )    { $effect = "builtin $f->{name}" }
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
                $class = $READS_STATE{ $f->{name} // '' };
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

1;
