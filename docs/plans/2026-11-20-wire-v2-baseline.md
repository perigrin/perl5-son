# Wire v2: baseline, inventory and measurements (stage 0)

Companion to `docs/plans/2026-11-20-wire-v2.md`. Measured 2026-11-20 on branches `v2-s01` in both repos. "Base" is producer 6d212cc (`wip/chalk-lib-roundtrip`) and chalk 8c512c2e (`bson/llvm-corpus`), each with only `tools/gates.sh` added (producer ebabb75, chalk b6fd052d). "Stage 1" is the heads after the debts: see the last section.

## 1. The gates, in one command

```
HOME=/home/runner nohup tools/gates.sh --chalk /path/to/chalk --out DIR > DIR.log 2>&1 &
tools/gates.sh --summary --out DIR
```

`tools/gates.sh --list` names the six gates and their limits. It copies both trees into `DIR/snap`, so edits made while it runs do not reach it, and it resumes: run the same command again after a restart. chalk's `tools/gates.sh` is the same script, entered from chalk's checkout. See `docs/memory/the-gates-are-one-command.md`.

## 2. Numbers at base

| gate | result at base |
|---|---|
| producer suite | 741 files, 0 failing (742 with `t/wire-verify-ratchet.t`, run as the ratchet gate) |
| chalk suite | not run to its end here: 236 of 916 files, 0 failing, when the run was stopped to free the machine. The last full run at this pair of commits is in `docs/memory/chalk-takes-the-class-read-wire.md`: 917 files, 0 failing |
| census | ROUNDTRIP 426, DIFFERS 0, LLI_FAIL 0, GAP 5, LOAD_FAIL 0, NOJSON 0 (431 cases) |
| corpus gate | gate-green 222; `paad/worklist.json` untouched |
| audit probes | SAME 348, REFUSED 114, LOUD 2, WRONG 0 (464 probes) |
| verifier ratchet | corpus and probes rows hold; the chalk rows were not compared (they named c1a48dfe) |

