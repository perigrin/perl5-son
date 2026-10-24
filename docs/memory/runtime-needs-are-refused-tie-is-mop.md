---
name: runtime-needs-are-refused-tie-is-mop
description: perigrin's rule for the 430/430 goal — a feature that needs a perl runtime (string eval, s///ee, ...) is a named GAP, not a target; tie is in scope via the MOP and metaclass manipulation
metadata:
  type: feedback
---

**The rule (perigrin, 2026-10-24):** "If things require a runtime we GAP
and refuse them." A refused-by-name case is the right answer for these.
Don't build an interpreter into the lowered program to round-trip one.

**Why:** chalk compiles ahead of time. String `eval`, `s///ee`, and
`require` of a computed name need perl's compiler at run time.

**The exception:** "Tie though I think is tractable via the MOP and
metaclass manipulation." A tied variable's methods are known classes, so
treat tie as dispatch through the metaclass, not as a runtime need.

**How to apply:** when ranking census causes, set the runtime-needing
cases aside as done once their refusal names the feature. Count them
apart from the real misses. Plan tie with the MOP method-dispatch causes.

**Update (perigrin, 2026-10-24):** "String eval may be taken care of by
the Bson session by the time we get there." Don't write string eval off
as permanently refused. Leave its cases at a named GAP, and check what
the Bson session has landed before the final count.

**Formats are open, not refused (perigrin, 2026-10-24):** "We will need
to discuss how much runtime support formats need when we get there …
they feel pretty static to me." Don't class `format`/`write` as
runtime-needing. The picture lines are fixed at compile time; only the
values flowing in vary. Discuss with perigrin before building or
refusing them (cases 292, 293).
