# Agentic review of the session's chalk commits (15a3064f..57ea6240), 2026-11-05

- A fresh-context agent reviewed the 15 commits. It wrote ~145 probes and
  bisected each finding with `git archive` snapshots.
  - Probes are in the scratchpad's review/ folder.

## Regressions: refused at the start of the session, WRONG after (fixed in chalk 5a60302b)
1. 5f40cdf0 `g(@a)`, callee writes `$_[N]`: @_ is a copy stored back. A
   callee that also reaches @a (a closure) read/wrote the other copy.
   - Now the callee must touch no aggregate but @_ and call no sub.
2. 70247c1e `?:` of lists in a list: both arms are made. `@$y` on an Int
   emitted invalid IR. Refused.
3. 57ea6240 s///ge: Divide/Modulo in the body exited 255 silently. Refused.
4. 287a6c03 frame-scoped `_pending_tag_reads`: this removed a refusal that
   was hiding miscompile A. Backed out.

## Older miscompiles (wrong at the session's start, fixed in chalk 1b9231da)
- A: a read whose memory is a loop's/if's merge Phi was made at its use,
  after a later store.
  - `_freeze_merge_reads` now runs after each If/Loop.
  - It skips open evals: inside one it broke pvm 156 via the eval join.
- B: a foreach over a list that flattens arrays aliases their elements, but
  chalk's list is a copy. A store into it is refused.
- C: a `[...]` pinned in a loop body, written in an inner loop, was rebuilt
  per use.
  - Loop bodies now collect pinned literals.
  - If arms do not: there the literal is the arm's value (`$v // []`), and
    collecting it gave dominance LLI_FAILs.
- The first try at A+C regressed the census to 406 (3 LLI_FAIL). The full
  check caught it.

## Lessons
- Removing a refusal can unmask an older miscompile it stood in front of.
  Probe the refused neighbour shapes, not just the target.
- A fix that makes a value early (freeze) or collects a node as a statement
  must exclude eval bodies and if-arm values.
- Still open (pre-existing, not fixed): family A inside an eval body.
