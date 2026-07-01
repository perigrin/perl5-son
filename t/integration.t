# ABOUTME: Integration tests comparing optree-translated SoN graphs against expected output.
# ABOUTME: Validates the full pipeline and provides infrastructure for Chalk comparison.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;
use SoN::Compare;

my $renderer = SoN::Render::Text->new();

# Helper: translate and render
sub translate_and_render ($sub) {
    my $graph = SoN::FromOptree->translate($sub);
    return ($graph, $renderer->render($graph));
}

# --- Arithmetic expressions ---

subtest 'Simple addition' => sub {
    my ($graph, $text) = translate_and_render(eval 'sub { my $a = 3; my $b = 4; $a + $b }');
    like($text, qr/Constant\(3\).*\[Int\]/, 'constant 3');
    like($text, qr/Constant\(4\).*\[Int\]/, 'constant 4');
    like($text, qr/Add/, 'addition');
    diag($text);
};

subtest 'Chained arithmetic' => sub {
    my ($graph, $text) = translate_and_render(eval 'sub { my $a = 1; my $b = 2; my $c = 3; ($a + $b) * $c }');
    like($text, qr/Add/, 'addition');
    like($text, qr/Multiply/, 'multiplication');
    diag($text);
};

subtest 'String concatenation' => sub {
    my ($graph, $text) = translate_and_render(eval 'sub { my $a = "hello"; my $b = " world"; $a . $b }');
    like($text, qr/Concat/, 'concatenation');
    diag($text);
};

# --- Variable assignment ---

subtest 'Variable assignment and use' => sub {
    my ($graph, $text) = translate_and_render(eval 'sub { my $x = 42; $x }');
    like($text, qr/Constant\(42\)/, 'constant assigned');
    like($text, qr/Return/, 'returns');
    diag($text);
};

# --- Conditionals ---

subtest 'Ternary operator' => sub {
    my ($graph, $text) = translate_and_render(eval 'sub { my $x = 1; $x ? 10 : 20 }');
    like($text, qr/TernaryExpr/, 'TernaryExpr node');
    diag($text);
};

subtest 'Short-circuit and' => sub {
    # `&&` is an operand-returning short-circuit op: the producer emits a single
    # And node (corpus logical.md L1); the backend expands it to the br+phi.
    my ($graph, $text) = translate_and_render(eval 'sub { my $a = 1; my $b = 2; $a && $b }');
    like($text, qr/And/, 'And node for &&');
    diag($text);
};

# --- Subroutine calls ---

subtest 'Function call' => sub {
    my ($graph, $text) = translate_and_render(eval 'sub { abs(-42) }');
    like($text, qr/Call|Constant/, 'function call or folded');
    diag($text);
};

# --- Feature class ---

class IntegrationTestClass {
    field $x :param :reader;
    field $y :param :reader;

    method magnitude () { $x * $x + $y * $y }
}

subtest 'Feature class field access' => sub {
    my ($graph, $text) = translate_and_render(\&IntegrationTestClass::magnitude);
    like($text, qr/FieldAccess.*index: 0.*IntegrationTestClass/, 'field $x access');
    like($text, qr/FieldAccess.*index: 1.*IntegrationTestClass/, 'field $y access');
    like($text, qr/Multiply/, 'multiplication');
    like($text, qr/Add/, 'addition');
    diag($text);
};

subtest 'Feature class reader method' => sub {
    my ($graph, $text) = translate_and_render(\&IntegrationTestClass::x);
    # Auto-generated :reader methods access the field via pad (the field
    # variable is in the method's pad), which may appear as PadAccess
    # rather than FieldAccess depending on how perl compiles the reader.
    like($text, qr/FieldAccess|PadAccess/, 'reader accesses field via pad or field');
    diag($text);
};

# --- Comparison ---

subtest 'Numeric comparison' => sub {
    my ($graph, $text) = translate_and_render(eval 'sub { my $a = 1; my $b = 2; $a < $b }');
    like($text, qr/NumLt/, 'less-than comparison');
    diag($text);
};

# --- Graph self-comparison ---

subtest 'Same graph compares as identical' => sub {
    my $sub = eval 'sub { my $x = 1; my $y = 2; $x + $y }';
    my $graph = SoN::FromOptree->translate($sub);
    my $diff = SoN::Compare->new()->diff($graph, $graph);
    ok($diff->is_empty, 'self-comparison produces empty diff');
};

# --- Deterministic rendering ---

subtest 'Rendering is deterministic across calls' => sub {
    my $sub = eval 'sub { my $a = 5; my $b = 10; $a * $b - 3 }';
    my $graph = SoN::FromOptree->translate($sub);
    my $text1 = $renderer->render($graph);
    my $text2 = $renderer->render($graph);
    is($text1, $text2, 'same graph renders identically');
};

done_testing;
