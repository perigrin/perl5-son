# Design B, approved by perigrin 2026-11-25: places everywhere, promotion a separate pass

Heads: producer `/home/user/repo` `wip/chalk-lib-roundtrip` f06ba3e (branch `places-everywhere`), chalk `/home/perigrin/dev/chalk` `bson/llvm-corpus` eca706af (branch `places-everywhere`). Follows the third final audit (`docs/research/2026-11-25-memory-model-final-audit-3.md`, classes N1-N8, N10-N12, design risks 1, 3, 6, 7, 8), design 1 (`docs/plans/2026-11-24-aliases-as-places.md`) and baseline sections 25 and 27. Scope widened by perigrin during the work: K2 (`local` under an alias) and the N8 `local` forms are in, with the two-level model of section 4.

## 1. The problem

Design 1 made an alias a place, but the walk decides, as it builds each node, whether the alias is "proved private" and may be a plain value. The proofs are optree scans keyed on how a store is spelled (`ModSets::arg_stored_by_call`, `call_stores_through_args`, `stores_invocant`, `args_may_be_places`, `_reread_alias_operand_stored_later`, `_elem_alias_plan`, the K5/K7 refusals). Audit 3 found 101 of its 146 wrong answers one spelling past such a scan: `tr///` where `=` was listed, a method call where a direct one was, a slice where an array was. A fast path inside construction is as wide as the spellings it lists.

## 2. The model

Clang emits an `alloca` for every local and LLVM's mem2reg/SROA promote the ones whose address does not escape. Construction is naive; promotion is a separate pass with its own proof.

**Construction (FromOptree) is naive and always correct.** Every SV perl hands on by alias is a place or a read made where perl reads it:

| perl aliases | construction emits |
|---|---|
| a sub's or a method's argument (`f($x)`, `$o->m($g)`, the invocant) | the argument's place, always (`fields.place`), for a `my` scalar (demoted, as today), a package scalar, an element, a field, a captured cell, an assignment's target, `substr` (new, 3.1), `$#a` (new, 3.1) |
| `@_` in the callee (`$_[N]`, `shift`, `my (...) = @_`) | a read of `$_[N]` at the version where it stands, never a record |
| a foreach / map / grep item | an alias list of places: each scalar item its place, each aggregate item the aggregate (aliased per element by the consumer), a slice / `values` / `reverse` / `grep` result as an alias list (3.1); the iterator read at the version where each read stands |
| an operand perl pushes as an SV (`$x`, `$a[0]`, `$$r`, `($a[0] = 5)`, `++$x`) | read at the version current when its consumer runs, not where its op stands |
| `my $i; for $i (...)` | the loop's own scalar: the outer slot is neither read nor written by the loop (3.3) |

**Promotion (`SoN::Promote`) is a separate pass over the built wire**, in B::SoN, after the walk and before the JSON text is written (section 5). It rewrites a place or a late read into the earlier value only where its proof holds over the wire, and marks each rewrite `fields.promoted` so that the verifier re-checks it. `SON_NO_PROMOTE=1` skips the pass: the wire is the naive one, and every probe must give perl's answer both ways.

