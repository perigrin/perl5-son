# A declaration syntax for signatures

perigrin's ideal spelling:

    sub :infix + (Num $x, Num $y) Num;

It is the right shape, and it makes "an operator is a function with a weird
spelling" SYNTACTIC rather than merely architectural: `:infix` is the spelling,
and everything else is an ordinary signature. Two things have to be settled
before it can be implemented.

## Problem 1: a flat return type cannot express the rows we have

    Add(Int,Int)    = Int        <- the JOIN of its operands, capped at Num
    Add(Int,Num)    = Num
    Add(Str,Int)    = Num
    Divide(Int,Int) = Num        <- FIXED; 1/2 is not an Int

`Add` and `Divide` both "return Num" in the loose sense, and the proposed
syntax spells them identically. Writing `Num` for Add would mistype every
integer addition in the corpus -- `%RESULT_IS_JOIN` exists exactly because the
two differ.

So the return position needs to say WHICH of the two it is. The distinction is
already in the table as a separate set; the syntax has to carry it. Sketches,
none chosen:

    sub :infix + (Num $x, Num $y) Num;        fixed -- wrong for Add
    sub :infix + (Num $x, Num $y) join Num;   join, capped at Num
    sub :infix + (Num $x, Num $y) <=Num;      cap notation
    sub :infix + (Num $x, Num $y) $x|$y;      name the operands joined

The third fact the table keeps -- `operands`, what the op REQUIRES of its
inputs, which is what lets a use site type an untyped operand -- IS covered by
the parameter list, so the signature carries two of the three facts naturally.

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

1. Decide how the return position spells join-vs-fixed (Problem 1). This blocks
   the syntax being correct rather than merely parseable.
2. A parser for the declaration file, producing `declare()` calls.
3. `:infix` and friends map a declaration onto an IR op name, so a declared
   `+` lands on `Add` rather than on a sub named `+`.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
