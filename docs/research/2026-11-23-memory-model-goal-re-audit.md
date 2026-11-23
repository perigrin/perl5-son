# Re-audit of the goal "Make the SoN memory model mechanical and checked, measured" (2026-11-23)

Producer `/home/user/repo`, `wip/chalk-lib-roundtrip`, 27b1d74. Chalk `/home/perigrin/dev/chalk`, `bson/llvm-corpus`, a8057fb6. Read-only: this file is the only change. It follows the first goal audit (`2026-11-22-memory-model-goal-audit.md`, heads ae71279 / 287e5da1), whose findings are the baseline for "what was open".

## Verdict

**No, the goal is not met. Its gates are met; its first sentence is not.**

- Every measured gate in clause 5 holds, and I reproduced the cheap ones. Every finding of the 2026-11-22 audit is fixed or refused by name, apart from the ones the baseline note itself lists as open.
- But 499 new one-line probes found **68 silent wrong answers** in seven classes, plus 3 programs that die with an error that is not a refusal. All 68 wires pass `SoN::Verify` clean.
- None is a regression: every one I re-ran at the first audit's heads was already wrong there. The fix rounds did not make anything worse (493 probes: WRONG 100 at ae71279 / 287e5da1, 64 now, no SAME became WRONG).
- The worst class is everyday code: `my %opt = %defaults; $opt{color} = "blue";` changes `%defaults`.

So the model is checked for the shapes the probes hold, and "mechanical and checked" does not yet hold for memory in general: copies of a hash, scope-exit code (`finally`, `defer`), `state` variables, a fault under a `local`, and three kinds of alias are outside it, silently.

## 1. Verdict per clause

| clause | verdict | what holds (evidence) | what does not |
|---|---|---|---|
| (1) No silent wrong answers from the audit | **MET to the letter; NOT MET in substance** | All 917 gated probes re-run here: SAME 726, REFUSED 187, LOUD 4, WRONG 0, no verdict differs from chalk's `t/data/audit-probes/BASELINE.tsv`. The 22 producer-only probes (`probes/w/`) run here: 22 SAME. The first audit's 25 tabled wrong programs re-run: 17 SAME, 8 REFUSED by name. New probes are beside the audit's (`probes/a/au*`, `probes/l/lw*`). | 48 refusals are recorded as "no program graph", with no name in the baseline. 2 of them (aue1, rn1) are a B::SoN `INTERNAL ERROR ... Stack underflow`, which is not a refusal by name. 11 chalk probes (cr10, fk1-7, hc1-3) are still not beside the audit's. The 68 new wrong answers of section 3 are neighbours the probes miss. |
| (2) Producer placement is mechanical | **PARTIAL** | `_place` / `_pin` at `lib/SoN/FromOptree.pm:862,871`; `_target_storage` `:22586`; `_key_lives_in_memory` `:14362`; `_may_fault` `:920`; `B::SoN::EffectTable` refuses an unknown builtin (`t/effect-table-has-a-row-for-every-builtin.t`, `t/placement-one-constructor.t` pass here). | A may-fault division after `next unless` in a loop body still floats (held: a/aun5d). `set_control_in` is still written by hand at `:3288`, `:4879`, `:4997`, and the source test matches one spelling only. A hash copy and a `state` variable are placed nowhere (section 3, A and D). |
| (3) Wire v2 | **MET, with caveats** | `mem_in` / `mem_out` on the wire, `Exc` and catch Region, `Loop [entry, back]` with an `If` (seen on every wire dumped here). chalk `lib/`: grep for `is_memory\b`, `is_placed`, `memory_input`, `WireUpgrade` finds one comment. | `record` is still derived by the serializer (`lib/SoN/Serialize/JSON.pm:218`), now cross-checked by the verifier. "Without the double walk" holds only while every guess holds: a wrong guess, and since 2430ead a learned aggregate, walks the sub again (`%LOOP_HINTS`, `:14503`, `:24922`). Exceptional edges exist only inside an eval: a sub with no eval has no way out for a fault (section 3, B). Positional memory survives in the producer's deparser (`lib/SoN/Deparse.pm:174`, `%MEM_MIN_INPUTS`). |
| (4) Checked | **PARTIAL** | Verifier re-run here over the corpus (431 wires, 0 violations) and the probes (928 wires). `t/wire-verify-rejects-hand-broken-wires.t` passes: 11 of the first audit's 12 breakages are rejected. chalk loader invariant and `t/bootstrap/ir/wire-verify.t` exist; the suite gate now misses if that test skips. | "Passes on the probes" is with 2 violations held by name (aun6 `read-unversioned`, aun5d `effect-floating`). The loader still skips every check for a wire with no `dowarn` key (chalk `lib/Chalk/IR/Serialize/JSON.pm:1314`, `:1417`). The verifier cannot see an effect the producer never emitted: all 68 wrong wires are clean. |
| (5) Verified and pushed | **MET** | Gate record (`tools/gates.sh --summary`): producer suite 791 files, 0 failing; chalk suite 934 files, 0 failing; census ROUNDTRIP 426, DIFFERS 0, LLI_FAIL 0; corpus gate 222; probes WRONG 0; ratchet PASS, held 2. `git ls-remote origin` run here: producer `pu` and `wip/chalk-lib-roundtrip` at 27b1d74, chalk `pu` and `bson/llvm-corpus` at a8057fb6. `tools/gates.sh` is committed in both repos. | The gates ran at 732eec4 plus uncommitted docs; 27b1d74 differs from it by four docs files only (`git diff --stat`). Both full suites, the census, the corpus gate and the chalk-lib verifier run were not re-run here. The corpus gate is at its floor (222; it was 223 at stage 10). |

