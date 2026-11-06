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
