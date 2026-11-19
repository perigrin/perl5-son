# Sigil vs stamp: why `my @a` arrives typed `Scalar`

Read-only investigation, 2026-11-19. Producer `/home/user/repo` (wip/chalk-lib-roundtrip), consumer
`/home/perigrin/dev/chalk` at c1a48dfe. Nothing in either repo was changed. Scratch programs, wires and
patched *copies* of the producer are under `/tmp/claude-0/sigil-investigation/` (`q/ r/ s/` probes,
`run.pl` = B::SoN + chalk T2 + lli vs perl, `la.pl` = list-Assign summary, `expA/ expB/` patched libs).
Probes ran with `LLI=/usr/lib/llvm-18/bin/lli` (llvm-15's lli rejects chalk's `ptr`).

## 1. How a PadAccess gets its stamp, and the exact path for `!@a`

Stamping is forward and backward, and a stamp is written once (from `Unknown`, never revised).

- **Construction.** `_make_pad_or_field` (FromOptree.pm:21909-21942) builds every PadAccess unstamped
  on purpose; its comment leaves the sigil floor to `B::SoN::_declared_slot_type`.
- **Forward.** `_resolve_deferred_stamps` (B/SoN.pm:721, loop at 755-763): field reads, callee
  returns, literal subscripts, `_stamp_merges` (1824, join), `_stamp_derived` (1882).
- **Backward.** `_infer_backward` (B/SoN.pm:2042), last. Only PadAccess, FieldAccess and Parameter are
  eligible (`_is_backward_inferable`, 2181). It gathers each consumer's operand requirement from
  TypeLibrary, threads through Coerce, meets them, then writes `meet(declared, required)` (2144-2154).

The path for `my @a; ... if !@a; my $r = \@a`:

1. A scalar-context `padav` becomes `Count(@a, mem)` (FromOptree.pm:7710-7714).
2. `Count => { operands => ['List'] }` (TypeLibrary.pm:131).
3. `_declared_slot_type` (B/SoN.pm:2211-2217) returns **`Scalar` for every PadAccess and never reads
   the sigil**. `meet(Scalar, List) = Scalar`, because Scalar is a child of List (Stamp.pm:12).
4. B/SoN.pm:2154 writes `Scalar` onto the one shared `@a` node.
5. `_derived_type` for `Ref` (B/SoN.pm:1914-1928) answers `ScalarRef` for any operand stamp that is not
   Array/Hash/Code/Glob/Unknown.

Without `!@a` nothing requires anything, so both stay Unknown. No path yields Array. Other uses write
other types on the container: `my %h; my $n = %h; print "n=$n"` stamps the `%h` PadAccess **`Str`**.

