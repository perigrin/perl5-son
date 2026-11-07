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

## Slice 17: list returns (chalk e436df5e, test 3c...)
- Four check rounds. A call's context must come from its USE (element of
  a list, print/push/join/call argument, map value, a return's list) --
  not B::SoN's want (`$o->m || "x"` says list) nor its stamp (`my $n =
  f()` stamped List). Memory positions are not uses.
- Perl traps hit: `for my $x (@{$node->inputs}) { $x = ... }` writes the
  graph (aliasing) -- T2 then handed a mutated graph to the fallback (two
  GAPs); now tested (t2-never-mutates-the-graph.t). A bare `grep {...}
  @pos` inside an || chain swallows the rest of the condition.
- T2 takes ~124+ of 430 outright; census 412 throughout slices 6-17.

## Slice 18: the class feature (chalk a7c137e0)
- perigrin chose it next. Methods join the run-time MOP's stashes; `new`
  is built at its call (fields root-first under :isa, then ADJUST).
- Traps: FieldAccess.field_index is perl's (a child's after its parents'),
  the MOP's fieldix starts at 0 per class; B::SoN stamps array fields
  Scalar; a class named B collides with perl's B:: (test bug); `sort { $a
  <=> $b }` inside a Builder method uses the builder for $b.
- Wrong answers caught by the full check: `return values %h` in list
  context (246), then `return scalar(keys %h)` over-applied.
- Pre-existing Context.pm miscompile (TODO): a missing required :param
  makes the object where perl dies.

## Slice 19: closures (chalk, after a7c137e0)
- Cells are the captured variable's location, heap-allocated when this
  function captures it. First check: 3 DIFFERS -- accepting every shared
  pad let a named sub's view of an outer lexical become its own cell.
- B::SoN gap (producer, this repo): `$t += 1` on a capture has no
  CellWrite (the add is dead); T2 and Context.pm refuse it. Fix belongs in
  FromOptree.
- perigrin: uncaught die needs no eval (stderr + exit). Next slice: die.

## Slice 20: uncaught die (chalk, after 58a9eabc)
- STDERR + " at FILE line N.\n" + exit 255; dead arms skip the join.
- Wrong answer caught building it: try/catch exited. A die in a sub that a
  caller's try wraps has no eval_id, so the eval/try check must scan the
  whole program (computed in lower_program; a func's $b->{ret} is its own).
- The container restarted mid-check once: the base worktree dir came back
  empty, but check.sh only needs the saved g217-base.txt.

## Slice 21: eval and try (chalk + producer)
- A die is an error flag, not a longjmp: t2_die_unwind sets $@ and
  @t2_dying when an eval is open (depth > 0); every call checks the flag
  after it returns and branches to the open eval's catch, or returns up.
- Producer fix (perigrin: "both my repo, just fix it"): an eval's end is
  its own memory version (a memory Phi on its Region). Without it B::SoN
  made two `$@` reads after nested evals one node, and the outer printed
  the inner's message. Deparse and Context.pm skip that memory Phi as a
  value; the deparser's element-read pass treats it like an if's merge
  (an element read indexed by a later loop stays in the loop).
- Dominance trap: a value made in an eval body after its first block need
  not dominate the join. close_eval poisons those memo entries: constants
  are remade, anything else is refused. The catch block gets a local memo.
- Refused while a program has an eval (perl dies where T2 would not):
  method calls (not `new`), divide/modulo, any scalar deref (even dead:
  `my $v = $$x` unused still dies), eval in list/caller context.
- `$@` starts ""; a normal eval end sets it ""; `die ""` is "Died at ...".

## Slice 22: perl's own dies (chalk, producer 0c978df)
- t2_div/t2_mod raise through t2_die_unwind; the builder checks the dying
  flag after them as after a call. Trap: close_eval popped the frame
  before making the body's value, so a divide there saw no open eval.
- t2_mresolve(invocant, name, at) replaces classof + mfind: perl's
  messages for undef / unblessed / empty / no method / package not loaded
  ("perhaps you forgot to load"). Method Calls carry file/line from B::SoN.
- Trap: un-refusing undefined method names let `Derived::SUPER::hi`
  through (pvm 056); qualified names stay refused.
- Mishap: `perl -0pi` that reads another file with <> inside the loop
  empties the target. Use a script that opens files itself.

## Slice 23: qualified method names (chalk 94f3a9e5, producer 6ed2b9a)
- perigrin: "include other qualified names too". `Pkg::m` starts at Pkg,
  `Pkg::SUPER::m` at Pkg's @ISA (B::SoN puts the compiling package in
  front of SUPER::). t2_mresolve(inv, m, at, start, mode); t2_mfind1 skip.
- Producer: method_redir / method_redir_super had no handler (a direct
  Call named `unknown`); rclass is a pad index on threaded perl. Dropped
  from every-op-has-a-disposition's allowlist (the ratchet catches it).

## Slice 24: UNIVERSAL (chalk)
- perigrin: "put them in a UNIVERSAL class that is the root of
  inheritance; isa is method isa ($other) { $self isa $other }". Done so:
  t2_universal_setup makes the stash; t2_mfind_u falls back to it.
- Traps: runtime wrappers must honour @t2_want (t2_list_of) or a list
  context reads past the value; `can` needs every sub in the stash, not
  only those called by name. Code values are {fn, env}: a trampoline
  (t2_stash_tramp) carries a stash method's pointer in env.
- Not yet: VERSION, `push @Pkg::ISA` (assignment works).

## Slice 25: @ISA is the MOP's parent list (chalk)
- perigrin suggested a tied @ISA; built as a view instead (the variable
  resolves to the stash's @ISA array, t2_mop_isa_arr), which perigrin
  accepted. Their framing: a tie swaps a container's default metaclass
  hooks for a new set -- @ISA is one container with a built-in metaobject.
  `tie` itself is queued after VERSION.
- unshift added for any array (t2_aunshift).
- Trap: t/bootstrap/no-tie-in-the-subset.t greps lib/ for the tie/tied
  operators -- a comment saying "a tied @ISA" fails it. That test guards
  chalk's own source (the bootstrap subset), not what T2 compiles.
