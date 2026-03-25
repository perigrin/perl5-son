# ABOUTME: Tests for SoN::FromOptree linear (no-branch) optree translation.
# ABOUTME: Verifies basic optree-to-SoN conversion for straight-line code.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;

my $renderer = SoN::Render::Text->new();

subtest 'Translate sub { 1 + 2 } (constant-folded by perl)' => sub {
    my $sub = eval 'sub { 1 + 2 }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/Start/, 'has Start');
    # Perl constant-folds 1+2 to 3, so we see a single Constant(3)
    like($text, qr/Constant\(3\)/, 'has Constant(3) (folded)');
    like($text, qr/Return/, 'has Return');
    diag($text);
};

subtest 'Translate sub with variables that prevent folding' => sub {
    # Use two variable reads so perl can't fold
    my $sub = eval 'sub { my $x = 1; my $y = 2; $x + $y }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/Add/, 'has Add (not folded)');
    like($text, qr/Constant\(1\)/, 'has Constant(1)');
    like($text, qr/Constant\(2\)/, 'has Constant(2)');
    diag($text);
};

subtest 'Translate sub { my $x = 3; my $y = 4; $x * $y + 1 }' => sub {
    my $sub = eval 'sub { my $x = 3; my $y = 4; $x * $y + 1 }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/Multiply/, 'has Multiply');
    like($text, qr/Add/, 'has Add');
    diag($text);
};

subtest 'Constants get Int stamps' => sub {
    my $sub = eval 'sub { 42 }';
    my $graph = SoN::FromOptree->translate($sub);
    my $text = $renderer->render($graph);
    like($text, qr/Constant\(42\).*\[Int\]/, 'integer constant stamped as Int');
    diag($text);
};

subtest 'Text rendering of output matches expected graph structure' => sub {
    my $sub = eval 'sub { my $a = 10; my $b = 20; $a - $b }';
    my $graph = SoN::FromOptree->translate($sub);
    my $text = $renderer->render($graph);
    like($text, qr/Constant\(10\)/, 'has 10');
    like($text, qr/Constant\(20\)/, 'has 20');
    like($text, qr/Subtract/, 'has Subtract');
    like($text, qr/Return/, 'has Return');
    diag($text);
};

done_testing;
