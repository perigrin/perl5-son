# One operator, one declaration

**Status:** proposed, not started
**Measured:** 2026-08-31, at commit 3afe1fc

## The problem

Adding one operator to the IR means editing **five declaration sites across
four files**, and the compiler cannot tell you when you have filled in four:

| # | file | what it declares |
|---|------|------------------|
| 1 | `lib/SoN/FromOptree/OpMap.pm` | optree name -> pop/node/push/flags |
| 2 | `lib/SoN/IR/Node/<Name>.pm` | the node class (~10 lines of boilerplate) |
| 3 | `lib/SoN/IR/NodeFactory.pm` | a `use` line AND a name in a `qw()` list |
| 4 | `lib/B/SoN/TypeLibrary.pm` | `operands`, `result`, `%RESULT_IS_JOIN` |
| 5 | `lib/SoN/FromOptree.pm` | `%RESULT_STAMP` |

Each omission fails **differently**, and none of them fails at the edit:

- miss 1 -> the op falls through silently (the block-eval shape, `b8552e6`)
- miss 2 -> the factory dies "no such node class"
- miss 3 -> the factory dies, or the node never reaches the wire
- miss 4 -> operands are never coerced; no signature to check against
- miss 5 -> the node reaches the wire stamped `Unknown`

Miss 5 is not hypothetical. Adding `Count` this session updated TypeLibrary but
not `%RESULT_STAMP`, and the node came out `Unknown`. Commit `93a2d12` recorded
it and deferred the fix: *"A FOURTH COPY OF THE RESULT-TYPE FACTS, found on the
way and NOT fixed here."*

`TypeLibrary.pm`'s own header names the same defect from earlier still:

> It was previously being re-derived by accident, in pieces, in two different
> files... **Three partial copies of one table, none of them labelled as such.**

### The tables already disagree

    OpMap names          47 IR nodes
    TypeLibrary declares 39 signatures
    %RESULT_STAMP holds  19 entries

13 nodes OpMap can build have **no TypeLibrary signature at all**:

    AnonSub ArrayRef Assign BacktickExpr Call Constant HashRef
    Match PadAccess Ref Slice Subscript Xor

(0 nodes lack a class file, so site 2 is currently consistent.)

## What this is NOT

Not an Allium-style extraction from perl. That was investigated the same
session (see `docs/` note or memory `allium-instruction-sets`) and answers the
wrong half:

- **Generatable from perl:** op class, and `pop_count` for the unambiguous
  classes. Churn here is small -- 5.38 -> 5.44 added 8 ops and removed none.
- **NOT generatable:** `add -> Add`, `operands => ['Num','Num']`,
  `result => join`. These encode what *our IR means* and no perl metadata knows
  them.

Allium's `prototype` field must not be used as `pop_count`: it is the
source-level signature, not the runtime stack discipline. They agree on plain
BINOPs and diverge everywhere else (`floor` has `prototype: []` but pops its
UNOP child; `and` is a LOGOP that branches; `print` is variadic and needs the
`mark` discipline, which a prototype cannot express).

## Proposal

One table, one entry per operator, everything else derived:

```perl
Add => {
    optree   => 'add',            # -> OpMap
    node     => 'Add',            # -> NodeFactory + class check
    operands => ['Num', 'Num'],   # -> TypeLibrary
    result   => 'join',           # -> TypeLibrary result + %RESULT_STAMP,
                                  #    capped at Num
},
```

`OpMap`, `NodeFactory`, `TypeLibrary` and `%RESULT_STAMP` all read from it. A
missing field becomes an error at load time, not an `Unknown` on the wire three
passes later.

## Sequencing

The audit gates the ergonomics; do them in this order.

1. **DONE -- `t/every-op-has-a-disposition.t`.** Every op perl can emit must
   have a deliberate disposition (node / skip / control / handler / GAP), or an
   explicit allowlist entry. This is the gate: it fails when a new op appears
   with nothing decided about it, which is how block eval hid for months.
2. **DONE -- `t/opmap-respects-op-class.t`.** `pop_count` must agree with
   perl's op class. Found exactly one violation in 350 entries (`goto`, fixed
   in `3afe1fc`).
3. **NEXT -- a consistency test across the five sites**, before touching any
   of them. For every node OpMap can build: a class file exists, the factory
   knows it, and it has a signature *or* is on a documented exemption list.
   This makes the 47/39/19 gap visible and stops it widening.
4. **THEN -- the unified table**, one operator at a time, with (3) green
   throughout. Start with the 13 signature-less nodes: either give them
   signatures or record why they cannot have one (`Constant` and `PadAccess`
   plausibly cannot -- they have no operands to constrain).

## Open questions

- Do `Constant`, `PadAccess`, `Call` belong in a *signature* table at all?
  They may need a different shape rather than an exemption.
- `%RESULT_IS_JOIN` is a second axis on `result` (join-of-operands vs fixed).
  The unified entry should express both without a separate set.
- Chalk mirrors `TypeLibrary` deliberately (`%BINARY_OP_SIGNATURES`). Any
  change to the signature *shape* is a cross-repo conversation, not a
  producer-local refactor.
