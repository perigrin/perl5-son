# Audit of the finished goal "Make the SoN memory model mechanical and checked, measured" (2026-11-22)

Producer `/home/user/repo`, `wip/chalk-lib-roundtrip`, ae71279. Chalk `/home/perigrin/dev/chalk`, `bson/llvm-corpus`, 287e5da1. Independent, read-only: no code was changed in either repo. A wire line `9 Assign [8,4,6,8] ^7 m7 OUT` means node 9, inputs, `control_in` 7, `mem_in` 7, `mem_out`.

**Bottom line.** The gates the goal names are met, and I reproduced the ones that are cheap. The wire really is v2, the deletions are real, and every one of the audit's 418 probes is right or refused. But the goal's first sentence is not met: the memory model is not yet "checked" in the sense the audit asked for.

- 12 hand-made breakages of good wires were tried against the verifier and the loader. The verifier caught 0 of them and the loader 2.
- About 290 new one-line probes found 55 silent wrong answers (variants of about nine distinct defects). Every one of their wires passes `SoN::Verify` clean.
- 3 of the 55 were refused at the audit's commits and are wrong now.
- The rest were already wrong at the audit's commits. They are neighbours of classes the goal lists as closed (W2, W6, W7, W8, W9, W10).

## 1. Verdict per clause

| clause | verdict | what holds | what does not |
|---|---|---|---|
| (1) No silent wrong answers from the audit | **Met to the letter, not in substance** | All 254 probes right at the audit are SAME today. Of the audit's 69 wrong: 56 SAME, 11 REFUSED, 2 LOUD. Sweep re-run here: LOUD 2, REFUSED 97, SAME 434, WRONG 0. | The classes are closed only for the probe shapes. 55 new wrong answers in the same classes (section 2). 25 refusals are recorded as "no program graph", with no name. 11 chalk probes are not beside the audit's. No probe was added to the producer's directory for stages 8 to 10. |
| (2) Producer placement is mechanical | **Mostly met** | `_pin` / `_place` / `_call_memory_barrier` are the only placement; `_target_storage` decides by kind and sigil; package scalars read through memory (W1 probes right, and 10 of 11 new variants, the other refused); dynamic method call and may-fault `Divide` / `Modulo` pinned; `B::SoN::EffectTable` exists. | The table is an allow-list: a builtin with no row is pure. `log(0)` and `sqrt(-1)` die in perl and are dropped. A void `keys %h` floats and never runs. A `die` ending a loop body is not emitted at all. The source test that holds "one constructor" matches one spelling only. |
| (3) Wire v2 | **Met, with three gaps** | `mem_in` / `mem_out` on the wire, inputs are values, `Exc` and catch Region, `Loop [entry, back]` with an `If`, no scouts; chalk has no `Phi::is_memory`, `Assign::is_placed`, `memory_input`, `WireUpgrade` (grep: 0 hits in `lib/`). | `record` is not a flag the producer sets: the serializer derives it from "on neither chain". The eval's normal way out carries no `local` restore. "Without the double walk" holds only while every guess holds; a wrong guess re-translates the whole sub. Positional memory survives in the producer (`SoN::Wire::as_v1`, `%MEM_MIN_INPUTS`, for the deparser). |
| (4) Checked | **Met as worded, weak as a check** | `SoN::Verify` runs in both suites; corpus and probes re-run here: PASS, one held. Loader invariant L0 to L9 exists and its test passes. | "Every write is reachable" is checked only for nodes that already say `mem_out`. "Every read names a version" skips a memory-kept `my` scalar and any builtin with no table row. Rule V10 (exceptional edges) was never written. The loader skips every check for a wire with no `dowarn` key. Three violations are held by name, so "passes" is not zero. |
| (5) Verified and pushed | **Met on the record; partly reproduced** | `tools/gates.sh` in both repos; `origin/wip/chalk-lib-roundtrip`, `origin/bson/llvm-corpus` and both `origin/pu` are at the audited heads (local tracking refs). Probe gate and ratchet (corpus, probes) re-run here and equal to the record. | Not re-run here: both full suites, the census (426), the corpus gate (223), the verifier over chalk's lib. Those numbers are the baseline note's section 16. |

## 2. New silent wrong answers found by this audit

