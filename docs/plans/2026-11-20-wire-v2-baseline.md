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
