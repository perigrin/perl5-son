# ABOUTME: Tests SoN::FromOptree single-exit normalization — multi-exit/early-return
# ABOUTME: bodies merge to ONE Return via Region+Phi (Phase 4b-1).

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;

my $renderer = SoN::Render::Text->new();

# A multi-exit body (early return inside a branch) previously died "Stack
# underflow" inside _walk_branch (no return handling) or truncated at the
# first return. Single-exit normalization collects each exit's (value,
# control) and merges them through Region+Phi into ONE Return — the shape
# the LLVM backend's _method_body_root requires (exactly one Return).

subtest 'early return inside a branch does not die' => sub {
    my $sub = eval 'sub ($x) { return 1 if $x; return 2 }';
    my $graph;
    ok(lives { $graph = SoN::FromOptree->translate($sub) },
        'translate does not die on an early-return body')
        or diag($@);
    ok(defined $graph, 'got a graph');
};

subtest 'a multi-exit body normalizes to exactly one Return' => sub {
    my $sub = eval 'sub ($x) { return 1 if $x; return 2 }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph') or return;
    my $rets = $graph->returns;
    is(scalar(@$rets), 1, 'exactly one Return node (single-exit)')
        or diag($renderer->render($graph));
};

subtest 'the merged return value is a Phi over the two exits' => sub {
    my $sub = eval 'sub ($x) { return 1 if $x; return 2 }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph') or return;
    my $text = $renderer->render($graph);
    like($text, qr/Phi/, 'the single Return value is a Phi merge of the two exits')
        or diag($text);
    # The truncation bug produced Return($x) — the actual exit values 1 and 2
    # were dropped. Assert both constants survive (the merge carries them).
    like($text, qr/Constant.*\b1\b/, 'the guarded return value (1) is present')
        or diag($text);
    like($text, qr/Constant.*\b2\b/, 'the fall-through return value (2) is present')
        or diag($text);
};

subtest 'a plain trailing return is unchanged (one Return, no spurious Phi)' => sub {
    my $sub = eval 'sub ($x) { return $x + 1 }';
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'got a graph') or return;
    my $rets = $graph->returns;
    is(scalar(@$rets), 1, 'one Return');
    my $text = $renderer->render($graph);
    like($text, qr/Add/, 'the body computes x + 1');
    unlike($text, qr/Phi/, 'no merge Phi for a single-exit body');
};

subtest 'three exits merge to one Return' => sub {
    my $sub = eval 'sub ($x) { return 1 if $x > 5; return 2 if $x > 0; return 3 }';
    my $graph;
    ok(lives { $graph = SoN::FromOptree->translate($sub) }, 'translate lives')
        or diag($@);
    ok(defined $graph, 'got a graph') or return;
    my $rets = $graph->returns;
    is(scalar(@$rets), 1, 'exactly one Return for three source returns')
        or diag($renderer->render($graph));
};

done_testing;
