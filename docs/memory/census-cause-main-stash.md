# Census cause: a read of the stash %main:: (341 -> 345, if the check holds)

**Cause:** "a package variable %main:: that is not a scalar is not lowered"
held 4 cases: 013, 316, 317 and 346. All four round-trip in probes. Case 013
then hit an %INC read, fixed in the same batch.

## What changed

- **Producer:** the serializer gives a constant-key `exists $::{K}` or
  `$::{K}` a `stash_has` field. It is 1 where the key was in %main:: at
  CHECK, 0 where it was not.
- **The toolchain's own keys:** B::SoN's code puts about 17 keys in
  %main:: before the program compiles (SIG, BEGIN, ^WARNING_BITS, ...).
  Plain perl would not have them. %B::SoN::LOADED_KEYS is a snapshot taken
  when B::SoN loads; a key in it gets no fact, so it stays refused.
- **Chalk:** the loader's `_stash_changes` scans every method graph for
  anything that may change the stash at run time. Then `$STASH_CHANGES`
  names the first such thing:
  - a store to or delete from the stash
  - a symbolic deref (a PostfixDeref of a non-reference)
  - a string eval
  - `do FILE`
  - a require of a module neither a pure pragma nor already `use`d
  - an import or unimport the program does not define

  Where nothing like that appears, `exists` lowers to the fact and the
  entry lowers to "*main::K" (what a glob prints) or undef. Elsewhere the
  read is refused by name.
- **`my %s = %::`:** the producer already folds a copy of the stash into
  reads of the stash itself (346).
- **%INC (013):** the walk back from an %INC read for a require of its key
  now also follows `control_in` past a direct call that carries no memory
  edge. It stops at Region, Loop or Start, where a require in an arm may
  not have run.

## What they hit next

Nothing in probes. The pin census confirms.

## Lessons

- A fact read at CHECK time under `-MO` includes the toolchain's own
  effects. Snapshot what the toolchain made before the program compiles,
  and refuse those keys.
- A refusal test that expects a reason may meet an earlier GAP first.
  Assert the refusal and the loader's stated reason separately.
