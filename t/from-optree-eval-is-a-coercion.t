# ABOUTME: `eval STRING` is a Str -> Code coercion the producer STATES; deciding
# ABOUTME: whether it can be lowered belongs to the consumer, not here.
use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub ops_of ($g, $op) { return grep { $_->operation eq $op } $g->nodes->@* }

# THE DIVISION. B::SoN is T1: it states what the program does with types. It
# does not decide what can be lowered -- that is T2, and chalk's.
#
#   producer   "a Str becomes Code here"      -> Coerce[Str -> Code]
#   consumer   "can I emit that conversion?"  -> dies at the Code machine type
#
# Before this, `entereval` was a hand-written refusal in the producer's op
# table, next to `goto`, and ONE eval anywhere refused the WHOLE FILE: perl's
# t/base/lex.t translated 10 nodes and stopped. Now the graph exists and
# exactly one node in it is un-lowerable, which is strictly more information
# and the shape the rest of the producer already uses.
subtest 'string eval builds a Str -> Code coercion' => sub {
    my $g = graph_of('sub { my $x = eval "1+1"; $x }');
    ok($g, 'the graph exists rather than the file being refused') or return;

    my ($c) = grep {
        ($_->from_repr // '') eq 'Str' && ($_->to_repr // '') eq 'Code'
    } ops_of($g, 'Coerce');
    ok($c, 'a Coerce[Str -> Code] is emitted');
};

# THE OPERAND IS THE SOURCE STRING, not something invented. `eval $s` and
# `eval "literal"` differ only in what feeds the coercion.
subtest 'the coercion reads the eval source' => sub {
    my $g = graph_of('sub { my $x = eval "1+1"; $x }');
    my ($c) = grep {
        ($_->from_repr // '') eq 'Str' && ($_->to_repr // '') eq 'Code'
    } ops_of($g, 'Coerce');
    ok($c, 'the coercion exists') or return;
    my ($src) = $c->inputs->@*;
    ok($src, 'it has an operand') or return;
    is($src->operation, 'Constant', 'a literal eval reads a Constant');
    is($src->value, '1+1', 'and it is the source text');
};

subtest 'a variable eval operand works the same way' => sub {
    my $g = graph_of('sub { my $s = "1+1"; my $x = eval $s; $x }');
    my ($c) = grep {
        ($_->from_repr // '') eq 'Str' && ($_->to_repr // '') eq 'Code'
    } ops_of($g, 'Coerce');
    ok($c, 'a runtime operand builds the same coercion');
};

# THE TRAP. `eval "die"` returns undef and sets $@ WITHOUT unwinding -- the
# trap is part of eval, and a graph that omits it claims the program always
# produces a value. The producer already has a shape for "this may or may not
# have thrown": block eval walks both arms and merge()s them into a Region.
# Reused here rather than inventing one.
#
# NOT a TryCatch node. That type exists but has never been constructed, and
# chalk cannot lower it (Context.pm:1463 -- it needs an LLVM landingpad and a
# personality function, which is a design question for a runtime-free backend,
# not a missing arm). Wrapping in one would add a SECOND un-lowerable node to
# describe a refusal, and would misattribute the blocker: the gate would name
# the wrapper when the unsupported thing is the conversion.
subtest 'the trap is modelled, and the coercion is what fails to lower' => sub {
    my $g = graph_of('sub { my $x = eval "1+1"; $x }');
    is(scalar(ops_of($g, 'TryCatch')), 0,
        'no TryCatch node -- chalk cannot lower one');
    ok(scalar(ops_of($g, 'Region')),
        'the may-or-may-not-have-thrown merge is a Region, as block eval uses');
};

# A VOID EVAL MUST NOT VANISH. This is the guard the old refusal-era test
# carried, and it caught a real defect in the first version of this handler:
# with the Coerce left as a pure value node, `eval q{1};` in void context had
# no consumer, dead-code elimination removed the whole chain, and the graph
# kept only a bare Region. The eval had disappeared -- the same silent-drop
# class `write` and `goto` are refused for.
#
# An eval is an EFFECT, not just a value: it can die, and it can define subs.
# So the Coerce is pinned to the control chain, and the value is pushed only
# when someone wants it.
subtest 'a void string eval still appears in the graph' => sub {
    my $g = graph_of('sub { eval q{1}; 7 }');
    my ($c) = grep {
        ($_->to_repr // '') eq 'Code'
    } ops_of($g, 'Coerce');
    ok($c, 'the coercion survives void context') or return;
    ok(defined $c->control_in,
        'and it is pinned to the control chain -- an eval is an effect');
};

# ORDINARY CODE IS UNTOUCHED. The handler is keyed by op name; nothing about
# adding it may disturb constructs that already translate.
subtest 'ordinary code is untouched' => sub {
    ok(lives { graph_of('sub { my $x = 1; $x + 1 }') },
        'plain arithmetic still translates');
    ok(lives { graph_of('sub { my $t = 0; for my $i (1..3) { $t += $i } $t }') },
        'loops still translate');
};

# THE COUNTEREXAMPLE that keeps the meet rule honest, moved here from the
# refusal-era file: meet(ArrayRef, Str) is None and the producer EMITS that
# coercion anyway. A None meet says the types share no common subtype -- it
# says nothing about whether a conversion exists. If this ever GAPs, someone
# has added a `meet == None -> refuse` rule, which would also have refused
# Str -> Code for the wrong reason.
subtest 'a meet==None coercion is still emitted' => sub {
    my $g = graph_of('sub { my $r = [1,2]; print "x" . $r }');
    ok($g, 'ArrayRef -> Str translates, though meet(ArrayRef,Str) is None')
        or return;
    ok(scalar(ops_of($g, 'Coerce')), 'and it really is a Coerce node');
};

done_testing;