Run as the probe gate runs: B::SoN, chalk T2, `lli`, against perl. "Base" is the audit's commits (producer c205256, chalk c1a48dfe), extracted with `git archive`. `SoN::Verify` is clean on every wire below.

| class | program | perl | chalk | at base |
|---|---|---|---|---|
| W6: a `local` in an eval that ends normally is never put back | `our $g=1; eval { local $g = 2; 1 }; print "$g\n";` | `1` | `2` | wrong |
| W6 | `our $g=1; my $r = eval { local $g = 2; 5 }; print "$g $r\n";` | `1 5` | `2 5` | wrong |
| W6 | `our $g=1; eval { local $g = 2; f() }; sub f { 1 } print "$g\n";` | `1` | `2` | wrong |
| W6 | `use feature 'try'; our $g = 1; try { local $g = 2; } catch ($e) { } print "$g\n";` | `1` | `2` | wrong |
| W7: a `die` that ends a loop body is not on the wire | `for my $x (1) { die "m\n" } print "after\n";` | dies | `after`, exit 0 | wrong |
| W7 | `eval { my $i = 0; while ($i < 3) { $i++; die "w$i\n" } }; print "[$@]\n";` | `[w1` | `[]` | wrong |
| W7 | `sub t { for my $x (1) { die "t\n" } "end" } print eval { t() } // "died", "\n";` | `died` | `end` | wrong |
| W7 | `eval { die "a\n" for 1; }; print "[$@]\n";` | `[a` | `[]` | wrong |
| W7, **regressed** | `eval { my @a = map { die "m\n" } 1; }; print "[$@]\n";` | `[m` | `[]` | REFUSED |
| W7, **regressed** | `our $g=1; eval { my @a = map { die "m\n" } 1; }; print "$g [$@]\n";` | `1 [m` | `1 []` | REFUSED |
| W7: a builtin that faults | `my $z = @ARGV; my $x = log($z); print "after\n";` | dies | `after` | wrong |
| W7 | `my $n = 0; eval { $n = 1; my $z = @ARGV; my $x = log($z); $n = 2 }; print "$n\n";` | `1` | `2` | wrong |
| W2: a list assign with one target in memory | `my ($x,$y)=(1,2); my $r=\$x; ($x,$y)=($y,$x); print "$x $y\n";` | `2 1` | `2 2` | wrong |
| W2 | `my ($x,$y,$z)=(1,2,3); my $r=\$y; ($x,$y,$z)=($z,$x,$y); print "$x $y $z\n";` | `3 1 2` | `3 1 1` | wrong |
| W10: a `my` aggregate flattened beside a call that grows it | `my @a=(1); my $f = sub { push @a, 2; 0 }; my @c = (@a, $f->()); print "@c\n";` | `1 0` | `1 2 0` | wrong |
| W10 | `my @a=(1); sub w { push @a, 2; 0 } my @c = (@a, w(), @a); print "@c\n";` | `1 0 1 2` | `1 2 0 1 2` | wrong |
| W10 | `my %h=(a=>1); my $f = sub { $h{b} = 2; 0 }; my @c = (%h, $f->()); print scalar(@c), "\n";` | `3` | `5` | wrong |
| `$_` alias written by a callee | `my @l = (1,2); for (@l) { inner(); } sub inner { $_ = 9 } print "@l\n";` | `9 9` | `1 2` | wrong |
| same, package array | `our @l = (1,2); for (@l) { inner(); } sub inner { $_ = 9 } print "@l\n";` | `9 9` | `1 2` | wrong |
| W8: DESTROY reached by inheritance | `package B1; sub DESTROY { print "d\n" } package K; our @ISA = ("B1"); package main; { my $x = bless {}, "K"; } print "e\n";` | `d e` | `e` | wrong |
| W8: DESTROY through AUTOLOAD | `package P; sub AUTOLOAD { print "auto\n" } package main; { my $x = bless {}, "P"; } print "e\n";` | `auto e` | `e` | wrong |
| W9: autovivification | `my %h; my $x = $h{a}{b}; print scalar(keys %h), "\n";` | `1` | `0` | wrong |
| W9 | `my @a; my $x = $a[1]{k}; print scalar(@a), "\n";` | `2` | `0` | wrong |
| W9 | `my %h; print "y\n" if $h{a}{b}; print scalar(keys %h), "\n";` | `1` | `0` | wrong |
| W9 | `sub cfg { my $c = shift; return $c->{opt}{verbose} ? 1 : 0 } my %c; cfg(\%c); print join(",", keys %c), "\n";` | `opt` | (empty) | wrong |

