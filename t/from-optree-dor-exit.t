# ABOUTME: `E // return X` threads the // fallback return as a real early exit (zhi 019f26a5).
# ABOUTME: Was: the return was dropped and E//return became DefinedOr(E,E) -- a silent miscompile.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    return SoN::FromOptree->translate($cv);
}

sub ops_of ($g) {
    my %seen;
    return grep { !$seen{$_}++ } map { $_->operation } $g->nodes->@*;
}

# `my $x = E // return "f"; $x + 1` has TWO exits: an early return "f" when E is
# undef, and the fall-through ($x + 1) when E is defined. The dor handler walked
# the // fallback arm WITHOUT the exits arrayref, so the return was not recorded
# as an exit -- it fell through, the DefinedOr got E as both inputs, and both the
# returned "f" and the fall-through $x+1 vanished (returned E, a silent
# miscompile on both paths).
subtest 'E // return X threads the fallback return as an early exit' => sub {
    my $g = translate('sub { my $e = shift; my $x = $e // return "f"; $x + 1 }');
    my @ops = ops_of($g);

    # The defined-guard must appear as real control flow: an If on defined(E).
    ok((grep { $_ eq 'If' } @ops), 'a defined-guard If is emitted')
        or diag("ops = [@ops]");
    ok((grep { $_ eq 'Defined' } @ops), 'the guard tests defined(E)')
        or diag("ops = [@ops]");

    # Two exits: the early return "f" and the fall-through -- merged via a Region
    # + Phi into the single Return (the backend's single-exit shape).
    my @regions = grep { $_->operation eq 'Region' } $g->nodes->@*;
    ok(@regions >= 1, 'the two exits merge through a Region')
        or diag("ops = [@ops]");

    # The fall-through value $x + 1 must survive (it was dropped pre-fix).
    ok((grep { $_ eq 'Add' } @ops), 'the fall-through $x + 1 is not dropped')
        or diag("ops = [@ops]");

    # The literal "f" return value must survive (it was dropped pre-fix).
    my $has_f = grep {
        $_->operation eq 'Constant'
            && defined $_->value && $_->value eq 'f'
    } $g->nodes->@*;
    ok($has_f, 'the early-return value "f" is not dropped') or diag("ops = [@ops]");
};

# A plain value `//` (no return) must still lower to a single DefinedOr node.
subtest 'plain E // V (value fallback) still a single DefinedOr' => sub {
    my $g = translate('sub { my $e = shift; my $x = $e // 7; $x }');
    my @ops = ops_of($g);
    ok((grep { $_ eq 'DefinedOr' } @ops), 'value // keeps its DefinedOr')
        or diag("ops = [@ops]");
    ok(!(grep { $_ eq 'If' } @ops), 'no spurious If for a plain value //')
        or diag("ops = [@ops]");
};

done_testing();
