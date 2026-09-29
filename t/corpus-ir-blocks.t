# ABOUTME: Opt-in drift check: every graph block in t/corpus/mdtest is what B::SoN
# ABOUTME: produces for its case today (SON_CORPUS_IR=1 to run).

use v5.42.0;
use Test2::V0;

# OPT-IN, like the round-trip ratchet: it translates every case in both of our
# corpus copies, which takes several minutes.
#
# A PRODUCER CHANGE THAT MOVES A GRAPH FAILS HERE, and the fix is to rerun
# `perl tools/corpus-fill-ir.pl` in the same change, so the corpus never
# describes a graph the producer no longer makes.
skip_all 'set SON_CORPUS_IR=1 to check the corpus graph blocks'
    unless $ENV{SON_CORPUS_IR};

my $out = qx($^X tools/corpus-fill-ir.pl --check 2>&1);
my $status = $? >> 8;
my ($cases)   = $out =~ /^cases: (\d+)$/m;
my ($drifted) = $out =~ /^drifted: (\d+)$/m;

# THE DENOMINATOR, so a parse that found nothing cannot pass as "no drift".
ok $cases && $cases >= 400, "the check read both corpora ($cases cases)"
    or diag $out;
is $drifted, 0, 'no graph block has drifted from the producer' or diag $out;
is $status, 0, '... and the check says so';

done_testing;
