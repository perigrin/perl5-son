#!/usr/bin/env perl
# ABOUTME: Wire v2 stage 9b's proof: over the corpus, the probes and chalk's lib, each wire this
# ABOUTME: producer writes equals the stage 9a producer's wire once trivial Phis are taken out.
use v5.42.0;
use FindBin;
use lib "$FindBin::Bin/lib";
use JSON::PP;
use Digest::SHA qw(sha1_hex);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Getopt::Long;
use PvmCorpus qw(read_cases);

# WHY (docs/plans/2026-11-20-wire-v2.md, stage 9b). Braun's construction
# replaced the scouts: a loop's header gets a Phi for every variable its body
# MAY write, and memory always has one; the body is walked once, and a Phi the
# body did not write is forwarded to its init at sealing. The claim is that
# nothing else changed: the graph is the scouts' graph. So each wire is
# compared with the one the stage 9a producer (the scouts, the same wire
# format) writes for the same file.
#
# EQUAL MEANS: the same graphs, and in each the same nodes up to identity,
# after a trivial Phi -- one whose inputs other than itself are all one node
# (Braun's definition; a loop Phi the body never wrote, a memory Phi of one
# way in) -- is replaced by that node, in both wires. A node is its op, its
# fields that are not node ids, its stamp, whether it is a memory version,
# and what it names: inputs, mem_in, control_in, region, head, predecessors
# (refined until stable, so a node is told by the whole graph around it). The
# node ids, the order of the nodes, two equal nodes where one stood (a read
# made against a Phi later forwarded beside the same read made against its
# init), a node nothing that runs uses, a memory Phi's stamp (no value's
# type: the join of its versions') and an eval's number (its place among the
# wire's evals is) are not compared. An eval join's value Phi of one way in is
# not trivial: it carries the eval's value (stage 8).
#
# TWO DEPARTURES FROM "EQUAL", each counted and listed apart, and passing:
#   SAME-BUT-STAMPS  the same graph but for stamps, the coercions they make,
#                    and lines. The scouts read
#                    placeholders where the walk reads the real bindings, so
#                    the walk may know a type better (a Phi the scout left
#                    unstamped); and a scout's walk left its last line for
#                    what came after it (Carp::trusts: 722 for 715).
#   GAINED           a graph the 9a producer refused and this one writes: a
#                    scout's throwaway node could refuse its graph (a value
#                    that may die, made and never reached: probe ev8).
#
# usage: wire-braun-proof.pl --base LIB [--corpus] [--probes] [--chalk DIR]
#                            [--wires DIR] [--jobs N] [--list]
#   --base LIB   the stage 9a producer's lib/ (git archive of its commit).
#   no source named: --corpus --probes. Exit 1 when any wire differs, or a
#   graph the 9a producer writes this one does not.
my ( $base, $corpus, $probes, $chalk, $wires, $jobs, $list );
GetOptions( 'base=s' => \$base, 'corpus' => \$corpus, 'probes' => \$probes, 'chalk=s' => \$chalk,
    'wires=s' => \$wires, 'jobs=i' => \$jobs, 'list' => \$list )
    && $base or die "usage: $0 --base LIB [--corpus] [--probes] [--chalk DIR] [--wires DIR] [--jobs N] [--list]\n";
$jobs //= 2;
$corpus = $probes = 1 unless $corpus || $probes || $chalk;
my $root = "$FindBin::Bin/..";
my $tmp  = tempdir( CLEANUP => 1 );
$wires //= "$tmp/wires";
my %lib = ( base => $base, head => "$root/lib" );
my $json = JSON::PP->new->utf8->canonical;

