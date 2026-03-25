# ABOUTME: Tests for SoN::FromOptree try/catch translation.
# ABOUTME: Verifies try/catch produces correct CFG structure with Region merge.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;

my $renderer = SoN::Render::Text->new();

subtest 'try/catch translates to Region merge' => sub {
    my $sub = eval 'use feature "try"; no warnings "experimental::try"; sub { try { 42 } catch ($e) { 0 } }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/Start/, 'has Start');
    like($text, qr/Return/, 'has Return');
    like($text, qr/Region/, 'has Region merge for try/catch paths');
    diag($text);
};

subtest 'try/catch with variable binding' => sub {
    my $sub = eval 'use feature "try"; no warnings "experimental::try"; sub { my $r; try { $r = 42 } catch ($e) { $r = 0 } $r }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/Start/, 'has Start');
    diag($text);
};

done_testing;
