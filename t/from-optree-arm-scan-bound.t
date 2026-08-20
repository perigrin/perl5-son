# ABOUTME: The void-arm scans must stop at the arm's end, not run into later statements.
# ABOUTME: A postfix modifier followed by a print must not be read as a void-call arm.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;

my $renderer = SoN::Render::Text->new();

# `$x = 1 if COND` is a pure scalar rebind: the arm is the sassign and nothing
# else. A `print`/`say` in a LATER statement is not in the arm.
#
# _arm_has_void_call / _arm_has_element_store bound their walk with
# `$$op != $stop`, so $stop must be an ADDRESS. This call site passed
# `$op->next` -- a B::OP OBJECT -- and the comparison never matched, so the
# scan ran past the arm to the end of the sub and saw the later `say`. That
# made $mem_branch true for a branch with no effect in its arm, which then hit
# the 2b-3 "void call combined with a scalar rebind" GAP. Corpus
# control-flow.md D4; also t/base/term.t and translate.t.
subtest 'a scalar-rebind modifier followed by a later say is not a void-call arm' => sub {
    my $sub = eval 'sub { my $n = 5; my $x = 0; $x = 1 if $n > 0; say($x); }';
    ok(defined $sub, 'compiled the probe sub') or diag($@);
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'translated without a GAP');
};

subtest 'the same shape with print rather than say' => sub {
    my $sub = eval 'sub { my $n = 5; my $x = 0; $x = 1 if $n > 0; print $x; }';
    ok(defined $sub, 'compiled the probe sub') or diag($@);
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'translated without a GAP');
};

subtest 'block form of the same conditional rebind' => sub {
    my $sub = eval 'sub { my $n = 5; my $x = 0; if ($n > 0) { $x = 1 } say($x); }';
    ok(defined $sub, 'compiled the probe sub') or diag($@);
    my $graph = SoN::FromOptree->translate($sub);
    ok(defined $graph, 'translated without a GAP');
};

# The BILATERAL partner: a void call genuinely INSIDE the arm must still be
# RECOGNISED, or a fix could pass by simply disabling the detection.
#
# What changed 2026-08-20: recognising it no longer means refusing it. A void
# call plus a scalar rebind now lowers correctly (chalk `f2971b5f` + `9ce43cdd`;
# 14 bilateral shapes measured against perl), so asserting a GAP here would pin a
# refusal that outlived its defect.
#
# The guard's INTENT is preserved by asserting what recognition produces: the arm
# must keep its Call AND merge the rebind through a Phi. A detection that had been
# switched off would drop one or the other, and this fails.
subtest 'a void call genuinely inside the arm is still detected' => sub {
    my $sub = eval 'sub { my $n = 5; my $x = 0; if ($n > 0) { say("in"); $x = 1 } $x }';
    ok(defined $sub, 'compiled the probe sub') or diag($@);

    my $graph = eval { SoN::FromOptree->translate($sub) };
    ok(defined $graph, 'an in-arm void call plus a rebind now translates')
        or do { diag("err=$@"); return };

    # Render rather than hand-walk: translate() returns the graph's Return node,
    # and the renderer already knows how to reach everything from it.
    my $text = $renderer->render($graph);
    like($text, qr/\b(?:Call|Print)\b/, 'the in-arm void call survives the merge')
        or diag($text);
    like($text, qr/\bPhi\b/, 'the rebind still merges through a Phi')
        or diag($text);
};

# THE SURVIVING REFUSAL, pinned so lifting the scalar-rebind half cannot quietly
# take the element-store half with it.
#
# CHARACTERIZATION, not an endorsement. Measured 2026-08-20: for
# `if ($n==0) { $a[0]=9; $n=5 }` the producer emits If/Proj/Region/Phi for the
# scalar rebind and NO STORE NODE AT ALL -- the `$a[0]=9` is silently dropped.
# The graph is therefore WRONG, and what stops it becoming a wrong answer is
# chalk's backend refusing it ("a branch arm that both rebinds a scalar and
# stores an element", Target/LLVM/Context.pm), verified firing today.
#
# So this asserts the drop is still happening, to detect the day it changes in
# either direction: if the producer learns to emit the store this goes red and
# the backend refusal can be revisited; if the backend refusal is ever removed
# while the drop remains, the corpus is the thing that catches it. Do NOT read
# this passing as the shape being supported.
subtest 'CHARACTERIZATION: a rebind PLUS an element store still drops the store' => sub {
    my $sub = eval 'sub { my @a=(1,2,3); my $n=0; if ($n==0) { $a[0]=9; $n=5 } $n }';
    ok(defined $sub, 'compiled the probe sub') or diag($@);

    my $graph = eval { SoN::FromOptree->translate($sub) };
    ok(defined $graph, 'the producer builds a graph (the refusal is the backend\'s)')
        or do { diag("err=$@"); return };

    my $text = $renderer->render($graph);
    unlike($text, qr/\bElementStore\b|\bStore\b/,
        'the element store is still absent -- this graph is WRONG and the '
      . 'backend must keep refusing it')
        or diag($text);
};

done_testing;
