# FromOptree Walker Unification — Design (4b-1 prerequisite)

**Date:** 2026-06-15
**Why:** Phase 4b-1 (single-exit normalization) needs return/leavesub handling
that works inside branches. FromOptree has THREE partly-duplicated `while
($$op)` walkers, and the duplication is the root cause: `_walk_branch` has NO
return/leavesub handling, so `return X if $cond` dies "Stack underflow"
(probe-confirmed). Unify the walkers FIRST (no behavior change), then add
single-exit returns once. Decision: perigrin, 2026-06-15.

## The three walkers (current state, FromOptree.pm)

1. `translate` (:19-533) — the main entry. `while ($$op)` at :31. Handles:
   pushmark, skip-ops, dor, cond_expr(ternary), and/or branches (build
   If/Proj/Region via `_walk_branch` on each arm + `$sim->merge`),
   entertrycatch, loop ops (enterloop/enteriter via `_walk_loop_body`),
   leaveloop, gv, method-name(const for ->method), **return**, **leavesub**,
   const, padsv/padav/padhv, argelem, sassign, padsv_store, the TARGMY-write
   path, the generic OpMap dispatch, entersub/call shapes, aelem/helem,
   refgen, etc. Falls through at :516 to build ONE Return from the final stack.
2. `_walk_loop_body` (:573-747) — `while ($$op)` at :574. Handles the COMMON
   core (const, padsv, padav/padhv, argelem, sassign, padsv_store, TARGMY,
   generic OpMap) PLUS loop-specific: unstack→last, leaveloop→last, the
   loop-condition and/or (build If/body-Proj, jump to `$op->other`). Uses a
   SEPARATE `$loop_visited` map + the `$outer_visited` map.
3. `_walk_branch` (:750-879) — `while ($$op)` at :751. Handles the COMMON core
   PLUS its own If/Region handling (:597 per the grep) for nested branches.
   Convergence: `return $op if $visited->{$$op}` (:753). **Has NO
   return/leavesub handling** — the bug.

## Common op-set (identical across all three — extract verbatim)

const, padsv, padav, padhv, argelem, sassign, padsv_store, pushmark, skip-ops,
the TARGMY-write path (`$op->private & 16`), and the generic OpMap dispatch
(known && !branch && !loop). These are byte-for-byte duplicated (modulo
`_make_pad_or_field` vs the inline PadAccess in a couple of `_walk_branch`
arms — UNIFY to `_make_pad_or_field`, which is the newer/correct one that
distinguishes fields).

## Target shape

Extract ONE op-handler:

    # _step($cv, $op, $sim, $factory, $opmap, $ctx) -> ($next_op, $signal)
    #   $ctx = { mode => 'main'|'branch'|'loop', visited => \%h, ... }
    #   returns the next op to process, and an optional signal
    #   ('converged' | 'loop_end' | 'returned' => $ret_record | undef).
    # Handles ONLY the common op-set. Returns ($op, 'unhandled') for any op
    # the common core does not own, so the caller's mode-specific switch runs.

Each walker becomes:

    while ($$op) {
        <mode-specific visited/termination check>
        my ($next, $sig) = _step(...);
        if ($sig eq 'unhandled') { <mode-specific op dispatch>; next }
        <act on $sig>; $op = $next;
    }

- **main** mode keeps: dor, cond_expr, and/or-branch, entertrycatch, loop ops,
  leaveloop, gv, method-name, return, leavesub, entersub/call, aelem/helem,
  refgen — everything not in the common core.
- **branch** mode keeps: its nested If/Region handling; convergence via
  `$visited`.
- **loop** mode keeps: unstack/leaveloop termination, loop-condition and/or.

## Hard invariant

**No behavior change.** The full perl5-son suite (all t/*.t) is GREEN at the
start (confirmed 2026-06-15). It must stay byte-identical green after the
unification — same node graphs, same JSON. The refactor is mechanical: move
the common handlers into `_step`, leave the mode-specific handlers in place,
verify the suite. Do NOT add return-in-branch handling in this step (that is
4b-1's feature commit, done separately after the unification lands green).

## Caution (someone else's working module)

- Move handlers VERBATIM. Where two walkers differ on a "common" op (inline
  PadAccess vs `_make_pad_or_field`), converge on `_make_pad_or_field` and
  confirm the affected test (from-optree-fields.t / from-optree-branches.t)
  still passes — if it changes a graph, STOP and flag it, do not paper over.
- The `$visited` vs `$loop_visited`/`$outer_visited` map distinction is
  load-bearing for convergence/termination — preserve each walker's exact
  visited-map semantics; `_step` must take the relevant map via `$ctx`.
- Commit the unification as ONE commit, suite-green, before the feature.
