# %RESULT_IS_JOIN records preservation, not joining

perigrin, after establishing that the join rule is T2 polymorphism and T1 only
ever writes a concrete supertype: "I think this makes RESULT IS JOIN
unnecessary."

Tested, and the answer is more interesting than yes or no: the flag is NOT
eliminable as the code stands, but it is MISNAMED, and the fact it really
records is a different one.

## The measurement

Delete the flag and give every op `meet(join(operands), result)`. Twelve change
answer:

    CellRead CellWrite Concat Delete Divide Power
    Range RefType Repeat Slice UnaryPlus Wantarray

all of them wrongly toward `Int` -- `Concat(Int,Int)` would be `Int` instead of
`Str`, `Range(Int,Int)` would be `Int` instead of `List`.

## The first correction: the rows already carry `operands`

My probe ignored them, and they are exactly the missing input:

    Concat    { operands => ['Str','Str'], result => 'Str' }
    Add       (via %SIGNATURES)            result => 'Num'

Joining the DECLARED operand types rather than the raw actuals is closer -- it
fixes `Concat(Str,Int)` -- but still wrong for `Concat(Int,Int)`, because
meeting an actual `Int` against a declared `Str` narrows to `Int`, and
concatenation does not preserve Int-ness.

## What the flag actually distinguishes

Not "joins" versus "does not join". Whether the operator PRESERVES its operand
types or CONVERTS them:

    Add(Int,Int)    = Int     Int survives the operation
    Concat(Int,Int) = Str     the Int is consumed by stringification
    Divide(Int,Int) = Num     converts to Num and cannot come back

`result` is a CAP in both groups. What differs is whether narrower operand
information survives to be capped at all.

And this is NOT the same fact as `operands`. Add REQUIRES Num and an Int still
comes out Int; Concat requires Str and an Int does not come out Int. Requiring
a type is not the same as destroying information narrower than it.

## Consequence for the declaration syntax

    sub :infix +  (Num $x, Num $y) Num;    preserves -- Int in, Int out
    sub :infix .  (Str $x, Str $y) Str;    converts  -- Int in, Str out

These are spelled identically and mean different things, so the syntax DOES
still need one bit -- but it is a bit about CONVERSION, not about joining, and
it is a property of the operator rather than of its result type.

Whether that bit can be derived instead of declared is the open question: it
may follow from whether `result` is a supertype of the declared operands
(Concat's Str IS its operands' type; Add's Num is a supertype of nothing it
declares, since its operands are Num too). That symmetry does not obviously
hold, and it has not been measured.

## Remaining work

1. Rename the flag to what it records, once (2) settles whether it survives.
2. Measure whether preservation is derivable from `operands` + `result`, across
   the whole table rather than the handful probed here.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
