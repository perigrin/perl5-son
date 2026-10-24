---
name: census-cause-phi-before-structure
description: 430/430 goal, cause "Phi node encountered before its enclosing if/loop structure" (17 cases) — early returns built one headless N-way Region; folded pairwise in the producer, plus a value phi misread as memory; ROUNDTRIP 109 -> 111; most remaining cases are eval
metadata:
  type: project
---

**Cause:** "Phi node encountered in lower_value before its enclosing
if/loop structure" held 17 cases at c8f72658.

**What it was, three things:**
- `return A if C1; return B if C2; return D` built one Region over three
  exits. No one If owns three, so it had no head and chalk could not
  find the structure. `_build_single_exit` (FromOptree) now folds two
  sibling arms of one If into their own merge until two remain.
- chalk then refused the inner merge's phi as "made inside one of its
  arms". An inner merge that has an If for its head is lowered with its
  arm.
- `$p ? one() : 4`: `_is_memory_phi` took any phi with a direct-call
  input for memory, so the value phi was never wired. B::SoN flags its
  memory phis (`memory: true`); chalk's Phi now carries that flag, and an
  unflagged stamped phi is a value.

**Side effect:** forty nested merges make SoN::Serialize::JSON's recursive
walk exceed perl's 100-frame warning. The warning is silenced there,
caught by t/deparse-many-guarded-returns-render-in-time.t.

**Round-tripped:** 109 -> 111. 14 left under the same message.

**What they hit next:**
- Mostly `eval` (block and string). String eval needs a runtime and is
  a named GAP (see runtime-needs-are-refused-tie-is-mop).
- `my @c = two()`: list-returning subs don't lower at all ("ArrayRef
  elem has repr=List").
- A Str ternary condition: "_ensure_i1 cannot convert repr=Str".
