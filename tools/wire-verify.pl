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
use SoN::Verify;

# usage: wire-verify.pl [--corpus] [--probes] [--chalk DIR] [--list] [--tsv]
#                       [--wires DIR] [--jobs N]
#   no source named: --corpus --probes.
#   --chalk DIR   every lib/**/*.pm of a chalk checkout (its working tree: the
#                 commit is printed, and the numbers are that commit's).
#   --list        every violation, after the counts.
#   --tsv         only `source<TAB>rule<TAB>count` lines -- the format of
#                 t/data/wire-verify-baseline.tsv, which t/wire-verify-ratchet.t
#                 holds `#wires` and `#graphs` to. Rules are sorted; `#wires`
#                 and `#graphs` are the denominators, `#dropped` the cases with
#                 no wire, `allowed:*` the floating Assigns that are records or
#                 parameter binds. Then one line per violation,
#                 `source<TAB>!<TAB>CASE:GRAPH#NODE<TAB>OP<TAB>RULE<TAB>DETAIL`.
#   A DROPPED WIRE (the compile timed out, was killed, or wrote no JSON) is named
#   on stderr, counted as #dropped, and not cached: the next run compiles it.
#   --wires DIR   keep each wire as DIR/SOURCE/NAME.json and reuse one that is
#                 there. A STALE CACHE LIES: empty the directory after any
#                 change to the producer.
#   --jobs N      compile N wires at a time (default 1). The verifying is one
#                 process either way; the compiles are where the time goes.
my ( $corpus, $probes, $chalk, $list, $tsv, $wires, $jobs );
GetOptions( 'corpus' => \$corpus, 'probes' => \$probes, 'chalk=s' => \$chalk,
    'list' => \$list, 'tsv' => \$tsv, 'wires=s' => \$wires, 'jobs=i' => \$jobs )
    or die "usage: $0 [--corpus] [--probes] [--chalk DIR] [--list] [--tsv] [--wires DIR] [--jobs N]\n";
$jobs //= 1;
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
                . "-MO=-q,SoN,json,not_package=SoN '$file' > '$cache.tmp' 2>/dev/null" );
        # Dropped: timed out (124), killed (the shell says 128 + signal), or no
        # JSON. A program perl rejects (exit 255) keeps the wire B::SoN wrote of
        # what compiled, as it always did.
        my $exit   = $rc >> 8;
        my $killed = $exit == 124 || ( $exit > 128 && $exit < 160 ) || ( $rc & 127 );
        if ( !$killed && -s "$cache.tmp" && eval { $json->decode( do { local ( @ARGV, $/ ) = "$cache.tmp"; <> } ); 1 } ) {
            rename "$cache.tmp", $cache or die "$cache: $!";
        }
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

my ( %count, @violations, @sources );

sub run ( $source, @cases ) {    # each case: [name, file, cwd]
    push @sources, $source;
    $count{$source}{$_} = 0 for '#cases', '#wires', '#graphs', '#dropped';
    compile_ahead( $source, @cases ) if $jobs > 1;
    for my $c (@cases) {
        $count{$source}{'#cases'}++;
        my $w = wire( $source, @$c );
        if ( !$w ) {
            $count{$source}{'#dropped'}++;
            warn "dropped: $source $c->[0] (no wire: the compile timed out, was killed or wrote no JSON)\n";
            next;
        }
        $count{$source}{'#wires'}++;
        my $r = SoN::Verify::verify($w);
        $count{$source}{'#graphs'} += $r->{graphs};
        $count{$source}{"allowed:$_"} += $r->{allowed}{$_} for keys $r->{allowed}->%*;
        for my $v ( $r->{violations}->@* ) {
            $count{$source}{ $v->{rule} }++;
            push @violations, [ $source, "$c->[0]:$v->{graph}#$v->{node}", @$v{qw(op rule detail)} ];
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
    run( "corpus" => @cases );
}
if ($probes) {
    my $dir = "$root/docs/research/son-ir-audit-2026-11-19/probes";
    run( "probes" => map { [ $_ =~ s{^\Q$dir\E/|\.pl$}{}gr, $_ ] } sort glob "$dir/*/*.pl" );
}
if ($chalk) {
    -d "$chalk/lib" or die "no lib/ under $chalk\n";
    chomp( my $at = $ENV{SON_CHALK_AT} // `git -C '$chalk' rev-parse --short=8 HEAD 2>/dev/null` );
    say "# chalk at $at" unless $tsv;
    chomp( my @mods = `cd '$chalk' && find lib -name '*.pm' | sort` );
    run( "chalk" => map { [ $_ =~ s{^lib/|\.pm$}{}gr, $_, $chalk ] } @mods );
}

my %rules = map { $_ => 1 } map { keys %$_ } values %count;
my @rules = sort keys %rules;
if ($tsv) {
    for my $s (@sources) { say join "\t", $s, $_, $count{$s}{$_} // 0 for @rules }
    say join "\t", $_->[0], '!', $_->@[ 1 .. 4 ] for @violations;
    exit 0;
}
printf "%-44s" . ( ' %8s' x @sources ) . "\n", 'rule', @sources;
for my $r (@rules) { printf "%-44s" . ( ' %8d' x @sources ) . "\n", $r, map { $count{$_}{$r} // 0 } @sources }
if ($list) {
    say '';
    say join "\t", @$_ for @violations;
}
