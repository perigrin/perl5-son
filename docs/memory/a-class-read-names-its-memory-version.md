---
name: a-class-read-names-its-memory-version
description: "ref / blessed / reftype take the memory they read as their last input and bless is a version; a hash or package array read as a scalar is a Count at a version. The wire had the place all along; what chalk must do to drop its two rules"
metadata:
  type: project
---

Branch `class-reads` (2026-11-20), from wip/chalk-lib-roundtrip ba6f585. The
problem is [[ref-of-a-blessed-reference-names-no-version]]: `bless $h, "K";
print ref($h)` and `my $r = ref($h); bless $h, "K"; print $r` were one wire.

**What the producer does now, with no new wire shape:**

- `RefType` is `[reference, memory]` (`%SoN::Deparse::MEM_MIN_INPUTS`
  RefType => 1). `blessed`, `reftype` and `reftype_of_ref` are builtin Calls
  flagged `memory_input`, memory last. Decided by one column of the effect
  table: `B::SoN::EffectTable::reads_at_version` (reads `object-class`).
- `bless` has `version => 1`: always `[ref, class, memory]`, flagged, and the
  memory after it. Before, it carried memory only when its operand happened to
  be a literal (the "whole array or hash operand" rule) and was never the
  memory after.
- A hash read in scalar context -- `%h ? :`, `if (%h)`, `!%h`, `%h + 1`,
  `my $n = %h` -- is `Count(hash, memory)`: the padhv handler for a `my`
  hash, the rv2av/rv2hv-over-gv handler for a package hash AND a package
  array (`@g ? :` was the same defect: one TernaryExpr(ArrayLiteral) shared
  by two prints, "tt" for perl's "tf"; chalk printed that at base). `keys %h`
  is told apart by OPpPADHV_ISKEYS / OPpRV2HV_ISKEYS, not by OPf_MOD alone.

**Lessons:**

- **"The wire has no place for it" was wrong.** The effect table's note and
  the audit both said a class read waits for wire v2's `mem_in`. A Count, a
  Subscript and a flagged Call already carry memory by position; RefType
  needed one row in `%MEM_MIN_INPUTS`. Ask what the nearest read that IS
  versioned does before filing a shape under the next format.
- **A read is only half; its write must be a version.** With the memory input
  alone the two programs were still one wire: both reads named MemStart,
  because bless was pinned and not placed.
- **A versioned read meets every consumer's "is this read bound" list.** The
  deparser's stale-read pass names its kinds (Subscript, Count, keys/values);
  RefType and the class Calls were added there and at the emission rule
  (`no rule for control node RefType` is what a missing second half says).
- **Input order is not chain order.** `_last_bound_input` took the last bound
  node it VISITED; a read's operand comes before its memory in the inputs, and
  a second read of the first's operand moved the anchor back above the bless
  (`my @r = (ref($o), ref(bless $o, "K"), ref($o))` declared @r first). It
  now never moves back along control (`_chain_follows`).
- **A sub call shadows a Count.** The deparser excused every Call without
  `memory_input` (for `undef *v`); a sub call has none and is a version.
  `our @g; my $a = @g; add(); my $b = @g` rendered "1 1" at base.
- **A new versioned shape can land on a consumer's old bug.** chalk lowers
  `Count` of a package hash's bare `EntryDef` as an array length
  (`Containers.pm:832` asks `is_named_hash`, which EntryDef does not answer):
  "an array element read through no ARRAY reference" at run time. `scalar(%g)`
  hit it at base (probe hs9); `%g ? :` was shielded by the load-time refusal
  and now reaches it (probe hs7: REFUSED -> LOUD, a refusal at run time, not
  a wrong answer). Run the new shape's OLDEST spelling through the consumer
  at base before blaming the change.
- **A positional memory input is a new input to a consumer that counts
  uses.** chalk's `RefType` has no `memory_operand`, so its use scans
  (`list_only`, `_use_counts` in Target/LLVM/Builder.pm) take the second
  input for a value: a RefType whose memory is a pinned `%{$r}` copy is "a
  hash read whole taken as a scalar (RefType)", one whose memory is a call
  also printed is "a call used both as a list and as a scalar". Three corpus
  cases (adjacency-08_references, -10_io, -11_oo) go ROUNDTRIP -> GAP at
  chalk 39b15261: census 426 -> 423, DIFFERS 0. Loud, not wrong, and one
  line in chalk (below) puts them back -- measured on a scratch copy. "No
  new edge name" is not "no consumer change": ask what the consumer does
  with an input it has no name for, and run the CENSUS, not only the probes
  (no probe had a class read after a list-context call).
- **Judge a probe with the consumer's own harness.** A hand-rolled `got eq
  want` over 2>&1 called run-time refusals, stderr interleaving and a cwd
  miss WRONG (ar17, fl10, im23, io8, w1lib*). chalk's
  `tools/audit-probes.pl` (run from a scratch tree of symlinks to its lib,
  with the new probes copied in) says LOUD for the first three and SAME for
  the rest.
- **Still not bound by the deparser:** an entry-version Count of a `my`
  aggregate declared with no value (`my %h; my $n = %h; $h{a} = 1`): its
  operand is not in the prologue. Arrays had it at base; a TODO in
  `t/wire-a-hash-read-as-a-scalar-is-its-count.t`.
- **Not a hash read:** `while (my %i = f())` hands the pinned HashLiteral to
  the condition (Carp::ret_backtrace). That is a list assign's scalar value
  (its right side's count), pinned, and is left.

**What chalk must do**, first to take this wire at all and then to delete
its two WireCheck rules:

- `Chalk::IR::Node::RefType`: `method memory_operand() { return
  $self->inputs->@* > 1 ? $self->inputs->[1] : undef }`, as Count, Ref and
  PostfixDeref have. That alone restores the three census cases (426).
- `_class_reads_across_a_bless`: make a class read AT its memory input --
  no later than the next version after it (a bless, a sub call) -- the way
  `reads_before` already loads a memory-kept variable before the store that
  replaces its version. Then the rule goes and
  `t2-bless-a-scalar-or-code-reference.t`'s third case is perl's answer. Until
  then the rule is still needed: it now refuses only reads whose first use is
  past a later bless or call (ef9, st2, vp19), and bless1, bless2 and st16
  pass it, correctly, because the read names the bless.
- `_hashes_read_as_scalars`: give `EntryDef` (sigil `%`) the `is_named_hash`
  answer so its Count is a key count; then the rule matches nothing the
  producer emits except the pinned `while (my %i = ...)` literal above.

Related: [[the-effect-table-is-the-one-statement]],
[[the-wire-verifier-and-its-ratchet]], [[run-long-checks-on-a-snapshot]].
