# ABOUTME: Tests for SoN::FromOptree handling of subroutine signatures.
# ABOUTME: Verifies argelem ops (from 'use feature signatures') translate to Parameter nodes.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;

my $renderer = SoN::Render::Text->new();

subtest 'sub with single signature parameter' => sub {
    my $sub = eval 'sub ($x) { $x + 1 }';
    die "eval failed: $@" if $@;
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    # A declared parameter is a Parameter node, NOT a PadAccess. The pad slot
    # is perl's STORAGE for the parameter; the parameter itself is a value
    # identified by POSITION. See docs/plans/2026-08-22-parameter-node-design.md
    # in chalk.
    like($text, qr/Parameter/, 'has Parameter for signature parameter');
    unlike($text, qr/PadAccess/,
        'and NOT a PadAccess -- the pad slot is storage, not the parameter');
    like($text, qr/Add/, 'has Add node');
    diag($text);
};

subtest 'sub with multiple signature parameters' => sub {
    my $sub = eval 'sub ($a, $b) { $a + $b }';
    die "eval failed: $@" if $@;
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    # One Parameter per declared parameter, positionally identified.
    my @param_matches = ($text =~ /Parameter/g);
    ok(scalar @param_matches >= 2, 'has Parameter for both parameters')
        or diag("Only found " . scalar @param_matches . " Parameter nodes");
    unlike($text, qr/PadAccess/, 'and no PadAccess for either');
    like($text, qr/Add/, 'has Add node');
    diag($text);
};

subtest 'sub with signature and default value' => sub {
    my $sub = eval 'sub ($x, $y = 10) { $x + $y }';
    die "eval failed: $@" if $@;
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'sub with default value translated');
    my $text = $renderer->render($graph);
    like($text, qr/Parameter/, 'has Parameter for signature parameters');
    like($text, qr/Add/, 'has Add node');
    diag($text);
};

done_testing();
