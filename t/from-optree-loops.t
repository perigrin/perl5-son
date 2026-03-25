# ABOUTME: Tests for SoN::FromOptree loop handling.
# ABOUTME: Verifies loop translation produces Loop + Phi structures.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;

my $renderer = SoN::Render::Text->new();

subtest 'Simple arithmetic without loops still works' => sub {
    my ($graph, $text) = _translate(eval 'sub { my $x = 0; my $y = 10; $x + $y }');
    like($text, qr/Start/, 'has Start');
    like($text, qr/Return/, 'has Return');
    diag($text);
};

subtest 'While loop produces Loop node' => sub {
    my ($graph, $text) = _translate(eval 'sub { my $i = 0; while ($i < 10) { $i = $i + 1 } $i }');
    like($text, qr/Loop/, 'has Loop node');
    like($text, qr/If/, 'has If for condition');
    like($text, qr/NumLt/, 'has less-than comparison');
    diag($text);
};

subtest 'While loop has Phi for modified variable' => sub {
    my ($graph, $text) = _translate(eval 'sub { my $i = 0; while ($i < 10) { $i = $i + 1 } $i }');
    like($text, qr/Phi/, 'has Phi for loop-carried variable');
    diag($text);
};

subtest 'For loop produces Loop node' => sub {
    my ($graph, $text) = _translate(eval 'sub { my $sum = 0; for my $i (1..5) { $sum = $sum + $i } $sum }');
    like($text, qr/Loop/, 'has Loop node');
    diag($text);
};

sub _translate ($sub) {
    my $graph = SoN::FromOptree->translate($sub);
    my $text = $renderer->render($graph);
    return ($graph, $text);
}

done_testing;
