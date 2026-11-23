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

| rule | stale row (c1a48dfe, 2026-11-19) | base producer 6d212cc | stage-1 producer |
|---|---|---|---|
| `#cases` | 218 | 219 | 219 |
| `#graphs` | 24215 | 24521 | 24521 |
| `#wires` | 218 | 219 | 219 |
| `allowed:param-bind` | 18 | 18 | 18 |
| `allowed:record` | 389 | 392 | 392 |
| `control-fork` | - | (rule not there) | 1 |
| `effect-rides-value` | 64 | 58 | 58 |
| `memory-order-disagrees` | 228 | 291 | 291 |
| `phi-arity:eval-join` | 40 | 40 | 40 |
| `read-unversioned:args` | 3 | 3 | 3 |
| `read-unversioned:external` | 87 | 87 | 87 |
| `read-unversioned:field` | 3560 | 3560 | 3560 |
| `read-unversioned:my-aggregate` | 379 | 373 | 373 |
| `read-unversioned:object-class` | 4451 | 0 | 0 |
| `read-unversioned:package` | 17 | 5 | 5 |
| `read-unversioned:package-aggregate-literal` | 1 | 1 | 1 |
| `read-unversioned:through-ref` | 215 | 215 | 215 |
| `write-floating` | 6 | 6 | 6 |

What moved, and why:

