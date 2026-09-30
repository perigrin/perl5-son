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
  - SoN::Serialize::JSON recurses per node (line 456): comp/use.t's program
    graph draws "Deep recursion on anonymous subroutine" warnings. Output is
    right; the walk should be iterative.

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
