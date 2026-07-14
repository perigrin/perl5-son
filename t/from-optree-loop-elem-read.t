# ABOUTME: A loop-Phi-indexed element read ($a[$i] in a loop body) lowers: the
# ABOUTME: element read carries the container's element stamp. zhi 019f5da9/019f6198.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;
use SoN::Render::Text;

my $renderer = SoN::Render::Text->new();

sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

# `for my $i (0..2) { $s += $a[$i] }` reads an array element whose index is a
# loop-carried Phi. Two bugs blocked it:
#   (1) the body SCOUT StackSim had no memory, so the element read's Subscript
#       had an undef memory input and the Node ADJUST crashed (masked by B::SoN
#       as a silent sub-drop) -- fixed by seeding the scout with a MemStart.
#   (2) the element read Subscript was unstamped, so the accumulator's back-edge
#       Add($s_phi, Subscript) was unstamped and _patch_loop_phi refused it
#       ("loop-carried value loses its stamp") -- fixed by stamping an rvalue
#       aelem read with the container's element type.
# It now lowers (element-indexed loops are pervasive in real lib/).

subtest 'a loop-Phi-indexed element read translates (does not GAP or crash)' => sub {
    my $g;
    ok(lives { $g = translate('sub { my @a=(10,20,30); my $s=0; for my $i (0..2) { $s += $a[$i] } $s }') },
        'element-read-in-loop translates') or diag($@);
    ok(defined $g, 'got a graph') or return;
    my @loops = grep { $_->operation eq 'Loop' } $g->nodes->@*;
    is(scalar(@loops), 1, 'exactly one Loop') or diag($renderer->render($g));
    my @subs = grep { $_->operation eq 'Subscript' } $g->nodes->@*;
    ok(scalar(@subs) >= 1, 'the array element read is a Subscript in the graph');
};

subtest 'the same read over a runtime range (0..$#a) translates' => sub {
    my $g;
    ok(lives { $g = translate('sub { my @a=(10,20,30); my $s=0; for my $i (0..$#a) { $s += $a[$i] } $s }') },
        'runtime-range element-read translates') or diag($@);
    ok(defined $g, 'got a graph');
};

done_testing;
