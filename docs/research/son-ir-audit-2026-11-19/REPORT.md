# Audit: the B::SoN / chalk sea-of-nodes IR against the SSA literature (2026-11-19)

Producer: `/home/user/repo`, `wip/chalk-lib-roundtrip`, c205256. Consumer: `/home/perigrin/dev/chalk`, `bson/llvm-corpus`, c1a48dfe. A wire line `13 Assign [7,12] ^10` means node 13, inputs 7 and 12, `control_in` 10.

Theory: the summaries in [`docs/research/ssa/`](../ssa/README.md). Read-only audit by a Fable agent (effort xhigh); neither repo was changed. Probes, logs and the checking scripts are alongside this file (see [README](README.md)).

## 1. Executive summary

The design for memory (one chain, effectful nodes as the versions) is one the literature documents, and it is sound. What is missing is the rule that makes it safe: every node that touches memory takes memory in and gives memory out, by construction, where a checker can see it. In our IR that rule is kept by hand at about 120 places in the producer, is encoded two ways on the wire, and nothing checks it.

418 probes: 254 ran right, 95 were refused by name, and 69 printed something perl does not. Of the 69, 4 are known, 6 are set aside (see the end of section 4), and 59 are new silent wrong answers in 10 classes.

Top 10 findings, most severe first:

1. **A package scalar assigned in a loop is carried round the loop as a value, so a sub called in the loop cannot change it.** A global counter with a helper sub prints 13 for 33, and one probe never ends. New; producer (`lib/SoN/FromOptree.pm:8199-8205`, `10068-10085`).
2. **A store is on the memory chain only where a hand-written rule put it; a list assignment the rule misses is silently deleted.** New shapes: slices, `@_ = (...)`, `($r->[0],...)`, and `($x) = ...` of a captured variable. It occurs in chalk's own backend (`Builder/Control.pm:926`, `1075`, `1081`). Producer (`FromOptree.pm:11831-11840`).
3. **Some reads of changeable state carry no memory version, so two reads either side of a write are one node.** `ref($o)` before and after `bless` prints `K K` for `HASH K`. A package array flattened into a list is read after a later store. New.
4. **Some effects ride a value edge instead of the chain, so they run at first use, or never.** `$o->$m()` in void context is dropped, and `bless` used for its value runs late. In library code the same shape holds `open`, `chdir`, `mkdir`, `exec`. New; producer (`FromOptree.pm:5358-5366`).
5. **A fault has no place in the graph.** `1/$d` dies after an earlier `print`. An `eval` join has one way in but two-input Phis. A `die` of a reference becomes a string. New.
6. **`local` is restored only on exits someone wrote a rule for.** It is wrong through a `die` and on a loop pass. New.
7. **Arguments are values; chalk guesses from the node kind which are aliases.** A captured variable handed to a sub that writes `$_[0]` is not written. New.
8. **The memory chain is encoded two ways.** `EntryWrite`, `CellWrite`, `Delete` and `push` take memory as an input, as Click's Store does. `Assign` and every sub call do not, and `Return` takes none. This causes no wrong answer by itself, but it is why 1 to 4 are possible and uncheckable.
9. **No checker can see a floating write.** chalk's `TypedInvariant.pm:297` is called by nothing in `lib/`, and the graph it would walk has already lost the node. It answers "ok" on the known-wrong wire.
10. **Loops are right on every probe not refused, but each body is walked twice.** Producer time doubles per nesting level (depth 10: 1.4 s; 12: 4.9 s; 14: 20 s). The wire has no back edge and no `If` for the loop test.

Two further gaps: `DESTROY` is never called and is not refused, and a nested read does not autovivify.

## 4. New silent wrong answers

Each row is program, perl's stdout, chalk's stdout (B::SoN, then chalk T2, then lli). Probe files are `probes/p/NAME.pl` (`nv*` and `vp*` are in `probes/q/`). The `wrong_W*.md` files here are script-generated listings of each class.

**W1. Package scalar carried round a loop while a callee writes it (11; producer)**

