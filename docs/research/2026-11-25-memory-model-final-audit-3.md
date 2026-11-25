# Third final audit of the goal "Make the SoN memory model mechanical and checked, measured" (2026-11-25)

Producer `/home/user/repo`, `wip/chalk-lib-roundtrip`, 76f33aa. Chalk `/home/perigrin/dev/chalk`, `bson/llvm-corpus`, eca706af. No code was changed. The commit is this file, the probes in `docs/research/son-ir-audit-2026-11-19/probes/y/`, one README line and one memory note. It follows the two final audits (`2026-11-24-memory-model-final-audit.md`, `2026-11-25-memory-model-final-audit-2.md`) and baseline section 27.

## Verdict

**The gates hold and audit 2's 57 wrong answers are gone. The goal's first sentence still does not hold, and the rate of new wrong answers went up, not down.**

- The 3179 gated probes, re-run here: SAME 2435, REFUSED 724, LOUD 20, WRONG 0; no verdict differs from `BASELINE.tsv`.
- The verifier, run here with chalk's lib (`SON_RATCHET=1`): corpus 431 wires, probes 3184 wires, chalk lib 221 wires; 0 violations, 0 dropped. The ratchet passes.
- 1373 new one-line probes found **146 silent wrong answers** in twelve classes (10.6%; audit 2: 57 of 828, 7%). One more (`ya57`) differs from perl only where perl reads a freed scalar; it is not counted.
- 101 of the 146 sit one step outside a class audit 2 closed (K1, K3, K4, K5, K6, K7, K9). The fix or the refusal covers the probes it was written for; the next shape over is still wrong.
- 30 new probes break a verifier rule (61 violations). Nine of those are wrong answers: for the first time the verifier sees some wrong wires (9 of 146). It also flags twelve programs chalk gets right.
- Three short examples:
  - `my @a=(1,2); sub z { $a[1]=7 } print map { my $v=$_; z(); $v } @a;` prints `12` for perl's `17`.
  - `my @a=(1); sub f { $a[0]=7; 0 } my $n = ($a[0] = 5) + f(); print $n` prints `5` for perl's `7`.
  - `use YPriv; print YPriv::priv()` prints an empty value for perl's `5` (the module says `my $priv = 5; sub priv { $priv }`).

## 1. Verdict per clause

| clause | verdict | what holds | what does not |
|---|---|---|---|
| (1) No silent wrong answers from the audit | **MET to the letter; the neighbourhood is worse than at audit 2** | All 3179 gated probes re-run here: SAME 2435, REFUSED 724, LOUD 20, WRONG 0; no verdict differs from `BASELINE.tsv`. They hold the 59 W1-W10 cases, the hash-truth cases, the dropped list-assign stores and every later audit's probes, audit 2's 826 `z` probes among them. The five K2 probes (`zpa02`, `zqb01`, `zqb02`, `zqb05`, `zqb09`) are refused by name, as agreed. `st3` is refused in perl's words. | 146 new wrong answers (section 4). Two new refusals have no name (`yo26`, `yo35`: "no program graph"; B::SoN's stderr says "B::SoN compiles Perl, not XS" and the harness drops it). `zcp83` is still an internal check, not a name. 16 new LOUD. |
| (2) Producer placement is mechanical | **MET for what reaches the constructor; PARTLY MET overall** | `_place` `lib/SoN/FromOptree.pm:891`, `_pin` `:900`, `_unplace` `:939`; `_seat` `:956` is the one write of `control_in` (callers `:912`, `:942`, `:3589`, `:5193`, `:5311`); `t/placement-one-constructor.t` passes. List-assign targets by where they live: `_target_storage` `:24113`, called at `:12887`. Package scalars in loops: `_key_lives_in_memory` `:15141`, `_entry_live_value` `:15120`. Dynamic method: `dispatch_kind => 'dynamic_method'` `:6098`. Effect table: `B::SoN::EffectTable::on_chain` (`lib/B/SoN/EffectTable.pm:192`), asked at `FromOptree.pm:13985`, `:20423`, `:20561`; its test passes. May-fault division: `_may_fault` `:962`, pinned at `:983`. `effect-floating` is 0 on corpus, the 3184 older probes and chalk's lib. | A store with no rule still never reaches the constructor, with no GAP: `($x = $y) = 7` is two records and nothing on a chain (`y/yc31`); `for ($x .= "b") { $_ .= "!" }` stores into a literal (`y/yc29`); class N6, 13 probes. `local $g;` with no value is a store of `$g`'s own value (`y/yj37`). A foreach over an outer `my $i` is pinned to `$i`'s own slot, where perl gives the loop a new scalar (N10). `effect-floating` is not 0 on real modules: 12 violations in `Math::BigInt`, `Benchmark`, `Text::Balanced` (`y/unverified/yo27`, `yo30`, `yo33`). `corpus/398` still has a sub `Call` on no control chain. |
| (3) Wire v2 | **MET on the gated wires, with caveats** | My scan of 5209 wires (corpus 431, probes 4557, chalk lib 221; 33853 graphs): every `Return` (40833), `Unwind` (1874), `EntryWrite` (5570), non-builtin `Call` (36416), `Delete` (283), `CellWrite` (118) and non-record `Assign` (16615) has `mem_in`; 777 record `Assign`s; no `MemStart` or memory Phi is in any `inputs` but a memory Phi's; 1511 `Exc`; 7018 `Loop`s, all with one or two inputs; every wire says version 2. No double walk: `LOOP_HINTS` is one comment (`FromOptree.pm:15620`); `t/loop-body-is-walked-once.t` passes with the new probes in place. chalk `lib/`: `Phi::is_memory`, `Assign::is_placed`, `WireUpgrade` appear in one comment (`lib/Chalk/IR/Node/Phi.pm:42`); the loader refuses any wire but v2 (`lib/Chalk/IR/Serialize/JSON.pm:1327`). `as_v1` takes the producer's `mem_operand` mark (`lib/SoN/Wire.pm:57`). | Not every memory read names a version. A callee's `my ($p) = @_` is still a record over `ArgsSource` unless `ModSets::args_may_be_places` (`lib/SoN/FromOptree/ModSets.pm:371`) says a caller may hand places; it misses `tr///` through `$_[0]`, a store through `\$_[0]` or `\@_`, and a copy made in a loop (N1). A foreach, map or grep list is flattened once, on no version (`ArrayLiteral [13] List` in `y/yp06`); its per-pass `Subscript` names the header's memory but indexes the flattened copy (N3). The exceptional edge has a hole on a plain program: `eval { die } \|\| do { chomp(my $e = $@) ... }` gives `write-unreachable`, `control-fork` and `control-sink` (`y/unverified/yn26`). |
| (4) Checked | **MET on the three named sets; not on new probes** | `SoN::Verify`: `write-unreachable` `lib/SoN/Verify.pm:453`, `read-unversioned` `:630`, `effect-floating` `:436`, `alias-not-private` `:155` (calls) and `:223` (list items), `exc` `:700`-`:807`. Run here: `t/wire-verify-ratchet.t` with `SON_RATCHET=1` on a snapshot of 76f33aa against chalk eca706af passes (5 tests): corpus, probes, chalk's lib, 0 violations, 0 dropped wires. `t/wire-verify-rejects-hand-broken-wires.t` passes. The loader holds every wire to `WireInvariant` L1-L10 and `WireCheck` (`JSON.pm:1335`-`1337`); it refused `yn26`, `yo27` and `yo30` by L4. | 30 of the 1373 new probes break a rule (section 5). The loader still lets off a wire that says `writer: chalk` (`JSON.pm:1335`). The chalk-lib half of the ratchet is still opt-in. The verifier sees 9 of the 146 wrong wires and flags 12 right programs. |

