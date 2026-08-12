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
# recognised, or the fix would simply disable the detection. This one is
# expected to keep GAPping (it is the real 2b-3 mixed effect), so assert the
# GAP is still raised rather than that it translates.
subtest 'a void call genuinely inside the arm is still detected' => sub {
    my $sub = eval 'sub { my $n = 5; my $x = 0; if ($n > 0) { say("in"); $x = 1 } $x }';
    ok(defined $sub, 'compiled the probe sub') or diag($@);
    my $graph = eval { SoN::FromOptree->translate($sub) };
    my $err   = $@ // '';
    ok(!defined $graph && $err =~ /GAP/,
        'an in-arm void call plus a rebind still GAPs (2b-3)')
        or diag("got graph=" . (defined $graph ? 'yes' : 'no') . " err=$err");
};

done_testing;
