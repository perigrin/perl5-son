---
name: the-topic-is-a-global-a-callee-reads
description: the lowered foreach/map/grep never set `$_`, so any callee reading or writing the topic by name saw the wrong value; each pass now aliases it with `\local $_ = \$a[$i]`
metadata:
  type: feedback
---

`sub is_x { /x/ } grep { is_x() } @a` matched an undef topic: `|0 0 0`
for perl's `ax xc|1 0 1`. So did `g() for @a` with `sub g { print $_ }`,
and `for (1..3) { g() }`. All were on the base. The body's own `$_` reads
were bound to the element by index, so every in-body test passed. Only a
callee, which reads the global by name, saw the hole. "The implicit `$_`
is spared the call refusal" had been hiding it as a known gap.

The fix is a LocalAlias node, pinned at the pass top when the loop's body
contains an `entersub`. The deparser spells it
`use feature 'refaliasing'; no warnings 'experimental::refaliasing';
\local $_ = REF;`. `\local` is restored where the while body's block
ends, which is perl's foreach scope, and it leaves `@_` alone.
(`local *_` would clobber `@_`.)

- Array: REF is `\$a[$i]`. Over a possible hole it is `exists ? REF :
  undef // \(my $holeN)`, because `\$a[$i]` vivifies.
- Range: REF is `\(my $topicN = $i)`, a fresh copy, so a callee's write
  doesn't move the counter.

Mark the list's literal mutated, since any callee may write through the
alias. With the alias in place, a private unproven list under `$_` with a
call no longer refuses (`$topic_aliased` in `_unproven_list_reach`).
That's chalk's `$_->set_stamp(undef) for @stale`.

**Why:** a test that only reads `$_` in the body can't see this. Only a
named-sub callee exposes a global the lowering never set.

**How to apply:** when lowering any construct perl implements by aliasing
a global (`$_`, `$a`/`$b` in sort, a package foreach variable), test a
callee that reads it by name, not just the body.
