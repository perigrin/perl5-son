# ABOUTME: Tests for SoN::FromOptree call and method dispatch translation.
# ABOUTME: Verifies subroutine and method calls produce Call nodes.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;

sub test_func { 42 }

my $renderer = SoN::Render::Text->new();

subtest 'Direct sub call' => sub {
    my $sub = eval 'sub { test_func(1, 2) }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/Call/, 'has Call node');
    diag($text);
};

subtest 'Builtin call (sqrt)' => sub {
    my $sub = eval 'sub { sqrt(16) }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    # sqrt may be inlined as a builtin op rather than entersub
    like($text, qr/Call|Constant/, 'has Call or folded result');
    diag($text);
};

done_testing;
