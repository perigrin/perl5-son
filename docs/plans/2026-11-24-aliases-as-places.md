# Designs 1 and 3 -- approved by perigrin 2026-11-24: aliases are places on the wire; an assignment or `?:` as an lvalue

# Aliases as places (design 1), assignment and `?:` as lvalues (design 3)

Heads: producer `/home/user/repo` `wip/chalk-lib-roundtrip` 9afe7f0 (branch `alias-places`), chalk `/home/perigrin/dev/chalk` `bson/llvm-corpus` add5ce17 (branch `alias-places`). Follows the final audit (`docs/research/2026-11-24-memory-model-final-audit.md`, section 4 item 1, and item 3 for design 3).

---

## Design 1: an alias is a place

### The problem

Perl has four aliases:
- `$_[N]` in a sub;
- the foreach variable;
- `$_` in `map` and `grep`;
- a method's invocant (`$_[0]`).

Each one IS the variable or element it names. The wire carries an alias as a value: a read of the source at the version where the alias is bound. That is right only while nothing else touches the source during the alias's life. Patches cover the common cases:
- `@_` copy-in, with copy-out of `$_[N]` written by the callee (chalk's alias `@_` array);
- a foreach iterator's write stored where it stands (`$store_at_write`, `ON_DEFINE`);
- a demoted iterator's pass-end write-back, plus a store after each call that was passed it (`%AFTER_CALL_PASSING`).

What the patches miss is refused by name. These are the final audit's classes (chalk `t/data/audit-probes`, `fa` + the `f/` name):

| class | refusal | probes |
|---|---|---|
| C | `a variable passed to a sub that stores it by name and reads its arguments` | 19: faa30 faa32 fah01-08 fah10 fah12 fah13 fah15-20 |
| E | `a package scalar aliased by a foreach, map or grep` | 15: faj02-04 faj07-10 faj19 faj20 faj22-24 fal25, ree30 req12 |
| E | `an element perl's alias may make exist` | 8: faa67 faj16-18 faj25 faj27 faj28, lw25 |
| G | `a foreach iterator written in a pass a die may leave` | 13: fae25 fan04 fan05 fan10 fan13 fan14 fan16-19 fan21-23 |
| H | `a method that stores $_[0]` | 5: fao14 fap02 fap03 fap07 fap11 |

Class G is a bug in a rule already made: "the alias write is a store where it stands" (2430ead). Writes that `$store_at_write` does not see fall back to the pass-end write-back:
- an op-assign on a demoted iterator (`$x .= "!"`), which stores the slot;
- a write through `\$x`;
- a callee's `$_[0]` write.

A die passes that write-back by.

### The model

1. **A place** is storage, not a value. It is either a name in an environment or an element of a container:
   - a name: a package variable (`EntryDef`), a `my` variable kept in memory (`PadAccess`), a field (`FieldAccess`);
   - an element: `Subscript`.

   Chalk keeps package and lexical names in separate environments: no globs, no pad slots. An alias is bound to a place.
2. **A read through an alias is a memory read** at a named version (`mem_in`). **A write through it is a store**, which makes a new version. Inside a sub, `$_[N]` is already a read at a version (`Subscript [ArgsSource, N] mem_in`). In a loop, the per-pass read of the list is too.
3. **Fast path.** The producer passes a plain value instead of a place only where it PROVES the alias private: nothing else can read or write the source between the bind and the alias's last use. A body that may die is not private for an alias that is written, because a die would expose a half-done write-back. So a written alias is always a place, and the write-back goes.
4. **Checked.** `SoN::Verify` checks that an alias carried as a value has no other write to its source between the source's version and its use (rule V12). Chalk's loader (`WireInvariant`) checks the structural half (rule L10).
5. **Chalk** lowers a place to a pointer to the variable's storage. That is the runtime's alias `@_` array, an `SRef`, or an element alias (`t2_elv`), all of which exist today. A variable that may be aliased lives in memory, as a captured variable does (`MakeCell`) and as a demoted `my` scalar does (an alloca `%Slot`).

### Wire change (WIRE, approved)

**`fields.place: true`** on an access node: `PadAccess` (a `$` variable kept in memory), `EntryDef` (`$`), `Subscript`, or `FieldAccess` (`$`).
- The node names storage. It has no `mem_in`, `control_in` or `mem_out`.
- Hash-consing keeps it apart from a read of the same variable, because `fields` are content.
- It may be used only where perl binds an alias:
  - an input of a sub `Call` (`direct`, `method`, `indirect`, `dynamic_method`), the invocant included;
  - an item of an **alias list**: an `ArrayLiteral` with no `symbol` that a foreach, `map` or `grep` walks.
- A `Subscript` place also carries **`fields.vivify: true`** where perl's binder makes the element exist: a foreach, `map` or `grep` item, or an element of a slice passed to a call. Perl's deferred element (`f($a[9])`) does not. This is a Perl fact, so the producer states it. Chalk does not guess it.

**An alias carried as a value** is any other node in those positions: a read with `mem_in`, a constant, a computed value. It means the producer proved the alias private, or perl's alias is of a temporary.

Before this change, an argument was always a value. The access node with no `mem_in` that v2 section 3.3 called "an argument a sub call may alias" is now said, not inferred.

Section 3.3 of `docs/plans/2026-11-20-wire-v2.md` gains one row:

| node | `control_in` | `mem_in` | `mem_out` |
|---|---|---|---|
| an access node with `place` | no | no | no |

Nothing else on the wire changes:
- A read through an alias is the node kind it already is: `$_[N]` in the callee, `Subscript [list, i]` per pass in a loop, `$_` as `EntryDef` under `LocalAlias`.
- A store through it is an `Assign` to the same `Subscript`.
- A foreach over a named aggregate already reads each pass's element at that pass's version. Its iterator becomes the element itself, never a copy in a slot (below).

### What the producer does

**Calls (classes C, H; and design 3's `inc($x += 1)`).**
- At each sub call, the producer asks the privacy question already written as `ModSets::arg_stored_by_call`: does a sub the call reaches store the argument's variable by name and then read `@_`? For a method's invocant, it asks `ModSets::stores_invocant`.
- Where the alias is not private, the argument is a `place`. A `my` scalar so passed is demoted, so it lives in memory (`$ADDR_TAKEN`, as `\$x` demotes it). Every later read of it is a versioned read after the call.
- The two GAPs go: `a variable passed to a sub that stores it by name and reads its arguments` and `a method that stores $_[0]`.

**Alias lists (class E).**
- A foreach, `map` or `grep` over a list of items builds its `ArrayLiteral` from places for each package scalar, demoted `my` scalar and element. Each element place carries `vivify`.
- The per-pass read is a memory read through the alias. A write is an `Assign` to that same `Subscript`.
- `_alias_list_gap` and `_element_is_there` go.

**The foreach iterator (class G).**
- A demoted iterator is no longer a copy in its pad slot. While the pass runs, `$x` IS the element `Subscript [list, i]`: a read of it reads the element at the current version, and a store to it (op-assign, `TARGMY`, `\$x`, a callee's `$_[0]`) stores the element.
- So every write is a store where it happens, and nothing is left to write back. These go:
  - the pass-end write-back (`if ($demoted_iter && !$writes_iter ...)`);
  - `%AFTER_CALL_PASSING` and its `$after_call`;
  - the slot store in `$store_at_write`;
  - the per-pass `Assign [iter_slot, elem]`;
  - `_iterator_written_unstored` and the GAP `a foreach iterator written in a pass a die may leave`.
- No write-back is copied onto `Exc` edges.
- A form that cannot yet be a store is refused by name, never written back.

**The fast path.** A value is kept where:
- `arg_stored_by_call` is false;
- the invocant is not stored;
- an alias list's item is not written in the body and nothing in the body may write its source (`ModSets` over the body).

The producer counts each decision. `tools/alias-fastpath.pl` reports them over chalk's lib wires.

### The proof rule (verifier V12, `alias-not-private`)

V12 applies to an alias carried as a value whose source is named: a read with `mem_in` of a package scalar, a `my` scalar in memory, a field, or an element of a named aggregate. It must hold:

- **As a sub `Call` input:** in each callee the wire holds (`direct`: by name; `method`: every sub of that name; any other kind: none, so the rule is not checked), take every read of `@_` at that position (`Subscript [ArgsSource, N]`, a `shift`, a list assign from `ArgsSource`). Walk the memory chain back from the read's `mem_in` to the callee's `MemStart`. It must meet no store whose target names the source. It must also meet no sub call, unless that call's own callees, closed transitively over the wire, store no such name.
- **As an alias-list item:** for each use of a per-pass `Subscript [list, i]` read, walk the memory chain back from the use to the item's own version. It must meet no store to the source other than one through the list itself.

The walk crosses memory Phis by every input, and it stops at a version it has already seen.

**Mutation test.** `t/wire-verify-rejects-hand-broken-wires.t` gains two hand-broken wires:
- C's `my $x=1; sub f { $x=2; $_[0] } f($x)` with the place changed back into a read (`mem_in` set, `place` dropped);
- an alias list whose item is a read the body stores by name.

Each must fail V12 by name. Their unbroken versions must pass.

**Loader (chalk `WireInvariant`, L10, structural half).** A node with `fields.place` has no `mem_in`, `control_in` or `mem_out`. Its op is `PadAccess`, `EntryDef`, `Subscript` or `FieldAccess`. Every consumer is a sub `Call` or an `ArrayLiteral` with no `symbol`. `fields.vivify` appears only on a `Subscript` place.

### What chalk does

- **`arg_alias` / `alias_list`** (`Builder/Calls.pm`) already lower a place to a pointer:
  - `SRef(location)` for a `my` variable in memory;
  - `SRef(GAddr)` for a package scalar;
  - `ElvA` / `ElvH` (`t2_elv`) for an element.
  
  A `vivify` place makes its element exist first. That is the runtime's existing store path for an absent element.
- **A callee passed a place anywhere in the program** takes `@_` as the array of aliases (the "list" convention that a callee writing `$_[N]` uses today). Its `$_[N]`, `shift` and `my (...) = @_` read through it at their versions. The positional value binding stays for callees that are never passed a place: that is the fast path.
- **An alias list with a place among its items** is built by `args_array`, with each item aliased. The per-pass `Subscript` reads through it (`t2_alias_aget`), and an `Assign` to it stores through it (`t2_alias_aset`).
- **A method's invocant place** is the first alias of the method call's `@_`, which `MCall` already builds by `args_array`.

### Patches deleted

| where | what | replaced by |
|---|---|---|
| producer `_handle_entersub` | GAP `... stores it by name and reads its arguments` | a place argument |
| producer `_handle_entersub` | GAP `a method that stores $_[0]` | a place invocant |
| producer `_alias_list_gap`, `_element_is_there` | GAPs `a package scalar aliased by ...`, `an element perl's alias may make exist` | place items, `vivify` |
| producer foreach walker | per-pass slot store, `$store_at_write`'s slot store, `%AFTER_CALL_PASSING`, the pass-end write-back, `_iterator_written_unstored` and its GAP | the iterator is the element's place |
| chalk `Builder/Args.pm` | the positional bind of a callee whose arguments some call passes as places | `@_` as aliases |

The `foreach` over `@_` write GAP and the iterator-reference GAPs are not this design's patches. Each one is rechecked once the iterator is a place, and lifted only if its probe prints perl's answer.

### Prior art

- **LLVM `alloca` + mem2reg / SROA.** Every variable starts in memory. mem2reg promotes it to SSA when its address does not escape. Here a variable stays an SSA value unless it may be aliased (the fast path), and is demoted to memory when not. The proof is our "private" test, as mem2reg's is "address not taken".
- **MemorySSA.** A read through an alias is a MemoryUse at a MemoryDef. V12 is a clobber query: is there a clobbering def between the use and the def its value came from?
- **HHVM boxed refs** (`RefData`). A PHP variable bound by reference is boxed, and every access goes through the box. That is a place that lowers to a pointer to the variable's storage.
- **C2 memory slices.** Alias classes split the one heap so that a store to `$x` would not version `$y`. They are left for later: precision, not soundness.

### Class G after design 1

With the iterator a place, a die leaves the element already written. A G probe left refused must name a form that is not yet a store. The report lists what remains.

---

## Design 3: an assignment or `?:` as an lvalue (class D, 14 probes)

Probes: f/b47 s13 i01 i03 i05 i07 i09 i10 i11 i14 i19 i20 i21 i24. Today each is refused: `a ?: / an assignment used as the target of ...`.

- **An assignment as a target** (`($x += 2) *= 3`, `(my $t = $a[0]) *= 10`, `($x = 5) += 2`, `my $y = (($x += 2) *= 3)`):
  1. Lower the inner assignment.
  2. The outer op's target is the inner op's target, the same variable or element.
  3. The outer op reads it at the inner store's version: the current binding, or its memory.
  
  No new node. The value of the whole expression is the outer store's value.
- **`?:` as a target** of `=`, an op-assign, `++` or `--` (`($c ? $a : $b) = 9`, `($c ? $a : $b)++`):
  1. Compute the right side first, in perl's order: sassign runs its right side before its left.
  2. Branch on the condition, with the same store into each arm's variable: `if ($c) { $a = V } else { $b = V }`.
  3. The expression's value is a Phi of the arms' values. For a postfix `++`, that is the old value.
  
  No pointer at run time.
- **An assignment passed as an argument** (`inc($x += 1)`): after the inner store, `$_[0]` is `$x`'s place (design 1).
- **Refused by name:** a nested `?:` as a target, an arm that is not a variable or an element of a named aggregate (an element through a reference, a slice, a call), and a `?:` target of a list assignment. A Phi of places would be a wire change, and that needs perigrin again.

---

## Probes and gates

- New probes for each shape go in `docs/research/son-ir-audit-2026-11-19/probes/al/`, and in chalk as `t/data/audit-probes/al<name>.pl`. Each one is compared against perl.
- Done means:
  - every C, D, E, G and H refusal above prints perl's answer, or stays refused by name with a reason;
  - the gates pass: held by name 0, census at least 426, corpus at least 222, WRONG 0, SAME lost 0;
  - the fast path's proof failures are measured on chalk's lib wires.
