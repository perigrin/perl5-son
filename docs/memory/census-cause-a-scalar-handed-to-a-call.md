---
name: census-cause-a-scalar-handed-to-a-call
description: 430/430 goal, cause 5 — "Assign lhs got MemStart" (38): a `my $x` handed to a call is a location (alloca %Slot per graph instance); ROUNDTRIP 81 -> 81; 14 moved to in-place writers (s///, tr///, substr); five wrong answers found, two pre-existing in perl5-son's render
metadata:
  type: project
---

**Cause:** `@_` aliases a scalar handed to a call, so the producer keeps
it in memory. Its PadAccess reads a memory version, not a VarDecl, and
chalk refused every store to one ("Assign lhs ... got MemStart").

**Cases held:** 38.

**Fix (chalk dc812501, perl5-son 9bead81 and 8faee94):**
- Each such variable is one `%Slot` per graph instance. The alloca goes
  in the function's entry block, and the slot is set undef where its
  graph's lowering began. That makes a callee's `my $x` distinct from its
  caller's, and fresh on each call and each loop pass.
- perl5-son spells a shadowing `my $x` apart (`x__2`). Before this, the
  Perl render itself printed l1l2l2 for l1l2l1.
- An in-place write (s///, tr///, chop, lvalue substr) is refused by
  name, because nothing stores its result back.

**Round-tripped:** 0 new. ROUNDTRIP stays 81.

**What they hit next:**
- 14 hit an in-place writer: s/// 10, tr/// 3, substr 1.
- 7 hit a store of a reference into a shared lexical.
- The rest are scattered, one or two each.

**Wrong answers found on the way, each red first:**
- An arm's body walk reached the next loop pass through a memory phi and
  recursed forever (backlog 34066162). An arm owns what its *control
  chain* reaches, not what the walk reaches. A pinned read on that chain
  counts as part of it: when it didn't, a hash increment in a loop was
  silently dropped.
- My own b019b022 guard dropped a written hash's element type. A
  `%HashEntry` has no tag, so the read printed nothing. Hash literals
  mixing value types are now refused (Int with Num printed 4.94e-324).
- `%` over a Num reached `srem i64` (pre-existing).
- A test expected "f4 gf12" for a case that had only ever been refused.
  perl prints "ffg4 12".
- chop of a memory-kept scalar was dropped by the producer, and its
  value was read after the store (perl5-son render, pre-existing).

**Lessons:**
- Write a test's expected output by running perl, never from memory. A
  case that is "refused or right" hides a wrong expectation until the day
  it lowers.
- Treating a crash as a refusal in a "refused or right" helper passes a
  wrong answer. Match the refusal's own prefix.
- Never edit the tree a check is running against. I did it twice; both
  runs were void.
