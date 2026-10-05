# Chalk's lib/ round-trips through B::SoN

**Date:** 2026-09-30
**Status:** IN PROGRESS. Goal set by perigrin: "parse all of chalk's lib/
directory and round trip it cleanly".

## The framing question (open)

perigrin: SoN is not really designed around pre-compiled libraries, and
chalk's lib/ is classes rather than applications.

What B::SoN does already: one graph per sub or method, a class as a MOP
record plus its method graphs. So a library file translates. What does NOT
hold is the closed-world assumption the tooling made -- everything a graph
names is in the same wire:

  - a parent class from another file was emitted again ("Cannot reopen
    existing class"; fixed 5425304: marked `external`, left to the `use`);
  - a call to a sub another file defines refuses ("not in the graph");
  - a module's file value (`1;`) is not in the optree when the file is
    compiled as a program -- covered by the target bundle's module_true.

Two framings, perigrin to choose; the per-module one is what is being built
meanwhile, since the coverage work is the same under either:

  1. PER MODULE, OPEN WORLD. Each lib/ file round-trips on its own; open-
     world facts (external class, unresolved callee) are explicit on the
     wire.
  2. WHOLE PROGRAM, CLOSED WORLD. Translate real entry points with the lib/
     code they load as part of the program; the emission is one program per
     entry point, not a lib/ tree.

## The criterion: three gates, separate numbers

  1. PARSE -- every module translates, no graph skipped (no GAP).
  2. EMIT -- every module renders, and the emitted lib/ compiles with only
     itself on @INC.
  3. ROUND TRIP -- chalk's own test suite gives the same per-file result
     against the emitted lib/ as against the original. This is "cleanly".

Measured against a snapshot of chalk HEAD 5948f648 (179 modules, 43k lines,
547 test files), never chalk's working tree.

## Baseline, 2026-09-30 (before any fix)

    179 modules   21 compile (6 with graphs skipped)   77 invalid   81 refused

  - 127 "no Start node": other files' classes emitted (fixed 5425304).
  - 77 "did not return a true value": the bundle was dropped (fixed f7031ba,
    which also makes every emission strict, warnings and `use v5.42;` --
    perigrin's direction).
  - Skipped graphs, the long tail: foreach with an unrecognised bounds shape
    (241), nested and/or in a loop body (67), a ternary with a multi-element
    list arm (27), dor in a loop body (21), next in a branch arm (18), ...

## Defects found on the way, not yet fixed

  - A symbolic `@{"name"}` dereference is dropped by the producer: the
    string stands in for the array (comp/line_debug.t).
  - A loop Phi read before its loop is emitted (comp/retainedlines.t).
  - A string holding a code point past U+10FFFF reaches the wire as perl's
    extended UTF-8, which a strict decoder rejects (comp/parser.t).
  - `print COND ? A : B` over a runtime-regex match crashes the walker ("No
    mark on mark stack"), an internal error rather than a GAP.
  - Emission style that draws warnings: `@foo[1]` for a one-element slice,
    `sort` in scalar context.
  - A `require` inside an `eval` takes the previous statement's value as an
    extra argument -- `require("t/Foo.pm", $eff11)` (comp/filter_exception.t,
    reached once calls to other files' subs stopped refusing).
  - comp/parser_run.t reports EMITS_INVALID_PERL but its emission compiles
    and runs from t/ -- a harness-context difference. Cause: perl-t-roundtrip
    ran `-c` from the repo while running the program from t/; a file whose
    BEGIN does `chdir 't'` (comp/use.t) only compiles from t/. Fixed.
  - An array read in list context after an ELEMENT store reads the literal:
    `my @a=(5,5); $a[0] -= 2; print "@a"` prints `5 5`. The padav flatten
    shortcut is guarded by `mutated_aggregate`, which an element store does
    not set.
  - The target bundle leaks into string evals: `eval "use 5.006"` under the
    emitted `use v5.42;` dies "use VERSION is not permitted while another use
    VERSION of 5.39 or above is in scope" (comp/use.t tests 1-9). Open: the
    bundle is the emission's scope, and a string eval compiles in it.
  - `grep` over a named array holding a literal list refuses: "an element
    of a `PostfixDeref` spelled `(1, 2, ...)` has no aggregate sigil to
    switch" (`my @l = (1..6); my @e = grep {...} @l`). Honest, not wrong.
  - A dynamic method call (`$obj->$m(...)`) is built as a floating Call with
    no control_in and no memory barrier, unlike a named method or a direct
    call (FromOptree _handle_entersub, `dynamic_method`): its effects are
    unordered.
  - `${\ f()}` in a pattern miscompiles: the call is bound as a list
    (`my @eff6 = f()`) and the deref spelled over `\@eff6`, "Not a SCALAR
    reference" -- perl takes a reference to the call's last value.
    `"x" =~ ("a\$|" . $p)` with a constant target is the "No mark on mark
    stack" crash above.
  - SoN::Serialize::JSON recurses per node (line 456): comp/use.t's program
    graph draws "Deep recursion on anonymous subroutine" warnings. Output is
    right; the walk should be iterative.

## Gate 3 reads source: the emission must be Perl chalk can parse

59 of chalk's 547 test files read lib/ modules as INPUT to chalk's own
parser (cfg-statements.t parses lib/Chalk/Grammar/Symbol.pm). Gate 3
overlays those files with the emission, so those tests parse B::SoN's output.
perigrin: chalk will meet the same test compiling itself and "needs to be
able to parse its own output" -- so the file overlay stays and these rows
are gaps, not harness noise.

Run over the 130 emitted modules (chalk's grammar from perl_pipeline):

  - All 130 failed on the preamble: chalk reads `use v5.42.0;` and
    `use 5.42.0;`, not `use v5.42;`.
  - Past it: `undef()` (~20 modules), circumfix `@{EXPR}` / `%{EXPR}`
    (none of chalk's grammar; it reads `@$name` and `EXPR->@*`), and one
    computed pattern `m{(?:${\ (...)})}` (Bootstrap/Terminal.pm).

Renderer spellings now: `use v5.42.0;`, `(undef)`, postfix dereference, and
a computed match pattern written as pattern text when it is a Concat of
string constants and plain scalars (`/\G($p)/` again). Not a `do` block
binding a temporary: `$1` is scoped to the block, and the caller lost the
capture. t/deparse-an-emission-chalk-can-read.t covers each, and runs chalk's
parser over them when a chalk clone is present. After these, chalk parses
110 of the 130 emitted modules; the other 20 are the 19 whose ORIGINALS fail
the same way (below) and Terminal.pm, since fixed.

Still spelled `${\ ...}`, no chalk module reaching them yet: a computed
s/// pattern (_subst_operands), a computed match pattern of any other shape,
and a dynamic method name (`->${\ EXPR}(...)`).

Chalk-side gaps met on the way, at 5948f648, in chalk's semantic actions
rather than its grammar -- they fail the ORIGINAL modules too (19 of 130):

  - "Unknown data node operation: ArrayRef / HashRef" for any anonymous
    `[...]` / `{...}`, `\%h`, and any list of two or more elements
    (`my @x = ($a, $b)`).
  - `@main::x` (a package-qualified aggregate) does not parse. B::SoN spells
    package aggregates qualified (T2.pm: `%Chalk::IR::Transform::T2::...`,
    and a self-assignment `%X = %X;` there worth reading). T2's original
    fails in chalk anyway, so it is not yet on the measured path.

Filed on chalk (perigrin, 2026-10-02): #738 `use v5.42;`, #739 `undef()`,
#740 the ArrayRef/HashRef semantic actions (with the 19 modules), #741 the
Perl target generating `()` for a method with no signature; the circumfix
`@{ EXPR }` form added to #230 as a comment.

Not a spelling: some tests assert the SHAPE of a lib/ file's source. Two
shapes are now reconstructed, by perigrin's decision over the recorded
"ugly and faithful" `$_[N]` rule: a declared signature is emitted as one
(it also restores perl's arity check, which `$_[N]` lost), and a sub that
falls off its end ends on its bare value (the producer marks the Return
`implicit`). `use Module LIST` is spelled `use`, a class keeps its own subs,
and `use experimental 'class'` is not repeated by the class section.

Still a shape difference: the postfix `if` in Symbol.pm's to_string, which
B::SoN renders as a ternary, as a compiler is free to (cfg-statements.t).

A `:reader` field keeps the attribute (its accessor is not written out),
and `:param` is bare when its name is the field's. A RENAMED reader --
`:reader(get_x)` -- is still emitted as a plain method: B::SoN recognizes a
reader by the field's name (_extract_class and three consumers), and chalk's
lib/ has none. Correct Perl either way; the attribute is lost.

## Silent drops in class code, found through gate 3

ir-node-binop.t died after two tests against the emitted Node/BinOp.pm,
whose ADJUST (`$left //= $self->inputs()->[0]`) was missing. Three silent
drops, and a census that let the module through as clean:

  - `$f .= ...` and `$f = "..$x.."` into a field: multiconcat rebound the
    target as a pad slot. In a method the store vanished; in an ADJUST the
    serializer died on the unbound read. Now Assign(FieldAccess)
    (t/deparse-a-string-build-into-a-field.t).
  - `//=`, `||=`, `&&=` into a field: the same rebind, and a right side with
    an effect refused. Now the memory-slot path: If, the right side on the
    assigning arm, the store there, a pinned read after
    (t/deparse-a-logical-assign-into-a-field.t).
  - A subclass's own ADJUST blocks were all dropped, without a warning,
    when its parent had any: `scalar adjust_cvs(...)` is the last block,
    not a count (t/deparse-an-adjust-of-a-subclass.t).
  - tools/chalk-lib-roundtrip.pl counted only `skipped` and `INTERNAL`; a
    dropped ADJUST warns in its own words. It counts as a skipped graph
    now, so such a module is not overlaid.

The other fused field writes (`+=`, `x=`, `**=`, `|=`, `<<=`, ...) round-trip;
probed with starting values that make each one change the field.

## Open-world wire facts, as built

  - A class from another file: `external` on its class record (5425304); an
    empty class declared here is still ours (recorded by the same
    positive-evidence test).
  - A call to a sub that exists but is compiled elsewhere (another module,
    an import, XS): `external` on the Call; only a call to a sub that does
    not exist still refuses.
  - A phase block's package: `package` on the block; the emission runs each
    `use` in the package it ran in (`use parent` sets that package's @ISA).
  - A `my` aggregate introduced in a loop body: its named ArrayLiteral /
    HashLiteral carries `control_in` -- an allocation at that point, like
    `new` in Simple -- so each iteration makes a fresh one (perigrin's
    choice over refusing). Unpinned literals keep the prologue placement.
  - An anonymous constructor (`[]`, `{}`, `[...]`, `{...}`) whose value is
    used carries `control_in` too: one allocation, however many names hold
    it (perigrin's choice). Read twice unpinned, it was built twice and
    `my $s = $r; push @$s, 1` never reached @$r.
  - A class field whose default the wire cannot carry (computed: `field $t
    = time`) carries `default_unmodeled` instead of being dropped; the
    renderer refuses it by name. An aggregate field's list of constants is
    now a default graph like a scalar's.

## Newly translating modules expose older defects (2026-10-03 to 10-05)

Lowering more of chalk's shapes (a die in a loop guard, a value
short-circuit whose right side calls, a call under a nested modifier) let
four modules translate that had refused: IR/NodeFactory, IR/Schedule/
Elaborate, MOP, Target/LLVM/ElaboratedContext. Each then emitted Perl that
did not compile, or compiled wrong, for reasons older than the change:

  - An exit join's seed was spelled at the top of the sub, ahead of what it
    reads: _under_proj gave up at an `or die` merge or a loop exit (adad17d).
  - The renderer resumed at a diamond the arm built itself, so everything
    after it was emitted twice (4e6dd91).
  - `if (C) { ...; return X if D } REST` emitted REST twice, or dropped the
    outer guard when the arm rebinds a scalar (f0d242b).
  - A lexical read in a ternary arm passed to a sub became an unbound name
    (perl flags call arguments OPf_MOD): NodeFactory::make gave every Phi
    undef inputs, and gate 3 fell from 545 to 495 at f0d242b (2f84b3a).
  - `main::c()` from a method and `\&Q::c` lost their package (6a6da18).

Gate 3 is the only census that catches the last kind: COMPILES rose to 136
and INVALID reached 0 while 51 test files differed. A newly compiling module
is measured by gate 3 before its count is trusted.

Still open, found on the way:
  - A sub falling off its end after `return X if C` returns 1 where perl
    returns the failed condition (`sub mk { ...; return $c{$h} if exists
    $c{$h}; }` with the key absent).
  - `next unless A && B` (B calls) followed by an `if` in a loop body
    refuses "a control node with 2 successors".
  - `my $r = defined $v ? $v : []` refuses "an anonymous ArrayLiteral
    reached as a statement" (the same merge, bound by an assignment rather
    than passed as an argument).
