# Final audit of the goal "Make the SoN memory model mechanical and checked, measured" (2026-11-24)

Producer `/home/user/repo`, `wip/chalk-lib-roundtrip`, a5df593. Chalk `/home/perigrin/dev/chalk`, `bson/llvm-corpus`, 93c01e4c. No code was changed: this file, the probes in `docs/research/son-ir-audit-2026-11-19/probes/f/`, one README line and one memory note are the whole commit. It follows the re-audit (`2026-11-23-memory-model-goal-re-audit.md`, heads 27b1d74 / a8057fb6).

## Verdict

**The gates hold. The goal's first sentence does not.**

- Every gate I re-ran passes: 1451 gated probes with WRONG 0 and no verdict changed, the verifier over the corpus and the old probes with 0 violations, the ratchet, the clause tests.
- Every finding of the re-audit is closed: classes A and B are lowered, C to G are refused by name, the two verifier holds are gone.
- But 847 new one-line probes found **111 silent wrong answers** in nine classes. That is 13% of them. Every one of the 111 wires passes `SoN::Verify` clean.
- None is a regression. All 111 were already wrong at the re-audit's heads and at the heads before designs A and B1 (`probes/f/_base.log`).
- Several are everyday code:
  - `my $l=[1,2]; my @c=@$l; push @$l,3; print scalar(@c)` prints 3.
  - `our ($x,$y)=(1,2); my $t=0; for ($x,$y) { $t+=$_ } print $t` prints 0.
  - `my $s="abc"; my $c=chop $s; print $c` prints 1.

The model is checked for the shapes the probe set holds. It is not yet sound for Perl's aliases, for a read made later than the version it names, or for a store the producer has no handler for.

## 1. Verdict per clause

| clause | verdict | what holds | what does not |
|---|---|---|---|
| (1) No silent wrong answers from the audit | **PARTLY MET** (met to the letter) | All 1451 gated probes re-run here: SAME 1145, REFUSED 297, LOUD 9, WRONG 0; no verdict differs from chalk's `t/data/audit-probes/BASELINE.tsv`. The 22 producer-only probes (`probes/w/`): 22 SAME. One refusal has no name (`st3`: "no program graph"); the re-audit counted 48. | 111 new wrong answers in the neighbourhood (section 3). The fix probes for designs A and B1 (`cpa01`-`cpa35`) are in chalk's `t/data/audit-probes` only, not beside the audit's probes in the producer. The 9 LOUD are run-time refusals with a name, not perl's answer. |
| (2) Producer placement is mechanical | **PARTLY MET** | `_place` and `_pin` at `lib/SoN/FromOptree.pm:880`, `:889`; `t/placement-one-constructor.t` passes. `_target_storage` `:22848`; `_key_lives_in_memory` `:14618`; `_may_fault` `:939`; `B::SoN::EffectTable` (`on_chain`, `lib/B/SoN/EffectTable.pm:186`, read at `FromOptree.pm:13473`, `:13517`); `t/effect-table-has-a-row-for-every-builtin.t` passes. A dynamic method call is on both chains (wire dumped here: `dispatch_kind: dynamic_method`, `control_in`, `mem_in`, `mem_out`). No list-assign probe is WRONG (`f/w01`-`w30`: 22 SAME, 8 refused). | A may-fault division still floats: `sub f { sprintf("%d", 1/$_[0]) }` (verifier: `effect-floating`; `f/unverified/d61`). `set_control_in` is still written by hand at `:3459`, `:5060`, `:5178`, and the source test matches one spelling only. A package scalar in a foreach list is not read through memory: `for ($x,$y)` puts two `EntryDef`s with no `mem_in` into an `ArrayLiteral` (class E). A store with no handler never reaches the constructor: `($x = 5) += 2` and `($c ? $a : $b) = 9` leave no store on the wire and no GAP (class D). |
| (3) Wire v2 | **MET, with three caveats** | Scanned here over 2703 wires (corpus 431, probes 2272): every `Return` (4297), `EntryWrite` (2888), sub `Call` (2289), non-record `Assign` (2249; the other 158 are flagged `record`), `Delete`, `CellWrite` has `mem_in`; no `MemStart` or memory Phi is in any `inputs`; every non-record `Assign` is on both chains; every `Loop` has one or two inputs, and 1023 of the 1063 have their test's `If` directly on the header (the other 40 were not looked at); 511 `Exc`, 112 rethrow `Unwind`. chalk `lib/`: grep for `is_memory\b`, `is_placed`, `memory_input`, `WireUpgrade` finds one comment (`lib/Chalk/IR/Node/Phi.pm:42`). | `record` is still derived by the serializer (`lib/SoN/Serialize/JSON.pm:218`). "Without the double walk" holds while every guess holds: a wrong guess walks the sub again (`%LOOP_HINTS`, `FromOptree.pm:14755-14767`, `:25219-25222`). Not every memory read names a version: 26 `ArrayLiteral`s and 2 Phis in the probe wires take an `EntryDef` with no `mem_in` as a value (class E, and `f/i03`). Positional memory survives in the producer's deparser (`lib/SoN/Deparse.pm:174`, `:1531`). |
| (4) Checked | **PARTLY MET** | `SoN::Verify`: `write-unreachable` `lib/SoN/Verify.pm:273`, `read-unversioned` `:411`. Run here: corpus 431 wires, 0 violations; the 1428 older probes, 0 violations; `t/wire-verify-ratchet.t` passes with `%HELD` empty; `t/wire-verify-rejects-hand-broken-wires.t` passes. chalk loader: `WireInvariant` L1-L9, called at `lib/Chalk/IR/Serialize/JSON.pm:1316`; chalk's `t/bootstrap/ir/wire-verify.t` over chalk's lib and its probes: passes here (3 tests run, none skipped). | "Passes on the probes" is true of the probes it was tuned on: 3 of the 847 new ones break a rule (section 3.3). The loader still skips the invariant and `WireCheck` for a wire with no `dowarn` key (chalk `JSON.pm:1312-1319`, `:1419`). The producer's ratchet checks chalk's lib only with `SON_RATCHET=1`; chalk's test is `skip_all` without the producer. The verifier sees none of the 111 wrong wires. |

