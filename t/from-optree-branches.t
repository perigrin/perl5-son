# ABOUTME: Tests for SoN::FromOptree branch handling (if/else, and, or).
# ABOUTME: Verifies LOGOP branch translation produces If/Proj/Region/Phi.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;

my $renderer = SoN::Render::Text->new();

subtest 'Ternary produces TernaryExpr node' => sub {
    my $sub = eval 'sub { my $x = 1; $x ? 10 : 20 }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/TernaryExpr/, 'has TernaryExpr node');
    diag($text);
};

subtest 'Short-circuit && produces graph' => sub {
    my $sub = eval 'sub { my $a = 1; my $b = 2; $a && $b }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/If/, 'has If node');
    diag($text);
};

subtest 'Short-circuit || produces graph' => sub {
    my $sub = eval 'sub { my $a = 0; my $b = 2; $a || $b }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/If/, 'has If node');
    diag($text);
};

done_testing;
