# Second final audit of the goal "Make the SoN memory model mechanical and checked, measured" (2026-11-25)

Producer `/home/user/repo`, `wip/chalk-lib-roundtrip`, 888d71b. Chalk `/home/perigrin/dev/chalk`, `bson/llvm-corpus`, f1d9aa74. No code was changed. The commit is this file, the probes in `docs/research/son-ir-audit-2026-11-19/probes/z/`, one README line and one memory note. It follows the final audit (`2026-11-24-memory-model-final-audit.md`, heads a5df593 / 93c01e4c) and baseline sections 23-26.

## Verdict

**Every gate I re-ran passes, and every caveat of the last audit but four small ones is closed. The goal's first sentence still does not hold.**

- The 2351 gated probes: SAME 1860, REFUSED 476, LOUD 15, WRONG 0. One verdict differs from `BASELINE.tsv` (`lw25`, REFUSED to SAME, as section 26 says).
- The verifier: corpus 431 wires and the 2356 older probes, 0 violations. The ratchet, the walk-once sweep and chalk's `wire-verify.t` pass.
- The last audit's 111 wrong answers are gone: lowered or refused by name.
- 828 new one-line probes found **57 silent wrong answers** in nine classes. That is 7% (the last audit: 13%). All 57 wires pass `SoN::Verify` and chalk's loader clean.
- The new mechanisms held where they were aimed: rethrow edges (80 probes, 0 wrong), copies (90 probes, 1 wrong, and that one is `@_`), references (40, 0 wrong), package scalars a callee writes (0 wrong where the callee is on the wire).
- The wrong answers sit where the new mechanisms stop:
  - `my @a=(1,2); sub z { $a[0]=7 } for my $x (@a) { z(); print $x }` prints `12` for perl's `72`.
  - `sub f { my ($p)=@_; $_[0]=9; $p } print f($x)` prints `9` for perl's `1`.
  - `use ZUp; print "$ZUp::n\n"` prints an empty line for perl's `1` (the module says `our $n = 1`).

## 1. Verdict per clause