Clause 5 (verified and pushed) was not asked for here. I did not re-run either full suite, the census or the corpus gate.

## 2. The design against the literature

### Click, sea of nodes

What matches: effects are nodes on a control chain; memory is a state edge that a store takes and makes; a read takes one; Phis merge states at Regions. One alias class for the whole heap is coarser than C2's sliced memory. That costs precision, not soundness.

Departures:

1. **A read that names an old version can be made late. Not sound as built.** In Click's IR a load floats, and the scheduler adds an anti-dependence so it is never placed after a store that kills its state. Here the wire is right and the consumer is not: in `my $l=[1,2]; my @c=@$l; push @$l,3`, the copy is `PostfixDeref {copy, mem_in: MemStart}` and the `push` is the next version, but chalk makes the copy after the push (class B, 17 probes). The re-audit recorded this as "a consumer rule, not a wire fact". The rule has holes, and no wire check can see them.
2. **A `my` aggregate's location is still a value node.** Design A makes a copy a new node, which closed the re-audit's class A. But identity is still "which node the name is bound to", and a reader can still be handed the wrong node: `my @c=@a; w(); print "@c"` joins the `PadAccess` of `@a`, not the literal of `@c` (class A here, 12 probes). Sound only if every reader goes through the copy's node. Nothing checks that.
3. **Aliases are outside the model. Not sound.** Click's IR was built for Java, where an argument is a value. In Perl `@_`, a foreach variable, `$_` in map and grep, and a method's invocant are aliases. The wire passes an argument as a value at a version, and patches the common cases (copy-in and copy-out, a demoted iterator with a write-back, by-name refusals). Classes C, E, G and H, 52 probes, are what the patches miss.
4. **A store exists only where a handler makes one.** In Click's parser every assignment is a store by construction. Here an lvalue the producer has no rule for is dropped without a GAP (class D).

### Braun et al. 2013

What matches: incomplete Phis at an unsealed loop header, memory as one more variable, trivial Phis removed, no dominance frontiers.

Departures:

1. **A wrong guess walks the sub again.** Braun never guesses: a read in an unsealed block makes an operandless Phi. The guesses here are about things Braun's variables do not have (a stamp, whether a literal is mutated later, an alias write-back). Sound while sealing catches every wrong guess, and it ends while the hints only grow. Both are held by tests, not by construction.
2. **Braun's variables have no aliases.** The algorithm is for locals whose address is never taken. A foreach iterator is an alias, kept as an SSA binding and written back. The write-back is lost when the pass ends by a `die` (class G): the same precondition, broken.

### Memory SSA

`mem_out`, `mem_in` and the memory Phi are MemoryDef, MemoryUse and MemoryPhi over one heap partition. Two real differences:

- In LLVM, MemorySSA is derived from ordered instructions and can be verified against them. Here it is the only order and the optree is gone. So the verifier proves the wire well-formed, never that it is the program. Section 3 is the measure: 111 wrong wires, 0 violations.
- In LLVM a MemoryUse stays in its block, in order. Here a read floats and the version is its only anchor (departure 1 above).

### Exception edges (C2, Graal)

