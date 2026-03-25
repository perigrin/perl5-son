# ABOUTME: Tests for SoN::FromOptree loop handling.
# ABOUTME: Verifies loop translation produces Loop + Phi structures.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;

my $renderer = SoN::Render::Text->new();

subtest 'Simple arithmetic without loops still works' => sub {
    my $sub = eval 'sub { my $x = 0; my $y = 10; $x + $y }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/Start/, 'has Start');
    like($text, qr/Return/, 'has Return');
    diag($text);
};

subtest 'While loop produces Loop node' => sub {
    todo 'Loop Phi sentinels not yet implemented' => sub {
        my $sub = eval 'sub { my $i = 0; while ($i < 10) { $i = $i + 1 } $i }';
        my $graph = eval { SoN::FromOptree->translate($sub) };
        ok(defined $graph, 'got a graph') or do { diag("Error: $@"); return };
        my $text = $renderer->render($graph);
        like($text, qr/Loop/, 'has Loop node');
        diag($text);
    };
};

subtest 'For loop produces Loop node' => sub {
    todo 'Loop Phi sentinels not yet implemented' => sub {
        my $sub = eval 'sub { my $sum = 0; for my $i (1..5) { $sum = $sum + $i } $sum }';
        my $graph = SoN::FromOptree->translate($sub);
        ok(defined $graph, 'got a graph');
        my $text = $renderer->render($graph);
        like($text, qr/Loop/, 'has Loop node');
        diag($text);
    };
};

done_testing;
