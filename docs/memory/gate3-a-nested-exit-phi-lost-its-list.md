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