## 2. The 2026-11-22 audit's findings, one by one

### 2.1 Its wrong-answer rows (re-run here)

| finding | status now | evidence |
|---|---|---|
| W6: `local` in an eval that ends normally (4 rows) | fixed | 4 SAME; producer 0c2237f |
| W7: `die` ending a loop body (4 rows) | fixed | 4 SAME; producer 0c2237f, chalk 8c9e0a32 |
| W7: `map { die }` in an eval (2 rows, were regressions) | refused by name | `GAP: T2: out of its slices (a phi stamped List)` |
| W7: `log` / `sqrt` that faults (2 rows) | refused by name | `GAP: T2: out of its slices (a statement Call builtin log)`; producer 731e4ce pins them. Not lowered as statements: open as coverage |
| W2: list assign with one target in memory (2 rows) | fixed | 2 SAME; chalk a33216b0 |
| W10: `my` aggregate flattened beside a call that grows it (3 rows) | refused by name | `GAP: a 'my' aggregate a sub also reaches, flattened beside a call that may change it`; chalk 7b605d42 |
| `$_` alias written by a callee (2 rows) | fixed | 2 SAME; producer 3f0d8a6, chalk 79a2d6d1 |
| W8: inherited or AUTOLOADed `DESTROY` (2 rows) | refused by name | `GAP: a DESTROY method (...), or an AUTOLOAD perl calls for one` |
| W9: autovivifying reads (4 rows) | fixed | 4 SAME; producer 3f0d8a6 |

### 2.2 Its verifier, held-list and risk findings

