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

### What fits instead: a bounded type variable -- AT T2, NOT T1

Bounded polymorphism does describe the rule:

    sub :infix +  <T <= Num>    (T $x, T $y) T;
    sub :infix && <T <= Scalar> (T $x, T $y) T;
    sub :infix /                (Num $x, Num $y) Num;

T binds to the join of the actual argument types, capped by its bound, and that
reproduces every measured row in both groups.

BUT perigrin: the polymorphism %RESULT_IS_JOIN measures is T2 polymorphism.
At T1 it is mostly just a supertype in the lattice. Measured, and he is right:

    my $i = 2; my $f = 1.5; my $s = "x";
    $i + $i   ->  wire node {op=>Add, inputs=>[..], stamp=>'Int'}
    $f + $i   ->  stamp Num
    $s + $i   ->  stamp Num

Every stamp that reaches the wire is a CONCRETE lattice member. Surveyed across
two files, the whole stamp vocabulary is Int/Num/Str/Scalar/Boolean/Array/
ArrayRef/HashRef/Glob/GlobRef/Regex/ScalarRef/Undef/Unknown -- no type variable
appears anywhere, and an Add node is exactly

    { id => 3, inputs => [2,2], op => 'Add', stamp => 'Int' }

The join rule left NO trace. `%RESULT_IS_JOIN` is referenced only inside
TypeLibrary; chalk never sees it.

So T1 does not need polymorphic signatures. It applies the rule once, per node,
against the operand types it is holding, and writes down a concrete answer. The
polymorphism is a property of the OPERATOR, consumed at translation time and
discarded -- exactly like `operands`, which types an untyped operand and is
likewise never emitted.

Where a type variable WOULD be load-bearing is T2: chalk lowers one Add to
different machine instructions depending on the stamp, and a declaration it can
instantiate per callsite is a different artifact from the one T1 needs. The
`<T <= Num>` syntax belongs there.

### What this means for the declaration syntax

The syntax perigrin proposed --

    sub :infix + (Num $x, Num $y) Num;

-- is the right T1 artifact AS WRITTEN. The declared return type is the cap; T1
meets it with the operand join and stamps the node. No T, no :join attribute,
no notation for the dependency, because T1 never has to express the rule in the
general case -- only to APPLY it to the operands in front of it.

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

1. Nothing, for T1. The flat form is sufficient, since T1 applies the rule and
   emits a concrete stamp. A bounded type variable is a T2 question, and
   belongs in a chalk-side plan rather than this one.
2. A parser for the declaration file, producing `declare()` calls.
3. `:infix` and friends map a declaration onto an IR op name, so a declared
   `+` lands on `Add` rather than on a sub named `+`.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc

## A prototype determines PARSE SHAPE, and it is derivable from the string

Measured on 5.42.0, prompted by the pvm session (a Perl parser in Go) asking
whether parse shape needs its own field beside a prototype. It does not:

    no prototype    np(1,2,3)        swallows the list        LIST OPERATOR
    ()              `nil + 1`        parses as nil() + 1      NILADIC
    ($)             `one 1, 2`       parses as one(1), 2      NAMED UNARY
    (;$)            `pass;` and `pass "x";` both parse        ZERO-OR-ONE

The fourth has no slot in a list/unary/niladic enum, which is why the STRING is
the right thing to keep and the shape should be derived from it. Same reason
this project reads `prototype("CORE::$name")` rather than keeping a hand list
(memory: op-names-are-not-perl-spellings).

### The block-first form needs a LEADING `&`

    sub bf (&@) { }   bf { ... } (1,2,3)   works
    sub ao (&)  { }   ao { 42 }            works
    sub na ($@) { }   na { 1 } (2,3)       syntax error near "} ("

so it is not an option the caller may take -- without a leading `&` the block
form does not parse at all. Non-initial `&` and `\&` do NOT license it (pvm
measured these after I declined to claim them without evidence):

    sub ni ($&) { }   ni { 1 } (2)   "Not enough arguments" AND a syntax error
    sub rf (\&) { }   rf { 1 }       "Type of arg 1 ... must be subroutine
                                      (not anonymous hash ({}))"

In both, `{1}` parsed as an anonymous HASH and the failure came afterwards --
so `&` is an ordinary code-ref slot outside the first position. Anchor on a
leading `&` not preceded by a backslash; `strings.Contains(proto, "&")` gets
the negative cases wrong.

NOTE on the non-initial case: perl emits BOTH an arity error and a syntax
error, so a test that asserts "arity error, not syntax error" is testing
something perl does not promise.

### Why this is recorded here

If the declaration syntax above ever gets a parser, a prototype is a plausible
third column beside `operands`/`result` -- a signature declares arity, a
prototype declares PARSE arity, and they are different facts. `operands` is a
COERCION CEILING (`Add => operands => ['Num','Num']` means "coerce both to
Num", and `operands => []` imposes nothing), not a description of how a call is
parsed. They must not be merged.

## The circularity argument does NOT apply here (it does for a standalone parser)

The pvm session (a Perl parser in Go) reversed its plan to generate prototype
data from perl's symbol table, on perigrin's point: reading the symbol table
means libperl has already parsed the text, and a Perl parser that must run Perl
to parse Perl is circular. Their answer is to parse the module's own source --
`Test/More.pm` is text on disk, and everything they need is on the `sub` line.

Right for them, and it does not transfer, for two measured reasons:

1. **We are a compiler BACKEND.** `perl -MO=SoN file.pm` -- perl has already
   parsed the file into an optree before we run, and that optree IS our input.
   The dependency they are eliminating is the one we are built on. There is no
   circularity to break.

2. **`CORE::` is not a module.** Their fix is "parse the module's text
   instead", and that has no analogue here:

       Test/More.pm   ->  /…/lib/perl5/5.42.0/Test/More.pm     TEXT ON DISK
       CORE           ->  $INC{"CORE.pm"} is undef              THE INTERPRETER

   `prototype("CORE::$name")` asks the interpreter about its own keywords.
   There is no source file to parse, so the alternative does not exist.

Our single use of it (lib/SoN/Deparse.pm) is a REFUSAL predicate, not a data
source: it asks whether a name is a perl keyword at all, so the deparser can
refuse an op with no Perl spelling rather than emit a call to a sub that does
not exist. That is exactly the case the
[[op-names-are-not-perl-spellings]] memory records a hand-maintained list
getting wrong.

Their three practical consequences are worth recording even though they do not
bind us, because they would bind any offline generation step we ever add:
uninstalled dependencies make a repo unanalysable, the data pins to whichever
module version was on the generating machine, and local modules get no
coverage.
