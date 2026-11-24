---
name: the-wire-says-record-and-memory-by-name
description: "Branch clause3: record flagged where B::SoN builds it; an alias list's package scalar names its version (V6 no longer excuses it); the deparser reads as_v1's memory_input mark, not a table; time/sleep/rand/srand ordered; the double walk needs a design decision (measured: 8 of 1671 corpus walks)"
metadata:
  type: project
---

Branch `clause3` (2026-11-24; baseline section 24; producer 9afe7f0..c66429e,
chalk add5ce17..b1de1e4f; gates2 all PASS). The final audit's clause-3 caveats and items 7 and 10.

| item | outcome |
|---|---|
| `record` derived by the serializer | B::SoN decides record-or-store before it builds the list Assign (the only site that made one, measured), `record => 1` is in its content hash, `_pin` dies on one; the serializer writes the flag |
| the double walk (`%LOOP_HINTS`) | NOT removed: a design decision, reported (below) |
| EntryDef with no version in an alias list | the gvsv handler gives a foreach/map/grep list item `mem`; V6's alias-list exemption no longer covers a package scalar; 0 such items over corpus and probes |
| positional memory in the deparser | as_v1 marks every node it appends a mem_in to (`memory_input`, not Calls only); `_mem_input` in the reads scan, the version scans, the hoist, `_expr`, `_latest_store_read`; `%MEM_MIN_INPUTS` and its test deleted |
| time, sleep, rand, srand unordered | EffectTable: time reads the `clock` (an ordered class), rand writes the random stream; chalk BuiltinTable `reads_state` for both; sleep/srand statements stay refused by name in T2 |

**The double walk.** The walk guesses four things before a loop body:
which slots get a header Phi (`extra`), a Phi's stamp (its init's,
`unstamped`), whether the body writes the foreach iterator (`writes`), and
whether an aggregate a read flattened is written later (`mutated`). Over the
corpus, 8 of 1671 sub walks went round again: 4 by a stamp, 4 by the
iterator write, none by the other two. Braun's construction has none of
these: its incomplete Phi has no class. The walk reads a binding's class to
choose what it builds, so dropping the guess is a choice between precision
(class-free Phis), a post-seal pass that re-decides what the walk built from
a class, and an exact pre-scan (still a second pass over the ops).

**Lessons:**

- **An instrument loaded with -M is compiled into the wire.** Its subs are
  graphs: corpus #graphs read 2373 for 1082. Compare counts only between
  uninstrumented runs.
- **The table agreed with the mark on every real wire.** The positional rule
  was never wrong on corpus or probes; it fails on a kind it does not list.
  The test gives a node a mem_in the producer does not (a Chomp's).
- **An ordered read renames structural oracle keys.** rand pinned moved its
  Call ids down by one in chalk's interval oracle (loops:11, 6 new = 6 lost):
  re-keyed, not re-recorded.
- **The deparser printed `no` for perl's `ok`** on `time; sleep 1; time`:
  a silent wrong in the round trip that chalk never showed, because T2
  refuses a sleep statement.

Related: [[the-final-audit-s-wrong-answers-lowered-or-refused]],
[[the-deparser-reads-v2-through-as-v1]], [[a-loop-is-walked-once]],
[[the-effect-table-is-the-one-statement]].