| finding | status now | evidence |
|---|---|---|
| Mutation test: verifier caught 0 of 12 | fixed for 11 | `t/wire-verify-rejects-hand-broken-wires.t` (M1-M4, M6-M11, M3b), passes here; producer 62a6a94 |
| M5: a floating read naming an older version | open, by design | called "another program, not a broken wire"; chalk now makes every read before the next version (a33216b0), outside an eval body |
| `record` flag derived | open in form, guarded | still `JSON.pm:218`; V7 now rejects M1 |
| V10 (exceptional edges) not written | fixed | rule `exc`, M8 and M9 rejected |
| `LocalAlias` out of the store kinds | fixed | producer 3f0d8a6 |
| DynaLoader holds "not traced" | fixed | traced; `aelemfast` refused by name (e334f9a) |
| pl13 / aun17f held as `record` | fixed | SAME (f7ebc16, chalk 48c36bd6) |
| 25 probes "no program graph" | still open, larger | 48 now; 2 are internal errors |
| loader skips checks without `dowarn` | still open | chalk `JSON.pm:1314`, `:1417` |
| risk 8: external-state wires wrong | still open | `my $t0 = time; sleep 1; my $t1 = time`: both `time` nodes name `MemStart`, `sleep` has no `mem_out`. Refused only because T2 does not lower a statement `sleep` |
| risk 9: `-e` then `mkdir` is an INTERNAL ERROR | still open | aue1, and rn1 (`srand` / `rand`) the same way |
| risk 10: chalk `wire-verify.t` can skip | fixed in the gate | 78f9182; the test itself still has `skip_all` |
| risk 11: probe verdict ignores exit status | fixed | chalk c4033db6. LOUD still counts as a pass (section 3, H) |
| one-constructor test matches one spelling | still open | three hand-written `set_control_in` sites remain |
| "walked once" proved for the good case only | still open | a second reason to re-walk was added (cc4e0db) |

## 3. New silent wrong answers

499 programs in `/tmp/claude-0/-home-user-repo/adb6f1fb-b446-5864-9f34-e919755b5de6/scratchpad/reaudit/` (not committed), run as the probe gate runs them. 68 WRONG; all 68 wires verify clean. "Base" is the first audit's heads; every row re-run there was already wrong.

### A. A copy of a hash shares the original (26 probes) — producer

The wire has no node for the copy: the store's target is a `Subscript` of the source's `HashLiteral`. An array copy gets its own `ArrayLiteral`; a hash copy does not. It is wrong only while the source is never stored to afterwards.

| program | perl | chalk |
|---|---|---|
| `my %defaults=(color=>"red",size=>1); my %opt=%defaults; $opt{color}="blue"; print "$defaults{color} $opt{color}\n";` | `red blue` | `blue blue` |
| `my %h=(a=>1); my %c=%h; $c{a}=2; print "$h{a}\n";` | `1` | `2` |
| `my %h=(a=>1); my %c=%h; delete $c{a}; print exists $h{a} ? "y":"n","\n";` | `y` | `n` |
| `sub f { my %o=(v=>1); my %c=%o; $c{v}=2; return $o{v} } print f(),"\n";` | `1` | `2` |
| `my %h=(a=>1); my %c=%h; my %d=%c; $d{a}=3; print "$h{a}$c{a}$d{a}\n";` | `113` | `333` |

### B. A fault under a `local`, in a sub with no eval, leaves the `local` in place (16 probes) — both sides

The producer builds no way out of a sub for a fault. chalk refuses the same shape for a sub call (`WireCheck.pm:209-234`), but line 220 walks sub calls only: a pinned `Divide`, `Modulo` or strict deref is not asked.

| program | perl | chalk |
|---|---|---|
| `our $g=1; sub f { local $g=2; my $z = shift; 1/$z } eval { f(0) }; print "$g ", ($@?1:0), "\n";` | `1 1` | `2 1` |
| `our $g=1; sub f { local $g=2; my $z=shift; 5 % $z } eval { f(0) }; print "$g\n";` | `1` | `2` |
| `our @g=(1); sub f { local @g=(2,3); my $z=shift; 1/$z } eval { f(0) }; print "@g\n";` | `1` | `2 3` |
| `our $g=1; sub f { local $g=2; my $r=shift; use strict; $$r } eval { f("str") }; print "$g\n";` | `1` | `2` |
| `sub f { local $_=7; my $z=shift; 1/$z } $_="t"; eval { f(0) }; print "$_\n";` | `t` | `7` |

### C. `finally` and `defer` blocks never run (6 probes) — producer

No handler: the block is not on the wire and nothing is refused.

