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

Section 19 re-runs the proof with `%MUTATED_LITERALS` keyed by the node on both sides and accounts for each row: that judgment held for 8 of the 17 rows (the collision, two 9a scout marks); the other 9 were Braun's scan (three departures, fixed there), and behind them was a silent wrong answer of Braun's, fixed too.

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

## 18. The goal's last gaps closed (branch `goal-close`)

Heads: producer `goal-close` 78f9182 (from 9e40d47), chalk `goal-close` 48c36bd6 (from c959f983). Probes pl13 and a/aun17f (a list assignment to package scalars that is its sub's value, held as V7 `record`) are SAME: the aassign handler marks the one made in the caller's context, by position, into package scalars, and the sub's Return carries its two readings -- the targets read after the stores, the right side's count made before them -- the `[list, scalar]` shape `return @a` already had and chalk T2 already read (f7ebc16, chalk 48c36bd6). `_list_count` counts an aggregate by its sigil (`sub f { my $n = () = @x; $n }` gave 1 for 3: a silent wrong answer at the base). The chalk-suite gate misses unless chalk's `t/bootstrap/ir/wire-verify.t` ran tests (audit risk 10; 78f9182: it ran 3 here). The probe verdict compares the exit status, not only success (audit risk 11; chalk c4033db6): every probe re-run, none changed by it. Held by name: a/aun6 and a/aun5d (open, as in section 17).

`tools/gates.sh` at producer 78f9182, chalk 48c36bd6:

```
producer-suite  PASS  787 files, 0 failing [10m44s]
chalk-suite     PASS  934 files, 0 failing [95m55s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [2m11s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [5m28s]
probes          PASS  LOUD=4 REFUSED=162 SAME=655; WRONG 0, SAME lost 0, changed 0 [2m45s]
ratchet         PASS  prove exit 0; chalk's lib compared; held by name: 2 [33m31s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [8m07s]
```

## 19. The Braun proof re-run, with node identity fixed (branch `id-collide`)

Section 15 put the 17 chalk-lib rows of stage 9b's proof down to the 9a wire's leftovers, without a row-by-row account. This section is that account. First the bug that polluted both sides was fixed: `%MUTATED_LITERALS` was keyed by `$node->id`, a per-graph counter, while the table lives for a compilation unit, so one sub's mark fell on another sub's node of the same id (`ArrayLiteral#4` in every sub that builds one fourth). It is keyed by the node now (refaddr => node; holding the node keeps its address from being reused): `t/from-optree-a-mutated-literal-is-marked-in-its-own-sub.t`.

**The comparison.** `tools/wire-braun-proof.pl` (as at 6fdb254), base = throwaway branch `ic-proof-base` (006b485, stage 9a, + the fix: 2d551a6), head = throwaway branch `ic-proof-head` (6fdb254, the end of stage 9b: Braun fde4976, scouts deleted 15cc7f9, 5d55bde, 6fdb254; + the fix: 0d901ec). 6fdb254 rather than fde4976: it is the 9b point section 15's 17 rows came from, so each row maps to one of them; stage 10 and later change the wire on purpose and are left out. Inputs: the corpus, the probes, and chalk's lib at daaf243f (the lib section 15's run read). A file stops at its first differing graph in the proof; every graph of every row was also compared (`--list`, no stop).

**Run 1 (the fix on both sides).** corpus SAME 427, SAME-BUT-STAMPS 4; probes SAME 541, SAME-BUT-STAMPS 2, GAINED 1 (ev8); chalk SAME 193, SAME-BUT-STAMPS 16, DIFFERS 12. Six of section 15's rows go (they were the collision); one row appears (WireCheck.pm, where the collision had pinned the read on both sides alike).

| row (section 15) | graph(s) that differ | cause | kind | evidence |
|---|---|---|---|---|
| StructPromotion.pm, SemanticAction.pm, Grammar/BNF/Actions.pm, NodeFactory.pm | Concat::const_choices, Ref::stores_through | node-id collision in `%MUTATED_LITERALS` | (a) | SAME or SAME-BUT-STAMPS with the fix on both sides (run 1) |
| Impl.pm | JSON::PP::object_to_json | node-id collision | (a) | SAME-BUT-STAMPS in run 1 |
| Builder/Values.pm | Builder::_bit_source_numified | node-id collision | (a) | SAME in run 1 |
| DefinedOrFold.pm, IR/Analysis.pm, Serialize/JSON.pm, LLVM/Lower.pm, LLVM.pm | Analysis::_answer_sub_defined; Builder::_common_memo, full_jump; WireCheck::_unread_derefs; part of _propagate_computed_reprs | Braun's scan took a grep's list (OPf_MOD, for its `$_` alias) for a rebinding: the read in the body was the header Phi, so the in-loop guard of a mutated slot (FromOptree's padav read: `@LOOP_STACK && $MUTATED_SLOTS`) and a mark on the list's node saw no literal; the 9a wire pinned `PostfixDeref '@'` there | (b) fixed | each graph equal once a PostfixDeref '@' over a literal or Phi is taken out of both sides (`norm2.pl`); traced (`padav-read ... lit=Phi` in 9b, `lit=ArrayLiteral ... ml=1` in 9a); gone with the fix |
| the same five, Analysis::_insert_str_coercions, _narrow_unknown_coercions | method Call without `class_name` | `_loop_cycle_ops` went round an enclosing loop (an inner loop's exit goes on round the outer body and back in), so the inner header had a Phi for every slot the outer body writes; `my $factory = ...->new` read through one lost its class | (b) fixed | the only node difference is `class_name`; repro (`$factory` declared in the outer body, called in the inner) loses it at 6fdb254 and keeps it at 006b485; gone with the fix |
| Perl/Target/C.pm, Perl/Target/EmitHelpers.pm | EmitHelpers::_repair_stale_merge | the grep-list Phi again, over a memory-held `@keys`: read as a PostfixDeref of the PadAccess where 9a wrapped it in an ArrayLiteral | (b) fixed | gone with the fix |
| Builder/Args.pm | Args::_collect_positional_arg_reads | the grep-list Phi over `@shifts` (as above); the rest stamps (an Assign Unknown in 9a, Scalar in 9b) | (b) fixed | SAME-BUT-STAMPS with the fix |
| Builder/Control.pm | Builder::_common_memo, full_jump | the grep-list Phi | (b) fixed | gone with the fix |
| (none in section 15: hidden by the collision) | the in-loop read of an array a call is passed later in the body | a SILENT WRONG ANSWER since 9b: the callee may write `$_[0]`, and on the next pass the read before the call flattened the literal as first built: `1,2 1,2` for perl's `1,2 1x,2` (SAME at 006b485; WRONG at 6fdb254 and at 9e40d47). The 9a scouts' walk set the slot's mark (`$ctx->{mutated_aggregate}`, an array passed to a call) before the real walk read it | (b) fixed | found reading `_propagate_computed_reprs`' 9a trace (`@reprs` marked by a scout from `_join_repr(..., @reprs)`); probe through chalk WRONG -> SAME; the Braun header marks the slot now |
| Perl/Actions.pm | Actions::AssignmentExpression | a 9a scout's walk of the rest of the body marked `@names` mutated (`\@names`, two statements on) in the shared `$ctx->{mutated_aggregate}` before the real walk read it at `grep { !defined } @names`; `@names` is a `my` of the pass, so the later reference cannot reach that read | (a) | trace: `MA targ=15 scout=1` before the real walk's `PFD targ=15 ctx=1`; equal once the PostfixDeref is taken out |
| IR/Graph/TypedInvariant.pm | TypedInvariant::check_nodes | `@controls = $controls[0]->@* if ...` an If in 9a, a select (TernaryExpr) in 9b: the arm walker's `_arm_advances_control` asks whether any slot is referenced yet (`$REFERENCED_SLOTS`, filled as the walk lowers `\@x`); the first 9a scout walked the whole body (its `\@violations`) and the second scout and the real walk saw it non-empty. No reference reaches `@controls` | (a) | trace: `ARM-AND ... ac=0 refslots=` (first scout), `ac=1 refslots=6,77` (second scout, real walk); the select is the producer's shape for this statement outside a loop too, and its may-die arm is not run when the guard fails (a scratch probe of the shape, through chalk: SAME) |

The fix of the three (b) rows, test first (`t/loop-header-knows-what-its-own-body-does.t`): `_loop_cycle_ops` keeps only the ops under the loop's own `leaveloop`/`grepwhile`/`mapwhile`; `_may_write_targs` takes a grep's or map's list as aliased, as a foreach's; `_braun_phis` marks, at the header, each array the body passes to a call.

**Run 2 (the fix and the three Braun fixes on the head, 6fdb254 + 0d901ec + 5e4aac0).** corpus SAME 427, SAME-BUT-STAMPS 4; probes SAME 541, SAME-BUT-STAMPS 2, GAINED 1 (ev8); chalk SAME 201, SAME-BUT-STAMPS 18, DIFFERS 2 -- AssignmentExpression and check_nodes, the two (a) rows above, every other graph of both files equal. `_propagate_computed_reprs` is equal too: the header's mark of `@reprs` (passed to `_join_repr` later in the body) is the 9a scout's mark, made where the header is. The SAME-BUT-STAMPS rows are the proof's pass class (a stamp or a line the walk knows from the real binding); there are 18 where section 15 had 11 because files that differed there hid their other graphs behind the first. Nothing unexplained.

**Still open, not Braun's.** A foreach write-back later in a loop body is not seen by a list read earlier in the body on the next pass: `for my $i (1..2) { push @r, join(",", @a); for (@a) { $_ .= "x" } }` prints `1,2 1,2` for perl's `1,2 1x,2x` -- WRONG at 006b485 and 6fdb254 alike, and today (docs/memory/pending-bug-foreach-write-back-later-in-a-loop-body.md).

`tools/gates.sh` at producer `id-collide` 52ebf77 (on 246a7f7), chalk `id-collide` 48c36bd6 (no chalk change):

```
producer-suite  PASS  789 files, 0 failing [10m46s]
chalk-suite     PASS  934 files, 0 failing [78m06s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [1m59s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [5m12s]
probes          PASS  LOUD=4 REFUSED=162 SAME=655; WRONG 0, SAME lost 0, changed 0 [2m24s]
ratchet         PASS  prove exit 0; chalk's lib compared; held by name: 2 [32m27s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [3m12s]
```

## 20. A loop body writing an aggregate after reading it (branch `loop-writeback`)

Heads: producer `loop-writeback` 732eec4 (from d142906: cc4e0db, 2430ead; probes fd3eb53, 732eec4), chalk `loop-writeback` a8057fb6 (from 48c36bd6: probes and BASELINE.tsv fff90e52, oracle a8057fb6). Two silent wrong answers, both at d142906, closed as classes; their probes are `docs/research/son-ir-audit-2026-11-19/probes/l/lw1-lw96` (copied to chalk's `t/data/audit-probes`), `_run1.log` at d142906, `_run2.log` at 732eec4.

**A read early in a loop body flattened a literal the body wrote later** (the pending note of section 19). The kinds of write probed (lw1-lw62): a foreach alias, direct, named, through a callee's `$_` or `$_[0]`; an element store, push, pop, shift, unshift, splice, delete, `$#a`; slices; `local`; list assignment; references written through; map and grep writing `$_`; sort and reverse in place; nested loops; and the read as a join, `"@a"`, a copy, an element, a count, a return. WRONG at d142906: the foreach alias kinds (lw1-6, lw9), a slice store (lw23), map/grep `$_` (lw39-40), nested loops (lw44, 47, 48, 57), other read shapes (lw49, 54-56, 58, 59, 61). The fix is the walk's own mark, checked at sealing: each list or void read of a literal in a loop is recorded in every enclosing loop frame; a literal bound before the loop that the walk has since marked is learned (`$hint->{mutated}`), the sub walked again, and `_braun_phis` marks the slot (cc4e0db; t/loop-header-marks-an-aggregate-its-body-writes-later.t). An op scan of the kinds was not the fix: `$e .= "x"` has no padsv op (TARGMY), `$_ .= "x"` no MOD flag.

**A foreach's write-back was lost on a pass left early**, found probing beside the first. The alias write was stored at the pass end: `last if`, a `last` in an arm, a return, a conditional `next` or `last` naming an outer loop, and a callee's `$_[0]` write before a `last` all lost it (`1 2` for perl's `1x 2`); a callee reading the array mid-pass saw the element before the write. Decision (the user's): the write is a store to the element where it stands. `StackSim::define` runs the iterator's `%ON_DEFINE` hook, set by the foreach walker for the body walk; the pass's element read is pinned at its top; a demoted iterator is stored after each call passed it; the arm scan counts a hooked write as a store (2430ead; t/loop-a-foreach-alias-write-is-a-store-where-it-stands.t, RED at d142906). Refused by name where the alias read after the write would be the walk's binding and not the element: an element store, a store through a reference or a call whose MOD set may reach the array (`ModSets::array_place`), after an alias write (lw91, 92, 96: WRONG at d142906); a reference to the iterator in a pass that may be left early (lw85). Unconditional `last`, `next LABEL` and `redo` stay refused: their refusals are of the control shape. Four deparse tests that held the stale-read refusal now round trip (the element read is bound at the pass top) or name the new refusal.

Probes lw1-lw96: at d142906 SAME 34, REFUSED 21, WRONG 41; at 732eec4 SAME 71, REFUSED 25, WRONG 0. Every other probe kept its verdict. chalk's integer-interval oracle is keyed by node ids: chalk-found-gaps:160's `C::f` gained the after-call store of its demoted iterator, and its four proofs are renumbered (a8057fb6; the first gate run missed on it, chalk-suite 1 failing). Compile time: no cost seen -- census 1m34s, ratchet 28m26s, the deparser's round trip 2m44s, producer suite 9m41s, against 1m59s, 32m27s, 3m12s and 10m46s in section 19 (the second walk is made only for a loop that learned a slot).

`tools/gates.sh` at producer 732eec4, chalk a8057fb6:

```
producer-suite  PASS  791 files, 0 failing [9m41s]
chalk-suite     PASS  934 files, 0 failing [64m02s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [1m34s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [4m46s]
probes          PASS  LOUD=4 REFUSED=187 SAME=726; WRONG 0, SAME lost 0, changed 0 [2m12s]
ratchet         PASS  prove exit 0; chalk's lib compared; held by name: 2 [28m26s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [2m44s]
```

(The run read the producer at 732eec4 with this section's draft and the notes uncommitted: docs only.)

## 21. The re-audit's wrong answers refused by name (branch `reaudit-refuse`)

Heads: producer `reaudit-refuse` 1f402b9 (from 087e828: 64a110f, ada4761, 470aa28, 5ef9fcf, b30c231, b58d82f, 0010940, 216d190, b184aa8, 67851f2, 4920f1a, 57f9e9e, 1f402b9; docs e128acd, 8b7dea0), chalk `reaudit-refuse` 890c0ff8 (from a8057fb6: 41654fd8, 262b43e5, 9a9bd2dc, probes and BASELINE.tsv 3cc2195a, tests b8061d83, 8f6e3670, 890c0ff8). The re-audit (`docs/research/2026-11-23-memory-model-goal-re-audit.md`) found 68 silent wrong answers in seven classes among its 499 probes (`docs/research/son-ir-audit-2026-11-19/probes/r`, in chalk's `t/data/audit-probes` as `re<name>`), and three programs that died with an error perl never gives. Every one is now refused by name; none was lowered. Classes A and B wait on a design the user holds; the others were refused because refusal is the default.

| class | probes | side | refused as |
|---|---|---|---|
| A: `my %c = %h` binds %c to %h's node | 26 | B::SoN | `a copy of a hash that may then be written` -- either side may be written ($MUTATED_SLOTS, or %$HASH_WRITTEN: a slice store or delete, a call's argument, a foreach or `values` alias, `undef`), a sub shares it, or the target is a package hash (64a110f) |
| B: a fault under a `local`, in a sub with no eval | 16 | chalk WireCheck | `a Divide/Modulo/PostfixDeref that may die under a `local` ($main::g), in a sub with no eval` -- W6 started from sub calls only (41654fd8) |
| C: `finally`, `defer` | 6 | B::SoN | `a `defer` or `finally` block is not yet lowered` (pushdefer, 470aa28) |
| D: `state $n;` with no initialiser | 3 | B::SoN | `a `state` variable with no initialiser, where it can be reached more than once` (ada4761) |
| E: `for my $y ($x)` with $x written in the body | 4 | B::SoN | `a foreach over a scalar variable its body may write` (5ef9fcf) |
| F: grep's block writes `$_`, result read as a list | 4 | B::SoN | `a grep whose block writes $_, read as a list` -- ModSets' stores, or a callee that may store an argument (b58d82f, 0010940, 57f9e9e) |
| G: an operand read by alias, stored by another name | 9 | B::SoN | `a scalar operand is read by alias and a later operand stores it [through a reference]`: a `++$x` operand, a `$$r` store; `an element operand ... stores into its container` for `$a[0]` beside `$r->[0] = ...` (0010940) |

The three invented errors: `C->get` where get is refused (`//=` into a package scalar) died "Can't locate object method": B::SoN now puts the program's own refused subs in the wire's `refused` (the key a followed module's already used), and chalk's loader names the refusal (67851f2). A try whose body begins with a try or an eval shares its eval entry, and T2's `eval_at` kept one of the two: refused in T2 (262b43e5; nested tries that never die printed nothing too). aue1 and rn1 (an INTERNAL ERROR, stack underflow): rand, srand and mkdir pop what their op says, the sixth optional-arity operator (4920f1a; `5 + rand()` was rand(5)); both are now T2 refusals by name. ModSets read a match's OPf_STACKED as an op-assign (a PMOP isa B::BINOP): fixed (b30c231), or the grep rule refused chalk-lib's `grep { $d->isn($_) }`.

Probes: re SAME 339, REFUSED 156, LOUD 4, WRONG 0 (at 087e828 / a8057fb6: SAME 341, REFUSED 83, LOUD 7, WRONG 68). rec02 and rec03 went SAME -> REFUSED: a dereference that may die under a `local` (the wire cannot say it does not). lw40 went SAME -> REFUSED with the grep rule and back (57f9e9e: a result into a `my` array nothing reads). No other probe changed verdict. The harness names a program B::SoN skips in its words (9a9bd2dc): 58 refusals that said "no program graph" or "a direct call with no sub" now name their GAP. The ratchet's probes source took in probes/r at 087e828, and with it a violation: r/a12, `sub z { @a = () }`, whose Return read the package ArrayLiteral its store wrote, at no version. Held by name first (216d190, chalk 8f6e3670), then fixed: the assign's value, where used, is @a read at its store's version (1f402b9), and T2 returns a package array as it does a `my` one (890c0ff8; it refused `sub z { @a }` before). Both holds dropped: two held, as at section 20. Still LOUD, by a run-time refusal: rec14, reh06, req31, req33. Not done: SoN::Verify cannot see class A (the wire names the source's symbol only).

`tools/gates.sh` at producer 1f402b9, chalk 890c0ff8:

```
producer-suite  PASS  801 files, 0 failing [9m34s]
chalk-suite     PASS  937 files, 0 failing [65m44s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [1m38s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [4m37s]
probes          PASS  LOUD=8 REFUSED=343 SAME=1065; WRONG 0, SAME lost 0, changed 0 [3m21s]
ratchet         PASS  prove exit 0; chalk's lib compared; held by name: 2 [29m09s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [2m39s]
```

(The run read the producer at 1f402b9 with this section and the memory note's a12 paragraph uncommitted: docs only. Earlier runs: at chalk 3cc2195a two chalk tests held a refusal whose cause had moved into B::SoN (b8061d83 names both); at b8061d83 chalk's wire-verify.t met r/a12 (then held, now fixed); two runs were killed by container restarts.)

## 22. A copy is a new location; a `local` has a way out (branch `copy-unwind`)

Heads: producer `copy-unwind` f0a62b5 (from ba42f34: plan 28efa37, A daa58bd and ae5675a, B1 286dd2d and 98360e9, V10 6a60088 and f0a62b5), chalk `copy-unwind` 34783892 (from 4ba00e14: probes 7e31e2a3 and bbc309fa, B1 5cc0e7d0, L7 9459e93d, 53fc9f6a, 34783892; BASELINE.tsv 93c01e4c). The two designs of `docs/plans/2026-11-24-copy-and-local-unwind.md`, approved by perigrin, lower the re-audit's classes A and B (section 21), which were refused.

**A, always copy (no wire change).** `my %c = %h` makes a HashLiteral of its own, read from the source where it is made; the elision guarded by `$MUTATED_SLOTS`/`$HASH_WRITTEN` and the GAP `a copy of a hash that may then be written` are gone. A `my` array copied from a literal the list shortcut cannot flatten (a ternary among its elements) was elided the same way -- `my @d = @b; $d[0] = 9` changed @b (cpa33, cpa34, silent wrongs at base) -- and is copied too. Two more silent wrongs of the family, at base: a `my` hash among other pairs floated past a later store (`my %d = (%h, x => 1)`, cpa21), and the padav list shortcut pushed a named literal among an array's inputs, so `"@l"` read %h itself (cpa23, cpa30, cpa31). A `my` aggregate bound to another name's literal is a GAP by name where it is looked up (`a `my` aggregate bound to another's location`), as the name is spelled (%PAD_SYMBOL); it found the array case.

**B1, a rethrow edge (wire change: an Exc outside an eval; Unwind `fields.rethrow`).** Each graph has a sub frame below its eval frames; where no eval of the graph is open, a node that may die while a `local` of the graph is live gets an Exc, the restores, and an Unwind marked rethrow (input the Exc, `mem_in` the last restore). chalk's `after_call` takes it (`rethrow_way`) and returns with the dying flag set; an edge T2 never takes is refused by name. W6 deleted. SoN::Verify V10: a thrower under a live local outside an eval has an edge that puts it back, an Exc outside an eval ends in its own rethrow, a rethrow is of its own edge's Exc (M12-M16, each rule disabled in turn and caught). WireInvariant L7: the edge's shape (the two structural rules, each disabled in turn and caught); that every such point has an edge is not L7's, because the wire cannot tell `local $G = 0` from `my $c = $G; $G = 0; ...; $G = $c` (Test::Chalk::subtest), so only V10 checks it, over the ratchet's wires. An Exc is an eval's by where its edge goes (a die in a sort block inlined in an eval has no `eval_id`).

Probes: 1451 (35 new: cpa01-35), SAME 1145, REFUSED 297, LOUD 9, WRONG 0 (at ba42f34 / 4ba00e14: 1416, SAME 1065, REFUSED 343, LOUD 8, WRONG 0). 48 REFUSED -> SAME: 26 of the 28 class-A rows and 22 of the 24 W6 rows, r/c02 and r/c03 (chalk rec02, rec03) among them. Refused by name still, each the same without the copy or the `local`: ren26 (T2: a list perl may alias passed where a sub writes @_), ren35 (T2: a value stamped List), req32 (T2: a sub returning a list as one value); req35 REFUSED -> LOUD (T2's run-time refusal of a call of undef). cpa05, cpa06 (package to package, T2: a statement EntryWrite) and cpa25 (T2: PadAccess) refused by T2.

`tools/gates.sh` at producer f0a62b5, chalk 34783892:

```
producer-suite  PASS  804 files, 0 failing [9m48s]
chalk-suite     PASS  937 files, 0 failing [70m18s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [1m40s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [4m48s]
probes          PASS  LOUD=9 REFUSED=297 SAME=1145; WRONG 0, SAME lost 0, changed 49 [3m49s]
ratchet         PASS  prove exit 0; chalk's lib compared; held by name: 0 [29m26s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [2m49s]
```

(Earlier runs: gates1 was abandoned when verify-holds merged; gates2 found the guard on arrays and on a re-declared name, and a hand-set control_in (`placement-one-constructor.t`); gates3 found V10/L7 calling a call at a loop's top live past the pass-end restore (lo22), L7's liveness rule refusing every Test::Chalk program, and `list_only` taking a rethrow Exc for a scalar use (c178). The interval oracle needed no re-keying.)

## 23. The final audit's wrong answers lowered or refused by name (branch `final-audit`)

Heads: producer `final-audit` 21457b0 (from 40e86a6: 1dc13d9, 83564dc, ed66c63, 21457b0), chalk `final-audit` add5ce17 (from 93c01e4c: 7a1b43e8 F, 6b7756b2 B, ddb10251 I, bf532dcf, e9407350 loader, b21dda85 probes, add5ce17). The final audit (`docs/research/2026-11-24-memory-model-final-audit.md`) found 111 silent wrong answers in 847 probes (`probes/f`), in nine classes; all 111 now print perl's answer or are refused by name.

| class | n | outcome | where |
|---|---|---|---|
| A copy of a shared `my` array read as its source | 12 | SAME | B::SoN: the padav list shortcut does not flatten a literal holding a whole aggregate read at a version or shared |
| B copy through a reference made late | 17 | SAME | chalk: Count/keys of a copy read the copy; an rvalue whole deref reads_before makes is a copy |
| C callee stores a variable by name, then reads `$_[N]` | 19 | REFUSED | `a variable passed to a sub that stores it by name and reads its arguments` (ModSets::arg_stored_by_call, in the sub's own order) |
| D assignment or ?: as an lvalue, store dropped | 14 | REFUSED | `a ?: used as the target of an assignment/op=/increment`, `an assignment used as the target of an op=`, `... of a sub's write through $_[N]`; the sassign catch-all is a GAP but for a call's result |
| E package scalars / new elements in an alias list | 18 | REFUSED | `a package scalar aliased by a foreach, map or grep`, `an element (or a slice) perl's alias may make exist` |
| F chop's value | 10 | SAME | chalk: ChopChar |
| G foreach write-back lost on a die | 13 | REFUSED | `a foreach iterator written in a pass a die may leave`; an op= now stores the demoted iterator's slot too (a silent wrong at base: `$x += 1; print $x` in an eval body) |
| H `$_[0] = ...` on a `my` invocant | 2 | REFUSED | `a method that stores $_[0]` |
| I `$1` scoped to its block; `$2` past the groups | 6 | SAME | B::SoN restores the last match at a block's or loop's end; chalk: a group past the result is undef |

Clause 2: a may-fault division under OPf_MOD (sprintf's arguments) is pinned; `_seat` is the one write of `control_in` (a Return on an exit's recorded control and a guarded exit's re-seat are not placements, and stay outside `_pin`), and `t/placement-one-constructor.t` catches any spelling. Clause 4: a55, d61, o11 verify clean and are in `probes/f/`; chalk's loader holds every wire to WireInvariant and WireCheck but one chalk wrote (`writer: chalk`, from to_json; eleven tests' hand-built wires say so; four old fixtures fixed). Clause 1: `probes/cpa/` holds cpa01-35.

Probes: 2298 in chalk (847 new: `fa<name>`), SAME 1748, REFUSED 535, LOUD 15, WRONG 0. fa: SAME 603, REFUSED 238, LOUD 6 (at the audit's heads 557 / 173 / 6 / 111). No older probe changed verdict; three refusals are named by the new rules first (lw25, ree30, req12). All 847 f wires and the 35 cpa wires pass SoN::Verify.

Open design items (refused, not lowered): aliases on the wire (C, E, H); a write-back on every way out (G); an lvalue `?:`/assignment (D). Shortcuts named in the code: an unknown call is not counted by the call-argument rule; a caller's own `$_[N]` argument is not counted by C; an element through a reference or of a stash is not refused by E.

`tools/gates.sh` at producer 21457b0, chalk add5ce17:

```
producer-suite  PASS  812 files, 0 failing [10m29s]
chalk-suite     PASS  940 files, 0 failing [77m15s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [1m49s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [5m02s]
probes          PASS  LOUD=15 REFUSED=535 SAME=1748; WRONG 0, SAME lost 0, changed 0 [6m20s]
ratchet         PASS  prove exit 0; chalk's lib compared; held by name: 0 [35m40s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [3m06s]
```

(gates1 was stopped: its producer suite failed 16 files and the ratchet lost 6 corpus graphs, all refusals reaching past their class -- ed66c63. gates2: five chalk tests refused programs that matched perl -- slices and hash keys known to be there, `"@_"` read whole, a hash copy of an undef reference -- 21457b0, add5ce17.)

## 24. Clause 3's caveats and the verifier's alias-list exemption (branch `clause3`)

Heads: producer `clause3` c66429e (from 9afe7f0: 46cb342 time/rand, 053a625 record, 3ec0817 alias item, c66429e deparser), chalk `clause3` b1de1e4f (from add5ce17: 5dd631c7, 640ad9af, b1de1e4f). The final audit's clause-3 row and its section 4 items 7 and 10.

| item | outcome | where |
|---|---|---|
| `record` derived by the serializer | DONE | the list assign (the only site that made one, measured over corpus and probes) decides record-or-store before it builds the Assign and says `record => 1` (in its content hash); `_pin` dies on a record; SoN::Serialize::JSON writes the flag and derives nothing |
| the double walk (`%LOOP_HINTS`) | NOT DONE: a design decision | over the corpus, 8 of 1671 sub walks go round again (4 a Phi's stamp, 4 the iterator-write guess, 0 a missed slot, 0 a later write); the guesses are about the binding's class, which Braun's incomplete Phi does not have |
| EntryDef with no version in an alias list | DONE | the gvsv handler gives an item of a foreach/map/grep list the memory there; V6 no longer excuses a package scalar as an alias-list place; 0 such items over corpus and probes (2 at base: f/j01, r/e29, both SAME before and after) |
| positional memory in the deparser | DONE | SoN::Wire::as_v1 marks every node it appends a mem_in to (`memory_input`); the deparser reads it (`_mem_input`); `%MEM_MIN_INPUTS`, Ref's and Subscript's positional pops, and t/deparse-memory-table-matches-producer.t are gone |
| time, sleep, rand, srand not ordered | DONE | EffectTable: `time` reads the `clock` (an ordered class), `rand` writes the random stream; chalk's BuiltinTable `reads_state` makes both where they stand; a sleep or srand statement stays refused by name in T2 (c3t1, c3t3-6) |

Probes: c3t1-7 added (2 SAME, 5 REFUSED). The deparser printed `no` for perl's `ok` on `my $t0 = time; sleep 1; my $t1 = time` (both reads floated); chalk never showed it, since T2 refuses the sleep. chalk's interval oracle re-keyed for loops:11 (rand's Calls numbered one lower, the same six proofs).

`tools/gates.sh` at producer c66429e, chalk b1de1e4f:

```
producer-suite  PASS  815 files, 0 failing [18m21s]
chalk-suite     PASS  940 files, 0 failing [40m25s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [1m46s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [6m18s]
probes          PASS  LOUD=15 REFUSED=540 SAME=1750; WRONG 0, SAME lost 0, changed 0 [5m46s]
ratchet         PASS  prove exit 0; chalk's lib compared; held by name: 0 [85m35s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [3m15s]
```

(gates1, producer c66429e and chalk 640ad9af: all PASS but the chalk suite -- t1-integer-intervals-prove-nothing-new.t counted rand's renamed Calls as six proofs new and six lost; re-keyed, b1de1e4f. gates2 ran beside another session's gates, which slowed the ratchet to 85m.)
## 25. Aliases are places; an assignment or `?:` as an lvalue (branch `alias-places`)

Heads (rebased on clause3, producer 152a6be, chalk b1de1e4f): producer `alias-places` e899786 (e30a00f design doc, 337c1ec design 1, 7dd249b design 3, d10b2c6, 1edebdd, 3e0705d, e899786), chalk `alias-places` f1d9aa74 (design 1, design 3 probes, alg03, 7d78744a, f1d9aa74). Design: `docs/plans/2026-11-24-aliases-as-places.md` (designs 1 and 3, approved; wire change: `fields.place`, `fields.vivify`).

The final audit's wrong answers in the classes the designs cover, by the audit's own lists:

| class | n | now |
|---|---|---|
| C a callee stores the argument by name, then reads `$_[N]` | 19 | 19 SAME: the argument is a place, the callee reads `@_` as aliases |
| E foreach/map/grep over package scalars or new elements | 18 | 14 SAME; 4 slices refused by name (`a slice perl's alias may make elements of`) |
| G a foreach write lost when a die leaves the pass | 13 | 12 SAME: the iterator in memory is its element, nothing is written back; f/n10 (`values %h`) refused by name |
| H `$_[0] = ...` on a `my` invocant | 2 | 2 SAME |
| D an assignment or `?:` as an lvalue | 14 | 13 SAME; f/i03 (a `?:` of package scalars needs a real If) refused by name |

Probes: 2351 in chalk (46 new `al<name>`; producer `probes/al/`), SAME 1859, REFUSED 477, LOUD 15, WRONG 0. Against section 23 no older verdict changed but REFUSED -> SAME (74 probes); the 46 new ones are 35 SAME, 11 refused by name. Deleted: the GAPs of C, H, G and E's package scalar and element arms; the pass-end write-back, `%AFTER_CALL_PASSING`, `_iterator_written_unstored`. New: SoN::Verify V12 `alias-not-private` (mutation case M17), chalk WireInvariant L10.

The fast path (`tools/alias-fastpath.pl --chalk`, over chalk's 221 lib wires at 002086d0; a sub walked again inside one translation counts again, and a module counts once per wire that loads it):

```
call  value  49999  place   1487  proof fails   2.9%
list  value    227  place     54  proof fails  19.2%
iter  value   9417  place     67  proof fails   0.7%
```

`tools/gates.sh` at producer e899786, chalk f1d9aa74:

```
producer-suite  PASS  814 files, 0 failing [25m35s]
chalk-suite     PASS  941 files, 0 failing [83m14s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [1m40s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [11m24s]
probes          PASS  LOUD=15 REFUSED=477 SAME=1859; WRONG 0, SAME lost 0, changed 0 [6m06s]
ratchet         PASS  prove exit 0; chalk's lib compared; held by name: 0 [61m52s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [2m50s]
```

(gates1 stopped: two producer tests over Carp's `for ($::{$p})` -- as_v1 took a placed alias list's mem_in for an operand. gates2 stopped: clause3 merged, rebased. gates3: V12 counted a `local` as a store to the alias's source (f/h11), and the fast path called a foreach over @_ private (f/h14: now a place); chalk's grammar refused `grep( { } LIST )`; an interval-oracle row renamed (node ids moved). gates4: chalk's Analysis typed an element of `my @c = @$r` as an Array, which Test::Chalk's isa_ok now read through its iterator.)

## 26. A sub is walked once (branch `single-walk`)

Heads: producer `single-walk` 896bca7 (from ce5f564: 07a1858, 3e4b6e7, 46f2641, f7ea4b1, 896bca7), chalk `single-walk` f1d9aa74 (unchanged). Clause 3's last caveat: "built Braun-style without the double walk" held only while every guess held -- a wrong one walked the sub again (`%LOOP_HINTS`). Design (c), approved: a pre-scan of the ops decides each fact, exactly or conservatively, before the walk; the walk never guesses.

| fact the header needed | pre-scan | where a miss is refused |
|---|---|---|
| the body writes the foreach iterator | `_body_writes`, `_op_writes_key` (every op of the body; an inner loop aliasing the same name left out; a name in an inner loop's list written only where that loop writes its alias; a demoted iterator by `_demoted_rebinds`) | `_check_writes` |
| a Phi keeps its init's stamp | `_loop_stamp_scan` (a fixpoint over the slots the pass writes: stamped, element read, unknown; `_patch_loop_phi`'s recurrence) | `_patch_loop_phi` ("loses its stamp") |
| the slots that get a Phi | `_may_write_targs` (+ package scalars and aggregates; a body that never goes round: all its ops; `next` through the continue block; an inner loop's `last` goes on round) | `_braun_seal` ("its header's scan missed") |
| an aggregate written after a read flattened it | `_loop_aggregates_written` (the header marks the literal) | `_braun_seal` |

Deleted: `%LOOP_HINTS`, `$DIRTY`, `_loop_hint`, `_writes_guess`, `_backedge_loses_stamp`, the retry that wrapped `_translate_from_once` (now `_translate_from`), and B::SoN's settle pass (`_translate_until_settled`, now `_translate_program`, one pass). B::SoN also translated each class method twice (`_extract_class` for its return type, the stash walk for its graph); `_translate_once` keeps the first.

THE SETTLE PASS (perigrin's choice "B", 2026-11-25). B::SoN translated the whole program again when a walk met a writer of a package scalar the first scan had not read (p/w1lib4: a method of a class from a file it does not follow). Now a package scalar counts as written unless the first scan read every sub of its package (`%PKG_UNREAD`, `_scalar_written`), and a writer met later of a scalar some graph was told is unwritten is refused by name (`_scan_run_set_cv`). Its cost, package-scalar reads through memory (EntryDef with mem_in) at ce5f564 -> 896bca7: corpus 368 -> 368, probes 2748 -> 2748, chalk's lib 422 -> 422. None.

Sub walks repeated (t/lib/WalkCount.pm: a loop body walked twice in one process), at ce5f564: corpus 11 files -- 8 loop guesses (013 316 317 POSIX::import's iterator write, 190 the iterator write, 106 169 203 208 a stamp), 3 a class method (126 164 231); probes 142 files (at 152a6be, of 117: the iterator write 103, a stamp 14, an aggregate 23, a missed slot 1 -- r/o16; clause 3's note that "the other two never fired" held for the corpus only; w1lib1 a class method, w1lib4 the settle pass). At 896bca7: none. t/loop-body-is-walked-once.t sweeps corpus and probes and holds nothing by name.

Exactness, by wire identity (`tools/wire-verify.pl --wires`, both producers, paths and refusal locations normalised): corpus and probes 2786 of 2787 byte-identical to ce5f564's, #graphs equal (1082, 3323); the one is probes l/lw25 (`$_ .= "x" for @a[0,1]` after a read of `@a` in the loop), where the header marks `@a` and the read is made through memory -- base flattened it; chalk refused it there and prints perl's answer now (the probes gate's one change). chalk's lib: 221 wires, #graphs equal (25134); ten differ from the base's in eval numbering only (the base's second walks had numbered a sub's evals twice). The scans were wrong, on the way, in ways only those diffs showed: B::SoN compiles without the peephole (`$_` is `rv2sv(gv)`); a gvsv carries no lvalue flag; "written" for a demoted iterator skipped its pass-end write-back (f/n03 printed `1 2` for `1! 2!`); and chalk's lib alone held an s/// in an arm, a name in an inner foreach's list, an inner loop's `last`, an s/// by targ, a count, and a capture (eight graphs refused, then none) -- docs/memory/a-sub-is-walked-once.md.

Tests: t/loop-body-is-walked-once.t (a nest; each guess's program -- corpus case, probe or chalk shape -- walked once, translated whole, and through the deparser against perl where the base renders it; each scan made to miss and refused by name; the corpus and probes swept), t/package-scalar-of-an-unscanned-package-is-written.t; t/lib/MayWriteCheck.pm reads the refusal for t/loop-may-write-scan-covers-the-walk.t.

`tools/gates.sh` at producer 896bca7, chalk f1d9aa74:

```
producer-suite  PASS  815 files, 0 failing [14m06s]
chalk-suite     PASS  941 files, 0 failing [64m07s]
census          PASS  ROUNDTRIP 426 (>= 426) DIFFERS 0 LLI_FAIL 0; GAP 5 LOAD_FAIL 0 NOJSON 0 [1m40s]
corpus-gate     PASS  gate-green 222 (>= 222), prove exit 0, paad/worklist.json untouched [4m53s]
probes          PASS  LOUD=15 REFUSED=476 SAME=1860; WRONG 0, SAME lost 0, changed 1 [6m06s]
ratchet         PASS  prove exit 0; chalk's lib compared; held by name: 0 [33m44s]
                PASS  (deparser round trip) ROUNDTRIP 430 (>= 430) EMITS_INVALID_PERL 0 [3m00s]
```

(The probes gate's one change is l/lw25, REFUSED -> SAME: its read of `@a` is made through memory now, and chalk prints perl's `1,2 1x,2x`. The run on the old base, 152a6be, was stopped when alias-places merged; none ran on it to the end.)

## 27. The second final audit's wrong answers lowered or refused by name (branch `audit2`)

Heads: producer `audit2` from 8257e66, chalk `audit2` from f1d9aa74. The second final audit (docs/research/2026-11-25-memory-model-final-audit-2.md) found 57 silent wrong answers in 828 new probes (probes/z), nine classes. Each is lowered or refused by name; the z probes are in chalk's `t/data/audit-probes` as `z<name>` with BASELINE rows (pa79 and un75 out of `z/unverified/`, which is gone).

| class (n) | outcome | how |
|---|---|---|
| K1 (13) | SAME 13 | `my ($p, $q) = @_` binds each target to `$_[i]` read where it stands, where a caller may hand the sub places (`ModSets::args_may_be_places`: it stores through `$_[N]`, reads `@_` after a store, or a call no walk sees into may be its call); `my @l = @_` is a pinned copy and a slurpy bind is placed where the sub's MOD set is not empty (T2 hands `@_` as aliases). Elsewhere the parameter record stays. SoN::Verify: a record is used where its target is, and a used record of `@_` in a graph that stores into an element of `@_` is `read-unversioned:args` |
| K2 (5) | REFUSED 5 | `GAP: a variable handed to a sub as its $_[N] where that sub localizes it` (`ModSets::arg_localized_by_call`: a place, or a reference to `$_[N]`; a call no walk sees into only where code the scan read localizes that variable, `%PKG_LOCALIZED`) |
| K3 (5) | SAME 2, REFUSED 3 | a lexical iterator over one array whose body calls a sub that may store it (MOD set) is aliased by reference; refused: `$_` (foreach, map, grep) or a package iterator read after such a call, and a list of several items or one a call returns, read after it (`keys` is copies; a list of variables, elements and constants is a list of places) |
| K4 (8) | SAME 3, REFUSED 5 | the op= refusal takes a fused store (TARGMY) for a target; `x=` of a list; an assignment as an item of an alias list whose body may write it; a TARGMY op (`$x .= "b"`) passed to a sub storing `$_[N]` is `$x`'s place |
| K5 (6) | REFUSED 6 | `GAP: an assignment's element is read by alias and a later operand stores into its container` |
| K6 (2) | SAME 2 | chalk `arg_alias`: a package scalar read at an older version than its call's, not a place, is a copy of the value; producer: a postincrement's value is no place |
| K7 (3) | REFUSED 3 | `GAP: an aggregate flattened into a list is read by alias and a later item may store into its elements` (an array; a hash only by a call's store; a reshape or a new key is no such store) |
| K8 (4) | SAME 4 | not a pre-scan miss: scan and walk both said "written"; `store_at_write` skipped any loop Phi as the iterator's own, and `$y`'s was what `$x` was set to (`%LOOP_PHI_KEY`) |
| K9 (11) | SAME 11 | B::SoN reads, at CHECK, each followed module's package variables some graph names and puts them on the wire as a BEGIN block of literal stores after the program's own BEGIN blocks; refused by name: an object, code, a glob, or one a program BEGIN block reads |

Clause gaps: st3 is refused in perl's words (the harness: perl does not compile it); pa79's lvalue substr reads `$_[0]` at a version; V10 counts a local put back before the thrower as closed (un75, with a mutation test); V12's alias-list half (a foreach/map/grep's own item, used after a store that may reach its list; mutation test and the base's pa69 wire); `as_v1` takes the producer's `mem_operand` mark (`marks.mem_operand` on the wire); t/pre-scan-agrees-with-the-walk.t compares the iterator write and the slots, scan against walk, over corpus and probes (eleven named disagreements: ten safe-side Phis, one refused miss).

Shortcuts named in the code: a call no walk sees into is not counted by K3's and K7's refusals (as the call-argument rule does not); a sub a BEGIN block calls reads a followed module's variable as the wire has it then, unset; an import that is not followed code stores no followed module's variable.

Design question left open (K2): a place is the variable's storage, so under `local` it names the new scalar where perl's alias keeps the saved one. Either `local` on the wire makes a new place -- the save holds the old place, the name is rebound, and a place taken before keeps the old one (HHVM's box) -- or the refusal stands.