| clause | verdict | what holds | what does not |
|---|---|---|---|
| (1) No silent wrong answers from the audit | **MET to the letter; the neighbourhood is not clean** | All 2351 gated probes re-run here: SAME 1860, REFUSED 476, LOUD 15, WRONG 0. They hold the 59 W1-W10 cases, the hash-truth cases, the dropped list-assign stores, and every later audit's probes (`au`, `re`, `fa`, `cpa`, `al`, `c3t`). No probe that was SAME is anything else. Fix probes are beside the audit's: `probes/cpa/` (35), `probes/al/` (46). | 57 new wrong answers (section 3). One refusal still has no name: `st3`, "no program graph". The 15 LOUD are run-time stops, not perl's answer. |
| (2) Producer placement is mechanical | **MET for what reaches the constructor; PARTLY MET overall** | `_place` `lib/SoN/FromOptree.pm:887`, `_pin` `:896`; `_seat` `:952` is the one write of `control_in` (5 callers: `:908`, `:938`, `:3543`, `:5147`, `:5265`); `t/placement-one-constructor.t` passes. List-assign targets by where they live: `_target_storage` `:23895`, called at `:12784`. Package scalars in loops: `_key_lives_in_memory` `:14978`; my scan of 3613 wires finds no package scalar read with no version in a loop. Dynamic method: `dispatch_kind => 'dynamic_method'` `:6042`; all 13 in the wires have `control_in` and `mem_in`. Effect table: `B::SoN::EffectTable::on_chain` (`lib/B/SoN/EffectTable.pm:192`), asked at `FromOptree.pm:13878`, `:20205`, `:20343`; its test passes. May-fault division: `_may_fault` `:958`, pinned at `:979`; verifier `effect-floating` is 0 on every wire. | A store the producer has no rule for still never reaches the constructor, with no GAP: `($c ? $a : $b) x= 3`, `($x = $x + 1) *= $x`, `inc($x .= "b")`, `for ($x += 5) { $_++ }` (class K4, 8 probes). A list assignment to a foreach iterator is pinned to the iterator's pad slot, not to the element it lives in: "by where it lives" fails there (class K8, 4 probes). One sub `Call` in the corpus is on no control chain (`corpus/398`, an `:lvalue` call taken back by `_unplace`). |
| (3) Wire v2 | **MET, with three smaller caveats** | Scanned here over 3613 wires (corpus 431, probes 3182): every `Return` (5491), `EntryWrite` (3580), non-builtin `Call` (2723), `Delete` (69), `CellWrite` (81) and non-record `Assign` (2863) has `mem_in`; the 208 record `Assign`s are on no chain and carry `record` (said by the producer, `FromOptree.pm:12918`; written as said, `lib/SoN/Serialize/JSON.pm:218`); no `MemStart` or memory Phi is in any `inputs` but a memory Phi's; 605 `Exc`, 125 rethrow `Unwind`; 1362 `Loop`s, all with one or two inputs. The double walk is gone: `LOOP_HINTS`, `$DIRTY`, `_translate_from_once`, `_translate_until_settled` appear in one comment only (`:15457`), and `t/loop-body-is-walked-once.t` passes over corpus and all probes, the new 826 included. chalk `lib/`: `is_memory`, `is_placed`, `WireUpgrade` are one comment (`lib/Chalk/IR/Node/Phi.pm:42`); the loader refuses any wire but v2 (`lib/Chalk/IR/Serialize/JSON.pm:1327`). | A pre-scan miss is not always refused by name: `for my $x (@a) { ($x,$y)=($y,$x) }` is translated wrong, with no GAP (class K8). Not every memory read names a version: a callee's `my (...) = @_` is a record over `ArgsSource`, which has no `mem_in`, though `@_` holds places (class K1); one value Phi takes `$@` as an `EntryDef` with no version (`z/un19`, SAME). The producer's deparser still reads v2 through `SoN::Wire::as_v1`, which decides by node kind which `mem_in` was an operand (`lib/SoN/Wire.pm:34-43`, "wrong for about 30 builtin calls in 9000", marked by `memory_input`). That is the producer's checker, not chalk. |
| (4) Checked | **MET as written; the check is of form** | `SoN::Verify`: `write-unreachable` `lib/SoN/Verify.pm:388`, `read-unversioned` (V6), `effect-floating` `:371`, `alias-not-private` `:155`. Run here: corpus 0 violations, the 2356 older probes 0, `t/wire-verify-ratchet.t` passes (4 tests), `t/wire-verify-rejects-hand-broken-wires.t` passes (27). chalk's loader holds every wire to `WireInvariant` L1-L10 and `WireCheck` (`JSON.pm:1335-1340`, `:1435`); chalk's `t/bootstrap/ir/wire-verify.t` over chalk's lib and its probes passes (3 tests, none skipped). | 2 of the 828 new probes break a rule (section 3.3). The loader lets off any wire that says `writer: chalk`: a wire exempts itself by one key. The producer's ratchet checks chalk's lib only with `SON_RATCHET=1` (not run here). V12 has only its call half: the alias-list half was dropped as unbuildable, and class K3 is that half. The verifier sees none of the 57 wrong wires. |

Clause 5 (verified and pushed) was not asked for. I did not run either full suite, the census, or the corpus gate.

## 2. The last audit's caveats

| caveat (2026-11-24) | now |
|---|---|
| 111 wrong answers in nine classes | **Closed.** All 847 `f` probes are in the gated set (`fa*`): WRONG 0. |
| The fix probes `cpa01-35` were in chalk only | **Closed.** `probes/cpa/`. |
| One refusal with no name (`st3`) | **Open.** Still "no program graph". |
| A may-fault division floats (`d61`) | **Closed.** `effect-floating` 0 on every wire; `d61` is in `f/`. |
| `set_control_in` written by hand at three sites | **Closed.** `_seat` is the one write; the test catches any spelling. |
| A package scalar in a foreach list is not read through memory | **Closed.** The item is a place (`fields.place`); `for ($x,$y)` over package scalars is SAME (`z/pa63` for `my`, `fa` class E for `our`). |
| A store with no handler is dropped, not refused (class D) | **Partly closed.** The 14 probes are SAME or refused. The class is not: 8 new drops (K4), and 6 more where an assignment's value is read as a value, not as the element (K5). |
| `record` derived by the serializer | **Closed.** |
| A wrong guess walks the sub again | **Closed.** No re-walk, no settle pass. But see K8: one fact the pre-scan misses is not refused. |
| `EntryDef` with no version in an `ArrayLiteral` | **Closed.** 0 in 3613 wires. |
| Positional memory in the producer's deparser | **Mostly closed.** `%MEM_MIN_INPUTS` is gone; `as_v1` still guesses by kind and marks the result. |
| Three probes broke verifier rules (`a55`, `d61`, `o11`) | **Closed.** All three are clean and in `f/`. |
| The loader skipped a wire with no `dowarn` | **Closed**, replaced by the narrower `writer: chalk` exemption. |
| The ratchet reads chalk's lib only with `SON_RATCHET=1` | **Open** (by design). |
| The verifier sees none of the wrong wires | **Open.** 57 of 57 here. |
| `time`, `sleep`, `rand` not ordered | **Closed** (`clock`, EffectTable `:115`, `:188`). |
| Aliases outside the model (C, E, G, H) | **Mostly closed.** 60 of 66 SAME. What is left is the fast path's proof (K3), `local` under an alias (K2), and `@_` copied late (K1). |
| A floating read made late in chalk (B) | **Mostly closed.** Two new cases (K6). |
| Edges only under an eval or a live `local` | **Open, and sound so far**: 80 unwind probes, 0 wrong. |