| probe | program | perl | chalk |
|---|---|---|---|
| pg1 | `our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; bump(); } print "$g\n";` | `33` | `13` |
| pl4 | `our $g = 0; sub bump { $g += 10 } my $i = 0; while ($i < 3) { $i++; $g = $g + 1; bump(); } print "$g\n";` | `33` | `13` |
| pl5 | `our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g++; bump(); } print "$g\n";` | `33` | `13` |
| pl6 | `our $g = 0; sub bump { $g += 10 } for my $i (1..3) { bump(); $g = $g + 1; } print "$g\n";` | `33` | `3` |
| pl8 | `our $g = 0; package O; sub new { bless {}, shift } sub hit { $main::g += 10 } package main; my $o = O->new; for my $i (1..3) { $g = $g + 1; $o->hit; } print "$g\n";` | `33` | `13` |
| pl11 | `our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; if ($i > 1) { bump() } } print "$g\n";` | `23` | `13` |
| pg2 | `our $g = 0; my $s = ""; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; bump(); $s .= "$g," } print "$s\n";` | `11,22,33,` | `1,2,3,` |
| tp5 | `our $depth = 0; sub walk { my $n = shift; $depth++; walk($n - 1) if $n > 0; return } for my $k (1..2) { $depth = $depth + 0; walk($k) } print "$depth\n";` | `5` | `3` |
| tp6 | `our $total = 0; sub add { $total += $_[0] } for my $x (1..4) { add($x); $total = $total * 1 } print "$total\n";` | `10` | `0` |
| tp7 | `our $s = ""; sub ap { $s .= $_[0] } for my $c ("a".."c") { $s .= "-"; ap($c) } print "$s\n";` | `-a-b-c` | `-a` |
| pl10 | `our $n = 0; sub step { $n++ < 3 } my $t = 0; while (step()) { $t += $n; $n = $n + 0 } print "$t $n\n";` | `6 4` | never ends |

**W2. List assignment whose store floats: new target shapes (15; producer)**

| probe | program | perl | chalk |
|---|---|---|---|
| slice1 | `my %h; @h{qw(a b)} = (1,2); print "$h{a} $h{b}\n";` | `1 2` | ` ` |
| slice2 | `my @a = (0,0,0); @a[0,1] = (5,6); print "@a\n";` | `5 6 0` | `0 0 0` |
| slice3 | `my %h = (a=>0); my @k = ("a","b"); @h{@k} = (7,8); print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";` | `a=7,b=8` | `a=0` |
| wa18 | `my @a = (1,2,3); my ($x, $y) = @a[0,1]; @a[0,1] = ($y, $x); print "@a\n";` | `2 1 3` | `1 2 3` |
| swap1 | `my @a = (1,2); ($a[0], $a[1]) = ($a[1], $a[0]); print "@a\n";` | `2 1` | `1 2` |
| swap3 | `my %h = (a=>1, b=>2); ($h{a}, $h{b}) = ($h{b}, $h{a}); print "$h{a} $h{b}\n";` | `2 1` | `1 2` |
| la2 | `my $r = [0,0]; ($r->[0], $r->[1]) = (3,4); print "@$r\n";` | `3 4` | `0 0` |
| la3 | `our @g = (0,0); ($g[0], $g[1]) = (3,4); print "@g\n";` | `3 4` | `0 0` |
| la5 | `my %h; my ($k, $v) = ("a", 1); ($h{$k}) = ($v); print "$h{a}\n";` | `1` | (empty line) |
| la6 | `my @a = (0,0); my $i = 0; ($a[$i++], $a[$i++]) = (8,9); print "@a $i\n";` | `8 9 2` | `0 0 2` |
| ar12 | `sub f { @_ = (9, 9); $_[0] = 3 } my $x = 1; f($x); print "$x\n";` | `1` | `3` |
| cl15 | `my %h = (a => 1); my $g = sub { join ",", map { "$_$h{$_}" } sort keys %h }; $h{b} = 2; ($h{c}) = (3); print $g->(), "\n";` | `a1,b2,c3` | `a1,b2` |
| cl1 | `my $x = 1; my $g = sub { $x }; ($x) = (7); print $g->(), "\n";` | `7` | `1` |
| cl2 | `my $x = 1; my $g = sub { $x }; my @l = (7, 8); ($x) = @l; print $g->(), "\n";` | `7` | `1` |
| cl25 | `my $x = 5; my $g = sub { $x }; my $s = "v=5"; ($x) = $s =~ /(\d)/ ? 6 : 0; print $g->(), "\n";` | `6` | `5` |

**W3. Dynamic method call off the chain (2; producer)**

| probe | program | perl | chalk |
|---|---|---|---|
| dyn1 | `package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; return } package main; my $o = C->new; my $m = "inc"; $o->$m(); print $o->{n}, "\n";` | `1` | `0` |
| dyn2 | same class, `inc` returning 5; `my $r = $o->$m(); print "$r $o->{n}\n";` | `5 1` | `5 0` |

**W4. `ref` / `blessed` read at no memory version; `bless` as a value (8; producer and wire)**

