# A declaration syntax for signatures

perigrin's ideal spelling:

    sub :infix + (Num $x, Num $y) Num;

It is the right shape, and it makes "an operator is a function with a weird
spelling" SYNTACTIC rather than merely architectural: `:infix` is the spelling,
and everything else is an ordinary signature. Two things have to be settled
before it can be implemented.

## Problem 1 (WITHDRAWN): the lattice already handles it

I claimed `sub :infix + (Num $x, Num $y) Num;` was wrong because "Int + Int is
Int, not Num". perigrin: check the type lattice.

    Int -> Num -> Str -> Scalar -> List

`Int` IS a `Num`. So declaring Add's return as `Num` is an UPPER BOUND that
`Int + Int = Int` satisfies, and the join rule is a narrowing WITHIN that bound
rather than a contradiction of it. The objection was mine, not the syntax's.

Better still, the join is DERIVABLE from the declaration. Measured over every
op the table describes:

    result = meet( join(operand types), declared result )

holds for all 33 ops that join. The difference between `Add` and `And` is not a
flag -- it is their declared RETURN TYPES:

    Add(Str,Int)   join=Str  capped by declared Num     -> Num
    And(Str,Int)   join=Str  capped by declared Scalar  -> Str

So `(Num $x, Num $y) Num` carries the cap, and the parameter list carries the
operand requirements. Two of the three facts fall straight out of the syntax.

## What genuinely remains: join-vs-fixed

12 ops do NOT join -- their result is flat whatever arrives:

    Concat -> Str always      Range, Slice -> List always
    Divide, Power -> Num      Repeat, RefType -> Str

and `Divide(Int,Int)` is `Num` because `1/2` escapes Int even though its
operands do not. No declared return type recovers that, since `Add` and
`Divide` both declare `Num`.

But the table ALREADY discriminates them without a flag, and the signature can
too. Asked with NO operands:

    result_for("Add")    -> undef     the answer DEPENDS on its operands
    result_for("Divide") -> Num       the answer does not

So the only fact the syntax still has to carry is a BOOLEAN: does this result
vary with its parameter types?

### What the cap needs: nothing

Measured -- for every joining op, the type the join is capped against IS the
declared return type. Forcing the join wide with (Str,Str) returns the cap:

    Add, Subtract, Multiply, Negate   -> Num
    And, Or, DefinedOr                -> Str

So a notation does not need to spell the cap. `(Num $x, Num $y) Num` already
says it.

### A rejected notation, and why it is recorded

I first wrote `Num($x|$y)`, meaning "the join of $x and $y, capped at Num". It
reproduces Add's rows, and it is still wrong -- perigrin named the reason:

    Int|Num collapses to Num, because Int <: Num.

A declaration `(Num $x, Num $y)` fixes BOTH parameter types at Num, so `$x|$y`
read over the declared types is `join(Num, Num)` = `Num`, a constant. The
expression carries no information at all.

It only says something if `$x` denotes the type of the ARGUMENT at a callsite
rather than the type of the PARAMETER -- and those differ:

    Add(Int,Int) -> Int      both are legal arguments to (Num $x, Num $y)
    Add(Num,Num) -> Num      and they give different results

So the varying quantity is the argument type, per call. No expression over
parameter NAMES can denote it, because a parameter's type is exactly what the
declaration pinned down. The notation was a category error, not merely ugly
(the `|`/bitwise-or collision and the doubled `Num` are true but secondary).

### What fits instead: a bounded type variable

The construct that does quantify over argument types is ordinary bounded
polymorphism:

    sub :infix + <T <= Num>    (T $x, T $y) T;
    sub :infix && <T <= Scalar> (T $x, T $y) T;
    sub :infix /               (Num $x, Num $y) Num;

T binds to the join of the actual argument types and is capped by its bound.
Measured, that reproduces every row in both groups:

    T <= Num      Add(Int,Int)=Int  (Int,Num)=Num  (Str,Int)=Num
                  (Str,Str)=Num     (Boolean,Int)=Num
    T <= Scalar   And(Int,Int)=Int  (Str,Int)=Str  (Str,Str)=Str

and the join-vs-fixed distinction needs no attribute after all: a joining op
MENTIONS T, a fixed one does not. `Divide` writes concrete `Num` and gets the
flat answer for free.

This also explains what `%RESULT_IS_JOIN` has been all along -- the set of ops
whose signature is polymorphic -- and why the bound and the "cap" were always
the same type. They are one thing: T's upper bound.

## Problem 2: perl cannot parse it

Measured on 5.42.0, three of the four pieces are rejected:

    sub f ($x) Num { }      syntax error near ") Num"
    sub f (Num $x) { }      "A signature parameter must start with '$', '@' or '%'"
    sub f ($x);             syntax error near ");"      (no bodyless signature)
    sub f :lvalue ($x) { }  OK -- attributes parse

So a declaration file cannot be a perl file, and `declare()` cannot be reached
by writing perl that perl compiles. That is not fatal -- a .d.ts is not
JavaScript either -- but it means the syntax needs its own parser, and that is
the bulk of the work rather than an afterthought.

## What exists today

`B::SoN::TypeLibrary::declare($name, { operands => [...], result => '...' })`
is the programmatic form, landed and measured: a declaration moves a callsite
from Unknown to Num in a real graph. The syntax above is a FRONT END for it,
and nothing else needs to change to adopt one.

## Remaining work

1. Confirm a bounded type variable (`<T <= Num>`) covers every joining op, not
   just the seven probed here, and that nothing needs two independent
   variables. If it holds, %RESULT_IS_JOIN disappears into the signatures.
2. A parser for the declaration file, producing `declare()` calls.
3. `:infix` and friends map a declaration onto an IR op name, so a declared
   `+` lands on `Add` rather than on a sub named `+`.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