The table shows 25 of the 55; the others are variants of the same rows. The third regression is the `map`-die row with a `local` before it.

Whose fault each is, read from the wires:

- **W6, normal end of an eval: producer.** The restore is built only on `Exc` edges. The normal way into the join has `local $g = 2`, then `$@ = ""`, then the Region. The saved value (`EntryDef m9`) is built and unused.
- **W7, die ending a loop body: producer.** The wire has no `Unwind`. The body `Proj` is the back edge.
- **W2, mixed targets: chalk.** The wire is right: `9 Assign [8,4,6,8] ^7 m7 OUT`, where node 8 is `$x` read at version 7 and is also the target. chalk makes that floating read after the store.
- **`$_` alias: not settled.** The wire has `LocalAlias ^25 m4` (no `mem_out`) then the call. The callee stores to `$main::_`. Either consumer or producer could be argued; it is the node kind the verifier holds out by name.
- **W8, W9: chalk's refusals are too narrow.** W8 matches a `bless` whose constant class equals the `DESTROY`'s package (`WireCheck.pm:240-251`). W9 fires only where B::SoN stamped the container `Undef` (`WireCheck.pm:112-122`).

## 3. What the verifier and the loader catch (mutation test)

Good wires from this producer, broken by hand, then given to `SoN::Verify::verify` and `Chalk::IR::Serialize::WireInvariant::check`.