Clause 5 (verified and pushed) was not asked for. I did not run either full suite, the census, or the corpus gate.

## 2. Audit 2's caveats

| caveat (audit 2) | now |
|---|---|
| 57 wrong answers in nine classes | **Closed.** The 826 `z` probes are gated: WRONG 0. |
| K1: a callee's copy of `@_` has no version | **Partly closed.** The 13 are SAME. The rule that decides when to give the copy a version has holes: N1, 13 new. |
| K2: `local` under an alias | **Refused by name** (5 probes), pending the design decision. New neighbours outside the refusal: `print $g, local $g = 5` and `inc(local $g)` (N8, 4 probes). |
| K3: an iterator read after a call that stores its array | **Partly closed.** V12's list half exists. It looks inside one pass. A store in one pass that reaches a later pass's item is not seen: N3, 8 new. |
| K4: an lvalue with no rule is dropped | **Partly closed.** N6, 13 new. The default is still not a GAP. |
| K5: an element assignment's value read as a value | **Partly closed.** Refused where a later operand stores the same container by name. Not where a call, a nested element or a reference stores it: N4, 18 new. |
| K6: the old value of `$g++` read late in chalk | **Closed** for direct calls. The same program with a method call is wrong at the producer (`Call [obj, 8, 8]`, `y/ye20`), and `tr///` is not counted as a store: N7, 11 new. |
| K7: an array flattened into a list, then stored | **Partly closed.** Refused for a whole array. Not for a slice, `values`, `reverse`, `grep`, or `?:` of two arrays: N5, 16 new. |
| K8: list assignment to a foreach iterator | **Closed.** |
| K9: a followed module's start state | **Partly closed.** Plain package data is right (51 of 80 `yd` probes SAME). Not: file lexicals, shared references, file-level prints, stores into other packages, `import`, INIT, a BEGIN block that calls the module: N9, 22 new. |
| `st3` has no name | **Closed.** |
| One `Call` in the corpus on no chain (`398`) | **Open.** Still there. |
| A pre-scan miss not refused | **Closed** as stated; `t/pre-scan-agrees-with-the-walk.t` passes on the gated probes; nine new probes disagree, eight on the safe side (section 3). |
| `z/un19`: `$@` as an `EntryDef` with no version | **Closed.** Every `$@` read there names a version now. |
| `as_v1` guesses by kind | **Closed.** |
| Two probes broke verifier rules (`pa79`, `un75`) | **Closed.** 30 new ones do. |
| `writer: chalk` exempts a wire | **Open.** |
| The ratchet reads chalk's lib only with `SON_RATCHET=1` | **Open** (by design). Run here: passes. |
| V12 has only its call half | **Closed** in form; see K3. |
| The verifier sees none of the wrong wires | **Partly closed.** 9 of 146. |
| `z/cp83` refused by an internal check | **Open.** |
| `z/pk11` LOUD names something untrue | **Open.** |
| The unscanned-package rule has no end-to-end probe | **Open.** |
| Edges only under an eval or a live `local` | **Open, and sound so far** but for `yn26`'s wire. |

## 3. Verifier counts

Run on a snapshot of the producer at 76f33aa, chalk at eca706af, one wire cache.

| source | wires | graphs | dropped | violations |
|---|---|---|---|---|
| corpus | 431 | 1082 | 0 | 0 |
| probes (all older) | 3184 | 4372 | 0 | 0 |
| chalk `lib/` | 221 | 24838 | 0 | 0 |
| probes with `y/` added | 4557 | 7933 | 0 | 61, in 30 probes, all new |