The five census GAPs: 008 (`%SIG` where perl may raise warnings of its own), 210 (a statement Coerce), 229 (`utf8::upgrade` is XS), 291 (a string eval of run-time code with a lexical in scope: the producer's refusal), 385 (a match against a pattern built at run time).

Times on this machine (4 cores, with other jobs running beside them, so upper bounds): producer suite about 15 minutes at one worker; the ratchet over corpus and probes 201 s; the census 5 to 15 minutes depending on load.

## 3. The verifier's chalk rows, re-counted

The `chalk` rows of `t/data/wire-verify-baseline.tsv` were c1a48dfe's (2026-11-19), from before class reads took a memory version. Re-counted at the stage-1 heads (section 7); the middle column is the same chalk lib under the base producer, which is what tells this stage's effect from everything that landed between c1a48dfe and base.

CHALK_ROWS_TABLE

What moved, and why:

CHALK_ROWS_NOTES

## 4. The three measurements for Q6 and Q7

Instrumented on the scratch branch `v2-s01-measure` (producer, one commit on ebabb75, **never merged**): `_scout_mutated_targs` logs one line per loop the real walk translates (not the loops walked inside a scout). Run over the 431 corpus cases, the 486 probes and chalk's 219 lib modules. A library loop that many wires hold is counted once, by file and line.

| set | loops translated | needed a second `_scout_once` (the stamp guess failed) | loops where the syntactic may-write scan missed a key the scout found |
|---|---|---|---|
| corpus | 212 (155 array / map / grep, 20 range, 37 while) | 6 | 2 |
| probes | 218 (49 array, 126 range, 43 while) | 3 | 0 |
| chalk lib | 1629 (1448 array, 63 range, 118 while) | 25 | 2 |

No loop needed a third scout.

**Q7 (roll back and re-walk, or refuse, when the optimistic stamp fails at sealing).** The count is not zero: 34 loops, 1.7 % of 2059, and 25 of them are in chalk's lib (Earley.pm, Analysis.pm, Actions.pm, Bindings.pm ...). By the accepted recommendation that means the `NodeFactory` `mark` / `rollback` journal, not a refusal: refusing would take 25 chalk-lib graphs off the wire. The second walk stays, but only for those loops.

**Q6 (the may-write filter).** The scan as section 5.2 describes it (a pad op with `OPf_MOD` or `OPpLVAL_INTRO`, `OPpTARGET_MY`, an assignment's target subtree, an op-assign's and an inc / dec's operand, a foreach iterator, `padrange` with INTRO, and the operands of the builtins that write an operand perl does not flag: push, pop, shift, unshift, splice, chomp, chop, s///, tr///, undef, delete, each, keys, values, read, sysread, open, sprintf, substr, vec, pos, local, a reference taken, a sub call's arguments, an in-place sort or reverse) was a superset of the scout's answer in 2055 of 2059 loops. The four misses are two slot kinds:

- corpus 003:26 and 373:4, `grep { $on[$_] .. $off[$_] } @idx`: the scalar-context range (flip-flop) keeps its state in its own pad slot (the `range` / `flip` op's `targ`). Add: a `flip`, `flop` or `range` op's `targ`.
- chalk `lib/Chalk/Bootstrap/Perl/Target/Perl.pm:1691` and `:1857`, `for my $stmt (...) { my $code = $self->_emit_node($stmt); ... }`: key `0`, pad slot 0, rebound from a Call to a Phi. Add: slot 0 when the body holds a sub or method call (stage 9b must first say what binds slot 0; the measurement only shows that the scout sees it move).

The condition scout of a while loop (`_scout_condition_mutated_targs`, 37 + 43 + 116 conditions) found no key the scan missed.

So the filter is workable: with those two rules W is a superset everywhere measured, and what it over-approximates costs trivial Phis that sealing removes. The sealing check (`_refuse_unscouted_writes`) stays as the loud backstop.

The scan was written for the measurement and is in the scratch commit (`_measure_may_write`, `_measure_body_ops`); stage 9b can start from it. Its body is "the ops on a cycle through the loop's first op" (reachable from it by `next` / `other`, and reaching it again; a `next` op is an edge back).

## 5. Where chalk's `Phi::is_memory` and the wire's flag disagree

`tools/phi-memory-agreement.pl` in chalk (committed) loads wires and compares `Phi::is_memory` with `fields.memory`, Phi by Phi.

| set | wires loaded | Phis | flagged memory | disagree |
|---|---|---|---|---|
| corpus | 431 (0 refused by the loader) | 753 | 298 | 0 |
| probes | 462 (24 refused) | 716 | 379 | 4 |
| chalk lib | PHI_CHALK |

The four are in probes cl5, cl19 and cl20 (a closure over a variable a loop writes): a loop's memory Phi over `MakeCell` and `CellWrite`, which the producer flags and `is_memory`'s case list does not know. The flag is right; chalk refuses all three probes today for other reasons. Nothing for the producer to fix before stage 6; chalk's lowering of a cell version under a Phi is new work when those probes are taken on.

## 6. What records wire shapes

| what | where | how it is made | v2 work |
|---|---|---|---|
| corpus ir blocks | producer `t/corpus/mdtest/{pvm,chalk}/*.md`, 689 cases; checked by `t/corpus-ir-blocks.t` (opt-in, `SON_CORPUS_IR=1`) | regenerated: `tools/corpus-fill-ir.pl` | **already stale**: `--check` reports 683 of 689 drifted at base (last filled about 2026-10-22). Refill at stage 6 as planned; do not read a drift there as a v2 regression |
| the shape leg of chalk's corpus gate | chalk `t/bootstrap/corpus/son-corpus-wide.t` against chalk's own corpus copy (`shape_subset_check`) | hand-kept ir blocks; a subset match on kinds and stamps, not on inputs | 223 of the cases pass the shape leg today; watch the count at stages 6, 8 and 9 |
| chalk JSON fixtures | `t/bootstrap/ir/data/*.json`, 18 files (one is 1 MB), read by 13 test files; `t/fixtures/codegen-harness/gap-map.json` is no wire | recorded B::SoN output, `version: 1`; all 18 have `control_in`, 9 have `MemStart` or `memory_input` | the v1 upgrader keeps them loading until stage 6; convert them there with a script, not by hand |
| producer tests that read a wire | 72 files mention `control_in`; 106 index `inputs` by position; 8 name `memory_input` or `MEM_MIN_INPUTS` | all but 3 compile a program in the test and read the fresh wire | each must move with the wire at stage 6 (the v1 writer of stage 3 lets them wait) |
| producer hand-built wires | `t/wire-verify.t` (`nd()` / `graph()`), and two more with literal `control_in =>` | hand-written v1 | rewritten with the verifier's v2 rules in stage 3 |
| chalk tests that mention `control_in` | 99 files | 27 load a B::SoN wire (`from_json` / `run_detail`); about 58 build chalk nodes directly (`set_control_in`, the paused Earley front end's graphs, hand graphs in `t/lib/.../HandGraphs.pm`) | the direct builders are the "Earley front end" risk of section 9.1: if they place memory positionally, convert them in stage 2 |
| the probes' verdicts | chalk `t/data/audit-probes/BASELINE.tsv` (475 rows) | regenerated: `tools/audit-probes.pl --update` | unchanged by the format; a verdict that moves is a finding |
| the verifier's counts | producer `t/data/wire-verify-baseline.tsv` | regenerated: `tools/wire-verify.pl --tsv` | new `corpus2` / `probes2` / `chalk2` rows at stage 3 |

## 7. After stage 1

STAGE1_SECTION
