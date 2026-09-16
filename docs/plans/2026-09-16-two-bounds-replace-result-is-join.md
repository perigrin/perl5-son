# Two bounds replace %RESULT_IS_JOIN

perigrin, twice: the T1/T2 finding makes %RESULT_IS_JOIN unnecessary -- and,
correcting my "Concat converts Int to Str": no, Str in Str out, with a coercion
if necessary, and also Int <: Str.

Both are right, and together they produce a rule with no flag in it.

## The correction that unlocked it

I claimed Concat CONVERTS its operands (Int in, Str out) while Add PRESERVES
them. That is wrong: the lattice is Int -> Num -> Str -> Scalar -> List, so
Int <: Str. An Int argument to Concat is ALREADY a Str. Nothing converts;
`(Str, Str) -> Str` is the whole signature, and subsumption does the rest.

So the real question was never conversion. It is why Concat(Int,Int) widens to
Str while Add(Int,Int) stays Int.

## The answer: closure

    Add    : Int x Int -> Int always?   1+2=3, -1+-2=-3       YES
    Concat : Int x Int -> Int always?   1 . -5 = "1-5"        NO
    Divide : Int x Int -> Int always?   1/2 = 0.5             NO

Measured with perl. `1 . -5` is "1-5", which is not a number, so Str is the
honest answer for Concat and Int would be a miscompile. Add IS closed over Int;
Concat and Divide are not.

## One rule, two bounds

    result = clamp( join(actual operand types), floor, ceiling )

      floor    the NARROWEST type the operator is closed over
      ceiling  the WIDEST type it can yield          (today's `result`)

      join below the floor   -> floor      (Concat(Int,Int) -> Str)
      join above the ceiling -> ceiling    (Add(Str,Int)    -> Num)
      otherwise              -> the join   (Add(Int,Int)    -> Int)

Measured against the table over six operand pairs per op, it reproduces EVERY
row for both groups:

    Add, Subtract, Multiply   floor Int   ceiling Num
    Divide, Power, UnaryPlus  floor Num   ceiling Num
    Concat, Repeat            floor Str   ceiling Str
    And, Or, DefinedOr        floor Int   ceiling Scalar

A first attempt with the floor ALONE failed on 12 rows -- every one a Str
operand to an arithmetic op, where the join escaped upward past Num. Both
bounds are load-bearing; neither alone is sufficient.

## What this says about the flag

%RESULT_IS_JOIN was a BOOLEAN standing in for a missing TYPE. An op "joins"
exactly when its floor is strictly below its ceiling:

    Add     Int < Num      joins
    Divide  Num = Num      does not
    Concat  Str = Str      does not

so the flag is derivable and does not need storing. That is the simplification
perigrin proposed; it needed the floor to exist before it could be taken.

## Consequence for the declaration syntax

Two bounds are two types, and a signature already has two type positions --
parameters and return:

    sub :infix +  (Int $x, Int $y) Num;     floor Int, ceiling Num  -- joins
    sub :infix /  (Num $x, Num $y) Num;     floor Num, ceiling Num  -- flat
    sub :infix .  (Str $x, Str $y) Str;     floor Str, ceiling Str  -- flat

The PARAMETER types are the floor and the RETURN type is the ceiling. Nothing
extra is needed -- no :join attribute, no type variable, no expression over
parameters. perigrin's original spelling was sufficient all along, once the
parameter list is read as the closure floor rather than as a coercion target.

NOTE this changes what `operands` means. Today Add declares operands => ['Num']
(what it REQUIRES); under this reading it would declare Int (what it is closed
over). Those are different facts and both are needed -- the requirement types
an untyped operand, the floor bounds the result -- so this is a third column,
not a renaming. Whether they can share one position is unmeasured.

## Remaining work

1. Measure the floor for every op in the table, not the eleven probed here.
2. Decide whether `operands` (requirement) and the floor (closure) can share a
   syntactic position, or whether a signature needs both.
3. Then delete %RESULT_IS_JOIN and derive it as floor < ceiling.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