| probe | program | perl | chalk |
|---|---|---|---|
| ef9 | `my $o = {}; my $c = ref($o); bless $o, "K"; my $d = ref($o); print "$c $d\n";` | `HASH K` | `K K` |
| bless2 | `my $h = {}; my $o = bless $h, "K"; print ref($h), " ", ref($o), "\n";` | `K K` | `HASH K` |
| ef10 | `my $o = bless {}, "A"; my $c1 = ref $o; my $p = bless $o, "B"; print "$c1 ", ref($o), "\n";` | `A B` | `A A` |
| st2 | `use Scalar::Util qw(blessed); my $o = {}; my $a = blessed($o) // "u"; bless $o, "K"; my $b = blessed($o) // "u"; print "$a $b\n";` | `u K` | `K K` |
| st6 | `my $o = bless {}, "A"; my $a = ref($o); my $q = $o; bless $q, "B"; print "$a ", ref($o), "\n";` | `A B` | `B B` |
| st7 | `sub mk { return bless {}, "A" } sub re { bless $_[0], "B"; return } my $o = mk(); my $a = ref($o); re($o); print "$a ", ref($o), "\n";` | `A B` | `B B` |
| st14 | `my $f = sub { 1 }; my $a = ref($f); my $h = {}; my $b = ref($h); bless $h, "Z"; print "$a $b ", ref($h), "\n";` | `CODE HASH Z` | `CODE Z Z` |
| vp19 | `my $o = {}; my @r = (ref($o), ref(bless $o, "K"), ref($o)); print "@r\n";` | `HASH K K` | `HASH K HASH` |

**W5. `@_` alias of a captured variable (3)**

| probe | program | perl | chalk |
|---|---|---|---|
| cl23 | `my $x = 1; my $g = sub { $x }; sub setx { $_[0] = 12 } setx($x); print $g->(), "\n";` | `12` | `1` |
| ar21 | `my $x = 1; my $g = sub { $x }; my $set = sub { $_[0] = 5 }; $set->($x); print $g->(), "\n";` | `5` | `1` |
| ar22 | `my $c = 0; my $g = sub { $c }; sub bump { $_[0]++ } bump($c) for 1..3; print $g->(), "\n";` | `3` | `0` |

**W6. `local` not put back (3)**

| probe | program | perl | chalk |
|---|---|---|---|
| lo2 | `our $g = 1; sub t { local $g = 2; die "x\n" } eval { t() }; print "$g\n";` | `1` | `2` |
| lo3 | `our $g = 1; for my $i (1..2) { local $g = $g + $i; last if $i == 2 } print "$g\n";` | `1` | `4` |
| lo16 | `our $v = 1; sub show { print $v } sub t { local $v = 2; show(); eval { local $v = 3; show(); die "x\n" }; show() } t(); show(); print "\n";` | `2321` | `2331` |

**W7. Faults and exceptions (8)**

| probe | program | perl | chalk |
|---|---|---|---|
| fl1 | `my $d = @ARGV; my $q = 1 / $d; print "before\n"; print "$q\n";` | prints nothing, dies | prints `before`, dies |
| fl6 | the same with `7 % $d` | prints nothing, dies | prints `before`, dies |
| fl5 | `use strict; my $r; print "a\n"; my @l = @$r; print "b\n";` | `a`, dies | `a\nb`, exit 0 |
| ex1 | `eval { die { code => 7 } }; print ref($@), " ", (ref $@ ? $@->{code} : "str"), "\n";` | `HASH 7` | ` str` |
| ex2 | `eval { die [1,2] }; print ref($@) ? "ref" : "str", "\n";` | `ref` | `str` |
| ex3 | `package E; sub new { bless { m => $_[1] }, $_[0] } sub msg { $_[0]{m} } package main; eval { die E->new("oops") }; print ref($@) ? $@->msg : "str:$@", "\n";` | `oops` | `str:E=HASH(0x..) at ... line 1.` |
| ex4 | `my $e; { local $@; eval { die { code => 7 } }; $e = $@ } print ref($e), "\n";` | `HASH` | (empty line) |
| ev6 | `my $x = 1; { local $@; eval { $x = 5; die { code => 7 } }; $x += $@->{code} if ref $@ } print "$x\n";` | `12` | `5` |

fl5 and ex1 to ev6 are chalk-side (`Builder/Control.pm:130-132`, `:167`); fl1 and fl6 are the producer's floating `Divide`.

**W8. `DESTROY` never runs (2). W9. No autovivification on a nested read (1).**

| probe | program | perl | chalk |
|---|---|---|---|
| ca29 | `my @o; sub DESTROY { push @o, "d" } { my $x = bless [], "main"; } print "@o\n";` | `d` | (empty line) |
| im6 | `my @o; package D; sub new { bless {}, shift } sub DESTROY { push @o, "d" } package main; my $x = D->new; undef $x; print "@o\n";` | `d` | (empty line) |
| fl11 | `my $h = { a => 1 }; my $v = $h->{b}{c}; print exists $h->{b} ? "viv" : "none", "\n";` | `viv` | `none` |

