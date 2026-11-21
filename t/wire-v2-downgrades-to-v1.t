# ABOUTME: The proof of wire v2's stage 3: the producer that names memory edges writes, as
# ABOUTME: v1, the very wire the commit before it wrote -- every probe and a corpus sample.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use Cwd qw(getcwd);

# WHY (docs/plans/2026-11-20-wire-v2.md, stage 3, "The proof"). Stage 3 moves
# every memory operand out of a node's inputs into `mem_in` and gives the
# chains their edges; the v1 writer puts the operand back where v1 had it and
# leaves out what v1 has no place for. If any of that changed what a v1
# consumer reads, this says where: the wire of each file, compiled by the
# commit before the change and by this tree, is the same JSON graph by graph
# (tools/wire-diff.pl).
#
# The commit before: $BASE, read from git, or a checkout of it named by
# SON_V1_BASE (a snapshot has no .git: tools/gates.sh extracts it there).
# SON_DOWNGRADE_FULL=1 takes the whole corpus, and with SON_CHALK chalk's lib.
# SON_DOWNGRADE_CACHE keeps the base's wires between runs (they cannot go
# stale: the base is one commit).

my $BASE = '315dd0391047b73ea7929a5b40eee9c0525a0c73';
my $root = getcwd();
my $jobs = $ENV{SON_WIRE_JOBS} // 4;
# ONE HASH ORDER FOR BOTH. The producer is not deterministic on every input:
# chalk's Target/LLVM/Lower.pm gives Builder::read_as_a_truth one of two
# shapes, and Builder::go_round one of two refusals, run to run, under the
# base and under this tree alike. Compared, two runs differ by that alone.
$ENV{PERL_HASH_SEED}    = 0;
$ENV{PERL_PERTURB_KEYS} = 0;

my $base = $ENV{SON_V1_BASE};
unless ( $base && -d "$base/lib" ) {
    $base = tempdir( CLEANUP => 1 );
    system("git -C '$root' archive $BASE 2>/dev/null | tar -x -C '$base'") == 0 && -d "$base/lib"
        or skip_all "no checkout of $BASE: set SON_V1_BASE (tools/gates.sh does)";
}
my $cache = $ENV{SON_DOWNGRADE_CACHE} // tempdir( CLEANUP => 1 );
my $now   = tempdir( CLEANUP => 1 );

my @sets = ('--probes');
push @sets, '--corpus' if $ENV{SON_DOWNGRADE_FULL};
push @sets, '--chalk', $ENV{SON_CHALK} if $ENV{SON_DOWNGRADE_FULL} && $ENV{SON_CHALK} && -d "$ENV{SON_CHALK}/lib";

# The probes are read from THIS tree in both runs (the base's own copy may
# have fewer), so the two compile the same files.
sub compile ( $tree, $wires, @what ) {
    my $out = qx(cd '$tree' && $^X tools/wire-verify.pl --tsv --jobs $jobs --wires '$wires' @what 2>&1);
    return $out;
}
if ( !$ENV{SON_DOWNGRADE_FULL} ) {
    # A SAMPLE OF THE CORPUS: every tenth case, as files both runs read.
    my $sample = tempdir( CLEANUP => 1 );
    require "$root/tools/lib/PvmCorpus.pm";
    my $i = 0;
    for my $c ( PvmCorpus::read_cases("$root/t/corpus/mdtest/pvm") ) {
        next if $i++ % 10;
        open my $o, '>', sprintf( '%s/%03d.pl', $sample, $i ) or die $!;
        print $o $c->{src};
    }
    ok 1, 'corpus sample written';
    for my $pair ( [ $base, $cache ], [ $root, $now ] ) {
        my ( $tree, $wires ) = @$pair;
        for my $f ( glob "$sample/*.pl" ) {
            my $name = ( $f =~ s{.*/}{}r ) =~ s/\.pl$//r;
            my $to   = "$wires/sample/$name.json";
            next if -e $to;
            system("mkdir -p '$wires/sample' && cd '$tree' && ulimit -v 4000000; /usr/bin/timeout 300 $^X -I$tree/lib -MO=-q,SoN,json,not_package=SoN '$f' > '$to' 2>/dev/null");
        }
    }
}
for my $pair ( [ $base, $cache ], [ $root, $now ] ) {
    my ( $tree, $wires ) = @$pair;
    # (the base's wire-verify.pl, when it has one; the probes are this tree's)
    my @what = map { $_ eq '--probes' ? () : $_ } @sets;
    compile( $tree, $wires, @what ) if @what;
    my $pdir = "$root/docs/research/son-ir-audit-2026-11-19/probes";
    my @probes = sort glob "$pdir/*/*.pl";
    system("mkdir -p '$wires/probes'");
    my %kids;
    for my $f (@probes) {
        my $name = $f =~ s{^\Q$pdir\E/|\.pl$}{}gr =~ s{/}{__}gr;
        my $to = "$wires/probes/$name.json";
        next if -e $to;
        if ( keys %kids >= $jobs ) { delete $kids{ waitpid -1, 0 } }
        my $pid = fork // die "fork: $!";
        if ( !$pid ) {
            exec "/bin/sh", "-c", "ulimit -v 4000000; cd '$tree' && /usr/bin/timeout 300 $^X -I$tree/lib -MO=-q,SoN,json,not_package=SoN '$f' > '$to.tmp' 2>/dev/null; mv '$to.tmp' '$to'";
        }
        $kids{$pid} = 1;
    }
    waitpid $_, 0 for keys %kids;
}

# EXCEPT what a v1 bug fix changed on purpose since $BASE, graph by graph
# (t/data/wire-v1-changed-on-purpose.tsv, each with its test).
my $diff = qx($^X $root/tools/wire-diff.pl --allow '$root/t/data/wire-v1-changed-on-purpose.tsv' '$cache' '$now' 2>&1);
my ($line) = $diff =~ /^(# \d+ of \d+ wires differ)$/m;
like $line // $diff, qr/^# 0 of [1-9]\d* wires differ$/, "v1 is the base's wire, byte for byte ($BASE)"
    or diag $diff;

# AND v2 IS ANOTHER WIRE: its version, and no memory_input on it.
my $v2 = qx($^X -Ilib -MO=-q,SoN,json,wire=2 -e 'my \@k; push \@k, 1; print scalar(\@k)' 2>/dev/null);
like $v2, qr/"version"\s*:\s*2/, 'wire=2 says version 2';
unlike $v2, qr/memory_input/, '... and carries no memory_input';

done_testing;
