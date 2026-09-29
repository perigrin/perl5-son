# ABOUTME: Opt-in drift check: every ```ir block in pvm's corpus is what B::SoN
# ABOUTME: produces for its case today (SON_CORPUS_IR=<mdtest dir> to run).

use v5.42.0;
use Test2::V0;

# OPT-IN, like the round-trip ratchet: it translates every case in a corpus
# that lives in another repository.
#
# A PRODUCER CHANGE THAT MOVES A GRAPH FAILS HERE, and the fix is to rerun
# `perl tools/corpus-fill-ir.pl DIR` in the same change, so the corpus never
# describes a graph the producer no longer makes.
my $dir = $ENV{SON_CORPUS_IR}
    or skip_all 'set SON_CORPUS_IR to a filled mdtest directory';

my $out = qx($^X tools/corpus-fill-ir.pl --check $dir 2>&1);
my $status = $? >> 8;
my ($cases)   = $out =~ /^cases: (\d+)$/m;
my ($drifted) = $out =~ /^drifted: (\d+)$/m;

# THE DENOMINATOR, so a parse that found nothing cannot pass as "no drift".
ok $cases && $cases >= 200, "the check read the corpus ($cases cases)"
    or diag $out;
is $drifted, 0, 'no ir block has drifted from the producer' or diag $out;
is $status, 0, '... and the check says so';

done_testing;
