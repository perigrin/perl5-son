---
name: a-timeout-can-be-a-hang
description: The 11-17 swap's 5 TIMEOUTs were a B::SoN infinite loop, not compile cost; flat RSS at 100% CPU is the tell
metadata:
  type: feedback
---

On 11-11, 208 easy-tier TIMEOUTs read as "compile cost". On 11-17 the 5
that were left looked like that too. They were a hang: B::SoN
`_required_files` walks a BEGIN CV by `op_next` with no visited set, and a
loop with no condition (Math::BigInt::Calc's `for (...; ; ...)`, reached
through `require Math::BigInt` in Chalk::IR::Analysis) is a cycle. Repro:
`BEGIN { my $i = 0; while (1) { last if $i++ > 2 } } print "ok\n";`

**Why:** a timeout only says the budget ran out. A slow run and a spin look
the same.

**How to apply:** before calling a TIMEOUT "slow", check it. RSS that stays
flat with CPU at 100% is a spin. A SIGALRM handler that calls
`Carp::longmess`, loaded with `-M` and armed for 45 s, names the loop.
Rerun with a much larger budget. Correlate what the TIMEOUT files load:
here all five, and only those five, loaded Math::BigInt at compile time.

Also from that day: `grep -v 'e.g.'` is a regex, and it dropped "unseen by the
graph" from a cause table. Summing the table back to the verdict count
caught it.
