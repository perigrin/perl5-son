#!/usr/bin/perl
# ABOUTME: Round-trip census of the pvm corpus through LLVM: B::SoN's graph, lowered
# ABOUTME: by chalk at a pinned commit, run by lli, its stdout compared with perl's.
#
# RUNG 1 OF LOWERING PERL'S t/ TO LLVM (perigrin, 2026-10-22): the corpus
# first, because its cases are small whole programs with a recorded output,
# and what chalk's backend cannot lower yet is ranked by how often it is
# needed -- GAP_CAUSE, below. corpus-roundtrip.pl asks the same question of
# the Perl the graph renders to; this asks it of the machine code.
#
# CHALK IS READ AT A PINNED COMMIT, from a clone (SON_CHALK, or
# ~/dev/chalk) through `git archive` -- never its working tree -- so a
# number moves only when the pin does.
#
#   perl tools/corpus-llvm-roundtrip.pl [-v] [--commit SHA] [--jobs N]
#
# Buckets, one per case:
#   ROUNDTRIP  lli printed exactly the recorded output
#   DIFFERS    lli ran to completion and printed something else
#   LLI_FAIL   lli exited non-zero or timed out
#   GAP        chalk refused to lower it, naming why
#   LOAD_FAIL  chalk could not load the graph (an op it does not know, a
#              malformed wire) -- a GAP it raises by name while loading, a
#              BEGIN block it will not drop, is a GAP
#   NOJSON     B::SoN produced no graph
use v5.42.0;
use FindBin;
use File::Temp qw(tempdir);
use Getopt::Long;
use lib "$FindBin::Bin/lib";
use PvmCorpus qw(read_cases);
use CorpusLlvmCause;

# chalk's bson/llvm-corpus branch, where the backend work for this census
# lands -- not the chalk-lib census's 5948f648, which stays put.
my $COMMIT  = '75cdf33e';
my $jobs    = 8;
my $verbose = 0;
my $timeout = 60;
GetOptions('commit=s' => \$COMMIT, 'jobs=i' => \$jobs, 'v' => \$verbose,
           'timeout=i' => \$timeout)
    or die "usage: $0 [-v] [--commit SHA] [--jobs N] [--timeout S]\n";

my $C     = $ENV{SON_CORPUS} // "$FindBin::Bin/../t/corpus/mdtest/pvm";
my $chalk = $ENV{SON_CHALK}  // "$ENV{HOME}/dev/chalk";
die "no corpus at $C (set SON_CORPUS)\n"            unless -d $C;
die "no chalk clone at $chalk (set SON_CHALK)\n"     unless -d "$chalk/.git";
my ($lli) = grep { -x } map { "$_/lli" } split /:/, $ENV{PATH};
die "no lli on PATH\n" unless $lli;

my $dir  = tempdir(CLEANUP => 1);
my $snap = "$dir/chalk";
mkdir $snap;
system("git -C '$chalk' archive '$COMMIT' lib t/lib | tar -x -C '$snap'") == 0
    or die "cannot read $COMMIT from $chalk\n";

my @cases = read_cases($C);
printf "cases: %d\n", scalar @cases;

# ONE CASE, START TO FINISH, in its own process: chalk is loaded fresh for
# each, and a lowering that hangs or dies costs one case, not the census.
sub run_case ($id, $c) {
    my $base = "$dir/c$id";
    open my $o, '>', "$base.pl" or die $!; print $o $c->{src}; close $o;
    qx($^X -I$FindBin::Bin/../lib -MO=-q,SoN,json,not_package=SoN $base.pl > $base.json 2> $base.err);
    # A PROGRAM THE PRODUCER REFUSES is skipped, and B::SoN says why on
    # stderr: a refusal by name, so a GAP with that reason -- not the load
    # failure chalk reports for a graph set with no program in it.
    my ($refused) = do { local (@ARGV, $/) = "$base.err"; -e "$base.err" ? <> : '' }
        =~ /skipped main::__PROGRAM__: (GAP: .*)/;
    return ('NOJSON', 'B::SoN produced no graph') unless -s "$base.json";
    my $why = qx(timeout $timeout $^X -I$snap/lib -I$snap/t/lib $FindBin::Bin/chalk-lower.pl $base.json $base.ll 2>/dev/null);
    chomp $why;
    if ($?) {
        return ('GAP', $1)       if $why =~ /^LOAD: ((?:from_json failed: )?GAP:.*)/;
        return ('GAP', "producer: $refused")
            if defined $refused && $why =~ /^LOAD: no program graph/;
        return ('LOAD_FAIL', $1) if $why =~ /^LOAD: (.*)/;
        return ('GAP', $1)       if $why =~ /^GAP: (.*)/;
        return ('GAP', 'chalk timed out or died lowering it');
    }
    my $got = qx(timeout $timeout $lli $base.ll 2>/dev/null </dev/null);
    return ('LLI_FAIL', 'lli exited ' . ($? >> 8)) if $?;
    return $got eq $c->{want} ? ('ROUNDTRIP', '') : ('DIFFERS', '');
}

# A FIXED NUMBER OF WORKERS, each writing its verdict to a file.
my (@status, %kids);
my @queue = (0 .. $#cases);
while (@queue || %kids) {
    while (@queue && keys(%kids) < $jobs) {
        my $i = shift @queue;
        my $pid = fork // die "fork: $!";
        if (!$pid) {
            my ($bucket, $why) = run_case(sprintf('%03d', $i + 1), $cases[$i]);
            open my $f, '>', "$dir/s$i" or exit 1;
            print $f "$bucket\t$why";
            exit 0;
        }
        $kids{$pid} = $i;
    }
    my $pid = waitpid(-1, 0);
    my $i = delete $kids{$pid} // next;
    my $line = do { local (@ARGV, $/) = "$dir/s$i"; -e "$dir/s$i" ? <> : "LOAD_FAIL\tworker died" };
    $status[$i] = [ split /\t/, $line, 2 ];
}

my (%tally, %cause);
for my $s (@status) {
    $tally{ $s->[0] }++;
    $cause{ $s->[0] }{ CorpusLlvmCause::cause_key($s->[1]) }++
        if $s->[0] =~ /\A(?:GAP|LOAD_FAIL)\z/;
}
$tally{$_} //= 0 for qw(ROUNDTRIP DIFFERS LLI_FAIL GAP LOAD_FAIL NOJSON);
printf "%-10s %d\n", $_, $tally{$_} for sort keys %tally;

# WHAT TO BUILD NEXT: chalk's refusals, and the node types its loader does
# not know yet, by how many cases each blocks (CorpusLlvmCause::cause_key).
for ([GAP => 'GAP_CAUSE'], [LOAD_FAIL => 'LOAD_CAUSE']) {
    my ($bucket, $label) = $_->@*;
    my $r = $cause{$bucket} // {};
    printf "%s %3d %s\n", $label, $r->{$_}, $_
        for sort { $r->{$b} <=> $r->{$a} || $a cmp $b } keys %$r;
}

if ($verbose) {
    for my $i (0 .. $#cases) {
        printf "STATUS %03d %-9s %s: %s\n", $i + 1, $status[$i][0],
            $cases[$i]{file} =~ s{.*/}{}r, $status[$i][1] // '';
    }
}
