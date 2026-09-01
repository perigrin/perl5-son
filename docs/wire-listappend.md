# ListAppend — node contract

`ListAppend` is wire vocabulary added in `f57cd9d`. A consumer pinned before that
commit will not recognise it. This is what it means and what it guarantees.

## Signature

    op:     "ListAppend"
    inputs: [ accumulator, contribution... ]
    stamp:  Array

- `inputs[0]` is the accumulator so far. It is **always a Phi** in every graph
  B::SoN currently emits: the loop-header Phi whose other input is the empty
  `ArrayLiteral` seed.
- `inputs[1..]` are this iteration's contribution. **The count varies per
  emission site, and may be zero.**
- The node's value is the new accumulator: the old one with the contribution
  appended, flattened.

It is a pure value node. No control input, no memory input, no side effect.

## Why it exists

`map` and `grep` are loops. They carry `mapwhile`/`grepwhile` in the optree
exactly as `while` carries `enterloop`/`leaveloop`, so the counted-loop lowering
already built their control flow. What was missing was a *value*: their output
length is not their input length.

    map  { ($_, $_) } (1,2)    -> 4 elements
    map  { () }       (1,2)    -> 0 elements
    grep { $_ > 1 }   (1,2,3)  -> 2 elements

`Count(list)` bounds the **input**. Nothing bounded the output. `ListAppend` is
the loop-carried value that does, and because `inputs[0]` is an ordinary loop
Phi, the existing back-edge machinery moves it with no new control handling.

## The two emission shapes

### map — contribution is the body's value

`my @m = map { $_ * 2 } (1,2,3);`

    9    ArrayLiteral   in=[6,7,8]     # the input list, stamp List
    10   Count          in=[9]         # bounds the loop
    12   Phi            in=[11,15]     # induction variable
    13   NumGt          in=[10,12]     # loop condition
    17   Subscript      in=[9,12,16]   # $_ this iteration
    18   Multiply       in=[17,7]      # the body
    19   ArrayLiteral   in=[]          # empty seed
    20   Phi            in=[19,21]     # the accumulator
    21   ListAppend     in=[20,18]     # accumulator + body value

`inputs[1..]` is **whatever the body left on the stack**, so its arity is the
body's list arity, not one:

    map { ($_,$_) } (1,2)   ->  ListAppend in=[18,16,16]    two contributions
    map { () }      (1,2)   ->  ListAppend in=[4]           zero contributions

A `ListAppend` with a single input is well-formed and means "this iteration
contributes nothing".

### grep — contribution is gated by a predicate

`my @g = grep { $_ > 1 } @a;`

    21   ListAppend     in=[20,17,18]
                            ^   ^  ^
                            |   |  predicate (Boolean)
                            |   element
                            accumulator

For `grep`, and **only** for `grep`, the append is exactly three inputs and the
last one is a `Boolean` predicate: append `inputs[1]` if `inputs[2]` is true,
otherwise contribute nothing. B::SoN refuses (`GAP:`) if a grep block does not
produce exactly one predicate value, so the three-input form is guaranteed.

Distinguishing the two shapes from the node alone is not possible and is not
intended to be — the predicate's `Boolean` stamp is the tell, and a consumer that
wants to be explicit should key off the stamp of the last input.

## Companion wire change

`Array`- and `Hash`-stamped values now reach `Count` where previously they did
not. `_is_aggregate_node` had recognised only `ArrayRef`/`HashRef`, so
`scalar(@g)` on a map/grep result fell through to the non-aggregate path and
emitted `Coerce` of the array rather than `Count` of it. Both types are now
recognised. A consumer that assumed `Count`'s operand is always a literal or a
ref will now also see a Phi carrying an `Array`.

Relatedly: an aggregate-stamped RHS in an array assignment is no longer wrapped
as a single element. `my @g = grep {...}` previously produced
`ArrayLiteral[Array]` — one input holding two elements — so a consumer counting
inputs read 1 where perl says 2. The accumulated value now flows through
directly.

## Stamps

The accumulator, its seed, and the `ListAppend` are all stamped `Array`.

The **input** list is stamped by what it is, and it is not always `Array`:

    grep { ... } @a          ->  Array   the named aggregate itself
    map  { ... } (1,2,3)     ->  List    a literal list

`List` sits directly under `Unknown` with `Array`, `Hash` and `Scalar` beneath
it, so a consumer wanting "some list-ish thing" should test against `List` and
accept its subtypes rather than matching `Array` exactly.

## What a consumer must not assume

1. That `ListAppend` has a fixed arity. It does not; it is 1 or more.
2. That `inputs[0]` is a Phi *forever*. It is one in every graph emitted today,
   because nested `map`/`grep` currently refuses (`GAP: foreach body writes the
   iterator variable`) and so no `ListAppend` ever feeds another. Treat it as a
   list-valued node.
3. That the last input is a predicate. That holds for `grep` only.
4. That the input list is stamped `Array`. A literal list is stamped `List`.