| program | perl | chalk |
|---|---|---|
| `use feature "try"; no warnings; my $x=0; try { $x=1 } catch ($e) { $x=9 } finally { $x.=3 } print "$x\n";` | `13` | `1` |
| `use feature "try"; no warnings; my $x=0; try { $x=1; } catch ($e) { } finally { print "fin\n" } print "$x\n";` | `fin`, `1` | `1` |
| `use feature "defer"; no warnings; my $x=1; { defer { $x=2 } $x=3; } print "$x\n";` | `2` | `3` |
| `use feature "defer"; no warnings; our $g=1; sub f { defer { $g=2 } return 5 } f(); print "$g\n";` | `2` | `1` |

### D. A `state` variable with no initializer is a `my` (3 probes) — producer

Only `state $x = V` (the `once` op, `FromOptree.pm:2784`) is handled.

| program | perl | chalk |
|---|---|---|
| `use feature "state"; sub c { state $n; $n.="x"; $n } c(); print c(),"\n";` | `xx` | `x` |
| `use feature "state"; sub c { state @l; push @l,1; scalar @l } c(); print c(),"\n";` | `2` | `1` |
| `use feature "state"; sub c { state %h; $h{$_[0]}++; scalar keys %h } c("a"); print c("b"),"\n";` | `2` | `1` |

### E. A foreach over a scalar variable does not alias it (4 probes) — producer

The list is built as a literal of the value; a write to the variable in the body is not seen through the iterator.

| program | perl | chalk |
|---|---|---|
| `my $x=5; for my $y ($x) { $x=1; print "$y\n" }` | `1` | `5` |
| `our $x=5; sub s1 { $x=1 } for my $y ($x) { s1(); print "$y\n" }` | `1` | (empty line) |
| `my $x=1; my $t=""; for my $y ($x) { $t.=$y; $x++; $t.=$y } print "$t\n";` | `12` | `11` |

### F. What `grep` returns are aliases its block may write (4 probes) — not traced

| program | perl | chalk |
|---|---|---|
| `my @a=(1,2,3); my @g = grep { $_ *= 2 } @a; print "@a\|@g\n";` | `2 4 6\|2 4 6` | `2 4 6\|1 2 3` |
| `my @a=(1,2,3); my @b = grep { $_-- > 1 } @a; print "@a\|@b\n";` | `0 1 2\|1 2` | `0 1 2\|2 3` |
| `my @a=(1,2,3); my ($f) = grep { $_++ } @a; print "$f @a\n";` | `2 2 3 4` | `1 2 3 4` |

### G. A `my` scalar operand read by alias, written later in the same expression (9 probes) — not traced

The producer refuses this for an element operand by name; a `my` scalar written by `++` or through a reference is not covered.

| program | perl | chalk |
|---|---|---|
| `my $x=1; my $r=\$x; my $v = $x + ($$r=5); print "$v\n";` | `10` | `6` |
| `my $x=1; my $r=\$x; print $x, ($$r=2), "\n";` | `22` | `12` |
| `my $x=5; my @l=(++$x, ++$x); print "@l\n";` | `7 7` | `6 7` |
| `my $x=5; my $y = ++$x + $x++; print "$y $x\n";` | `13 7` | `12 7` |

### H. Dies where perl does not, with an error that is not a refusal (3 probes)

The harness calls these LOUD and counts them as a pass. They are not silent, but they are not refusals either.

| program | perl | chalk |
|---|---|---|
| `package C; our $inst; sub get { $inst //= bless {n=>0}, shift } package main; C->get->{n}++; C->get->{n}++; print C->get->{n},"\n";` | `2` | dies: `Can't locate object method "get" via package "C"` |
| `use feature "try"; no warnings; my $x=0; try { try { die "i\n" } catch ($e) { $x.=1; die "o\n" } } catch ($e) { $x.=2 } print "$x\n";` | `012` | dies: `o` |

### What came through clean

Worth saying, because it is most of the surface: 45 of 45 closure and callee-side-effect probes are SAME; the 50 list-assign and package-variable-in-loop probes have no WRONG (39 SAME, 11 refused by name); and of the 40 eval / `local` / `die` probes the only WRONG are one `finally` and one fault under a `local`.

## 4. The design against the literature

**Click, sea of nodes.** The chain matches: a store takes and makes a memory state, a read takes one, Phis merge states. One alias class instead of C2's sliced memory is conservative and sound. Two departures are not:

