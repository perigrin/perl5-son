#!/usr/bin/env perl
# ABOUTME: Runs SoN::Verify (the memory-chain rules) over the pvm corpus, the audit's
# ABOUTME: probes and, optionally, chalk's lib; prints counts per rule per source.
use v5.42.0;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use JSON::PP;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(basename);
use Getopt::Long;
use PvmCorpus qw(read_cases);
use WireRatchet qw(graph_line);
use SoN::Verify;

# usage: wire-verify.pl [--corpus] [--probes] [--chalk DIR] [--list] [--tsv]
#                       [--wires DIR] [--jobs N]
#   no source named: --corpus --probes.
#   --chalk DIR   every lib/**/*.pm of a chalk checkout (its working tree: the
#                 commit is printed, and the numbers are that commit's).
#   --list        every violation, after the counts.
#   --tsv         only `source<TAB>rule<TAB>count` lines -- the format of
#                 t/data/wire-verify-baseline.tsv, which t/wire-verify-ratchet.t
#                 holds these numbers to. Rules are sorted; `#wires` and
#                 `#graphs` are the denominators, `#dropped` the cases with no
#                 wire, `allowed:*` the floating Assigns that are records or
#                 parameter binds. chalk's lib also gets one line per graph,
#                 `source<TAB>@GRAPH<TAB>rule=n,...` (tools/lib/WireRatchet.pm),
#                 the most any one wire counted for it; a file's own graph,
#                 main::__PROGRAM__, is named by its wire (`Mod::Name:main::...`).
#   A DROPPED WIRE (the compile failed, timed out, or wrote no JSON) is named
#   on stderr, counted as #dropped, and not cached: the next run compiles it.
#   --wires DIR   keep each wire as DIR/SOURCE/NAME.json and reuse one that is
#                 there. A STALE CACHE LIES: empty the directory after any
#                 change to the producer.
#   --jobs N      compile N wires at a time (default 1). The verifying is one
#                 process either way; the compiles are where the time goes.
#   --wire N      the wire version B::SoN writes (`wire=N`, default 1). The
#                 sources of a v2 run are named corpus2, probes2, chalk2, and
#                 SoN::Verify checks them by the v2 rules.
my ( $corpus, $probes, $chalk, $list, $tsv, $wires, $jobs, $wire );
GetOptions( 'corpus' => \$corpus, 'probes' => \$probes, 'chalk=s' => \$chalk,
    'list' => \$list, 'tsv' => \$tsv, 'wires=s' => \$wires, 'jobs=i' => \$jobs, 'wire=i' => \$wire )
    or die "usage: $0 [--corpus] [--probes] [--chalk DIR] [--list] [--tsv] [--wires DIR] [--jobs N] [--wire N]\n";
$jobs //= 1;
$wire //= 1;
die "--wire: 1 or 2\n" unless $wire == 1 || $wire == 2;
my $sfx = $wire == 2 ? '2' : '';
$corpus = $probes = 1 unless $corpus || $probes || $chalk;

my $root = "$FindBin::Bin/..";
my $tmp  = tempdir( CLEANUP => 1 );
$wires //= "$tmp/wires";
my $json = JSON::PP->new->utf8;

# wire($source, $name, $file, $cwd) -> the decoded wire of $file, or undef.
sub wire ( $source, $name, $file, $cwd = undef ) {
    my $cache = "$wires/$source/" . ( $name =~ s{[/:]}{__}gr ) . '.json';
    unless ( -e $cache ) {
        make_path("$wires/$source");
        my $cd = defined $cwd ? "cd '$cwd' && " : '';
        my $inc = defined $cwd ? '-Ilib' : '';
        # 900 s and 4 GB: a producer that spins or balloons is a missing wire
        # (counted below), not a hung census. (300 s was too few for chalk's
        # Target/LLVM and Lower -- four minutes alone -- beside other jobs.)
        my $limit = $ENV{SON_WIRE_TIMEOUT} // 900;
        my $rc = system( "ulimit -v 4000000; $cd/usr/bin/timeout $limit $^X -I$root/lib $inc "
                . "-MO=-q,SoN,json,wire=$wire,not_package=SoN '$file' > '$cache.tmp' 2>/dev/null" );
        if ( $rc == 0 && -s "$cache.tmp" ) { rename "$cache.tmp", $cache or die "$cache: $!" }
        else {
            unlink "$cache.tmp";
            return undef;
        }
    }
    open my $fh, '<', $cache or die "$cache: $!";
    local $/;
    return eval { $json->decode(<$fh>) };
}