`SON_RATCHET=1 prove -l t/wire-verify-ratchet.t`: PASS, 5 tests, 1148 s. With the 30 moved to `y/unverified/`: the ratchet (without chalk's lib), `t/loop-body-is-walked-once.t`, `t/placement-one-constructor.t`, `t/wire-verify-rejects-hand-broken-wires.t` and `t/effect-table-has-a-row-for-every-builtin.t` pass. `t/pre-scan-agrees-with-the-walk.t` failed on nine more new probes (`yb52`, `yf51`, `yf111`, `yi30`, `yi34`, `yj54`, `yj56`, `yo28`, `yo36`): eight where the scan names a slot the walk does not (the safe side), one where the walk writes the iterator and the scan says no (`yi34`, refused by name). With those nine in `y/unverified/` too, it passes.

The 61 violations by rule: `alias-not-private` 15, `effect-floating` 12, `read-unversioned:through-ref` 8, `write-unreachable` 6, `read-unversioned:args` 5, `control-sink` 4, `read-unversioned:my-aggregate` 4, `control-fork` 3, `read-unversioned:package` 3, `read-unversioned:package-aggregate-literal` 1.

## 4. New probes

1373 programs, written for this audit: 1334 in `probes/y/`, 39 in `probes/y/unverified/` (30 for a verifier rule, 9 for the pre-scan test). Fourteen modules for the `yd` probes are in `probes/y/ylib/`. Each was run under perl and through B::SoN, chalk T2 and `lli` by `AuditProbe::run_all`, from the probes' own directory. Verdicts are in `probes/y/_run1.log`.

| group | n | SAME | REFUSED | LOUD | WRONG |
|---|---|---|---|---|---|
| ya | 81 | 63 | 13 | 0 | 5 |
| yb | 56 | 37 | 18 | 0 | 1 |
| yc | 182 | 96 | 76 | 1 | 9 |
| yd | 80 | 51 | 8 | 2 | 19 |
| ye | 60 | 50 | 7 | 0 | 3 |
| yf | 123 | 98 | 23 | 1 | 1 |
| yg | 93 | 87 | 4 | 1 | 1 |
| yh | 63 | 27 | 34 | 0 | 2 |
| yi | 61 | 32 | 23 | 3 | 3 |
| yj | 84 | 56 | 24 | 0 | 4 |
| yk | 44 | 19 | 22 | 3 | 0 |
| yl | 45 | 25 | 15 | 2 | 3 |
| ym | 54 | 31 | 22 | 1 | 0 |
| yn | 61 | 33 | 27 | 0 | 1 |
| yo | 40 | 6 | 32 | 0 | 2 |
| yp | 204 | 67 | 58 | 2 | 77 |
| yq | 42 | 11 | 15 | 0 | 16 |
| **all** | **1373** | **789** | **421** | **16** | **147** |


What each group is aimed at:

- `ya` `@_` copies and slurpy binds; `yb` the iterator aliased by reference; `yc` the edges of the K4, K5 and K7 refusals, and order of evaluation; `yd` a followed module's start state; `ye` chalk's `arg_alias` rule; `yf` what a loop body writes (pre-scan and walk).
- `yg` numbers and strings; `yh` context and return values; `yi` argument aliasing; `yj` closures, scope, `state`, `local`, phase blocks; `yk` objects, DESTROY, `class`; `yl` regexes; `ym` lists, sort, hashes, ranges; `yn` eval, die, I/O; `yo` real modules.
- `yp`, `yq`: a second round written around each first-round WRONG.

The rate by round (`ya57` left out): first round, aimed at audit 2's fixes (`ya`-`yf`), 37 of 582 (6.4%). Broad, never covered (`yg`-`yo`), 16 of 545 (2.9%). Second round (`yp`, `yq`), 93 of 246 (38%).

What came through clean: integer and float arithmetic at the 64-bit edges, `sprintf` and string functions (93 probes, 1 wrong); sort, stable sort, slices, ranges, hashes (54, 0 wrong); objects and `class` (44, 0 wrong; every DESTROY is refused by name); eval and die (61, 1 wrong); vivifying reads (37, 0 wrong); closures and `state` (0 wrong).

16 LOUD:

| probe | program | what chalk says |
|---|---|---|
| y/yc43 | `my %h=(a=>"x", b=>"y"); %h = reverse %h; print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";` | chalk: refused at run time: a hash element read through no HASH reference |
| y/yd57 | `use YKid; print YKid->new->hello, "\n";` | Can't locate object method "new" via package "YKid" |
| y/yd63 | `use YConst; print YConst::PI, YConst->PI, scalar(my @l = YConst::LIST), "\n";` | Can't locate object method "PI" via package "YConst" |
| y/yf04 | `my @a=(undef); for my $x (@a) { for my $k (keys %$x) { } } print defined $a[0] ? "d" : "u", "\n";` | chalk: refused at run time: a hash element read through no HASH reference |
| y/yg54 | `my $s="hello"; { no warnings; my $o = substr($s,9); print defined $o ? "d" : "u"; } substr($s,0,1)="J"; substr($s,-1,1,"y"); print "$s\n";` | substr outside of string (perl warns): stopped (chalk, T2) |
| y/yi05 | `sub inc { $_[0]++ } my $x=1; inc(scalar($x)); print "$x\n";` | Modification of a read-only value attempted. |
| y/yi12 | `sub inc { $_[0]++ } my $x=1; inc(do { $x }); print "$x\n";` | Modification of a read-only value attempted. |
| y/yi44 | `sub f { $_[0]{k} = 1; $_[1][2] = 1 } my ($h,$a1); f($h,$a1); print ref($h), ref($a1), scalar(@$a1), "\n";` | chalk: refused at run time: a hash element read through no HASH reference |
| y/yk14 | `package A; sub new { my $c = shift; bless {@_}, $c } sub name { $_[0]{name} } package B; use parent -norequire, "A"; sub new { my ($c,%a)=@_; my $s = A::new($c, %a, kind => "b"); $s } sub kind { $_[0]{kind} } package main; my $o = B->new(name => "n"); print $o->name, $o->kind, ref($o), "\n";` | Can't locate object method "name" via package "B" |
| y/yk24 | `package P; sub new { bless {v=>$_[1]}, $_[0] } sub cmp { $_[0]{v} <=> $_[1]{v} } package main; my @o = map { P->new($_) } 3,1,2; print join(",", map { $_->{v} } sort { $a->cmp($b) } @o), "\n";` | Can't locate object method "cmp" via package "P" |
| y/yk41 | `use feature 'class'; no warnings; class P { field $x :param; method cmp($o) { $x <=> $o->x } method x { $x } } my @s = sort { $a->cmp($b) } map { P->new(x => $_) } 3,1,2; print join(",", map { $_->x } @s), "\n";` | Can't locate object method "cmp" via package "P" |
| y/yl01 | `"ab" =~ /(a)/; "zz" =~ /(q)/; print $1, "\n";` | a capture read where its match failed (perl reads the last match that succeeded): stopped (chalk, T2) |
| y/yl05 | `for my $s (qw(a1 b c3)) { if ($s =~ /(\d)/) { print $1 } else { print defined $1 ? "d" : "u" } } print "\n";` | a capture read where its match failed (perl reads the last match that succeeded): stopped (chalk, T2) |
| y/ym12 | `my @a = (1,2,3); my $r = eval { $a[-5] = 1; 1 }; print $r ? "ok" : "died", $@ =~ /Modification of non-creatable array value attempted, subscript -5/ ? "msg" : "other", "\n";` | Modification of non-creatable array value attempted, subscript -5. |
| y/yp145 | `my ($x,$y)=(1,2); my $r = \($x = $y); $$r = 7; print "$x $y\n";` | Modification of a read-only value attempted |
| y/yp188 | `our $g="aab"; my $n=0; while ($g =~ tr/a/b/) { $n++ } print "$n$g\n";` | PLEASE submit a bug report to https://github.com/llvm/llvm-project/issues/ and include the crash backtrace. St |


Five of these say a method that exists cannot be found: `yd57`, `yd63`, `yk14`, `yk24`, `yk41`. `yp188` is an `lli` crash.

### 4.1 The twelve wrong classes

| class | what | n | next to | side | traced on |
|---|---|---|---|---|---|
| N1 | A callee's copy of `@_` shows a later store: by `tr///` through `$_[0]`, through `\$_[0]` or `\@_`, or the copy is made in a loop while the caller's variable is stored. | 13 | K1 | producer: the copy is still a record with no version (`Assign [1,2] record`). For the loop form the wire is right and chalk reads once. | `ya37`, `yp47`, `yp57` |
| N2 | `@_` itself: `@_ = ()` is not applied; after `unshift @a`, `$_[0]` of `f(@a)` follows the index, not the scalar. | 9 | new | chalk: the wire carries the store and the order | `ya32`, `yp61` |
| N3 | A foreach, map or grep item reads the list as it was at loop entry when an earlier pass stored a later element. | 8 | K3 | both: the list is flattened once on no version; the item names the header's memory | `yp06` |
| N4 | The value of an element assignment, or a plain element read, used as an operand, then stored by a call, a nested element, or through a reference. | 18 | K5 | producer: `Add [5, call]`; `Subscript` at the version before the store | `yc108`, `yc125` |
| N5 | A slice, `values`, `reverse`, `grep`, or `?:` of arrays in a list, then a later item stores an element. | 16 | K7 | producer: `Slice` at the version before the store | `yc142` |
| N6 | An assignment or op= as an lvalue: a foreach, map or grep item (`for ($x .= "b")`), or the target of a list assignment (`($x = $y) = 7`). | 13 | K4 | producer: the store is a record or goes into a literal | `yc29`, `yc31` |
| N7 | A call's argument is the variable, and a later argument stores it: method calls (`$o->m($g, $g++)`), and `tr///` as the store. | 11 | K6 | producer: `Call [obj, 8, 8]`; for `tr`, the read names the version before it and chalk's rule copies | `ye20`, `ye60` |
| N8 | `local`: as a list item after its own variable, with no value (`local $g;`), under `if` or `and`, and `delete local`. | 10 | K2 | producer: `local $g;` stores `$g`'s own value; a conditional `local` has no restore | `yj37`, `yj33`, `yp167` |
| N9 | A followed module's start state beyond plain data, and INIT and CHECK blocks. | 22 | K9 | producer: not on the wire, no GAP | `yd43`, `yq13` |
| N10 | `my $i; for $i (...)`: a closure, a named sub or a reference sees the loop's values; perl's loop has its own scalar. | 5 | new | producer: the body stores `$i`'s slot | `yf81` |
| N11 | `substr(...)` or `$#a` as a sub argument or a foreach item: the write is lost. | 6 | new | producer: the builtin's value is passed | `yi23` |
| N12 | Values: `length(undef)`, `reverse` returned from a sub by context, `(1,2) x 2` in scalar context, the count of an empty `split`, `split //` with a limit, a capture from an earlier pass, a bare `die` after `$@` was set, `use Env`, `use English`. | 15 | new | producer for `reverse` (stamped with no context); the rest not traced | `yh26` |

N9 and most of N12 are not the memory model. N9 is the state the model starts from.

### 4.2 Every WRONG

#### N1 (13)

| probe | program | perl | chalk |
|---|---|---|---|
| y/unverified/ya37 | `my $x="ab"; sub f { my ($p)=@_; $_[0] =~ tr/a/z/; $p } print f($x), "$x\n";` | `abzb` | `zbzb` |
| y/ya41 | `my $x=1; sub f { my ($p)=@_; my $r=\$_[0]; $$r=9; $p } print f($x), "$x\n";` | `19` | `99` |
| y/unverified/ya49 | `my $x=1; sub f { my $s=""; for my $i (1..2) { my ($p)=@_; $s.=$p; $x++ } $s } print f($x), "$x\n";` | `123` | `113` |
| y/unverified/yp40 | `my $x="ab"; sub f { my ($p)=@_; my $c = ($_[0] =~ tr/a/z/); "$p$c" } print f($x), "$x\n";` | `ab1zb` | `zb1zb` |
| y/unverified/yp41 | `my $x="ab"; sub f { my ($p)=@_; $_[0] =~ y/b/z/; $p } print f($x), "$x\n";` | `abaz` | `azaz` |
| y/yp47 | `my $x=1; sub f { my ($p)=@_; ${\ $_[0]} = 9; $p } print f($x), "$x\n";` | `19` | `99` |
| y/yp48 | `my $x=1; sub f { my ($p)=@_; my $r=\@_; $r->[0]=9; $p } print f($x), "$x\n";` | `19` | `99` |
| y/yp55 | `my @a=(1,2); sub f { my ($p)=@_; my $r=\$_[0]; $$r=9; $p } print f(@a), "@a\n";` | `19 2` | `99 2` |
| y/unverified/yp56 | `my $x=1; sub f { my $s=""; my $i=0; while ($i++ < 2) { my ($p)=@_; $s.=$p; $x++ } $s } print f($x), "$x\n";` | `123` | `113` |
| y/unverified/yp57 | `my $x=1; sub f { my $s=""; for my $i (1..2) { my $p=$_[0]; $s.=$p; $x++ } $s } print f($x), "$x\n";` | `123` | `113` |
| y/unverified/yp58 | `my $x=1; sub g { $x++ } sub f { my $s=""; for my $i (1..2) { $s.=$_[0]; g() } $s } print f($x), "$x\n";` | `123` | `113` |
| y/unverified/yp59 | `my $x=1; sub g { $x++ } sub f { my $s=""; for my $i (1..2) { my ($p)=@_; $s.=$p; g() } $s } print f($x), "$x\n";` | `123` | `113` |
| y/unverified/yp191 | `my $x="ab"; sub t { $_[0] =~ tr/a/z/ } sub f { my ($p)=@_; t($_[0]); $p } print f($x), "$x\n";` | `abzb` | `zbzb` |

#### N2 (9)

| probe | program | perl | chalk |
|---|---|---|---|
| y/ya32 | `my $x=1; sub f { $_[0]=9; @_=(); scalar @_ } print f($x), "$x\n";` | `09` | `19` |
| y/yp25 | `my $x=1; sub f { @_=(); "[@_]" } print f($x), "\n";` | `[` | `[1]` |
| y/yp31 | `my $x=1; sub f { @_=(); $_[0]=5; "@_" } print f($x), "$x\n";` | `51` | `55` |
| y/yp61 | `my @a=(1,2); sub f { unshift @a, 0; "@_" } print f(@a), "\n";` | `1 2` | `0 1` |
| y/yp62 | `my @a=(1,2); sub f { unshift @a, 0; $_[0]=9; "@a" } print f(@a), "\n";` | `0 9 2` | `9 1 2` |
| y/yp65 | `my @a=(1,2); sub f { unshift @a, 0; my ($p,$q)=@_; "$p$q" } print f(@a), "\n";` | `12` | `01` |
| y/yp66 | `my @a=(1,2); sub f { unshift @a, 0; $_[1] } print f(@a), "\n";` | `2` | `1` |
| y/yp68 | `my @a=(1,2); sub f { unshift @a, 0; $_[0]=9; "@a" } print f($a[0]), "\n";` | `0 9 2` | `9 1 2` |
| y/yp69 | `my @a=(1,2); sub inc { $_[0]++ } sub f { unshift @a, 0; inc($_[0]); "@a" } print f($a[0]), "\n";` | `0 2 2` | `1 1 2` |

#### N3 (8)

| probe | program | perl | chalk |
|---|---|---|---|
| y/yb46 | `my @a=(1,2); sub z { $a[1]=7 } my @g = map { my $v=$_; z(); $v } @a; print "@g\n";` | `1 7` | `1 2` |
| y/yp04 | `my @a=(1,2); my @b=(3); sub z { $a[1]=7 } for my $x (@a,@b) { print $x; z() } print "\n";` | `173` | `123` |
| y/yp05 | `my @a=(1,2); my @b=(3); sub z { $b[0]=7 } for my $x (@a,@b) { my $v=$x; z(); print $v } print "\n";` | `127` | `123` |
| y/yp06 | `my @a=(1,2); sub z { $a[1]=7 } print map { my $v=$_; z(); $v } @a; print "\n";` | `17` | `12` |
| y/yp07 | `my @a=(1,2); sub z { $a[1]=7 } my @g = grep { my $v=$_; z(); $v > 1 } @a; print "@g\n";` | `7` | `2` |
| y/yp09 | `my @a=(1,2); sub z { $a[1]=7; 0 } my @g = map { $_ + z() } @a; print "@g\n";` | `1 7` | `1 2` |
| y/yp13 | `my %h=(a=>1,b=>2); sub z { $h{b}=7; $h{a}=7 } my $s=0; for my $v (values %h) { $s += $v; z() } print "$s\n";` | `9` | `3` |
| y/yp16 | `my @a=(1,2); my $f = sub { $a[1]=7 }; print map { my $v=$_; $f->(); $v } @a; print "\n";` | `17` | `12` |

#### N4 (18)

| probe | program | perl | chalk |
|---|---|---|---|
| y/yc107 | `my %h; my $n = ($h{a}{b} = 5) + ($h{a}{b} = 7); print "$n\n";` | `14` | `12` |
| y/yc108 | `my @a=(1); sub f { $a[0]=7; 0 } my $n = ($a[0] = 5) + f(); print "$n\n";` | `7` | `5` |
| y/yc122 | `package C; sub new { bless {v=>1}, shift } sub set { $_[0]{v}=$_[1]; 0 } package main; my $o=C->new; my $n = ($o->{v} = 5) + $o->set(7); print "$n\n";` | `7` | `5` |
| y/yc125 | `my @a=(1); my $e=\$a[0]; my $n = $a[0] + ($$e = 7); print "$n\n";` | `14` | `8` |
| y/yc126 | `my @a=(1); my $e=\$a[0]; my @l = ($a[0], $$e = 7); print "@l\n";` | `7 7` | `1 7` |
| y/yp79 | `my %h; my $n = ($h{a}{b} += 5) + ($h{a}{b} += 7); print "$n\n";` | `24` | `17` |
| y/yp80 | `my @a=([1]); my $n = ($a[0][0] = 5) + ($a[0][0] = 7); print "$n\n";` | `14` | `12` |
| y/yp81 | `my $o={l=>[1]}; my $n = ($o->{l}[0] = 5) + ($o->{l}[0] = 7); print "$n\n";` | `14` | `12` |
| y/yp82 | `my @a=(1); sub f { $a[0]=7; 0 } my $n = ($a[0] += 5) + f(); print "$n\n";` | `7` | `6` |
| y/yp83 | `my @a=(1); sub f { $a[0]=7; 0 } my $n = ++$a[0] + f(); print "$n\n";` | `7` | `2` |
| y/yp84 | `my %h=(k=>1); sub f { $h{k}=7; 0 } my $n = ($h{k} = 5) + f(); print "$n\n";` | `7` | `5` |
| y/yp85 | `my @a=(1); my $f = sub { $a[0]=7; 0 }; my $n = ($a[0] = 5) + $f->(); print "$n\n";` | `7` | `5` |
| y/yp90 | `my @a=(1); sub f { $a[0]=7; 0 } my @l = ($a[0] = 5, f()); print "@l\n";` | `7 0` | `5 0` |
| y/yp91 | `my @a=(1); sub f { $a[0]=7; "" } my $s = ($a[0] = 5) . f(); print "$s\n";` | `7` | `5` |
| y/yp94 | `my %h=(a=>1); my $e=\$h{a}; my $n = $h{a} + ($$e = 7); print "$n\n";` | `14` | `8` |
| y/yp95 | `my @a=(1); my $e=\$a[0]; my $s = $a[0] . ($$e = 7); print "$s\n";` | `77` | `17` |
| y/yp97 | `my @a=(1); my $e=\$a[0]; my $n = $a[0] + $$e++; print "$n\n";` | `3` | `2` |
| y/yp99 | `my @a=(1); my @e=(\$a[0]); my $n = $a[0] + (${$e[0]} = 7); print "$n\n";` | `14` | `8` |

#### N5 (16)

| probe | program | perl | chalk |
|---|---|---|---|
| y/yc142 | `my @a=(1,2,3); my @b=(@a[0,1], $a[0]=9); print "@b\n";` | `9 2 9` | `1 2 9` |
| y/yc147 | `my %h=(a=>1); my @b=(values %h, $h{a}=9); print "@b\n";` | `9 9` | `1 9` |
| y/yp100 | `my %h=(a=>1,b=>2); my @b=(@h{qw(a b)}, $h{a}=9); print "@b\n";` | `9 2 9` | `1 2 9` |
| y/yp101 | `my @a=(1,2,3); my @b=(reverse(@a), $a[0]=9); print "@b\n";` | `3 2 9 9` | `3 2 1 9` |
| y/yp102 | `my @a=(1,2,3); my @b=((grep { 1 } @a), $a[0]=9); print "@b\n";` | `9 2 3 9` | `1 2 3 9` |
| y/yp103 | `my @a=(1,2,3); my @b=(@a[0..1], $a[1]=9); print "@b\n";` | `1 9 9` | `1 2 9` |
| y/yp104 | `my @a=(1,2,3); my $r=\@a; my @b=(@$r[0,1], $a[0]=9); print "@b\n";` | `9 2 9` | `1 2 9` |
| y/yp105 | `my @a=(1,2,3); my $r=\@a; my @b=($r->@[0,1], $r->[0]=9); print "@b\n";` | `9 2 9` | `1 2 9` |
| y/yp108 | `my @a=(1,2); my @c=(3); my $c=1; my @b=(($c ? @a : @c), $a[0]=9); print "@b\n";` | `9 2 9` | `1 2 9` |
| y/yp110 | `my @a=(1,2,3); my ($p)=(@a[0,1], $a[0]=9); print "$p\n";` | `9` | `1` |
| y/yp111 | `my @a=(1,2,3); print @a[0,1], $a[0]=9; print "\n";` | `929` | `129` |
| y/yp113 | `my @a=(1,2,3); my $s = join(",", @a[0,1], $a[0]=9); print "$s\n";` | `9,2,9` | `1,2,9` |
| y/yp114 | `my %h=(a=>1); my $s = join(",", values %h, $h{a}=9); print "$s\n";` | `9,9` | `1,9` |
| y/yp115 | `my %h=(a=>1); sub f { $h{a}=9 } my @b=(values %h, f()); print "@b\n";` | `9 9` | `1 9` |
| y/yp116 | `my @a=(1,2,3); sub f { $a[0]=9 } my @b=(@a[0,1], f()); print "@b\n";` | `9 2 9` | `1 2 9` |
| y/yp119 | `my @a=(1,2,3); my @b=(@a[0,1], $a[0]++); print "@b\n";` | `2 2 1` | `1 2 1` |

#### N6 (13)

| probe | program | perl | chalk |
|---|---|---|---|
| y/yc29 | `my $x="a"; $_ .= "!" for ($x .= "b"); print "$x\n";` | `ab!` | `ab` |
| y/yc31 | `my ($x,$y)=(1,2); ($x = $y) = 7; print "$x $y\n";` | `7 2` | `2 2` |
| y/yp122 | `my @a=("a"); for ($a[0] .= "b") { $_ .= "!" } print "@a\n";` | `ab!` | `ab` |
| y/yp123 | `my $x="a"; for ($x x= 2) { $_ .= "!" } print "$x\n";` | `aa!` | `aa` |
| y/yp124 | `my $x=1; for (++$x) { $_++ } print "$x\n";` | `3` | `2` |
| y/yp126 | `my $x="a"; my @t = map { $_ .= "!" } ($x .= "b"); print "$x\n";` | `ab!` | `ab` |
| y/yp130 | `my $x="a"; s/a/z/ for ($x .= "a"); print "$x\n";` | `za` | `aa` |
| y/yp131 | `my $x="a"; my @t = grep { s/a/z/ } ($x .= "a"); print "$x\n";` | `za` | `aa` |
| y/yp135 | `my $y=2; (my $z = $y) = 7; print "$z $y\n";` | `7 2` | `2 2` |
| y/yp140 | `my ($x,$y)=(1,2); (($x = $y)) = (7); print "$x $y\n";` | `7 2` | `2 2` |
| y/yp143 | `my @a=(1); my $y=2; ($a[0] = $y) = 7; print "@a $y\n";` | `7 2` | `2 2` |
| y/yp144 | `our ($x,$y)=(1,2); ($x = $y) = 7; print "$x $y\n";` | `7 2` | `2 7` |
| y/yq38 | `my ($x,$y)=(1,2); (($x, $y) = (5,6)) = (7); print "$x", defined $y ? $y : "u", "\n";` | `7u` | `56` |

#### N7 (11)

| probe | program | perl | chalk |
|---|---|---|---|
| y/ye20 | `package C; sub new { bless {}, shift } sub m { shift; "@_" } package main; our $g=1; print C->new->m($g, $g++), "\n";` | `2 1` | `1 1` |
| y/yp147 | `package C; sub m { shift; "@_" } package main; our $g=1; print C->m($g, $g++), "\n";` | `2 1` | `1 1` |
| y/yp151 | `package C; sub new { bless {}, shift } sub m { shift; "@_" } package main; our $g=1; my $o=C->new; print $o->m($g, $g = 5), "\n";` | `5 5` | `1 5` |
| y/yp152 | `package C; sub new { bless {}, shift } sub m { shift; "@_" } package main; our $g=1; my $o=C->new; print $o->m($g, ++$g), "\n";` | `2 2` | `1 2` |
| y/yp155 | `package C; sub new { bless {}, shift } sub m { shift; "@_" } sub k { $main::g++ } package main; our $g=1; my $o=C->new; print $o->m($g, $o->k), "\n";` | `2 1` | `1 1` |
| y/ye60 | `our $g="ab"; sub f { "@_" } print f($g, $g =~ tr/a/z/), "\n";` | `zb 1` | `ab 1` |
| y/yp178 | `our $g="ab"; print $g, $g =~ tr/a/z/; print "\n";` | `zb1` | `ab1` |
| y/yp179 | `our $g="ab"; my @l = ($g, $g =~ tr/a/z/); print "@l\n";` | `zb 1` | `ab 1` |
| y/yp180 | `our $g="ab"; my $s = $g . ($g =~ tr/a/z/); print "$s\n";` | `zb1` | `ab1` |
| y/yp181 | `my @a=("ab","c"); my @l = (@a, $a[0] =~ tr/a/z/); print "@l\n";` | `zb c 1` | `ab c 1` |
| y/yp182 | `my @a=("ab"); my @l = ($a[0], $a[0] =~ tr/a/z/); print "@l\n";` | `zb 1` | `ab 1` |

#### N8 (10)

| probe | program | perl | chalk |
|---|---|---|---|
| y/ye54 | `our $g=1; sub f { "@_" } print f($g, local $g = 5), "\n";` | `1 5` | `5 5` |
| y/yp167 | `our $g=1; print $g, local $g = 5; print "\n";` | `15` | `55` |
| y/yp168 | `our $g=1; my @l = ($g, local $g = 5); print "@l\n";` | `1 5` | `5 5` |
| y/yi19 | `sub inc { $_[0]++ } our $g=1; sub t { inc(local $g); $g } print t(), "$g\n";` | `11` | `21` |
| y/yj33 | `our $g=1; sub p { print $g } my $c=1; { local $g = 5 if $c; p() } p(); print "\n";` | `51` | `55` |
| y/yq19 | `our $g=1; sub p { $g } sub t { local $g = 5 if $_[0]; p() } print t(1), t(0), p(), "\n";` | `511` | `555` |
| y/yq21 | `our $g=1; sub p { $g } sub t { $_[0] and local $g = 5; p() } print t(1), t(0), p(), "\n";` | `511` | `555` |
| y/yj37 | `our $g=1; sub t { local $g; defined $g ? "d" : "u" } print t(), $g, "\n";` | `u1` | `d1` |
| y/yq17 | `our $g=1; sub p { defined $g ? $g : "u" } sub t { local $g; p() } print t(), p(), "\n";` | `u1` | `11` |
| y/yj41 | `our %h=(a=>1,b=>2); sub g1 { join ",", map { "$_$h{$_}" } sort keys %h } sub t { my $v = delete local $h{a}; $v . g1() } print t(), g1(), "\n";` | `1b2a1,b2` | `1b2b2` |

#### N9 (22)

| probe | program | perl | chalk |
|---|---|---|---|
| y/yd19 | `use YInit; BEGIN { print YInit::get(), "\n" }` | `1` | (empty) |
| y/yd24 | `use YInit; INIT { $YInit::n = 7 } print "$YInit::n\n";` | `7` | `1` |
| y/yd35 | `use YRef; push @$YRef::r, 2; print YRef::lstr(), "\n";` | `1 2` | `1` |
| y/yd36 | `use YRef; push @$YRef::p, 2; print "@$YRef::q\n";` | `1 2` | `1` |
| y/yd39 | `use YRef; push @{$YRef::h{a}}, 2; print "@$YRef::ha\n";` | `1 2` | `1` |
| y/yd40 | `use YRef; print $YRef::p == $YRef::q ? "same" : "diff", $YRef::r == \@YRef::l ? "same" : "diff", "\n";` | `samesame` | `diffdiff` |
| y/yd41 | `use YRef; $YRef::l[0] = 5; print "$$YRef::r[0]\n";` | `5` | `1` |
| y/yd43 | `use YPriv; print YPriv::priv(), YPriv::bump(), YPriv::priv(), "\n";` | `566` | `11` |
| y/yd44 | `use YPriv; print YPriv::pl(), YPriv::ph(), "\n";` | `1 21` | (empty) |
| y/yd46 | `use YPriv; YPriv::addpl(3); print YPriv::pl(), "\n";` | `1 2 3` | `3` |
| y/yd48 | `use YPrint; print "main\n";` | `loading main` | `main` |
| y/yd49 | `use YPrint; print YPrint::v(), "\n";` | `loading 1` | `1` |
| y/yd50 | `our $g; use YMain; print defined $g ? $g : "u", "\n";` | `7` | `u` |
| y/yd51 | `our @l; use YMain; print scalar(@l), "\n";` | `2` | `0` |
| y/yd52 | `use YMain; print defined $Other::v ? $Other::v : "u", "\n";` | `3` | `u` |
| y/yd54 | `our $imp; use YImp; print defined $imp ? $imp : "u", YImp::cnt(), "\n";` | `i1` | `u1` |
| y/yd55 | `our $imp; use YImp; use YImp; print "$imp $YImp::cnt\n";` | `ii 2` | ` 2` |
| y/yd69 | `use YPhase; print YPhase::get(), "\n";` | `9 lib end` | `1` |
| y/yd70 | `use YPhase; $YPhase::n++; print "$YPhase::n\n";` | `10 lib end` | `2` |
| y/yj68 | `INIT { print "i" } CHECK { } BEGIN { print "b" } print "r"; END { print "e\n" }` | `bire` | `bre` |
| y/yq13 | `INIT { print "i" } print "r\n";` | `ir` | `r` |
| y/yq15 | `CHECK { print "c" } print "r\n";` | `cr` | `r` |

#### N10 (5)

| probe | program | perl | chalk |
|---|---|---|---|
| y/yf81 | `my $i=7; sub p { print $i } for $i (1..3) { p() } print "$i\n";` | `7777` | `1233` |
| y/yp197 | `my $i=7; sub p { print $i } for $i (1..2) { p() } p(); print "\n";` | `777` | `122` |
| y/yp198 | `my $i=7; my $c = sub { $i }; for $i (1..2) { print $c->() } print "\n";` | `77` | `12` |
| y/yp199 | `my $i=7; my $c = sub { $i }; for $i (1..2) { print $i } print $c->(), "\n";` | `127` | `122` |
| y/yp204 | `my $i=7; my $r=\$i; for $i (1..2) { print $$r } print "\n";` | `77` | `12` |

#### N11 (6)

| probe | program | perl | chalk |
|---|---|---|---|
| y/yi23 | `sub inc { $_[0]++ } my $s="1b"; inc(substr($s,0,1)); print "$s\n";` | `2b` | `1b` |
| y/yi24 | `sub inc { $_[0]++ } my @a=(1); inc($#a); print scalar(@a), "\n";` | `2` | `1` |
| y/yq33 | `sub inc { $_[0]++ } my $s="15"; inc(substr($s,1,1)); my @a=(1,2); inc($a[$#a]); inc($#{[1]}); print "$s@a\n";` | `161 3` | `151 3` |
| y/yq34 | `sub set { $_[0] = "ZZ" } my $s="abc"; set(substr($s,0,1)); print "$s\n";` | `ZZbc` | `abc` |
| y/yq35 | `my $s="abc"; for (substr($s,0,1)) { $_ = "ZZ" } print "$s\n";` | `ZZbc` | `abc` |
| y/yq37 | `my @a=(1,2); for ($#a) { $_ = 3 } print scalar(@a), "\n";` | `4` | `2` |

#### N12 (15)

| probe | program | perl | chalk |
|---|---|---|---|
| y/yg60 | `print length("abc"), length(""), defined(length(undef)) ? "d" : "u", length(12345), length(1.50), "\n";` | `30u53` | `30d53` |
| y/yq25 | `my $u; print defined(length($u)) ? "d" : "u", defined(length(undef)) ? "d" : "u", length($u) // "U", "\n";` | `uuU` | `dd0` |
| y/yh26 | `sub f { reverse "abc" } my $s = f(); my @l = f(); print "$s@l", scalar(reverse("ab","cd")), "\n";` | `cbaabcdcba` | `cbacbadcba` |
| y/yq23 | `sub f { reverse @_ } my $s = f("ab","cd"); my @l = f("ab","cd"); print "$s@l\n";` | `dcbacd ab` | `dcbadcba` |
| y/yq24 | `sub f { return reverse "abc" } sub g { scalar reverse "abc" } print f(), g(), scalar(f()), "\n";` | `abccbacba` | `cbacbacba` |
| y/yh48 | `my @a = (1) x 3; my @b = (1,2) x 2; my @c = ((1,2) x 2, 3); my $s = (1,2) x 2; my @d = (0) x @a; print "@a\|@b\|@c\|$s\|@d\n";` | `1 1 1\|1 2 1 2\|1 2 1 2 3\|22\|0 0 0` | `1 1 1\|1 2 1 2\|1 2 1 2 3\|4\|0 0 0` |
| y/yq22 | `my $s = (1,2) x 2; my $t = ("a","b") x 3; my $n = () = (1,2) x 3; print "$s$t$n\n";` | `22bbb6` | `466` |
| y/yl24 | `print join("\|", split /(,)/, "a,b"), " ", join("\|", split /,/, ",a"), " ", join("\|", split /,/, "a,b,c", 2), " ", scalar(my @p = split /,/, ""), " ", join("\|", split /\s*,\s*/, "a , b,c"), "\n";` | `a\|,\|b \|a a\|b,c 0 a\|b\|c` | `a\|,\|b \|a a\|b,c a\|b\|c` |
| y/yl26 | `print join("\|", split(/(-)\|(\+)/, "a-b+c")) =~ s/\\|\\|/\|u\|/gr, " ", join("\|", split /x/, "axbxc", -1), " ", join("\|", split(//, "ab", 5)), " ", join("\|", split(/^/, "a\nb\n")) =~ s/\n/N/gr, "\n";` | `a\|-\|u\|b\|u\|+\|c a\|b\|c a\|b\| aN\|bN` | `a\|-\|u\|b\|u\|+\|c a\|b\|c a\|b aN\|bN` |
| y/yq27 | `print join("\|", split(//, "ab", 5)), " ", join("\|", split(//, "abc", 2)), " ", join("\|", split(/,/, "a,b", 5)), " ", join("\|", split(/,/, "a,b,,", 5)), "\n";` | `a\|b\| a\|bc a\|b a\|b\|\|` | `a\|b a\|bc a\|b a\|b\|\|` |
| y/yl06 | `"x1" =~ /(\d)/; for my $s (qw(a b)) { print $1; "y2" =~ /(\d)/ if $s eq "a" } print $1, "\n";` | `121` | `111` |
| y/yn20 | `eval { eval { die "first\n" }; die }; print $@ =~ /^first\n\t\.\.\.propagated at/ ? "prop" : "other:$@", "\n";` | `prop` | `other:Died at /home/user/repo/docs/research/son-ir-audit-2026-11-19/probes/y/yn20.pl line 1.` |
| y/yq31 | `eval { $@ = "preset\n"; die }; print $@ =~ /^preset\n\t\.\.\.propagated/ ? "prop" : "other", "\n";` | `prop` | `other` |
| y/unverified/yo23 | `use Env qw(HOME); print defined $HOME ? "env" : "none", "\n";` | `env` | `none` |
| y/yo24 | `use English qw(-no_match_vars); "abc" =~ /b/; print $PROGRAM_NAME =~ /yo/ ? "name" : "other", defined $PID ? "pid" : "", $OUTPUT_AUTOFLUSH, "\n";` | `namepid0` | `other` |

Not counted: `y/ya57`, `my @a=(1,2); sub f { my $n=scalar @_; shift @a; "$n@_" } print f(@a)`. perl prints `2 2`: `@_` holds the scalar `shift` freed. chalk prints `22`. Neither is the value a careful reader expects (`21 2`).

## 5. Thirty new verifier violations

The ratchet reads `probes/*/*.pl`, so these are in `probes/y/unverified/`.

| probes | rule | verdict | whose fault |
|---|---|---|---|
| `ya37`, `yp40`, `yp41`, `yp191`, `yp42` | `read-unversioned:args`: a used record of `@_` in a sub that stores through `$_[0]` by `tr///` | WRONG (4), SAME (`yp42`) | producer; the verifier is right |
| `ya49`, `yp56`, `yp57`, `yp58`, `yp59`, `ya10` | `alias-not-private`: an argument read by the callee after a store | WRONG (5), SAME (`ya10`) | producer or chalk; the verifier is right on the five |
| `yp01`, `yp18`, `yp19`, `yp21`, `yp22`, `yp185`, `yb41` | `alias-not-private`: a per-pass item used after a store | SAME (7) | the producer's wire; chalk reads it right anyway |
| `ye49` | `alias-not-private` (argument) | SAME | as above |
| `yc160` | `read-unversioned:my-aggregate` | SAME | producer |
| `ye53`, `yp158` | `read-unversioned:package` | REFUSED | producer |
| `yn26` | `write-unreachable`, `control-fork`, `control-sink`: `eval { die } \|\| do { chomp(my $e = $@) ... }` | REFUSED by the loader (L4) | producer |
| `yo27` (`Math::BigInt`), `yo30` (`Benchmark`), `yo33` (`Text::Balanced`) | `write-unreachable`, `control-fork`, `control-sink`, `effect-floating` (12), `read-unversioned` | REFUSED | producer, on real module code |
| `yo15` (`List::Util`), `yo17` (`Data::Dumper`), `yo22`, `yo23` (`Tie::Array`) | `read-unversioned` in followed module subs | REFUSED (2), SAME (`yo22`), WRONG (`yo23`, for another reason) | producer |

Two things follow. The verifier's rules are right where they fire on wrong wires: 9 wrong answers would have been stopped had the loader held V6 and V12 as it holds L4. And the rules' zero on the gated sets is a zero on those sets: one `use` of a core module brings wires that break five rules.

## 6. Design risks, ranked

1. **Each fix is as wide as its probes.** 101 of 146 wrong answers are the next shape past a K-class fix or refusal. The refusals are keyed on how the store is spelled (an assignment by name in a later operand; a whole array; a direct call; `$_[N] =`). Perl's rule is about the scalar: anything that can reach it. Key each refusal on "an operand or list item that is an lvalue, and anything later in the statement that may store", with the MOD sets and "a reference proves nothing" as the default. That is one rule for N4, N5, N6 and N7.
2. **`tr///` is not a store in the scans.** N1 (5 probes), N7 (6), one `lli` crash. `ModSets::_stores`, `args_may_be_places` and the "later operand stores it" refusal each list the ops that store, and `tr` is missing from at least two. One table of storing ops, read by every scan (the effect table already does this for builtins), closes this and the next omission.
3. **A list is flattened once; an alias is per scalar.** N3, N5, N2. The iterator fix aliases by reference for a lexical iterator over one array. `$_`, map, grep, several items, `values`, slices and `@_` are still copies or indices. Either they all become places, or each is refused when anything in the loop body or the statement may store (not only "read after a call in the same pass").
4. **The start state is whatever CHECK shows for package data.** N9, 22 wrong. A module's file lexicals, shared references, file-level output, `import` effects, stores into the program's package, INIT and CHECK blocks: none is on the wire and none is refused. Refuse a followed module whose file has lexicals a sub closes over, or code with effects, until it is modelled.
5. **The verifier is not held on new wires.** It now catches 9 wrong wires, but the loader does not run V6 or V12, so chalk compiled all 9. And 30 of 1373 fresh programs break a rule, 7 of them through core modules. Put the two alias rules in the loader, or run `SoN::Verify` in B::SoN before the wire leaves.
6. **`local` is still a store to one place.** N8, and K2 is open. `local $g;` with no value and a conditional `local` are plain producer faults, not the design question. Fix those two; the K2 decision then covers the rest.
7. **A value stands where perl has a magic lvalue.** N11: `substr` and `$#a` as arguments or foreach items. Refuse them where the callee may write `$_[N]`, as `||` and `&&` already are (`yi07`-`yi09`).
8. **The outer lexical as a foreach variable.** N10. Small and mechanical: the loop needs its own slot.
9. **Refusal hides what is behind it.** 421 of 1373 refused. Of the 40 `yo` probes 6 are SAME; no real module's state is exercised end to end.
10. **Leftovers.** `corpus/398`'s `Call` on no chain; `writer: chalk`; `zcp83`; `zpk11`; "no program graph" for an XS module; five LOUD messages that say an existing method cannot be found.

## 7. The trend

| audit | new probes | WRONG | rate |
|---|---|---|---|
| IR audit, 2026-11-19 | | 59 | |
| goal audit, 2026-11-22 | 288 | 55 | 19% |
| re-audit, 2026-11-23 | | 68 | |
| final audit, 2026-11-24 | 847 | 111 | 13% |
| final audit 2, 2026-11-25 | 828 | 57 | 7% |
| this audit | 1373 | 146 | 10.6% |

The rate is not falling. Audit 2 read 13% to 7% as a trend; this audit, with the same method (an aimed round, then a round around the hits), finds 10.6%. The first round alone is 6.4%, about audit 2's whole rate, and the second round's 38% says each hit has many neighbours.

What did change: the wrong answers moved outward. None is in a shape an earlier audit probed. The broad round over areas no audit had covered is 2.9%, and arithmetic, formatting, sorting, objects and exceptions are clean. The wrong answers are concentrated where perl has aliases and the wire has values, and in the start state. That is the same place as at the two audits before.

The count in the gate is zero after every fix round and has been each time. It measures the probe set. Until the refusals are keyed on the property and not the spelling (risk 1), the next audit will find the next ring.

## 8. What was run, and what was not

Run here, at 76f33aa / eca706af:

- chalk `tools/audit-probes.pl` over all 3179 gated probes;
- `SON_RATCHET=1 prove -l t/wire-verify-ratchet.t` on a snapshot (corpus, probes, chalk's lib);
- `tools/wire-verify.pl --tsv` over corpus, probes and chalk's lib, then over the probes with `y/` added;
- a scan of my own over 5209 wires (`mem_in`, `inputs`, records, loops, version);
- 1373 new probes in three batches (`_run1.log`), once each;
- with the new probes in place: `t/wire-verify-ratchet.t`, `t/loop-body-is-walked-once.t`, `t/pre-scan-agrees-with-the-walk.t`, `t/placement-one-constructor.t`, `t/wire-verify-rejects-hand-broken-wires.t`, `t/effect-table-has-a-row-for-every-builtin.t`;
- wire dumps for 21 wrong probes (the "traced on" column).

Not run: either full suite, the census, the corpus gate, the deparser round trip, chalk's `t/bootstrap/ir/wire-verify.t`. The side of each class is read off one or two wires, not from the source; N12's is mostly not traced. The new probes are not in chalk's `t/data/audit-probes`: the gate does not hold them yet.