- `read-unversioned:object-class` 4451 -> 0 and `read-unversioned:package` 17 -> 5: the class-read work (`ref`, `blessed`, `reftype` read at a memory version; a hash or package array as a scalar is a Count at one), as the plan expected.
- `memory-order-disagrees` 228 -> 291. **Not this stage**: the base producer gives 291 on the same wires. The rise happened between c1a48dfe and base and was invisible because the rows were not being compared (the ratchet skips chalk's rows when chalk is not at the commit the baseline names). 223 of the 291 are a `Subscript`, 40 a `PostfixDeref`; 74 distinct graph-and-node pairs, the same sub counted once per wire that loads it. The largest: `TypeLibrary::join_types` (20 wires: "input says Phi, control says LocalAlias"), `Node::Region::reached_by`, `Node::Ref::_reshaped`, `Node::Assign::is_placed`, `Graph::program_nodes`, `Graph::component` (10 to 14 wires each: "input says Call, control says Phi"). Rule V5 at zero is still the strictest new demand of the plan; this is its real size.
- `#cases` and `#wires` 218 -> 219, `#graphs` 24215 -> 24521: one more module in chalk's lib.
- `control-fork` 1: `Chalk::Bootstrap::Perl::Actions::SubroutineDefinition`, after stage 1 fixed the three other chalk-lib graphs that had one (section 7).
- Every other row is unchanged between the base producer and stage 1. `#graphs` is equal too, which matters: see section 7.

Time: 219 compiles at 4 jobs took about 10 minutes, and the verifying pass over the 219 decoded wires (two of them 24 MB) about 5. That is Q16's number: too slow to run cold in chalk's suite on every run, fine warm with the cache the plan describes.

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
| chalk lib | 211 (8 refused) | 12834 | 6043 | 3 |

The three in chalk's lib (each counted once; the graphs are in one wire each):

- `Chalk::Target::LLVM::Builder::regex_split`, a Phi of `[Assign, Not]`: `is_memory` says memory (an input is an element store), the wire says value. A `Not` is a value, so the flag is right and the guess is wrong.
- `Chalk::Bootstrap::Perl::Target::EmitHelpers::_repair_stale_merge`, two Phis, `[RegexSubst, Phi]` and the `[Phi]` over it: the wire says memory (a pinned `s///` is a version), `is_memory`'s case list has no `RegexSubst`.

In all three the flag reads right. They are the subs whose lowering changes the day stage 6 takes the flag; run them by name then.

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

Heads: producer `v2-s01` 6c03947 (plus this note and `tools/gates.sh`'s time limit, committed after the run), chalk `v2-s01` 45a1b8d5. One `tools/gates.sh` run on snapshots of those two commits:

```
producer-suite  PASS  743 files, 0 failing [12m43s]
chalk-suite     PASS  917 files, 0 failing [64m29s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [2m33s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [7m52s]
probes          PASS  LOUD=2 REFUSED=112 SAME=361; WRONG 0, SAME lost 0, changed 0 [1m44s]
ratchet         PASS  prove exit 0; chalk's lib compared; rows that fell: 0 [2m46s]
```

(The ratchet's 2m46s is with the wires already compiled for section 3, from the same two commits; cold it is the 15 minutes of that section. chalk's suite is 64 minutes because one file, `t/grammar-conformance.t`, takes 40 minutes of one core.)

| | base | stage 1 |
|---|---|---|
| producer suite | 741 files | 743 files (two new tests) |
| chalk suite | 917 files at the last full run | 919 with the two gate files (two new tests) |
| census | 426 / 0 / 0, GAP 5 | the same five GAPs |
| corpus gate | 222 | 222 |
| probes | SAME 348, REFUSED 114, LOUD 2 of 464 | SAME 361, REFUSED 112, LOUD 2 of 475: cr3, cr8 and st15 turned SAME; eleven new probes, ten SAME and one REFUSED (fk7: a list assignment to an array, chalk's gap) |
| verifier, corpus and probes | rows as recorded | unchanged; `control-fork` 0 and 0 |
| verifier, chalk lib | stale rows | re-counted (section 3); equal to the base producer's in every row |

What stage 1 changed, in one line each (the notes are in `docs/memory`):

- **1a.** The arm scans ask `B::SoN::EffectTable::on_chain`; `SoN::Verify` has `control-fork` (the plan's V9, on wire v1). The rule found the same hole in ten more statements, all fixed: `$#a = N` (three corpus wires, through Carp), `tr///`, array and hash slices assigned, a package aggregate or one behind a reference assigned whole, a list assignment with a `my` aggregate among its targets, a field stored, incremented or op-assigned alone in an arm (chalk's ReferenceFlow), and `$st->{i}++` in two arms sharing one pinned read (chalk's Regex::Parse). `the-arm-scan-asks-what-the-walk-pins.md`.
- **1b.** `_list_count`: a list assignment to a hash in scalar context is the Count of its right side, taken before the store; `() = LIST` uses it too (two silent wrong counts fixed). chalk's `_hash_assigns_read_as_scalars` is deleted. `a-list-assign-counts-its-right-side.md`.
- **1c.** chalk lowers `reftype` (`referent_type`, `t2_referent_type`); a reference to a reference is `REF` to `ref()` as well, which was `SCALAR`.
- **1d.** Already merged before this stage (producer 714b191).

The three refused probes the stage was asked to look at:

- **hs5** (`while (%h) { delete $h{ (sort keys %h)[0] }; ... }`): REFUSED by chalk, "a slice taken as a scalar (Coerce)". The wire is right (the hash's truth is a Count at the header memory Phi). chalk has no lowering for a list slice in scalar context (its last element); a small arm in `Builder/Containers.pm`, not a wire matter.
- **sg1**: SAME at base already.
- **sr1** (`for my $c ("a".."c")`): the producer's own refusal, by name ("a foreach over a range of strings (perl's magic increment) is not yet lowered"). A feature, not a debt.

## 8. What stages 2 and 3 should know

1. **V9 is not zero on chalk's lib.** One fork is left: `Chalk::Bootstrap::Perl::Actions::SubroutineDefinition` (an elsif arm inside a foreach, whose inner if builds control while the arm got none; Proj#134 feeds both the join Region and the inner If). Six reductions did not reproduce it. Stage 3's "V9: 0 from stage 3" needs it fixed or the graph refused. chalk and the deparser both refuse a forked graph by name, so it is loud today.
2. **V5's real size is 291 on chalk's lib, not 228** (section 3), 74 distinct sites.
3. **`control_in` is not in a node's content hash, and that bites data nodes that are `make`d and then pinned.** `$st->{i}++` in two arms was one node. Stage 3 puts `mem_in` in the hash, which does not help here: both arms read at the same memory. Either a pinned data node is never hash-consed (`make_unique` where `_pin` follows), or `_pin` refuses a node that is already pinned elsewhere. The second is a three-line guard and would have caught this at build time.
4. **The ratchet's chalk rows name a chalk commit** (`# chalk at 45a1b8d5`). Stage 2 is chalk-only and changes chalk's lib in every commit, so each stage-2 gate run needs the rows re-counted (15 minutes cold) and the line moved, or `tools/gates.sh` reports MISS. Consider holding chalk's rows to "no rise" at any chalk commit instead; that is a decision about the ratchet, not made here.
5. **`#graphs` is held now.** A refusal added to the producer lowers it and fails the ratchet; that is intended (it is how a wrong refusal was caught in this stage). A stage that refuses on purpose lowers the row with its reason.
6. **The census pin is still 8c512c2e** (`tools/corpus-llvm-roundtrip.pl`). `tools/gates.sh` reads chalk at the head it is given, so the gates do not depend on the pin; move the pin to chalk's merge commit when `v2-s01` is merged.
7. **Stage 6's three subs** (section 5): `regex_split` and `_repair_stale_merge` are where the flag and `is_memory` differ in chalk's lib. Four probe Phis differ too (cells).
8. **The corpus ir blocks are stale already** (section 6): 683 of 689.
9. **Q7 is the journal; Q6's scan needs two more rules** (section 4). The scan and the cycle walk are on branch `v2-s01-measure`.
10. **chalk does not lower a hash made of a call's list** (`my %h = f()`: "a {...} of an odd list"; with its count: "a call used both as a list and as a scalar"). The stage-1 wire is right and counted; the refusal is T2's.


## 9. After stage 3

Heads: producer `v2-s3` (commits 1a004ac to 9307e25 on 148d296), chalk 45a1b8d5 (unchanged). Wire v1 is the default and is, byte for byte, what 315dd03 (the commit before the v2 work) wrote: every probe, the corpus and chalk's 219 modules, compared graph by graph under one hash seed (t/wire-v2-downgrades-to-v1.t). chalk's Target/LLVM/Lower.pm is the one input the producer is not deterministic on (Builder::read_as_a_truth's shape and Builder::go_round's refusal flip from run to run, under either commit).

The v2 rules (wire=2), per set:

| rule | corpus2 | probes2 | chalk2 |
|---|---|---|---|
| `#wires` / `#graphs` | 431 / 1082 | 486 / 693 | 219 / 24521 |
| V1 mem-in-not-version | 0 | 0 | 0 |
| V2 version-off-chain | 14 (13 MakeCell, 1 builtin version left unpinned) | 34 (MakeCell) | 642 (MakeCell) |
| V3 write-unreachable | 0 | 0 | 7 |
| V4 control-sink | 0 | 0 | 0 |
| V5 memory-order-disagrees | 17 | 31 | 518 |
| V7 record | 0 | 5 | 6 |
| V8 phi:memory-as-value | 0 | 0 | 25 |
| V8 phi-arity, :eval-join | 1, 32 | 3, 25 | 0, 40 |
| V9 control-fork | 0 | 0 | 0 |
| V6 read-unversioned (all classes) | 89 | 28 | 4325 |

v1's chalk `control-fork` is 0 (it was 1); every other v1 row is unchanged.

`tools/gates.sh` at 63397a0 (the stage's last code commit; 9307e25 after it moved the downgrade proof into the ratchet gate and touched no code):

```
producer-suite  PASS  748 files, 0 failing [22m30s]
chalk-suite     917 files, 1 failing: t/bootstrap/gates-script.t (the seventh gate the run's gates.sh listed; 9307e25 folds it into the ratchet, and the file passes there)
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched
probes          PASS  LOUD=2 REFUSED=112 SAME=361; WRONG 0, SAME lost 0, changed 0
ratchet         PASS  prove exit 0; chalk's lib compared; rows that fell: 0 (wire 1 and wire 2)
downgrade       PASS  t/wire-v2-downgrades-to-v1.t, SON_DOWNGRADE_FULL with chalk's lib, at 9307e25: 0 wires differ
```

What stages 4 and 5 should know:

1. **FIXED in stage 4** (section 10). **MakeCell is a version made off the control chain** (V2: every chalk2 violation, 13 of 14 corpus2, all 34 probes2; most of V5). `_place`-ing it is one line and breaks the deparser's closure round trips (t/wire-a-write-to-a-captured-lexical-goes-through-its-cell.t, 50 cases): the deparser (stage 4's adapter, or before it) and chalk must accept a pinned MakeCell first. Then V2 and most of V5 fall.
2. **A sub's exits merge their memory in a Phi only v2 writes** (stage 4 marks it: `fields.exits`) (`v2_only`): chalk reading v2 meets a memory Phi at a function-exit Region, with predecessors, named only by the Return's `mem_in`.
3. **`record` is derived by the writer** (an Assign on neither chain). V7's 5 + 6 are `($p, my $q) = LIST` with a package target: the store is a separate EntryWrite and the Assign floats (v1's `write-floating`).
4. **EXPLAINED in stage 4** (section 10). **phi:memory-as-value 25 and write-unreachable 7, chalk's lib only**, are new findings of the v2 rules and unexplained.
5. **`v1_inputs`** is how the walker still asks its questions; `%MEM_MIN_INPUTS` stays in SoN::Deparse (stage 4's `as_v1` can take it from there or put `mem_in` back by `mem_operand`'s rule, which the v1 writer uses).
6. **The producer is not deterministic on chalk's Target/LLVM/Lower.pm** (two graph shapes, two refusals, run to run). The downgrade proof sets one hash seed; the ratchet's chalk rows may move by it.
7. **An elsif that is a sub's last statement, with its only store in a nested if's true arm, still forks** (none in the three sets): the value short-circuit handler does not ask the field-store question, and asking it there refused chalk graphs.

## 10. After stage 4

Heads: producer `v2-s4` (c44ad95 to 999c490 on 7d5d8f2), chalk `v2-s4` 1eaafd8a (one commit on eef945c6: T2 walks past a MakeCell on the chain).

`tools/gates.sh` at producer 353560d, chalk 1eaafd8a:

```
producer-suite  PASS  757 files, 0 failing [10m17s]
chalk-suite     PASS  919 files, 0 failing [77m50s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [2m41s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [5m16s]
probes          PASS  LOUD=2 REFUSED=112 SAME=361; WRONG 0, SAME lost 0, changed 0 [1m50s]
ratchet         PASS  prove exit 0; chalk's lib compared; rows that fell: 0; new graphs: 0, 0 of them with violations [59m38s]
                PASS  (downgrade proof) prove exit 0; no comparison [44m16s]
```

("no comparison" is how the summary prints a passing proof: the test prints its count only when it fails; it passes only on `0 of N wires differ` with N > 0, chalk's lib included, `Earley::_force` allowed.)

What changed, in one line each (notes in `docs/memory`):

- **Stage 4.** `SoN::Deparse` reads v2 through `SoN::Wire::as_v1` (`the-deparser-reads-v2-through-as-v1.md`). Over corpus and probes every v2 wire renders as its v1 wire does (up to names made from node ids) or prints the same. The exit memory Phi is marked on v2 (`fields.exits`).
- **Known issue 1, fixed.** MakeCell is `_place`d; v1 is unchanged (its writer and `as_v1` leave the pin out, and v1's node order is kept by when each consumer edge was made); chalk T2 walks past it (`a-cell-is-a-version-made-where-it-stands.md`).
- **Known issue 4, explained.** `phi:memory-as-value` 25 was the copy 77c664b fixed (0 at the merge). `write-unreachable` 7 was one graph, `Earley::_force`: an endless loop in an else arm lost the if's join, a silent wrong answer, fixed (`an-endless-loop-in-an-arm-lost-the-join.md`). It changes v1 for that graph: the downgrade proof lists it (`t/data/wire-v1-changed-on-purpose.tsv`).
- **L8 (forward memory references).** The writer has listed a node's `mem_in` before it since stage 3: 0 forward references on corpus2, probes2 and chalk2. `t/wire-v2-a-nodes-memory-comes-before-it.t` holds it (it names ten when the rule is taken out).
- **A flake at the base.** `t/from-optree-match-subject.t` failed about 3 runs in 100: the package-write scan knew a CV by its address and a freed one's was reused (`a-freed-cvs-address-is-another-cvs.md`).

The v2 rules, stage 3 -> stage 4:

| rule | corpus2 | probes2 | chalk2 |
|---|---|---|---|
| V2 version-off-chain | 14 -> 1 | 34 -> 0 | 646 -> 0 |
| V3 write-unreachable | 0 | 0 | 7 -> 0 |
| V5 memory-order-disagrees | 17 -> 7 | 31 -> 4 | 522 -> 290 |
| V8 phi:memory-as-value | 0 | 0 | 0 (25 at stage 3, 0 since 77c664b) |

corpus2's one V2 left is a builtin version left unpinned (stage 3's note).

The census on wire 2 (chalk 1eaafd8a, report only): ROUNDTRIP 412, DIFFERS 0, LLI_FAIL 0, GAP 19, unchanged from the integration. Of the 14 cases v1 round-trips and v2 does not, none is cured; all are T2's "out of its slices":

- 7, "a reference to an element at an index not a constant": 073 123 188 195 217 232 233;
- 6, "a variable that is not a `my` scalar kept here (PadAccess ... not-location)": 013 316 317 318 319 346;
- 1, "a bless of one argument": 027.

Stage 5 owns these.

## 11. After stage 5

Heads: producer `v2-s5` (315512d to the commit that adds this section, on 8d63628), chalk `v2-s5` (2c8f1a58 to its last, on 1eaafd8a).

**The 14 cases the wire-2 census lost** were chalk's, two causes (docs/memory/a-memory-edge-is-not-a-version.md): an Impl class (%SIG's, %INC's, a stash's) was compiled at wire 1 into a v2 program's wire, and `Ref::taken_where_it_stands` asked for a memory edge (every pinned read has one on v2) where it meant a version (`mem_out`).

**The loader invariant** (`Chalk::IR::Serialize::WireInvariant`) holds every graph of a B::SoN v2 wire to L1-L6; a v1 wire (upgraded) and a graph chalk wrote itself (no `dowarn`) are not held. L5 is V2's (a non-record Assign and a sub call name memory) until stage 6; L6 lets a trap's value Phi keep its extra input until stage 8 (docs/memory/the-loader-holds-v2-to-its-invariant.md).

**chalk's `t/bootstrap/ir/wire-verify.t`** runs SoN::Verify over chalk's lib (219 wires) and its 477 probes at wire 2: no V1-V5 or V7 violation except three held by name (probe pl13; DynaLoader::bootstrap and ::bootstrap_inherit, a floating Assign of `@isa` not yet traced); V6, V8, V9 held to `t/data/wire-verify-v2-baseline.tsv`.

The rows the stage had to resolve, before -> after (wire 2):

| rule | corpus2 | probes2 | chalk2 (graphs) |
|---|---|---|---|
| V2 version-off-chain | 1 -> 0 (398, an :lvalue call left the memory version off the chain) | 0 | 0 |
| V5 memory-order-disagrees | 7 -> 0 | 4 -> 0 | 290 -> 0 |
| V7 record | 0 | 5 -> 1 (pl13, held) | 6 -> 2 (DynaLoader, held) |
| phi-arity | 1 | 3 -> 4 (al1: a one-pass loop's new memory Phi, like al2's; refused by name) | 0 |

V5 was mostly the verifier (a loop body follows its test's last version on a wire without the `loop` profile); the rest were producer faults: a foreach body writing its alias and a while body storing after an arm got no header memory Phi before the walk (al16, lp28, 205; corpus 140's graph changed with it, and chalk's intervals oracle rows for it were renamed). Also fixed: an append's result read with its store as an input on v2 (probe ev10, refused on wire 2 only).

Found, not fixed (not v2's): `print f(1), $g, f(0), $g` with `f` storing `$g` prints `1122` for perl's `1222` on both wires (print's arguments are aliases).

`tools/gates.sh` at producer 2ddf303, chalk d5f06c06 (wire 1, B::SoN's default):

```
producer-suite  PASS  763 files, 0 failing [10m43s]
chalk-suite     PASS  923 files, 0 failing [88m19s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [2m57s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [5m31s]
probes          PASS  LOUD=2 REFUSED=112 SAME=361; WRONG 0, SAME lost 0, changed 0 [1m57s]
ratchet         PASS  prove exit 0; chalk's lib compared; rows that fell: 48; new graphs: 38, 3 of them with violations [66m45s]
                PASS  (downgrade proof) prove exit 0; no comparison [49m10s]
```

With `SON_WIRE=2` exported (`--only census,corpus-gate,probes`, producer lib as at 2ddf303, chalk d5f06c06):

```
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [4m38s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [6m39s]
probes          PASS  LOUD=2 REFUSED=107 SAME=366; WRONG 0, SAME lost 0, changed 5 [2m09s]
```

(The five changed on wire 2 are cl5, cl6, cl13, cl19, cl20, REFUSED -> SAME: the cell pinned on the chain. The downgrade proof's v1 changes on purpose are listed in t/data/wire-v1-changed-on-purpose.tsv, now scoped to a wire where the graph is a program's own.)

## 12. After stage 6

Heads: producer `v2-s6` (8fdb3e8 to the commit that adds this section, on a752617), chalk `v2-s6` (a1e31bc2 to 645a0d4a, on 56bc0efe). B::SoN writes wire v2 only; chalk reads v2 only (docs/memory/wire-v1-is-gone.md).

`tools/gates.sh` at producer 0b61e281, chalk 645a0d4a (the chalk suite and the census ran at 5284360b; 645a0d4a changes only the probes' BASELINE.tsv, and the probe gate ran again at it):

```
producer-suite  PASS  763 files, 0 failing [20m23s]
chalk-suite     PASS  924 files, 0 failing [110m36s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [2m57s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [10m48s]
probes          PASS  LOUD=2 REFUSED=115 SAME=390; WRONG 0, SAME lost 0, changed 0 [4m29s]
ratchet         PASS  prove exit 0; chalk's lib compared; rows that fell: 0; new graphs: 0, 0 of them with violations [67m30s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [5m16s]
```

The ratchet gate's second line is new: the downgrade proof (v1 writer against the commit before stage 3) had nothing left to compare, and the deparser's round trip through `SoN::Wire::as_v1` holds what is left of v1 (430, as a752617 measured it with v1 direct).

Probes against the stage's start (56bc0efe): cl5, cl6, cl13, cl19, cl20 REFUSED -> SAME (the cell on the chain, wire 2 the default); al1, al2, ef31 refused by another name; fk7 REFUSED by another name (`a my scalar two list assignments bind one after the other`).

Corpus and probe verifier rows (one wire now: corpus, probes): unchanged from corpus2 and probes2 but for the probes' denominators (519 wires, ag1-ag33 added since). chalk's lib re-recorded per graph at 5284360b; one graph rose against 1eaafd8a (Chalk::Regex::Graph::stmt, read-unversioned:through-ref 0 -> 1, a hash-consed read and place in code stage 6 wrote).

What stage 7 and later should know:

1. **A `my` scalar a list assign rebinds after a read is read by name** (one node, no memory version): T2 refuses two list assigns of one scalar where control reaches one from the other. It refuses fk7, which is right only because `$x` is read after the second alone. The fix is the producer's: those reads at a version (V6).
2. **`_flattened_package_aggregates` stays** in chalk's WireCheck: off, nv1, nv4, nv5, nv7, nv8, lo14 are WRONG. Stage 7's `package` row removes the need.
3. **Kept, by kind:** chalk's store classes (Assign, EntryWrite, CellWrite, Delete, ElemRestore) answer `is_memory_version` 1 by class, not by `mem_out` (chalk's own Earley-built graphs set no `mem_out`); WireCheck's `_follows_memory` is a kind list (Return, Unwind, Assign, sub calls). Both could read the wire's flags once nothing builds a graph without them.
4. **`wire=2` is accepted** by B::SoN (it changes nothing); `SON_WIRE` still passes through the harnesses. Any other `wire=` is refused by name.
5. **The :lvalue call of corpus 398** is the one sub call L5 lets off both chains: the place its Assign stores through.
6. **Stage 7's text names `t/wire-verify.t`** for the V6 hard rule; that file (v1's rules) is gone, its v2 cases are in `t/wire-verify-v2.t`, and the counts are `t/wire-verify-ratchet.t`'s.

## 13. After stage 7

Heads: producer `v2-s7` (ad8080f to the commit that adds this section, on bfa4d40), chalk `v2-s7` (f95685ee to the probe-baseline commit after acac1715, on 22685dbf). Lessons: docs/memory/every-read-names-a-version.md.

V6 (`read-unversioned:C`) per class, before (stage 6's rows; chalk's lib the most one wire counts, summed over its graphs at 22685dbf with bfa4d40's producer) and after:

| class | corpus | probes | chalk lib (per-graph sum) |
|---|---|---|---|
| field | 5 -> 0 | 0 -> 0 | 309 -> 0 |
| my-aggregate | 24 -> 0 | 2 -> 0 | 96 -> 0 |
| through-ref | 35 -> 0 | 1 -> 0 | 50 -> 0 |
| package | 7 -> 0 | 4 -> 0 | 3 -> 0 |
| package-aggregate-literal | 0 -> 0 | 5 -> 0 | 1 -> 0 |
| external | 14 -> 0 | 14 -> 0 | 33 -> 0 |
| args | 0 -> 0 | 1 -> 0 | 1 -> 0 |
| cell | 0 -> 0 | 1 -> 0 | 0 -> 0 |

(chalk's lib by every violation listed, not per graph, at base: field 3813, my-aggregate 369, through-ref 215, external 87, package 5, args 3, package-aggregate-literal 1.) The probes' denominators are 542 wires and 799 graphs (ag34-ag43 and rv1-rv13 added). V6 is hard now: `t/wire-verify-ratchet.t` (corpus, probes, chalk's lib) and chalk's `t/bootstrap/ir/wire-verify.t` fail on any; the rows are deleted from both baselines and from `t/data/wire-verify-chalk-graphs.tsv`.

Probes (chalk, against 22685dbf): fk7, lo14, nv1, nv4, nv5, nv7, nv8 REFUSED -> SAME; rv1-rv15 new (rv8, rv9, rv10, rv12 WRONG at base, rv14 WRONG through the first form of chalk's copy; rv4 REFUSED by name). LOUD 2, REFUSED 105, SAME 426, WRONG 0. WireCheck's W10 is deleted (with it off the probes were the same).

What later stages should know:

1. **A read of an aggregate at a version is a copy** in chalk (`is_versioned_read`, the EntryDef and FieldAccess branches of `_value`): reads_before makes it before the next store.
2. **V6 asks "is the value used, and not as a place"**: a dead consumer, a record's targets, a list slice, pos()'s operand and the items of an alias list (foreach/map/grep, a Phi or `?:` of an aggregate's bindings) are not reads. A new consumer kind that only holds places belongs in `$is_place_use`.
3. **Not done here:** a scalar-context list assign of a builtin's list or an aggregate (`while (my ($k, $v) = each %h)`) is still the Assign; `rand` is an external read, not a write (Q13); `my $a = rand();` is an INTERNAL ERROR in B::SoN at base too; `if (C) { @l = @x }` with the copy alone in the arm forks control (V9; chalk refuses it by name).

The gates at the stage's last commits:

`tools/gates.sh` at producer b548d6f4, chalk acac1715 (the chalk commit after it changes only the probes' BASELINE.tsv: rv14, rv15 SAME, as the probe gate measured):

```
producer-suite  PASS  772 files, 0 failing [20m39s]
chalk-suite     PASS  925 files, 0 failing [110m06s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [3m54s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [10m17s]
probes          PASS  LOUD=2 REFUSED=105 SAME=426; WRONG 0, SAME lost 0, changed 0 [3m10s]
ratchet         PASS  prove exit 0; chalk's lib compared; rows that fell: 0; new graphs: 12, 0 of them with violations [66m47s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [5m51s]
```

The first gate run (5d1f110 / 81f674dc) found three things fixed since: chalk's copy of a versioned `my` aggregate took the variable's storage, not what `my ($c, @x) = @_` bound (t2-slurpy-args.t: " 1 2" for "1 2 9 1 2"); as_v1 handed an external read memory v1 never had (corpus 006 REFUSED by the deparser, 430 -> 429); two chalk tests expected refusals stage 7 lifts, and the intervals oracle named 8 Counts by their old memory input.

## 14. After stage 8

Heads: producer `v2-s8` (fd3b147 to d326a6f, rebased on stage 7's 0497211), chalk `v2-s8` (fab4a30f to 99ef3cc0, on 22dcedc4). The eval exceptional edge: profile `["mem","eval"]` (docs/memory/an-eval-s-die-has-its-way-out.md).

`tools/gates.sh` at producer d326a6f, chalk 99ef3cc0:

```
producer-suite  PASS  775 files, 0 failing [10m29s]
chalk-suite     PASS  927 files, 0 failing [74m12s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [1m53s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [5m19s]
probes          PASS  LOUD=2 REFUSED=98 SAME=433; WRONG 0, SAME lost 0, changed 0 [1m31s]
ratchet         PASS  prove exit 0; chalk's lib compared; rows that fell: 0; new graphs: 30, 0 of them with violations [32m14s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [3m04s]
```

Verifier: `phi-arity:eval-join` is no class (corpus 32, probes 25, chalk's lib 40 -> 0, rows deleted); corpus `phi-arity` 1 -> 0 (the run-time string eval's trap). probes `phi-arity` stays 4: al1 and al2 (one-pass loops, stage 9), held by name in chalk's `wire-verify.t`, where phi-arity is now hard -- with V6 hard since stage 7, chalk's `t/data/wire-verify-v2-baseline.tsv` holds no row. The 30 "new graphs" of the ratchet are chalk graphs whose only recorded entry was an eval-join or read-unversioned count (rows emptied; none has a violation).

Probes (against 22dcedc4): lo2, lo16, ex1, ex2, ex3, ex4, ev6 REFUSED -> SAME. Two silent wrong answers found that no probe had: a call that dies under a live `local` in a sub with no eval (`sub t { local $g = 2; u() } eval { t() }`), refused by name (WireCheck `_calls_a_local_dies_through`, the plan's Q9); a list-context eval whose body always dies (`my @r = eval { die "x\n" }`), refused by name (T2, a list eval typed a scalar). The interval oracle re-recorded (compared modulo ids: one key moved, own:edges' 7 allowed losses kept).

What later stages should know:

1. **Q9 is open**: a call dying under a live `local` in a sub with no eval needs a rethrow pad (Exc, restores, Unwind `rethrow`); refused by name until then, only where the callee may die.
2. **V10 (`exc`) is not written**; L7 is chalk's.
3. **`$@ = ""` is not stored at a `return` from an eval** (T2 refuses an eval whose body returns).
4. **The eval's value stays a Phi at its join even of one way in** (list context reads it); memory Phis of one input are not emitted.

## 15. After stage 9

### 9a: the `loop` profile (the gated 9a point)

Heads: producer `v2-s9` 006b485 (on 1e190aa), chalk `v2-s9` d99ac083, d4db080e, 89317de9 (on 99ef3cc0). A Loop is [entry, back], its test an If; profile `["mem","eval","loop"]` (docs/memory/a-loop-goes-round-by-an-edge.md).

`tools/gates.sh` at producer 006b485, chalk 89317de9 (run from a worktree of 006b485; the first run, at chalk d4db080e, failed three chalk tests that 89317de9 fixes -- T1's intervals and `Ref::is_alias_ref` read the old shape; the intervals oracle re-recorded, equal modulo ids):

```
producer-suite  PASS  776 files, 0 failing [13m14s]
chalk-suite     PASS  928 files, 0 failing [82m22s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [4m06s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [6m42s]
probes          PASS  LOUD=2 REFUSED=98 SAME=433; WRONG 0, SAME lost 0, changed 0 [2m54s]
ratchet         PASS  prove exit 0; chalk's lib compared; rows that fell: 0; new graphs: 94, 0 of them with violations [39m53s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [3m27s]
```

Verifier: probes `phi-arity` 4 -> 0 (al1, al2: the foreach write-back to a scalar source returned before the loop's back edges and exit); `loop` (V11) new, 0 everywhere. al1 and al2 stay REFUSED, now by T2's `out of its slices (PadAccess)` (the list's PadAccess), no longer held by name in chalk's wire-verify.t. The deparser reads the new shape through `as_v1` (430 held).

### 9b: Braun's construction

Heads: producer `v2-s9` fde4976 (Braun), 15cc7f9 (scouts deleted), f743cdb (the proof in gates.sh), 5305f64 (memory), 5d55bde, 6fdb254; chalk b7923c82, 22037842, daaf243f (probes baseline: al1, al2 refused by T2 by name; ev8 SAME). Depth-14 nest: under 2 s; each body walked once (docs/memory/a-loop-is-walked-once.md).

`tools/gates.sh` at producer 6fdb254, chalk daaf243f:

```
producer-suite  PASS  780 files, 0 failing [10m13s]
chalk-suite     PASS  928 files, 0 failing [81m25s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [1m48s]
corpus-gate     PASS  gate-green 223 (>= 222), prove exit 0, paad/worklist.json untouched [5m16s]
probes          PASS  LOUD=2 REFUSED=97 SAME=434; WRONG 0, SAME lost 0, changed 0 [1m32s]
ratchet         PASS  prove exit 0; chalk's lib compared; rows that fell: 0; new graphs: 94, 0 of them with violations [29m24s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [3m01s]
                MISS  (wire-braun-proof against 006b485) chalk DIFFERS 17; chalk SAME 193; chalk SAME-BUT-STAMPS 11; corpus SAME 427; corpus SAME-BUT-STAMPS 4; probes GAINED 1; probes SAME 541; probes SAME-BUT-STAMPS 2 [47m13s]
```

The Braun proof holds over the corpus and the probes (SAME up to the listed stamps; GAINED: ev8) and MISSES over chalk's lib: 17 rows, 10 graphs. Read node by node, they are the 9a wire's scout artifacts, not Braun's: a pinned `PostfixDeref '@'` on one side, from `%MUTATED_LITERALS` node-id collisions that moved with the counters (docs/memory/pending-bug-mutated-literals-keyed-by-node-id.md) or a scout's `mutated_aggregate` mark (Builder::_common_memo); and check_nodes' `@controls = ... if ...` as a TernaryExpr where 9a built an If (no Phi for a `my @a`). No WRONG anywhere (probes, census, the deparser's round trip, chalk's suite).

The Braun proof is retired from `tools/gates.sh` in stage 10. It was a one-time check of the 9b producer against the 9a producer's wire (006b485), and this section records its result. Its 17 chalk-lib rows were judged leftovers of the 9a wire, not departures of Braun's: each is a place where the 9a scouts made the wire less precise (a `PostfixDeref '@'` pinned by a `%MUTATED_LITERALS` node-id collision or a scout's `mutated_aggregate` mark, and check_nodes' `@controls = ... if ...` built as an If with no Phi for a `my @a`), the 9b wire is the more precise of the two, and no gate found a wrong answer on either side. What the proof was for -- that Braun's walk builds the 9a graph up to trivial Phis -- is shown on the corpus and the probes; chalk's lib needs no proof against a wire that was the imprecise one. `tools/wire-braun-proof.pl` stays in `tools/` as the script that made this record.

## 16. After stage 10

Heads: producer `v2-s10` 4a3019c (no profile; every rule hard, held by name; Braun proof retired), c17f570 (census pin); chalk `v2-s10` 1cd20654 (loader refuses `profile`; L1-L9 on every wire; wire-verify.t all hard), 287e5da1 (chalk's grammar refuses an interpolated postfix deref: the refusal message joins). Held by name: probes pl13 `main::sw`, chalk's lib DynaLoader::bootstrap and bootstrap_inherit (V7 `record`); LocalAlias out of V2's store kinds (SoN::Verify, with its reason). The verifier over chalk's lib: 221 wires in the gated run, the two held its only violations (25158 graphs in a run before it, on the lib bar 287e5da1's one line).

`tools/gates.sh` at producer c17f570, chalk 287e5da1 (a first run at 4a3019c / 1cd20654 missed one chalk test, t/grammar-conformance.t, on the refusal's interpolated `->@*`; everything else passed there):

```
producer-suite  PASS  779 files, 0 failing [10m02s]
chalk-suite     PASS  929 files, 0 failing [70m08s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [1m38s]
corpus-gate     PASS  gate-green 223 (>= 222), prove exit 0, paad/worklist.json untouched [5m01s]
probes          PASS  LOUD=2 REFUSED=97 SAME=434; WRONG 0, SAME lost 0, changed 0 [1m22s]
ratchet         PASS  prove exit 0; chalk's lib compared; held by name: 3 [28m40s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [2m47s]
```

## 17. After the goal audit's fixes (branch `audit-fix`)

Heads: producer `audit-fix` bfdfe43 (from 2d67c84), chalk `audit-fix` 98b69cb5 (from 287e5da1). What the independent audit (docs/research/2026-11-22-memory-model-goal-audit.md) found and this branch closed: a `die` ending a loop body is on the wire (risk 1); an eval that ends puts its `local`s back (risk 2); the verifier rejects 11 of the audit's 12 hand-broken wires rebuilt from fresh wires (`t/wire-verify-rejects-hand-broken-wires.t`; M5, a read naming an older version, is another program, not a broken wire) -- on the audit's own saved wires 10 of 12, M9 there being indistinguishable from a program with no `local` (risk 3); T2 makes every read at a node's `mem_in` before that node, outside an eval's body (risk 4); a read through an element vivifies it (W9), a foreach's alias of `$_` is a memory version (LocalAlias in V2's store kinds), no builtin is pure by default (EffectTable: `log`/`sqrt` pinned, an unknown name refused). Refused by name by class: W8 (any bless beside a DESTROY or AUTOLOAD), W10 (a shared `my` aggregate flattened beside a sub call). The DynaLoader hold is traced (compiled before peep is off; `aelemfast` refused) and gone. Held by name: probes pl13 and a/aun17f (a list assign that is its sub's value: a design), a/aun6 (a symbolic-ref compound assign reads at no version: open), a/aun5d (a division after `next unless` floats: open).

The audit's 288 probes are `probes/a/au*` here and `t/data/audit-probes/au*` in chalk: at the base LOUD 2, REFUSED 55, SAME 176, WRONG 55; at these heads LOUD 2, REFUSED 68, SAME 218, WRONG 0 (`probes/a/_run1.log`, `_run2.log`). Of the 533 before them: fl11 REFUSED -> SAME, no other verdict changed. The corpus gate's 222 is one under section 16's 223: R8 (nested array ref deref) keeps its behaviour and loses its recorded shape, the read now going through the vivifying `DefinedOr`. chalk's t1 intervals oracle re-recorded for five cases whose node ids the wire changes moved (cbe45923).

`tools/gates.sh` at producer bfdfe43, chalk 98b69cb5:

```
producer-suite  PASS  786 files, 0 failing [10m23s]
chalk-suite     PASS  933 files, 0 failing [70m46s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [1m43s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [5m06s]
probes          PASS  LOUD=4 REFUSED=164 SAME=653; WRONG 0, SAME lost 0, changed 1 [2m15s]
ratchet         PASS  prove exit 0; chalk's lib compared; held by name: 4 [31m46s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [3m21s]
```
