# ABOUTME: Tests for SoN::FromOptree handling of subroutine signatures.
# ABOUTME: Verifies argelem ops (from 'use feature signatures') translate to PadAccess nodes.

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
    like($text, qr/PadAccess/, 'has PadAccess for signature parameter');
    like($text, qr/Add/, 'has Add node');
    diag($text);
};

subtest 'sub with multiple signature parameters' => sub {
    my $sub = eval 'sub ($a, $b) { $a + $b }';
    die "eval failed: $@" if $@;
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    # Should have PadAccess nodes for both parameters
    my @pad_matches = ($text =~ /PadAccess/g);
    ok(scalar @pad_matches >= 2, 'has PadAccess for both parameters')
        or diag("Only found " . scalar @pad_matches . " PadAccess nodes");
    like($text, qr/Add/, 'has Add node');
    diag($text);
};

subtest 'sub with signature and default value' => sub {
    my $sub = eval 'sub ($x, $y = 10) { $x + $y }';
    die "eval failed: $@" if $@;
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'sub with default value translated');
    my $text = $renderer->render($graph);
    like($text, qr/PadAccess/, 'has PadAccess for signature parameters');
    like($text, qr/Add/, 'has Add node');
    diag($text);
};

done_testing();