## 3. The design against the literature

### Click, sea of nodes

Matches: effects on a control chain; one memory state a store takes and makes; reads name a state; Phis at Regions; an explicit loop back edge with an `If` for the test. One alias class for the whole heap is coarser than C2's slices. That costs precision, not soundness.

Departures:

1. **A read that names an old version may be made late.** Click's scheduler adds an anti-dependence so a load is never placed after a store that kills its state. Here that is a consumer rule in chalk, with no wire check. It now holds for copies. It fails for the old value of `$g++` passed to a call: the wire of `f($g, $g++)` is right (`inputs: [read at the store, read before it]`), and chalk prints `2 2` for `2 1` (K6). **Not sound as built**, in a smaller corner than before.
2. **A value stands where perl has a location.** In Click's IR (Java) an expression's result is a value. In Perl the result of `$a[0] = 5`, `++$a[0]`, `$a[0] += 1`, and each item of `(@a, ...)` is the variable itself, read when the consumer runs. The producer refuses the scalar cases by name ("a scalar operand is read by alias and a later operand stores it") but not the element ones (K5), nor an aggregate flattened into a list before a later item stores into it (K7). **Not sound**; the fix is the refusal the scalar case already has.
3. **A store exists only where a handler makes one.** Unchanged from the last audit. The default for an lvalue op with no rule is still not a GAP everywhere (K4).

### Braun et al. 2013

Matches: Phis made at an unsealed header, memory as one more variable, trivial Phis removed, **one walk**. The re-walk the last audit named is deleted, and the walk-once sweep holds it.

Departure: **the pre-scan is a second analysis Braun does not have.** Braun never needs to know, at the header, what the body will write: an incomplete Phi stands in. Here the header must know (the iterator write, a Phi's stamp, the slots, the aggregates written) because the walk picks a binding's class, value or memory, as it goes. The scan must then agree with the walk on every op. A miss is meant to be refused by name, and two of mine were (`z/ps12`, `z/ps32`). One was not: a list assignment to the iterator (K8) is scanned as no write, walked as a slot store, and nothing compares the two. **Sound only while every miss is caught**, and that is held by tests, not by construction.

### Memory SSA

`mem_out`, `mem_in` and the memory Phi are MemoryDef, MemoryUse and MemoryPhi over one partition. V12 is a clobber query, as the design says. Two differences remain:

- LLVM derives MemorySSA from ordered instructions and can verify it against them. Here the wire is the only order. The verifier proves the wire well-formed, never that it is the program: 57 wrong wires, 0 violations.
- V12 asks the clobber question for a call's argument only. The same question for a foreach, map or grep item read per pass (`Subscript [list, i]` at the header's version, used after a call) is not asked. That is K3: the read names the loop header's memory, its use stands after a `Call` that stores the array.

### LLVM alloca and mem2reg

The design is mem2reg run backwards: a variable is an SSA value unless something may alias it, then it is demoted to memory. mem2reg's proof is simple and total: the address does not escape. The proof here is spread over several scans (`arg_stored_by_call`, `stores_invocant`, `call_stores_through_args`, the body scans), each written for one alias kind. Two real departures:

1. **The unproved case must default to memory.** For calls it now does ("an unknown call proves nothing"). For a per-pass iterator read it does not (K3).
2. **`local` is not a store to the same alloca.** Perl's `local $x` gives the name a new scalar and puts the old one back; an alias taken before stays with the old scalar. The wire models `local` as save, store, restore on one location, and chalk lowers a place to a pointer to that location. So `sub f { local $x=5; $_[0]=7; $x } f($x)` writes the new value where perl writes the saved one (K2). **Not sound.** It needs either a refusal ("a `local` of a variable some alias reaches") or a place that is the scalar, not the name.

