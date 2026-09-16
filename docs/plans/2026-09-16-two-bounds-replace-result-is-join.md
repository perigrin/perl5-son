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

## CORRECTION: the floor is not a signature, and T1 need not join at all

perigrin, on my `sub :infix + (Int $x, Int $y) Num;`:

> Except this isn't the signature and it doesn't join since Int <: Num.
> `sub :infix + (Num $x, Num $y) Num;` is correct and doesn't need to "join"
> over anything at the T1 / IR level.

Both halves are right and the second is the important one.

FIRST: `(Int $x, Int $y)` is simply FALSE as a signature. `+` accepts a Num --
`1.5 + 2` is legal -- so declaring Int would reject valid arguments. I let the
floor mechanism dictate the declaration, which inverts the relationship: a
signature says what the operator ACCEPTS, and the floor was an implementation
detail of how I was computing a result. They are not the same position and the
floor has no business in the parameter list.

SECOND, and this subsumes the whole document above: T1 does not need the join.
The only row it buys is

    Add(Int,Int)  stamp Int   -- would be Num without the join

and Num is TRUTHFUL for it, because Int <: Num. Losing the join costs precision,
not correctness.

And nothing at T1 consumes that precision. Measured -- the entire codebase
branches on `Int` in exactly two places, and neither is this:

  _coerce_int_to_num (FromOptree)  wraps an Int OPERAND of a Divide. Its own
                                   comment says why: to satisfy chalk's
                                   TypedInvariant and emit sitofp exactly once.
                                   A T2 requirement reaching back into T1, and
                                   it keys on the OPERAND's stamp, not on any
                                   join.

  Deparse's `keys`                 reads Int as a marker for SCALAR CONTEXT, a
                                   fact the producer recorded from the op, not
                                   from an arithmetic join.

Measured on a real graph, `$i/$i` and `$i+$i` side by side:

    Coerce in=[Constant/Int]              stamp=Num    <- on Divide's OPERAND
    Divide in=[Coerce/Num,Coerce/Num]     stamp=Num
    Add    in=[Constant/Int,Constant/Int] stamp=Int
    Coerce in=[Add/Int]                   stamp=Str    <- immediately widened

Add's Int is recorded and then coerced away. Nothing reads it.

So the correct T1 rule is the simple one:

    result = the operator's declared return type

and `sub :infix + (Num $x, Num $y) Num;` says it completely -- which is what
perigrin wrote at the start, before I added a floor, a type variable, a :join
attribute and an expression language, none of which T1 needs.

The two-bounds rule above is not wrong, it is T2's. Chalk is where Int-vs-Num
selects an instruction, and where narrowing a result below its declared type
pays for itself.

## Consequence for the declaration syntax

Two bounds are two types, and a signature already has two type positions --
parameters and return:

    sub :infix +  (Num $x, Num $y) Num;
    sub :infix /  (Num $x, Num $y) Num;
    sub :infix .  (Str $x, Str $y) Str;

For T1 these are complete AS WRITTEN: the return type is the answer, full stop.
No floor in the parameter list, no :join attribute, no type variable, no
expression over parameters.

Note that + and / now read IDENTICALLY, and at T1 that is correct -- they yield
the same type. The distinction between them is T2's, where it decides an
instruction.

NOTE this changes what `operands` means. Today Add declares operands => ['Num']
(what it REQUIRES); under this reading it would declare Int (what it is closed
over). Those are different facts and both are needed -- the requirement types
an untyped operand, the floor bounds the result -- so this is a third column,
not a renaming. Whether they can share one position is unmeasured.

## MEASURED: the join IS load-bearing at T1, for a case that is not Add

I predicted that dropping the join would cost precision and no behaviour.
Tested it -- gated `result_for`'s join behind SON_NO_JOIN and ran the suite.
The prediction was WRONG. Five files fail:

    t/wire-shortcircuit-is-a-join.t         3 of 3
    t/wire-loop-compound-assign-ternary.t   4 of 5
    t/wire-phi-join-stamp.t, t/wire-selftyped-stamp.t,
    t/wire-internal-errors-refuse.t         1 each

And the reason is a kind of operator I had not separated from Add:

    $@ || "Zombie Error"    with join: Scalar     without: List

`Or`'s declared return type is `List`. Add's is `Num`, and dropping to Num
costs only precision because Int <: Num. Dropping Or to List is NOT loose --
List is the TOP of the lattice, and the stamp then says the expression MIGHT BE
A LIST. It cannot be: `scalar(() = ($@ || "Zombie"))` is 1. That is a wrong
claim about ARITY, not a vague one about width.

The difference is what the operator does with its operands:

    Add     COMPUTES a new value -- the result is not either operand
    Or/And  RETURN ONE ARM UNCHANGED -- the arms ARE the result

For the second kind the join is not an optimisation, it is the only way to say
what the node yields, because the node yields exactly one of the things joined.
A short-circuit is a Phi written as an operator, which is precisely why
`_stamp_merges` uses the same operation for a real Phi.

So the correct statement is narrower than either of us had it:

  - For COMPUTING operators (Add, Subtract, Multiply), perigrin is right: T1
    does not need the join. The declared return type is truthful, nothing at T1
    branches on the narrower answer, and the two consumers of `Int` are a T2
    requirement (_coerce_int_to_num, for chalk's sitofp) and a context marker
    on `keys`.

  - For SELECTING operators (And, Or, DefinedOr), the join is mandatory at T1
    and is not about precision at all.

%RESULT_IS_JOIN conflates these. Its seven members are

    Add Subtract Multiply Negate      computing -- join is T2 precision
    And Or DefinedOr                  selecting -- join is T1 correctness

which is why every attempt above to give it ONE meaning -- "joins", "preserves",
"is closed over" -- kept failing on half the set.

## Remaining work

1. Split %RESULT_IS_JOIN into its two kinds -- selecting (And/Or/DefinedOr,
   where the join is T1 correctness) and computing (Add and friends, where it
   is T2 precision). The set is seven entries; the split is mechanical.
2. Then decide, separately, whether T1 keeps the computing half. Dropping it
   costs only precision -- measured, the only differing row is
   Add(Int,Int) Int -> Num -- but chalk reads these stamps, so the decision is
   chalk's to make, not this repo's.
3. The two-bounds rule stands for the computing half wherever narrowing pays.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
