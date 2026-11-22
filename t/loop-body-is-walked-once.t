# ABOUTME: A loop body is walked once (wire v2 stage 9b, Braun): no scout walks it first, so
# ABOUTME: a nest of six loops walks each body once, not 2^depth times.
use v5.42.0;
use Test2::V0;
use SoN::FromOptree;

# WHY. Before stage 9b each loop translator scouted its body (a throwaway walk
# to learn which variables it rebinds, and again until the stamps settled)
# and then walked it for real; an inner loop scouted again inside each outer
# walk, so a body at depth d was walked about 2^d times (audit 2.2). Braun's
# construction (docs/plans/2026-11-20-wire-v2.md, 5.2) makes the header's
# Phis from a scan of the ops and walks the body once.

my %walks;
{
    no warnings 'redefine';
    my $orig = \&SoN::FromOptree::_walk_loop_body;
    *SoN::FromOptree::_walk_loop_body = sub { $walks{ ${ $_[1] } }++; goto &$orig };
}

# a nest of loops of each translator: while, range foreach, array foreach.
# (Each variable keeps its stamp round its loops: a Phi whose init's stamp
# the back edge loses is a wrong guess, learned by a second walk -- stage 0
# measured 34 such loops in 2059.)
my $src = 'sub { my @a = (1, 2); my $s = 0; my $t = ""; my $i = 0; '
        . 'for my $a1 (1..2) { for my $a2 (@a) { while ($i < 2) { $i++; '
        . 'for my $a4 (1..2) { for my $a5 (@a) { for my $a6 (1..2) { $s += $a6; $t .= $a5 } } } } } } "$s $t" }';
my $cv = eval $src or die $@;
SoN::FromOptree->translate($cv);

is scalar( keys %walks ), 6, 'six loop bodies were walked';
is [ sort { $a <=> $b } values %walks ], [ (1) x 6 ], 'each of them once';

done_testing;