### HHVM refs

HHVM boxes a variable bound by reference; every access goes through the box, and the box is the identity. That is the place here, and it is why classes C, G and H are SAME now. HHVM's box survives rebinding the name; a place here is the name's storage, which is departure 2 above. HHVM also treats by-value parameters as copies made at the call. Perl's `my ($p) = @_` is that copy, made by the callee at the point it runs. The wire makes it a record with no version (K1): the copy has no place in the order, so chalk makes it at first use, after `$_[0] = 9`.

### Exception edges (C2, Graal)

Matches: an `Exc` per may-die point inside an eval, merged at a catch Region with a memory Phi; the `local` restores and the `$@` store on the edge; design B1's rethrow `Unwind` outside an eval where a `local` is live (125 in the wires). This is Graal's `InvokeWithException` and `UnwindNode`.

Departures, both unchanged and both sound so far:

1. **An edge exists only where an eval is open or a `local` is live.** With the iterator a place there is no pending write-back left to lose, so the last audit's class G cannot recur by that road. 80 probes aimed here: 0 wrong.
2. **What may die is a list** (`_dies_by_its_values`, `:922`). A fault outside it stops the program loudly inside an eval where perl carries on (`z/un39`: a call of undef). Loud, not silent.

One verifier fault: V10 counts a `local` in an inner block that has already closed as live (`z/un75`, section 3.3). The wire cannot say a `local` is live, so the verifier guesses.

## 4. New probes

828 programs, written for this audit: 826 in `probes/z/`, 2 in `probes/z/unverified/`. Each was run under perl and through B::SoN, chalk T2 and `lli` by `AuditProbe::run_all`, from the probes' own directory. Verdicts are in `probes/z/_run1.log`. Two modules for the package probes are in `probes/z/zlib/`.

| group | aimed at | n | SAME | REFUSED | LOUD | WRONG |
|---|---|---|---|---|---|---|
| pa | places: arguments, alias lists, the fast path | 99 | 62 | 33 | 1 | 3 |
| qa | a callee's copy of `@_`, then a store | 25 | 13 | 1 | 0 | 11 |
| qb | `local` under an alias | 15 | 4 | 7 | 0 | 4 |
| qc | an iterator read after a call that stores its list | 25 | 20 | 1 | 0 | 4 |
| lv | `?:` and assignment as lvalues, order of evaluation | 80 | 41 | 33 | 1 | 5 |
| qd | the same, second round | 50 | 19 | 17 | 3 | 11 |
| fl | an aggregate in a list, then a store | 30 | 25 | 2 | 0 | 3 |
| un | rethrow edges, `local` and die, `$@` | 80 | 56 | 23 | 1 | 0 |
| cp | always-copy | 90 | 73 | 16 | 0 | 1 |
| ps | pre-scan facts: iterator writes, stamps, slots, aggregates | 90 | 68 | 21 | 0 | 1 |
| qf | list assignment to a foreach iterator | 12 | 6 | 3 | 0 | 3 |
| pk | package scalars: unscanned and followed packages, `$_`, globs | 60 | 27 | 31 | 1 | 1 |
| qe | a followed module's own package scalar | 12 | 2 | 0 | 0 | 10 |
| rf | references to variables, elements, iterators | 40 | 33 | 7 | 0 | 0 |
| rc | recursion, per-call `my`, `state` | 15 | 9 | 6 | 0 | 0 |
| nd | nested data | 15 | 10 | 5 | 0 | 0 |
| mi | what earlier audits did not cover: integer overflow, number formats, sprintf, context, slices | 90 | 72 | 18 | 0 | 0 |
| **all** | | **828** | **540** | **224** | **7** | **57** |

What came through clean: rethrow edges and `local` (80), references (40), recursion (15), nested data (15), arithmetic and formatting (90, none wrong: `9223372036854775807 + 1`, `1 << 63`, `"az"++`, `%g` all match perl). Copies: 1 wrong in 90.

Refusals: 223 of 224 name a cause. One is an internal check, not a name: `z/cp83` ("method P::l has return type 'Array' on the wire but 'ArrayRef' derived from its graph ... One of the two is wrong"). Every lower-case module call is refused by name ("a direct call with no sub"), so the unscanned-package rule could not be reached through chalk: `pk01`-`pk20` are 19 refusals and one LOUD.

