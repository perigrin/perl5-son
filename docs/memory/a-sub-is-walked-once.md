---
name: a-sub-is-walked-once
description: "Branch single-walk (clause 3): a pre-scan of the ops decides what a loop header guessed -- iterator write, Phi stamp, slots, aggregates written -- and the sub is walked once; no settle pass: an unread package's scalars count as written; a fact the scans miss is refused by name; B::SoN's own compile has no peephole, a gvsv has no lvalue flag, and \"written\" is not always the safe answer"
metadata:
  type: project
---

Branch `single-walk` (2026-11-25; baseline section 26). Design (c), approved
by perigrin: an exact or conservative pre-scan of the ops before the walk; the
walk reads the facts and never guesses; `%LOOP_HINTS`, `$DIRTY` and the
re-walk driver (`_translate_from` around `_translate_from_once`) are deleted.
B::SoN's settle pass is gone too (perigrin's "B"): a package scalar counts as
written unless the first scan read every sub of its package (`%PKG_UNREAD`,
`_scalar_written`), and a writer met later of any other is refused by name.

| fact | pre-scan | a miss |
|---|---|---|
| the iterator is written | `_body_writes` / `_op_writes_key`: every op of the body, an inner loop aliasing the same name left out | `_check_writes`: GAP by name |
| a Phi keeps its init's stamp | `_loop_stamp_scan`: each value classed S / E (element read) / U; an op it does not list is U (an unstamped Phi) | `_patch_loop_phi`: "loses its stamp" |
| which slots get a Phi | `_may_write_targs`, now with package scalars and package aggregates | `_braun_seal`: "its header's scan missed" |
| an aggregate written after a read flattened it | `_loop_aggregates_written`: the header marks the literal | `_braun_seal`: GAP by name |

Walks repeated (t/lib/WalkCount.pm), at the alias-places base ce5f564:
corpus 11 files (8 loop guesses, 3 class methods), probes 142. After: none,
and nothing is held. Wires: corpus and probes byte-identical to the base but
probes l/lw25 (the header marks the array a slice alias writes: REFUSED ->
SAME in chalk); chalk's lib identical but for eval numbering. The cost of
"B": package-scalar memory reads 368/2748/422 (corpus/probes/chalk lib)
before and after -- none. gates all PASS (baseline section 26).

**Lessons:**

- **B::SoN compiles the program without the peephole.** `$_` reaches the scan
  as `rv2sv(gv)`, not `gvsv`; `$s .= "x"` as a stacked concat. A scan written
  from `perl -MO=Concise` (peeped) missed every package iterator write. Read
  the ops B::SoN reads.
- **A gvsv carries no lvalue flag; its ex-rv2sv does.** `$_ = 0`, `$_++` were
  read as no write because OPf_MOD was asked of the gvsv.
- **OPf_MOD alone is not a write.** perl flags `blessed($_)`, `refaddr`,
  `lock`, `pos`, weaken's operand, a call's argument, and every operand of a
  string append (`$s .= "$x"` flags `$x`). An operator writes only its op=
  target, its first operand; an increment's operand is written even as a
  call's argument (`g($l, $i++)`).
- **On a threaded perl `$op->gv` reads the pad perl has current** -- another
  sub's (B::SPECIAL). Resolve through the walked CV (`$OPS_CV`, `_op_gv`).
- **"Written" is not always the safe answer.** A demoted iterator (written in
  an eval body) is stored, not rebound, by `=`, `.=`, chop, `||=`, undef, and
  rebound by an op=, `++`, s///, a list assign; scanned "written" where the
  walk only stored, the pass-end write-back was skipped and f/n03 printed
  `1 2` for `1! 2!`. The rule is measured (`_demoted_rebinds`), and a mismatch
  is refused by name. Probe a "safe" default before trusting it.
- **A body that never goes round** (`$i++; die`) is walked to its end, and the
  sealing reads what it bound there: its slots are all its ops, not its cycle.
- **The stamp scan is a fixpoint over every slot the pass writes**, a Phi's
  and one the pass only binds alike (`my $k = 0; ... $k++` recursed to its
  depth limit and read U).
- **The walk reads a binding's class, so a value's class is the walk's
  rule, not perl's**: a list assign from a reference-holding scalar binds by
  count (`_flattens` takes an ArrayRef for an aggregate), so `($a, $b) = ($b,
  $a)` over references loses the Phis' stamp, and the scan says so.
- **Wire identity is the exactness check**: compile corpus and probes with
  both producers (`tools/wire-verify.pl --wires DIR`) and diff the JSON after
  normalising paths; each difference is a fact the scan read otherwise.
- **Three double walks, not one.** A class method was translated by
  `_extract_class` for its return type and again for its graph
  (`B::SoN::_translate_once` keeps the first). B::SoN's settle pass
  translated the whole program again when a walk met a package-scalar writer
  it had not scanned (w1lib4); it is gone (`%PKG_UNREAD`).
- **chalk's lib is the scan's third corpus.** Its wires found three shapes
  corpus and probes have not: an s/// in an arm on an iterator it demotes is
  stored in place (the arm's walker), not rebound (the loop body's); a name
  in an inner foreach's list is aliased, not written; a `last` of an inner
  loop goes on round the outer one. Each was a refusal (8 graphs), not a
  wrong wire -- the backstop held -- and each wire is the base's now.
- **An instrument that loads B::SoN before the program changes the run**: a
  `-M` module `use`-ing B::SoN made w1lib1 settle twice; load only
  SoN::FromOptree in a walk counter.

Related: [[a-loop-is-walked-once]], [[the-write-scan-covers-the-run-set]],
[[a-foreach-alias-write-is-a-store-where-it-stands]],
[[the-wire-says-record-and-memory-by-name]].
