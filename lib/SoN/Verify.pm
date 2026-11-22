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
    for my $name ( sort keys( ( $wire->{methods} // {} )->%* ) ) {
        $res{graphs}++;
        _graph_v2( $name, $wire->{methods}{$name}, \%res, { map { $_ => 1 } ( $wire->{profile} // [] )->@* } );
    }
    return \%res;
}

sub _fields ($n) { $n->{fields} // {} }


# The nodes control reaches $n from: a Region's every input; the first input
# of If, Loop and Proj; anything else's control_in.
sub _control_preds ($n) {
    my $in = $n->{inputs} // [];
    return grep { defined } @$in if $n->{op} eq 'Region';
    # (a Loop's back input, on the `loop` profile, is the pass's end: the
    # Loop follows it)
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
#                        is no record has no mem_in.
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
#                        An eval's join too: since the `eval` profile (stage
#                        8) its catch is a way in like the body's end.
#   phi-no-region        a Phi whose `region` is no Region or Loop.
#   phi:memory-as-value  V8: a memory Phi used as a value input.
#   control-fork         V9: a node other than an If or a Loop has more than
#                        one control successor: two things claim to run next.
#   loop                 V11 (`loop` profile): a Loop has one or two inputs
#                        and one control successor, and no Proj takes it; a
#                        Phi at it has one input per input of it.
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
    # A LOOP'S TEST, on a wire without the `loop` profile: its effects are
    # pinned to the Loop beside the body's Proj 0 (stage 9a gives the test an
    # If), and the body follows the last of them -- the test's version no
    # other on its chain follows. Undef where the test writes nothing.
    my $test_version = sub ($loop) {
        my ( @q, %seen, %v ) = ( $loop->{id} );
        while ( defined( my $id = shift @q ) ) {
            next if $seen{$id}++;
            for my $s ( grep { $by{$_}{op} ne 'Proj' || $id != $loop->{id} } ( $succ{$id} // [] )->@* ) {
                $v{$s} = 1 if $by{$s}{mem_out};
                # (a test with arms -- `while (C && shift @q)` -- merges its
                # memory at a Region of its own)
                $v{ $region_mem{$s} } = 1 if $by{$s}{op} eq 'Region' && exists $region_mem{$s};
                push @q, $s;
            }
        }
        for my $x ( map { $by{$_} } keys %v ) {
            delete @v{ grep { defined } $x->{mem_in}, ( $memphi->($x) ? ( $x->{inputs} // [] )->@* : () ) };
        }
        return keys %v == 1 ? ( keys %v )[0] : undef;
    };
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
            elsif ( $op eq 'Proj' ) {
                my $h = $by{ $pn->{inputs}[0] // '' };
                if ( !$loop_profile && $h && $h->{op} eq 'Loop' && ( _fields($pn)->{index} // 0 ) == 0 ) {
                    my $t = $test_version->($h);
                    return $t if defined $t;
                }
                $p = $pn->{inputs}[0];
            }
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
        my @q = map { $_->{id} } grep { defined $_->{control_in} || $_->{op} =~ /^(?:Start|Return|Unwind|Region|If|Loop|Proj)$/ } @nodes;
        while ( defined( my $id = shift @q ) ) {
            next if $live{$id}++;
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
        # (a list slice, `(f())[0]`, picks from values: index_count says so)
        next if $op eq 'Slice' && defined $f->{index_count};
        if    ( $op =~ /^(?:Subscript|Slice|Count|PostfixDeref|CellRead|EntryDef|PadAccess|FieldAccess)$/ ) { $class = $place_class->($n) }
        elsif ( $op eq 'RefType' ) { $class = 'object-class' }
        elsif ( $op eq 'Call' && ( $f->{dispatch_kind} // '' ) eq 'builtin' ) { $class = B::SoN::EffectTable::reads_state( $f->{name} ) }
        next unless $class && grep { $live{ $_->[0]{id} } && !$is_place_use->(@$_) } ( $cons{ $n->{id} } // [] )->@*;
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
    if ($loop_profile) {
        for my $L ( grep { $_->{op} eq 'Loop' } @nodes ) {
            my $k = scalar( ( $L->{inputs} // [] )->@* );
            $bad->( $L, 'loop', "$k inputs (one or two)" ) if $k < 1 || $k > 2;
            my %u;
            my @s = grep { $by{$_}{op} ne 'Proj' && !$u{$_}++ } ( $succ{ $L->{id} } // [] )->@*;
            $bad->( $L, 'loop', scalar(@s) . ' control successors' ) if @s > 1;
            $bad->( $L, 'loop', 'a Proj of it: ' . join ', ', map { $say->($_) } @{ [ grep { $by{$_}{op} eq 'Proj' } ( $succ{ $L->{id} } // [] )->@* ] } )
                if grep { $by{$_}{op} eq 'Proj' } ( $succ{ $L->{id} } // [] )->@*;
        }
    }

    # (V8) PHIS PAIR WITH THEIR REGION; MEMORY AND VALUES DO NOT MIX.
    for my $n ( grep { $_->{op} eq 'Phi' } @nodes ) {
        my $f = _fields($n);
        my $r = $by{ $f->{region} // '' };
        if ( !$r || $r->{op} !~ /^(?:Region|Loop)$/ ) { $bad->( $n, 'phi-no-region', 'region=' . ( $f->{region} // 'none' ) ); next }
        my $want = $r->{op} eq 'Loop' ? ( $loop_profile ? scalar $r->{inputs}->@* : 2 ) : scalar grep { defined } $r->{inputs}->@*;
        my $have = scalar( $n->{inputs}->@* );
        $bad->( $n, 'phi-arity',
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