Seven LOUD:

| probe | program | what chalk says |
|---|---|---|
| z/lv78 | `my $x=1; my $r = \($x = 5); $$r++; print "$x\n";` | Modification of a read-only value attempted |
| z/pa30 | `my $x=1; sub inc { $_[0]++ } inc(do { $x }); print "$x\n";` | the same |
| z/qd22 | `sub inc { $_[0]++ } my $x=1; inc($x++); print "$x\n";` | the same |
| z/qd48 | `my $x=1; for ($x = 5) { $_++ } print "$x\n";` | the same |
| z/qd50 | `my $x=1; $_++ for ($x = 5), $x; print "$x\n";` | the same |
| z/pk11 | `use zlow; my $m="bump"; ... zlow->$m; ...` | Can't locate object method "bump" via package "zlow" (perhaps you forgot to load "zlow"?) |
| z/un39 | `eval { local $g=2; my $f; $f->(); }; print ...` | refused at run time: a call of what is not a code value |

Five are the same fault as K4 and K5 turned loud: a value where perl has a variable. `pk11` names something untrue: the module is loaded.

### 4.1 The nine wrong classes

| class | what | n | side | traced on |
|---|---|---|---|---|
| K1 | A callee copies `@_` (`my @l=@_`, `my ($p,$q)=@_`), then stores through `$_[N]` or to the caller's variable; the copy shows the store. | 13 | wire: the copy is a record over `ArgsSource`, with no version; chalk makes it late | `z/qa05` |
| K2 | `local` of a variable an alias reaches: the alias follows the new value, perl's stays with the saved one. | 5 | model: `local` is a store to the same place | `z/qb01` |
| K3 | A foreach iterator, or `$_` in map or grep, read after a call that stores its array: the read is the pass's first version. | 5 | producer: `Subscript [list, i]` names the header's memory and is used after the `Call` | `z/pa69`, `z/qc05` |
| K4 | An lvalue with no rule: the store is dropped, no GAP. | 8 | producer: no store on the wire | `z/qd01`, `z/qd09`, `z/qd16`, `z/qd49` |
| K5 | The result of an element assignment, op= or `++` used as an operand is its value then, not the element. | 6 | producer: `Add [5, 7]` for `($a[0]=5)+($a[0]=7)` | `z/qd29` |
| K6 | The old value of `$g++` passed to a call is read after the store. | 2 | chalk: the wire is right | `z/qd40` |
| K7 | An array in a list, then a later item stores an element: the list holds the old element. | 3 | producer: the literal is flattened to constants | `z/fl01` |
| K8 | A list assignment whose target is a foreach iterator: the element is not written. | 4 | producer: the pre-scan sees no write, the walk stores the pad slot, nothing refuses | `z/qf01` |
| K9 | A followed module's file-level `our $n = 1` never runs: the program reads undef. | 11 | producer: the module's own code is not on the wire, no GAP | `z/qe03` |

K9 is not the memory model. It is the state the model starts from, and it is silent: any module with an initialised package variable.

### 4.2 Every WRONG

#### K1 (13)

| probe | program | perl | chalk |
|---|---|---|---|
| z/cp24 | `my @a=(1,2); sub f { my @l=@_; $a[0]=9; "@l" } print f(@a), "\n";` | `1 2` | `9 2` |
| z/pa82 | `my @a=(1,2); sub f { my ($p,$q)=@_; $_[0]=9; "$p$q" } print f(@a),"@a\n";` | `129 2` | `929 2` |
| z/qa01 | `my @a=(1,2); sub f { my @l=@_; $_[0]=9; "@l" } print f(@a), "\n";` | `1 2` | `9 2` |
| z/qa05 | `my $x=1; sub f { my ($p)=@_; $_[0]=9; $p } print f($x), "\n";` | `1` | `9` |
| z/qa07 | `my @a=(1,2); sub f { my @l=@_; @a=(); "@l" } print f(@a), "\n";` | `1 2` | (empty) |
| z/qa08 | `our @a=(1,2); sub f { my @l=@_; $a[0]=9; "@l" } print f(@a), "\n";` | `1 2` | `9 2` |
| z/qa10 | `my @a=(1,2); sub f { my ($p,@r)=@_; $a[1]=9; "$p@r" } print f(@a), "\n";` | `12` | `19` |
| z/qa11 | `my @a=(1,2); sub f { my $n=@_; my @l=@_; $_[1]=9; "$n@l" } print f(@a), "\n";` | `21 2` | `21 9` |
| z/qa12 | `my @a=(1,2); sub f { my ($p,$q)=@_; $_[1]=9; "$p$q" } print f(@a), "@a\n";` | `121 9` | `191 9` |
| z/qa13 | `my ($x,$y)=(1,2); sub f { my ($p,$q)=@_; $_[0]=9; "$p$q" } print f($x,$y), "$x\n";` | `129` | `929` |
| z/qa16 | `my @a=(1,2); sub g { $a[0]=9 } sub f { my @l=@_; g(); "@l" } print f(@a), "\n";` | `1 2` | `9 2` |
| z/qa21 | `my @a=(1,2); sub f { my @l=(0,@_); $a[0]=9; "@l" } print f(@a), "\n";` | `0 1 2` | `0 9 2` |
| z/qa25 | `package C; sub new { bless {v=>1}, shift } sub m { my ($s,@l)=@_; $_[1]=9; "@l" } package main; my @a=(1,2); print C->new->m(@a), "@a\n";` | `1 29 2` | `9 29 2` |

