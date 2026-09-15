# ABOUTME: Tests SoN::FromOptree lowers a foreach over a RUNTIME integer range
# ABOUTME: (for my $i (0..$n) where $n is a runtime value). zhi 019f5da9.

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

# `for my $i (0..$n)` with a runtime $n was refused as "non-constant integer
# bounds". The range still desugars to a counted loop; only the HIGH bound is a
# runtime value now, so the continuation is NumGt(high+1, i_phi) with a runtime
# high. This is the #1 Phase-5 blocker (28 lib/ methods use `for (0..$#x)` /
# `for ($lo..$hi)`).

subtest 'foreach over 0..$n (runtime high bound) translates to a Loop' => sub {
    my $g;
    ok(lives { $g = translate('sub { my ($n)=@_; my $s=0; for my $i (0..$n) { $s += $i } $s }') },
        'runtime-range foreach translates') or diag($@);
    ok(defined $g, 'got a graph') or return;
    my @loops = grep { $_->operation eq 'Loop' } $g->nodes->@*;
    is(scalar(@loops), 1, 'exactly one Loop node') or diag($renderer->render($g));
};

# A range whose LOW bound is also runtime (`for my $i ($lo..$hi)`) used to GAP
# on a loop-carried-stamp limitation: the induction Phi took its stamp from the
# init, and a runtime low bound left it Unknown, so an accumulator's back-edge
# was `Add(Phi/Int, Phi/Unknown)`.
#
# IT NOW LOWERS. The induction variable of a range is ALWAYS Int whatever the
# bounds are -- perl's `..` truncates, measured: `2.7..5.2` yields `2 3 4 5` --
# so the stamp is a fact of the construct rather than something inherited.
#
# THE ASSERTION KEPT ITS INTENT. This subtest read "GAPs loudly, NOT silently
# miscompiles", and the concern was correctness rather than the GAP itself. So
# it now checks the STRONGER property: the loop is built, and the accumulator's
# back-edge is stamped rather than Unknown -- which is what the old GAP existed
# to avoid guessing at.
subtest 'foreach over $lo..$hi (both runtime) lowers with a stamped back-edge' => sub {
    my $g;
    ok(lives { $g = translate('sub { my ($lo,$hi)=@_; my $s=0; for my $i ($lo..$hi) { $s += $i } $s }') },
        'a both-runtime-bound range translates') or diag($@);
    ok(defined $g, 'got a graph') or return;

    my @loops = grep { $_->operation eq 'Loop' } $g->nodes->@*;
    is(scalar(@loops), 1, 'exactly one Loop node') or return;

    # EVERY loop Phi is stamped. An Unknown one is what the old refusal was
    # protecting against, and it would reach the backend as an untyped value.
    my @phis = grep { $_->operation eq 'Phi' } $g->nodes->@*;
    ok(scalar(@phis), 'the loop carries Phis') or return;
    my @unstamped = grep { !$_->stamp || $_->stamp->type eq 'Unknown' } @phis;
    is(scalar(@unstamped), 0, 'and none of them is left Unknown')
        or diag(join ', ', map { $_->operation . '#' . $_->id } @unstamped);
};

done_testing;