What stays in the walk: which `my` variables live in memory (the pre-scan's demotion, `_address_taken`). A variable that is not in memory has no place to promote from, so its demotion is a representation decision made before the walk, not an alias proof. The pre-scan demotes on syntax only (an argument, an alias-list item, `\`, a capture), never on a proof that the alias is private.

## 3. Wire changes (WIRE, approved)

### 3.1 New place kinds

`fields.place` (design 1) gains:

| node | place of | chalk lowers to |
|---|---|---|
| `Substr [string place, offset, length] place` | `substr($s, o, l)` as an lvalue | a substr lvalue `%Slot` (a new runtime tag): a read reads the substring of the string now, a write splices |
| `LastIndex [array] place` | `$#a` as an lvalue | a `$#a` lvalue `%Slot` (new tag): a read is the length - 1, a write sets the length |
| `Slice [..., source] place` | an array or hash slice as alias-list items or arguments | each element's alias (`ASliceAlias`, `HSliceAlias`, which exist) |
| `HashValues [hash] place` | `values %h` in an alias list | an alias of each value |
| an alias list (`ArrayLiteral`, no symbol) as an item of an alias list | `reverse` / `grep` / `?:` results over places | the items' aliases, flattened |

A package scalar's place carries `mem_in`: it is the scalar the name is bound to at that version (section 4). L10 changes accordingly: a place has no `control_in` or `mem_out`; it has `mem_in` only if it is a package scalar's.

### 3.2 `fields.promoted`

On a node the pass made from a place or a late read: the proof the verifier checks (section 6). Absent from every node of a `SON_NO_PROMOTE=1` wire.

### 3.3 The foreach over an outer `my`

`my $i; for $i (LIST)`: perl gives the loop its own scalar, aliased to each item, and puts the outer scalar back after. The walk binds the slot to the item for the body's reads (as for `for my $i`), and makes no store to the outer slot. A closure, a named sub or a reference made outside the loop reads the outer scalar. No new node.

## 4. A place is the scalar, not the name; `local` (the two-level model)

1. **Two levels.** In the package environment a name holds a *binding*: a reference to a scalar (or container). The scalar holds the value. Reading `$x` by name loads the binding at a version, then the scalar's value. An alias (`$_[N]`, a foreach/map/grep item, a method argument) and `\$x` hold the SCALAR, taken from the binding when they are made, never the name.
2. **`local $x = 2`:**
   ```
   old = load-binding $x          (at a version)
   new = new-scalar
   store-binding $x := new
   store new := 2
   ```
   On every way out -- the normal exit, `next`/`last`/`return`, the B1 rethrow edge and the eval catch -- `store-binding $x := old`. `local $x;` stores undef. A `local` under `if` or `and` restores on the path it ran on only (a Phi of `old` and the binding the other path has).

   For `local $h{k}` / `local $a[i]` the same shape on the element slot; restoring puts the old value back if the key existed and deletes it if it did not.
3. **On the wire** (no new op kinds):
   - `EntryDef $x mem_in=V` (a read) is both loads at V. `EntryWrite [EntryDef $x, v]` stores into the scalar bound then.
   - `Ref [EntryDef $x] mem_in=V` (`\$x`) and `EntryDef $x place mem_in=V` are the scalar bound at V.
   - `local`: the save is `Ref [EntryDef $x]` at the version before the `local`; `EntryWrite fields.local` is new-scalar + store-binding + store; `EntryWrite fields.restore [EntryDef $x, saved Ref]` is store-binding := the saved scalar. Elements: `ElemRestore` (exists) with the saved existence.
4. **Promotion, two levels.**
   - *Binding level.* With no call, eval, die, string eval or symbolic reference between the `local` and a use, load-binding folds to the known scalar; a name no `local` or glob assignment anywhere in the wire rebinds is always its program scalar (chalk's static global, today's lowering). The pass marks the fold; the verifier checks no store-binding of that name in between (a rebind anywhere in the wire, for the program scalar).
   - *Value level.* If that scalar is never aliased or referenced, its value may be an SSA value. Not built in this branch: package scalars are not carried (as today), so there is nothing to fold yet.
5. **Chalk.** A scalar is a heap cell, like `MakeCell`. A binding is a package-table slot holding a cell pointer, so `local` is a pointer swap. A name no `local` rebinds keeps its static global, which the binding initially points at.

Probe for the model: `our $x = 1; sub f { local $x = 2; print "$_[0]\n" } f($x)` prints 1; with `g()` reading `$x` inside `f` first, `g` prints 2 (the new scalar, through the name) and `$_[0]` still 1.

## 5. Where the pass lives

In B::SoN, `SoN::Promote::promote($data)` on the wire data `SoN::Serialize::JSON::to_json` builds, before it is encoded. Reasons:

- the verifier (`SoN::Verify`) reads exactly this form; the pass and the rule that checks it share one representation, and the pass's predicate is the verifier's;
- every consumer (chalk, the deparser through `as_v1`) gets one wire, unchanged in kind;
- the proofs need every graph of the program (callees, their transitive stores), which exist only once the walk has finished.

No reason found for the pass to live in chalk T1: every proof is over the wire alone.

## 6. The promotions and their proofs

Each is a rewrite plus a check. `SoN::Verify` runs the check on every node marked `promoted` (rule V14, `promoted-not-private`); the pass is not trusted.

| | rewrite | proof (over the wire) |
|---|---|---|
| P1 call argument | a place input of a sub `Call` -> a read of its source at the Call's `mem_in` | every callee is known (`direct` by name; `method`: every sub of that name); none, closed over its calls, stores the source before it reads `@_` at that position (V12's walk); none stores through `$_[N]`, takes a reference into `@_`, hands `@_` on whole, or calls code the wire cannot see |
| P2 callee copy of `@_` | `my (...) = @_`'s per-element reads -> the parameter record | no call in the wire hands this sub a place, it may not be called by code the wire cannot see (`fields.called_unknown` on its graph, from the pre-scan), and it stores no element of `@_` |
| P3 late operand | a read made at its consumer's version (an element's guarded by its existence where perl pushed it) -> the read where perl pushed it | no store on the memory chain between the two versions may store its source (a call by its callees' stores, closed; one not known stores everything) |
| P4 alias-list item | a per-use read of the iterator's element -> the read at the pass's header version | V12's list half: no store in the pass, before the use, may reach the item |
| P5 binding | section 4.4 | section 4.4 |

A place that fails its proof stays a place; a late read stays late. The pass counts each kind (held / promoted) for `tools/alias-fastpath.pl`.

**Mutation tests** (`t/wire-verify-rejects-hand-broken-wires.t`): for each of P1-P5 a wire whose `promoted` node has a store to its source in between must fail V14 by name; its unbroken form must pass.

## 7. Refusals deleted

Each is replaced by a lowering above; each removal is checked by its probes with promotion on and off.

| refusal | replaced by |
|---|---|
| `a variable handed to a sub as its $_[N] where that sub localizes it` (K2) | section 4 |
| `an assignment's element is read by alias and a later operand stores into its container` (K5) | P3: read at its consumer |
| `an aggregate flattened into a list is read by alias and a later item may store into its elements` (K7) | P3 / an alias list |
| `an element operand is read by alias and a later operand stores into its container` / `... calls a sub that may store into it ...` / `... calls code whose stores cannot be known here ...` | P3 |
| `a scalar operand is read by alias and a later operand stores it` (and `... through a reference`) | P3 |
| `a slice perl's alias may make elements of` | a `Slice` place |
| `a written iterator over a list a call returns` | an alias list of the call's places where perl's are (grep, reverse); a copy where perl's are copies (map, sort, a sub's return) |
| the `ModSets` alias proofs inside the walk (`arg_stored_by_call`, `call_stores_through_args` for the place decision, `stores_invocant`, `args_may_be_places`, `arg_localized_by_call`) | P1, P2 |

