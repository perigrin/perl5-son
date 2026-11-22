# The B::SoN IR and its wire format, as built for Chalk

This document describes the Sea-of-Nodes IR that B::SoN builds and the JSON
wire format chalk consumes. It is for anyone building a different producer
of that IR, such as a Perl parser.

It was compiled on 2026-10-29 from perl5-son `c018c89` and chalk
`bson/llvm-corpus` `fcaa7224` (census pin: corpus_llvm ROUNDTRIP 354/430).
Quotes are verbatim, with `file:line`, as of those commits. The line numbers
will drift, but the quoted text is the anchor.

Repos:
- **Producer:** perl5-son (this repo).
- **Consumer:** chalk, `lib/Chalk/IR/Serialize/JSON.pm` and onward.

## 0. Summary

- **"BSON" is not binary JSON.** In both repos "bson" is shorthand for
  **B::SoN**, the producer. Chalk's branch `bson/llvm-corpus` is where its
  LLVM backend work for B::SoN's corpus lands
  (`tools/corpus-llvm-roundtrip.pl`: *"chalk's bson/llvm-corpus branch,
  where the backend work for this census lands"*). Neither repo uses a
  BSON encoder.
- **The wire is pretty-printed, canonical, UTF-8 JSON.** There is one
  document per compiled file, written to stdout by
  `perl -MO=SoN,json file.pl`. The top-level keys are:
  - `version`: 2 (wire v2, `docs/plans/2026-11-20-wire-v2.md`); chalk's loader
    refuses any other by name;
  - `profile`: the parts of v2 the wire obeys, `["mem", "eval"]` (the
    migration's; `loop` follows);
  - `source`: always null;
  - `methods`: one graph per sub;
  - optionally `classes`, `data_section` and `phase_blocks`;
  - `dowarn`: perl's warning switches for the run, `{on, all_on, all_off}`
    (-w or a compile-time `$^W`, -W, -X), each a boolean (2026-11-15).
- **Each graph is a flat array of nodes in topological order.** A node's
  id is its index in that array. A node is
  `{id, op, inputs:[idx…], fields?:{…}, stamp?, control_in?, mem_in?, mem_out?, head?}`.
  `inputs` are values; `mem_in` names the memory version a node reads or
  follows, `mem_out` says it is one. The only forward reference the loader
  allows is a loop Phi's back edge.
- **A non-perl producer only has to emit this JSON.** Chalk's loader never
  sees perl internals. It does enforce a set of invariants (§3.2):
  ordering, required sigils, op names it knows, stamps that are lattice
  names, the memory invariant (L1-L6: every memory edge names a version
  listed before it, every version reached from a Return or Unwind, every
  Assign a record or on both chains), and a `main::__PROGRAM__` graph with a
  Return.
- **Chalk already has an Earley front end** that builds this same IR
  directly (`lib/Chalk/Bootstrap/Earley.pm`,
  `lib/Chalk/Bootstrap/Perl/Actions.pm`). Chalk's Phase 4 brief calls it
  "untrusted, paused" in favour of B::SoN (§3.4).

---

## 1. The IR

### 1.1 The base node, and the value/control split

`lib/SoN/IR/Node.pm` (producer), mirrored by chalk's `lib/Chalk/IR/Node.pm`:

```perl
# Node.pm:9-30
    field $id :param :reader;                 # Stable content-based ID for the node
    field $inputs :param :reader = [];        # Producer nodes
    field $consumers :reader = [];            # Consumer nodes (mutable)
    field $stamp        :param :reader = undef;
    field $compat_class :param :reader = undef;
    # Effect-chain predecessor when this node appears as a statement-position
    # side effect (bare Call, bare Assign, etc.). ... Not part of content_hash:
    # side-effect vs pure-data uses of the same content (e.g. `foo()` as statement
    # vs as expression) should still hash-cons to the same node; control_in is a
    # per-use decoration.
    field $control_in :reader = undef;
```

`content_hash` defaults to `join('|', operation, input ids…)`. Subclasses
add the fields that carry identity.

`lib/SoN/IR/Value.pm`:

> THE SPLIT IS NOT ON THE WIRE, AND MUST NOT BE. The serialized form carries
> `op`, and both sides map that name to a class independently. Value-ness is
> therefore DERIVED identically at both ends from data already present. …
>
> THE STAMP IS REQUIRED, AND `Unknown` IS THE WAY TO SAY "UNKNOWN". A Value
> node exists to define a value, and a value has a type, so an undef stamp is
> not a state a Value node may be in.
>
> ORTHOGONAL TO EFFECTS. Value-ness and control-reachability are independent
> axes. Assign and CompoundAssign carry effects AND produce values …

### 1.2 Node kinds

There are 105 classes in `lib/SoN/IR/Node/*.pm`, and chalk has the same
names. In the table, **bold** fields are the ones `_extract_fields`
serializes (§2.4). The rest are internal to the producer.

| Op | Parent | Fields (wire-visible in **bold**) |
|---|---|---|
| **Control** | | |
| Start | Node | — |
| Return | Node | **implicit**, **valueless**, synthetic. Inputs `[value, scalar_value?]`; control comes from `control_in`. |
| Unwind (die) | Node | **eval_id**, **file**, **line**. Inputs `[exception args…]`. |
| If | Node | region (internal). Inputs `[control, condition]`. |
| Proj | Node | **index**. Inputs `[If or Loop]`. |
| Region | Node | `head` (a top-level wire key), **eval_entry**, **eval_want**, **eval_may_die**, **eval_id**. Inputs `[pred control…]`. |
| Loop | Node | **bound** (`each` or `entry`). Inputs `[entry_ctrl]`. |
| PackageMark | Node | **package** |
| MemStart | Node | — (the initial memory state) |
| **Merge** | | |
| Phi | Value | **region** (node index), **predecessors** (node indices), **memory** (bool) |
| **Constants and variables** | | |
| Constant | Value | **const_type** (`integer`, `number`, `string`, `undef`, `boolean`, `regex`, `code`, `glob`), **value** (always a string or null), **flags** |
| PadAccess | Access | **sigil**, **symbol**, **shared**. `targ` is internal and deliberately not on the wire. |
| EntryDef (a package variable) | Access | **package**, **sigil** (required), **symbol** |
| EntryWrite | Value | **binds**. Inputs `[entry, value, memory]`. Never hash-consed. |
| Parameter | Access | **index**, **name**, **sigil**, **default_when** (`absent`, `undef` or `false`) |
| ArgsSource (`@_`) | Access | — |
| VarDecl | Node | **scope** |
| ListAssign | Node | scope |
| FieldAccess | Access | **field_index**, **field_stash** |
| CellParam | Access | **index**, **name** |
| CellRead | Access | — |
| CellWrite | Value | write_id |
| MakeCell | Value | **cell_name**, **captured_written** |
| AnonSub | Value | **name** (the `methods` key of its body), **captures** |
| LocalAlias | Value | **name** |
| ElemRestore | Value | **kind**, **at_return** |
| Wantarray | Access | — |
| EnvRead | Value | **key** |
| **Aggregates** | | |
| ArrayLiteral, HashLiteral | Aggregate | **sigil**, **symbol**, **rebinds** |
| Interpolate | Aggregate | — |
| Slice | Aggregate | **index_count**, **kind** |
| Subscript | Access | **kind**, **stash_has** |
| Exists, Delete | Access/Value | **kind**; **stash_has** (Exists) |
| Count | Access | **presence_test** |
| PostfixDeref | Value | **sigil**, **copy**; **file**, **line**, **eval_id**, **strict**, **package** where it may die |
| ListAppend (map, grep) | Value | **collector** |
| ExpressionList, StructRef, StructFieldAccess, BacktickExpr | Value | — |
| TernaryExpr | Value | **rebind_arm** |
| **Calls and effects** | | |
| Call | Value | **dispatch_kind** (`builtin`, `direct`, `method`, `dynamic_method`, `indirect`), **name**, **want**, **class_name**, **param_names**, **shares_args**, **string_eval**, **eval_id**, **external**, **sort_cmp**, **sort_order**, **sort_cmp_body**, **sort_package**. Internal only: paren_form, target, resolved_graph. |
| Print | Node | **has_filehandle** |
| Assign | BinOp | **targets**, **if_changed**, **local** |
| CompoundAssign | Value | **op** |
| TryCatch | Node | — |
| **Regexes and strings** | | |
| Regex, RegexMatch | Value | **pattern**, **flags** |
| RegexSubst | Regex | **pattern**, **replacement**, **flags**, **pattern_is_input**, **replacement_body** |
| RegexSubstCount, TransliterateCount | UnaryOp | — |
| RegexCapture | Value | **n** |
| Match, NotMatch | BinOp | **flags** (Match) |
| Transliterate | Value | **from**, **to**, **flags** |
| Chomp, ChompValue | Value | **kind** |
| Length | UnaryOp | **bytes** |
| Coerce | Value | **from_repr**, **to_repr** |
| **Binary ops** (BinOp: left, right) | | Add, Subtract, Multiply, Divide (**eval_id**, **file**, **line**), Modulo (same three), Power, Concat, Repeat, NumEq, NumNe, NumLt, NumGt, NumLe, NumGe, NumCmp, StrEq, StrNe, StrLt, StrGt, StrLe, StrGe, StrCmp, And, Or, Xor, DefinedOr, BitAnd/BitOr/BitXor (**flavor**), LeftShift, RightShift, Range, IsaOp, Yada |
| **Unary ops** (UnaryOp: operand) | | Not, Negate, Complement (**flavor**), Defined, UnaryPlus, Increment, Ref (**each**, **fresh_each_pass**, **file**, **line**), RefType, Length |

### 1.3 Control flow

There are no basic blocks. Control is carried by CFG nodes and by a
`control_in` edge on each statement-position effect.

- **Start and Return.** `Return.pm`: *"inputs[0] is the return value,
  inputs[1] the scalar reading of a list return; the control predecessor
  lives in control_in."* On why there are two:

  > A perl sub is compiled once and cannot see its caller's context, so a
  > list-returning sub carries both faces: value() is every value flattened,
  > and this is what a scalar-context callsite takes. Which one applies is the
  > calling Call node's `want`.

- **If, Proj and Region.** `If.pm`: *"CFG nodes carry their control input
  in inputs[0] (convention), not in the base $control_in field."*
  - An If's inputs are `[control, cond]`.
  - Its two Projs have `index 0` (then) and `index 1` (else).
  - A Region's inputs are each arm's **last control node**. That is the
    Proj only when the arm has no effects.
  - The Region's `head` names the If or Loop it closes.
- **Which predecessor each Phi input arrives from.** `Phi.pm`:

  > WHICH PREDECESSOR EACH INCOMING VALUE ARRIVES FROM. inputs[i] pairs with
  > predecessors[i]. … A Region's control input cannot answer this: it is the
  > arm's LAST CONTROL NODE, which is the arm's Proj only when the arm is
  > empty of effects. … OPTIONAL: a loop Phi pairs with the loop's entry and
  > back edges rather than a predecessor list, so absent reads as "not
  > recorded".

- **Loops.**
  - A Loop's inputs are `[entry_ctrl]`.
  - `Proj index 0` is the loop body. `Proj index 1` is the exit, which
    feeds a Region whose `head` is the Loop.
  - The loop condition is a value node whose `control_in` is the Loop.
  - Loop Phis are `Phi{region: Loop}` with inputs `[init, backedge]`. The
    back edge is a forward reference.

  `docs/plans/2026-09-28-loop-control-is-an-edge.md`:

  > THERE IS NO CONTROL BACK EDGE. `Loop::set_backedge_ctrl` is never
  > called; the Loop's inputs are `[entry]` and the back edge exists only on
  > Phis.

  As built: *"`next LABEL` is an edge sim, merged into the named loop's
  body state at its latch … The merge Region's head is the Loop; that is
  how the renderer tells a latch from an if's merge. No new wire field."*

- **Loop bound.** `Loop.pm`:

  > WHEN THE LOOP'S BOUND IS EVALUATED: 'entry' or 'each'. … A foreach
  > evaluates its endpoints ONCE … A `while` and a C-style `for` run their
  > condition every pass. A CONSUMER CANNOT DERIVE THIS. … hoisting the bound
  > to a temporary is CORRECT for 'entry' and a non-terminating loop for
  > 'each'.

- **Statement effects** are threaded by `control_in` in source order:
  Start → effect → … → Return. Which ops count as statement effects is a
  shared table in `NodeFactory.pm`:

  > Statement-effect ops: ops whose occurrences are distinct side effects …
  > control_in is excluded from the content hash, so hash-consing these would
  > collapse two textually-identical effects into one node … This table is a
  > SHARED contract: make() gives these ops per-call identity, the Block
  > control-chain fixup in Actions.pm threads exactly this set via
  > set_control_in, and the LLVM backend's chain/branch collectors read it.
  > Keep it the single source.
  >
  > `our %STATEMENT_EFFECT_OPS = map { $_ => 1 } qw( Assign CompoundAssign
  > RegexSubst TryCatch Call RegexMatch Match NotMatch BacktickExpr Print );`

- **Block eval.** The eval's join Region carries `eval_entry`, the control
  node after which the protected body begins (`docs/wire-region-eval-entry.md`):
  *"The body is everything on the control chain strictly between
  `eval_entry` and the Region itself."* Each die in the body is an Unwind
  with the same `eval_id`. A Call or a may-die Divide/Modulo in the body
  carries `eval_id` too.
- **The exceptional edge** (`eval` profile, 2026-11-22; the plan's 3.5).
  Each node in an eval's body that may die -- an Unwind, a sub call, a
  may-fault Divide/Modulo, a read pinned because it may die -- has its way
  out: an `Exc` (a control node, `inputs: [T]`, its value the exception in
  flight). On it stand the restores of the `local`s the eval made that are
  live at T, innermost first, threaded from the memory after T (T itself
  when it is a version). The edges merge at a **catch Region**
  (`fields.catch`, `eval_id`), with a memory Phi and a Phi of the Excs where
  there is more than one; `$@` is stored there from it (an EntryWrite).
  The join Region takes the body's end (where `$@ = ""` is stored: perl
  clears it there; a body that ends in a die has no such way in), each
  `return`, and the catch's end, and its Phis have one input per way in. A
  try and a string eval (known or run-time) are traps of the same shape. A
  die where no eval of its graph is open puts the `local`s live there back
  first: their restores stand on the chain immediately before the Unwind.
- **String eval of code known when B::SoN runs** (2026-11-16, perigrin's
  design): a block eval whose body is one direct Call, `string_eval: true`,
  of the body B::SoN compiled from the string. The string is known when it
  is a constant, or a `my` lexical whose one store is `my $c = CONSTANT`
  made before the eval in a block around it, that nothing else stores,
  refers to, closes over or evals. B::SoN compiles it, in the eval's
  package and with its `$^H`/`%^H`, as an anonymous sub inside a sub that
  declares each lexical in scope at the eval; the names it closes over are
  matched to the program's slots in scope there. The body is a `methods`
  key named `main::__PROGRAM__::__EVAL__:LINE:N` (N: the eval's number
  among the program's), and an AnonSub of that name in the program holds
  the cells of the lexicals it names (`captures`, as a closure's); a read
  after the eval goes through the cell. Shape:

  ```
  MakeCell($i) ... EntryWrite($@ = "") -> Call(direct, string_eval, eval_id=K)
     -> EntryWrite($@ = "") -> Region([that, catch's end], eval_entry, eval_id=K) ; Phi(memory) ; Phi([Call, undef]) (unless void)
  Call -> Exc -> Region(catch) -> EntryWrite($@ = Exc)
  AnonSub([cells], name=__EVAL__:LINE:N, captures)
  ```

  So it means `eval { (sub { STRING })->() }`: the last statement's value
  in the eval's context, a `return` leaving the eval, a die setting `$@`
  and the eval undef, success clearing `$@`. Where that would differ,
  B::SoN refuses by name (a GAP that skips the program): a string that
  does not compile (perl sets `$@` as the eval runs, naming "(eval N)", a
  count of evals run); a die whose message names its place, a warn,
  caller, `__FILE__` and its kin, or warnings on (each names "(eval N)");
  `@_`; `use integer`; code that runs as it compiles (BEGIN, `use`/`no`,
  `sub`, `package`, `format`); an eval inside a sub, in a loop, in list or
  caller context, or in an s///e replacement naming a lexical; a string
  naming a lexical array, hash, state variable or lexical sub, or a name
  the file declares twice; and any op outside the body's allow-list (ops
  that run straight through and cannot die, a choice, print, and a die of
  one constant message ending in a newline). An eval of code made at run
  time with a lexical in scope stays refused by name ("a string eval of
  code made at run time, with a lexical in scope ($x), can read or write
  it unseen by the graph"); with none in scope it is the Coerce(Str ->
  Code) it was. chalk lowers the call in T2 as a closure's; its fallback
  refuses it by name.

### 1.4 Data flow

Data flow is `inputs[]`, an ordered list of node references. Positions are
meaningful per op; for example Assign is `[targets…, values…]`, with
`targets` giving the split (`docs/memory/assign-targets-are-positional.md`).
An input may be an **array of nodes** (Unwind's exception arguments). On the
wire it is flattened into `inputs`.

Call conventions, from `docs/wire-indirect-call.md`:

```
builtin    name is the perl builtin        inputs are args (+ memory)
direct     name is a `methods` key         inputs are args
method     name is the method              inputs are [invocant, args...]
indirect   name is EMPTY                   inputs are [callee, args...]
```

The fifth kind, `dynamic_method` (`$o->$m(ARGS)`), has an empty name and
inputs `[invocant, method-name value, args...]`.

### 1.5 Effects and memory (memory SSA)

- `MemStart.pm`: *"Initial aggregate-memory value … Has no inputs; the
  memory state at function entry, before any element store."*
- **A memory version is the effect node that produced it:** an Assign,
  Call, EntryWrite, CellWrite, Delete and so on, flagged `mem_out` on the
  wire (and MemStart, and a Phi flagged `memory`). A read that must come
  after a store names that node as its **`mem_in`**; a write, a sub call, a
  Return and an Unwind name the version they follow the same way. In §2.5,
  `PadAccess $x` has `mem_in:2` (MemStart) before the store and `mem_in:5`
  (the Assign) after it.
- **Memory is named, not positional (wire v2).** Until stage 6 of the wire v2
  plan the memory a node read was its trailing input (wire v1), told by
  `Call.memory_input` and a per-kind table. The table survives only in the
  deparser, which reads v2 through `SoN::Wire::as_v1` (stage 11 retires
  both). It was (`lib/SoN/Deparse.pm`):

  ```
  Call         => 1,   # [arg, ..., memory]
  EntryWrite   => 2,   # [slot, value, memory]
  Delete       => 2,   # [container, key, memory]
  ElemRestore  => 4,   # [container, key, saved, existed, memory]
  Exists       => 2,   # [container, key, memory]
  Subscript    => 2,   # [container, index, memory]
  Count        => 1,   # [aggregate, memory]
  PostfixDeref => 1,   # [container, memory]
  EntryDef     => 0,   # [memory] -- ordering only
  PadAccess    => 0,   # [memory] -- ordering only
  FieldAccess  => 0,   # [memory] -- ordering only
  RegexSubst   => 1,
  ```

  `docs/memory/the-memory-table-must-be-scraped.md`: the kinds that take a
  memory input are *"Call, CellRead, CellWrite, Count, Delete, EntryWrite,
  Exists, MakeCell, PostfixDeref, RegexSubst, Subscript, Transliterate."*
- **Memory Phi.** `Phi.pm`:

  > A MERGE OF MEMORY STATES, not of values. Said by the producer that built
  > it: from its inputs alone a consumer cannot tell -- a call is a value and
  > a memory version both, so a loop's memory Phi over calls read as a
  > loop-carried value.

- **EntryWrite.** `EntryWrite.pm`:

  > inputs are [entry, value, memory]. The node becomes the new memory
  > version, so a later EntryDef read -- in this sub, in another sub, or at
  > program level -- observes the write. A PAD SLOT DOES NOT NEED THIS AND A
  > PACKAGE VARIABLE DOES. … NEVER HASH-CONSED, for CellWrite's reason: two
  > writes of the same value to the same variable are two distinct events.

- **Lexicals in memory.** An address-taken or shared lexical is a PadAccess
  whose input is a memory version rather than a VarDecl.
- **Closures** use MakeCell, CellParam, CellRead and CellWrite.
  `AnonSub.captures[N]` pairs with input N, which the body reads as
  `CellParam(index=N)`. A capture is the variable perl closes over -- the
  inner pad entry's `PARENT_PAD_INDEX`, not the first of its name -- and
  `AnonSub.captures`, `MakeCell.cell_name` and `CellParam.name` spell it as
  the making scope does: of two `my $x` there, the second is `$x__2`, as its
  PadAccess is (`my $i = 1; { my $i = 5; sub { $i = 7 } }` writes the inner).
- **A write in place to a merged aggregate** -- push, unshift, splice, shift
  or pop on a value Phi of an array's versions (`@p = ()` in an arm or a loop
  body, merged at the join or the loop's head) -- takes the memory it runs at
  as its `mem_in`, is the memory version after it (`mem_out`), and
  merges at the next join and round the loop's back edge, as one on a `my`
  array does. A count after it reads at it (pvm c140). One onto a merge
  B::SoN cannot tell is an array's is refused (a GAP), never left off the
  chain.
- **Autovivification is spelled.** An element dereferenced for a write --
  a store through it (`$s->{t}{$k} = v`), a push onto its array, a foreach,
  map or grep walking it (`for (@{$h{k}})`), keys or values of it -- is made a
  hash or array first where it is undef: a Subscript read pinned where it
  stands (never hash-consed with another read of it), a fresh ArrayLiteral or
  HashLiteral pinned after it, `DefinedOr(read, fresh)`, and an Assign of that
  into the element; the deref then reads the DefinedOr. Whatever the outer
  container is (a `my` aggregate, one just made, one through a reference an
  argument holds), and in a loop body too. Not through @_ (an element of it is
  the caller's variable) nor a tied container. A `my` scalar known undef
  dereferenced for a write is bound to a fresh one. Left as perl's: a read
  through an undef intermediate (`$x->[0]` makes `$x` an array) and a scalar
  not known undef (`my $x = shift; for (@$x)`).
- **A whole read through a reference may die.** An rvalue `@$x`, `%$x`
  (rv2av/rv2hv with neither OPf_REF nor OPf_MOD: a count, a copy, a list, a
  truth, `"@$x"`) dies of an undef under strict refs ("Can't use an undefined
  value as an ARRAY reference at FILE line N."), of a string under them, of
  another kind of reference; without strict refs an undef reads empty (its
  count undef) and is left undef. Such a PostfixDeref names `file`, `line`,
  `eval_id`, `package` and `strict`, as a scalar deref does, and stands where
  the program reads it (on the control chain, the memory version after it)
  when what it reads through is a scalar's. In an lvalue context (foreach,
  map, grep, keys, values, each, a slice, `$#`, a call's argument) perl makes
  the aggregate and dies of nothing: no site; nor of what is never other
  than the aggregate (a list perl folded to a constant array, a fresh
  `[...]` or `{...}`, a reference just taken).

### 1.6 Source positions

There are **no general spans and no columns.** What does exist:

- **`file` and `line` on Unwind, on a `warn` Call (2026-11-15: the same
  two fields, from the same statement), on a Ref that may die (2026-11-15,
  the same two again: `\$a[$i]` at an index that may be before the start,
  where perl dies "Modification of non-creatable array value attempted,
  subscript -N at FILE line N."), and on Divide/Modulo when they may die.**
  `Divide.pm`: *"ONE THAT MAY DIE (by what may be zero) names the block eval
  whose body made it, and its statement's file and line, which perl's
  message names. Part of its content."* `Unwind.pm` (`set_site`): *"THE FILE
  AND LINE OF ITS STATEMENT: perl's message names them when it does not end
  in a newline ("MSG at FILE line N.")."* Both come from the nearest
  statement boundary (`FromOptree.pm`, `_step`):

  ```perl
  if ($name eq 'nextstate' || $name eq 'dbstate') {
      ... $CURRENT_PACKAGE = $pkg ...; $STMT_LABEL = $op->label;
      $SoN::IR::NodeFactory::SITE = [ $op->file, $op->line ];
  }
  ```

- **Line numbers on subs and methods:**
  `classes.{PKG}.subs.{name}.line` and `classes.{PKG}.method_lines.{name}`.
- **Body names that encode a line:** an anonymous body is named
  `<enclosing>::__ANON__:<line>:<targ>`, and sort-comparator and
  substitution-replacement bodies are tagged `__SORTCMP__` and
  `__SUBSTREPL__`.
- **Labels** are read from statements but not emitted as fields.

### 1.7 Uncertain and unresolved things

**The stamp lattice.** It is in `lib/SoN/IR/Stamp.pm`, mirroring chalk's
canonical `lib/Chalk/Grammar/Perl/TypeLibrary.pm` (*"the CANONICAL lattice
… verified mechanically over all 729 ordered pairs … B::SoN's
SoN::IR::Stamp mirrors this table; the two must not drift"*):

```
Unknown (top root)
├── List ── Scalar ── Undef | Str (── Num ── Int ; ── VString) | Boolean | DualVar
│        │           └ Ref ── Object (── Regex) | ScalarRef (── LValueRef) | ArrayRef | HashRef | CodeRef | GlobRef
│        ├── Void
│        ├── Array
│        └── Hash
├── Code ; Glob ; IO ; Format
None (bottom)
```

`Stamp.pm`: *"None is the identity. That is what lets a recursive function
type from its base case."* Boolean sits under Scalar, not under Str.

**`Unknown` is an answer, not an absence.** `NodeFactory.pm`
`_default_stamp`: *"`Unknown` is the fallback because it is an ANSWER, not
an absence: a real lattice member with defined join/meet … it is what a
Subscript or a Call honestly is at construction time."* Operator result
types come from `B::SoN::TypeLibrary::result_for`, a *"deliberate mirror of
chalk's TypeLibrary, keyed by IR op name"*. Sub metadata
(`B/SoN.pm`, `_record_sub`): *"`Unknown` when the value carries no stamp
yet … NOT omitted: an absent field is not a type, and it forces every
consumer to invent a meaning."*

**Coerce** makes every representation change an explicit edge, with
`from_repr` and `to_repr`.

**GAP refusals.** A translator refuses with `die "GAP: …\n"`. B::SoN catches
that per graph, **skips the graph**, and warns on stderr (`B/SoN.pm`,
`_discover_and_translate`):

```perl
if ($e =~ /^GAP:/) {
    warn "B::SoN: skipped main::__PROGRAM__: $e";
} else {
    warn "B::SoN: INTERNAL ERROR translating main::__PROGRAM__ (masked as "
       . "a silent skip -- fix or convert to a clean GAP): $e";
}
```

A skipped graph is **absent from `methods`**, with no marker in the JSON.
The refusal appears only on stderr. Other rules:
- *"a named-but-absent methods key is a dangling reference for the
  consumer"*;
- *"AN ANON BODY NOTHING NAMES MUST NOT SHIP."*

Chalk raises its own `GAP:` refusals while loading and lowering. Its census
sorts each case into ROUNDTRIP, DIFFERS, LLI_FAIL, GAP, LOAD_FAIL or NOJSON
(`tools/corpus-llvm-roundtrip.pl`).

---

## 2. The wire

### 2.1 Encoding and direction

- **Encoding:** `JSON::PP->new->canonical->pretty->utf8`. The output is UTF-8
  with sorted keys. Flag fields are JSON booleans. Every Constant `value` is
  a **string** or null.
- **Framing:** one whole JSON document per program, on stdout. There is no
  streaming, length prefix or multi-document framing. Diagnostics go to
  stderr: `syntax OK` (suppressed with `-MO=-q,…`) and
  `B::SoN: skipped …`.
- **Producer:** `perl -MO=SoN,json[,package=NAME][,not_package=PREFIX] file.pl`.
  Chalk's own `to_json` also writes the format, but it emits no `stamp`
  (`t/bootstrap/ir/loader-reproduces-the-wire.t`).
- **Consumer:** chalk's `Chalk::IR::Serialize::JSON::from_json`. This repo
  no longer has a `from_json`.
- **Versioning: `version` is 2, and checked.** B::SoN writes wire v2 only
  (stage 6 of `docs/plans/2026-11-20-wire-v2.md`); `-MO=SoN,json,wire=2`
  names it and changes nothing, any other `wire=` is refused (`B::SoN:
  wire=1: the wire is version 2 (wire v1 is gone)`). Chalk's loader refuses a
  wire of any other version by name (`GAP: wire version 1 is not one chalk
  reads`), and holds a B::SoN wire to the memory invariant before it makes a
  graph. `profile` says which parts of v2 the wire obeys (`mem` and `eval` today);
  the loader refuses a part it does not read yet. Compatibility is still
  kept by pinning a chalk commit (`tools/corpus-llvm-roundtrip.pl`,
  `$COMMIT`). Optional fields are emitted only when set. Adding a field is
  the safe direction (an unknown field is ignorable); adding a KIND is not,
  because chalk's NodeFactory dispatches on kind
  (`docs/plans/2026-09-26-wire-additions-chalk-must-agree.md`).

### 2.2 The serializer (`lib/SoN/Serialize/JSON.pm`)

```perl
# ABOUTME: Serialize SoN::IR::Graph instances (built by B::SoN's FromOptree)
# ABOUTME: to the B::SoN wire JSON format. Provides to_json(\%named_graphs).

sub to_json ($named_graphs, $classes = undef, $data_section = undef,
             $phase_blocks = []) {
    my %methods;
    for my $name (sort keys $named_graphs->%*) {
        $methods{$name} = _serialize_graph($named_graphs->{$name});
    }
    my $data = { version => 2, profile => ['mem'], source => undef, methods => \%methods };
    # The declarative class section (4c): name, parent, fields, method-refs.
    # Chalk's loader replays it through the MOP declare_*/seal API.
    $data->{classes} = _json_booleans($classes) if defined $classes && %$classes;
    # The text after __DATA__ / __END__, verbatim. Absent when the source has none
    $data->{data_section} = $data_section if defined $data_section;
    # The program's BEGIN and END blocks, in source order, each a graph like a
    # method's. Kept out of `methods` because a method is emitted as a named
    # sub, and these are not callable.
    $data->{phase_blocks} = [ map {
        { phase => $_->[0], _serialize_graph( $_->[1] )->%*,
          ( defined $_->[2] ? ( package => $_->[2] ) : () ) }
    } $phase_blocks->@* ] if $phase_blocks && $phase_blocks->@*;
    return JSON::PP->new->canonical->pretty->utf8->encode($data);
}
```

`B/SoN.pm` calls it as
`print to_json( $graphs, $classes, _data_section(), _phase_blocks() );`.

### 2.3 Document shape

```
{
  "version": 2,                       # checked: chalk reads v2 only
  "profile": ["mem", "eval"],         # the parts of v2 this wire obeys
  "source": null,
  "methods": {                         # graph name -> graph
     "main::__PROGRAM__": GRAPH,       # the file's top level (the entry graph)
     "main::add": GRAPH,               # named subs, fully qualified
     "Pt::dbl": GRAPH,                 # class methods
     "main::__ANON__:<line>:<targ>": GRAPH, "...__SORTCMP__...", "Pt::__DEFAULT_0", ...
  },
  "classes": { PKG: CLASS, ... },      # optional
  "data_section": "text after __DATA__",   # optional
  "phase_blocks": [ { "phase": "BEGIN"|"END", "package": "main", ...GRAPH }, ... ],  # optional
  "dowarn": { "on": BOOL, "all_on": BOOL, "all_off": BOOL }   # -w/$^W, -W, -X
}
GRAPH = { "nodes": [NODE...], "start": <idx>, "returns": [<idx>...] }
NODE  = { "id": <idx == array position>, "op": "<Op>", "inputs": [<idx>...],
          "fields"?: {...}, "stamp"?: "<lattice type>",
          "control_in"?: <idx>, "head"?: <idx (Region only)>,
          "mem_in"?: <idx: the memory version read or followed, listed before>,
          "mem_out"?: true (this node is a memory version) }
```

CLASS, as observed:

```json
{"name":"Pt","parent":null,"is_class":true,"adjusts":[],
 "fields":[{"name":"$x","fieldix":0,"param_name":"x","is_param":true,"is_reader":true,
            "has_default":true,"default_ref":"Pt::__DEFAULT_0","type":"Scalar"}],
 "methods":{"dbl":"Pt::dbl","x":"Pt::x"},
 "method_lines":{"dbl":2},
 "method_signatures":{"dbl":{"invocant":true,"kind":"implicit","mandatory":0,"optional":0,
                             "params":[{"index":0,"name":"@_","sigil":"@"}],"slurpy":"@"}},
 "method_return_types":{"dbl":"Num","x":"Scalar"},
 "subs":{"add":{"name":"add","graph":"main::add","line":1,"uses_args":true,
                "params":["@_"],"signature":{...},"return_type":"Num",
                "prototype"?:"...","lvalue"?:1}}}
```

- A plain package such as `main` gets the same record with `fields:[]` and
  `methods:{}`. A parent defined in another file is marked `external`.
- These boolean keys are JSON booleans: `uses_args is_reader invocant
  has_default is_param is_class`.

### 2.4 `fields` per op (the full serializer list)

- **Constant** `{const_type, value, flags?}`
- **Call** `{dispatch_kind, name, sort_cmp?, sort_order?, sort_cmp_body?,
  sort_package?, want?, shares_args?, string_eval?, eval_id?, external?,
  class_name?, param_names?}` (v1's `memory_input` is gone: a builtin's
  memory is its `mem_in`) -- `string_eval` (true, or
  absent) on the direct call of an eval string's compiled body (§1.3).
- **Ref** `{each?, fresh_each_pass?, file?, line?}`
  Inputs `[operand]`; one to an aggregate's element (`mem_in`: the memory it
  reads) (`\$a[i]`, `\$h{k}`, `\$r->[i]`, `\(@a)`, `\($a[0],
  ...)`): the element at its index where it is taken, read at that memory
  version; pinned on control there and the memory version after it (taking
  it may make the element). A slice's references (`\(@a[0, 1])`) are refused.
  `file` and `line` (its statement's, as an Unwind's) only on one that may
  die: a reference to an array's element at an index not a constant not
  before the start (`\$a[$i]`, `\$a[-5]`). Part of its content, as a
  Divide's site is.
- **BitAnd/BitOr/BitXor/Complement** `{flavor?}`
- **ArrayLiteral/HashLiteral** `{sigil?, symbol?, rebinds?}`
- **AnonSub** `{name?, captures?}`
- **MakeCell** `{cell_name?, captured_written}`
- **CellParam** `{index, name?}`
- **Phi** `{region, predecessors?, memory?, exits?}` -- `exits`: the memory
  Phi where a sub's exits merge, which only its Return names
- **Proj** `{index}`
- **Assign** `{if_changed?, targets?, local?, record?}` -- `record`: a
  binding (of SSA `my` scalars, or of `@_` into `my` aggregates) on neither
  chain, not a store; every other Assign is on both
- **Return** `{implicit?, valueless?}`
- **PackageMark** `{package}`
- **TernaryExpr** `{rebind_arm?}`
- **PadAccess** `{sigil, symbol, shared?}`
- **FieldAccess** `{field_index, field_stash}`
- **Parameter** `{index, name, sigil, default_when?}`
- **EntryWrite** `{binds?}`
- **Loop** `{bound}`
- **EntryDef** `{package, sigil, symbol}`
- **CompoundAssign** `{op}`
- **PostfixDeref** `{sigil, copy?, eval_id?, file?, line?, strict?, package?}` (the site: a `$` deref always, a whole `@`/`%` read where perl may die)
- **Match** `{flags}`
- **RegexMatch** `{pattern, flags}`
- **Print** `{has_filehandle?}`
- **Count** `{presence_test?}`
- **RegexSubst** `{pattern, replacement, flags, pattern_is_input?,
  replacement_body?}`
- **Divide/Modulo** `{eval_id?, file, line}`, only when a line is set
- **Unwind** `{eval_id?, file?, line?}`
- **Region** `{eval_entry, eval_want?, eval_may_die?, eval_id?}`, eval joins
  only; `{catch: true, eval_id}` on an eval's catch
- **Exc** no fields; `inputs: [the node that may die]`
- **Chomp/ChompValue** `{kind}`
- **Transliterate** `{from, to, flags}`
- **ListAppend** `{collector}`
- **Slice** `{index_count?, kind?}`
- **RegexCapture** `{n}`
- **EnvRead** `{key}`
- **VarDecl** `{scope}`
- **Coerce** `{from_repr, to_repr}`
- **Exists/Delete/ElemRestore** `{kind?, stash_has?}`; ElemRestore also `{at_return?}`: made on a way out of the sub (a `return`, or the sub's end), where perl puts the element back by itself, so a deparser spells no block end for it
- **Subscript** `{kind?, stash_has?}`
- **LocalAlias** `{name}`
- **Length** `{bytes?}`

The per-field contracts are in `docs/wire-*.md`: indirect-call, listappend,
regexsubst, region-eval-entry, slice-index-count and transliterate.

The original spec, `docs/plans/2026-04-07-son-json-serialization-design.md`,
is **stale**. It describes a `"cfg": true` key, PadAccess `targ`/`varname`,
and a producer `from_json`. Chalk's loader now ignores `cfg`.

### 2.5 Real output

```perl
sub add { my ($a, $b) = @_; return $a + $b }
my $x = 3;
if ($x > 1) { $x = add($x, 4) } else { $x = 0 }
print "$x\n";
```

`perl -Ilib -MO=-q,SoN,json,not_package=SoN t.pl` produces the following,
shown one node per line with canonical keys:

```
== main::__PROGRAM__ start=0 returns=25
{"id":0,"inputs":[],"op":"Start"}
{"fields":{"const_type":"undef","value":null},"id":1,"inputs":[],"op":"Constant","stamp":"Undef"}
{"id":2,"inputs":[],"op":"MemStart"}
{"fields":{"sigil":"$","symbol":"x"},"id":3,"inputs":[],"mem_in":2,"op":"PadAccess","stamp":"Unknown"}
{"fields":{"const_type":"integer","value":"3"},"id":4,"inputs":[],"op":"Constant","stamp":"Int"}
{"control_in":0,"id":5,"inputs":[3,4],"mem_in":2,"mem_out":true,"op":"Assign","stamp":"Int"}
{"fields":{"sigil":"$","symbol":"x"},"id":6,"inputs":[],"mem_in":5,"op":"PadAccess","stamp":"Num"}
{"fields":{"const_type":"integer","value":"4"},"id":7,"inputs":[],"op":"Constant","stamp":"Int"}
{"fields":{"const_type":"integer","value":"1"},"id":8,"inputs":[],"op":"Constant","stamp":"Int"}
{"id":9,"inputs":[6,8],"op":"NumGt","stamp":"Boolean"}
{"control_in":5,"id":10,"inputs":[5,9],"op":"If"}
{"fields":{"index":0},"id":11,"inputs":[10],"op":"Proj"}
{"control_in":11,"fields":{"dispatch_kind":"direct","name":"main::add","param_names":[],"want":"scalar"},"id":12,"inputs":[6,7],"mem_in":5,"mem_out":true,"op":"Call","stamp":"Num"}
{"fields":{"sigil":"$","symbol":"x"},"id":13,"inputs":[],"mem_in":12,"op":"PadAccess","stamp":"Unknown"}
{"control_in":12,"id":14,"inputs":[13,12],"mem_in":12,"mem_out":true,"op":"Assign","stamp":"Num"}
{"fields":{"const_type":"integer","value":"0"},"id":15,"inputs":[],"op":"Constant","stamp":"Int"}
{"fields":{"index":1},"id":16,"inputs":[10],"op":"Proj"}
{"control_in":16,"id":17,"inputs":[6,15],"mem_in":5,"mem_out":true,"op":"Assign","stamp":"Int"}
{"head":10,"id":18,"inputs":[14,17],"op":"Region"}
{"fields":{"memory":true,"predecessors":[11,16],"region":18},"id":19,"inputs":[14,17],"op":"Phi","stamp":"Num"}
{"fields":{"sigil":"$","symbol":"x"},"id":20,"inputs":[],"mem_in":19,"op":"PadAccess","stamp":"Str"}
{"fields":{"from_repr":"Unknown","to_repr":"Str"},"id":21,"inputs":[20],"op":"Coerce","stamp":"Str"}
{"fields":{"const_type":"string","value":"\n"},"id":22,"inputs":[],"op":"Constant","stamp":"Str"}
{"id":23,"inputs":[21,22],"op":"Concat","stamp":"Str"}
{"control_in":18,"id":24,"inputs":[23],"op":"Print","stamp":"Maybe[Boolean]"}
{"control_in":24,"fields":{"implicit":true},"id":25,"inputs":[1],"mem_in":19,"op":"Return"}
== main::add start=0 returns=5
{"id":0,"inputs":[],"op":"Start"}
{"fields":{"sigil":"$","symbol":"a"},"id":1,"inputs":[],"op":"PadAccess","stamp":"Num"}
{"fields":{"sigil":"$","symbol":"b"},"id":2,"inputs":[],"op":"PadAccess","stamp":"Num"}
{"id":3,"inputs":[1,2],"op":"Add","stamp":"Num"}
{"id":4,"inputs":[],"op":"MemStart"}
{"control_in":0,"id":5,"inputs":[3],"mem_in":4,"op":"Return"}
{"id":6,"inputs":[],"op":"ArgsSource","stamp":"Array"}
{"fields":{"record":true,"targets":2},"id":7,"inputs":[1,2,6],"op":"Assign","stamp":"List"}
```

Things to notice:
- The Region's inputs are the arms' last effects (the Assigns), not their
  Projs; `predecessors` gives the Projs.
- The memory Phi merges the two Assigns.
- Each PadAccess read of `$x` (a `my` the program keeps in memory) names
  the memory version it reads as `mem_in`; its `inputs` are empty.
- The call is a value (the Assign's input) and a memory version (`mem_out`,
  the Assign's `mem_in`): one node, two faces, told apart by the edge.
- `add`'s `my ($a, $b) = @_` is a `record`, on neither chain.
- (`file`, `line` and `package` of the call are left out here.)

A loop with a die
(`while ($i < 3) { $s = $s + $i; $i++ } die "neg" if $s < 0; print $s / 2, "\n";`),
excerpt:

```
{"control_in":0,"fields":{"bound":"each"},"id":3,"inputs":[0],"op":"Loop"}
{"fields":{"region":3},"id":4,"inputs":[2,28],"op":"Phi","stamp":"Int"}      # backedge 28: a forward ref
{"id":8,"inputs":[5,7],"op":"Divide","stamp":"Num"}                          # constant divisor: no site
{"fields":{"index":1},"id":11,"inputs":[3],"op":"Proj"}                      # loop exit
{"head":3,"id":12,"inputs":[11],"op":"Region"}
{"control_in":12,"id":14,"inputs":[12,13],"op":"If"}
{"control_in":17,"fields":{"file":"l.pl","line":3},"id":18,"inputs":[16],"op":"Unwind"}
{"head":14,"id":19,"inputs":[15,18],"op":"Region"}
{"control_in":3,"id":24,"inputs":[22,23],"op":"NumLt","stamp":"Boolean"}     # loop condition pinned to Loop
{"fields":{"index":0},"id":25,"inputs":[3],"op":"Proj"}                      # loop body
{"id":28,"inputs":[4,22],"op":"Add","stamp":"Int"}
```

---

## 3. What builds the IR, and what another producer must supply

### 3.1 The B::SoN path

- **When it runs.** `B::SoN::compile` runs at CHECK time. It installs a
  no-op peephole optimizer, so the optree stays in canonical, unfused form.
- **What it walks.** `_discover_and_translate`:
  - walks the stashes and translates each user CV with
    `SoN::FromOptree->translate`;
  - translates the file's top level with `translate_root` into
    `main::__PROGRAM__`;
  - translates anonymous, sort and substitution bodies to a fixpoint.

  `_phase_blocks` collects BEGIN and END blocks, and the class records are
  filled in along the way.
- **The translator.** `SoN::FromOptree`: *"Translates perl5 compiled
  optrees into SoN IR graphs. Uses stack simulation to reconstruct data flow
  from the op_next chain"* (`FromOptree/StackSim.pm`, `FromOptree/OpMap.pm`).
- **Node identity** (`lib/SoN/IR/NodeFactory.pm`):
  - Data nodes are hash-consed by `content_hash`, which becomes the node id.
  - These get per-call ids `Op#N` instead:
    - CFG nodes (`Start Return Unwind If Proj Region Loop PackageMark Exc`);
    - the routed CFG ops (`If Proj Region Phi Loop`);
    - VarDecl and ListAssign;
    - `%STATEMENT_EFFECT_OPS`;
    - `%ALLOC_OPS` (`ArrayLiteral HashLiteral MakeCell CellWrite`).
  - A PadAccess at a different pad index is forced unique.
  - **None of these internal ids reach the wire.** The serializer renumbers
    every node by its position.
- **Serializer ordering.** The serializer does its own BFS from `start` and
  `returns`, following inputs, consumers and `control_in`. It then orders
  the nodes with `_all_nodes_topo`:

  > This is the cross-repo walk-order contract; the corpus gate enforces it.
  > This function is a deliberate DUPLICATE of chalk-side IR Serialize JSON
  > copy (the repos are divorced); the gate keeps them honest.

  A node's predecessors are its inputs, a Phi's `region`, and `control_in`.
  A **loop Phi's back edge is left out**, which is why it is the only
  forward reference.

  **The two copies have drifted.** This repo's copy expands array-valued
  inputs (Unwind's argument list) and silences recursion warnings; chalk's
  copy does neither. No check compares the two functions directly.

### 3.2 What chalk's loader requires

These come from `lib/Chalk/IR/Serialize/JSON.pm` (`_deserialize_graph`,
`from_json`). A producer that meets all of them will load:

1. **Valid JSON** with a `methods` hash of `{nodes, start, returns}`.
   `version` must be 2 (a GAP names another); `source` is ignored.
2. **Nodes are addressed by array position.** `id` must equal the node's
   position.
3. **No forward references except a loop Phi's back edge** (a `mem_in` too
   names a node listed before it: since stage 6, when v1's upgrade went):

   > The one sanctioned forward edge is a loop Phi's backedge (inputs[1]),
   > deferred and patched below. Any OTHER forward index is a producer
   > ordering bug … Die at the seam

   That edge is recognised as `op eq 'Phi' && @inputs == 2 && inputs[1] >=
   current count`. `control_in`, `head`, `region`, `predecessors` and
   `eval_entry` must all point backwards.
4. **`op` must be a name chalk's NodeFactory knows.** CFG ops are
   `Start Return Unwind If Proj Region Loop Exc`. Any other op goes through
   `make()`, which dies with `"Unknown data node operation: $op_name"`.
   Fields the loader does not name are dropped silently.
5. **Required fields:**
   - `PadAccess.fields.sigil` and `EntryDef.fields.sigil` (a missing one is
     a GAP, e.g. `"GAP: PadAccess '…' arrived with no sigil"`);
   - `Parameter.index`, which is its identity;
   - `Phi.region`;
   - `Proj.index`;
   - `Call.dispatch_kind` and `Call.name`.
6. **Stamps are lattice names.** These are admitted as representations:
   `Int Num Str Boolean Undef Object ArrayRef HashRef Array Hash Scalar`.
   Any other name the lattice knows is kept as a type. A string the lattice
   doesn't know is dropped. The loader also fixes some stamps itself:
   - an `@` or `%` PadAccess becomes Array or Hash;
   - a Ref of a PadAccess becomes a typed ref;
   - a builtin Call or ArrayLiteral stamped `List` becomes `Array`;
   - Print becomes Boolean.
7. **Memory is named** (§1.5): `mem_in`, `mem_out`, and `memory: true` on a
   memory Phi. A B::SoN wire (one with `dowarn`) is held to the memory
   invariant, `Chalk::IR::Serialize::WireInvariant`: L1 every `mem_in` names
   a version; L2 a version is on the control chain and follows one; L3 every
   Return and Unwind names its memory; L4 every version is reached backwards
   from a Return or Unwind (or a loop with no exit); L5 an Assign is a
   `record` or has all three edges, as a sub Call does (but an :lvalue call,
   the place an Assign stores through); L6 a Phi's inputs pair with its
   Region's ways in (a trap's value Phi keeps one more on a wire without
   the `eval` profile); L7 (`eval`) every way into a catch Region leads back
   to an Exc.
8. **The control chain:**
   - Statement effects need `control_in`.
   - Each Return's `control_in` chain decides which nodes belong to the
     graph.
   - If, Loop and Region carry their control in `inputs`.
   - A Region needs `head`.
   - A Phi needs `predecessors` to pair inputs with arms; without them the
     consumer searches.
9. **An entry graph.** The LLVM path needs a `main::__PROGRAM__` graph with
   at least one Return; without one it fails with
   `LOAD: no program graph with a return`.
10. **Phase blocks:**
    - A BEGIN or END block with effects is accepted only in package `main`,
      where it loads as `main::__BEGIN_N`.
    - A `use`-shaped block may contain only `require` plus
      `import`/`unimport`/`VERSION` calls.
    - Anything else is a GAP: *"a … block with effects of its own is not
      lowered"*.
11. **Analysis runs inside `from_json`** (`Chalk::IR::Analysis->run`). Its
    exit check `_assert_value_nodes_are_typed` is called
    (`Analysis.pm:561`) and dies with *"IR: analysis finished with untyped
    Value node(s)"*. The comment above it still says it is disabled, which
    contradicts the code. **Stamp every value node, using `Unknown` when
    unsure.**
12. **The class section** must have the shape in §2.3, so it can be
    replayed through the MOP. `methods.{name}` is a string key into the
    top-level `methods`.

The loader's own statement of where it should end (`Chalk/IR/Serialize/JSON.pm`):

> STILL TO DO, and this is the actual boundary: from_json should not call
> this at all. The loader's job is to reproduce the graph the frontend
> serialized -- typing it is T1's. … measured by
> t/bootstrap/ir/loader-reproduces-the-wire.t, it adds 16 stamps the wire
> never sent. That number reaching zero is what finishing the split means.

### 3.3 Gates and tests that hold the contract

- **Chalk:**
  - `t/bootstrap/ir/loader-reproduces-the-wire.t` (decode, then re-encode;
    not yet an assertion);
  - `t/bootstrap/ir-node-unify-roundtrip.t` and `ir-serialize-json.t`;
  - `t/bootstrap/codegen-harness/wire*.t`;
  - `t/bootstrap/ir/*-survives-the-loader.t`;
  - `method-return-type-from-wire.t`;
  - `loader-*.t`;
  - `t/corpus/mdtest/control-flow.md` §T2c, the walk-order pin.
- **This repo:**
  - `t/corpus-llvm-roundtrip.t` and `tools/corpus-llvm-roundtrip.pl`: the
    B::SoN → chalk (at a pinned commit) → lli census, compared with perl;
  - `t/roundtrip-ratchet.t`: the floor on that census;
  - `tools/corpus-roundtrip.pl`;
  - `t/deparse-memory-table-matches-producer.t`;
  - `t/wire-booleans-are-json-booleans.t`: *"a decoded comparison cannot
    tell `true` from `1`"*;
  - the `t/wire-*.t` field pins.

### 3.4 Prior art for a parser

**Chalk's own Earley front end.** From chalk's `ARCHITECTURE.md`: *"Chalk is
… built on a scanless Earley parser with semiring-based disambiguation … The
parser emits SoN IR directly; there is no intermediate parse tree or Shared
Packed Parse Forest stage."*
- **Code:** `lib/Chalk/Bootstrap/Earley.pm`, `LR0DFA.pm`, `Semiring/*` and
  `Perl/Actions.pm`. Actions build the IR through `Chalk::IR::NodeFactory`,
  and the "Block control-chain fixup" sets `control_in`.
- **Docs:** `docs/architecture/earley-parser.md`, `parsing-pipeline.md`,
  `docs/chalk-grammar-spec.md` and `docs/chalk-parse-perl-plan.md`.
- **Status**, from `docs/plans/2026-06-12-phase4-bson-brief.md`:

  > The capstone … needs an IR-producer for real Perl input. It is NOT the
  > Chalk parser/SemanticAction (untrusted, paused); it is **B::SoN** … B::SoN
  > is DIRECTIONAL … It earns trust ONLY through the now-trusted instruments:
  > B::SoN IR → verified backend → run → compare to perl.

**A textual IR**, chalk's mdtest "constructive ir-block"
(`docs/plans/2026-06-07-mdtest-corpus-format-draft.md`):

```
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
control: %a -> %b
L: GREEN | L: GAP(reason)
```

Its examples predate memory edges.

**The rule any producer earns trust by**
(`docs/memory/bson-emits-ir-perl-is-validation.md`): *"B::SoN's job is to
emit IR. Lowering that IR back to Perl (SoN::Deparse) and comparing the
program's behaviour with the original is our VALIDATION that the IR is
right."* A new producer passes the same perl-oracle round trip.

---

## 4. Status

**Implemented:**
- The B::SoN JSON producer: `lib/B/SoN.pm`, `lib/SoN/FromOptree.pm` and
  `lib/SoN/Serialize/JSON.pm`.
- 105 node classes.
- Memory SSA: MemStart, memory Phis, EntryWrite and cells.
- Phi `predecessors`, Region `eval_entry`, Loop `bound`.
- Loop control: next and last, with labels.
- `Ref.each` and `Parameter.default_when`.
- Chalk's loader, Analysis and LLVM target, on `bson/llvm-corpus`. 354 of
  430 corpus cases round-trip through LLVM with perl's output, and none
  differ.

**Proposed, not built:**
- `Call.enclosing_package` for SUPER:: dispatch.
- goto as a tail call.
- `docs/plans/2026-08-31-one-operator-one-declaration.md`.
- `2026-09-26-the-slot-is-the-stamp.md`.
- `2026-09-12-deparse-target-as-a-differential-oracle.md`.
- `2026-09-13-an-aggregate-has-no-perl-spelling.md`.
- `2026-09-30-chalk-lib-round-trip.md`.
- Chalk's loader split: typing (T1) out of `from_json`, `stamp` separate
  from representation.
- **Stamps beyond a type.** `Value.pm`: *"Today SoN::IR::Stamp holds only
  `type`, because no pass here produces the other components yet"*.

**Missing for a parser front end:**
- **A schema file.** The version is checked (2) and the memory edges are
  (the loader's invariant, `SoN::Verify`); the rest of the schema is
  `_extract_fields` plus the loader's matching branches, kept in step by
  tests and the chalk pin.
- **Source spans** beyond file and line on Unwind, Divide and Modulo, and
  line numbers on sub and method records.
- **Refusals in the wire.** A GAP refusal and a skipped graph appear only
  on stderr.

**Key files**
- **This repo:**
  - `lib/SoN/Serialize/JSON.pm`
  - `lib/B/SoN.pm`
  - `lib/SoN/IR/{Node,Value,Stamp,NodeFactory,Graph}.pm`
  - `lib/SoN/IR/Node/*.pm`
  - `lib/B/SoN/TypeLibrary.pm`
  - `lib/SoN/Deparse.pm`
  - `docs/wire-*.md`
  - `docs/plans/2026-04-07-son-json-serialization-design.md` (stale)
- **Chalk:**
  - `lib/Chalk/IR/Serialize/JSON.pm`
  - `lib/Chalk/IR/Analysis.pm`
  - `lib/Chalk/Grammar/Perl/TypeLibrary.pm`
  - `docs/plans/2026-06-12-phase4-bson-brief.md`
  - `lib/Chalk/Bootstrap/Earley.pm`
  - `lib/Chalk/Bootstrap/Perl/Actions.pm`