**W10. A package array or hash flattened into a list is read at no memory version (6)**

| probe | program | perl | chalk |
|---|---|---|---|
| nv1 | `our @st = (1); my @c = (@st, 2); @st = (); print "@c\n";` | `1 2` | `2` |
| nv4 | `our @g = (1,2); my @c = (0, @g); @g = (7); print "@c\|@g\n";` | `0 1 2\|7` | `0 7\|7` |
| nv5 | `our %g = (a => 1); my @k = (%g); %g = (); print scalar(@k), "\n";` | `2` | `0` |
| nv7 | `our @g = (1,2); sub cp { my @c = (@g, 0); @g = (); return scalar @c } print cp(), scalar(@g), "\n";` | `30` | `10` |
| nv8 | `our @g = (1); sub t { local @g = (@g, 2); return scalar @g } print t(), scalar(@g), "\n";` | `21` | `11` |
| lo14 | the same shape with `@st` | `21` | `11` |

**Set aside (6).**
- `im23`, `ar17`, `fl10`: chalk stops at run time with a message, so they are loud, not silent.
- `fl14`: `use warnings FATAL`, out of scope.
- `vp5`: `$a[0] + ($a[0] = 10) + $a[0]`, perl's late read of an aliased operand.
- `io8`: a harness artefact (stdout buffering against stderr).

**Known, reconfirmed (4).** `m4` (` 10` for `9 10`), `ht1`, `ht2`, `st10` (hash truth and `my $n = %h`). `($a[0],$c)=(5,6)` and the captured `($x, my $y)` are also still wrong.

## 2. The four areas

### 2.1 Memory chain

**The idea.** Give "everything in memory" a version number. Each write makes the next version, each read names the version it looks at, and a Phi merges versions where paths meet. A write that makes no version is invisible to every later read.

**Theory.**
- Click and Paleczny section 2.5: `Store(STORE, addr, val)` gives a new STORE, `Load(STORE, addr)` gives a value, Phi merges STOREs, and calls take and return control, STORE and I/O.
- Click, code motion: "all dependence must be explicit... Faulting instructions keep an explicit control input."
- libFIRM: Load and Store both take and give M; `Call ... x M -> ... x M`; `Return` consumes M.
- Cytron 3.1: the heap is one variable "both modified and used by any statement that may change the heap".
- Cytron, Lowry and Zadeck: a may-write "both USEs and DEFs"; a call is "a birthpoint for all external variables".
- SSA book 12.5 (VSDG): one state edge; the return node returns the state; what the exit does not reach is deleted.
- Kelsey: captured and mutated variables are cells.

**What we do.**

- **One chain from `MemStart`** (`FromOptree.pm:2371`, `StackSim.pm:13-17`), with no slices. *Sound, deliberate.*
- **The effectful node is the version; there is no Store or Load.** For `$a[0] = 10; my $x = $a[0]; $a[1] = $x + 1` (`probes/w/a1.pl`):
  ```
   8 Subscript [5,6]        the place $a[0]: container, index, no memory
  10 Assign    [8,9] ^0     the store; this node is the next memory version
  11 Subscript [5,6,10]     the read: container, index, memory version 10
  13 Assign    [7,12] ^10   the next store
  24 Return    [1] ^23
  ```
  The SSA book treats this as equivalent to Store/Load. *Sound.* In the corpus 17 kinds stand as versions. They include four kinds of pinned read (`PostfixDeref` 150 times, `Subscript` 75, `Exists` 8, `Ref` 4).
- **Departure: a write does not name the version it follows.** Node 13's inputs are place and value; it follows version 10 only through `control_in`. The rule is not uniform:

  | node | memory as an input? | corpus count |
  |---|---|---|
  | `Assign` | no | 605 |
  | sub `Call` (direct, method, indirect) | no | 895 |
  | `Return` | never | 1084 |
  | `EntryWrite [entry, value, memory]` | yes | 187 |
  | `CellWrite`, `Delete`, `ElemRestore`, `MakeCell` | yes | 46 |
  | builtin `Call` flagged `memory_input` | yes | 552 of 743 |

  Whether the two orderings disagree (`tools/memcheck.pl`): on the corpus 793 of 798 pinned nodes agree, and the other 5 are conventions the checker did not model. On the chalk-lib sample 3552 of 3622 agree; the other 70 were not analysed. *Debatable, not unsound.* The cost is that no per-node rule is checkable, and chalk re-derives "is this Phi memory?" from a 40-line case list (`Node/Phi.pm:55-99`).
