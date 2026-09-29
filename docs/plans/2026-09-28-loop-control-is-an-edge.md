# Loop control is an edge, not a rewrite

**Date:** 2026-09-28
**Status:** PLAN, APPROVED 2026-09-29 (perigrin: phases 1-6, replacing the
existing next/last lowering). Phase 0 done in 347d2f7.

## Why

Eleven tier-1 cases stand on loop control or early exit, and two of them are
SILENT wrong answers rather than refusals:

    118  `next OUTER` from an inner loop lowered as the inner loop's `next`
    137  `next` skips the `continue` block -- perl runs it on every `next`

The rest refuse: 006 007 116 117 134 (producer GAPs), 008 030 (the deparser's
"a control node with 2 successors"). 015 and 100 share the deparser message but
are `s///ee` and belong elsewhere.

The goal is 224/224 with no honest-refusal list: the target is Perl, which
has `next LABEL`, `last LABEL`, `redo`, `continue {}` and `goto LABEL`, so
there is nothing the emitted program cannot say.

## What the code does today (mapped 2026-09-28, FromOptree.pm)

EVERY LOOP-CONTROL FORM IS A STRUCTURAL REWRITE, not an edge:

  - Unconditional `next` stops the body walk (`last;` at ~10101), on the
    assumption that "next jumps to the unstack". True only with no continue
    block and no label.
  - `next if C` becomes `if (!C) { rest }` -- the skip arm merges pre-guard
    bindings with the rest arm (~10248-10333).
  - `last if C` pushes Proj0 onto @break_projs; the exit Region joins them.
    A head-of-body `last if C` is hoisted to BE the loop condition, and a
    second one refuses ("already has a loop condition").
  - `next`/`redo` inside a branch arm refuse; `last` in an arm returns
    'broke' (_walk_branch ~12245).
  - `goto` is in %UNBUILT_OP_GAP.

And three structural facts the rework has to face:

  - THERE IS NO CONTROL BACK EDGE. `Loop::set_backedge_ctrl` is never called;
    the Loop's inputs are `[entry]` and the back edge exists only on Phis.
  - NO LABEL IS READ. Neither `COP->label` nor a loop-exit PVOP's `pv`.
  - `continue` blocks have no handling: their ops lie before `unstack` and
    are walked as trailing body statements, so anything that stops the walk
    early (a `next`) skips them. A C-style `for` loses its step the same way.

Early `return X if C` builds `If` and only `Proj1`; the exit records the
PRE-GUARD control, which then has two successors (the If and the exit
Region). Measured on 030:

    10 If     in=[0, 9]
    11 Proj   index=1 of 10          no Proj index=0 exists
    15 Region in=[0, 11, 14]         Start is a predecessor

UNVERIFIED, from the map: OpMap gives `last/next/redo/dump` `[0, undef, 0,
0]` with no GAP, so outside a loop body (a bare block) they may build nothing
and fall through. Phase 1 measures it first.

## The design

Each loop gets three join points, and every loop-control op is an edge to
one of them:

    header   Loop            entry + back edge (set_backedge_ctrl, at last)
    latch    Region          fallthrough + every `next` edge; the continue
                             block runs here, then the back edge
    exit     Region          condition-false + every `last` edge
    (redo)   Region          body entry + every `redo` edge

Bindings merge where the edges meet: a Phi on the latch over the paths that
reach it, whose value feeds the header Phi's back edge. The header Phi stays
two-input, so the renderer's loop contract (Proj0 body, Proj1 exit) holds.

A LABELED edge targets the named loop's join points. The walker keeps a
stack of active loops, each with its label (from the nextstate that precedes
its enter*), and `next LABEL` resolves by name; an unlabeled one takes the
innermost.

THE RENDERER spells edges, it does not reconstruct them:

    edge to the innermost loop's latch    `next`
    edge to an outer loop's latch         `next LABEL`   (loop emitted labeled)
    edge to an exit                       `last` / `last LABEL`
    edge to a redo point                  `redo` / `redo LABEL`
    latch Region's own nodes              `continue { ... }`

`goto LABEL` is an edge to a Region created at the label's nextstate; the
renderer emits the label and `goto LABEL`. Perl allows exactly the forward
and backward jumps the corpus uses (not into a foreach or a sub).

## Phases -- each TDD against its named corpus cases, full suite + census

  0. GUARDED RETURNS BUILD THEIR TRUE PROJ. The main and/or handler and the
     `E // return X` handler create Proj0 and record the exit on it. Renderer:
     an exit arm emits `if (C) { return X }`. Targets 030 (and the return half
     of 008). Independent of the loop work -- a bug fix to existing code.
  1. `next` IS AN EDGE TO A LATCH REGION, unconditional, guarded and inside
     arms; the continue block is walked once, at the latch. Measure the
     bare-block drop first. Targets 137, 007; a C-style for with `next`.
  2. `last` IS AN EDGE EVERYWHERE, including with a header condition already
     present and inside arms. Targets 006's while, 116's last.
  3. LABELS. Loop stack with labels; labeled edges; the renderer labels only
     loops something targets by name. Targets 118.
  4. `redo`. Targets 116, 006.
  5. `do {} while` / `until` whose body runs first. Targets 134.
  6. `goto LABEL` and computed `goto $t` (117 has both). A computed goto is an
     edge set over every label in scope, selected by the runtime value; the
     renderer can spell it as `goto $t` directly.

Scalar flip-flop (003 176) is state, not control, and is not in this plan.

## Acceptance

Per phase: the named cases flip to ROUNDTRIP, the full suite passes, and the
census shows no other case changing bucket. At the end: every loop-control
GAP message above is gone from FromOptree.pm, not merely unreached, and the
structural rewrites they guarded are deleted rather than left beside the edges.