# compile_ahead($source, @cases): fill the cache for these cases, $jobs
# compiles at a time. wire() then finds each file there.
sub compile_ahead ( $source, @cases ) {
    my %kids;
    for my $c (@cases) {
        if ( keys %kids >= $jobs ) { delete $kids{ waitpid -1, 0 } }
        my $pid = fork // die "fork: $!";
        if ( !$pid ) { wire( $source, @$c ); exec '/bin/true' }
        $kids{$pid} = 1;
    }
    waitpid $_, 0 for keys %kids;
}

my ( %count, @violations, @sources, %graph );

sub run ( $source, @cases ) {    # each case: [name, file, cwd]
    push @sources, $source;
    $count{$source}{$_} = 0 for '#cases', '#wires', '#graphs', '#dropped';
    compile_ahead( $source, @cases ) if $jobs > 1;
    my $per_graph = $source =~ /^chalk/;
    for my $c (@cases) {
        $count{$source}{'#cases'}++;
        my $w = wire( $source, @$c );
        if ( !$w ) {
            $count{$source}{'#dropped'}++;
            warn "dropped: $source $c->[0] (no wire: the compile failed or timed out)\n";
            next;
        }
        $count{$source}{'#wires'}++;
        my $r = SoN::Verify::verify($w);
        $count{$source}{'#graphs'} += $r->{graphs};
        $count{$source}{"allowed:$_"} += $r->{allowed}{$_} for keys $r->{allowed}->%*;
        my $key = sub ($g) { $g eq 'main::__PROGRAM__' ? "$c->[0]:$g" : $g };
        my %here = map { $key->($_) => {} } keys( ( $w->{methods} // {} )->%* );
        for my $v ( $r->{violations}->@* ) {
            $count{$source}{ $v->{rule} }++;
            $here{ $key->( $v->{graph} ) }{ $v->{rule} }++;
            push @violations, [ $source, "$c->[0]:$v->{graph}#$v->{node}", @$v{qw(op rule detail)} ];
        }
        next unless $per_graph;
        # A graph is in every wire that loads its module: hold the most one wire counts.
        for my $g ( keys %here ) {
            my $h = $graph{$source}{$g} //= {};
            $h->{$_} = $here{$g}{$_} for grep { $here{$g}{$_} > ( $h->{$_} // 0 ) } keys $here{$g}->%*;
        }
    }
}

if ($corpus) {
    my $i = 0;
    my @cases;
    for my $c ( read_cases("$root/t/corpus/mdtest/pvm") ) {
        my $id = sprintf '%03d', ++$i;
        open my $o, '>', "$tmp/$id.pl" or die $!;
        print $o $c->{src};
        close $o;
        push @cases, [ $id, "$tmp/$id.pl" ];
    }
    run( "corpus$sfx" => @cases );
}
if ($probes) {
    my $dir = "$root/docs/research/son-ir-audit-2026-11-19/probes";
    run( "probes$sfx" => map { [ $_ =~ s{^\Q$dir\E/|\.pl$}{}gr, $_ ] } sort glob "$dir/*/*.pl" );
}
if ($chalk) {
    -d "$chalk/lib" or die "no lib/ under $chalk\n";
    chomp( my $at = $ENV{SON_CHALK_AT} // `git -C '$chalk' rev-parse --short=8 HEAD 2>/dev/null` );
    say "# chalk at $at" unless $tsv;
    chomp( my @mods = `cd '$chalk' && find lib -name '*.pm' | sort` );
    run( "chalk$sfx" => map { [ $_ =~ s{^lib/|\.pm$}{}gr, $_, $chalk ] } @mods );
}

my %rules = map { $_ => 1 } map { keys %$_ } values %count;
my @rules = sort keys %rules;
if ($tsv) {
    for my $s (@sources) { say join "\t", $s, $_, $count{$s}{$_} // 0 for @rules }
    for my $s (@sources) { say graph_line( $s, $_, $graph{$s}{$_} ) for sort keys( ( $graph{$s} // {} )->%* ) }
    exit 0;
}
printf "%-44s" . ( ' %8s' x @sources ) . "\n", 'rule', @sources;
for my $r (@rules) { printf "%-44s" . ( ' %8d' x @sources ) . "\n", $r, map { $count{$_}{$r} // 0 } @sources }
if ($list) {
    say '';
    say join "\t", @$_ for @violations;
}
