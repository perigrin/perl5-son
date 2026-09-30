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