## 8. What stays refused, and why

- A string eval, `*x = \$y`, or a symbolic reference that may rebind a name an alias holds: the wire cannot see the rebind (the existing GAPs stay).
- `local` on an element an element alias reaches (`f($h{k})` with `local $h{k}` in `f`): chalk's element alias is (aggregate, key), not the element's scalar; until elements are cells (section 4 for elements), refused by name. `local $h{k}` with no alias over it is lowered (restore by existence).
- A place through a `?:` whose arms need a real If (design 3's list), and a `?:` target of a list assignment: a Phi of places is not on the wire.
- Each refusal left at the end of the branch is listed in the report with its probe.

## 9. Probes and gates

- New probes in `docs/research/son-ir-audit-2026-11-19/probes/pe/`, and in chalk as `t/data/audit-probes/pe<name>.pl`: one per place kind (argument of each source kind, method argument, invocant, `$_[N]` copies, alias-list items of each kind, slices, `values`, `reverse`, `grep`, `substr`, `$#a`, operands of each kind, the outer `my` iterator) and the `local` set (`pk*`: the coordinator's six, local in a loop, nested, a die caught outside, a closure across a local, `\$x` across a local).
- Each is run with promotion on and with `SON_NO_PROMOTE=1`.
- Done: every audit-3 WRONG in N1-N8, N10-N12 prints perl's answer or is refused by name with its reason, both ways; the gates pass (held by name 0, census >= 426, corpus >= 222, WRONG 0, SAME lost 0); promotion rates measured on chalk's lib wires against the old fast path (call 2.9%, list 19.2%, iter 0.7% failed proofs).

## 10. As built (branch `places-everywhere`)

What differs from sections 3-8, and why:

- **P1 is the one promotion built** (`SoN::Promote`, `SoN::AliasProof`, V14 `promoted-not-private`, mutation cases M18-M23). Construction passes every argument perl aliases as a place (`$ARGS_ARE_PLACES` is always 1); the walk's `arg_stored_by_call` / `call_stores_through_args` / `stores_invocant` place decision is gone. The proof is over the wire: the callee set by name, each callee's stores closed over its calls (a call the wire cannot see stores everything), stores classified by what the wire says they store (`EntryWrite`, `Assign` targets, `CellWrite` of a cell, a builtin version's container, a store through a reference by class), and `@_` handed on, referenced or stored through is never private.
- **@_ copies (P2)**: construction makes `my (...) = @_` the per-element read at its version (N1), left untyped (B::SoN does not floor it, as a parameter is not). `SoN::Promote` rewrites it to the parameter record (`Assign record [targets, ArgsSource]`) where no call on the wire hands the sub a place (after P1), no code the wire cannot see calls it (`%CALLED_UNKNOWN`), the sub neither hands `@_` on nor stores through it, and the reads are at its start with indices 0..n-1. V14 re-proves each (M24).
- **Operands (P3) need no promotion.** An SV operand is read at the memory version (or binding) current when its consumer runs; where nothing was stored between, that is the read already made (the same node), so there is nothing to fold. An element is guarded by whether it existed where it was pushed.
- **Alias lists (P4)**: an array item of a foreach/map/grep list is its place (each element aliased by the consumer); a written iterator is the element as before. No per-use iterator promotion was built: the per-pass read already names the pass's version.
- **Binding level (P5)**: a name no `local` binds is its static global (chalk decides from the wire: an `EntryWrite` with `local` on the name anywhere). A bound name is read through `bind::NAME`. No in-scope fold was built.
- **Wire for `local`**: `EntryWrite fields.local` (the new scalar, then the assignment's own store), the save `Ref [EntryDef]` at the version before it, the restore `EntryWrite fields.binds [EntryDef, Ref]` -- the shape `local *v` and `local @a` already had. Perl's punctuation variables keep the value save and restore.
- **Not built, refused by name** (each with its probe): a place of a package scalar at an older version than its call (`f($g, local $g = 5)`, `print $g, local $g = 5`); an element localized under an alias (z/qb05); a `local` in an arm of its own statement; `delete local`; `substr` / `$#a` as an alias where it may be stored (no magic-lvalue place); `reverse`/`sort`/`grep`/`?:` results as alias-list items or list operands where a later item or the body may store into them (decided by the MOD sets; no alias list of a call's result on the wire); a slice of non-constant indices in the same position; a list assignment as the target of a list assignment; a capture read in a loop of a match made before it where the loop matches; a package scalar with two names or tied at CHECK (`use English`, `use Env`, an imported scalar).
- **`values %h` as an alias list** is lowered: chalk aliases each value (`HSliceAlias(h, HKeys h)`), so it is not refused.
- **Element reads an operand's later call may store**: the existence test is made and pinned where perl pushed the element (an element that did not exist was pushed as undef), and the element read again when its consumer runs. A `Range` or `Call` result is a temporary list: no guard.
- **grep's result element** is the element as the body left it (read after the body where the body may store), since grep returns the element itself.
- **`\$g` of a name some `local` binds** is `Ref [EntryDef at the version]`: the scalar bound when the reference is made (pk03, pk04, pk10 print perl's answer through the deparser; chalk refuses them by name, "a scalar deref where a reference T2 does not make may reach it" -- T2 would need to make the reference where it is taken, not at its first use).
- **The topic aliased to an element** (`for (@a) { ... $_ ... }`) is read again at its use after a store since the pass bound it (pa09: a silent wrong V12 caught).
- **AliasProof's store model** (shared by the pass and V14): an element at a constant index is its own source; `push`/`unshift` leave the elements an alias holds, a `pop`, `shift`, `splice`, `$#a =` or whole assign frees them (perl reads undef or panics through `@_`) and so stores them; a `local` binds a new scalar and a store by the name after it, on one chain, stores the new one; a `my` no reference reaches and no closure captures is beyond code the wire cannot see. V12 leaves promoted arguments to V14.
- **Element operands a later call may reshape or cannot be seen into** are refused by name again (`_elem_alias_refused`, ModSets), as before the operand rewrite.