- **Departure: one node, three jobs.** A `Call` is its value, the memory after it, and a chain point. `Proj` exists only for `If` and `Loop`. Visible effects: memory Phis carry value stamps (`Phi [14,18] Int memory=true`, `probes/w/a2.pl`); memory is found by position per kind (the `memory_input` flag, `Node/Call.pm:74-79`); `Builder.pm:259-308` exists to tell a call-as-value from a call-as-memory. *Debatable.*
- **Departure: writes float.** A version is made by three hand-written lines. `FromOptree.pm` has 89 `set_memory` sites, 172 `set_control`, and 33 `make('Assign')`. List assignment pins by a kind list (`11831-11840`: in a loop, address-taken `my`, `PostfixDeref`, `FieldAccess`). The census (`tools/census.pl`) shows the result:

  | effect | on chain | off, value used | off and unread |
  |---|---|---|---|
  | corpus (431 wires, 1082 graphs): `Assign` to element or slice | 181 | 0 | **9** |
  | `Assign` to a `my` array/hash from `@_` (parameter bind) | 6 | 0 | 8 |
  | `Assign` of SSA scalars only (a record, not a store) | 22 | 0 | 57 |
  | every other `Assign` | 322 | 0 | 0 |
  | sub calls | 894 | 1 | 0 |
  | dynamic method call | **0** | 2 | 0 |
  | `bless` / `qx` | 0 | 45 | 0 |
  | chalk-lib sample (30 wires, 4129 graphs): `Assign` to element | 933 | 0 | **5** |
  | `Assign` to a `my` array/hash (not from `@_`) | 63 | 0 | **2** |
  | `open`, `chdir`, `mkdir`, `exec`, `read`, `sysopen`, `chmod`, `chown`, `readdir` | 0 | 24 | 0 |

  The corpus's 9 are all in library code it loads (`Carp::caller_info`'s `@call_info{...} = ...`, `POSIX::load_imports`), which is why the corpus census reads zero wrong. The chalk-lib 5 include chalk's own `( $b->{cur}, $b->{memo} ) = ...` lines. *Defect.*
- **Departure: nothing can check it.** `TypedInvariant.pm:156, 297-309` has the leg, but nothing in `lib/` calls it. The loaded graph for the known-wrong wire holds 16 of 20 nodes, with no `Assign`, and the check says "ok" (`tools/ti.pl`, `tools/ti2.pl`). It also could not be switched on: floating `Assign`s that are records or parameter binds are legitimate (120 in the corpus).
- **Reads name versions, with holes.** Element, count, `exists`, deref, package-scalar and cell reads carry one. `RefType` has one input: in `probes/p/ef9.pl` node `3 RefType [2]` serves both `ref($o)`. A package aggregate flattened through its named literal has none (`probes/q/nv1.pl`). `time`, `-e` and `rand` are unversioned; chalk refuses what would expose them. *Defect.*
- **Memory Phis.** Built at `if` merges (`StackSim.pm:317-331`), loop headers (`FromOptree.pm:14635`), and loop exits (`14743-14796`); 626 of 1401 Phis. *Sound in shape.* 20 trivial and 101 unread Phis are left in. The `eval` join's memory Phi has one input.
- **Aliasing.** A pre-scan moves address-taken, captured, call-passed and shared lexicals into memory (`_address_taken`, `1508-1795`). Every sub call is a barrier (`5762`). Of 30 probes, 26 were right, 4 refused, 0 wrong. *Sound.* It is a trigger list, so a miss would be silent; none was found.
- **Package scalars.** These are Click-shaped, except in loops. In `probes/p/pg1.pl`, `17 Phi [3,19] Int region=6` carries `$g` as a value past `25 Call ... bump`. The producer's own comment at `8183` says a written package scalar is never value-forwarded; `8199` makes the loop exception. The reason recorded at `10068` (a memory read in the loop names the pre-loop version) predates loop memory Phis. *Defect.*
- **`local`.** Restores are stores placed at listed exits (`13280`). Of 16 probes, 8 were right, 4 refused, 4 wrong.
- **I/O, `die`, `exit`.** There is one control chain; all 573 `Print`s are on it. *Sound.* It matches libFIRM and the VSDG, not Click's separate I/O chain. What is off the chain is the problem (`Divide`, `printf`, the builtins above).

**Cost.**
- Classes W1 to W6 and W10.
- 16 of T2's 342 refusal messages name a B::SoN ordering gap.
- `Assign::is_placed` (`Node/Assign.pm:35`) and `Lower.pm:59-78` detect floating list assigns after the fact, for aggregates only.
- T2's `reads_before` / `hash_reads_settled` (`Builder/Variables.pm:235`, `:23`) re-implement Click's "loads before the store that replaces their version" by flushing.

### 2.2 Loops