#### K2 (5)

| probe | program | perl | chalk |
|---|---|---|---|
| z/pa02 | `our $x=1; sub f { local $x=5; $_[0]=7; $x } print f($x),$x,"\n";` | `57` | `71` |
| z/qb01 | `our $x=1; sub f { local $x=5; $_[0]=7; $x } my $r=f($x); print "$r$x\n";` | `57` | `71` |
| z/qb02 | `our $x=1; sub f { local $x=5; $_[0]++; $x } print f($x), $x, "\n";` | `52` | `61` |
| z/qb05 | `our %h=(k=>1); sub f { local $h{k}=5; $_[0] } print f($h{k}), "\n";` | `1` | `5` |
| z/qb09 | `our $x=1; sub f { local $x=5; g2($_[0]) } sub g2 { $_[0]=7; $x } print f($x), $x, "\n";` | `57` | `71` |

#### K3 (5)

| probe | program | perl | chalk |
|---|---|---|---|
| z/pa69 | `my @a=(1,2); sub z { $a[0]=7 } for my $x (@a) { z(); print $x } print "\n";` | `72` | `12` |
| z/qc05 | `my @a=(1,2); sub z { $a[1]=7 } print map { z(); $_ } @a; print "\n";` | `17` | `12` |
| z/qc06 | `my @a=(1,2); sub z { $a[1]=7 } my @g=grep { z(); $_ > 1 } @a; print "@g\n";` | `7` | `2` |
| z/qc09 | `my @a=(1,2); sub z { $_++ for @a } for my $x (@a) { z(); print $x } print "\n";` | `24` | `13` |
| z/qc23 | `my @a=(1,2); my @b=(3,4); sub z { $b[0]=7 } for my $x (@a,@b) { z(); print $x } print "\n";` | `1274` | `1234` |

#### K4 (8)

| probe | program | perl | chalk |
|---|---|---|---|
| z/lv27 | `my $x=3; ($x = $x + 1) *= $x; print "$x\n";` | `16` | `4` |
| z/lv34 | `sub inc { $_[0]++ } my $x="a"; inc($x .= "b"); print "$x\n";` | `ac` | `ab` |
| z/lv58 | `my ($a1,$b1)=(1,2); my $c=1; ($c ? $a1 : $b1) x= 3; print "$a1 $b1\n";` | `111 2` | `1 2` |
| z/qd01 | `my ($a1,$b1)=(1,2); my $c=1; ($c ? $a1 : $b1) x= 3; print "$a1 $b1\n";` | `111 2` | `1 2` |
| z/qd09 | `my $x=3; ($x = $x + 1) *= $x; print "$x\n";` | `16` | `4` |
| z/qd16 | `sub inc { $_[0]++ } my $x="a"; inc($x .= "b"); print "$x\n";` | `ac` | `ab` |
| z/qd17 | `sub ap { $_[0].="!" } my $x="a"; ap($x .= "b"); print "$x\n";` | `ab!` | `ab` |
| z/qd49 | `my $x=1; for ($x += 5) { $_++ } print "$x\n";` | `7` | `6` |

#### K5 (6)

