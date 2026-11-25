# ABOUTME: The pre-scan's facts equal what the walk finds, over the corpus and the probes: the foreach
# ABOUTME: iterator's write and the slots a loop body rebinds, both ways (audit 2, risk 4 and item 3).
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use lib 'tools/lib';
use PvmCorpus qw(read_cases);

# WHY. A loop's header decides from the ops, before the body is walked, which
# slots the body rebinds and whether it writes the foreach iterator (Braun,
# with a pre-scan Braun does not need). A fact the walk finds and the scan did
# not is refused by name where it is found (t/loop-body-is-walked-once.t makes
# each scan miss). This holds the two answers EQUAL on every loop of the
# corpus and the probes (t/lib/ScanAgree.pm): a miss the walk refuses is a
# probe's REFUSED, an answer the scan gave that the walk did not need is a
# Phi or a pin built for nothing -- either is a scan that is not the walk's
# rule, and is listed here by name.
#
# shortcut: two facts, not four -- a Phi's stamp and an aggregate written
# after a flattening read are refused where the walk meets them, and not
# compared here; upgrade when one is found disagreeing.

my %known;    # file => [ lines ]: disagreements a probe was written to show, refused by name
%known = (
);

SKIP: {
    skip 'SON_SCAN_AGREE_QUICK set', 3 if $ENV{SON_SCAN_AGREE_QUICK};
    my $dir = tempdir( CLEANUP => 1 );
    my @files;
    my $i = 0;
    for my $c ( read_cases('t/corpus/mdtest/pvm') ) {
        my $f = sprintf '%s/%03d.pl', $dir, ++$i;
        open my $o, '>', $f or die $!;
        print $o $c->{src};
        close $o;
        push @files, $f;
    }
    push @files, sort glob 'docs/research/son-ir-audit-2026-11-19/probes/*/*.pl';
    my $jobs = $ENV{SON_SCAN_AGREE_JOBS} // 4;
    my ( %kids, @differ, $loops, $ran );
    my $reap = sub {
        my $pid = waitpid -1, 0;
        my $f = delete $kids{$pid} // return;
        open my $fh, '<', "$dir/out.$pid" or return;
        $ran++;
        my $name = $f =~ s{\A\Q$dir\E/|\Adocs/research/son-ir-audit-2026-11-19/probes/}{}r;
        while (<$fh>) {
            chomp;
            $loops++;
            push @differ, "$name: $_" if /^ITER \S+ \S+ scan=(\d) walk=(\d)/ && $1 != $2
                || /^SLOTS \S+ missed=(\S+) extra=(\S+)/ && ( $1 ne '-' || $2 ne '-' );
        }
    };
    for my $f (@files) {
        $reap->() while keys %kids >= $jobs;
        my $pid = fork // die "fork: $!";
        if ( !$pid ) {
            exec "ulimit -v 4000000; /usr/bin/timeout 900 $^X -Ilib -It/lib -MScanAgree -MO=-q,SoN,json,not_package=SoN '$f' 2>&1 >/dev/null"
               . " | grep -E '^(ITER|SLOTS) ' > '$dir/out.$$'";
        }
        $kids{$pid} = $f;
    }
    $reap->() while %kids;
    is $ran, scalar @files, 'every corpus case and probe was compiled';
    cmp_ok $loops // 0, '>=', 1000, 'and their loops were compared (the instrument ran)';
    is [ sort @differ ], [ sort map { my $f = $_; map { "$f: $_" } $known{$f}->@* } keys %known ], 'the pre-scan said what the walk found';
}

done_testing;
