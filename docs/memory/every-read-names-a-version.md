---
name: every-read-names-a-version
description: "Wire v2 stage 7: every memory read names a version (V6). What each class needed in B::SoN and chalk, the three silent wrong answers it found (a field, a `my` and a package aggregate copied before a later write), the verifier's precision fixes, and the list-assign context bugs"
metadata:
  type: project
---

Wire v2 stage 7 (branches `v2-s7`, 2026-11-22). V6 (`read-unversioned:C`)
went to 0 on the corpus and the probes; see the plan's baseline note,
section 13, for chalk's lib.

**What each class was, and the fix (producer):**

- `field`: a `:reader` accessor's body (B::SoN.pm `_readers_read_fields`
  made the FieldAccess with no memory: it takes the accessor's Return
  memory now); a field array or hash read whole (the padav/padhv handler
  pushes a FieldAccess at `$sim->memory`, as the scalar field read did).
- `package` / `package-aggregate-literal` (W10): a package aggregate
  flattened into a list is an `EntryDef` with `mem_in` (the rv2av/rv2hv
  handler); before, the list took the literal last stored, which chalk
  read as the global at the list's first use. A match's unbound `$_` is
  `_entry_live_value`'s read. A glob slot (`*$g{HASH}`, gelem) has memory.
- `my-aggregate`: `my @x;` binds the slot itself; a whole read of one the
  sub writes (`$MUTATED_SLOTS`) is a PadAccess with `mem_in`.
- `through-ref` / `args`: a container slice read (no OPf_MOD) has `mem_in`
  (aslice/hslice, both contexts); a returned array's scalar face (Count)
  is read where it returns; a ternary arm's element re-read after its
  store took that store as a POSITIONAL input (a v1 leftover the loader
  did not catch) and takes it as `mem_in` now.
- `external` (Q13): a Call whose EffectTable `reads` is `external` takes
  `mem_in` in the generic dispatch.
- `cell`: no producer change -- see the verifier below.

**chalk:** a read whole at a version is a COPY made where the read is
(reads_before makes it before the next store): a package aggregate's
EntryDef, a field's FieldAccess, a `my` aggregate's PadAccess
(`is_versioned_read`; `is_my_array`/`is_my_hash` answer for it too, so every
site that knows the variable knows it). A hash flattened by its package
EntryDef needed the HPairs branch of `array_of`. Analysis's tied-scalar
rewrite detaches a replaced `tied()` from memory (else reads_before made it).
WireCheck's W10 (`_flattened_package_aggregates`) is deleted: off, the
probes were identical. Lower.pm's "two list assignments bind one `my`
scalar" refusal is deleted: B::SoN binds a placed list assign's scalar
targets to reads at its version (fk7, rv1, rv11 SAME).

**Silent wrong answers found (WRONG at base, SAME now):** rv8 (a field
array copied, then pushed: `1 2|1 2`), rv9 (field hash), rv10 (a package
array copied, then pushed), rv12 (`my @x; push; my @c = @x; push`). Each is
the same defect: one node for every read of an aggregate the sub writes.

**The verifier was wrong four ways (SoN::Verify V6):** a list slice
(`index_count`) picks from values, not memory; a use by a dead node (a
loop scout's leftover condition) is no use; a record's targets are bound,
not written (a `my (%a) = @_` read whole needs no version); an item of an
alias list -- a foreach/map/grep list, a Phi or ?: of an aggregate's
bindings -- whose every use is a container use is a place. Each has a
hand-built case in t/wire-verify-v2.t.

**The list assign's value (found in stage 6, fixed here):** the generic
aassign path left the right side's own mark on the stack, so an enclosing
print lost what it pushed before (`print 7, (($x,$y) = (5,6))`: 56); in a
list it now yields its `my` scalar targets as they are after it, in scalar
context the right side's count where that is known (constants, sub calls).
The deparser's anchored bindings are spelled after the ones their value is
made of (`_after_their_inputs`: `scalar(%stale9)` before `%stale9 = ...`).

**Lessons:**

- **A versioned read of an aggregate is a copy.** Naming the version is
  half; the consumer must make the read there, and for an aggregate that
  is a copy, not the pointer -- the pointer read early still sees the push.
- **A wrong verifier rule looks like producer work.** 4 of the 6 corpus
  shapes left after the producer fixes were the rule's: decide "is this a
  read whose value is used" before adding `mem_in`.
- **Grep for positional memory after a format change.** One Subscript still
  took its version as a third input; V1 does not see an input.
- **`!grep {...} @u ? 1 : 0` is `!grep {...} (@u ? 1 : 0)`.** It crashed the
  verifier on Carp: parenthesize a list operator before `?:`.
- **A copy at a version is of what the PLACE lowers to**, not of the
  variable's storage: `my ($c, @x) = @_` binds @x to the arguments, and the
  first copy took an empty array (only chalk's suite saw it, t2-slurpy-args:
  add rv14/rv15-like probes for every way a variable is bound).
- **A new mem_in reaches as_v1's consumer too.** An external read handed
  memory v1 never had made the deparser read an eval join's store as a value
  (corpus 006, the round trip 430 -> 429): run the deparser census with the
  producer change, not only the LLVM one.
- **An oracle keyed by structure renames when a memory input changes**: 8
  Count proofs "lost" and 8 "new", one for one; re-recorded, keeping the
  allowed-lost rows as they were.
- **Two runs of the machine at once double every time** (another session's
  `--jobs 8` put the load at 20): measure with fewer jobs, not more.

**Still open:** a scalar-context list assign of a builtin's list or of an
aggregate (`while (my ($k, $v) = each %h)` is one) is still the Assign
itself; `my $a = rand();` is a B::SoN INTERNAL ERROR (stack underflow,
masked as a skip) at base too; `if (C) { @l = @x }` with only the copy in
the arm forks control without an If (V9; chalk refuses it by name).

Related: [[wire-v1-is-gone]], [[a-class-read-names-its-memory-version]],
[[a-call-s-stores-are-its-mod-set]].