# the work: [ source, name, file, cwd ]
my @work;
if ($corpus) {
    # (each case's file at one path every run: a wire names its file, and the
    # two producers' wires of a case are compared, cached, across runs)
    my $i = 0;
    make_path("$wires/src");
    for my $c ( read_cases("$root/t/corpus/mdtest/pvm") ) {
        my $f = sprintf "%s/src/c%03d.pl", $wires, ++$i;
        open my $o, '>', $f or die $!;
        print $o $c->{src};
        close $o;
        push @work, [ corpus => sprintf( '%03d', $i ), $f, undef ];
    }
}
if ($probes) {
    my $dir = "$root/docs/research/son-ir-audit-2026-11-19/probes";
    push @work, map { [ probes => $_ =~ s{^\Q$dir\E/|\.pl$}{}gr, $_, undef ] } sort glob "$dir/*/*.pl";
}
if ($chalk) {
    my @pm;
    my $walk;
    $walk = sub ($d) {
        opendir my $dh, $d or return;
        for my $e ( sort readdir $dh ) {
            next if $e =~ /\A\./;
            if    ( -d "$d/$e" )      { $walk->("$d/$e") }
            elsif ( $e =~ /\.pm\z/ ) { push @pm, "$d/$e" }
        }
    };
    $walk->("$chalk/lib");
    push @work, map { [ chalk => $_ =~ s{^\Q$chalk\E/}{}r, $_ =~ s{^\Q$chalk\E/}{}r, $chalk ] } @pm;
}

# compile every wire both ways, $jobs at a time (cached under $wires)
sub cache_of ( $which, $w ) { "$wires/$which/$w->[0]/" . ( $w->[1] =~ s{[/:]}{__}gr ) . '.json' }
my @todo;
for my $w (@work) {
    for my $which (qw(base head)) { push @todo, [ $which, $w ] unless -e cache_of( $which, $w ) }
}
my %running;
while ( @todo || %running ) {
    while ( @todo && keys %running < $jobs ) {
        my ( $which, $w ) = shift(@todo)->@*;
        my $out = cache_of( $which, $w );
        make_path( $out =~ s{/[^/]+\z}{}r );
        my $pid = fork // die "fork: $!";
        if ( !$pid ) {
            chdir $w->[3] if defined $w->[3];
            my $not = defined $w->[3] ? ',not_package=SoN' : '';
            my $inc = defined $w->[3] ? '-Ilib' : '';
            exec 'sh', '-c', "ulimit -v 4000000; PERL_HASH_SEED=0 PERL_PERTURB_KEYS=0 timeout 900 $^X -I$lib{$which} $inc "
                . "-MO=-q,SoN,json$not '$w->[2]' > '$out.tmp' 2>/dev/null; mv '$out.tmp' '$out'";
        }
        $running{$pid} = 1;
    }
    my $pid = wait;
    delete $running{$pid} if $pid > 0;
}

