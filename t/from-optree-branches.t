# ABOUTME: Tests for SoN::FromOptree branch handling (ternary, and, or).
# ABOUTME: Ternary -> TernaryExpr; && -> And; || -> Or (operand-returning nodes).

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

# `&&`/`||` are operand-returning short-circuit ops. Per corpus/mdtest/
# logical.md L1/L2 the producer emits a single And/Or node over the two
# operands; the Chalk backend expands it into the short-circuit br+phi at
# lowering time (the same producer/backend split DefinedOr uses for `//`).
subtest 'Short-circuit && produces an And node' => sub {
    my $sub = eval 'sub { my $a = 1; my $b = 2; $a && $b }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/And/, 'has And node');
    diag($text);
};

subtest 'Short-circuit || produces an Or node' => sub {
    my $sub = eval 'sub { my $a = 0; my $b = 2; $a || $b }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/Or/, 'has Or node');
    diag($text);
};

done_testing;
