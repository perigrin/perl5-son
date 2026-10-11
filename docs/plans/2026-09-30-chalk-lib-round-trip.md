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

## Deferred: tidy chalk's NodeFactory default (perigrin, 2026-10-06)

`lib/Chalk/IR/NodeFactory.pm:209` spells `inputs => (defined $values ?
$values : [])`; `inputs => $values // []` is the same for a plain lexical
(corpus: "A defined-ternary default and a defined-or default agree"). Not
made: chalk's checkout had staged changes that are not ours, and perigrin
said it can wait. When taken up, make it on a branch from `pu` in a separate
worktree and open a PR; gate 3 stays pinned at 5948f648 either way.

## Gate 3 measures behaviour; tests that read lib/ as source are deferred (perigrin, 2026-10-09)

B::SoN's product is the IR. Lowering it back to Perl and running that
against chalk's tests is how we check the IR is right -- the Perl is
validation, not a product. A chalk test that READS lib/ as source (feeds
chalk's own modules to chalk as input: compiling, comparing, recognising or
golden-checking them) measures the rendered TEXT against the overlay, not
the program, so it validates nothing about the IR.

Those tests are deferred to chalk's own LLVM lowering: when chalk compiles
its modules to LLVM IR, their output is what gets compared. Gate 3 runs the
rest against the emitted lib/ and requires the same per-file result.

The goal, restated: every chalk test file that does not read lib/ as source
gives the same per-file result against the emitted lib/ as against the
original. NOWORSE is gone (it existed only for these files), and the per-file
timeout is back to an hour (the file that needed three, perl-recognize-phase5,
is deferred).

What this deferral reverses: on 2026-10-02 the overlay was kept so that
chalk would parse B::SoN's output. The text-shape work done for those tests
-- conditional rebinds spelled as statements (6109270), class and package
statements in their blocks (d8aabcf, eddfaa3), forced-main names bare
(a05687d) -- stays: correct, and easier to read. It was not IR validation.

The 59 deferred files at 5948f648 (tools/chalk-gate3.pl, reads_source):

    t/benchmark/parse-performance.t
    t/bootstrap/c-data-model-classes.t
    t/bootstrap/c-direct-cross-class.t
    t/bootstrap/c-repair-coverage.t
    t/bootstrap/c-self-call-optimization.t
    t/bootstrap/c-target-boolean.t
    t/bootstrap/c-target-multi-class.t
    t/bootstrap/c-type-aware-dispatch.t
    t/bootstrap/c-xs-wrapper-gen.t
    t/bootstrap/cfg-statements.t
    t/bootstrap/codegen-perl.t
    t/bootstrap/codegen-pipeline.t
    t/bootstrap/earley-indexing.t
    t/bootstrap/emit-son-json.t
    t/bootstrap/implicit-return.t
    t/bootstrap/ir-subclass-field-audit.t
    t/bootstrap/ir/a-boxed-str-carries-its-encoding.t
    t/bootstrap/ir/backward-inference.t
    t/bootstrap/ir/fixpoint-folds-the-old-value.t
    t/bootstrap/ir/graph-no-body-stmts.t
    t/bootstrap/ir/propagate-fixpoint-terminates.t
    t/bootstrap/ir/resolve-direct-calls-reads-the-edge.t
    t/bootstrap/ir/slot-read-consults-the-tag.t
    t/bootstrap/ir/slot-tag-coercion.t
    t/bootstrap/ir/slot-tag-field.t
    t/bootstrap/ir/slot-tag-vocabulary.t
    t/bootstrap/ir/strpair-layout-single-source.t
    t/bootstrap/join-is-the-lattice-join.t
    t/bootstrap/lattice-edges-hold-in-perl.t
    t/bootstrap/mop/parse-integration.t
    t/bootstrap/no-tie-in-the-subset.t
    t/bootstrap/perl-actions-tier-a.t
    t/bootstrap/perl-actions-tier-b.t
    t/bootstrap/perl-actions-tier-c.t
    t/bootstrap/perl-recognize-phase5.t
    t/bootstrap/perl-target-perl-tier-a.t
    t/bootstrap/perl-target-perl-tier-b.t
    t/bootstrap/perl-target-perl-tier-c.t
    t/bootstrap/perl-target-perl-tier-d.t
    t/bootstrap/perl-target-xs-tier-a.t
    t/bootstrap/perl-target-xs-tier-b.t
    t/bootstrap/perl-target-xs-tier-c.t
    t/bootstrap/perl-target-xs-tier-d.t
    t/bootstrap/perl-target-xs-tier-d2.t
    t/bootstrap/perl-target-xs-tier-d3.t
    t/bootstrap/perl-target-xs-tier-d5.t
    t/bootstrap/perl-target-xs-tier-grammar.t
    t/bootstrap/phase5-lib-coverage.t
    t/bootstrap/phi-integration.t
    t/bootstrap/sa-epoch-gc-debug.t
    t/bootstrap/son-compare.t
    t/bootstrap/xs-build-perl.t
    t/bootstrap/xs-earley-behavioral.t
    t/bootstrap/xs-earley-full-semiring.t
    t/bootstrap/xs-pm-parse.t
    t/bootstrap/xs-polymorphic-dispatch.t
    t/bootstrap/xs-sub-recursion.t
    t/bootstrap/xs-target-c-smoke.t
    t/grammar-conformance.t