# trivial($graph) -> { id => the node it stands for }: Braun's trivial Phis,
# to a fixpoint.
sub trivial ($by) {
    my %fwd;
    my $r = sub ($id) { my %seen; $id = $fwd{$id} while defined $id && exists $fwd{$id} && !$seen{$id}++; $id };
    my $changed = 1;
    while ($changed) {
        $changed = 0;
        for my $n ( grep { $_->{op} eq 'Phi' && !exists $fwd{ $_->{id} } } values %$by ) {
            my $f = $n->{fields} // {};
            my $reg = $by->{ $f->{region} // '' };
            next if !$f->{memory} && $reg && defined( ( $reg->{fields} // {} )->{eval_entry} );
            my %v = map { ( $_ => 1 ) } grep { $_ ne $n->{id} } map { $r->($_) } grep { defined } $n->{inputs}->@*;
            next unless keys %v == 1;
            $fwd{ $n->{id} } = ( keys %v )[0];
            $changed = 1;
        }
    }
    return { map { ( $_ => $r->($_) ) } keys %fwd };
}

# signatures($graph) -> the set of its nodes' signatures (see WHY)
my %REF = map { ( $_ => 1 ) } qw(region head eval_entry);
sub signatures ( $g, $stamps = 1 ) {
    my %by  = map { ( $_->{id} => $_ ) } ( $g->{nodes} // [] )->@*;
    my $fwd = trivial( \%by );
    # (stamp-blind, a coercion is what it coerces: whether one is made
    # depends on the stamps at its two ends)
    unless ($stamps) {
        for my $c ( grep { $_->{op} eq 'Coerce' && !defined $_->{control_in} } values %by ) {
            my $to = $c->{inputs}[0];
            $to = $fwd->{$to} // $to;
            $to = $by{$to}{inputs}[0] while defined $to && $by{$to} && $by{$to}{op} eq 'Coerce' && !defined $by{$to}{control_in};
            $fwd->{ $c->{id} } = $fwd->{$to} // $to;
        }
        $_ = $fwd->{$_} // $_ for values %$fwd;
    }
    my $r   = sub ($id) { defined $id && exists $fwd->{$id} ? $fwd->{$id} : $id };
    # (what nothing that runs uses is not compared: a value made and left)
    my %used;
    my @q = map { $_->{id} } grep { defined $_->{control_in} || $_->{op} =~ /\A(?:Start|Return|Unwind|Region|If|Loop|Proj|Exc)\z/ } values %by;
    while ( defined( my $id = shift @q ) ) {
        $id = $r->($id);
        next if $used{$id}++;
        my $x = $by{$id} or next;
        push @q, map { ref $_ ? @$_ : $_ } grep { defined } $x->{inputs}->@*;
        push @q, grep { defined } $x->{mem_in}, $x->{control_in}, $x->{head}, ( $x->{fields} // {} )->{region};
    }
    my @live = grep { !exists $fwd->{ $_->{id} } && $used{ $_->{id} } } values %by;
    my ( %own, %refs );
    for my $n (@live) {
        my %f = %{ $n->{fields} // {} };
        # (a coercion's ends are stamps; a line is where a message says the
        # program was -- a scout's walk of the body left its last line for
        # the test after it: Carp::trusts' `@$partial` said 722 for 715)
        delete @f{qw(from_repr to_repr line)} unless $stamps;
        my @ref = map { ref $_ ? [ map { $r->($_) } @$_ ] : $r->($_) } $n->{inputs}->@*;
        push @ref, map { $r->($_) } grep { defined } $n->{mem_in}, $n->{control_in}, $n->{head};
        for my $k ( sort keys %f ) {
            if ( $REF{$k} ) { push @ref, "$k=" . ( $r->( $f{$k} ) // '' ); delete $f{$k} }
            elsif ( $k eq 'predecessors' ) { push @ref, "$k=" . join ',', map { $r->($_) // '' } ( ref $f{$k} ? $f{$k}->@* : $f{$k} ); delete $f{$k} }
        }
        # (a memory Phi's stamp is no value's type: the join of its versions')
        $own{ $n->{id} } = $json->encode( [ $n->{op}, \%f, $f{memory} || !$stamps ? '' : $n->{stamp} // '', $n->{mem_out} ? 1 : 0,
            defined $n->{mem_in} ? 1 : 0, defined $n->{control_in} ? 1 : 0 ] );
        $refs{ $n->{id} } = \@ref;
    }
    my %sig = %own;
    my $classes = -1;
    for ( 1 .. 1000 ) {
        my %next;
        for my $id ( keys %own ) {
            my $s = $own{$id} . '|' . join( ';', map {
                ref $_ ? '[' . join( ',', map { $sig{ $_ // '' } // 'none' } @$_ ) . ']'
                : /\A(\w+)=(.*)\z/ ? "$1=" . join( ',', map { $sig{$_} // 'none' } split /,/, $2 )
                : $sig{ $_ // '' } // 'none'
            } $refs{$id}->@* );
            $next{$id} = sha1_hex($s);
        }
        %sig = %next;
        my %u = map { ( $_ => 1 ) } values %sig;
        last if keys(%u) == $classes;
        $classes = keys %u;
    }
    return { map { ( $_ => 1 ) } values %sig };
}

# eval_ids($wire): AN EVAL'S NUMBER is its place among the wire's evals (a
# scout's walk of a body with an eval counted it too: 2 for 1).
sub eval_ids ($w) {
    return unless $w;
    my @n = map { ( $_->{nodes} // [] )->@* } values( ( $w->{methods} // {} )->%* );
    my %seen;
    my @ids = sort { $a <=> $b } grep { !$seen{$_}++ } grep { defined } map { ( $_->{fields} // {} )->{eval_id} } @n;
    my %to = map { ( $ids[$_] => $_ + 1 ) } 0 .. $#ids;
    $_->{fields}{eval_id} = $to{ $_->{fields}{eval_id} } for grep { defined( ( $_->{fields} // {} )->{eval_id} ) } @n;
}

my ( %n, @diff, %stamps_only, %gained );
for my $w (@work) {
    my %wire;
    for my $which (qw(base head)) {
        my $f = cache_of( $which, $w );
        $wire{$which} = -s $f ? eval { $json->decode( do { local ( @ARGV, $/ ) = $f; <> } ) } : undef;
        eval_ids( $wire{$which} );
    }
    my ( $a, $b ) = @wire{qw(base head)};
    my $why;
    if    ( !$a && !$b ) { $n{'no wire either way'}++; next }
    elsif ( !$a || !$b ) { $why = $a ? 'no wire from this producer' : 'no wire from the 9a producer' }
    else {
        my @ga = sort keys( ( $a->{methods} // {} )->%* );
        my @gb = sort keys( ( $b->{methods} // {} )->%* );
        # (A GRAPH THE 9a PRODUCER REFUSED and this one writes is counted
        # apart, GAINED: a scout's throwaway nodes could refuse a graph --
        # a value that may die, made by the scout and never reached. What it
        # is worth is the probes' and the census's to say.)
        my %in_b = map { ( $_ => 1 ) } @gb;
        my @lost = grep { !$in_b{$_} } @ga;
        if (@lost) { $why = 'graphs this producer does not write: ' . join ' ', @lost }
        else {
            my %in_a = map { ( $_ => 1 ) } @ga;
            $gained{"$w->[0]\t$w->[1]"} = join ' ', grep { !$in_a{$_} } @gb if @gb > @ga;
            for my $g (@ga) {
                my ( $sa, $sb ) = ( signatures( $a->{methods}{$g} ), signatures( $b->{methods}{$g} ) );
                my $only_a = grep { !$sb->{$_} } keys %$sa;
                my $only_b = grep { !$sa->{$_} } keys %$sb;
                next unless $only_a || $only_b;
                # (the same graph but for stamps and lines: a type the walk
                # knew better, reading the real binding where the scout read a
                # placeholder, or a line the scout left wrong)
                my ( $ta, $tb ) = ( signatures( $a->{methods}{$g}, 0 ), signatures( $b->{methods}{$g}, 0 ) );
                if ( !grep( { !$tb->{$_} } keys %$ta ) && !grep( { !$ta->{$_} } keys %$tb ) ) {
                    $stamps_only{"$w->[0]\t$w->[1]"} .= "$g ";
                    next;
                }
                $why = "$g: $only_a nodes only in 9a's, $only_b only in this one's";
                last;
            }
        }
    }
    if ($why) { push @diff, "$w->[0]\t$w->[1]\t$why"; $n{"$w->[0] DIFFERS"}++ }
    elsif ( $stamps_only{"$w->[0]\t$w->[1]"} ) { $n{"$w->[0] SAME-BUT-STAMPS"}++ }
    elsif ( $gained{"$w->[0]\t$w->[1]"} )      { $n{"$w->[0] GAINED"}++ }
    else      { $n{"$w->[0] SAME"}++ }
}
say "$_ $n{$_}" for sort keys %n;
say "stamps\t$_\t$stamps_only{$_}" for sort keys %stamps_only;
say "gained\t$_\t$gained{$_}" for sort keys %gained;
if ( @diff && $list ) { say for @diff }
elsif (@diff) { say for @diff[ 0 .. ( $#diff < 19 ? $#diff : 19 ) ] }
say @diff ? 'BRAUN-PROOF FAIL ' . scalar(@diff) : 'BRAUN-PROOF PASS';
exit( @diff ? 1 : 0 );
