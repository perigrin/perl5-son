# ABOUTME: Wire-level helpers over a decoded B::SoN wire. as_v1 turns a v2 wire into the
# ABOUTME: v1 shape (memory as a trailing input), for readers that have not moved to v2.
package SoN::Wire;
use v5.42.0;
use Storable ();
use JSON::PP ();

# as_v1($wire) -> a new decoded wire in v1's shape; $wire is not touched.
#
# The stage-3 downgrade (SoN::Serialize::JSON's v1 writer), applied to a
# decoded v2 wire (docs/plans/2026-11-20-wire-v2.md, stage 4):
#
# - `mem_in` goes back to the end of `inputs` where v1 had it as an operand,
#   and a builtin Call that gets one says so (`memory_input`);
# - `mem_in`, `mem_out` and `record` are dropped, and `version` is 1;
# - a MakeCell leaves the control chain (v1 never put it there);
# - the memory Phi where a sub's exits merge (`exits`; v1 has no place for
#   it) is dropped, and so is a node only a mem_in reached (a MemStart); the
#   nodes are numbered again in order;
# - an eval's exceptional edges (the `eval` profile: each Exc, what stands
#   on it, the catch Region and its Phis, the $@ store after it) are dropped,
#   and so is the store of "" to $@ where its body ends: its join is v1's
#   again, the body's end its way in (the die, where the body always dies),
#   and a memory edge to a dropped version names the one it followed.
#
# The ids differ from v1's: v2 lists a node's memory before it.
#
# WHICH mem_in WAS AN OPERAND. The producer knows (`mem_operand`: memory read
# where the node was built); the wire does not say. The rule below is what the
# producer does, measured over the corpus and the probes (2026-11-21): a node
# that only FOLLOWS memory on the chain never had it (an Assign, a sub call, a
# Return, an Unwind, a LocalAlias, a match); a builtin call, a Ref or a field
# read pinned as an ordered read, no version, did not either; every other
# read had it. Wrong for about 30 builtin calls in 9000 (a four-argument
# substr, `$#a = N`, half of the sorts with a comparator and of the printfs:
# the same kind and shape either way): such a call gains or lacks a trailing
# memory input, and says so by `memory_input`, which is what the deparser asks.
my %FOLLOWS_ONLY = map { $_ => 1 } qw(Assign Return Unwind LocalAlias Match RegexMatch);
my %ORDERED_READ = map { $_ => 1 } qw(Call Ref FieldAccess);

