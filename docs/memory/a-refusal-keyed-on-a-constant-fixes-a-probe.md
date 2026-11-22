---
name: a-refusal-keyed-on-a-constant-fixes-a-probe
description: "Audit 2026-11-22: five of ten closed wrong-answer classes had a wrong neighbour one edit away; W8 matched the bless's class name, W9 an Undef stamp, the effect table was an allow-list -- refuse or fix by the class, then probe its neighbours"
metadata:
  type: feedback
---

The 2026-11-19 audit's probes all went to SAME or REFUSED, and 288 new
one-line probes (docs/research/son-ir-audit-2026-11-19/probes/a/) found 55
silent wrong answers beside them.

- **W8:** chalk refused a `DESTROY` only where a `bless` named its package
  as a constant. Inheritance and AUTOLOAD reached one anyway. Now any bless
  in a program with a non-empty DESTROY or AUTOLOAD is refused.
- **W9:** chalk refused autovivification only where B::SoN had stamped the
  container `Undef`. The fix was B::SoN's: perl marks every intermediate of
  an rvalue chain OPf_MOD with DEREF, and the walk vivified only a chain
  ending in a store (`_deref_chain_writes`, deleted).
- **The effect table:** a builtin with no row was pure, so an unused
  `log(0)` was dropped. Now every Call in the op map has a row, `writes`
  of an unknown name is true, and the walk refuses a builtin it does not
  know.
- **W7:** a `die` that ended a loop body was stepped past: the body walk
  had no case for it and skipped what it did not know. It refuses now.

**How to apply:** a refusal or a fix keyed on a constant (a class name, a
stamp, a list of names) is a fix for a probe. Key it on what perl does, or
default to the conservative answer, and write the neighbours as probes.

Related: [[a-census-of-zero-wrong-is-only-its-cases]], [[a-verifier-that-reads-a-derived-flag-checks-itself]].