| probe | program | perl | chalk |
|---|---|---|---|
| z/lv74 | `my @a=(1,2,3); my $n = ($a[0] += 1) + ($a[0] += 1); print "$n @a\n";` | `6 3 2 3` | `5 3 2 3` |
| z/qd25 | `my @a=(1,2,3); my $n = ($a[0] += 1) + ($a[0] += 1); print "$n\n";` | `6` | `5` |
| z/qd28 | `my %h=(a=>1); my $n = ($h{a} += 1) + ($h{a} += 1); print "$n\n";` | `6` | `5` |
| z/qd29 | `my @a=(1); my $n = ($a[0] = 5) + ($a[0] = 7); print "$n\n";` | `14` | `12` |
| z/qd30 | `my @a=(1); my $n = ++$a[0] + ++$a[0]; print "$n\n";` | `6` | `5` |
| z/qd32 | `my @a=(1); my @l=(++$a[0], ++$a[0]); print "@l\n";` | `3 3` | `2 3` |

#### K6 (2)

| probe | program | perl | chalk |
|---|---|---|---|
| z/lv77 | `our $g=1; sub f { "@_" } print f($g, $g++), "\n";` | `2 1` | `2 2` |
| z/qd40 | `our $g=1; sub f { "@_" } my $s=f($g, $g++); print "$s $g\n";` | `2 1 2` | `2 2 2` |

#### K7 (3)

| probe | program | perl | chalk |
|---|---|---|---|
| z/fl01 | `my @a=(1,2,3); my @b=(@a, $a[0]=9); print "@b\n";` | `9 2 3 9` | `1 2 3 9` |
| z/fl04 | `my @a=(1,2,3); print "@{[ @a, $a[0]++ ]}\n";` | `2 2 3 1` | `1 2 3 1` |
| z/fl05 | `my @a=(1,2,3); my @b=(@a, map { $_++ } @a); print "@b\n";` | `2 3 4 1 2 3` | `1 2 3 1 2 3` |

#### K8 (4)

| probe | program | perl | chalk |
|---|---|---|---|
| z/ps22 | `my @a=(1,2); my $y=9; for my $x (@a) { ($x,$y)=($y,$x) } print "@a $y\n";` | `9 1 2` | `1 2 2` |
| z/qf01 | `my @a=(1,2); my $y=9; for my $x (@a) { ($x,$y)=($y,$x) } print "@a $y\n";` | `9 1 2` | `1 2 2` |
| z/qf03 | `my @a=(1,2); my $y=9; for my $x (@a) { ($y,$x)=($x,$y) } print "@a $y\n";` | `9 1 2` | `1 2 2` |
| z/qf12 | `my @a=(1,2); my $y=9; for my $x (@a) { my @t=($y,$x); ($x,$y)=@t } print "@a $y\n";` | `9 1 2` | `1 2 2` |

#### K9 (11)

| probe | program | perl | chalk |
|---|---|---|---|
| z/pk21 | `use ZUp; my $s=""; for (1..3) { $s.=$ZUp::n; ZUp::bump(); } print "$s$ZUp::n\n";` | `1234` | `123` |
| z/qe01 | `use ZUp; my $b=$ZUp::n; ZUp::bump(); print "$b$ZUp::n\n";` | `12` | `1` |
| z/qe02 | `use ZUp; ZUp::bump(); print "$ZUp::n\n";` | `2` | `1` |
| z/qe03 | `use ZUp; print "$ZUp::n\n";` | `1` | (empty) |
| z/qe05 | `use ZUp; for (1..2) { ZUp::bump() } print ZUp::get(), "\n";` | `3` | `2` |
| z/qe06 | `use ZUp; for (1..2) { ZUp::bump() } print "$ZUp::n\n";` | `3` | `2` |
| z/qe07 | `use ZUp; my $s=""; for (1..2) { $s.=ZUp::get(); ZUp::bump() } print "$s\n";` | `12` | `1` |
| z/qe08 | `use ZUp; my $s=""; for (1..2) { $s.=$ZUp::n; ZUp::bump() } print "$s\n";` | `12` | `1` |
| z/qe10 | `use ZUp; my $i=0; while ($i++<2) { ZUp::bump() } print "$ZUp::n\n";` | `3` | `2` |
| z/qe11 | `use ZUp; ZUp::bump() for 1..2; my $v=$ZUp::n+1; print "$v\n";` | `4` | `3` |
| z/qe12 | `use ZUp; if (1) { ZUp::bump() } print "$ZUp::n\n";` | `2` | `1` |

### 4.3 Two new verifier violations

The ratchet reads `probes/*/*.pl`, so these two are in `probes/z/unverified/`. With them there, `t/wire-verify-ratchet.t` passes.