## Silent miscompiles found by the GAP investigation (2026-10-10)

Thirteen cluster investigators (the 239 skipped graphs, grouped by GAP)
reported miscompiles adjacent to their GAPs. Each was re-run through the
round trip at b6919f7; all thirteen print something other than what perl
prints, with no GAP. None is caught by gate 3 (488/488), so chalk's tests do
not exercise them -- but a fix that lowers more graphs can make any of them
reachable. They are the next batch after the GAP fixes, ahead of nothing
else: a silent miscompile is worse than a refusal.

| program | perl | emitted |
|---|---|---|
| `my $n=0; sub f { my $x = $n++; return $x }` called twice, print `$a $b $n` | `0 1 2` | `1 2 2` |
| `my $v=1; my $r=\$v; $$r += 2; print $v` | `3` | `1` |
| `for my $i (1..3) { my $r = eval { die "x\n" if $i==2; 1 }; ... }` | `okEok` | dies `x` |
| `my @a=(3,4); for (@a) { $_ *= 2 } print "@a"` | `6 8` | `0 0` |
| `my @a; push @a,1,2; my @b=@a; print scalar(@b)` | `2` | `0` |
| `my @F=(1,2); sub f { push @F, 3 } f(); print "@F"` | `1 2 3` | `1 2` |
| `my $n = () = ($c ? 7 : ())` | `1` | `7` |
| `sub f { wantarray ? @a : [] } my @x = f(); print scalar(@x)` | `2` | `1` |
| `sub g { my ($k, @x) = @_; return $#x }` | `1` | `1`, via `length(@x)` (right by accident) |
| `if ($k) { @e = (0,4) } else { @e = (9) }` in a loop | `0 4` | `1`, and a masking `my @e` |
| `my $x = $c ? push(@a,3) : 0` | `3 1 2 3` | `3 1 2` |
| `sub f { my ($h)=@_; $h->{p}=2 } f($h); print keys %$h` | `p` | (empty) |
| `sort { $b <=> $a } (3,1,2)` -- the renderer ignores comparator fields | `3 2 1` | `1 2 3` |

The sort row is in batch 1 (cluster `sortsub`) because its GAP fix cannot
be validated without it. Per-cluster reports, with producer sites, are in
the session scratchpad under gaps/reports/.

### Status at 4c00529 (2026-10-10)

Element-read ordering came first (2bf5c42): `my $z = $a[0]; $a[0] = 1`
was wrong in the renderer, and `g(\@a)` was wrong in the IR -- a call
advanced memory only when a written cell existed. Every call is a memory
barrier now. Eleven of the thirteen rows above then round-trip: eval with
a guarded die, `$_ *= 2` in a foreach, a bare array's copy and a sub's
push, countof over a ternary, `wantarray ? @a : []`, `$#x` of a slurpy,
an array assign in both arms, push in a ternary arm, sort comparators,
tr/// on a copy, chop's value. Each was verified by an adversarial agent
against 2bf5c42 before merging.

All three remaining rows -- the closure `$n++`, `$$r += 2`, a store
through a hashref parameter -- landed at bd0e86a, after their merge was
repaired: postinc's alias refusal counted any call as a store to every
pad scalar (COMPILES fell to 133, SKIPPED_GRAPHS rose to 280; a call now
stores only what a closure or reference reaches), and two perl t/
emissions stopped compiling (fixed; perl t/ invalid emissions are
guarded by a ratchet ceiling of 2 now).

Ratchets at 4c00529: corpus 275/275, perl t/ 11, chalk COMPILES 137,
SKIPPED_GRAPHS 239, INVALID 0, gate 3 SAME 488 / DIFFERS 0 / DEFERRED 59.

Ratchets at bd0e86a (2026-10-11): corpus 275/275, perl t/ 11 with 2
invalid emissions (ceiling 2), chalk COMPILES 137, SKIPPED_GRAPHS 239,
INVALID 0, gate 3 SAME 488 / DIFFERS 0 / DEFERRED 59. All thirteen rows
of the table above round-trip.