What matches: an `Exc` per node that may die, merged at a catch Region with a memory Phi, with the `local` restores and the `$@` store on the edge. That is Graal's `InvokeWithException`. Design B1's rethrow edge is Graal's `UnwindNode`. V10 and L7 check the shape.

Departures:

1. **An edge exists only where an eval is open or a `local` is live.** Graal gives every invoke an exceptional successor and removes the dead ones. The shortcut is sound only if a restore is the one thing that must happen on the way out. It is not: a pending foreach write-back must happen too (class G), and `finally` and `defer` would (refused today). Graal carries this in a FrameState at each throwing node. The wire has no such thing.
2. **What may die is a list.** `_dies_by_its_values` (`FromOptree.pm:913`) knows a dereference, an element reference, `Divide` and `Modulo`. Other faults (an lvalue `substr`, a call of undef, a strict deref of a string through a hash) are caught by T2 at run time and stop the program, even inside an eval where perl would carry on (LOUD: `f/d58`, `d67`, `d68`, `d70`). Loud, not silent. Sound.
3. **The wire cannot say a `local` is live** (the project's own note). So only V10 checks that an edge exists, and only over the ratchet's wires.

## 3. New probes

847 programs, written for this audit and run as the probe gate runs them (`AuditProbe::run_all`, 4 jobs): 844 in `probes/f/`, 3 in `probes/f/unverified/` (section 3.3). Verdicts are in `probes/f/_run1.log`.

| group | aimed at | n | SAME | REFUSED | LOUD | WRONG |
|---|---|---|---|---|---|---|
| c | copies | 65 | 54 | 9 | 0 | 2 |
| g | copies read after a call or a store | 60 | 29 | 5 | 0 | 26 |
| d | `local` plus die | 75 | 50 | 21 | 4 | 0 |
| e | eval and try | 65 | 51 | 13 | 0 | 1 |
| n | an alias write, then a die | 24 | 7 | 5 | 0 | 12 |
| l | loops, write-back | 70 | 47 | 21 | 0 | 2 |
| a | aliasing, order of evaluation | 85 | 65 | 16 | 0 | 4 |
| h | an argument alias the callee writes | 20 | 3 | 0 | 0 | 17 |
| j | foreach, map, grep over scalars and elements | 28 | 5 | 7 | 0 | 16 |
| i | an assignment or a ternary as an lvalue | 28 | 2 | 14 | 0 | 12 |
| p | `$_[N] = ...` in a method | 12 | 7 | 4 | 0 | 1 |
| k | closures | 45 | 33 | 12 | 0 | 0 |
| o | objects | 20 | 14 | 5 | 0 | 1 |
| s | scopes, calls among operands | 60 | 51 | 8 | 0 | 1 |
| w | list assignment, hash truth | 30 | 22 | 8 | 0 | 0 |
| b | builtins, may-fault division, dynamic methods | 95 | 84 | 7 | 1 | 3 |
| m | chop, chomp, value builtins | 40 | 21 | 11 | 0 | 8 |
| q | regex captures | 25 | 12 | 7 | 1 | 5 |
| **all** | | **847** | **557** | **173** | **6** | **111** |

What came through clean: closures (45, none wrong), `local` plus die (75, none wrong: design B1 holds), list assignment and hash truth (30, none wrong), and 64 of 65 eval and try probes. All 173 refusals name a cause; none is an internal error or "no program graph".

### 3.1 The nine wrong classes

| class | what | n | side | traced on |
|---|---|---|---|---|
| A | A copy of a `my` array a sub also reaches reads the source after a later call. | 12 | producer: the join reads the `PadAccess` of `@a`, not `@c`'s literal | `f/c56` |
| B | A copy through a reference (`my @c=@$l`, `my %c=%$h`) is made after a later store. | 17 | chalk: the wire names the old version, the copy is made late | `f/g30`, `f/g35` |
| C | A callee writes a variable, then reads it through `$_[N]`. | 19 | both: the wire passes the argument as a value | `f/h01`, `f/h04` |
| D | An assignment or a ternary used as an lvalue: the store is dropped. | 14 | producer: no store on the wire, no GAP | `f/i05`, `f/s13` |
| E | foreach, map, grep or a call over package scalars or elements: aliases lost, reads give 0, elements not vivified. | 18 | producer: `EntryDef`s with no version in an `ArrayLiteral` | `f/j02`, `f/j23` |
| F | The value of `chop` is 1, not the character removed. | 10 | chalk: the wire says `ChompValue {kind: chop}` | `f/m01` |
| G | A foreach alias write is lost when the pass ends by a die caught outside. | 13 | producer: the `Exc` edge has no write-back | `f/n04` |
| H | `$_[0] = ...` in a method does not reach the caller's invocant. | 2 | not traced | |
| I | `$1` is not put back at a block's end; `$2` survives a later match with one group. | 6 | producer: `RegexCapture` reads the last match made | `f/q01` |

Classes C, H and the vivifying part of E are not traced past one wire each. Class F and class I are builtin semantics, not the memory model, but they are silent.

Six LOUD: `f/b69` (`my %i = reverse %h` stops with "a hash element read through no HASH reference", which names nothing the program does), `f/q06` (a run-time refusal by name), and `f/d58`, `d67`, `d68`, `d70` (a fault inside an eval stops the program). `f/d58` was REFUSED before design B1 lifted W6, as `req35` was.

### 3.2 Every WRONG

#### A (12)

| probe | program | perl | chalk |
|---|---|---|---|
| f/c56 | `my @a=(1,2); sub w { $a[0]=9 } my @c=@a; w(); print "@c\n";` | `1 2` | `9 2` |
| f/g01 | `my @a=(1,2); sub w { push @a,3 } my @c=@a; w(); print "@c\n";` | `1 2` | `1 2 3` |
| f/g02 | `my @a=(1,2); my $w=sub { $a[0]=9 }; my @c=@a; $w->(); print "@c\n";` | `1 2` | `9 2` |
| f/g03 | `my @a=(1,2); sub w { $a[0]=9 } my @c=(@a); w(); print "@c\n";` | `1 2` | `9 2` |
| f/g08 | `my @a=(1,2); sub w { $a[0]=9 } sub f { my @c=@a; w(); "@c" } print f(),"\n";` | `1 2` | `9 2` |
| f/g12 | `my @a=(1,2); sub w { $a[0]=9 } my @c=@a; for (1..2) { w() } print "@c\n";` | `1 2` | `9 2` |
| f/g13 | `my @a=(1,2); sub w { $a[0]=9 } my @c; @c=@a; w(); print "@c\n";` | `1 2` | `9 2` |
| f/g19 | `my @a=(1,2); sub w { $a[0]=9 } my @c=(0,@a); w(); print "@c\n";` | `0 1 2` | `0 9 2` |
| f/g24 | `my @a=(1,2); sub w { $a[0]=9 } my @c=@a; print "@c\n"; w(); print "@c\n";` | `1 2 1 2` | `1 2 9 2` |
| f/g25 | `my @a=(1,2); sub w { $a[1]="z" } my @c=@a; w(); my @d=@a; print "@c\|@d\n";` | `1 2\|1 z` | `1 z\|1 z` |
| f/g26 | `my @a=("x"); sub w { $a[0].="y" } my @c=@a; w(); w(); print "@c @a\n";` | `x xyy` | `xyy xyy` |
| f/g28 | `my @a=(1,2); sub w { $a[0]=9 } my @c=@a; if (@c) { w() } print "@c\n";` | `1 2` | `9 2` |

#### B (17)

| probe | program | perl | chalk |
|---|---|---|---|
| f/a78 | `sub ap { push @{$_[0]}, $_[1]; $_[0] } my $l=[]; ap(ap($l,1),2); my @c=@$l; ap($l,3); print scalar(@c), scalar(@$l), "\n";` | `23` | `33` |
| f/c52 | `my @a=(1,2); my %h=(k=>\@a); my @c=@{$h{k}}; push @a,3; print scalar(@c), scalar(@{$h{k}}),"\n";` | `23` | `33` |
| f/g30 | `my $l=[1,2]; my @c=@$l; push @$l,3; print scalar(@c),"\n";` | `2` | `3` |
| f/g31 | `my $l=[1,2]; sub ap { push @{$_[0]},3 } my @c=@$l; ap($l); print scalar(@c),"\n";` | `2` | `3` |
| f/g33 | `my @a=(1,2); my $r=\@a; my @c=@$r; push @a,3; print scalar(@c),"\n";` | `2` | `3` |
| f/g35 | `my $h={a=>1}; my %c=%$h; $h->{b}=2; print scalar(keys %c),"\n";` | `1` | `2` |
| f/g36 | `my $h={a=>1}; sub ad { $_[0]{b}=2 } my %c=%$h; ad($h); print scalar(keys %c),"\n";` | `1` | `2` |
| f/g38 | `my $o={l=>[1]}; sub ad { push @{$_[0]{l}},2 } my @c=@{$o->{l}}; ad($o); print scalar(@c),"\n";` | `1` | `2` |
| f/g39 | `my $l=[1,2]; my $n=@$l; push @$l,3; my @c=@$l; push @$l,4; print $n, scalar(@c),"\n";` | `23` | `24` |
| f/g40 | `sub ap { push @{$_[0]}, $_[1]; $_[0] } my $l=[]; ap($l,1); my @c=@$l; ap($l,3); print scalar(@c), scalar(@$l), "\n";` | `12` | `22` |
| f/g41 | `sub ap { push @{$_[0]}, $_[1] } my $l=[]; ap($l,1); my @c=@$l; ap($l,3); print scalar(@c), "\n";` | `1` | `2` |
| f/g42 | `my $l=[1]; my @c=(@$l); my @d=(0,@$l); push @$l,2; print scalar(@c),scalar(@d),"\n";` | `12` | `23` |
| f/g49 | `my @a=(1,2); my %h=(k=>\@a); my @c=@{$h{k}}; push @{$h{k}},3; print scalar(@c),"\n";` | `2` | `3` |
| f/g57 | `package P; sub new { bless {l=>[1]}, shift } sub add { push @{$_[0]{l}}, $_[1] } package main; my $p=P->new; my @c=@{$p->{l}}; $p->add(2); print scalar(@c),"\n";` | `1` | `2` |
| f/g58 | `package P; sub new { bless {l=>[1]}, shift } sub snap { my $s=shift; my @c=@{$s->{l}}; push @{$s->{l}},2; scalar @c } package main; print P->new->snap,"\n";` | `1` | `2` |
| f/g59 | `package P; sub new { bless {h=>{a=>1}}, shift } sub snap { my $s=shift; my %c=%{$s->{h}}; $s->{h}{b}=2; scalar keys %c } package main; print P->new->snap,"\n";` | `1` | `2` |
| f/g60 | `sub f { my $l=shift; my @c=@$l; push @$l,9; return scalar @c } print f([1,2]),"\n";` | `2` | `3` |

#### C (19)

| probe | program | perl | chalk |
|---|---|---|---|
| f/a30 | `my $x=1; sub f { $x=2; $_[0] } print f($x), "\n";` | `2` | `1` |
| f/a32 | `our $x=1; sub f { $x=2; $_[0] } print f($x), "\n";` | `2` | `1` |
| f/h01 | `my $x=1; sub f { $x=2; return $_[0] } my $v=f($x); print "$v\n";` | `2` | `1` |
| f/h02 | `my $x=1; sub f { $x=2; "$_[0]" } print f($x),"\n";` | `2` | `1` |
| f/h03 | `my $x=1; sub f { $x++; $_[0]+0 } print f($x),"\n";` | `2` | `1` |
| f/h04 | `our $x=1; sub f { my $o=$_[0]; $x=2; "$o$_[0]" } print f($x),"\n";` | `12` | `11` |
| f/h05 | `our @a=(1); sub f { $a[0]=2; $_[0] } print f($a[0]),"\n";` | `2` | `1` |
| f/h06 | `my %h=(k=>1); sub f { $h{k}=2; $_[0] } print f($h{k}),"\n";` | `2` | `1` |
| f/h07 | `our $x=1; sub g { $x=2 } sub f { g(); $_[0] } print f($x),"\n";` | `2` | `1` |
| f/h08 | `our $x=1; sub f { $x=2; my ($v)=@_; $v } print f($x),"\n";` | `2` | `1` |
| f/h10 | `our $x=1; sub f { $x=2; shift } print f($x),"\n";` | `2` | `1` |
| f/h12 | `my $x=1; my $f=sub { $x=2; $_[0] }; print $f->($x),"\n";` | `2` | `1` |
| f/h13 | `our $x=1; sub f { $x.="b"; length $_[0] } print f($x),"\n";` | `2` | `1` |
| f/h15 | `package C; our $x=1; sub m1 { $x=2; $_[1] } package main; print C->m1($C::x),"\n";` | `2` | `1` |
| f/h16 | `our $x=1; sub f { $x=2; return ($_[0], $_[0]+1) } my @r=f($x); print "@r\n";` | `2 3` | `1 2` |
| f/h17 | `my $o={n=>1}; sub f { $o->{n}=2; $_[0] } print f($o->{n}),"\n";` | `2` | `1` |
| f/h18 | `my @a=(1); sub f { $a[0]=2; $_[0] } print f($a[0]),"\n";` | `2` | `1` |
| f/h19 | `our $x=1; sub f { $x=2; if ($_[0] == 2) { return "new" } "old" } print f($x),"\n";` | `new` | `old` |
| f/h20 | `our $x=1; sub f { $x=2; my $y = $_[0] * 10; $y } print f($x),"\n";` | `20` | `10` |

#### D (14)

| probe | program | perl | chalk |
|---|---|---|---|
| f/b47 | `my $x=1; ($x += 2) *= 3; print "$x\n";` | `9` | `3` |
| f/s13 | `my ($a,$b)=(1,2); my $c=1; ($c ? $a : $b) = 9; print "$a$b\n";` | `92` | `12` |
| f/i01 | `my ($a,$b)=(1,2); my $c=0; ($c ? $a : $b) = 9; print "$a$b\n";` | `19` | `12` |
| f/i03 | `our ($a1,$b1)=(1,2); my $c=1; ($c ? $a1 : $b1) = 9; print "$a1$b1\n";` | `92` | `12` |
| f/i05 | `my $x=1; ($x = 5) += 2; print "$x\n";` | `7` | `5` |
| f/i07 | `my $x=1; (my $y = $x) += 5; print "$x$y\n";` | `16` | `11` |
| f/i09 | `my $x=1; my $y = (($x += 2) *= 3); print "$x$y\n";` | `99` | `39` |
| f/i10 | `our $x=1; ($x += 2) *= 3; print "$x\n";` | `9` | `3` |
| f/i11 | `my @a=(1); ($a[0] += 2) *= 3; print "@a\n";` | `9` | `3` |
| f/i14 | `my $x=1; sub inc { $_[0]++ } inc($x += 1); print "$x\n";` | `3` | `2` |
| f/i19 | `my ($a,$b)=(1,2); my $c=1; ($c ? $a : $b)++; print "$a$b\n";` | `22` | `12` |
| f/i20 | `my @a=(1,2,3); (my $t = $a[0]) *= 10; print "$t @a\n";` | `10 1 2 3` | `1 1 2 3` |
| f/i21 | `my $x=5; ($x -= 1) /= 2; print "$x\n";` | `2` | `4` |
| f/i24 | `my ($a,$b)=(1,2); my $c=1; ($c ? $a : $b) = ($c ? $b : $a) + 5; print "$a$b\n";` | `72` | `12` |

#### E (18)

| probe | program | perl | chalk |
|---|---|---|---|
| f/l25 | `our ($x,$y)=(1,2); for ($x,$y) { $_*=3 } print "$x $y\n";` | `3 6` | `0 0` |
| f/a67 | `my @a; for my $x ($a[2]) { } print scalar(@a),"\n";` | `3` | `0` |
| f/j02 | `our ($x,$y)=(1,2); for my $v ($x,$y) { $v*=3 } print "$x $y\n";` | `3 6` | `0 0` |
| f/j04 | `our @a=(1,2); our $x=5; for (@a,$x) { $_*=2 } print "@a $x\n";` | `2 4 10` | `2 4 0` |
| f/j07 | `our ($x,$y)=(1,2); $_*=3 for $x,$y; print "$x $y\n";` | `3 6` | `0 0` |
| f/j08 | `our ($x,$y)=(1,2); map { $_*=3 } $x,$y; print "$x $y\n";` | `3 6` | `0 0` |
| f/j09 | `our ($x,$y)=(1,2); my @g=grep { $_*=3 } $x,$y; print "$x $y\n";` | `3 6` | `0 0` |
| f/j10 | `our ($x,$y)=(1,2); s/^/a/ for $x,$y; print "$x $y\n";` | `a1 a2` | `a a` |
| f/j16 | `my %h; for my $x ($h{k}) { } print exists $h{k}?1:0,"\n";` | `1` | `0` |
| f/j17 | `my @a; my @b=map { $_ } $a[2]; print scalar(@a),"\n";` | `3` | `0` |
| f/j18 | `my @a; for (@a[0,1]) { } print scalar(@a),"\n";` | `2` | `0` |
| f/j19 | `our ($x,$y)=(1,2); for ($x,$y) { $_*=3; } my $s=$x+$y; print "$s\n";` | `9` | `0` |
| f/j22 | `our $x=1; for ($x) { $_++ } for ($x) { $_*=5 } print "$x\n";` | `10` | `0` |
| f/j23 | `our ($x,$y)=(1,2); my $t=0; for ($x,$y) { $t+=$_ } print "$t\n";` | `3` | `0` |
| f/j24 | `our ($x,$y)=(1,2); for ($x,$y) { $_ = "v$_" } print "$x$y\n";` | `v1v2` | `vv` |
| f/j25 | `my @a; for my $x (@a[1..2]) { } my %h; for my $v (@h{qw(a b)}) { } print scalar(@a), scalar(keys %h), "\n";` | `32` | `00` |
| f/j27 | `my @a; sub noop {} noop($a[3]); noop(@a[0,1]); print scalar(@a),"\n";` | `2` | `0` |
| f/j28 | `my %h; my @v=map { $_ } @h{qw(a)}; my @g=grep { 1 } $h{b}; print scalar(keys %h),"\n";` | `2` | `0` |

#### F (10)

| probe | program | perl | chalk |
|---|---|---|---|
| f/b55 | `my $s="ab\n"; my $c=chomp($s); my $d=chop($s); print "$c$d$s\n";` | `1ba` | `11a` |
| f/l68 | `my $s="abc"; my $o=""; while (length $s) { $o.=chop $s; } print "$o [$s]\n";` | `cba [` | `111 []` |
| f/m01 | `my $s="abc"; my $c=chop $s; print "$c $s\n";` | `c ab` | `1 ab` |
| f/m02 | `my $s="abc"; my $t=chop($s).chop($s); print "$t $s\n";` | `cb a` | `11 a` |
| f/m30 | `my $s="abc"; my $o=""; $o.=chop($s) for 1..2; print "$o $s\n";` | `cb a` | `11 a` |
| f/m32 | `my $s="ab"; my @l=(chop($s), $s); print "@l\n";` | `b a` | `1 a` |
| f/m34 | `my $s="abc"; my $c = chop $s; my $d = chop $s; print "$c$d$s\n";` | `cba` | `11a` |
| f/m35 | `our $s="abc"; my $c=chop $s; print "$c $s\n";` | `c ab` | `1 ab` |
| f/m38 | `my $s="abc"; print chop($s), "\n";` | `c` | `1` |
| f/m39 | `my $s="abc"; my $c = chop($s) . "!"; print "$c\n";` | `c!` | `1!` |

#### G (13)

| probe | program | perl | chalk |
|---|---|---|---|
| f/e25 | `my @a=(1,2); eval { for my $x (@a) { $x.="!"; die "x\n" } }; print "@a\n";` | `1! 2` | `1 2` |
| f/n04 | `my @a=(1,2); sub d { die "x\n" } eval { for my $x (@a) { $x.="!"; d() } }; print "@a\n";` | `1! 2` | `1 2` |
| f/n05 | `my @a=(1,2); eval { for my $x (@a) { $x.="!"; die "x\n" if $x eq "2!" } }; print "@a\n";` | `1! 2!` | `1! 2` |
| f/n10 | `my %h=(a=>1); eval { for my $v (values %h) { $v=5; die "x\n" } }; print "$h{a}\n";` | `5` | `1` |
| f/n13 | `my @a=(1,2); my $z=0; eval { for my $x (@a) { $x.="!"; my $q=1/$z; } }; print "@a\n";` | `1! 2` | `1 2` |
| f/n14 | `use feature 'try'; no warnings; my @a=(1,2); try { for my $x (@a) { $x.="!"; die "x\n" } } catch ($e) { } print "@a\n";` | `1! 2` | `1 2` |
| f/n16 | `my @a=(1,2); eval { for my $x (@a) { $x="q"; die "x\n" if $x; } 1 }; print "@a\n";` | `q 2` | `1 2` |
| f/n17 | `our @a=(1,2); eval { for my $x (@a) { $x.="!"; die "x\n" } }; print "@a\n";` | `1! 2` | `1 2` |
| f/n18 | `my $r=[1,2]; eval { for my $x (@$r) { $x.="!"; die "x\n" } }; print "@$r\n";` | `1! 2` | `1 2` |
| f/n19 | `my @a=(1,2); eval { for my $x (@a) { $x.="!"; die "x\n" } }; print "@a $@";` | `1! 2 x` | `1 2 x` |
| f/n21 | `my @a=(1,2); my $n=0; eval { for my $x (@a) { $n++; $x=0; die "x\n" } }; print "$n @a\n";` | `1 0 2` | `1 1 2` |
| f/n22 | `my @a=(1,2); eval { for my $x (@a) { $x.="!"; eval { die "in\n" }; die "x\n" } }; print "@a\n";` | `1! 2` | `1 2` |
| f/n23 | `my @a=(1,2); eval { for my $x (@a) { for my $y (@a) { $y.="!"; die "x\n" } } }; print "@a\n";` | `1! 2` | `1 2` |

#### H (2)

| probe | program | perl | chalk |
|---|---|---|---|
| f/o14 | `package C; sub new { bless {}, shift } sub repl { $_[0] = "gone" } package main; my $o=C->new; $o->repl; print ref($o) ? "obj" : $o, "\n";` | `gone` | `obj` |
| f/p02 | `package C; sub new { bless {}, shift } sub nul { $_[0] = undef } package main; my $o=C->new; $o->nul; print defined $o ? "d" : "u", "\n";` | `u` | `d` |

#### I (6)

| probe | program | perl | chalk |
|---|---|---|---|
| f/b17 | `my $s="abc"; $s=~/(b)/; my $x=$1; { "q"=~/(q)/; } print "$x$1\n";` | `bb` | `bq` |
| f/q01 | `"ab"=~/(a)/; { "xy"=~/(y)/; } print "$1\n";` | `a` | `y` |
| f/q02 | `"ab"=~/(a)/; if (1) { "xy"=~/(y)/; } print "$1\n";` | `a` | `y` |
| f/q05 | `"ab"=~/(a)/; my $t = do { "xy"=~/(y)/; $1 }; print "$t$1\n";` | `ya` | `yy` |
| f/q07 | `"ab"=~/(a)(b)/; "c"=~/(c)/; print defined $2 ? 1 : 0, "\n";` | `0` | `1` |
| f/q19 | `"ab"=~/(a)/; { "xy"=~/(y)/; print $1; } print "$1\n";` | `ya` | `yy` |

### 3.3 Three new verifier violations

The ratchet reads `probes/*/*.pl`, so these three are in `probes/f/unverified/`, where it does not look. Each prints what perl prints. With them in `probes/f/` the ratchet fails, as it should (checked here with `d61`).

| probe | program | rule |
|---|---|---|
| `a55` | `my @a=(1,2,3); my ($x,@a2)=@a; @a=(@a2,$x); print "@a\n";` | `read-unversioned:my-aggregate` (`PadAccess @a2`) |
| `d61` | `our $g=1; sub f { local $g=2; sprintf("%d", 1/$_[0]) } ...` | `effect-floating` (a `Divide` that may fault on no control chain). `sub f { sprintf("%d", 1/$_[0]) }` alone has it too. |
| `o11` | a `class` with `field @h` and `push @h,$x` in a method | `read-unversioned:field` (`FieldAccess`) |

## 4. Design risks, ranked

1. **Aliases are not in the model** (classes C, E, G, H: 52 wrong). Each alias kind is a special case with its own refusals, and each audit finds the cases between them. `for ($x,$y)` over package scalars reads 0 even when the body writes nothing. This needs one decision: an alias is a reference on the wire, or every alias the wire cannot say is refused by what perl does, not by op shape.
2. **A floating read is anchored only by the version it names** (class B: 17 wrong). chalk must make every read before the next version, and does not for a copy through a reference. The wire is right, so no verifier rule can catch it. Pin the copy, as a may-die read is pinned, or prove the consumer rule on every read kind.
3. **A store with no handler is dropped, not refused** (class D: 14 wrong). The one constructor cannot help: the node is never made. `docs/memory/a-silent-drop-is-worse-than-a-refusal.md` already says so. The default for an lvalue op with no rule should be a GAP.
4. **The verifier checks form, not meaning.** 111 of 111 wrong wires are clean. The gated probe set says WRONG 0 while a fresh set of 847 says 111. The zero measures the probe set. Each audit's fresh probes have found a similar rate (59, 55, 68, 111).
5. **A location is a node** (class A: 12 wrong). The list shortcut hands a reader the source's node. Design A fixed the write side for copies; the read side is open.
6. **Work that must happen on every way out is only half modelled.** `local` restores are on the exceptional edges. A pending write-back is not (class G). `finally` and `defer` are refused. Edges exist only under an eval or a live `local`.
7. **The verifier's own exemptions.** An `EntryDef` with no version passes as an "alias list" input (class E). Three new probes break rules that were at 0 (section 3.3). The loader skips its invariant for a wire with no `dowarn`.
8. **Builtin values are trusted** (classes F and I: 16 wrong). `chop` has returned 1 since before the first audit, and chalk's three `chop` probes are all `chomp`.
9. **Refusal is the main result outside the corpus shapes.** 173 of 847 are refused, about half of them by T2's "out of its slices". That is sound. It also hides what is behind it: each lifted refusal so far has shown older wrong answers.
10. **Leftovers from the re-audit**: three hand-set `control_in`s, the derived `record` flag, the re-walk on a wrong guess, positional memory in the deparser, `time`/`sleep`/`rand` not ordered on the wire.

## 5. What was run, and what was not

Run here, at a5df593 / 93c01e4c:

- chalk `tools/audit-probes.pl` over all 1451 gated probes;
- the 22 `probes/w/` programs;
- 847 new probes, and the 117 that were WRONG or LOUD again at 27b1d74 / a8057fb6 and at ba42f34 / 4ba00e14;
- `tools/wire-verify.pl --corpus --probes` (2706 wires) and a scan of my own over the same wires (`mem_in`, `inputs`, records, loops);
- `t/wire-verify-ratchet.t` (without chalk's lib), `t/placement-one-constructor.t`, `t/effect-table-has-a-row-for-every-builtin.t`, `t/wire-verify-rejects-hand-broken-wires.t`, `t/loop-body-is-walked-once.t`, `t/wire-verify-v2.t`;
- chalk's `t/bootstrap/ir/wire-verify.t`;
- wire dumps for one probe of each traced class.

Not run: either full suite, the census, the corpus gate, the deparser round trip, the ratchet over chalk's lib. Classes C and H are not traced to a side. I did not look for the cause of any class in the source: the side is read off the wire.