**Theory.**
- Click: a loop Region with a back edge, Phis on it, and an `If` for the test.
- Braun: incomplete Phis completed when the header is sealed, trivial ones removed, one linear pass, and memory can be one more variable.
- SSA book chapter 8: a Phi at the exit for each value leaving the loop.

**What we do** (`probes/w/l1.pl`):
```
 3 Loop   [0] ^0            header; one input, the way in; no back edge
 4 Phi    [2,40] memory     memory round the loop
 8 Phi    [7,10] Int        $i round the loop
35 NumLt  [8,34] ^3         the test: a value pinned to the Loop; no If
 6 Proj [3] index=0  body       5 Proj [3] index=1  way out
39 Region [36,38]           latch: `next` and the body's end
19 Region [5,18]            exit: header's way out, then each `last`; exit Phis for $i and memory
```
- **`Loop` is Region and If fused.** The back-edge control is absent: `Loop::set_backedge_ctrl` (`Node/Loop.pm:53`) is never called. The test is "whatever is pinned to the Loop", and chalk finds it by elimination (`Builder/Control.pm:815-826`).
- **Construction is neither Braun nor Cytron.** It is op-tree structural with a scout: walk the body once with placeholders to find changed slots (`13987`), make Phis for those (`14116`), walk again, and refuse a write the scout missed (`13960`).
- **The scout doubles the work per nesting level:**

  | depth | 1 | 8 | 10 | 12 | 14 |
  |---|---|---|---|---|---|
  | seconds | 0.17 | 0.49 | 1.44 | 4.88 | 20.0 |

- **Refused by name:** `redo`, backward `goto`, some `do {} while`, loop control inside `eval`. Irreducible flow is never built.
- **T2 lowers structurally** (`Control.pm:828-935`): pinned nodes in chain order, floating values at first use.

**Results.** Of 36 loop, modifier and `goto` probes, 29 were right, 7 refused, 0 wrong.

**Verdict.** The representation is debatable but sound for what it accepts. The construction is sound and costly. The loop-related wrong answers are W1 and `local`.

### 2.3 Calls

**Theory.**
- Click: a call takes and returns control, STORE and I/O, split by Projections.
- libFIRM table 1: `Call: B x args x M -> results x M`. The paper's table has no exception output.
- Zadeck: a call defines every external variable.
- Click: a faulting instruction keeps a control input.
- Kelsey: closures are explicit environments, and non-local exits need explicit control edges.

**What we do.**
- **Shape.** `Call [args] ^ctl` with `dispatch_kind` (builtin, direct, method, indirect, dynamic_method), `name`, `want`, `class_name`, `shares_args`, `eval_id`, and the site. There is no `Proj`.
- **Sub calls are pinned and made the current memory unconditionally** (`5489`, `5634`, `5762`). Of 30 probes, 25 were right, 4 refused, 1 wrong (`DESTROY`). *Sound.*
- **Exceptions to that:**
  - The dynamic method call is pushed unpinned (`5358-5366`); see W3.
  - The loop-carried package scalar; see W1.
  - Builtins are decided one at a time with no effect table in the producer. chalk has `reads_state` / `changes_state` (`BuiltinTable.pm:165-169`) for another purpose.
- **`@_`.** Arguments are value nodes, and chalk infers aliasing from the kind (`Builder/Calls.pm:681`). Of 22 probes, 10 were right, 8 refused, 1 was a loud stop, 3 wrong (W5 and `@_ = ...`). *Debatable.*
- **Returns.** One `Return` per sub (`4562`): `Return [value]` or `Return [list, scalar]`, with the call's `want` choosing. `wantarray` is refused in a sub. *Sound.*
- **Between subs.** Each sub has its own graph and `MemStart`. chalk emits real functions. Closures are `MakeCell` / `CellParam` / `CellRead` / `CellWrite`, all with memory inputs. *Sound.*
- **Exceptions.** `die` is a terminal `Unwind`. The `eval` join Region has one control input and two-input Phis: all 33 Phi-arity mismatches in the corpus are `eval` joins. chalk tests a dying flag after each call (`Calls.pm:29-44`). Of 18 `eval` probes, 14 were right. With no exceptional edge, `local` restores and the `$@` write have nowhere to stand (chalk refuses a second `$@` read, `Control.pm:292-303`). `Divide` floats. *Defect.*
- **Implicit calls.** `tie` and overloading are refused or partly handled. `DESTROY` is neither modelled nor refused.

### 2.4 Cross-cutting

