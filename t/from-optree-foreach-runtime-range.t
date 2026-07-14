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

# A range whose LOW bound is also runtime (`for my $i ($lo..$hi)`) currently
# GAPs on a separate loop-carried-stamp fixpoint limitation (the induction Phi
# init is a runtime value whose stamp is not yet propagated through the
# back-edge). It must GAP loudly, NOT silently miscompile.
subtest 'foreach over $lo..$hi (both runtime) GAPs loudly (not silent)' => sub {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval 'sub { my ($lo,$hi)=@_; my $s=0; for my $i ($lo..$hi) { $s += $i } $s }';
    SoN::OptSuppress::restore_peep();
    my $err = dies { SoN::FromOptree->translate($cv) };
    ok($err, 'a both-runtime-bound range does not silently miscompile') or diag('expected a GAP');
    like($err, qr/GAP/i, 'the die is a loud GAP') or diag("actual: $err");
};

done_testing;