| # | breakage | verifier | loader |
|---|---|---|---|
| M1 | a list assign to an address-taken `my` scalar taken off both chains (the serializer then calls it `record`) | clean | clean |
| M2 | an `Assign` with `control_in` and `mem_in` but no `mem_out` | clean | L5 |
| M3 | a `push` on no chain | clean | clean |
| M3b | a `push` pinned, with `mem_in`, no `mem_out` | clean | clean |
| M4 | a read of a memory-kept `my $x` with no `mem_in`, value used | clean | clean |
| M5 | a floating read naming an older version than the one current at its use | clean | clean |
| M6 | a `Print` on no control chain | clean | clean |
| M7 | a may-fault `Divide` floating (the audit's fl1) | clean | clean |
| M8 | a call in an eval under a `local` with no `Exc` edge (the audit's lo2) | clean | clean |
| M9 | an `Exc` edge with its `local` restore removed | clean | clean |
| M10 | a sub call with `mem_in` but no `mem_out` | clean | L5 |
| M11 | a builtin with no `EffectTable` row, floating, no `mem_in` | clean | clean |
| C1 | control: `Return` with no `mem_in` | V2, V3 | L3 |
| C2 | control: last store unreachable from the `Return` | V3, V5 | L4 |
| C3 | control: a package scalar read with no `mem_in` | V6 | clean |
| C4 | control: a floating `Assign` through a reference, not flagged | V2 | L5 |
| C5 | control: the same, flagged `record` | V7 | clean |

Why each is missed, in `lib/SoN/Verify.pm`:

- **M1.** `_target_class` (`:86`) tells a memory-kept `my` scalar by `inputs` or `shared`. On v2 that place has `mem_in` and no inputs, so it is `ssa-scalar` and V7 allows the record. `lib/SoN/Serialize/JSON.pm:218` writes `record` for any `Assign` with no `control_in` and no `mem_out`. A floating store is therefore a record by construction. This is the audit's departure 6 turned round.
- **M2, M10.** V2 (`:191-204`) asks `mem_out` only of `%WRITE` kinds and `version` builtins. `Assign` and sub calls are asked only for `mem_in`.
- **M3, M3b.** `push`, `pop`, `shift`, `unshift`, `splice`, `each`, `undef`, `chomp`, `chop` are `%OWN_HANDLER` in the effect table and have no `version` column. `RegexSubst`, `Transliterate`, `Chomp`, `LocalAlias` are not in `%WRITE`.
- **M4.** `$place_class` (`:329`) returns `undef` for a scalar `PadAccess` unless `shared`.
- **M5.** Nothing checks that a floating read's version is one its users can still see. See 5.1.
- **M6, M7.** The v1 rules `effect-rides-value` and `fault-floating` were deleted in stage 6, and chalk's `_floating_effects` and `_floating_divisions` with them. Nothing replaced them for nodes that are not versions.
- **M8, M9.** V10 is not written (plan, stage 8: "V10 (`exc`) is not written"). L7 checks only that a catch Region's inputs lead back to an `Exc`.
- **M11.** `reads_state` of an unknown name is `undef`: not a read.

## 4. The 2026-11-19 audit's findings, one by one

Status: **fixed**, **refused** (by name), **narrow** (fixed or refused for the probe's shape, still wrong beside it), **open**, **regressed**.

### 4.1 The ten wrong-answer classes

| class | status | evidence |
|---|---|---|
| W1 package scalar carried round a loop (11) | fixed | 10 SAME, tp7 refused by B::SoN (string range). 11 new variants (nested loops, `map`, `do-until`, `redo`, code ref, symbolic ref): 10 right, 1 refused. `_key_lives_in_memory`, `FromOptree.pm:14297`. |
| W2 list assign whose store floats (15) | narrow | 14 SAME, ar12 refused. Mixed memory and SSA targets wrong (section 2). |
| W3 dynamic method call off the chain (2) | fixed | dyn1, dyn2 SAME; `FromOptree.pm:5620-5630`; in a loop: right. |
| W4 `ref` / `blessed` at no version (8) | fixed | 8 SAME; 5 new variants (loop, callee, `isa`, redispatch after `bless`) right. |
| W5 `@_` alias of a captured variable (3) | refused | `WireCheck::_captured_arguments_written`. |
| W6 `local` not put back (3) | narrow | lo2, lo3, lo16 SAME. Normal end of an eval wrong (section 2). A call dying under a `local` in a sub with no eval: refused (`_calls_a_local_dies_through`), but only when the program has an eval. |
| W7 faults and exceptions (8) | narrow, and regressed beside it | fl1, fl6, ex1 to ex4, ev6 SAME; fl5 refused. A `die` ending a loop body, and `log` / `sqrt`, wrong. The `map`-die shape went REFUSED to WRONG. |
| W8 `DESTROY` (2) | narrow | ca29, im6 refused. Inherited or AUTOLOADed `DESTROY` wrong. |
| W9 autovivification (1) | narrow | fl11 refused. The common shape `my %h; $h{a}{b}` wrong. |
| W10 package aggregate flattened at no version (6) | narrow | 6 SAME. The same shape on a `my` aggregate beside a call wrong. |
| hash truth, `my $n = %h` (m4, ht1, ht2, st10) | fixed | 4 SAME; 7 new variants right. |
| dropped stores `($a[0],$c)=(5,6)`, captured `($x, my $y)` | fixed | both right as new probes. |
| set aside (im23, ar17, fl10, fl14, vp5, io8) | as before | LOUD 2, SAME 2, refused by B::SoN by name 2. |

### 4.2 The departures table

| # | departure | status | evidence |
|---|---|---|---|
| 1, 2, 14, 19 | one chain; node as version; I/O on control; call is a barrier | kept | sound, as the audit said |
| 3 | `Assign` and sub `Call` take no memory | fixed | `mem_in` on both; V2, L5 |
| 4 | `Return` takes no memory | fixed | V2, L3 |
| 5 | writes pinned by hand | fixed, weakly held | `_pin` / `_place` at `FromOptree.pm:851-876`. `t/placement-one-constructor.t` matches only `->set_control_in($x->control)`; `:3297`, `:4857`, `:4975` set `control_in` by hand and are not seen (the two Return sites are deliberate). |
| 6 | records that look like stores | open in a new form | the flag is derived (`JSON.pm:218`); M1 |
| 7 | reads with no version | fixed for the listed classes | V6 hard; M4, M11 are its holes |
| 8 | package scalar as a loop value Phi | fixed | W1 |
| 9 | effects riding value edges | narrow | table rows pinned; unknown builtins default to pure; void `keys` floats (T2 refuses: "B::SoN places them nowhere") |
| 10, 11 | pinned reads as versions; one node three roles | fixed on the wire | chalk still answers by class in places: `is_memory_version { 1 }` in `Assign.pm:13`, `EntryWrite.pm:13`, `CellWrite.pm:26`, `Delete.pm:13`, `ElemRestore.pm:14`; `WireCheck::_follows_memory` is a kind list |
| 12 | no verifier | fixed, shallow | sections 3 and 5 |
| 13 | `local` restore on listed exits only | narrow | W6 |
| 15, 16 | Loop is Region plus If; no back edge | fixed | V11, L8; `t/wire-a-loop-has-a-back-edge-and-an-if.t` |
| 17 | scout double walk | fixed, with a fallback | scouts gone (grep: comments only); a wrong guess re-translates the sub (`%LOOP_HINTS`, `:14430`, `:24694`) |
| 18 | `redo`, backward `goto` refused | open (out of scope) | |
| 20 | dynamic method call not pinned | fixed | W3 |
| 21 | arguments are values | open | W5 refused; `LocalAlias` held |
| 22 | eval join without a catch edge | fixed in shape | `Exc`, catch Region; unverified (V10) |
| 23 | `Divide` / `Modulo` float | fixed | `_may_fault`, `:908`; 11 new division probes right, including guarded ones that must not fault |
| 24 | pinned unread may-die read skipped | refused | fl5, `_unread_derefs` |
| 25 | `die` of a reference stringified | fixed | ex1 to ex4 |
| 26 | `DESTROY` | narrow | W8 |
| 27 | pinned hash-consed nodes | guarded | `_pin` refuses a second pin (`:866`). One node is still place and read at once (the W2 wire above). |
| 28 | type guess decides pinning | fixed for targets | `_target_storage`, `:22359`. Values still go by stamp: `_is_aggregate_node` has 15 uses, `_flattens` among them. |
| 29 | autovivifying read is not a write | narrow | W9 |

## 5. The design against the literature

### 5.1 Click: sea of nodes, memory edges, memory Phis, alias classes

**Matches.** A write consumes a memory state and produces the next; a read consumes one; Phis merge states at Regions and loop headers; a call takes and gives memory. Naming the edge (`mem_in`) instead of a positional input is libFIRM's typed edge, and it is what makes a per-node rule possible.

**Departs, soundly.**

- **One alias class.** C2 slices memory by alias index and merges with `MergeMem`. One slice is the conservative end: every store kills every read. No wrong answer can come from it.
- **No projections.** A call is its value and the memory after it; the referring edge says which. This is sound because the two edge kinds are disjoint on the wire (V8, L9).

**Departs, unsoundly.**

- **Floating reads have no anti-dependence.** In Click's scheduler a `Load` gets an anti-dependence edge to every `Store` that overwrites its memory state, so it is scheduled before them. Here a floating read names a version and nothing forces a consumer to make it before the next store. chalk does it by flushing (`reads_before`, 30 uses), which is a per-shape rule. The W2 row of section 2 is exactly a load scheduled after the store that kills it. This cannot be checked on the wire: it is a property of the consumer. Either reads that outlive their version are pinned by the producer, or chalk checks at lowering that a read at version V is made before any successor of V.
- **A place and a read are one node.** The plan (3.3) says a place has no `mem_in`. In the wire above the target of the `Assign` has `mem_in` and is also the right-hand value. The verifier's place-or-read split is by use, so it accepts this, but "this node is a load" is no longer a fact a consumer can read off the node.
- **`LocalAlias` creates an alias and is not a version.** After it, a store to `$_` is a store to an element. A callee's store to `$main::_` and the caller's read of the array are related only through that node, and it carries no `mem_out`.

### 5.2 Braun et al. 2013

**Matches.** Incomplete Phis at an unsealed header, memory as one more variable (`#mem`), operands appended at sealing, trivial Phis forwarded and not written (V8 `phi-trivial`).

**Departs.**

- **A may-write filter instead of lazy Phis.** Phis are made for a syntactic over-approximation, not on first read. Sound: a superfluous key costs a trivial Phi.
- **A wrong guess restarts the sub.** Braun never re-walks. Here a missed key, a failed stamp or a missed iterator write is recorded and the whole sub is translated again. It is sound as long as the sealing check catches every wrong guess, and it does not double per nesting level (depth 14 under 2 s). But `t/loop-body-is-walked-once.t` chooses a nest whose stamps hold, so "walked once" is proved for the good case only. Stage 0 measured 34 failing loops in 2059.
- **Trivial Phis are found one at a time.** V8 flags a loop Phi whose other inputs are one node. Braun's own algorithm also leaves redundant Phi cycles in some graphs; neither the producer nor V8 looks for them. This costs precision, not correctness.

### 5.3 Exceptional control flow (HotSpot C2, Graal)

**Matches.** Graal's `InvokeWithException` has a normal successor and an exception edge whose first node is the exception object. `Exc [T]` is that: a control node that is also the exception in flight, one per node that may die, merged at a catch Region, with the unwinding work (the `local` restores, the `$@` store) as ordinary nodes on the edge. One edge per thrower is the right choice: it is the only way to say which `local`s were live.

**Departs, unsoundly or incompletely.**

- **The normal edge has no cleanup.** In every IR with explicit unwinding, scope-exit work stands on both edges. Here the restores stand only on the exceptional one, so an eval that completes leaves its `local`s in place (section 2). This is the plainest defect found.
- **What may throw is a short list.** C2 and Graal derive "may throw" from the bytecode's semantics for every node. Here it is sub calls, `Unwind`, and values named in `_dies_by_its_values` (`PostfixDeref`, `Ref`, `Divide`, `Modulo`). `log`, `sqrt` and the comparator of a `sort` are not on it. A thrower not on the list gets no edge and, if its value is unused, is not emitted.
- **A terminal `die` in a loop body is lost** before any edge could be made for it.
- **No frame for a throw that leaves the sub.** A call that dies under a `local` in a sub with no eval needs a rethrow pad (the plan's Q9). It is refused by chalk, by a rule that runs only when the program contains an eval.
- **Unverified.** V10 does not exist, so none of the above is visible to the verifier (M8, M9).

### 5.4 Memory SSA (LLVM) and MOD/REF sets

**Matches.** The wire is MemorySSA made primary: a write is a `MemoryDef` whose operand is the previous access, a read is a `MemoryUse`, a memory Phi is a `MemoryPhi`, over one heap. V5 is MemorySSA's ordering check (the defining access is the nearest one back along control) for pinned nodes. `SoN::FromOptree::ModSets` is a classical flow-insensitive, transitive MOD summary per sub, with an explicit unknown (`U`) that turns into a refusal.

**Departs.**

- **MemorySSA is verified against the instruction order; this has no order to verify against.** In LLVM the IR is the truth and MemorySSA an overlay that can be recomputed and compared. Here the chain is the only statement of order, and the optree is gone. So the verifier can prove the wire is well-formed, never that it is the program. Every dropped effect in section 2 has a clean wire.
- **A floating use is not checked for dominance.** MemorySSA checks that a use is dominated by its defining access. V1 checks only that `mem_in` names a version (M5).
- **External state is on the chain but its writers are not versions.** `time`, `rand`, `-e` take `mem_in`; `sleep`, `srand`, `unlink` are ordered by control and make no version. So `my $t0 = time; sleep 1; my $t1 = time` has both `time` nodes at `MemStart`, and `srand(1); rand; srand(1); rand` has both `rand` nodes unordered against either `srand`. The wires are wrong and verify clean. chalk refuses these programs today because T2 does not lower a statement `sleep` or `srand`, not because of the ordering.
- **MOD sets are used for one question only** (may a later call store an operand perl reads by alias), and only for elements. The same question for a whole aggregate operand is not asked (the W10 rows). The module's own `shortcut:` note says implicit calls (overloading, tie, `DESTROY`) are not seen. There are no REF sets; none are needed while a call is a full barrier.

## 6. The held-by-name list

| held | where | justified? |
|---|---|---|
| probe pl13 `main::sw` (V7 `record`) | both `%HELD` tables | **Yes.** The stores are real `EntryWrite`s on the chain; the `Assign` is only the list's value. T2 refuses the program by name. |
| `DynaLoader::bootstrap`, `bootstrap_inherit` (V7 `record`) | both `%HELD` tables | **No.** The reason given is "not traced yet". It is a floating `Assign` of `@isa`, the exact defect the audit said hides in library code. An unexplained violation should fail, or be refused, until traced. |
| `LocalAlias` left out of the store kinds | `SoN/Verify.pm:58-63` | **No.** The stated reason ("a callee's reads are in its own graph") is the hole: a callee that writes `$_` gives a wrong answer (section 2). |
| a wire with no `dowarn` skips the invariant and `WireCheck` | chalk `JSON.pm:1314`, `:1417` | **Weak.** It is meant for chalk's own graphs, but it is keyed on an unrelated field. Any wire that lacks the key is unchecked. |
| an `:lvalue` call off both chains | `WireInvariant.pm:118-121` | Yes. One use, the `Assign` that stores through it. |
| V10 not written | plan, stage 8 | **No.** It is the only rule for the eval edge. |
| 25 probes recorded "no program graph" | chalk `BASELINE.tsv` | **Weak.** B::SoN names each refusal on stderr; the wire and the baseline do not carry the name, so a refusal that changes cause is not seen. |

## 7. Remaining risks, ranked

1. **A `die` that ends a loop body never happens.** `for (...) { ...; die }` runs on. In or out of an eval, in a sub or not. It is everyday code (validation loops), silent, verifier-clean, and present at the audit's commits too.
2. **A `local` in an eval that completes is never restored.** `eval { local $x = ...; work() }` is the standard idiom (`local $@`, `local $SIG{ALRM}`, `local $_`). Silent, verifier-clean, and inside the construct stage 8 rebuilt.
3. **The verifier does not check what the goal says it checks.** It trusts `mem_out`, derives `record`, has no rule for the eval edge, and treats an unknown builtin as pure (12 of 12 breakages pass). A future producer change that floats a `push`, a `Print`, a division or a memory `my` store will pass every gate unless a probe happens to cover it.
4. **A floating read can be made after the store that kills it.** Nothing on either side enforces the version a read names. Proven for a list assign with mixed targets; the same mechanism is behind the stage 6 and 7 wrong answers (`is_placed`, rv8 to rv12). More shapes are likely.
5. **The refusals for W8 and W9 are shape matches, and the fix for W10 is one storage class.** Autovivifying reads, inherited `DESTROY`, and `my` aggregates beside a call are wrong today. Autovivification in particular is in almost any real program.

Further down:

6. Dead faulting builtins (`log`, `sqrt`) are dropped; the three `map`-die shapes moved from refused to wrong.
7. A callee's write through `$_` in a `foreach` block is lost.
8. External-state wires are wrong and protected only by unrelated T2 refusals.
9. `my $a = -e $f ? 1 : 0; mkdir $f;` is an INTERNAL ERROR in B::SoN (stack underflow, "masked as a silent skip"), not a named GAP.
10. chalk's `wire-verify.t` is `skip_all` when `PERL5_SON_LIB` is unset and the default path is absent; outside `gates.sh` it can pass by not running.
11. The probe gate compares stdout and success only; stderr and the exit code are not compared, and LOUD counts as a pass.

## 8. What was run, and what was not

Run here, at the audited heads:

- chalk `tools/audit-probes.pl`, all 533 probes: LOUD 2, REFUSED 97, SAME 434, WRONG 0, no verdict changed.
- The audit's own logs (`probes/p/_all.log`, `q/_run*.log`, 418 probes) joined with that sweep: 254 ROUNDTRIP to SAME; 0 lost.
- `t/wire-verify-ratchet.t` (corpus and probes, not chalk's lib): PASS, held: pl13.
- 13 producer test files and 4 chalk test files that back the clauses: all pass.
- About 290 new probes in five batches, each also run through `SoN::Verify`; the wrong ones also run at the audit's commits.
- The mutation test of section 3.
- Greps for the deletions: `is_memory\b`, `is_placed`, `memory_input`, `WireUpgrade` in chalk `lib/`: none but one comment. `_scout_*`, `IN_SCOUT` in the producer: comments only.

Not run: both full suites, the census, the corpus gate, the verifier over chalk's lib, the deparser round trip. Not read: chalk's T2 builders beyond the loader, `Analysis.pm`, the deparser. The pushes were checked against local tracking refs, not fetched.

The new probes are not committed (this file is the only change). The programs are in the tables above; the rest are variants of them.

## 9. Lessons for `docs/memory` (not recorded there: this commit is one file)

- A verifier that reads a flag the writer derives checks the writer against itself: `record` is "on neither chain", so a floating store is a record.
- A wire rule cannot see an effect that was never emitted. A `die` dropped before the wire and a restore never built both verify clean. Mutation-test the verifier, and probe the neighbours of every fixed shape.
- A probe set that goes to zero wrong measures its own shapes. Five of the ten classes had a wrong neighbour one edit away.
- A refusal keyed on a constant (a class name, an `Undef` stamp) is a fix for a probe, not for a class.
- A read that names a version is half a rule. The other half is that the consumer makes it before the version is overwritten.
