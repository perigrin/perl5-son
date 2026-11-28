# ABOUTME: The promotion pass: after the walk, rewrite each place or late read the wire proves
# ABOUTME: private into the plain value, marked `promoted` for SoN::Verify to check (design B).
package SoN::Promote;
use v5.42.0;
use SoN::AliasProof ();

# DESIGN B (docs/plans/2026-11-25-places-everywhere.md). Construction is naive:
# every alias perl makes is a place, every SV operand is read where perl reads
# it. This pass, like mem2reg after Clang's allocas, turns a place back into a
# value only where SoN::AliasProof proves it over the whole wire, and marks the
# node it made `promoted`, so that the verifier checks the proof again rather
# than trusting the pass. SON_NO_PROMOTE=1 leaves the naive wire.
#
# It runs on the wire data SoN::Serialize::JSON::to_json builds, before it is
# encoded: the form the verifier reads, with every graph of the program.

# How often each proof held ('<kind>-value') or failed ('<kind>-place'), for
# tools/alias-fastpath.pl (B::SoN prints them under SON_ALIAS_STATS).
our %STATS;
# Sub name -> code the wire cannot see may call it (B::SoN sets it): such a
# sub may be handed places by none of the wire's calls (P2).
our %CALLED_UNKNOWN;

my %PLACE_OP = map { ( $_ => 1 ) } qw(EntryDef PadAccess Subscript FieldAccess CellRead);

