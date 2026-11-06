# T2 slices 6-7: objects and a run-time MOP (2026-11-06)

- perigrin's direction: method calls, inheritance, @ISA writes, SUPER and
  AUTOLOAD are all MOP manipulation. Build the MOP into the program's run
  time; static resolution is only an optimization over it.
- Built (chalk 68724d69); tests t2-slice6-objects.t, t2-slice7-dispatch.t.
  Census unchanged at 412 (the object cases stop on other shapes first).
  - An object: element 0 of its hash's %Array is the blessed class.
  - @t2_stashes: package name -> stash hash. A stash maps a sub name to a
    code slot (tag 7, a wrapper `%Slot (%Array* @_)`), and "@ISA" to an
    array slot (tag 6) of parent names (from use parent: MOP parent_name).
  - A method call builds @_, takes the class (object's or a name's own),
    looks the method up depth first through @ISA; none: a run-time stop.
  - Only subs whose names some method call uses are put in stashes; one of
    them T2 cannot build makes the whole program fall back.
- Lessons:
  - Functions were keyed by name; a method Call carries the bare name, so
    two classes' `hi` shared one function (a wrong answer). Key by sub.
  - In the Builder, `my ($b) = @_` hides sort's $b: sort plain keys.
  - `my (...) = @_` pinned by a following call: the reads after it are
    not in args; mapping only the targets read undef (6 for 14).
  - A check run in the background needs an explicit long timeout (the
    10-minute default killed one mid-suite).
- Next: `our @ISA = (...)` at run time, AUTOLOAD, SUPER::; then the five
  object cases (136, 175, 188, 212, 225) and what they hit next.

## Follow-up (chalk aeedc509)
- `our @ISA = (...)` writes the MOP; string comparisons; hash element
  stores. Census 412.
- Hash stores reopen slice 5's "hash reads are left in place": a pending
  hash read across a store OR A CALL (a sub may store) read the new value
  (22 for 12, 55 for 15). Refused now (hash_reads_settled). Settling it
  safely needs the read made where perl makes it, not hoisted above a guard.
- Pre-existing Context.pm miscompile (also on the baseline): a method
  storing through its invocant, a read kept before the call: 55 for 15.
  TODO test in t2-slice9-hash-stores.t. Not in the corpus.
- One census run showed 176 GAP ("a store to an element while a read
  waits"); not reproduced in 60 hash seeds or 2 more censuses. Watch it.
- T2 takes 76 of 430 corpus cases outright; the rest fall back. Plan
  (perigrin agreed): arrays/lists, sub calling convention, package
  variables, builtins, class feature, regex; then delete the fallback.

## Slices 10-12 (chalk ee1281ab, 6d25d545)
- `my @a` declared once per sub (unpinned PadAccess) is one %Array made at
  function entry; one in a loop body/arm is a pinned ArrayLiteral already.
  Arrays/hashes are lists wherever lists are refused (_is_list): their
  PadAccess is stamped Unknown, so stamp checks alone missed them.
- @ARGV from main's argc/argv, one global array. An array as a scalar is
  its count. && / || are values.
- List convention: a sub reading @_ as a list takes one %Array.
  `&f;` shares the caller's @_ -- it passed an empty one ("[]" for "[x y]")
  until an existing suite test caught it.
- Test-writing trap: subs named `s`, `m`, `y`, `q`, `tr` are operators.
- T2 takes 86 of 430 corpus programs outright (before slice 12).

## Slice 13: array references (chalk 5cac8982)
- First full check: DIFFERS 1, 6 suite fails, 5 wrong probes. Each was a
  shape T2 now reached for the first time:
  - `my @p = @$h` is PostfixDeref{copy=1}: aliased instead of copied.
  - PostfixDeref{sigil=$} (`${\ ...}`) taken as an array deref.
  - A read kept across a CALL that stores through a reference: arrays
    can alias now, so calls need reads_before too (9 for 1).
  - Refs as str/num stopped; perl gives ARRAY(0x..) / the address.
- Lesson: every new aggregate kind reopens read ordering (stores, calls)
  and every operator's handling of the new tag. Grep the runtime switches.
- Lesson: hand-counted [N x i8] sizes were wrong 4 times; a test now
  recounts them (t2-runtime-strings-are-sized.t).
- Reads through a reference stay where they are and are refused if still
  pending at a store/call (_through_ref); see slice 5's guard lesson.

## Slice 14: named hashes (chalk 22f322aa)
- First check: 8 suite fails, LLI_FAIL 2, census 410. Causes: a hash in a
  list (flatten = pairs), a store through foreach into a flattened list
  (perl aliases), IR tests' Length-of-array = count, and an OLD if_stmt
  bug newly reached: building a phi input in an arm can make blocks (a
  folded ?:), so the arm's end block must be re-read after it.
- Lesson: the full check is the only thing that catches these; each slice
  so far needed one or two rounds. Budget for it.

## Slice 15: package scalars (chalk 56105fd3)
- Read ordering bit three more times: exists not a memory read; EntryWrite
  and Delete not versions (two slice-14 wrong answers shipped, found by a
  probe of slice 15); B::SoN's version-less read of a write's target node.
- The cause is structural: _memory_input and _is_version are hand lists.
  Next: make them generic (any input that is a version; every statement
  on the chain a version) so a new store kind cannot be missed.

## Guard and slice 16 (chalk 5ffd81aa, 95f7f528)
- Guard: a statement a read takes as memory must be in _is_version, else
  refuse. Audit of the corpus graphs: readers and versions T2 handles are
  all listed; RegexSubst/Transliterate/Match/ElemRestore/CellWrite are not
  yet T2's and must be added to _is_version when they are.
- $_ is a package scalar (B::SoN desugars foreach aliasing to stores and
  write-backs); map/grep are ListAppend loops; their accumulator must be
  fresh per loop entry (a constant empty literal made at entry was shared:
  wrong answer, caught by an existing suite test).
- A printing death escaped T2's fallback (eval only wrapped build): one
  census case went ROUNDTRIP -> GAP. print_module is under eval now.
