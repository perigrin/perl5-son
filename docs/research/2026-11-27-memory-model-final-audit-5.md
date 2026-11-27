# Fifth final audit of the goal "Make the SoN memory model mechanical and checked, measured" (2026-11-27)

Producer worktree `au5-p`, branch `audit5`, 396aae40. Chalk worktree `au5-c`, detached at a2fe984d. No code was changed. The commit is this file, the probes in `docs/research/son-ir-audit-2026-11-19/probes/v/`, one README line and one memory note. It follows the four final audits; read `2026-11-26-memory-model-final-audit-4.md` first.

## Verdict

**The gates hold and audit 4's seven classes are closed. The goal's first sentence still does not hold: 2576 new probes found 301 silent wrong answers in eighteen classes.**

- Audit 4's 72 wrong probes are rows in chalk's gate now (`x<name>`), and the gate is WRONG 0 with promotion on and off. That is the gate run handed to this audit; I did not re-run the sweep.
- 2576 new one-line probes: SAME 1587, REFUSED 675, LOUD 13, WRONG 301 (11.7%). All 301 were run twice and reproduced.
- First round, 1610 broad probes: 29 wrong (1.8%; audit 4's broad round was 1.4%). Second rounds, 966 probes written around each first-round wrong: 272 wrong.
- **One is not an alias problem at all.** `$t = "$s$s"` assigned to an existing `my` scalar is dropped: `my $s = "a"; $s = "$s$s"; print $s` prints `a` for perl's `aa` (Q1, 20 probes).
- **Five classes sit on the edges of audit 4's fixes.** X4's fix reads a list assignment's targets as values, so a later item's store is lost and a `my` target can vanish (Q6, 55). X7's fix re-reads only the left operand of `&&`, `||`, `//` and does not look inside a `do` block, `x`, or a call's arguments (Q2 to Q5, 103). X5's fail-closed proof still says two constant indices are two elements, by spelling: `$a[-2]` and `$a[0]` (Q10, 23; SAME with `SON_NO_PROMOTE=1`; V14 passes all of them). X1's fix keeps the range iterator in memory and drops a store to it (Q11, 15). X3's refusal covers slices and not `local ${"x"}` or `local $$n` (Q8, 13).
- The other 72 are older and were never probed: `local` on a whole aggregate in chalk (Q7), an `:lvalue` sub under `local` (Q9), a reference to an element across `reverse` (Q12), a dereferenced array in a list read late (Q13), `delete @h{@k}` (Q14), a foreach over `@a[1..$#a]` (Q15), a call that returns none or two values, in a hash literal (Q16), `\(my $v = 1)` (Q18), two singles (Q17).
- The verifier flags 10 of the 301 wrong wires. Chalk's loader let all 10 through. 291 wrong wires are clean.

Three short examples:

- `my $s = "a"; $s = "$s$s"; print "$s\n"` prints `a` for perl's `aa`.
- `my ($x, $y); sub z { 0 } my @l = ((($x, $y) = (7,8)), z()); print "@l\n"` prints `7  0` for perl's `7 8 0`.
- `my @a = (1,2); sub f { $a[-2] = 5; $_[0] } print f($a[0])` prints `1` for perl's `5`.

## 1. Verdict per clause

| clause | verdict | what holds | what does not |
|---|---|---|---|
| (1) No silent wrong answers from the audit | **MET for the gated set; NOT MET for the audit's probes as a whole** | The gate as handed over: 5435 probes, SAME 4061, REFUSED 1334, LOUD 40, WRONG 0; promotion off WRONG 0. `t/data/audit-probes/BASELINE.tsv` (chalk) has 5435 rows with those counts. Audit 4's 825 are in it, X5's 16 too. New probes for each fix are beside the old ones. The 14 audit-3 probes still left out (their wires break a verifier rule) and `yp13`, `ya57` were run here (`v/_y_left_out.log`): 12 REFUSED, 3 SAME, and `ya57`, which reads a freed scalar and is not counted. | 301 new wrong answers (section 4). One new refusal has no name: `v/vo05` is "IR: analysis finished with untyped Value node(s)", an internal error, not a GAP. |
| (2) Producer placement is mechanical | **MET for what reaches the constructor; NOT MET for what never does** | One constructor: `_place` `lib/SoN/FromOptree.pm:902`, `_pin` `:911`, `_seat` `:955`; `t/placement-one-constructor.t` passes here. List-assign targets by storage: `_target_storage` `:24642`; `t/wire-list-assign-places-by-storage.t` passes. Package scalars through memory: `_entry_live_value` `:15535`, `_key_lives_in_memory` `:15556`. Dynamic method: `dispatch_kind => 'dynamic_method'` `:6316`. Effect table: `B::SoN::EffectTable::on_chain` (`lib/B/SoN/EffectTable.pm:192`), asked at `FromOptree.pm:14387`, `:20952`, `:21090`; both effect-table tests pass. May-fault division: `_may_fault` `:961`. | A store that gets no node is placed nowhere, as audit 4 said, at four new sites: the `stringify` handler ignores `OPpTARGET_MY` (`:13546`, Q1); a compound assignment to a range iterator kept in memory makes a floating `Multiply` and no store (Q11); `local` through a symbolic name makes a plain `Assign` (`_local_shape_gap` `:20447`, Q8); `delete @h{@k}` makes one `Delete` whose key is the whole array (`:11008`, Q14). There is still no default GAP for an `OPpLVAL_INTRO` or an `OPpTARGET_MY` no handler read. |
| (3) Wire v2 | **MET** | My scan of the 2576 new wires (3563 graphs; `v/_verify.log`): all are version 2; every `Return` (3563), `Unwind` (151), `EntryWrite` (1925), `CellWrite` (47), `Delete` (62), sub `Call` (1358) and non-record `Assign` (2019) has `mem_in`; no `MemStart` or memory Phi is in a value's `inputs`; 142 record `Assign`s are flagged; 171 `Exc`; 728 `Loop`s, each with one or two inputs. `%LOOP_HINTS` is one comment (`FromOptree.pm:16035`); `_braun_phis` `:16043`. chalk `lib/`: `Phi::is_memory` is one comment (`lib/Chalk/IR/Node/Phi.pm:42`); `is_placed`, `WireUpgrade`, `MEM_MIN_INPUTS` and `memory_input` do not occur. | Caveats, not breaches. The producer's deparser still asks `_is_memory` on the `as_v1` form (`lib/SoN/Deparse.pm`, 25 mentions). B::SoN reads the tree before perl's peephole pass; the peephole pass changes meaning in one place the wire does not carry (`@a = reverse @a` in place, Q12). |
| (4) Checked | **MET on the three named sets; the loader lets through what the verifier rejects** | `SoN::Verify`: `write-unreachable` `lib/SoN/Verify.pm:524`, `read-unversioned` `:701`, V12 `_alias_private` `:64`, V14 `_promoted_private` `:240`, now `lib/SoN/PromotedPrivate.pm`, which shares no code with `SoN::AliasProof`. Runs in both suites: producer `t/wire-verify-ratchet.t` (`%HELD` empty), chalk `t/bootstrap/ir/wire-verify.t` (must-run, `tools/gates.sh:52`). `t/wire-verify-rejects-hand-broken-wires.t` passes here. Loader: `WireInvariant` L1-L10 and `WireAliases` L11 on every wire but a memory-free `writer: chalk` one (`lib/Chalk/IR/Serialize/JSON.pm:1364`-`1371`). The gate ratchet with chalk's lib is PASS, 0 held, as handed over. | 17 of the 2576 new wires break a verifier rule (section 3). Chalk loaded ten of them and printed a wrong answer: the loader has no `read-unversioned` or `record` rule. V14 and the pass now differ in code and agree in one assumption: a constant index names an element by its spelling (`AliasProof.pm:237`, `PromotedPrivate.pm:76`). 23 wrong wires, 0 V14 violations. |
| (5) Verified and pushed | **MET as handed over; spot-checked** | Gate numbers are the ones given to this audit. Here: five producer tests pass (108 tests); `BASELINE.tsv` holds 5435 rows, SAME 4061, REFUSED 1334, LOUD 40. With `v/` in place: `t/wire-verify-ratchet.t` (corpus and probes, no chalk lib), `t/pre-scan-agrees-with-the-walk.t` and `t/loop-body-is-walked-once.t` pass (29 tests). Audit 4's 13 minimized programs (`x/min/`): 10 SAME, 3 REFUSED. | I did not run either full suite, the census, the corpus gate, the deparser round trip or the chalk-lib ratchet. |

## 2. Against the literature

Only real gaps are listed.

**MemorySSA; alias analysis that fails closed.** Audit 4 asked for a default of *may clobber*. `SoN::AliasProof::conflict` now ends `return 1` (`lib/SoN/AliasProof.pm:302`), and captures count as references. One "no" is still not proved: line 237 says two elements of one container at different constant indices are different storage, and compares the indices as strings. Perl's index is a number that wraps: `$a[-2]` is `$a[0]` in a two-element array; `$a[0.5]`, `$a[!1]` and `$a["0"]` are `$a[0]`. LLVM's BasicAA makes the same kind of claim only for indices it has normalized and knows in bounds. Here a negative or non-integer constant must be "index not known". 22 wrong.

**Translation validation; N-version checking.** Audit 4 said V14 shared its predicate with the pass. It no longer does: `SoN::PromotedPrivate` is its own module. It repeats the same assumption on its own (`PromotedPrivate.pm:76` names an element `container#constant`). Two implementations written from one specification fail together where the specification is wrong (Knight and Leveson's result on N-version programming). V14 passes all 23 Q10 wires. The differential the gates now run, `SON_NO_PROMOTE=1`, is the check that is independent: it separates all 23. It only sees programs someone wrote a probe for.

**LLVM alloca, mem2reg.** mem2reg promotes an alloca wholly or not at all. The fix for X1 keeps a range foreach's iterator in memory when a reference is taken, and its SSA binding lives on beside the slot. `$i *= 2` updates the binding; the slot keeps the pass's first value; `\$i` reads the slot (Q11). A variable in memory must have no SSA binding that a store can update alone.

**Clang's lvalue-to-rvalue conversion.** Clang makes "this operand is read now" a node of its own (`LValueToRValue`), so every load has a program point. Perl has no such point: an operand on the stack is the SV, read when its consumer runs, and an op may hand its operand's SV on. Audit 4 said the consumer list was a list of spellings. The fix moved the question to the op that hands the SV on, which is right, and wrote that as code for `scalar`, a one-statement `do`, and the left operand of `&&`, `||`, `//` (`FromOptree.pm:26254`-`26303`). The right operand, `x`, a list in a `do` block or a `map` body, `++$x` and `$x = 4` as call arguments, and magical values (`$1`, `substr`, `$#a`) are not in the code (Q2 to Q5, 103 wrong). The effect table (clause 2) is the model to follow: one row per op saying which operands it reads when it runs and which SVs it hands on, with "hands on" as the default for an op that has no row.

**Per-iteration bindings (ES2015); HHVM boxes.** Covered for `my` in a loop body and for a range iterator's reference (audit 4, X1: 5 of 6 SAME; the new probes on nested loops, `while`, `until`, `last`, `next`, closures and calls found one fault). It is Q11 above.

**Element identity.** Field-sensitive pointer analyses name a location as (object, offset). That is sound in C, where elements do not move. A Perl array holds scalars that can move: `reverse` and `sort` in place, `shift`, `splice`. Chalk's element alias is the aggregate and an index (`FromOptree.pm:26083` says so), and a `my` array assigned whole is a new SSA aggregate. A reference to `$a[1]` taken before `@a = reverse @a` then writes into nothing (Q12). HHVM boxes an element once a reference to it exists; nothing less keeps the identity.

**Peephole-sensitive semantics.** B::SoN compiles with the peephole pass off (memory note "a sub is walked once"). The pass is not only an optimization: `OPpREVERSE_INPLACE` and `OPpSORT_INPLACE` change which scalars an array holds, and for `$t = "$a$b"` the pass moves `OPpTARGET_MY` from the `stringify` to the `concat` under it. Q1 and Q12 both come from reading a tree perl never runs. A front end that reads an intermediate form owes a list of what the later pass changes in meaning.

**Braun et al.; Click's sea of nodes and C2 memory slices.** Nothing new. The pre-scan is still a second source of truth (ten new probes disagree with the walk; two of them are Q1's dropped store, which the scan saw and the walk did not). One fat memory chain is still sound and still leaves all precision to proofs outside the IR.

**Testing compilers (Csmith; EMI).** Eight audits since 2026-11-19 have each written fresh probes by hand, and each found 7 to 19 percent of them wrong: 59, 55, 68, 111, 57, 146, 72, 301. The rate does not fall. A gate that holds the probes of the last audit measures the last audit. The oracle is free here (perl itself); a generator of small programs over the constructs in section 4, run against perl in the gate, is what the literature does when the oracle is free.

## 3. Verifier and suite checks on the new probes

| check | result |
|---|---|
| `SoN::Verify` over 2576 new wires, 3563 graphs (`v/_verify.log`) | 17 violations in 17 probes: `read-unversioned:package` 9, `record` 4, `read-unversioned:args` 1, `read-unversioned:my-aggregate` 1, `effect-floating` 1, `alias-not-private` 1. Moved to `v/unverified/`. |
| of those, WRONG | 10: `vf217`, `vq111`-`vq116` (Q4, `read-unversioned:package`: `substr($t,0,1)` of a package `$t` as a call's argument) and `vo41`-`vo43` (Q6, `record` of a package variable). Chalk loaded each and ran it. |
| of those, not wrong | `vd84`, `ve46`, `vi161`, `vq117` refused by chalk for another reason; `vk59` refused by the loader's L11; `vq130`, `vq139` SAME. |
| WRONG wires the verifier does not flag | **291 of 301.** By class in section 4.1. |
| structure (clause 3 scan) | 0 faults |
| pre-scan agreement and walked-once instruments on `v/` | 10 probes differ, in each the scan says more than the walk: `SLOTS extra` 7 (`vb13`, `vb78`, `vk61`, `vn22`, `vn30`, `vs32`, `vs35`), `ITER scan=1 walk=0` 3 (`va44`, `va45`, `vm101`). No loop body was walked twice. Moved to `v/unverified/`. `vs32` and `vs35` are Q1: the scan saw the store to `$s` in the loop and the walk dropped it. `vm101` is Q8. "The safe side" is not always safe. |
| `SON_NO_PROMOTE=1` on the 301 wrong (`v/_nopromote.log`) | **23 SAME** (Q10), 278 WRONG both ways |
| `SON_NO_PROMOTE=1` on the 89 new wires that hold a `promoted` node | 50 SAME both ways, 10 REFUSED both ways, 1 LOUD both ways, 1 SAME with promotion and refused without, **23 WRONG with promotion and SAME without**, 4 WRONG both ways (other classes) |
| `t/placement-one-constructor.t`, `t/wire-verify-rejects-hand-broken-wires.t`, `t/effect-table.t`, `t/effect-table-has-a-row-for-every-builtin.t`, `t/wire-list-assign-places-by-storage.t` | pass (108 tests) |
| `t/wire-verify-ratchet.t` (corpus and probes, no chalk lib), `t/pre-scan-agrees-with-the-walk.t`, `t/loop-body-is-walked-once.t`, with the 2549 probes in `v/` and the 27 in `v/unverified/` | pass (4, 3 and 22 tests) |

## 4. New probes

2576 programs: 2549 in `probes/v/`, 27 in `probes/v/unverified/`. Each was run under perl 5.42.0 and through B::SoN, chalk T2 and `lli` by `AuditProbe::run_all`, the harness of `tools/audit-probes.pl`. Verdicts are in `v/_run1.log`, the class of each wrong probe in `v/_classes.tsv`. The log, and the tables below that are made from it, show a run of spaces as one. Twelve first-draft probes printed a hash in perl's own order; they were rewritten to sort and run again before counting.

| group | n | SAME | REFUSED | LOUD | WRONG |
|---|---|---|---|---|---|
| va | 121 | 61 | 53 | 1 | 6 |
| vb | 143 | 69 | 73 | 0 | 1 |
| vc | 87 | 19 | 68 | 0 | 0 |
| vd | 129 | 83 | 39 | 2 | 5 |
| ve | 160 | 109 | 45 | 4 | 2 |
| vf | 228 | 188 | 32 | 1 | 7 |
| vg | 154 | 125 | 27 | 1 | 1 |
| vh | 121 | 88 | 32 | 1 | 0 |
| vi | 163 | 121 | 39 | 0 | 3 |
| vj | 165 | 121 | 40 | 1 | 3 |
| vk | 139 | 103 | 34 | 1 | 1 |
| vm | 101 | 45 | 35 | 0 | 21 |
| vn | 69 | 34 | 21 | 0 | 14 |
| vo | 90 | 31 | 9 | 0 | 50 |
| vp | 124 | 85 | 9 | 0 | 30 |
| vq | 204 | 97 | 23 | 0 | 84 |
| vr | 127 | 66 | 44 | 0 | 17 |
| vs | 152 | 82 | 17 | 1 | 52 |
| vt | 99 | 60 | 35 | 0 | 4 |
| **all** | **2576** | **1587** | **675** | **13** | **301** |

What each group is aimed at:

- First round (1610, 29 wrong). `va` `local` of other shapes than a slice: elements, whole aggregates, lists, special variables, globs, symbolic names, loops, die through eval. `vb` cells made anew each pass: nested loops, `while`, `until`, C-style `for`, `last`/`next`/`redo`, closures, a callee that keeps `\$_[0]`. `vc` glob binds. `vd` list assignment, its value by context, swaps, chains. `ve` what the promotion proof must refuse: closures, references, symbolic stores, callees that write `@_`, elements and fields. `vf` the operand re-read rule, one probe per consumer and per op that hands an SV on. `vg` references and closures. `vh` eval, die, try. `vi` string ops in place. `vj` arrays and hashes. `vk` `@_`, `wantarray`, sort, `$_`, loops, recursion, methods.
- Second rounds (966, 272 wrong), around each first-round wrong. `vm` `local` on whole aggregates, through a symbolic name, with an `:lvalue` sub. `vn` a range iterator written and referenced. `vo` a list assignment's value followed by a store. `vp` constant indices and keys in other spellings; `++$x` as an argument. `vq` operand re-reads. `vr` element references across a reorder; foreach over a slice; `delete` of a slice. `vs` `"$s$s"`; `$1`; a call that returns no value, in a list. `vt` a foreach alias or a loop's `my` handed to a sub.

What came through clean:

- Glob binds (87 probes, 0 wrong, 68 refused). The X2 fix holds; most neighbours are refused by name.
- Cells made anew each pass (143 + 99 probes; the one wrong is Q11, the iterator's own store). A closure built in a loop over a fresh variable is refused by name (39 of the refusals).
- `local` on a slice: every form is refused by name (X3 holds). `local` on named scalars, in loops, nested, through die: 0 wrong.
- The fail-closed proof against closures, references, symbolic stores, `eval` strings, `&g;`, `goto &g`, callees that write `@_` (`ve`, 160 probes): 2 wrong, both in other classes' roots (Q10, Q3). X5 as audit 4 found it is closed.
- eval, die, try/catch, `$@`, locals through a die (121 probes, 0 wrong).
- `wantarray` in 13 call shapes, sort, recursion, method chains (139 probes, 1 wrong: Q16).

13 LOUD:

| probe | program | what chalk says |
|---|---|---|
| v/va73 | `our $x = 1; if ($x) { local $x = 2; print $x } else { local $x = 3 } print "$x\n";` | lli: "Instruction does not dominate all uses" (a bad module, not a named refusal) |
| v/vd38, v/vj130 | `%h = reverse %h` | refused at run time: a hash element read through no HASH reference |
| v/vd54 | `for my $e (($x, $y) = (5, 6)) { $e *= 2 }` | Modification of a read-only value attempted |
| v/ve140, v/ve141, v/ve142, v/ve143 | `f(do { $x })`, `f(do { 1; $x })`, `f(scalar($x))`, `f(($x, $y))` with a callee that stores `$_[0]` or `$_[1]` | Modification of a read-only value attempted. perl stores into the variable in the first, third and fourth, and into a copy in the second. |
| v/vf172, v/vg131, v/vs31 | `my $r = \(my $v = 1); ... $$r = 9` | Modification of a read-only value attempted (Q18's loud side) |
| v/vh72 | `my $c; eval { $c->() }; print $@ =~ /.../` | refused at run time: a call of what is not a code value |
| v/vk139 | `sort { $a->cmp2($b) } map { C->new($_) } 3, 1, 2` | Can't locate object method "cmp2" via package "C" (the method exists) |

One refusal with no name: `v/vo05`, `my @l = ((@a[0,1] = (7,8)), "$a[0]")`, is "IR: analysis finished with untyped Value node(s)", an internal error reported as a load failure.

### 4.1 The eighteen wrong classes

| class | what | n | side | verifier flags | with `SON_NO_PROMOTE=1` |
|---|---|---|---|---|---|
| Q1 | `$t = "$a$b"` to an existing `my` scalar is dropped. | 20 | producer | 0 | wrong |
| Q2 | An SV handed on, read where it stands: the right operand of `&&` `\|\|` `//`, `($x) x N`, a list in a `do` block or a `map` body. | 56 | producer | 0 | wrong |
| Q3 | `++$x`, `$x = 4`, `$x += 1` as a call's argument is a value, not `$x`. | 10 | producer | 0 | wrong |
| Q4 | A magical value as a call's argument, read before the call: `substr`, `$#a`, `reverse $t`. | 15 | producer | 7 | wrong |
| Q5 | `$1` read where it stands, not when its consumer runs; `s///` does not set it. | 22 | producer | 0 | wrong |
| Q6 | The value of a list assignment in a list is its targets' values then, not the targets. | 55 | producer | 3 | wrong |
| Q7 | `local %h`, and `local @a` beside a reference or with a slice of itself. | 10 | chalk | 0 | wrong |
| Q8 | `local ${"x"}`, `local $$n`, `local @{"a"}`, `local *{"x"}`: no `local` on the wire. | 13 | producer | 0 | wrong |
| Q9 | A store through an `:lvalue` sub under `local` goes to the old scalar. | 4 | chalk | 0 | wrong |
| Q10 | Promotion: two constant indices or keys are two elements by spelling. | 23 | producer, `AliasProof` and `PromotedPrivate` | 0 | **SAME, all 23** |
| Q11 | A store to a range foreach's iterator that a reference is taken of is dropped. | 15 | producer | 0 | wrong |
| Q12 | A reference to an array element, then `@a = reverse @a` or `@a = @a`. | 6 | producer | 0 | wrong |
| Q13 | `@$r` or `@{$h{a}}` as a list item is read when the list is used. | 18 | chalk | 0 | wrong |
| Q14 | `delete @h{@k}` with keys that are not literals deletes nothing. | 9 | producer | 0 | wrong |
| Q15 | A foreach over `@a[1..$#a]` writes into a copy. | 5 | producer | 0 | wrong |
| Q16 | A call in a hash literal counts as one item, whatever it returns; a `?:` arm of `()` is one undef. | 14 | chalk | 0 | wrong |
| Q17 | Two singles: `$_` read in a callee of a foreach body; a copy read late beside a per-pass cell. | 2 | chalk | 0 | wrong |
| Q18 | `\(my $v = 1)` is a reference to the 1. | 4 | producer | 0 | wrong |
| **all** | | **301** | | **10** | 23 SAME |

"Side" is where the wire first goes wrong. I read the wire of one probe per class (and the code where a line is given). "chalk" means the wire says what perl does and chalk's output does not; I did not trace chalk's lowering for Q9, Q13, Q16 and Q17.

### 4.2 Q1: `$t = "$a$b"` is dropped (20)

```perl
my $s = "a"; $s = "$s$s"; print "$s\n";                 # perl aa, chalk a
my $s = "a"; my $t = "x"; $t = "$t$s"; print "$t\n";     # perl xa, chalk x
```

The wire of the first holds `Concat [a, a]` with no consumer, and `Print` reads the old constant. No store, no rebind.

Cause, read in the code and traced. Before the peephole pass the tree is `stringify[$t]/TARGMY` over a plain `concat`. `lib/SoN/FromOptree.pm:13546` handles `stringify` by pushing a `Coerce` of its operand and returning; it never reads `OPpTARGET_MY`. The generic TARGMY path at `:12626` asks `$opmap->is_known($name)` first, and `stringify` is not in the op map (`lib/SoN/FromOptree/OpMap.pm:102`). After the peephole pass perl has moved TARGMY to the `concat`, which is why Concise shows nothing odd. Three or more parts, or a constant part, become a `multiconcat` before the peephole pass and are right (`"$s-$s"`, `"$s$s$s"`, `"b$s"`); `my $t = "$s$s"` and `$s = $s . $s` are right too. Exactly two interpolated variables into an existing `my` is the hole, in a sub, in a loop, with numbers (`$n = "$n$n"`). Where the target is the second part (`$t = "$s$t"`) perl keeps a plain assignment and the answer is right. A package target and an element target are right.

| probe | program | perl | chalk |
|---|---|---|---|
| v/vs02 | `my $s = "a"; $s = "$s$s"; print "$s\n";` | `aa` | `a` |
| v/vs19 | `my $s = "a"; my $t; $t = "$s$s"; print "$t\n";` | `aa` | (nothing) |
| v/vs20 | `my $s = "a"; my $t = "x"; $t = "$t$s"; print "$t\n";` | `xa` | `x` |
| v/unverified/vs32 | `my $s = "a"; for (1..3) { $s = "$s$s" } print "$s\n";` | `aaaaaaaa` | `a` |
| v/vs56 | `my $n = 1; $n = 2 + $n; $n = "$n$n"; print "$n\n";` | `33` | `3` |
| v/vs63 | `sub w { my ($s) = @_; $s = "<" . $s; $s = "$s$s"; $s } print w("a"), "\n";` | `<a<a` | `<a` |

### 4.3 Q6: the value of a list assignment in a list (55)

```perl
my ($x, $y); sub z { 0 } my @l = ((($x, $y) = (7,8)), z()); print "@l\n";   # perl "7 8 0", chalk "7  0"
my @a = (1,2,3); my @l = ((@a[0,1] = (7,8)), $a[0] = 9); print "@l\n";      # perl "9 8 9", chalk "7 8 9"
```

Perl's list assignment in list context yields its targets, as lvalues. Audit 4's fix for X4 (`lib/SoN/FromOptree.pm:13500`-`13523`) pushes, for `my` scalars, each target's value now (`$sim->lookup($_->targ)`), and for elements and slices a `Subscript` read at the store's version. Both are values. Two things follow.

- A later item that stores a target is not seen: `((($x,$y) = (7,8)), $x = 9)` gives `7 8 9` for `9 8 9`. Elements, slices, hashes, through a reference, package arrays, with a call, a closure, `++`, `.=`, as a call's arguments, in `join`, `push`, `[...]`, `print`, and as a `map` or `grep` list whose block stores.
- With a call after it, the operand rule then reads the pushed items "again" and gets them wrong with no store anywhere: the first example. The wire's list is `[Constant 7, PadAccess $x mem_in=Call, Call]`: the second item is `$x` read from memory, where nothing stored it, and `$y` is gone. `my ($p, $q)` as the targets loses an item the same way (`vo51`, `vo52`).

Three of the wires (`vo41`-`vo43`, package targets) break the verifier's `record` rule. The loader let them through.

| probe | program | perl | chalk |
|---|---|---|---|
| v/vo02 | `my @a = (1,2,3); my @l = ((@a[0,1] = (7,8)), $a[0] = 9); print "@l\n";` | `9 8 9` | `7 8 9` |
| v/vo06 | `my @a = (1,2,3); sub z { $a[0] = 9; 0 } my @l = ((@a[0,1] = (7,8)), z()); print "@l\n";` | `9 8 0` | `7 8 0` |
| v/vo11 | `my @a = (1,2,3); my @l = ((@a[0,1] = (7,8)), (@a[0,1] = (5,6))); print "@l\n";` | `5 6 5 6` | `7 8 5 6` |
| v/vo27 | `my ($x, $y); my @l = ((($x, $y) = (7,8)), $x = 9); print "@l\n";` | `9 8 9` | `7 8 9` |
| v/vo35 | `my ($x, $y); sub z { $x = 9; 0 } my @l = ((($x, $y) = (7,8)), z()); print "@l\n";` | `9 8 0` | `7 9 0` |
| v/vo37 | `my ($x, $y); sub z { 0 } my @l = ((($x, $y) = (7,8)), z()); print "@l\n";` | `7 8 0` | `7 0` |
| v/unverified/vo41 | `our ($x, $y); my @l = ((($x, $y) = (7,8)), $x = 9); print "@l\n";` | `9 8 9` | `9 9` |
| v/vo52 | `my @l = ((my ($p, $q) = (7,8)), $p++); print "@l\n";` | `7 8 0` | `7 0` |
| v/vo58 | `my @a; my @l = ((@a = (7,8)), shift @a); print "@l\n";` | `7 8 7` | `8 7` |
| v/vo62 | `my ($x, @a); my @l = ((($x, @a) = (7,8,9)), $a[0] = 0); print "@l\n";` | `7 0 9 0` | ` 0` |
| v/vo76 | `my ($x, $y); my @m = map { $x = 0; $_ } (($x, $y) = (7, 8)); print "@m\n";` | `0 8` | `7 8` |

### 4.4 Q2 to Q5: an operand read before its consumer runs (103)

Audit 4's X7. The fix closed the fourteen probes it had and three roots. What is left:

**Q2 (56). An op hands an SV on and the rule does not know.**

```perl
our $x = 1; our $y = 1; sub c { $x = 3; 2 } my @l = (($y && $x), c()); print "@l\n";   # perl "3 2", chalk "1 2"
our $x = 1; sub c { $x = 3; 2 } my @l = (($x) x 2, c()); print "@l\n";                 # perl "3 3 2", chalk "1 1 2"
my $x = 1; my @l = do { ($x, $x++) }; print "@l\n";                                    # perl "2 1", chalk "1 1"
```

- `&&`, `||`, `//` (19 probes). `_alias_passed_through` (`lib/SoN/FromOptree.pm:26283`-`26303`) takes `$p->first`, the left operand, as the SV handed on, and builds a ternary that reads it again. The value of `$y && $x` when `$y` is true is `$x`'s SV. The wire of the first example is `TernaryExpr [$y@before, $x@before, $y@after]`: the arm perl took reads the old version.
- `x` in a list (8). `repeat` is not among the ops `$hands_sv` (`:26278`) or the function knows.
- A list that is the value of a `do` block, of a `map` body, or of a nested `do` (29). `my @l = ($x, $x++)` is right. The consumer reads its operands again through `_operand_kids` (`:26062`), which opens an ex-list and not a `scope` or `leave`. So the items of `do { ($x, $x++) }` are never operands of anything.

| probe | program | perl | chalk |
|---|---|---|---|
| v/vq106 | `my $x = 1; my $y = 1; my @l = (($y && $x), $x = 3); print "@l\n";` | `3 3` | `1 3` |
| v/vq159 | `my $x = 1; my @l = do { ($x, $x++) }; print "@l\n";` | `2 1` | `1 1` |
| v/vq166 | `my $x = 1; my ($p, $q) = do { ($x, $x++) }; print "$p$q\n";` | `21` | `11` |
| v/vq181 | `my $x = 1; sub c { $x = 5; 0 } my @l = do { ($x, c()) }; print "@l\n";` | `5 0` | `1 0` |
| v/vq192 | `my $x = 1; my @l = map { ($x, $x++) } 1; print "@l\n";` | `2 1` | `1 1` |
| v/vq78 | `our $x = 1; sub c { $x = 3; 2 } my @l = (($x) x 2, c()); print "@l\n";` | `3 3 2` | `1 1 2` |
| v/vq83 | `my $x = 1; my @l = (($x) x 2, $x = 3); print "@l\n";` | `3 3 3` | `1 1 3` |
| v/vq88 | `our $x = 1; our $y = 1; sub c { $x = 3; 2 } my @l = (($y && $x), c()); print "@l\n";` | `3 2` | `1 2` |
| v/vq89 | `our $x = 1; our $y = 0; sub c { $x = 3; 2 } my @l = (($y \|\| $x), c()); print "@l\n";` | `3 2` | `1 2` |
| v/vq96 | `our $x = 1; our $y = 1; sub c { $x = 3; 2 } my $s = ($y && $x) . c(); print "$s\n";` | `32` | `12` |
| v/vt96 | `sub f { $_[0]++; 0 } my @a = (1,2,3); my @t = map { ($_, f($_), $_) } @a; print "@t\n";` | `2 0 2 3 0 3 4 0 4` | `1 0 2 2 0 3 3 0 4` |

**Q3 (10). `++$x` as an argument.** `sub f { $_[0] . $_[1] } my $x = 1; print f(++$x, $x++)` prints `22` for perl's `32`. The wire is `Call [Add, Add]`. `_handle_entersub` passes an assignment's target as its place only where the target is an element (`lib/SoN/FromOptree.pm:6260`-`6266`, "an assignment to an element passes the element it stored"). A `my` or package scalar target is passed as the value. `my @l = (++$x, $x++)` is right: the list's operand rule knows a `++`'s target.

| probe | program | perl | chalk |
|---|---|---|---|
| v/vp100 | `my $x = 1; sub c { $x = 7; 0 } sub f { "@_" } print f(++$x, c()), "\n";` | `7 0` | `2 0` |
| v/vp120 | `our $x = 1; sub f { $_[0] . $_[1] } print f(++$x, $x++), "\n";` | `32` | `22` |
| v/vp90 | `my $x = 1; sub f { $_[0] . $_[1] } print f(++$x, $x++), "\n";` | `32` | `22` |
| v/vp92 | `my $x = 1; sub f { $_[0] . $_[1] } print f(++$x, $x = 7), "\n";` | `77` | `27` |

**Q4 (15). A magical value as an argument.** `our $t = "a"; sub c { $t = "zz"; 2 } sub id { "@_" } print id(substr($t, 0, 1), c())` prints ` 2` for perl's `z 2`. A sub's arguments are lvalues to perl: `substr` pushes a proxy read when the callee reads it, `$#a` too, and `reverse $t` in a list hands `$t` on. The wire calls the builtin before the sub call and passes its value. Seven of these wires break `read-unversioned:package` and chalk ran them.

| probe | program | perl | chalk |
|---|---|---|---|
| v/unverified/vq111 | `our $t = "a"; sub c { $t = "zz"; 2 } sub id { "@_" } print id(substr($t, 0, 1), c()), "\n";` | `z 2` | ` 2` |
| v/vq118 | `my $t = "a"; sub id { "@_" } print id(substr($t, 0, 1), $t = "zz"), "\n";` | `z zz` | `a zz` |
| v/vq123 | `my $t = "abc"; sub rd { $t = "zzz"; "$_[0]" } print rd(substr($t, 0, 1)), "\n";` | `z` | `a` |
| v/vq140 | `my @t = (1,2); sub id { "@_" } print id($#t, push(@t, 3)), "\n";` | `2 3` | `1 3` |
| v/vq144 | `my $t = "ab"; sub id { "@_" } print id(reverse($t), $t = "z"), "\n";` | `z z` | `ab z` |

**Q5 (22). `$1`.** `my $s = "abc"; $s =~ /(a)/; my @l = ($1, $s =~ /(b)/); print "@l\n"` prints `a b` for perl's `b b`. The wire's item is `RegexCapture [RegexMatch (a)]`, a value tied to the match current where `$1` stood. `_note_alias_operand` notes a `gvsv` only where the node on the stack is a memory read (`lib/SoN/FromOptree.pm:25982`-`25985`); a `RegexCapture` is not one. As a call's argument the same: `sh($1)` with a match in `sh` (`vs97`, `vs98`). Two probes are another fault: after `(my $t = "x") =~ s/(x)/y/`, `$1` is still the earlier match's (`vs116`, `vs117`). A match in a called sub, an inner block, a loop body or an `eval` does not leak into the caller's `$1`: 14 such probes are SAME (5) or refused by name (9).

| probe | program | perl | chalk |
|---|---|---|---|
| v/vs116 | `my $s = "abc"; $s =~ /(a)/; (my $t = "x") =~ s/(x)/y/; print $1, "\n";` | `x` | `a` |
| v/vs68 | `my $s = "abc"; $s =~ /(a)/; my @l = ($1, $s =~ /(b)/); print "@l\n";` | `b b` | `a b` |
| v/vs72 | `my $s = "abc"; $s =~ /(a)/; my $t = $1 . ($s =~ /(b)/); print "$t\n";` | `b1` | `a1` |
| v/vs88 | `my $s = "abc"; $s =~ /(a)(b)/; my @l = ($2, $s =~ /(c)/); print join(",", map { $_ // "u" } @l), "\n";` | `u,c` | `b,c` |
| v/vs97 | `my $s = "abc"; $s =~ /(a)/; sub sh { $s =~ /(c)/; $_[0] } print sh($1), "\n";` | `c` | `a` |
| v/vs98 | `my $s = "abc"; $s =~ /(a)/; sub sh { "q" =~ /(q)/; $_[0] } print sh($1), "\n";` | `q` | `a` |

### 4.5 Q10: promotion and constant indices (23)

```perl
my @a = (1,2); sub f { $a[-2] = 5; $_[0] } print f($a[0]), "\n";      # perl 5, chalk 1
my @a = (1,2); sub f { $a[0.5] = 5; $_[0] } print f($a[0]), "\n";     # perl 5, chalk 1
```

The wire's argument is `Subscript [@a, 0] promoted, mem_in` = the store before the call. In `f`, `Assign [Subscript [@a, -2], 5]` comes before the read of `$_[0]`.

Cause, read in the code:

- `lib/SoN/AliasProof.pm:237`: `return 0 if $e =~ /\Aelem:\Q$c\E#(.*)\z/ && $1 ne $i;`. The indices are compared as strings. `-2`, `-1`, `0.5`, `1.9`, `!1` (the empty string) and a `use constant L => -1` all differ from `0` or `1` as strings and name the same element.
- `lib/SoN/PromotedPrivate.pm:76` names an element `"$c#" . value` from the `Constant`'s value, and line 87's rule is the same. V14 passes all 22.

With `SON_NO_PROMOTE=1` all 23 print perl's answer. Hash keys are safe: `$h{1}`, `$h{"1"}`, `$h{1.0}`, `$h{01}`, `$h{+K}` and the like are SAME (18 probes, one more refused). `$a[$#a]`, `$a[@a - 1]`, `$a[1 - 1]`, `$a["0"]` are SAME.

`vt59` is the 23rd and another shape: `for my $x (@{$o->{l}}) { f($x, $o) }` with `sub f { my ($v, $s) = @_; $s->{l}[0] = 0; "$v$_[0]" }` prints `00` for `10`. The parameter record is promoted, and `$v` is read after the store through `$s`. SAME with promotion off. I did not trace which rule of `PromotedPrivate` let it pass.

| probe | program | perl | chalk |
|---|---|---|---|
| v/vp01 | `my @a = (1,2); sub f { $a[-2] = 5; $_[0] } print f($a[0]), "\n";` | `5` | `1` |
| v/vp03 | `my @a = (1,2); sub f { $a[0] = 5; $_[0] } print f($a[-2]), "\n";` | `5` | `1` |
| v/vp11 | `my @a = (1,2); sub f { $a[0.5] = 5; $_[0] } print f($a[0]), "\n";` | `5` | `1` |
| v/vp12 | `my @a = (1,2); sub f { $a["1"] = 5; $_[0] } print f($a[1.9]), "\n";` | `5` | `2` |
| v/vp13 | `my @a = (1,2); sub f { $a[!1] = 5; $_[0] } { no warnings; print f($a[0]), "\n"; }` | `5` | `1` |
| v/vp20 | `my @a = (1,2); use constant L => -1; sub f { $a[L] = 5; $_[0] } print f($a[1]), "\n";` | `5` | `2` |
| v/vp30 | `my @a = (1,2); sub f { my ($o) = @_; $a[-2] = 5; "$o$_[0]" } print f($a[0]), "\n";` | `15` | `55` |
| v/vp55 | `my @a = (1,2); sub g { $a[-2] = 5 } sub f { g(); $_[0] } print f($a[0]), "\n";` | `5` | `1` |
| v/vt59 | `my $o = {l=>[1,2]}; sub f { my ($v, $s) = @_; $s->{l}[0] = 0; "$v$_[0]" } my @t; for my $x (@{$o->{l}}) { push @t, f($x, $o) } print "@t\n";` | `10 22` | `00 22` |

### 4.6 Q11: a store to a range iterator kept in memory (15)

```perl
my @r; for my $i (1..3) { $i *= 2; push @r, \$i } print join(",", map { $$_ } @r), "\n";   # perl 2,4,6, chalk 1,2,3
```

The wire: `Assign [PadAccess $i, Phi]` at the top of each pass, `Ref [PadAccess $i] fresh_each_pass`, and `Multiply [Phi, 2]` with no consumer. Audit 4's X1 fix (`_renewed_per_pass`, `lib/SoN/FromOptree.pm:2858`) made the range iterator a memory slot when a reference is taken. An arithmetic compound assignment still only rebinds the SSA slot: `*=`, `+=`, `++`, under `if` or a modifier, in an inner loop, before or after the `\$i`, and for an outer iterator written in an inner loop. `$i = 9` and `$i .= "a"` are right. `my $x = $i; $x *= 2; push @r, \$x` is right, and so is a callee that writes `$_[0]`.

| probe | program | perl | chalk |
|---|---|---|---|
| v/vn01 | `my @r; for my $i (1..3) { $i *= 2; push @r, \$i } print join(",", map { $$_ } @r), "\n";` | `2,4,6` | `1,2,3` |
| v/vn04 | `my @r; for my $i (1..3) { push @r, \$i; $i *= 2 } print join(",", map { $$_ } @r), "\n";` | `2,4,6` | `1,2,3` |
| v/vn07 | `my @r; for my $i (1..3) { $i += 10 if $i == 2; push @r, \$i } print join(",", map { $$_ } @r), "\n";` | `1,12,3` | `1,2,3` |
| v/vn14 | `my @r; my $s = ""; for my $i (1..3) { push @r, \$i; $i += 5; $s .= ${$r[-1]} } print "$s\n";` | `678` | `123` |
| v/vn31 | `my @r; for my $i (1..2) { for my $j (1..2) { $i++; push @r, \$i } } print join(",", map { $$_ } @r), "\n";` | `3,3,4,4` | `1,1,2,2` |

### 4.7 Q8, Q7, Q9: `local` (27)

**Q8 (13). `local` through a symbolic name.** `our $x = 1; { no strict 'refs'; local ${"x"} = 2; } print "$x\n"` prints `2` for perl's `1`. The wire holds `Assign [PostfixDeref ["x"], 2]` and no `local`, no save, no restore. `_local_shape_gap` (`lib/SoN/FromOptree.pm:20447`) returns at `:20453` for an `rv2sv` whose operand is not a glob or a pad scalar, and for `local $$n` it runs to the end and returns; in neither case does a handler localize. `local @{"a"} = (7)` does not even store (`vm91` prints `1 2;1 2`). `local *{"x"}` too. This is X3 again at another op: an `OPpLVAL_INTRO` nobody read and no default GAP.

| probe | program | perl | chalk |
|---|---|---|---|
| v/unverified/vm101 | `our ($x, $y) = (1, 2); { no strict 'refs'; for my $n ("x", "y") { local ${$n} = 9; print "$x$y;" } } print "$x$y\n";` | `92;19;12` | `92;99;99` |
| v/vm84 | `our $x = 1; { no strict 'refs'; local ${"x"} = 2; } print "$x\n";` | `1` | `2` |
| v/vm86 | `our $x = 1; { no strict 'refs'; my $n = "x"; local $$n = 2; print $x } print "$x\n";` | `21` | `22` |
| v/vm91 | `our @a = (1,2); { no strict 'refs'; local @{"a"} = (7); print "@a;" } print "@a\n";` | `7;1 2` | `1 2;1 2` |
| v/vm97 | `our $x = 1; { no strict 'refs'; local *{"x"}; $x = 5 } print "$x\n";` | `1` | `5` |

**Q7 (10). `local` on a whole aggregate, in chalk.** `our %h = (a=>1); { local %h = (b=>2); } print join(",", sort keys %h)` prints `b` for perl's `a`. The wire is right: bind a new empty hash, store, bind the saved reference back. Chalk's swap (`lib/Chalk/Target/LLVM/Builder/Control.pm:426`-`453`) is followed by "a package array or hash stored whole: its one aggregate refilled in place" (`:454`). Arrays are right alone (`local @a = (7)` and 23 more forms SAME) and wrong beside a reference taken before (`my $r = \@a` reads the new array, `vm40`-`vm42`) or with `local @a = @a[0,1]` then `push` (`va13`). I did not trace further.

| probe | program | perl | chalk |
|---|---|---|---|
| v/va04 | `our %h = (a=>1); { local %h = (b=>2); print join(",", sort keys %h), ";" } print join(",", sort keys %h), "\n";` | `b;a` | `b;b` |
| v/va13 | `our @a = (1,2,3); sub f { local @a = @a[0,1]; push @a, 9; "@a" } print f(), "\|@a\n";` | `1 2 9\|1 2 3` | `1 2\|1 2 3 9` |
| v/va58 | `our %h = (a=>1); { local %h; print scalar(keys %h); $h{b} = 1 } print join(",", sort keys %h), "\n";` | `0a` | `0b` |
| v/vm16 | `our %h = (a=>1); my $r = \%h; { local %h = (b=>2); print join(",", keys %$r) } print join(",", keys %$r), "\n";` | `aa` | `bb` |
| v/vm40 | `our @a = (1,2,3); my $r = \@a; { local @a = (3); print "@$r;" } print "@$r\n";` | `1 2 3;1 2 3` | `3;3` |
| v/vm41 | `our @a = (1,2,3); my $r = \@a; { local @a = (3); push @$r, 4; print "@a;" } print "@a\n";` | `3;1 2 3 4` | `3 4;1 2 3` |

**Q9 (4). An `:lvalue` sub under `local`.** `our $x = 1; sub f :lvalue { $x } { local $x = 2; f() = 5; print $x } print "$x\n"` prints `25` for perl's `51`. The wire is `Assign [Call f, 5]` and `f` returns `EntryDef $x`. Chalk stores into the scalar `$x` named before the `local`. Not traced.

| probe | program | perl | chalk |
|---|---|---|---|
| v/va69 | `our $x = 1; sub f :lvalue { $x } { local $x = 2; f() = 5; print $x } print "$x\n";` | `51` | `25` |
| v/vm66 | `our $x = 1; sub f :lvalue { $x } sub g { local $x = 2; f() = 5; $x } print g(), "$x\n";` | `51` | `25` |
| v/vm69 | `our $x = 1; sub f :lvalue { $x } { local $x; f() = 5; } print "$x\n";` | `1` | `5` |

### 4.8 Q12 to Q18

**Q12 (6). An element reference across a whole-array assignment.** `my @a = (1,2,3); my $r = \$a[1]; @a = reverse @a; $$r = 9; print "@a\n"` prints `3 2 1` for perl's `3 9 1`. The wire: `Ref [Subscript [ArrayLiteral#5, 1]]`, then `@a` is a new `ArrayLiteral [reverse #5]`. The store goes to the old one. Perl reverses in place (`OPpREVERSE_INPLACE`, set by the peephole pass B::SoN turns off), so the scalars stay. `@a = @a` is wrong the other way: perl copies and the reference is cut loose (`1 2 3`), chalk keeps it (`1 9 3`). `shift`, `unshift`, `splice`, `sort` with such a reference are refused by name or right.

| probe | program | perl | chalk |
|---|---|---|---|
| v/vr01 | `my @a = (1,2,3); my $r = \$a[1]; @a = reverse @a; $$r = 9; print "@a\n";` | `3 9 1` | `3 2 1` |
| v/vr02 | `my @a = (1,2,3); my $r = \$a[0]; @a = reverse @a; $$r = 9; print "@a\n";` | `3 2 9` | `3 2 1` |
| v/vr05 | `my @a = (1,2,3); my $r = \$a[0]; @a = (reverse @a); $a[2] = 7; print "$$r\n";` | `7` | `1` |
| v/vr23 | `my @a = (1,2,3); my $r = \$a[1]; @a = @a; $$r = 9; print "@a\n";` | `1 2 3` | `1 9 3` |
| v/vr38 | `my @a = (1,2,3); sub el { \$_[0] } my $r = el($a[1]); @a = reverse @a; $$r = 9; print "@a\n";` | `3 9 1` | `3 2 1` |

**Q13 (18). A dereferenced array in a list.** `my %h = (a=>[1,2]); my @l = (@{$h{a}}, "x"); push @{$h{a}}, 3; print "@l\n"` prints `1 2 3 x` for perl's `1 2 x`. The wire's item is `PostfixDeref @ mem_in=7`, a version before the `push`. Chalk reads the array when the list is used. A named array is right (`my @l = (@a, @b); push @a, 3`); `my @l = (@{$h{a}})` alone is right.

| probe | program | perl | chalk |
|---|---|---|---|
| v/vq43 | `my $o = [1]; sub c { push @$o, 9; 0 } my @l = (@$o, c()); print "@l\n";` | `1 0` | `1 9 0` |
| v/vq49 | `my %h = (a=>[1,2]); my @l = (@{$h{a}}, 0); push @{$h{a}}, 3; print "@l\n";` | `1 2 0` | `1 2 3 0` |
| v/vq53 | `my %h = (a=>[1,2]); my @l = (@{$h{a}}, "x"); $h{a}[0] = 9; print "@l\n";` | `1 2 x` | `9 2 x` |
| v/vq55 | `my %h = (a=>[1,2]); my @l = (@{$h{a}}, "x"); pop @{$h{a}}; print "@l\n";` | `1 2 x` | `1 x` |
| v/vq77 | `my %h = (a=>[1,2]); my @l = (@{$h{a}}, scalar(@{$h{a}})); push @{$h{a}}, 3; print "@l\n";` | `1 2 2` | `1 2 3 2` |

**Q14 (9). `delete` of a slice.** `my %h = (a=>1,b=>2,c=>3); my $k = [qw(b c)]; delete @h{@$k}; print join(",", keys %h)` prints `a,b,c` for perl's `a`. `lib/SoN/FromOptree.pm:11008`-`11014` makes one `Delete` per operand on the stack. An operand that is a list (`@$k`, a `grep`, a `map`, `@_`, a call) is one key. Literal keys and a `my @k` of literals (folded) are right.

| probe | program | perl | chalk |
|---|---|---|---|
| v/vr106 | `my %h = (a=>1,b=>2,c=>3); my $k = [qw(b c)]; delete @h{@$k}; print join(",", keys %h), "\n";` | `a` | `a,b,c` |
| v/vr107 | `my %h = (a=>1,b=>2,c=>3); sub ks { qw(b c) } delete @h{ks()}; print join(",", keys %h), "\n";` | `a` | `a,b` |
| v/vr119 | `my %h = (a=>1,b=>2,c=>3); my @k = qw(b c); my $l = delete @h{@k}; print "$l", scalar(keys %h), "\n";` | `31` | `231` |
| v/vr122 | `my %h = (a=>1,b=>2,c=>3); sub cl { my ($r, @k) = @_; delete @$r{@k} } cl(\%h, "b", "c"); print join(",", keys %h), "\n";` | `a` | `a,b,c` |
| v/vr96 | `my %h = (a=>1,b=>2,c=>3); my @big = grep { $h{$_} > 1 } sort keys %h; delete @h{@big}; print join(",", keys %h), "\n";` | `a` | `a,b,c` |

**Q15 (5). A foreach over a slice with a range.** `my @a = (1,2,3); $_ *= 2 for @a[1..$#a]; print "@a\n"` prints `1 2 3` for perl's `1 4 6`. The wire: `ArrayLiteral [Slice [Range, @a]]`, and the body stores into `Subscript` of that literal, a copy. The slice with constant bounds, with `@i`, and `map` or `grep` over it are refused by name; the same loop over a package array or `@$r` is right.

| probe | program | perl | chalk |
|---|---|---|---|
| v/vj49 | `my @a = (1,2,3); $_ *= 2 for @a[1..$#a]; print "@a\n";` | `1 4 6` | `1 2 3` |
| v/vr65 | `my @a = (1,2,3); $_ *= 2 for @a[1..$#a]; print "@a\n";` | `1 4 6` | `1 2 3` |
| v/vr68 | `my @a = (1,2,3); for my $e (@a[1..$#a]) { $e *= 2 } print "@a\n";` | `1 4 6` | `1 2 3` |
| v/vr69 | `my @a = (1,2,3); for (@a[0..$#a]) { $_++ } print "@a\n";` | `2 3 4` | `1 2 3` |
| v/vr78 | `my @a = (1,2,3); $_ = 0 for @a[1..$#a]; print "@a\n";` | `1 0 0` | `1 2 3` |

**Q16 (14). A call's list in a hash literal.** `sub f { return } my %h = (a => f(), b => 1);` gives chalk `{a => undef, b => 1}` for perl's `{a => "b", 1 => undef}`. A call that returns two values is one item too (`vs132`). The wire is right (`Return [list (), scalar undef]`, `want=list`). `sub f { my $x = shift; $x ? ($x) : () } my @l = (f(0), f(2), f(0))` prints `0 2 0` for `2`. `my @l = (f(), f())` and `[f(), 1, f()]` are right.

| probe | program | perl | chalk |
|---|---|---|---|
| v/vs120 | `sub f { return } my %h = (a => f(), b => 1); print join(",", map { "$_=" . ($h{$_} // "u") } sort keys %h), "\n";` | `1=u,a=b` | `a=u,b=1` |
| v/vs128 | `sub f { my @e; @e } my %h = (a => f(), b => 1); print join(",", map { "$_=" . ($h{$_} // "u") } sort keys %h), "\n";` | `1=u,a=b` | `a=0,b=1` |
| v/vs132 | `sub f { return (1, 2) } my %h = (a => f(), b => 1); print join(",", map {"$_$h{$_}"} sort keys %h), "\n";` | `1,2b,a1` | `a2,b1` |
| v/vs149 | `sub f { my $x = shift; $x ? ($x) : () } my @l = (f(0), f(2), f(0)); print "@l\n";` | `2` | `0 2 0` |
| v/vs151 | `package O; sub m { return } package main; my %h = (a => O->m, b => 1); print join(",", map { "$_=" . ($h{$_} // "u") } sort keys %h), "\n";` | `1=u,a=b` | `a=u,b=1` |

**Q18 (4). `\(my $v = 1)`.** The wire is `Ref [Constant 1]`: a reference to the assignment's value. `my $r = \(my $v = 1); sub c { $v = 9; 0 } my @l = ($$r, c())` prints `1 0` for perl's `9 0`. A store through `$r` is LOUD ("Modification of a read-only value", 3 probes).

| probe | program | perl | chalk |
|---|---|---|---|
| v/vq01 | `my $r = \(my $v = 1); sub c { $v = 9; 0 } my @l = ($$r, c()); print "@l\n";` | `9 0` | `1 0` |
| v/vq02 | `my $r = \(my $v = 1); sub c { $v = 9; 0 } my $s = $$r . c(); print "$s\n";` | `90` | `10` |

**Q17 (2). Two singles I did not map.**

| probe | program | perl | chalk |
|---|---|---|---|
| v/vt48 | `our @a = (1,2,3); sub f { $a[0]++; $_ } my $t = ""; for (@a) { $t .= f() } print "$t\n";` | `223` | `123` |
| v/vt87 | `sub f { $_[0]++; 0 } my @t; for my $i (1..3) { my $y = $i; push @t, "$y" . f($y) . "$y" } print "@t\n";` | `102 203 304` | `202 303 404` |

In `vt87` the wire is right (`Coerce [PadAccess $y mem_in=before the call]`); chalk makes the read after the call.

## 5. Recommendations, ranked

1. **Q1: read `OPpTARGET_MY` on `stringify`** (`FromOptree.pm:13546`), and make an op with `OPpTARGET_MY` that no handler stored a GAP. It is the plainest program in this report. 20 wrong.
2. **Q10: an index that is not a non-negative integer constant is "not known"** in `AliasProof.pm:237` and `PromotedPrivate.pm:76`. Add mutation cases with `-1` and `0.5`. 22 wrong.
3. **Q6: push the targets as places, or refuse.** Where any later item or the consumer may store a target, the value of a list assignment in a list is not its values now. Refuse the mix with a call until places are pushed (`FromOptree.pm:13500`). 55 wrong.
4. **Q2 to Q5: one table of what each op hands on.** `&&`/`||`/`//` hand on either operand; `x`, a block's last statement whatever it is, `reverse`, an assignment and `++` hand on their operand or target. `$1`, `substr` and `$#a` are read by the consumer. Default for an op with no row: refuse where a later operand may store. 103 wrong.
5. **Q8 and the default GAP.** Audit 4's recommendation 3 again: an op carrying `OPpLVAL_INTRO` that no handler localized is a GAP. 13 wrong.
6. **Q11: a variable in memory has no SSA binding of its own.** Route every store to a demoted iterator through the slot. 15 wrong.
7. **Q14, Q15: refuse a `delete` slice or a foreach slice whose index list is not a list of scalars.** 14 wrong.
8. **Chalk: Q7, Q13, Q16, Q9, Q17.** `local` on a hash; a versioned read through a reference is a copy; a call's list in a hash literal has its own length. 48 wrong.
9. **Q12, Q18: refuse a whole-array assignment while an element reference is live; `\(my $v = ...)` is a reference to `$v`.** 10 wrong.
10. **The loader should refuse what the verifier rejects.** Ten wrong wires broke `read-unversioned` or `record` and were compiled. Either port the two rules to `WireInvariant` or run `SoN::Verify` in the harness before chalk.
11. **A generator in the gate.** Section 2. Each audit finds the same rate. Hand-written probes will not end this.
12. Still open from audit 4: sources as memory slices on the wire.

## 6. What was not checked

- Neither full suite, the census, the corpus gate, the deparser round trip, nor the chalk-lib ratchet. The gate numbers in section 1 are the ones handed to this audit. The gated probe sweep was not re-run.
- Chalk's lowering was not traced for Q7 (beyond the two sites named), Q9, Q13, Q16, Q17. "Side: chalk" there means only that the wire of one probe says what perl does.
- Root causes were confirmed by reading one probe's wire per class and the code at the lines given. Only Q1 was traced op by op (an instrumented copy of the producer in a scratch directory; not committed).
- `vt59` (Q10) was not traced to a rule.
- The skill `i-have-adhd` named in `CLAUDE.local.md` cannot be loaded by a model in this session and was not.
