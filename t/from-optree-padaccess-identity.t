# ABOUTME: Tests the PadAccess cross-graph identity contract (Phase 4b-2).
# ABOUTME: A pad slot's identity must be its variable name, not the CV-local pad index.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# ---------------------------------------------------------------------------
# Phase 4b-2: targ stability.
#
# `targ` is the Perl pad-slot index. It is CV-LOCAL and unstable: an unrelated
# earlier lexical shifts every later slot's index. Two semantically identical
# variable reads must therefore have the SAME identity (content_hash) even when
# they land at different pad indices -- otherwise cross-graph comparison (and
# hash-consing on load) diverges on a value no consumer reads behaviorally.
#
# Decision (4b-2): identity = varname + inputs; targ is NOT identity-bearing.
# ---------------------------------------------------------------------------

# Helper: pull the PadAccess node for a given varname out of a translated graph.
sub padaccess_for ($coderef, $varname) {
    my $graph = SoN::FromOptree->translate($coderef);
    my @hits  = grep {
        $_->operation eq 'PadAccess' && $_->varname eq $varname
    } $graph->nodes->@*;
    return @hits ? $hits[0] : undef;
}

subtest 'identical reads at different pad indices share identity' => sub {
    # Both subs read $x identically. `shifted` has an extra earlier lexical,
    # so its $x lands at a higher pad index (targ) than `plain`'s $x.
    my $plain   = sub { my $x = 5; return $x + 1; };
    my $shifted = sub { my $junk = 9; my $x = 5; return $x + 1; };

    my $p = padaccess_for($plain,   '$x');
    my $s = padaccess_for($shifted, '$x');

    ok(defined $p, 'plain has a PadAccess for $x');
    ok(defined $s, 'shifted has a PadAccess for $x');

    isnt($p->targ, $s->targ,
        'the two reads DO have different pad indices (the instability)');

    is($p->content_hash, $s->content_hash,
        'but their content_hash is identical (targ is not identity-bearing)');
};

subtest 'distinctly named lexicals keep distinct identity' => sub {
    # Regression guard: dropping targ must NOT collapse genuinely different
    # variables. $a and $b are distinct slots with distinct names.
    my $two = sub { my $a = 2; my $b = 3; return $a * $b; };

    my $na = padaccess_for($two, '$a');
    my $nb = padaccess_for($two, '$b');

    ok(defined $na, 'has a PadAccess for $a');
    ok(defined $nb, 'has a PadAccess for $b');

    isnt($na->content_hash, $nb->content_hash,
        'different variable names produce different identity');
};

done_testing();
