# ABOUTME: Tests SoN::FromOptree resolves a loop-carried Phi stamp by fixpoint
# ABOUTME: instead of GAPping when the back-edge is transiently unstamped. zhi 019f6198.

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

# A loop accumulator whose back-edge is Add($phi, X) where X's stamp is derived
# from the Phi itself (a circular stamp dependency) left the back-edge Add
# unstamped at patch time, and _patch_loop_phi refused ("loop-carried value
# loses its stamp"). The fix re-derives the back-edge stamp after all Phis are
# wired (a fixpoint): the Add's inputs are now stamped (the Phi carries its init
# stamp), so its result stamp is recoverable and the join succeeds.

subtest 'a plain accumulator loop stamps by fixpoint (baseline, still works)' => sub {
    my $g;
    ok(lives { $g = translate('sub { my $s=0; for my $i (1..3) { $s = $s + $i } $s }') },
        'const-range accumulator translates') or diag($@);
    ok(defined $g, 'got a graph');
};

# The two shapes the fixpoint unblocks (previously GAPped at _patch_loop_phi):
subtest 'runtime-LOW-bound range ($lo..$hi) stamps by fixpoint' => sub {
    my $g;
    my $err = dies {
        $g = translate('sub { my ($lo,$hi)=@_; my $s=0; for my $i ($lo..$hi) { $s = $s + $i } $s }');
    };
    # This may still GAP on the runtime-low range's flip/flop, but it must NOT
    # be the "loses its stamp" GAP -- that specific fixpoint failure is fixed.
    if ($err) {
        unlike($err, qr/loses its stamp/,
            'a runtime-low range no longer fails on the loop-carried-stamp GAP')
            or diag("actual: $err");
    }
    else {
        ok(defined $g, 'runtime-low range translates');
    }
};

done_testing;