| probe | program | rule | verdict | whose fault |
|---|---|---|---|---|
| `pa79` | `my $s="abc"; sub f { substr($_[0],0,1)="z" } f($s); print "$s\n";` | `read-unversioned:args` (`Subscript` of `ArgsSource` with no `mem_in`) | REFUSED by T2 | producer |
| `un75` | `our $g=1; eval { { local $g=2; } die "x\n" }; print "$g\n";` | `exc` ("its way out does not put back the local of main:$:g") | SAME | verifier: the inner block has closed, the `local` is not live |

## 5. Design risks, ranked

1. **The fast path's proof is per alias kind, and the unproved case is a value for one kind** (K3, K1: 18 wrong). A call argument not proved private is a place. A per-pass iterator read, and a callee's copy of `@_`, are still values at a version nothing checks. Build V12's list half (a `Subscript [list, i]` use, walked back to its `mem_in`, must meet no call or store that reaches the list), and give the `@_` record a version or pin it. Until then the fast path is trusted, not checked, for its `list` and `iter` counters.
2. **A value stands where perl has a variable** (K4, K5, K7, five LOUD: 17 wrong). Design 3 covered the shapes the last audit listed. The rule that would cover the class is not in: any op that yields an lvalue (assignment, op=, pre-increment, an aggregate in a list) and is then an operand or an alias, with a later store to the same variable in the same statement, is a GAP. The scalar form of that GAP exists; extend it to elements and to flattened aggregates. And make "an lvalue op with no rule" a GAP by default, as the last audit asked.
3. **`local` under an alias** (K2: 5 wrong). The place model and perl disagree on what `local` does. Small in real code, but it is the one place where the model itself, not a hole in a scan, is wrong. Refuse it by name.
4. **The pre-scan must agree with the walk, and only the walk's refusals say so** (K8: 4 wrong). The scan is a second implementation of "what does this op write". Three scans and one walk now share that question. One table (op, operand, writes or not), read by both, would make a miss impossible instead of refused.
5. **The verifier checks form** (57 of 57 wrong wires are clean). Each audit's fresh probes find wrong answers the gated set does not: 59, 55, 68, 111, 57. The rate is falling (13% to 7%) and the classes are narrower. The zero in the gate still measures the probe set.
6. **Module initialisers** (K9: 11 wrong). Outside the memory model, but it makes every program that reads a followed module's package variable wrong, silently. The producer knows the module has file-level code; it should put it on the wire or refuse.
7. **A read made late in chalk** (K6: 2 wrong). The read-before-kill rule has one more hole: an operand of a call that names a version older than a store standing before the call.
8. **Refusal hides what is behind it.** 224 of 828 refused. Every lower-case module call is refused, so the "unscanned package counts as written" rule has no end-to-end probe that runs: it is covered by the producer's own test only.
9. **Verifier and loader exemptions.** `writer: chalk` lets a wire off the invariant. V10 guesses which `local` is live and is wrong for a closed inner block (`un75`). One `Call` in the corpus is on no chain (`398`).
10. **Leftovers.** `st3` has no name. `as_v1` guesses by kind. `SON_RATCHET=1` is opt-in.

## 6. What was run, and what was not

Run here, at 888d71b / f1d9aa74:

- chalk `tools/audit-probes.pl` over all 2351 gated probes;
- 828 new probes, three rounds, then all of them once more (`_run1.log`; no verdict moved between runs);
- `tools/wire-verify.pl --corpus --probes` (corpus 431, probes 3184 with the new ones: 2 violations, both new, both moved to `z/unverified/`);
- a scan of my own over the same 3613 wires (`mem_in`, `inputs`, records, places, loops, calls);
- `t/wire-verify-ratchet.t` (without chalk's lib) and `t/loop-body-is-walked-once.t`, both with `probes/z/` in place; `t/placement-one-constructor.t`, `t/effect-table-has-a-row-for-every-builtin.t`, `t/wire-verify-rejects-hand-broken-wires.t`, `t/wire-verify-v2.t`, `t/package-scalar-of-an-unscanned-package-is-written.t`;
- chalk's `t/bootstrap/ir/wire-verify.t`;
- wire dumps for one probe of each wrong class.

Not run: either full suite, the census, the corpus gate, the deparser round trip, the ratchet over chalk's lib, `tools/alias-fastpath.pl`. The side of each class is read off one wire, not from the source. The new probes are not in chalk's `t/data/audit-probes`: the gate does not hold them yet.
