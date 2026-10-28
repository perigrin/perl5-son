# Census causes: a die's site, require/%INC, \constant (334 -> 339)

**Round-tripped:** 215 (335, loop phi through next arms), 138 318 319 (338,
`\1`, require of a pragma, %INC's truth), 063 (339, a die of several
arguments / not ending in a newline).

## A die's site (producer 7edfc7d, chalk 788ac6d7)

"perl's message names the file and line, which this lowering does not
know" refused several shapes. The producer sees them: each Unwind now
carries the file and line of its statement's COP (`_cop_for`, the nearest
nextstate up the parent chain). chalk checks a message at run time and
appends " at FILE line N." (or "Died at ...", empty) where it does not end
in a newline. The census compiles and runs the same path, so the text is
perl's. Next uses of the same idea: a division by zero in an eval
("Illegal division by zero at ..."), warn with no handler.

## %INC and require

`require strict` (a pure pragma) is true; `$INC{K}` is read only as a truth
(its value is a path): loaded where a require of K is on its memory chain
or K is used; not loaded where nothing the program loads loads others;
else refused. Printing it gave "1" for the path in a probe before the
consumer check was sound (below).

## Node::remove_consumer removed by id (bug, fixed)

Ids are content hashes, so two Coerces of the same content share one.
Analysis replaces a Coerce with a new one and removes the old from its
operand's consumers -- by id, which removed the new one too. Any check
over `consumers` could miss a reader: the %INC check missed a print's
Coerce. Removed by identity now; the %INC check also scans @PROGRAM.

## Not done, and why

- 091 (eval in its caller's context, list call): a list-context eval
  value inside an inlined callee leaked a value across inlines (the
  flatten path read the first inline's array). Reverted; still refused.
- 006/062 (division in an eval): needs the may-die node tagged with its
  eval, or a division made before the eval but lowered inside it would be
  caught where perl dies. 093 (Num read as Str): exact for printing, not
  for later arithmetic -- refused.

## Lessons

- Code written before its test: twice this stretch (the loop-phi latch
  rule, the eval change). The first was confirmed failing against the
  committed worktree afterwards; the second was reverted.
- A consumer list is not proof of who reads a node; when soundness
  depends on it, scan the program's inputs.