sub _operand ($n) {
    my $op = $n->{op};
    return 0 if $FOLLOWS_ONLY{$op};
    return 0 if $op eq 'Call' && ( ( $n->{fields} // {} )->{dispatch_kind} // '' ) ne 'builtin';
    return 0 if $ORDERED_READ{$op} && defined $n->{control_in} && !$n->{mem_out};
    return 1;
}

sub as_v1 ($wire) {
    my $w = Storable::dclone($wire);
    return $w unless ( $w->{version} // 1 ) == 2;
    $w->{version} = 1;
    delete $w->{profile};
    for my $g ( values( ( $w->{methods} // {} )->%* ) ) {
        my $nodes = $g->{nodes} // [];
        _drop_catch_edges($g);

        # A MakeCell is not on v1's chain: what follows it follows what it
        # does, wherever control is named (SoN::Serialize::JSON::_on_chain).
        my %cell = map { $_->{id} => $_->{control_in} } grep { $_->{op} eq 'MakeCell' } @$nodes;
        my $on_chain = sub ($i) { $i = $cell{$i} while defined $i && exists $cell{$i}; $i };
        for my $n (@$nodes) {
            my $f = $n->{fields} // {};
            if ( exists $cell{ $n->{id} } ) { delete $n->{control_in} }
            elsif ( defined $n->{control_in} ) { $n->{control_in} = $on_chain->( $n->{control_in} ) }
            $n->{inputs} = [ map { $on_chain->($_) } $n->{inputs}->@* ] if $n->{op} =~ /\A(?:If|Loop|Region)\z/;
            $f->{predecessors} = [ map { $on_chain->($_) } $f->{predecessors}->@* ] if ref $f->{predecessors} eq 'ARRAY';
            $f->{eval_entry} = $on_chain->( $f->{eval_entry} ) if $n->{op} eq 'Region' && defined $f->{eval_entry};
            delete $n->{control_in} unless defined $n->{control_in};
        }

        for my $n (@$nodes) {
            my $operand = _operand($n);
            my $m = delete $n->{mem_in};
            delete $n->{mem_out};
            delete $n->{fields}{record} if $n->{fields};
            next unless defined $m && $operand;
            push $n->{inputs}->@*, $m;
            $n->{fields}{memory_input} = JSON::PP::true()
                if $n->{op} eq 'Call';
        }

        # What v1 reaches: the writer walks from Start and the Returns along
        # operands and control, both ways. A MemStart only a mem_in named
        # (a sub that reads no memory as an operand) is not on v1.
        my %adj;
        my %exits = map { $_->{id} => 1 } grep { $_->{op} eq 'Phi' && ( $_->{fields} // {} )->{exits} } @$nodes;
        for my $n ( grep { !$exits{ $_->{id} } } @$nodes ) {
            my @to = ( ( map { ref $_ ? @$_ : $_ } ( $n->{inputs} // [] )->@* ),
                ( defined $n->{control_in} ? $n->{control_in} : () ),
                ( $n->{op} eq 'Phi' && defined( ( $n->{fields} // {} )->{region} ) ? $n->{fields}{region} : () ) );
            for my $t ( grep { defined && !$exits{$_} } @to ) {
                push $adj{ $n->{id} }->@*, $t;
                push $adj{$t}->@*, $n->{id};
            }
        }
        my %seen;
        my @work = grep { defined && !$exits{$_} } ( $g->{start}, ( $g->{returns} // [] )->@* );
        while ( defined( my $i = shift @work ) ) {
            next if $seen{$i}++;
            push @work, ( $adj{$i} // [] )->@*;
        }
        next unless grep { !$seen{ $_->{id} } } @$nodes;

        # Number the nodes again: the ids are positions.
        my @keep = grep { $seen{ $_->{id} } } @$nodes;
        my %to;
        $to{ $keep[$_]{id} } = $_ for 0 .. $#keep;
        my $re = sub ($i) { defined $i && exists $to{$i} ? $to{$i} : $i };
        for my $n (@keep) {
            $n->{id} = $to{ $n->{id} };
            $n->{inputs} = [ map { ref $_ ? [ map { $re->($_) } @$_ ] : $re->($_) } ( $n->{inputs} // [] )->@* ];
            $n->{control_in} = $re->( $n->{control_in} ) if defined $n->{control_in};
            $n->{head} = $re->( $n->{head} ) if defined $n->{head};
            my $f = $n->{fields} or next;
            $f->{region} = $re->( $f->{region} ) if $n->{op} eq 'Phi' && defined $f->{region};
            $f->{predecessors} = [ map { $re->($_) } $f->{predecessors}->@* ] if ref $f->{predecessors} eq 'ARRAY';
            $f->{eval_entry} = $re->( $f->{eval_entry} ) if $n->{op} eq 'Region' && defined $f->{eval_entry};
        }
        $g->{nodes}   = \@keep;
        $g->{start}   = $re->( $g->{start} );
        $g->{returns} = [ map { $re->($_) } ( $g->{returns} // [] )->@* ];
    }
    return $w;
}

# _drop_catch_edges($graph): the `eval` profile's edges out of a decoded v2
# graph, in place (see as_v1).
sub _drop_catch_edges ($g) {
    my $nodes = $g->{nodes} // [];
    my %by = map { $_->{id} => $_ } @$nodes;
    my @catch = grep { $_->{op} eq 'Region' && ( $_->{fields} // {} )->{catch} } @$nodes or return;
    my %succ;    # control successors
    push $succ{ $_->{control_in} }->@*, $_ for grep { defined $_->{control_in} } @$nodes;
    my %region_in;    # a node => the Regions it is a way into
    for my $r ( grep { $_->{op} eq 'Region' } @$nodes ) { push $region_in{$_}->@*, $r for grep { defined } $r->{inputs}->@* }
    my $f = sub ( $n, $k ) { ( $n->{fields} // {} )->{$k} };
    my $is_err = sub ($n) { $n && $n->{op} eq 'EntryWrite' && do { my $t = $by{ $n->{inputs}[0] // '' }; $t && $t->{op} eq 'EntryDef' && ( $f->( $t, 'symbol' ) // '' ) eq '@' } };
    my ( %drop, %fwd );
    # chain($from) -> the nodes control reaches from $from, to (not into) a Region
    my $chain = sub ($from) {
        my @c;
        for ( my @s = ( $succ{$from} // [] )->@*; @s == 1; @s = ( $succ{ $s[0]{id} } // [] )->@* ) { push @c, $s[0] }
        return @c;
    };
    for my $c (@catch) {
        my @exc = map { my $x = $_; while ( $x && $x->{op} ne 'Exc' ) { $x = $by{ $x->{control_in} // '' } } $x // () } map { $by{$_} } $c->{inputs}->@*;
        $drop{ $_->{id} } = 1 for $c, @exc, map { $chain->( $_->{id} ) } @exc;
        $drop{ $_->{id} } = 1 for grep { $_->{op} eq 'Phi' && ( $f->( $_, 'region' ) // -1 ) == $c->{id} } @$nodes;
        my @after = $chain->( $c->{id} );
        $drop{ $_->{id} } = 1 for @after;
        my $end = @after ? $after[-1] : $c;
        for my $j ( ( $region_in{ $end->{id} } // [] )->@* ) {
            my @keep = grep { $j->{inputs}[$_] != $end->{id} } 0 .. $j->{inputs}->$#*;
            # (the body's end clears $@: v1's way in is what it follows)
            my @clear = grep { my $n = $by{ $j->{inputs}[$_] }; $is_err->($n) && ( ( ( $by{ $n->{inputs}[1] // '' } // {} )->{fields} // {} )->{const_type} // '' ) eq 'string' && ( $by{ $n->{inputs}[1] }{fields}{value} // 'x' ) eq '' } @keep;
            my @phis = grep { $_->{op} eq 'Phi' && ( $f->( $_, 'region' ) // -1 ) == $j->{id} } @$nodes;
            for my $p (@phis) {
                next unless $f->( $p, 'memory' );
                $p->{inputs} = [ map { $p->{inputs}[$_] } @keep ];
            }
            for my $k (@clear) {
                my $n = $by{ $j->{inputs}[$k] };
                $drop{ $n->{id} } = 1;
                $j->{inputs}[$k] = $n->{control_in};
                for my $p ( grep { $f->( $_, 'memory' ) } @phis ) {
                    $_ == $n->{id} and $_ = $n->{mem_in} for $p->{inputs}->@*;
                }
            }
            $j->{inputs} = [ map { $j->{inputs}[$_] } @keep ];
            # (a body that always dies: its die was v1's way in)
            unless ( $j->{inputs}->@* ) {
                my ($u) = grep { $_->{op} eq 'Unwind' && !$region_in{ $_->{id} } && !$succ{ $_->{id} } } map { $by{ $_->{inputs}[0] } } @exc;
                $j->{inputs} = [ $u ? $u->{id} : () ];
            }
            # (a trap with no entry -- a string eval's -- had no memory Phi)
            next if defined $f->( $j, 'eval_entry' );
            for my $p ( grep { $f->( $_, 'memory' ) && $_->{inputs}->@* == 1 } @phis ) {
                $drop{ $p->{id} } = 1;
                $fwd{ $p->{id} } = $p->{inputs}[0];
            }
        }
    }
    # A MEMORY EDGE TO A DROPPED VERSION names the one it followed.
    my $alive = sub ($i) {
        my %seen;
        while ( defined $i && $drop{$i} && !$seen{$i}++ ) {
            my $n = $by{$i};
            $i = exists $fwd{$i} ? $fwd{$i} : $n->{op} eq 'Phi' ? $n->{inputs}[0] : $n->{mem_in};
        }
        return $i;
    };
    @$nodes = grep { !$drop{ $_->{id} } } @$nodes;
    for my $n (@$nodes) {
        $n->{mem_in} = $alive->( $n->{mem_in} ) if defined $n->{mem_in};
        $n->{inputs} = [ map { $alive->($_) } $n->{inputs}->@* ] if $n->{op} eq 'Phi' && $f->( $n, 'memory' );
    }
    $g->{returns} = [ grep { !$drop{$_} } ( $g->{returns} // [] )->@* ];
    return;
}

1;
