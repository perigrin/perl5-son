---
name: allium-instruction-sets
description: Stevan Little's Allium has perl opcode metadata generated from perl; use operation_types, NOT prototype
metadata:
  type: reference
---

**github.com/stevan/Allium** — Stevan Little's "Freeing Perl from perl".
Pipeline is `perl → B → Allium::Optree → Allium::SyntaxTree`, JSON
serialization, round-trip via B::Generate. No SSA, no sea of nodes, no
lowering — it stops where B::SoN starts, so the architectures do not overlap.

**The useful part is `data/instruction-sets/perl-5.41.4.json`** — 415 opcodes,
generated from perl, versioned per release, with:

- `operation_types` — OP / UNOP / BINOP / LOGOP / LISTOP / LOOPEXOP / METHOP /
  UNOP_AUX / SVOP / PADOP / PMOP / COP / FILESTAT_OP
- `private_flags` — bitmask, bitmin/bitmax, and `mask_def` (the C name, e.g.
  OPpTARGET_MY, OPpLVAL_INTRO, OPpDEREF). B::SoN hand-writes these as bare hex
  (`$op->private & 16`), which cost an hour on OPf_MOD vs OPpTARGET_MY.
- `prototype`, `static_flags`, `category`, `description`

**DO NOT use `prototype` as `pop_count`.** They answer different questions:

    prototype   the SOURCE-LEVEL signature — what the operator accepts as
                written. From opcode.pl.
    pop_count   the RUNTIME STACK DISCIPLINE — what the walker pops.

They agree on plain BINOPs (266 of ours) and diverge everywhere else for good
reasons: `floor` has `prototype: []` but pops its UNOP child; `and` is a LOGOP
that branches rather than pops; `print` is variadic and uses `'mark'`, which a
prototype cannot express. Substituting would break 33+ ops.

`operation_types` IS usable, and is what t/opmap-respects-op-class.t (3afe1fc)
embeds: op class constrains pop_count, so a LOOPEXOP with a pop_count is a bug
by construction. That lint found exactly one violation in 350 entries — `goto`.

Related: [[crashes-mask-gaps]], [[opf-mod-is-not-a-write]]
