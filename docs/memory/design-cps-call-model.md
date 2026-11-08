---
name: CPS for the call model (perigrin, 2026-11-08)
description: perigrin wants continuation-passing style for T2's runtime call model explicitly, and for the compiler's internal calls ultimately -- no stack blowouts; a cycle still needs an in-progress mark.
type: project
---
perigrin: "This is where I wanted to have CPS for our internal call model ... to
avoid this and stack blowouts." Asked which: "Both ultimately ... but the latter
explicitly" -- the latter being the COMPILED PROGRAM's call model.

**Explicitly: T2's runtime calls.** Today a Perl sub call is a native LLVM call,
so deep Perl recursion overflows the C stack where perl (whose sub calls do not
nest C frames) does not. CPS / a trampoline: depth bounded by the heap, not the
C stack. `die`/`eval` become an escape continuation instead of the t2_dying
flag tested after every call (after_call).

**Ultimately: the compiler's own calls** (T2's builder: value -> value,
reads_before -> value, recursion on Perl's stack; "Deep recursion" warnings on
deep graphs). As a worklist/CPS, depth stops mattering and every pending node
is in one place.

**Not a fix for cycles.** The out-of-memory kill that prompted this
(hash_reads_settled -> a sort's comparator -> hash_reads_settled, 2026-11-08)
was a cycle, not depth: under CPS it loops on the heap instead. A node needs an
"in progress" mark either way (the re-entry guard in hash_reads_settled).

**How to apply:** after the T2-completion goal; the runtime call model first.
