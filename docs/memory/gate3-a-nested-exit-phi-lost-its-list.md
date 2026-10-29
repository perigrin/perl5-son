---
name: gate3-a-nested-exit-phi-lost-its-list
description: gate3 fell 482 -> 323 after d650119 merged early returns two at a time; Deparse read an exit Phi over an inner list Phi as a scalar (the count). 43 of the 159 DIFFERS are environmental (lli now present)
---

# gate3: a nested exit Phi lost its list (482 -> 323)

**What was seen.** SON_RATCHET subtest 6: gate3 SAME 323 against a floor of
482, with 159 DIFFERS. The Oct 25 listing (`g3-head.txt`) already showed the
same 159, so the drop predates this session's local-restore work.

**Split the DIFFERS before bisecting.** The 159 files were run against the lib
emitted by the floor commit 214e1a0 (`mixf`):
- **116 matched the original there.** Those are real regressions.
- **43 differed there too.** They are environmental. For example,
  `coerce-num-str-non-finite.t` runs lli now, and the emitted Context.pm's
  `"  " . @eff354` (an array concatenated as its count) was latent at the
  floor too. The floor of 482 was measured where these tests skipped or
  matched; it cannot be met in this container until the 43 are fixed.

**Find the module, then the commit.**
- Swapping each of the 36 changed emitted modules singly into the floor tree
  pointed at CoreItemIndex.pm, whose `advance()` returned a count.
- A 5-line probe (`return $m{$id} if ...; return unless ...; return $n`)
  bisected in seconds to d650119, "a sub's early returns merge two at a time".

**Cause.** d650119 merges the two arms of one If first, so the outer exit Phi
takes the inner Phi as an input. Deparse's `_phi_takes_a_list` looked only at
direct inputs: the List under the inner Phi was missed. The outer Phi became
`$phi`, took `@inner` (its count), and the Return lost `wantarray ? @l : $s`.

**Fix.** `_phi_takes_a_list` looks through Phi inputs, with a seen set because
loop Phis cycle.

**Second cause, same commit.** A `return CALL` whose call has no `want`
runs in the caller's context. Deparse spells it inline in the arm only when
its exit merge is "one a Return reads" (`$exit_merge` in the `%inline_return`
pass). Under the nested merges, the inner Phi is read by the outer Phi, not
the Return. So the call was bound to a scalar temporary, and a list came back
as its count. chalk's EagerPinning::_expand_node hit this: "Can't locate
object method kind via package 3" in the scheduler-* tests.

**Fix.** `$exit_merge` recurses: a Phi read only by exit-merge Phis whose
region takes this one's region is an exit merge too. The seen set is copied
per path, because a shared one made order matter.

Test: `t/deparse-a-nested-exit-merge-keeps-its-list.t` (3 cases).

## Lessons

- A wire-shape change (Region and Phi nesting) needs the lib census and gate3,
  not just the corpus census. Only gate3 runs chalk's real call graphs.
- When a SAME floor drops, first split the DIFFERS: run them against the floor
  commit's emission in today's environment.
- Bisect with a 5-line probe, not with gate3. A gate3 run takes about 1.5
  hours; the probe takes seconds.

## After the two fixes: 438, and what the remaining 44 hold

- **gate3 SAME 438** (DIFFERS 44). 43 of the 44 also differ against the floor
  commit's emission. The 44th, `llvm-mop-classes.t`, fails against the
  original lib too and only its ok count moved; it looks unstable.
- **One cause among the 43 is a producer wrong answer**, now fixed:
  `my ($a, $b, $c) = (f(), f(), f())` was bound by position. Each call runs in
  list context and can yield any number of values. Perl prints `1 2 5` for
  `(two(), 5)`, and the deparsed code printed `2 5` and undef. Context.pm's
  `"  " . @eff354` (`%Str 1` in lli) came from this.
  - **Fix.** A call (want not scalar), And, Or, DefinedOr, Phi or RegexMatch
    anywhere among several RHS values turns off positional binding, as it
    already did when it was the only value.
  - **Test:** `t/deparse-a-call-among-list-assign-values-has-no-position.t`.

**perigrin (2026-10-29): keep fixing the 44; do not lower the gate3 floor.**
482 stays the floor even though this container now runs the LLVM tests.

## The die path (26 of 44 cleared, then lower_value)

- **Producer (cb7e2cd, then generalised).** A sub's exit reachable only
  through a die carried `()` into the exit merge, which made the merge a list.
  In Context.pm, `_lower_constant` and `lower_value` (`$ret = @phi`) handed
  scalar callers a 1. An exit now carries undef when its control dies: an
  Unwind, or a Region all of whose inputs die (`if (C && D) { die } die`).
- **Chalk (195d3836, then extended).**
  - A merge's phi gets no entry from a dying arm.
  - `_find_unwind_consumer` continues past an arm's own If at its merge.
    Before this, `else { if (C) { die } die }` branched on to the merge and the
    sub RETURNED where perl dies: a silent wrong answer.
- **Tools.**
  - `$S/blame-module.pl` bisects which emitted module breaks a test.
  - `$S/blame-sub2.pl` with `$S/hook/SubSwap.pm` bisects which emitted sub:
    it loads the original source under a renamed package, so its file
    lexicals stay its own, and points every other sub at it.