sub promote ($data) {
    my $p = SoN::AliasProof->new($data);
    # (the hint B::SoN leaves a Call -- where each place argument's variable
    # was read where perl pushed it -- is this pass's alone: off the wire)
    my %hint;
    for my $g ( $p->graphs ) {
        for my $c ( grep { $_->{op} eq 'Call' } $p->nodes($g) ) {
            $hint{$g}{ $c->{id} } = delete $c->{fields}{arg_read_at} if exists( ( $c->{fields} // {} )->{arg_read_at} );
        }
    }
    return $data if $ENV{SON_NO_PROMOTE};
    require SoN::PromotedPrivate;
    my ( $v14, $v14_args_read_only, $v14_add, $v14_stores_nothing ) = SoN::PromotedPrivate::private_checker($data);
    # (each read of a variable already on the wire, by what it reads and where)
    my $sig = sub ( $op, $f, $in, $mem ) {
        my %f = %$f; delete @f{qw(place vivify promoted)};
        return join "\0", $op, ( map { "$_=" . ( ref $f{$_} ? '' : $f{$_} // '' ) } sort keys %f ), join( ',', map { $_ // '' } @$in ), $mem // '';
    };
    my %reads;
    for my $g ( $p->graphs ) {
        for my $n ( grep { $PLACE_OP{ $_->{op} } && defined $_->{mem_in} && !( $_->{fields} // {} )->{place} && !defined $_->{control_in} } $p->nodes($g) ) {
            $reads{$g}{ $sig->( $n->{op}, $n->{fields} // {}, $n->{inputs} // [], $n->{mem_in} ) } //= $n;
        }
    }
    my %new;    # graph -> [ [ before_id, node ] ... ]
    my %dead;   # graph -> { id => 1 }: a place no consumer is left
    for my $g ( $p->graphs ) {
        my $next = 1 + ( sort { $b <=> $a } map { $_->{id} } ( $p->{g}{$g}{nodes} // [] )->@* )[0];
        for my $c ( grep { SoN::AliasProof::is_sub_call($_) } $p->nodes($g) ) {
            my @pl = grep { my $a = $p->node( $g, $c->{inputs}[$_] ); $a && ( $a->{fields} // {} )->{place} && $PLACE_OP{ $a->{op} } }
                0 .. $#{ $c->{inputs} // [] };
            next unless @pl;
            my $all = 1;
            for my $i (@pl) {
                # P1: a place a call is handed -> its source read at the call's version
                if ( !defined $c->{mem_in} || defined $p->arg_private( $g, $c, $i ) ) { $all = 0; $STATS{'arg-place'}++; next }
                my $a = $p->node( $g, $c->{inputs}[$i] );
                my %f = ( $a->{fields} // {} )->%*;
                delete @f{qw(place vivify)};
                # (READ WHERE PERL PUSHED IT, where nothing on the chain between
                # that and the call may store it: the read the walk made)
                my $at = $c->{mem_in};
                my $h = ( $hint{$g}{ $c->{id} } // [] )->[$i];
                $at = $h if defined $h && $p->reaches( $g, $c->{mem_in}, $h )
                    && !defined $p->stored_between( $g, $c->{mem_in}, $h, $p->src( $g, $a ) )
                    && !defined $v14->( $g, $c, $i, $h );
                # (AND BY V14'S OWN RULE, which shares nothing with the proof
                # above: a promotion the verifier would reject is not made)
                if ( defined $v14->( $g, $c, $i, $at ) ) { $all = 0; $STATS{'arg-place'}++; next }
                $STATS{'arg-value'}++;
                # (THE READ THE WALK MADE, where it is still on the wire -- the
                # same node, as before the place: marked, not made again)
                my $key = $sig->( $a->{op}, \%f, $a->{inputs}, $at );
                if ( ( my $same = $reads{$g}{$key} ) && $reads{$g}{$key}{id} < $c->{id} ) {
                    $same->{fields}{promoted} = JSON::PP::true();
                    $c->{inputs}[$i] = $same->{id};
                    $dead{$g}{ $a->{id} } = 1;
                    next;
                }
                my $r = { id => $next++, op => $a->{op}, inputs => [ ( $a->{inputs} // [] )->@* ],
                          fields => { %f, promoted => JSON::PP::true() },
                          mem_in => $at, mem_operand => JSON::PP::true(),
                          ( defined $a->{stamp} ? ( stamp => $a->{stamp} ) : () ) };
                push $new{$g}->@*, [ $c->{id}, $r ];
                $v14_add->( $g, $r );    # (V14 is asked of the wire as it is now)
                $reads{$g}{$key} = $r;
                $c->{inputs}[$i] = $r->{id};
                $dead{$g}{ $a->{id} } = 1;
            }
            $STATS{ 'call-' . ( $all ? 'value' : 'place' ) }++;
        }
    }
    # P2: A SUB'S COPY OF @_ AS A RECORD. `my ($p, $q) = @_` is built as each
    # target read at the version where it stands (audit 3, N1). Where no call
    # the wire holds hands the sub a place (after P1), no code the wire cannot
    # see may call it, the reads are at its start and it neither hands @_ on
    # nor stores through it, the reads are its arguments as passed: the
    # parameter record (`Assign record [targets, ArgsSource]`), which binds
    # each target positionally.
    my %placed;    # sub name -> some call hands it a place
    for my $g ( $p->graphs ) {
        for my $c ( grep { SoN::AliasProof::is_sub_call($_) } $p->nodes($g) ) {
            next unless grep { my $a = $p->node( $g, $_ ); $a && ( $a->{fields} // {} )->{place} } ( $c->{inputs} // [] )->@*;
            my $t = $p->callees( $g, $c ) or next;
            $placed{$_} = 1 for @$t;
        }
    }
    my %repl;    # graph -> { read id => target id }
    for my $h ( grep { $p->{g}{$_} && exists $CALLED_UNKNOWN{$_} } $p->graphs ) {
        my $blocked = $CALLED_UNKNOWN{$h} || $placed{$h} || $p->args_escape($h) || !$v14_args_read_only->($h) || !$v14_stores_nothing->($h);
        # (A SUB THAT STORES: an argument is an alias, and its store may reach
        # one before the `my` it was copied into is read -- fifth final
        # audit, vt59: `my ($v, $s) = @_; $s->{l}[0] = 0; $v`. Fails closed: any
        # store but into its own `my`s.)
        $blocked ||= keys $p->writes($h)->%*;
        my ($start) = grep { $_->{op} eq 'MemStart' } $p->nodes($h);
        for my $as ( grep { $_->{op} eq 'Assign' && ( $_->{fields} // {} )->{record} } $p->nodes($h) ) {
            $STATS{'record-place'}++, next if $blocked;
            my $k = ( $as->{fields} // {} )->{targets} // next;
            my @in = ( $as->{inputs} // [] )->@*;
            my @t = @in[ 0 .. $k - 1 ];
            my @r = map { $p->node( $h, $_ ) } @in[ $k .. $#in ];
            next unless @r == $k && $start;
            my ( $args, $ok ) = ( undef, 1 );
            for my $i ( 0 .. $#r ) {
                my $r = $r[$i];
                my $ix = $r && $r->{op} eq 'Subscript' ? $p->node( $h, $r->{inputs}[1] ) : undef;
                my $src = $r ? $p->node( $h, $r->{inputs}[0] ) : undef;
                $ok = 0, last unless $src && $src->{op} eq 'ArgsSource' && ( $r->{mem_in} // -1 ) == $start->{id}
                    && $ix && $ix->{op} eq 'Constant' && ( $ix->{fields}{value} // '' ) eq "$i";
                $args = $src->{id};
            }
            $STATS{ 'record-' . ( $ok && defined $args ? 'value' : 'place' ) }++;
            next unless $ok && defined $args;
            $repl{$h}{ $r[$_]{id} } = $t[$_] for 0 .. $#r;
            # (the target stands for the read now: typed as its uses typed it)
            for my $i ( 0 .. $#r ) {
                my $t = $p->node( $h, $t[$i] ) or next;
                $t->{stamp} = $r[$i]{stamp} if defined $r[$i]{stamp} && ( $t->{stamp} // 'Unknown' ) eq 'Unknown';
            }
            $as->{inputs} = [ @t, $args ];
            $as->{fields}{promoted} = JSON::PP::true();
        }
    }
    for my $h ( keys %repl ) {
        my $m = $repl{$h};
        # (P1's new reads too, not yet in the graph's list: theirs name the
        # copies as the place they read through did -- yyi52's `$t->{l}`)
        for my $n ( ( $p->{g}{$h}{nodes} // [] )->@*, map { $_->[1] } ( $new{$h} // [] )->@* ) {
            next if $n->{op} eq 'Assign' && ( $n->{fields} // {} )->{record};
            $n->{inputs} = [ map { defined && !ref && exists $m->{$_} ? $m->{$_} : $_ } ( $n->{inputs} // [] )->@* ];
        }
        my %used = map { ( $_ => 1 ) } map { grep { defined && !ref } ( $_->{inputs} // [] )->@* } ( $p->{g}{$h}{nodes} // [] )->@*, map { $_->[1] } ( $new{$h} // [] )->@*;
        $p->{g}{$h}{nodes} = [ grep { !exists $m->{ $_->{id} } || $used{ $_->{id} } } $p->{g}{$h}{nodes}->@* ];
        # (the targets, which have no inputs, now named by the reads' uses:
        # moved to the front, so that no use comes before them)
        my %t = map { ( $_ => 1 ) } values %$m;
        my @n = $p->{g}{$h}{nodes}->@*;
        $p->{g}{$h}{nodes} = [ ( grep { $_->{op} eq 'Start' } @n ), ( grep { $t{ $_->{id} } } @n ), ( grep { $_->{op} ne 'Start' && !$t{ $_->{id} } } @n ) ];
        $new{$h} //= [];
    }
    for my $g ( keys %new ) {
        # (a place still handed to another call stays)
        my %used = map { ( $_ => 1 ) } map { grep { defined && !ref } ( $_->{inputs} // [] )->@* } ( $p->{g}{$g}{nodes} // [] )->@*;
        $p->{g}{$g}{nodes} = [ grep { !$dead{$g}{ $_->{id} } || $used{ $_->{id} } } $p->{g}{$g}{nodes}->@* ];
        _renumber( $p->{g}{$g}, $new{$g} );
    }
    return $data;
}

# _renumber($graph, [[before, node] ...]) -> put each new node just before the
# node that uses it, and number the graph's nodes 0.. again in that order:
# the wire names every input before its consumer (a forward edge is a loop
# Phi's back edge, and nothing else).
sub _renumber ( $graph, $new ) {
    my %before;
    push $before{ $_->[0] }->@*, $_->[1] for @$new;
    my @order;
    for my $n ( $graph->{nodes}->@* ) { push @order, ( $before{ $n->{id} } // [] )->@*, $n }
    my %map; $map{ $order[$_]{id} } = $_ for 0 .. $#order;
    my $m = sub ($v) { defined $v && !ref $v && exists $map{$v} ? $map{$v} : $v };
    for my $n (@order) {
        $n->{id} = $map{ $n->{id} };
        $n->{inputs} = [ map { ref $_ eq 'ARRAY' ? [ map { $m->($_) } @$_ ] : $m->($_) } ( $n->{inputs} // [] )->@* ];
        for my $k (qw(control_in mem_in head)) { $n->{$k} = $m->( $n->{$k} ) if exists $n->{$k} }
        my $f = $n->{fields} or next;
        for my $k (qw(region eval_entry)) { $f->{$k} = $m->( $f->{$k} ) if exists $f->{$k} }
        $f->{predecessors} = [ map { $m->($_) } $f->{predecessors}->@* ] if ref $f->{predecessors} eq 'ARRAY';
    }
    $graph->{nodes} = \@order;
    $graph->{start} = $m->( $graph->{start} ) if exists $graph->{start};
    $graph->{returns} = [ map { $m->($_) } $graph->{returns}->@* ] if ref $graph->{returns} eq 'ARRAY';
    return;
}

1;
