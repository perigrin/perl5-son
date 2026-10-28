# Census causes: package aggregates; labeled jumps to an outer loop

**Causes:** "a store to the package variable @a/%h that is not a scalar"
(343, 344; 056 is @ISA) and "a jump from inside a loop to an enclosing loop"
(115, 309). All four round-tripped: 322 -> 326 at chalk ec972634.

## Package aggregates

- B::SoN spells `@::a = (1,2,3)` as EntryWrite(EntryDef @a, ArrayLiteral
  symbol "@main::a"), and LATER READS USE THE LITERAL NODE ITSELF -- `join`
  after a sub pushed to @q read the literal. So the literal must *be* the
  package's storage: chalk's loader now keeps the literal's `symbol` (the
  Aggregate node had dropped it), the EntryWrite copies the contents into
  a module global in place (`_pkg_aggregate_ptr`, sharing the shared file
  lexical's `@chalk_lex_array/hash` helpers), and every later lowering of
  that literal is the global. A literal read before its store is refused.
- perl's own aggregates (@ISA @EXPORT %INC %ENV %SIG @ARGV, stashes) are
  refused by name: perl puts what they hold there.
- **`local @a` inside a scope was a silent wrong answer in the producer**:
  its save is the name's SSA binding (none inside a sub), the restore
  rebinds the name and stores nothing. Chalk printed "5 5" for perl's
  "5 1". Producer a2c9518 refuses it unless restored at program end;
  chalk also refuses a literal stored by a *second* store (a restore).
  The same store run twice (an inlined sub called twice) is fine.

## Labeled jumps

`_loop_exit_label_for` (the arm's target) looked only at the innermost
loop. Now it also walks the enclosing loops on `_loop_ctx_stack`: an arm
reaching an outer loop's exit Region is its `last`, one reaching a Region
that outer loop heads is its `next` (sets that ctx's latch_label); the
`next`-arm recorder finds the ctx by latch label anywhere on the stack.
The `last` recorder already searched the whole stack.

## Lessons

- A test that asked perl through `qx($^X -e '$src')` with `''` inside the
  source got an empty "expected": it passed only while chalk refused.
  Feed perl a file.
- Pinned the wrong hash once (typed a guess): the census then fails at
  `git archive`. Copy the hash from `git log -1`.