- **Edges are untyped.** Control is `control_in`, or `inputs[0]` for control nodes. Memory is a positional input by kind (`Subscript` 2, `Count` 1, `PadAccess` 0, `ElemRestore` 4, `Call` last if flagged). libFIRM types its edges.
- **`Proj`** exists only for `If` and `Loop`; `Start` and `Call` have none.
- **Identity.** Pure nodes are hash-consed. Ten statement-effect kinds and four allocation kinds are fresh per use (`NodeFactory.pm:238-241`, `257`); that list is the producer's only statement of which kinds have effects. `control_in` is "not part of content" (`Node.pm:25-31`), yet hash-consed reads are pinned (`Subscript` 177 times, `PostfixDeref` 99). The factory special-cases it (`NodeFactory.pm:549-559`).
- **Typing by use.** Not redone here (see [the sigil investigation](../../plans/2026-11-19-sigil-stamp-investigation.md)). Its bearing: a stamp guess (`_is_aggregate_node`, `FromOptree.pm:390`) decides whether a list assignment is pinned (`11927-11975`). SSA book chapter 11: a fact learned at a use belongs on a new name starting there.
- **The wire lacks:**
  - memory inputs on writes, calls and `Return`;
  - per-kind effect signatures;
  - a control input for the exceptional way into an `eval` join and for faults;
  - the loop back edge and its `If`;
  - place versus value.
- **We have what the theory says to avoid:**
  - records that look like writes;
  - multi-role nodes;
  - optional trailing inputs that change a node's meaning;
  - value-numbered reads of changeable state;
  - faulting nodes without control;
  - one variable in two representations.

## 3. Departures table

"Wire" means the wire format changes and needs perigrin's approval.

| # | departure | evidence | verdict | cost | recommendation | who |
|---|---|---|---|---|---|---|
| 1 | one chain, no slices | `StackSim.pm:13-17` | sound | none | keep | none |
| 2 | node-as-version, no Store/Load | `probes/w/a1.pl` | sound | none | keep | none |
| 3 | `Assign` and sub `Call` take no memory input | table in 2.1 | debatable | no local invariant | name the memory edge | wire |
| 4 | `Return` takes no memory | 1084 of 1084 | debatable | liveness only via control | add it | wire |
| 5 | writes pinned by hand; list assign by kind list | `FromOptree.pm:11831` | defect | W2; chalk's `Control.pm:926` | one store constructor; pin by where the target lives | producer |
| 6 | records that look like stores | 120 in corpus | defect | blocks checking | flag them | wire |
| 7 | reads with no version (`RefType`, `blessed`, flattened package aggregate) | `probes/p/ef9.pl`, `probes/q/nv1.pl` | defect | W4, W10 | every read of memory takes memory | wire |
| 8 | package scalar as a loop value Phi | `FromOptree.pm:8199` | defect | W1 | read through memory | producer |
| 9 | effects riding value edges | census | defect | W3, `bless`; refusals | effect table; pin in every context | producer |
| 10 | pinned reads are versions | `memcheck.pl` | debatable | `is_pinned` questions | fine once edges are named | wire |
| 11 | one node, three roles; no `Proj` | `Builder.pm:259-308` | debatable | positional guessing | named edges; `Proj` not needed | wire |
| 12 | no verifier | `TypedInvariant.pm:297` | defect | found only by wrong answers | verify the wire itself | both |
| 13 | `local` restore on listed exits only | `probes/p/lo2.pl`, `lo3.pl` | defect | W6 | restore on every edge out | producer, then wire |
| 14 | single control chain for I/O | 573 of 573 | sound | none | keep | none |
| 15 | `Loop` = Region + If; test by elimination | `Control.pm:815` | debatable | a heuristic | explicit `If` | wire |
| 16 | no back-edge control | `Loop.pm:53` unused | debatable | no generic CFG walk | add it | wire |
| 17 | scout double walk | `FromOptree.pm:13987` | sound, costly | time doubles per level | Braun's incomplete Phis | producer |
| 18 | `redo`, backward `goto` refused | `probes/p/lp8.pl`, `lp26.pl` | sound | refusals | falls out of 17 | producer |
| 19 | sub call is always a barrier | `FromOptree.pm:5762` | sound | none | keep | none |
| 20 | dynamic method call not pinned | `FromOptree.pm:5362` | defect | W3 | pin and barrier | producer |
| 21 | arguments are values | `Calls.pm:681` | debatable | W5 | writable arguments are places | wire |
| 22 | `eval` join without a catch edge | 33 Phis | defect | `local`, `$@` | add the edge | wire |
| 23 | `Divide` / `Modulo` float | `probes/p/fl1.pl` | defect | 2 probes | pin when the divisor may be zero | producer and chalk |
| 24 | pinned unread may-die read skipped | `Control.pm:132` | defect | `fl5` | make it for its effect | chalk |
| 25 | `die` of a reference stringified | `Control.pm:167` | defect | 5 probes | keep the value | chalk |
| 26 | `DESTROY` not modelled or refused | `probes/p/ca29.pl` | defect | 2 probes | refuse | chalk |
| 27 | pinned hash-consed nodes | `NodeFactory.pm:549` | debatable | one loader bug | never hash-cons a pinned node | producer |
| 28 | type guess decides pinning | `FromOptree.pm:11927` | defect | part of 5 | decide by sigil and storage | producer |
| 29 | autovivifying read is not a write | `probes/p/fl11.pl` | defect | 1 probe | a may-vivify read is a version | producer |

