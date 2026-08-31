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

## Not Allium-style generation -- decided 2026-08-31

Reviewed adversarially (Fable) and for over-engineering (ponytail); both said
no, and the numbers say why.

Generation reaches **~6-8% of the ~9600-line producer and ~20% of recent bugs**
-- and that 20% is already caught by the three lints built the same night,
which use perl's own `Opcode`/`B` at test time and so carry no artifact and no
version skew. Allium ships 5.41.4 (415 ops); we run 5.42 (426). The skew is
present today.

What generation cannot reach: the op->node collapse (only 13 of 264 mappings
are `ucfirst`; 176 collapse to one `Call`), the Num/Str narrowing that drives
coercion insertion (perl resolves it at runtime in `pp_add`/`pp_concat`), and
the ~4700 lines of SSA, control flow and memory ordering. Allium round-trips
the optree SHAPE -- no SSA, no Phi placement -- so its IR is the optree with
different capitalisation.

Maintenance inverts too: churn is +1/+4/+3 ops per stable release and zero
removals. `t/every-op-has-a-disposition.t` already fails BY NAME on a new op,
and deciding its disposition is the part no generator can do.

Keep the hand table as the source of truth; keep perl-derived facts as lints.

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
