---
name: the-final-audit-s-wrong-answers-lowered-or-refused
description: "Branch final-audit: the final audit's 111 silent wrong answers -- A, B, F, I lowered (45 SAME), C, D, E, G, H refused by name (66); the sassign catch-all is a GAP; _seat writes control_in; the loader checks every wire but chalk's own; probes f gated as fa<name>; each new refusal first reached past its class"
metadata:
  type: project
---

Branch `final-audit` (2026-11-24; baseline section 23; producer 40e86a6..21457b0,
chalk 93c01e4c..add5ce17). The final audit
(docs/research/2026-11-24-memory-model-final-audit.md) found 111 WRONG in
847 probes (probes/f). Now fa: SAME 603, REFUSED 238, LOUD 6, WRONG 0; all
2298 gated probes SAME 1748, REFUSED 535, LOUD 15, WRONG 0, no older verdict
changed. Gates: all PASS (census 426, corpus 222, deparse 430).

| class | outcome | fix or refusal |
|---|---|---|
| A (12) | SAME | padav list shortcut does not flatten a literal holding a versioned or shared whole aggregate |
| B (17) | SAME | chalk: Count/keys of a copy read the copy; reads_before makes an rvalue whole deref a copy |
| C (19) | REFUSED | `a variable passed to a sub that stores it by name and reads its arguments` |
| D (14) | REFUSED | `a ?: / an assignment used as the target of ...`; the sassign catch-all is a GAP (a call's result excepted) |
| E (18) | REFUSED | `a package scalar aliased by a foreach, map or grep`; `an element perl's alias may make exist` |
| F (10) | SAME | chalk ChopChar: chop's value is the character |
| G (13) | REFUSED | `a foreach iterator written in a pass a die may leave` |
| H (2) | REFUSED | `a method that stores $_[0]` (a `my` invocant) |
| I (6) | SAME | last match restored at a block's/loop's end; chalk: a group past the result is undef |

Clause 2: `sprintf("%d", 1/$d)` pinned (sprintf flags its args OPf_MOD);
`_seat` is the one write of control_in. Clause 4: a55, d61, o11 verify;
chalk's loader checks every wire but `writer: chalk` (to_json).

**Lessons:**

- **Every new refusal first reached past its class.** gates1: 16 producer
  files and 6 corpus graphs (a ?: argument already lowered, a plain stacked
  multiconcat, Carp's `caller_info(++$i)`, POSIX's `_getsig($_[1])`); gates2:
  five chalk tests (literal slices, hash keys, `"@_"`). The f sweep said SAME
  lost 0 each time: it is not the suites. Run both suites before the gates.
- **A null op's targ is the op type it was.** `$o->targ == $iter_targ`
  matched an ex-padsv under enteriter; skip nulls when scanning by targ.
- **An ex-pushmark is a null, not a pushmark.** A subscript list filtered by
  `/pushmark/` kept it and every constant slice looked non-constant.
- **_subtree_ops is breadth-first.** "Read after store" needs order: walk
  post-order (kids before op) for execution order.
- **A lucky SAME hides a wrong.** f/n20 matched perl because its die never
  fired; adding `$@` to the print (h5) showed the demoted iterator read
  its pass's start after `+=`. Fixed (the slot is stored too), not refused.
- **The bypass was the absence of a key.** The loader exempted a wire with
  no `dowarn`; an exemption must be a positive claim (`writer: chalk`), and
  tests' hand-built wires say so. Four fixtures were older B::SoN wires that
  broke L4-L9 (one held 417 graphs of B::SoN itself).
- **A sweep from a snapshot loses relative paths** (w1lib1/4 "no program
  graph"): recheck a lost SAME from the real tree before believing it.

Open design items: aliases on the wire (C, E, H); a write-back on every way
out (G); an assignment or ?: as an lvalue (D). Named shortcuts in the code:
an unknown call is not counted by the call-argument rule; a caller's own
`$_[N]` argument is not counted by C; an element through a reference or of a
stash, and `@a[$i .. N]`'s bottom, are not refused by E.

Related: [[the-final-audit-s-wrong-answers]], [[the-re-audit-s-wrong-answers-refused]],
[[a-silent-drop-is-worse-than-a-refusal]], [[opf-mod-is-not-a-write]].
