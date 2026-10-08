#!/usr/bin/env perl
# ABOUTME: Run chalk's own test suite against a lib/ where every module B::SoN emits
# ABOUTME: cleanly replaces its original, and compare each test file with the original run.
use v5.42.0;
use FindBin;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use Getopt::Long;

# THE SAME PINNED COMMIT as tools/chalk-lib-roundtrip.pl, read the same way:
# `git archive` from a clone, so chalk's working tree never enters.
my $COMMIT  = '5948f648';
my $chalk   = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
my $jobs    = 8;
# 300s, not 120: an emission may run slower than the original, and at 120s
# a test near the limit timed out under load in one run and not the next.
# AN HOUR, not 300s: seven of chalk's files take longer than that against
# the ORIGINAL lib/ -- measured under load, 344s to over 1800s -- and a file
# that times out against the original is SLOW, compared with nothing. Two of
# the seven differed once compared (earley-leo, perl-target-perl-tier-d).
# THREE HOURS, not one: t/bootstrap/perl-recognize-phase5.t recognises every
# .pm under lib/Chalk and took 8003s against the ORIGINAL lib/ (measured
# 2026-10-07, some load) -- SLOW, so compared with nothing. perigrin chose to
# count it at the cost of a longer gate 3 (2026-10-08).
my $timeout = 10800;
my $verbose = 0;   # -v lists DIFFERS rows; -v -v also the SLOW ones
GetOptions('chalk=s' => \$chalk, 'commit=s' => \$COMMIT, 'jobs=i' => \$jobs,
           'timeout=i' => \$timeout, 'v+' => \$verbose)
    or die "usage: $0 [--chalk PATH] [--commit SHA] [--jobs N] [--timeout S] [-v]\n";

my $work = tempdir(CLEANUP => 1);
my ($orig, $mixed, $emit) = map { "$work/$_" } qw(orig mixed emit);
make_path($orig, $mixed);
for my $tree ($orig, $mixed) {
    system("git -C '$chalk' archive '$COMMIT' | tar -x -C '$tree'") == 0
        or die "cannot read $COMMIT from $chalk\n";
}

# THE EMITTED lib/ COMES FROM THE CENSUS TOOL, so the two cannot disagree about
# which modules round-trip. Only a module that compiled with NO graph skipped
# is overlaid: a partial emission would be measured as wrong for a graph it
# never claimed to have.
my $census = `$^X $FindBin::Bin/chalk-lib-roundtrip.pl --chalk '$chalk' --commit '$COMMIT' --emit '$emit' 2>&1`;
open my $list, '<', "$emit/compiles.txt"
    or die "the census wrote no module list:\n$census";
my $overlaid = 0;
while (my $m = <$list>) {
    chomp $m;
    copy("$emit/emit/$m", "$mixed/$m") or die "overlay $m: $!";
    $overlaid++;
}

my @tests = sort split /\n/, `cd '$orig' && find t -name '*.t'`;

# ONE RESULT PER FILE: exit code, and the `ok` and `not ok` counts with TODO
# lines left out. Byte-identical output would be too strict -- addresses,
# timings and hash order vary between two runs of the SAME lib/.
sub run_tree ($tree, $tag, $skip = {}) {
    my %res;
    my @queue = grep { !$skip->{$_} } @tests;
    my %kids;
    while (@queue || %kids) {
        while (@queue && keys(%kids) < $jobs) {
            my $t = shift @queue;
            (my $key = $t) =~ s{/}{__}g;
            my $out = "$work/$tag.$key";
            my $pid = fork // die "fork: $!";
            if (!$pid) {
                chdir $tree or exit 99;
                exec "/bin/sh", "-c",
                    "timeout $timeout $^X -Ilib -It/lib '$t' > '$out.out' 2> '$out.err' < /dev/null; echo \$? > '$out.rc'";
            }
            $kids{$pid} = [$t, $out];
        }
        my $pid = waitpid(-1, 0);
        my ($t, $out) = @{ delete $kids{$pid} // next };
        my $rc = 'NA';
        if (open my $fh, '<', "$out.rc") { $rc = <$fh> // 'NA'; chomp $rc }
        my ($ok, $nok) = (0, 0);
        if (open my $fh, '<', "$out.out") {
            while (<$fh>) {
                # A TODO COUNTS NEITHER WAY: its pass was counted and its
                # fail was not, so a noisy TODO -- earley-leo's timing ratio,
                # "machine-dependent and noisy" by its own description --
                # flipped and differed.
                next if /# TODO/;
                $ok++  if /^\s*ok /;
                $nok++ if /^\s*not ok /;
            }
        }
        $res{$t} = "rc=$rc ok=$ok notok=$nok";
    }
    return \%res;
}

my $o = run_tree($orig,  'orig');
# NOT RUN AGAIN where the original timed out: the file is SLOW whatever the
# emission does, and the second run cost another hour.
my $x = run_tree($mixed, 'mixed',
                 { map { $_ => 1 } grep { $o->{$_} =~ /\Arc=124 / } @tests });

# A TEST THAT TIMES OUT AGAINST THE ORIGINAL has no result to compare: its
# ok count is how far it got before the kill, which moves with machine load.
# Measured, two runs of one commit differed in exactly such files (347 vs
# 348). They are counted as SLOW and left out of SAME / DIFFERS.
# A TEST THAT READS lib/ AS SOURCE -- chalk compiling, comparing or
# golden-checking its own modules -- measures the TEXT, and the emission is
# not the source's text: such a test can score higher against it, and in five
# files did. perigrin: count it as matching when it is NO WORSE -- as many
# passes or more, no more failures, no timeout. A test reads the source when
# it names a lib/Chalk module path or walks lib/.
sub reads_source ($t) {
    open my $fh, '<', "$orig/$t" or return 0;
    local $/;
    my $src = <$fh>;
    return $src =~ m{['"]lib/Chalk[A-Za-z0-9/_:]*\.pm|lib/Chalk/['"]|File::Find|glob\(.*lib} ? 1 : 0;
}
sub counts ($sig) { return $sig =~ /\Arc=(\S+) ok=(\d+) notok=(\d+)\z/ ? ($1, $2, $3) : () }

my ($same, $noworse, $differs, $slow) = (0, 0, 0, 0);
my @rows;
for my $t (@tests) {
    my ($orc, $ook, $onok) = counts($o->{$t});
    my ($xrc, $xok, $xnok) = counts($x->{$t} // q{});
    if ($o->{$t} =~ /\Arc=124 /) { $slow++; push @rows, "$t | SLOW (original timed out)" if $verbose > 1 }
    elsif ($o->{$t} eq $x->{$t}) { $same++ }
    elsif (defined $xok && $xrc ne '124' && $xok >= $ook && $xnok <= $onok
           && reads_source($t)) {
        $noworse++;
        push @rows, "$t | NOWORSE | orig $o->{$t} | emitted $x->{$t}" if $verbose > 1;
    }
    else { $differs++; push @rows, "$t | orig $o->{$t} | emitted $x->{$t}" }
}

print "commit: $COMMIT\n";
print "overlaid: $overlaid\n";
print "files: ", scalar(@tests), "\n";
printf "%-8s %d\n", 'SAME', $same;
printf "%-8s %d\n", 'NOWORSE', $noworse;
printf "%-8s %d\n", 'DIFFERS', $differs;
printf "%-8s %d\n", 'SLOW', $slow;
print "$_\n" for $verbose ? @rows : ();