## 5. Recommended direction, in order of work

Keep one chain and node-as-version. Make the rule mechanical.

1. **chalk only, now: refuse what floats.** In the loader, before unreachable nodes are dropped, refuse a wire with an effectful node that has no `control_in` and is not a record or parameter bind. This turns W2, W3 and the `bless` cases into refusals. Add the stopgaps:
   - extend the `Lower.pm:59-78` guard to every memory target;
   - refuse a loop value Phi of a package scalar when the loop holds a sub call;
   - refuse a program that defines `DESTROY`;
   - make a pinned unread may-die read;
   - keep a `die`'s value.
2. **Producer, no wire change: a wire verifier and a ratchet.** `tools/census.pl` and `tools/memcheck.pl` are prototypes. Run it over the corpus, perl `t/`, and chalk's lib.
3. **Producer, no format change: delete the loop exception for package scalars** (`8199`, `10068`) and read them through the header memory Phi. Fixes W1. chalk will then refuse some shapes ("a package scalar read of no one version") and needs lowering for them.
4. **Producer, no format change: one constructor for every memory-touching node.** It does `set_control_in`, `set_control` and `set_memory` together. List assignment decides by where each target lives (the sigil investigation's option C, producer half). Pin the dynamic method call. Add a builtin effect table and pin by it in every context. Pin a `Divide` that may fault; this is wire content, not format, and chalk needs a matching arm. Fixes W2, W3, part of W4, and `fl1`.
5. **Wire v2 (perigrin's approval): named edges.**
   - Each node carries `control_in`, a new `mem_in`, and `inputs` for values only.
   - `mem_in` is set on every version and every read of memory, including `RefType`, `blessed` and a flattened aggregate.
   - `Return` gets `mem_in`.
   - Record `Assign`s get a flag.
   - Retire the `memory_input` flag and the two-or-three-input `Subscript`.

   The invariant then becomes a short walk back from `Return.mem_in`. `Phi::is_memory`, `is_placed` and `_use_counts` shrink. Fixes W4 and W10 at the root.
6. **Wire (perigrin's approval): the exceptional edge.** Give the `eval` Region a second control input from a catch point. Emit `local` restores and the `$@` store on it. Fixes W6's die cases.
7. **Wire (perigrin's approval) and producer: loops.** Add the back-edge input and an explicit `If` for the test. Replace the scout with Braun's construction, which also makes `redo` and backward `goto` ordinary edges and removes the doubling.
8. **Later, unchanged plan:** places as nodes (`@_` aliasing, W5), then slices and Array SSA with escape analysis.

Lessons worth recording in `docs/memory`:
- a loop-carried package scalar is a value Phi a call cannot reach;
- a read of changeable state with no memory input is merged across the write;
- an effect riding a value edge runs at first use;
- the corpus census reads zero because floating writes live in the library code it loads;
- a checker over the loaded graph cannot see what the loader dropped.

## 6. What was not checked

- `SoN::Deparse` (the other consumer), gate3, the chalk-lib round trip, perl's `t/`.
- The `class` feature (fields, methods, ADJUST), regex graphs, sort comparators as callees, string eval, formats, signatures, BEGIN/END, use/require following, `tie` and overloading beyond one probe each.
- chalk's `Analysis.pm` (4125 lines), intervals, `ReferenceFlow`, and the loader's passes beyond their headers.
- The 70 unexplained ordering disagreements in the chalk-lib sample (31 involve `LocalAlias`).
- Whether `_address_taken` misses a trigger. 30 probes found none; that is not proof.
- External-state reads (`time`, `-e`, `rand`): wire evidence only, because chalk refuses the programs that would show them.
- Whether each W6 case is already in the memory notes. Notes on `local` exist, but not these shapes.
- Theory: quotes were verified in the primary texts for Click (both papers), libFIRM, Cytron, Zadeck 1986, Braun, and the book's VSDG section. Pizlo, Kelsey, Briggs and the rest of the book are from the summaries. The HSSA chapter is absent from our copy.
- Probes are small file-scope programs run once each; a fix to any class should re-run all of `probes/p/` and `probes/q/`.

Risk to know: finding 1 is in everyday code and the corpus cannot see it, and the floating list assign of finding 2 is in chalk's own `Builder/Control.pm`, so a self-compile through T2 would silently drop those stores.
