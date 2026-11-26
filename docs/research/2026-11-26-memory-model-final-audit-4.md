# Fourth final audit of the goal "Make the SoN memory model mechanical and checked, measured" (2026-11-26)

Producer `/home/user/repo`, `wip/chalk-lib-roundtrip`, 7656d8ef. Chalk worktree `combo-c`, `bson/llvm-corpus`, 07111727. No code was changed. The commit is this file, the probes in `docs/research/son-ir-audit-2026-11-19/probes/x/`, one README line and one memory note. It follows the three final audits and the "places everywhere" design (`docs/plans/2026-11-25-places-everywhere.md`).

## Verdict

**The gates hold. The goal's first sentence still does not: 825 new probes found 72 silent wrong answers in seven classes, and three of audit 3's wrong answers are still wrong and were never put in the gate.**

- The gated probe sweep, re-run here: SAME 3383, REFUSED 1086, LOUD 36, WRONG 0. No verdict differs from `BASELINE.tsv`.
- The 110 audit-3 probes that `BASELINE.tsv` leaves out by name ("they come in when the decision is made") are still out. Run here: SAME 79, REFUSED 26, WRONG 5. Three are real (`yc147`, `yp100`, `yp114`, class N5). `yp13` depends on perl's hash order and `ya57` reads a freed scalar; neither counts.
- 825 new one-line probes: SAME 531, REFUSED 218, LOUD 4, WRONG 72 (8.7%). First round, 512 broad probes: 7 wrong (1.4%; audit 3's broad round was 2.9%, its aimed round 6.4%). Second rounds, 313 probes written around each first-round wrong: 65 wrong.
- **16 of the 72 are made by the promotion pass.** With `SON_NO_PROMOTE=1` all 16 print perl's answer. `SoN::AliasProof::conflict` calls a closure-captured or referenced `my` scalar private. Verifier rule V14 runs the same predicate and passes all 16.
- The other 56 are in construction, so the "naive and always correct" wire is not: `local` on a slice is dropped with no restore and no refusal (15), the value of a list assignment in list context is its count (13), an operand perl pushes as an SV is read too early for consumers the rule does not list (14), a reference to a range-foreach iterator is one scalar for every pass (6), `*x = \42` stores a reference into `$x` (6), `tr///r` after a `tr` on the same variable yields the count (2).
- The verifier flags none of the 72 wrong wires. One new probe (`xt24`, refused by chalk) breaks `store-into-value`.

Three short examples:

- `sub f { $_[1]->(); $_[0] } my $x = 1; print f($x, sub { $x = 5 })` prints `1` for perl's `5`.
- `our @g = (1,2,3); { local @g[0,1] = (8,9); } print "@g"` prints `8 9 3` for perl's `1 2 3`.
- `my @a = (1,2); my ($x,$y) = @a[0,1] = (8,9); print "$x$y"` prints `2` for perl's `89`.

## 1. Verdict per clause

| clause | verdict | what holds | what does not |
|---|---|---|---|
| (1) No silent wrong answers from the audit | **MET for the gated set; NOT MET for the audit's probes as a whole** | Sweep re-run here over the 4505 gated probes (`t/data/audit-probes`, chalk): SAME 3383, REFUSED 1086, LOUD 36, WRONG 0, 0 rows differ from `BASELINE.tsv`. New probes for each fix are committed beside them (`pe/`, `al/`, `cpa/`). | `BASELINE.tsv` lines 3-18 leave 110 audit-3 probes out of the set by name. Three of them still print a different answer (`y/yc147`, `y/yp100`, `y/yp114`; section 4.8). The decision they waited for was made, and they were not brought in. 72 new wrong answers (section 4). Two new refusals have no name: `undef $$r` is "no program graph", an INTERNAL ERROR in B::SoN masked as a skip (`FromOptree.pm:24570`; `x/xd42`, `x/xq01`). |
| (2) Producer placement is mechanical | **MET for what reaches the constructor; NOT MET for what never does** | One constructor: `_place` `lib/SoN/FromOptree.pm:902`, `_pin` `:911`, `_seat` `:955` (the one write of `control_in`); `t/placement-one-constructor.t` passes here. List-assign targets by storage: `_target_storage` `:24588`, called at `:13245`; `t/wire-list-assign-places-by-storage.t` passes. Package scalars through memory: `_key_lives_in_memory` `:15512`, `_entry_live_value` `:15491`. Dynamic method: `dispatch_kind => 'dynamic_method'` `:6301`. Effect table: `B::SoN::EffectTable::on_chain` (`lib/B/SoN/EffectTable.pm:192`), asked at `FromOptree.pm:14343`, `:20898`, `:21036`; both effect-table tests pass. May-fault division: `_may_fault` `:961`, pinned at `:982`. | A store that gets no node is placed nowhere. `local` on an array or hash slice has no `local` mark, no save and no restore on the wire (X3). The constructor cannot be asked about a node that was not built, and there is no default GAP for an `OPpLVAL_INTRO` no handler read. |
| (3) Wire v2 | **MET** | My scan of the 825 new wires (1280 graphs; `probes/x/_verify.log`): all are version 2; every `Return` (1280), `Unwind` (41), `EntryWrite` (792), `CellWrite` (68), `Delete` (6), sub `Call` (599) and non-record `Assign` (614) has `mem_in`; no `MemStart` or memory Phi is in a value's `inputs`; 123 record `Assign`s are flagged; 46 `Exc`; 233 `Loop`s, each with one or two inputs. `%LOOP_HINTS` is one comment (`FromOptree.pm:15991`); `_braun_phis` `:15999`. chalk `lib/`: `Phi::is_memory` is one comment (`lib/Chalk/IR/Node/Phi.pm:42`); `is_placed`, `WireUpgrade`, `MEM_MIN_INPUTS` and `memory_input` do not occur. | Caveats, not breaches. The producer's own deparser still infers memory from input shape (`SoN::Deparse::_is_memory`, `lib/SoN/Deparse.pm:8955`, about 25 call sites) on the `as_v1` form. The wire is ambiguous in one place: a `Transliterate` named as an input means the string after it to B::SoN and the count to chalk (X6). |
| (4) Checked | **MET on the three named sets; the check is not independent** | `SoN::Verify`: `write-unreachable` `lib/SoN/Verify.pm:528`, `read-unversioned` `:705`, V12 `_alias_private` `:64`, V14 `_promoted_private` `:241`. Runs in both suites: producer `t/wire-verify-ratchet.t` (corpus, probes, chalk's lib with `SON_RATCHET=1`; `%HELD` empty), chalk `t/bootstrap/ir/wire-verify.t` (must-run in `tools/gates.sh:52`). `t/wire-verify-rejects-hand-broken-wires.t` passes here. Loader: every wire but a memory-free `writer: chalk` one is held to `WireInvariant` L1-L10 and `WireAliases` L11 (`lib/Chalk/IR/Serialize/JSON.pm:1354`-`1370`). | V14 re-proves a promotion with the pass's own predicate (`SoN::AliasProof`, by design, plan section 5). A fault in the predicate is invisible to both: 16 wrong wires, 0 violations. No rule looks for a `local` that has no restore or an operand read before a store its consumer follows, so the other 56 wrong wires are clean too. |

Clause 5 was not asked for. I did not run either full suite, the census or the corpus gate. I ran the probe sweep, five producer tests, and the three producer tests that read the probe directories (section 3).

## 2. Against the literature

Only real gaps are listed.

**MemorySSA (LLVM).** The wire has MemorySSA's shape: one chain of defs (`mem_out`), uses that name a def (`mem_in`), memory Phis. MemorySSA separates that structure from the question "does this def clobber this use", and its walker answers *may clobber* unless alias analysis proves otherwise. Here the question is answered by `SoN::AliasProof::conflict`, a table of source spellings whose last line is `return 0` (`lib/SoN/AliasProof.pm:254`). A source kind the table does not list is "no conflict". That is the fault behind X5: the table spells a `my` scalar `my:` at line 233 while `src` builds `my|G|$x` (line 63), so a store through a reference never conflicts with a `my` scalar. The default should be the other way round.

**LLVM alloca, mem2reg, SROA.** Design B cites this model, and the split is right: build places, promote after. Two differences matter.

- mem2reg promotes an alloca only when every use is a direct load or store. Escape is one syntactic test on the variable. `SoN::Promote` instead proves each call private with interprocedural store sets. Line 220 says a `my` scalar is beyond "code the wire cannot see" unless a `Ref` node names it, on the grounds that a captured one "would be a cell". It is not: in the caller's graph a captured `$x` is still a `PadAccess` beside its `MakeCell` (`probes/x/min/h1.pl`, nodes 6 and 8). A captured variable is an escaped alloca and mem2reg would never touch it.
- Clang's alloca form is correct by construction because every read is a load at its own program point. Perl is harder: an operand on the stack is the SV, read when its consumer runs. Construction handles this per consumer, and the list of consumers is a list of spellings again (X7). Section 1 of the design says "a fast path inside construction is as wide as the spellings it lists". That is still true of the operand rule, one level down.

**Translation validation (Necula; Alive2).** A checker earns trust by being independent of the transformation. V14 shares its predicate with the pass. The mutation tests (M19-M26) break the wire and confirm that V14 notices; none of them can show that the predicate is wrong on an unbroken wire. The cheap independent check already exists and is not a gate: run each probe with `SON_NO_PROMOTE=1` and compare. It separated the 16 in one pass over 69 wires.

**Braun et al.** Braun's construction needs no prior knowledge of what a loop writes: it puts operandless Phis in an unsealed header and removes the trivial ones at sealing. Here a pre-scan of the ops decides which slots get a Phi, and sealing checks the scan. It is one walk, and a miss is refused by name, so it is sound. It is a second source of truth read off spellings; seven new probes disagree with the walk on the safe side (section 3). Not a wrong-answer risk today.

**Click's sea of nodes; C2 memory slices.** C2 splits memory into alias classes, each store and load on its own slice, joined by `MergeMem` at calls. This wire has one fat chain, which is sound and simple. All precision is then recovered outside the IR by `AliasProof`'s source strings, which are alias classes computed late. If sources were slices on the wire, "no store to this source between these versions" would be a path property the verifier could check without the pass's predicate. That is the structural answer to the independence gap.

**HHVM boxed references; ECMAScript per-iteration bindings.** HHVM boxes any local that may be reference-bound and treats name, box and value as three things. The two-level `local` (a binding points at a scalar) is that model, applied to names some `local` binds. Two rebinding forms are outside it:

- A glob assignment rebinds a name exactly as `local` does. `*x = \$y` is refused in chalk by an incidental rule; `*x = \42` and `*x = \$a[1]` get through as a store of a reference into the static `$x` (X2).
- Each pass of a foreach gives the iterator a fresh scalar. ES2015 added `CreatePerIterationEnvironment` for the same reason. A counted foreach here keeps one memory slot for all passes, and the existing refusal for `\$i` covers list foreach only (X1).

## 3. Verifier and suite checks on the new probes

| check | result |
|---|---|
| `SoN::Verify` over 825 new wires, 1280 graphs | 2 violations in 1 probe: `xt24`, `store-into-value` (target is a `CellParam`: `sub { ($x,$y) = ($y,$x) }` over captures). chalk refuses it by name. Moved to `x/unverified/`. |
| structure (clause 3 scan, `_verify.log`) | 0 faults |
| `t/pre-scan-agrees-with-the-walk.t` with `x/` in place | fails on 7 new probes, all `missed=- extra=N` (the scan names a slot the walk does not; the safe side): `xb20`, `xj24`, `xk09`, `xk10`, `xk11`, `xk12`, `xl16`. Moved to `x/unverified/`, as audit 3 did. |
| `t/placement-one-constructor.t`, `t/wire-verify-rejects-hand-broken-wires.t`, `t/effect-table.t`, `t/effect-table-has-a-row-for-every-builtin.t`, `t/wire-list-assign-places-by-storage.t` | pass (84 tests) |
| `SON_NO_PROMOTE=1` on the 69 new wires that hold a `promoted` node (`_nopromote.log`) | 47 SAME both ways, 6 REFUSED both ways, **16 WRONG with promotion, SAME without** |
| `t/wire-verify-ratchet.t` (corpus and probes, no chalk lib), `t/pre-scan-agrees-with-the-walk.t`, `t/loop-body-is-walked-once.t`, with the 817 probes in `x/` and the 8 in `x/unverified/` | pass |

## 4. New probes

825 programs: 817 in `probes/x/`, 8 in `probes/x/unverified/`. Minimized programs are in `probes/x/min/`. Each was run under perl and through B::SoN, chalk T2 and `lli` by `AuditProbe::run_all`. Verdicts are in `probes/x/_run1.log`. All 72 WRONG were run a second time and reproduced.

| group | n | SAME | REFUSED | LOUD | WRONG |
|---|---|---|---|---|---|
| xa | 56 | 41 | 15 | 0 | 0 |
| xb | 58 | 37 | 21 | 0 | 0 |
| xc | 20 | 17 | 3 | 0 | 0 |
| xd | 50 | 38 | 11 | 0 | 1 |
| xe | 15 | 1 | 13 | 0 | 1 |
| xf | 72 | 47 | 23 | 0 | 2 |
| xg | 57 | 46 | 7 | 3 | 1 |
| xh | 52 | 43 | 8 | 0 | 1 |
| xi | 20 | 11 | 9 | 0 | 0 |
| xj | 40 | 26 | 14 | 0 | 0 |
| xk | 32 | 15 | 16 | 0 | 1 |
| xl | 40 | 35 | 5 | 0 | 0 |
| xm | 23 | 11 | 7 | 0 | 5 |
| xn | 16 | 0 | 11 | 0 | 5 |
| xo | 23 | 1 | 9 | 0 | 13 |
| xp | 28 | 6 | 10 | 0 | 12 |
| xq | 8 | 5 | 3 | 0 | 0 |
| xr | 48 | 27 | 6 | 0 | 15 |
| xs | 9 | 6 | 3 | 0 | 0 |
| xt | 30 | 17 | 11 | 1 | 1 |
| xu | 112 | 86 | 13 | 0 | 13 |
| xv | 16 | 15 | 0 | 0 | 1 |
| **all** | **825** | **531** | **218** | **4** | **72** |

What each group is aimed at:

- First round. `xa` `@_` aliasing; `xb` foreach, map and grep aliasing; `xc` sort blocks and `$a`/`$b`; `xd` references and closures; `xe` glob aliases; `xf` `local` (elements, nested, loops, die through eval); `xg` list assignment, overlaps, swaps, chains, order of evaluation; `xh` what P1 and P2 prove private, methods, recursion; `xi` string eval and symbolic references; `xj` `$1`, `pos`, `each`; `xk` `?:` as an lvalue, `s///e`, `tr///` on aliases; `xl` loop back edges with memory.
- Second rounds, around each first-round wrong. `xm` references to loop scalars; `xn` glob rebinding; `xo` `local` on slices and lists; `xp` the value of a list assignment; `xq` `undef EXPR`; `xr` promotion against closures and references; `xs` `tr///r`; `xt` a closure call between two reads; `xu` an operand read before a call that stores it, one probe per consumer; `xv` `tr` and `s///` sequences.

What came through clean: `@_` aliasing in 56 shapes (0 wrong); foreach, map and grep aliasing (58, 0 wrong); sort (20, 0 wrong); `local` on named scalars, in loops, nested and through die (the two wrong in `xf` are slices); string eval and symbolic references (20, 0 wrong, 9 refused); `$1`, `pos`, `each` (40, 0 wrong); loops with memory (40, 0 wrong). The audit-3 classes N1-N4, N6-N8, N10 and N11 did not reappear in new shapes.

4 LOUD:

| probe | program | what chalk says |
|---|---|---|
| x/xg09 | `my %h = (a=>1,b=>2); %h = (%h, c=>3); %h = reverse %h; ...` | refused at run time: a hash element read through no HASH reference |
| x/xg17 | `(($x,$y) = ($y,$x))[0]; for ((($x,$y) = (5,6))) { $_++ }` | Modification of a read-only value attempted |
| x/xg18 | `$_++ for (($x,$y) = (5,6));` | Modification of a read-only value attempted |
| x/xt06 | `my @a = ([$x], $c->(), [$x]); print $a[0][0], $a[1][0]` | refused at run time: an array element read through no ARRAY reference |

### 4.1 The seven wrong classes

| class | what | n | side | with `SON_NO_PROMOTE=1` |
|---|---|---|---|---|
| X5 | A promoted argument: the callee reads `$_[N]` after a closure call or a store through a reference changed the caller's `my` scalar. | 16 | producer, `SoN::AliasProof::conflict` | SAME, all 16 |
| X3 | `local` on an array or hash slice is not restored; `local @g[0,1];` does not even clear. | 15 | producer: no `local` on the wire | wrong |
| X7 | An operand perl pushes as an SV, read where it stands and not when its consumer runs: slice indices, `substr` arguments, `scalar($x)`, `do { $x }`, `$x \|\| 0`, `$x // 9`, and `sort`, `grep`, `reverse` and lvalue-sub results in a list. | 14 | producer | wrong |
| X4 | The value of a list assignment to a slice or to elements, in list context, is its count. | 13 | producer: the outer record binds the inner `Assign` as one scalar | wrong |
| X1 | A reference to the iterator of a foreach over a range: every pass is the same scalar. | 6 | producer: one slot for the loop | wrong |
| X2 | `*x = \42`, `*x = \$a[1]`: the name is not rebound; `$x` holds a reference. | 6 | chalk (the wire says `EntryWrite binds`) | wrong |
| X6 | `tr///r` after a `tr` on the same variable returns the count. | 2 | wire: `Transliterate` as an input read two ways | wrong |

### 4.2 X5: promotion calls a captured or referenced `my` scalar private (16)

Minimized (`min/min5a.pl`, `min/min5b.pl`):

```perl
sub f { $_[1]->(); $_[0] } my $x = 1; print f($x, sub { $x = 5 }), "\n";   # perl 5, chalk 1
my $x = 1; my $r = \$x; sub f { $$r = 5; $_[0] } print f($x), "\n";          # perl 5, chalk 1
```

The wire of the first (`min/h1.pl` has the two-parameter form): the argument is `PadAccess $x promoted, mem_in` = the store of 1, a value read before the call. In `f`, `Call indirect` is a memory version and `Subscript [ArgsSource, 0]` names it. The proof walked back from that read, met the indirect call, got the effect `any`, and returned "no conflict".

Cause, read in the code:

- `lib/SoN/AliasProof.pm:220`: `return 0 if $e eq 'any' && $src =~ /\Amy\|/ && !$s->referenced($src);`. `referenced` (`:106`) counts `Ref` nodes only. A closure capture is not a `Ref`, and the caller's read of a captured `$x` is a `PadAccess`, not a `CellRead`.
- `lib/SoN/AliasProof.pm:233`: `kind` matches `my:`; a `my` source is spelled `my|G|$x`. Its kind is `?`, so line 252 (`R:scalar` against a scalar source) returns 0 even when a `Ref` to it exists.
- `lib/SoN/AliasProof.pm:254`: the table ends `return 0`.

`SoN::Verify` V14 (`lib/SoN/Verify.pm:241`) asks the same module and passes each. Mutation cases M21 and M23 use `our $x` and a closure that is itself the callee; neither reaches these lines.

| probe | program | perl | chalk |
|---|---|---|---|
| x/xh05 | `sub f { my ($p,$q) = @_; $q->(); "$p$_[0]" } my $x = 1; print f($x, sub { $x = 5 }), "\n";` | `15` | `55` |
| x/xr01 | `sub f { my $p = $_[0]; $_[1]->(); $p . $_[0] } my $x = 1; print f($x, sub { $x = 5 }), "\n";` | `15` | `11` |
| x/xr02 | `sub g { ${$_[0]} = 5 } sub f { my ($p,$r) = @_; g($r); "$p$_[0]" } my $x = 1; print f($x, \$x), "\n";` | `15` | `11` |
| x/xr03 | `sub f { my ($p,$r) = @_; $$r = 5; "$p$_[0]" } my $x = 1; print f($x, \$x), "\n";` | `15` | `55` |
| x/xr08 | `sub f { my ($p,$q) = @_; $q->(); $p + $_[0] } my $x = 1; print f($x, sub { $x = 5 }), "\n";` | `6` | `10` |
| x/xr10 | `sub f { $_[1]->(); $_[0] } my $x = 1; print f($x, sub { $x = 5 }), "\n";` | `5` | `1` |
| x/xr18 | `my $x = 1; my $r = \$x; sub f { my $o = $_[0]; $$r = 5; "$o$_[0]" } print f($x), "\n";` | `15` | `11` |
| x/xr20 | `my $x = 1; my @r = (\$x); sub f { my $o = $_[0]; ${$_[1][0]} = 5; "$o$_[0]" } print f($x, \@r), "\n";` | `15` | `11` |
| x/xr21 | `my $x = 1; my %o = (r => \$x); sub f { my $o = $_[0]; ${$_[1]{r}} = 5; "$o$_[0]" } print f($x, \%o), "\n";` | `15` | `11` |
| x/xr27 | `sub f { my ($s, $o, $c) = ($_[0], $_[1], $_[2]); $c->(); "$o$_[1]" } my $x = 1; print f(0, $x, sub { $x++ }), "\n";` | `12` | `22` |
| x/xr30 | `sub f { my $o = $_[0]; $_[1]->(); "$o$_[0]" } sub w { my $x = 1; f($x, sub { $x = 5 }) } print w(), "\n";` | `15` | `11` |
| x/xr35 | `sub f { my ($p, $c) = @_; eval { $c->() }; "$p$_[0]" } my $x = 1; print f($x, sub { $x = 5; die "z\n" }), "\n";` | `15` | `55` |
| x/xr37 | `sub f { my ($p, $c) = @_; my $i = 0; while ($i++ < 2) { $c->() } "$p$_[0]" } my $x = 1; print f($x, sub { $x++ }), "\n";` | `13` | `33` |
| x/xr38 | `sub f { my ($p, $c) = @_; "$p" . $c->() . "$_[0]" } my $x = 1; print f($x, sub { $x = 5; "-" }), "\n";` | `1-5` | `5-5` |
| x/xr43 | `sub f { my $t = "$_[0]"; $_[1]->(); "$t$_[0]" } my $x = 1; print f($x, sub { $x = 5 }), "\n";` | `15` | `11` |
| x/xr45 | `sub f { my ($p, $c) = @_; $c->($p); "$p$_[0]" } my $x = 1; print f($x, sub { $x = $_[0] + 4 }), "\n";` | `15` | `11` |

### 4.3 X3: `local` on a slice is dropped (15)

Minimized (`min/s1.pl`, `min/min3.pl`):

```perl
our @g = (1,2,3); { local @g[0,1] = (8,9); } print "@g\n";    # perl "1 2 3", chalk "8 9 3"
our %g = (a=>1); { local @g{"a"} = (8); } print "$g{a}\n";      # perl 1, chalk 8
```

The wire of the first holds `Assign [Slice [0, 1, @g], 8, 9] targets 1` and nothing else: no `local` field, no save, no `ElemRestore`. It is the wire of the same program without `local`. `local @g[0,1];` with no assignment makes no node at all (`xo01` prints `d`). Package and `my` aggregates, array and hash, through a reference, in a sub, in a loop and through a die are all the same. `local $g[0]` and `local ($g[0], $g[1])` are refused by name; the slice ops have no such test. `local @g[0..1]` escapes only because chalk refuses a range as a slice index for another reason; `local @g[@i]` and `local @g{@k}` are wrong (`xo15`, `xo16`).

| probe | program | perl | chalk |
|---|---|---|---|
| x/xf40 | `our @g = (1,2,3); { local @g[0,1] = (8,9); print "@g" } print "@g\n";` | `8 9 31 2 3` | `8 9 38 9 3` |
| x/xf41 | `our %g = (a=>1,b=>2); { local @g{qw(a c)} = (8,9); print join(",", map {"$_$g{$_}"} sort keys %g) } print join(",", map {"$_$g{$_}"} sort keys %g), "\n";` | `a8,b2,c9a1,b2` | `a8,b2,c9a8,b2,c9` |
| x/xo01 | `our @g = (1,2,3); { local @g[0,1]; print defined $g[0] ? "d" : "u" } print "@g\n";` | `u1 2 3` | `d1 2 3` |
| x/xo04 | `our @g = (1,2,3); sub f { local @g[1,2] = (0,0); "@g" } print f(), "@g\n";` | `1 0 01 2 3` | `1 0 01 0 0` |
| x/xo05 | `our %g = (a=>1,b=>2); { local @g{qw(a b)} = (8,9); print "$g{a}$g{b}" } print "$g{a}$g{b}\n";` | `8912` | `8989` |
| x/xo06 | `our %g = (a=>1,b=>2); { local @g{qw(a b)}; print defined $g{a} ? "d" : "u" } print "$g{a}$g{b}\n";` | `u12` | `d12` |
| x/xo08 | `my @a = (1,2,3); { local @a[0,1] = (8,9); print "@a" } print "@a\n";` | `8 9 31 2 3` | `8 9 38 9 3` |
| x/xo09 | `my %h = (a=>1,b=>2); { local @h{qw(a b)} = (8,9); print "$h{a}$h{b}" } print "$h{a}$h{b}\n";` | `8912` | `8989` |
| x/xo10 | `my $r = [1,2,3]; { local @$r[0,1] = (8,9); print "@$r" } print "@$r\n";` | `8 9 31 2 3` | `8 9 38 9 3` |
| x/xo11 | `my $r = {a=>1}; { local @$r{qw(a b)} = (8,9); print join(",", sort keys %$r) } print join(",", map {"$_$r->{$_}"} sort keys %$r), "\n";` | `a,ba1` | `a,ba8,b9` |
| x/xo12 | `our @g = (1,2,3); for my $i (0,1) { local @g[$i,$i+1] = (7,7); print "@g;" } print "@g\n";` | `7 7 3;1 7 7;1 2 3` | `7 7 3;7 7 7;7 7 7` |
| x/xo13 | `our @g = (1,2,3); eval { local @g[0,1] = (8,9); die "x\n" }; print "@g\n";` | `1 2 3` | `8 9 3` |
| x/xo15 | `our @g = (1,2,3); my @i = (0,2); { local @g[@i] = (8,9); } print "@g\n";` | `1 2 3` | `8 2 9` |
| x/xo16 | `our %g = (a=>1,b=>2); my @k = qw(a b); { local @g{@k} = (8,9); } print "$g{a}$g{b}\n";` | `12` | `89` |
| x/xo17 | `our %g = (a=>1,b=>2); sub rk { "$g{a}$g{b}" } sub f { local @g{qw(a b)} = (8,9); rk() } print f(), rk(), "\n";` | `8912` | `8989` |

### 4.4 X7: an operand read before its consumer runs (14)

Minimized (`min/min7.pl`, `min/u2.pl`):

```perl
our $x = 1; sub c { $x = 3; 2 } print scalar($x) . c(), "\n";                 # perl 32, chalk 12
our $x = 1; sub c { $x = 5; 1 } my @a = (10,20,30,40,50,60);
my @l = @a[$x, c()]; print "@l\n";                                            # perl "60 20", chalk "20 20"
```

The wire of the second: `Slice [EntryDef $x mem_in=5, Call#6, @a] mem_in=6`. `$x` names the version before the call. Perl pushes `$x` itself and the slice reads it after `c()` ran. The plan (section 2) says an SV operand is "read at the version current when its consumer runs". That is built for `+`, `.`, list items, `print`, `join`, `push`, `[...]`, `{...}`, comparisons and plain call arguments (99 of the 112 `xu` probes are SAME or refused). It is not built where the SV passes through an op that returns its argument, or where the consumer is a slice or `substr`:

| probe | program | perl | chalk |
|---|---|---|---|
| x/xt22 | `my $x = 1; my $c = sub { $x = 5; 1 }; my @a = (10,20,30,40,50,60); my @l = @a[$x, $c->(), $x]; print "@l\n";` | `60 20 60` | `20 20 60` |
| x/xu01 | `our $x = 1; sub c { $x = 5; 1 } my @a = (10,20,30,40,50,60); my @l = @a[$x, c()]; print "@l\n";` | `60 20` | `20 20` |
| x/xu02 | `our $x = "b"; sub c { $x = "a"; "c" } my %h = (a=>1,b=>2,c=>3); my @l = @h{$x, c()}; print "@l\n";` | `1 3` | `2 3` |
| x/xu15 | `our $x = 1; sub c { $x = 3; 2 } my $s = substr("abcdef", $x, c()); print "$s\n";` | `de` | `bc` |
| x/xu67 | `our $x = 1; sub c { $x = 3; 2 } my $s = do { $x } + c(); print "$s\n";` | `5` | `3` |
| x/xu69 | `our $x = 1; sub c { $x = 3; 2 } my $s = scalar($x) . c(); print "$s\n";` | `32` | `12` |
| x/xu70 | `our $x = 1; sub c { $x = 3; 2 } my $s = ($x \|\| 0) . c(); print "$s\n";` | `32` | `12` |
| x/xu92 | `our $x = 1; sub c { $x = 3; 2 } my @l = ((sort { $a <=> $b } $x, 0), c()); print "@l\n";` | `0 3 2` | `0 1 2` |
| x/xu94 | `our $x = 1; sub c { $x = 3; 2 } my @l = ((grep { 1 } $x), c()); print "@l\n";` | `3 2` | `1 2` |
| x/xu95 | `our $x = 1; sub c { $x = 3; 2 } my @l = ((reverse $x), c()); print "@l\n";` | `3 2` | `1 2` |
| x/xu96 | `our $x = 1; sub c { $x = 3; 2 } my @l = (do { $x }, c()); print "@l\n";` | `3 2` | `1 2` |
| x/xu98 | `our $x = 1; sub c { $x = 3; 2 } my @l = (($x \|\| 9), c()); print "@l\n";` | `3 2` | `1 2` |
| x/xu99 | `our $x = 1; sub c { $x = 3; 2 } my @l = (($x // 9), c()); print "@l\n";` | `3 2` | `1 2` |
| x/xu109 | `our $x = 1; sub c { $x = 3; 2 } sub lv :lvalue { $x } my @l = (lv(), c()); print "@l\n";` | `3 2` | `1 2` |

### 4.5 X4: the value of a list assignment in list context (13)

Minimized (`min/min4.pl`):

```perl
my @a = (1,2); my ($x,$y) = @a[0,1] = (8,9); print "$x$y\n";    # perl 89, chalk 2
```

The wire (`min/v1.pl`): the inner store is `Assign#10 [Slice, 8, 9] stamp List`. The outer is `Assign record [x, y, Assign#10]`; the print reads `Coerce(Assign#10)` for `$x` and the undef constant for `$y`. B::SoN bound the list assignment's value as one item. chalk reads an `Assign` as a scalar as its count. In other positions chalk refuses the same node by name ("a value stamped List (Assign)", 8 probes); the record path is not covered. `xp08` shows it is not only slices: `my ($x,$y) = ($a[0],$a[1]) = (8,9)`.

| probe | program | perl | chalk |
|---|---|---|---|
| x/xg55 | `my @a = (1,2,3); my ($x,$y) = @a[1,2] = (8,9); print "$x$y@a\n";` | `891 8 9` | `21 8 9` |
| x/xp02 | `my @a = (1,2,3); my ($x) = @a[1,2] = (8,9); print "$x\|@a\n";` | `8\|1 8 9` | `2\|1 8 9` |
| x/xp04 | `my @a = (1,2,3); my $n = () = (@a[1,2] = (8,9,7)); print "$n\n";` | `2` | `1` |
| x/xp06 | `my %h; my ($x,$y) = @h{qw(a b)} = (8,9); print "$x$y\n";` | `89` | `2` |
| x/xp08 | `my @a = (1,2,3); my ($x,$y) = ($a[0],$a[1]) = (8,9); print "$x$y@a\n";` | `898 9 3` | `28 9 3` |
| x/xp18 | `my @a = (1,2,3); my @b; my ($x,$y) = @b[0,1] = @a; print "$x$y@b\n";` | `121 2` | `31 2` |
| x/xp19 | `my @a = (1,2,3); my @b; my ($x,$y) = @b[1,0] = @a[1,2]; print "$x$y\|", join(",", map { $_ // "u" } @b), "\n";` | `23\|3,2` | `2\|3,2` |
| x/xp20 | `my @a = (1,2,3); my ($x,$y) = (@a[1,2]) = (8); print defined $y ? "d" : "u", "$x@a[0,1]\n";` | `u81 8` | `u11 8` |
| x/xp21 | `my ($p,$q,@a); my ($x,$y) = ($p,$q) = (5,6); my ($u,$v) = @a[0,1] = ($p,$q); print "$x$y$u$v\n";` | `5656` | `562` |
| x/xp22 | `my $r = [1,2,3]; my ($x,$y) = @$r[1,2] = (8,9); print "$x$y@$r\n";` | `891 8 9` | `21 8 9` |
| x/xp23 | `my $r = {}; my ($x,$y) = @$r{qw(a b)} = (8,9); print "$x$y\n";` | `89` | `2` |
| x/xp24 | `our @g = (1,2,3); my ($x,$y) = @g[1,2] = (8,9); print "$x$y@g\n";` | `891 8 9` | `21 8 9` |
| x/xp25 | `my @a = (1,2,3); my ($x,$y) = @a[1,2]; ($x,$y) = @a[0,1] = ($y,$x); print "$x$y@a\n";` | `323 2 3` | `23 2 3` |

### 4.6 X1: a reference to a range-foreach iterator (6)

Minimized (`min/min1.pl`):

```perl
my @r; for my $i (1..2) { push @r, \$i } print ${$r[0]}, "\n";    # perl 1, chalk 2
```

The wire (`min/i1.pl`): the loop is a counted one, `Assign [PadAccess $i, Phi]` each pass, and `Ref [PadAccess $i]`. `$i` is one memory slot; every reference is to it. Perl makes a fresh scalar per pass. The refusal "a reference to a foreach iterator is not yet lowered" (`FromOptree.pm:18251`) fires for `for my $i (1,2,3)` and `for my $i (@a)` (`xm01`, `xm08`, `xm09`, `xm12`) and not for a range. A `my` declared in the body is right (`xm13`-`xm19` SAME).

| probe | program | perl | chalk |
|---|---|---|---|
| x/xd32 | `my @r; for my $i (1..3) { push @r, \$i } print join(",", map { $$_ } @r), "\n";` | `1,2,3` | `3,3,3` |
| x/xm04 | `my $r; for my $i (1..3) { $r //= \$i } print $$r, "\n";` | `1` | `3` |
| x/xm06 | `my @r; for my $i (1..3) { my $q = \$i; push @r, $q } print join(",", map { $$_ } @r), "\n";` | `1,2,3` | `3,3,3` |
| x/xm07 | `my @r; for my $i (1..3) { push @r, \$i; ${$r[0]} += 10 } print join(",", map { $$_ } @r), "\n";` | `31,2,3` | `13,13,13` |
| x/xm10 | `my @r; for my $i (1..2) { for my $j (1..2) { push @r, \$j } } print join(",", map { $$_ } @r), "\n";` | `1,2,1,2` | `2,2,2,2` |
| x/xm11 | `my @r; for my $i (1..3) { push @r, [\$i, $i * 2] } print join(",", map { ${$_->[0]} + $_->[1] } @r), "\n";` | `3,6,9` | `5,7,9` |

### 4.7 X2 and X6

X2, minimized (`min/g1.pl`): `our $x = 1; *x = \42; print "$x\n";` prints `SCALAR(0x...)` for perl's `42`. The wire says `EntryWrite binds [EntryDef $x, Constant ref 42]`, then reads `$x` stamped Int. chalk stores the reference as the value. With `*x = \$a[1]` a later `$x++` goes to the static `$x`, not the element (`xn09`). `*x = \$y` and `*x = *y` are refused, by rules that are not about rebinding ("a reference to what is not an array", "a statement EntryWrite").

| probe | program | perl | chalk |
|---|---|---|---|
| x/xe15 | `our $x = 1; sub chg { *x = \99 } my $o = $x; chg(); print "$o$x\n";` | `199` | `1SCALAR(0x...)` |
| x/xn02 | `our $x = 1; sub chg { *x = \99 } chg(); print "$x\n";` | `99` | `SCALAR(0x...)` |
| x/xn03 | `our $x = 1; sub chg { *x = \99 } my $o = $x; chg(); my $n = $x; print "$o$n\n";` | `199` | `1SCALAR(0x...)` |
| x/xn09 | `our $x = 1; my @a = (4,5); *x = \$a[1]; $x++; print "@a\n";` | `4 6` | `4 5` |
| x/xn10 | `our $x = 1; sub rd { $x } *x = \42; print rd(), "\n";` | `42` | `SCALAR(0x...)` |
| x/xn11 | `our $x = 1; sub rd { $x } sub chg { *x = \42 } my @l = (rd(), chg() && rd()); print "@l\n";` | `1 42` | `1 SCALAR(0x...)` |

X6, minimized (`min/t1.pl`): `my $s = "bb"; my $t = $s =~ tr/b//; my $r = $s =~ tr/b/c/r; print "$t$r\n";` prints `22` for perl's `2cc`. The wire: `Transliterate#10 flags r, inputs [Transliterate#7]`. B::SoN names the earlier `tr` as "the string after it". chalk reads a `Transliterate` used as a value as its count (`lib/Chalk/Target/LLVM/Builder/Regex.pm:291`). `tr///r` alone, and after `s///`, is right.

| probe | program | perl | chalk |
|---|---|---|---|
| x/xk27 | `my $s = "aaa"; my $c = ($s =~ s/a/b/g); my $t = $s =~ tr/b//; my $r = $s =~ tr/b/c/r; print "$c$t$r$s\n";` | `33cccbbb` | `333bbb` |
| x/xv01 | `my $s = "bb"; my $t = $s =~ tr/b//; my $r = $s =~ tr/b/c/r; print "$t$r\n";` | `2cc` | `22` |

### 4.8 Audit 3's probes that are still out of the gate

`t/data/audit-probes/BASELINE.tsv` (chalk) lists 86 WRONG probes in classes N1-N5, N7, N10-N12, `ya57`, and 24 whose wires broke a verifier rule, and says they come in "when the decision is made and they are SAME or refused". None is in `t/data/audit-probes`. Run here from `probes/y/` (`probes/x/_y_left_out.log`): SAME 79, REFUSED 26, WRONG 5.

| probe | program | perl | chalk | |
|---|---|---|---|---|
| y/yc147 | `my %h=(a=>1); my @b=(values %h, $h{a}=9); print "@b\n";` | `9 9` | `1 9` | N5, still wrong, also with `SON_NO_PROMOTE=1` |
| y/yp100 | `my %h=(a=>1,b=>2); my @b=(@h{qw(a b)}, $h{a}=9); print "@b\n";` | `9 2 9` | `1 2 9` | N5, still wrong |
| y/yp114 | `my %h=(a=>1); my $s = join(",", values %h, $h{a}=9); print "$s\n";` | `9,9` | `1,9` | N5, still wrong |
| y/yp13 | `for my $v (values %h) { $s += $v; z() }` | `8` or `9` | `8` | perl's answer depends on hash order (noted in `docs/memory/places-everywhere.md`); not counted |
| y/ya57 | `shift @a` under `@_` | | | perl reads a freed scalar; not counted |

These three are N5 with a hash: `values %h` or a hash slice as list items, then an element store. The same refusal that now covers the array forms ("a list item perl aliases element by element ...", 5 of the 26 refusals) does not reach them.

## 5. Recommendations, ranked

1. **Fix `SoN::AliasProof::conflict` and make it fail closed.** Spell `my|` at line 233. At line 220 count a capture (`MakeCell`, `AnonSub.captures`, a named sub's use of a file lexical) as a reference. End the table with `return 1`. Add mutation cases for a closure passed as an argument, a file-level `\$x` stored through by the callee, and a reference held in an array or hash. 16 wrong.
2. **Gate the promotion differential.** For every probe whose wire holds a `promoted` node, run it with `SON_NO_PROMOTE=1` too and fail on any difference. This is the independent check V14 is not. It costs 69 extra runs on this set.
3. **Refuse `local` on a slice by name, or lower it as `local` on each element.** More generally, an op with `OPpLVAL_INTRO` that no handler consumed should be a GAP: this is the project's own lesson ("a silent drop is worse than a refusal") at one more site. 15 wrong.
4. **Bring the 110 left-out audit-3 probes into the gate.** 105 are SAME or REFUSED today. Fix or refuse the three N5 hash forms; record `yp13` and `ya57` as not deterministic. Until then clause 1 is met only by leaving probes out.
5. **Operand reads (X7): decide by what the op returns, not by the consumer.** Ops that return their argument SV (`scalar`, a `do` block, `||`, `//`, `&&`, `?:`, `sort`, `grep`, `reverse`, an lvalue sub) keep the alias; slice index lists and `substr` arguments are read by their consumer. Where a store to the source lies between the push and the consumer and the form is not handled, refuse by name. 14 wrong, plus the three in item 4.
6. **The value of a list assignment (X4).** Refuse a list-stamped `Assign` as a record's source, as chalk already does elsewhere, or bind its targets. 13 wrong.
7. **Range foreach with `\$i` (X1).** Extend the refusal at `FromOptree.pm:18251` to counted loops, or make a cell per pass when a reference or closure takes the iterator. 6 wrong.
8. **Glob assignment of a scalar reference (X2).** Refuse `EntryWrite binds` of a scalar name in chalk unless it is lowered through `bind::NAME` as `local` is. 6 wrong.
9. **`Transliterate` as an input (X6).** Say on the wire which reading is meant, or have B::SoN read the variable at the `tr`'s version. 2 wrong.
10. **`undef $$r`**: turn the masked INTERNAL ERROR into a GAP with a name.
11. **Longer term: sources as memory slices on the wire** (section 2). It would let the verifier check privacy as a path property with no shared predicate.

## 6. What was not checked

- Neither full suite, the census, nor the corpus gate was run. `SON_RATCHET=1` (chalk's lib through the verifier) was not run.
- X2 and X6 were attributed by reading the wire and one chalk line each; chalk's lowering was not traced.
- The skill `i-have-adhd` named in `CLAUDE.local.md` is not installed in this session and was not loaded.