- **A `my` aggregate is a value node that is stored into.** `HashLiteral` and `ArrayLiteral` are SSA values, yet an `Assign` to a `Subscript` of one mutates it. In Click's IR a location has identity (an allocation); a value does not. Here a location's identity is whichever value node the name is bound to, so a copy that binds the same node is the same location (class A). The model is sound only if every copy makes a new node, and nothing checks that.
- **No anti-dependence for floating reads.** chalk now orders every read before the next version (a33216b0), which closes the first audit's W2 row. It is a consumer rule, not a wire fact, and it is off inside an eval body.

**Braun et al. 2013.** Incomplete Phis at unsealed headers, memory as one more variable, trivial Phis removed: matches. Departure: Braun never re-walks; here a wrong guess restarts the sub, and loop-writeback added a second cause. Sound as long as sealing catches every wrong guess. Classes E and F are guesses nothing catches: the walk binds an iterator to a value where perl binds an alias.

**Exceptional edges (C2, Graal).** `Exc` per thrower, merged at a catch Region, with the restores and the `$@` store on the edge: matches Graal's `InvokeWithException`, and V10 now checks it. Departures:

- **Only an eval has an exceptional exit.** In C2 and Graal every method has an unwind path. Here a sub with no eval has none, so scope-exit work on a fault is not done (class B). chalk refuses the call case and misses the operator case.
- **Scope-exit code is not on any edge.** `finally` and `defer` are the same construct as a `local` restore (work on every way out) and are not emitted (class C).

**MemorySSA.** The wire is MemorySSA made primary, over one heap. LLVM verifies MemorySSA against the instruction order; here the chain is the only order and the optree is gone. So the verifier proves the wire well-formed, never that it is the program. Every class in section 3 is a dropped or mis-bound effect with a clean wire. Only differential testing against perl finds these, and the probe set is that test.

## 5. Open items

Known and recorded by the project:

- Held verifier violations: a/aun6 (compound assign through a symbolic ref reads at no version), a/aun5d (may-fault division after `next unless` floats).
- External state: `time` / `sleep` / `srand` / `rand` are not ordered on the wire; protected only by unrelated T2 refusals.
- `-e` then `mkdir`, and `srand` then `rand`, are a B::SoN INTERNAL ERROR (stack underflow), not a named GAP.
- The loader skips its invariant and `WireCheck` for a wire with no `dowarn` key.
- `log` / `sqrt` as statements are pinned but not lowered by T2 (refused).
- Unconditional `last`, `next LABEL`, `redo`, backward `goto` are refused.

Found here:

- The seven wrong classes of section 3 (A is the urgent one).
- LOUD is a pass in the probe harness even when the error is not a refusal (class H).
- 48 gated refusals carry no name in the baseline, so a refusal that changes cause is not seen.
- Two of my probes went SAME to REFUSED between the audits (a statement `sqrt`; a foreach with `continue` writing an element). No audit probe did.

## 6. What was run, and what was not

Run here: all 917 gated probes plus the 22 producer-only ones; `tools/wire-verify.pl` over corpus and probes; six producer test files backing clauses 2 to 4; 499 new probes at the final heads and 493 of them at the first audit's heads; `git ls-remote` on both repos; greps for the deletions.

Not run: both full suites, the census, the corpus gate, the verifier over chalk's lib, the deparser round trip. Those numbers are the gate record's. Classes F and G were not traced to a side. The six `defer` and late hash-copy probes (r01-r06) were not re-run at the first audit's heads.

## 7. Lessons (not written to `docs/memory`: this audit changes one file)

- A copy that binds a name to the source's node is not a copy. Probe every aggregate kind when one is fixed: arrays were right, hashes were not.
- Work that runs on every way out of a scope (`local` restore, `finally`, `defer`) is one class. Fixing it for one construct leaves the others.
- A refusal that walks one node kind (sub calls) misses the same hazard from another (a faulting operator).
- LOUD needs a refusal's name to be a pass; an invented perl error is a wrong answer that happens to be noisy.