PadAccess is the only variable node typed this way. EntryDef `@x`/`%g` is stamped from its sigil at
construction (FromOptree.pm:6723-6728) and by `_floor_package_globals` (B/SoN.pm:1043-1058); a slurpy
Parameter from its sigil (t/aggregate-parameter-stamp.t); a field from its class record
(B/SoN.pm:3593). The recorded reason for leaving PadAccess unstamped ("stamping Scalar pre-empts the
meet") concerns `$` only: nothing sits below Array or Hash in the lattice (Stamp.pm:56-57).

## 2. Is the node shared, and does the wire separate container from read?

Nodes are hash-consed on attributes and inputs, so it depends on the variable's form:

| form | node | sharing |
|---|---|---|
| bare `my @a;` / `my %h;` | `PadAccess` with no inputs | one node for every use in the graph |
| `my @a = (...)` | slot bound to `ArrayLiteral{sigil,symbol}` stamped Array; no PadAccess | one per whole assignment |
| `my $x`, bound | no node; reads are the SSA value | n/a |
| `my $x` in memory (`\$x`, shared) | `PadAccess [mem]` | one per memory version (7572) |
| `our @x` | `EntryDef` stamped Array | one node |

Read nodes exist and carry the memory version the container lacks: `Count [c, mem]`,
`Subscript [c, i, mem]`, `PostfixDeref [c, mem]`, `Call join [sep, c, mem]`. `Ref`, the mutators and
an Assign target take the container itself. The split is not kept everywhere; these hand the
container to a consumer that wants a scalar:

- `if (%h)`, `!%h`, `%h ? :`, `while (%h)`: `If [ctl, PadAccess %h]`. Line 7710 is `padav` only.
- `my $n = %h` on a fresh `my %h`: `$n` is bound to the container.
- `!@x`, `@main::x + 1`: `If [ctl, EntryDef]`, `Coerce(Array->Num)[EntryDef]`. Chalk covers these
  for `%Array*` in `as`/`truth` (Values.pm:1487-1507).

A PadAccess `@a` therefore stands for the place (Assign target), the container (operand of
Count/Ref/push) and, where a read node is missing, the value.

## 3. Inventory

### B::SoN: the stamp used to mean "is an aggregate"

| site (FromOptree.pm) | question | when the stamp is missing or wrong |
|---|---|---|
| `_is_aggregate_node` 390-417 (patched for ArgsSource, Array/Hash, List) | countable aggregate? | every caller below |
| 10270, 10866 (sassign, padsv_store) | count the RHS? | `my %h; my $n = %h` binds `$n` to the hash |
| 11928 `$positional` | bind targets to values by position? | `my (@rest, $f) = (1,2,3)` binds `$f` to Constant 2 |
| 11959, 11975 | pin the Assign? | `my ($f, @rest) = (1,2,3)` floats; `@rest` reads empty |
| 9108, 10693, 10760, 10782, 11432 | flatten / foreach bounds / count | array path not taken |
| 4018, 4400, 4494 (returns) | flatten a returned aggregate | `return %r` of a fresh hash returns the container |
| 11561 `$stamp->type eq $want` | RHS already the aggregate? | wrapped as one element |
| StackSim `_joined_stamp` 229-259; `_is_array_merge` 372-388 | does a merge stay an array | scalar `$phi` merge |
| B/SoN.pm 1917-1918 (Ref kind), 989-1013, 907, 1716 | derived stamps | `ScalarRef` for `\@a` |

Deparse.pm has about 63 more stamp tests of this kind and 15 sigil tests; not classified here.

### B::SoN: already falls back to the sigil or the op

`_is_array_operand` 357-362; `_is_array_merge` 384; `scalar` 6385-6388; `av2arylen` 6446; foreach
10787-10800 and 10802; aggregate-copy pinning 11623, 11716; push/shift 12285, 12334, 12897; 905, 911,
1375, 1402, 14048; `_merged_aggregate_return` 4401; `_is_scalar_rebind_target` 21833 (asks the place,
by sigil); EntryDef 6713-6728; `_floor_package_globals`.

### Chalk

- **Loader** (Serialize/JSON.pm): 716-723 memory-form `$` PadAccess Unknown -> Scalar; 728-732 `@`/`%`
  PadAccess stamped Unknown or Scalar -> Array/Hash (misses `Str`, the `my $n = %h` case); 743-747 and
  753-757 (e2eccbc5) `Ref` of a PadAccess -> by sigil.
- **T1** BackwardInference.pm:71: the same `_declared_slot_type` = Scalar. Analysis.pm:3407, 3509 read
  PadAccess stamps to choose boxing.
- **T2** already decides a `my` array by sigil (`PadAccess::is_my_array`, Node/PadAccess.pm:74;
  Lower.pm:70; Variables.pm:497). It depends on the stamp at 71 sites marked `# static type`, mostly to
  tell an ArrayLiteral stamped Array from one stamped ArrayRef. `truth` has no hash arm.

## 4. What the conflation reaches (perl output is the oracle)

| program | chalk | cause |
|---|---|---|
| `my %h; print "e" if !%h`; `if (%h)`; `%h ? :`; `unless %h`; after `delete`; `our %g` | wrong (7 probes) | `If` on the container; chalk `truth` has no hash arm |
| `my %h; my $n = %h` (also after `$h{a}=1`) | `n=HASH(0x..)` | stamp test at 10270/10866; container then stamped Str |
| `my %h=(a=>1,b=>2); my $n = %h`, `scalar(%h)`, `keys %h` | right | literal stamped Hash; `scalar`/`keys` ask the op |
| `our %g; my $n = %g` | prints nothing | wire is right (`Count[EntryDef %]`); chalk stops at run time: "an array element read through no ARRAY reference" |
| `@a + 1`, `scalar(@a)`, `$#a`, `"n" . @a`, `"@a"`, `@a ? :`, `while (@a)`, `our @x` forms | right | Count exists, or chalk counts `%Array*` |
| `sub f { my %r; return %r }`, scalar call | refused | container returned as a value |
| `wantarray` | refused by name | unrelated |

### List assignment

No node stands for the LHS. `pop_to_mark` gives a Perl list of target nodes (11410), spliced into
`Assign inputs => [@lhs, @rhs], targets => N` (11810). A lone aggregate target takes another path
(11471-11760) and usually makes no Assign at all. Arity and storage are re-derived from the targets.

The coordinator's three cases are confirmed. `my @a=(0); my $c; ($a[0], $c) = (5,6)` yields
`Assign#19 [Subscript, PadAccess $c, 5, 6] targets=2` with no `control_in` and no consumer; the later
read is `Subscript [a, 0, MemStart]`; `$c` is Constant 6. Cause: the pin list at 11831-11840 names node
kinds (in a loop, address-taken PadAccess, PostfixDeref, FieldAccess), then `$positional` (11927) is
true because no target is an aggregate by stamp, and the loop at 11937 rebinds only `$` pad/package
targets. The SSA half is done, the memory half is a dead node.

| target | placed | chalk |
|---|---|---|
| bound `my $x` | no, rebound | right |
| `our $p`, `local $_` | no, `_entry_store` stores separately | right |
| address-taken `my $x` | yes, memory version | right |
| `$$r`, class field | yes, memory version | refused |
| `$a[i]`, `$h{k}`, `$o->[0]` (Subscript) | **no** | **wrong**: `0 6`, ` 10`, `0`, `5 ` (5 probes) |
| captured `$x` (MakeCell) | **no** | **wrong**: `1 8` |
| bare `my @r`/`my %h`, `our @g` | no, except one-call RHS, loop, shared | refused |
| `my (@rest, $f)` | n/a | `$f` bound to Constant 2 on the wire (perl: undef); chalk refuses |

The comment at 11862 ("a Subscript target ... was already right") does not hold on the wire.
docs/memory/a-list-assign-into-an-aggregate-is-placed-or-refused.md already records the floating
shapes and a 6-line scratch fix for the aggregate targets; the element and cell cases are new.

## 5. Design options

**A. The sigil is the declared type.** Tried two ways in scratch copies:
- `expA`: `_declared_slot_type` reads the sigil. Fixes the reported symptom (`@a` Array, `\@a`
  ArrayRef). An unused variable is still Unknown, so list assignment and `my $n = %h` are unchanged.
- `expB`: one line in `_make_pad_or_field` stamps `@`/`%` at construction, as EntryDef and Parameter
  are. Also makes `my $n = %h` a Count and stops the wrong bind in `my (@rest, $f)`; 3 of 46 chalk
  probes move from wrong/refused to right, none worse. Producer suite: 722 of 724 files pass; 8 tests
  fail in t/deparse-a-foreach-over-an-unproven-list-refuses-what-reaches-it.t (7) and
  t/deparse-a-foreach-what-perl-does-per-pass.t (1). The 7 are refusals that no longer fire: foreach
  took the unstamped branch (10787, `$UNPROVEN_LIST = 1`) because the stamp was absent, so "unstamped"
  was doubling as "array kept in memory".
- Deletes: chalk loader 728-732 and 753-757, and the sigil arms in `_is_array_operand`, `scalar`,
  `av2arylen`, foreach, `_joined_stamp`. Leaves hash truth and all list-assign storage as they are.

**B. Container and read are different nodes, enforced.** Containers (PadAccess/EntryDef/FieldAccess
`@`/`%`, slurpy Parameter, named literal) are typed by sigil and never inferred; inference types reads
only. Every scalar use goes through a read node: Count for arrays and hashes (padhv gets 7710's
rule; EntryDef gets Count, not Coerce/If). A verifier can state it: only Count, Subscript,
PostfixDeref, Ref, the mutators, a list flatten and an Assign target may take a container.
`_is_aggregate_node` splits into its two real questions: "is this operand a container" (kind + sigil)
and "does this value flatten or have unknown arity" (stamp List, a call's `want`). Chalk gains hash
truth with no work, loses the loader overrides, and needs a hash arm in Count (package hashes).

**C. The LHS is a typed list of places.** One node, or a `places` field on Assign, carrying two
independent facts per element, read at construction:
- arity, from the sigil/op: a `$` place takes one, `@`/`%` takes the rest, `undef` skips one;
- storage, from the binding: SSA (bound `my $x`) or memory (element, cell, package, address-taken,
  field, any aggregate).
Then one rule each: values distribute by position up to the first rest-place or first unsized value;
any memory place puts the Assign on the chain as the memory version; SSA places are rebound. That
replaces the kind list at 11831 and the three `_is_aggregate_node` tests at 11928-11975, and makes
chalk's `is_placed` true by construction.

*Place vs container.* Two kinds, not three: a place is where a store lands, typed by sigil; a value
is what a read at a version yields, typed by inference. For `@`/`%` the place is the container. For
`$` the place is the slot, and today's `$x` PadAccess is both Assign target and by-name read, the same
conflation in the scalar spine. `Ref` takes a place.

**Recommendation.** B is the root fix and C is its statement for assignment; A is B's first step.
Order: expB's line plus an explicit "kept in memory" test where foreach relied on the missing stamp;
then the two missing read nodes (nine hash wrong answers); then C, since the six dropped stores are a
storage decision no stamp change touches.

## Uncertain

- expB was measured on the producer suite and 46 probes only. No census, gate3 or corpus-through-LLVM
  run (those tests skipped here: no SON_CHALK). Other places may also read "unstamped" as a signal.
- Deparse.pm's stamp tests are unclassified.
- Whether `$` PadAccess should split into place and read is argued, not tested.
- Probes are small file-scope programs; loops, subs and closures are thinly sampled.
- CLAUDE.local.md asks for new lessons in docs/memory; the task was read-only, so none were written.
  It also names skills `ponytail` and `i-have-adhd`, which are not installed in this session.
