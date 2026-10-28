# Census cause: an inlined argument the callee reads as another type

**Cause:** "an inlined argument is a X where the callee reads a Y -- a
coercion between them would not keep the value" (060 075 082 201 208
224). Plus, along the way, 230 (a push through a reference) and 060's next
refusal (an arity die inside an eval).

**Round-tripped:** 060 201 230 (326 -> 329). 075 next hits `scalar(@b)` of
a list-returning call (Length of a List); 082/208/224 are references.

## What the stamp was

B::SoN's backward inference (`_infer_backward`) types a parameter by what
its uses require: `$v =~ /x/` makes $v Str, `$v + 1` Num. That is the
callee's *reading*, not what the caller passed -- and for a value that is
also tested (`defined`) or handed on (a call, a return, a store, a merge),
it was a wrong answer, not just a refusal:

- `sub f { my ($v)=@_; return ($v =~ /x/ ? "x":"-") . (defined(g($v)) ? "d":"u") }`
  with f(undef): the location read was stamped Str, unboxed to "", passed
  to g: defined. chalk printed "-d" for perl's "-u".

Producer fix: a read that a `%SEES_UNDEF` consumer (Defined DefinedOr
Call Return Phi ArrayLiteral HashLiteral Assign VarDecl -- value side) takes
is not narrowed -- **only for a parameter** (a Parameter, or a variable
bound by `my (...) = @_` / `shift`). Applied to every variable, it
untyped `$p` in `$p = g($p)` and a loop of arithmetic over it went TOP
(three suite files regressed); an Increment consumer blocked typing too
until the set was explicit.

Chalk then reads such an argument as the caller passed it (`_repr_of`),
in each consumer that read the node's stamp: numeric comparisons
(`_lower_icmp_int`, `_coerce_ref_to_num` takes Scalar/Boolean), push, the
RegexMatch subject, a Range's bounds (`_is_walked_list`, flattening), a
loop Phi nothing typed (its two values' repr, decided at each lowering), a
jump merge. Where a use-typed stamp remains and every consumer only reads
the value as that reading (`_read_only_as_its_stamp`), a caller's undef or
integer is coerced to it.

## Pre-existing miscompiles found (reported)

- `sub f { my ($v)=@_; return $v } defined(f(undef))` was true: the
  call kept its Unknown stamp; an Undef value now stamps it.
- A frozen Count was re-lowered at its use, after a later push through the
  same reference (230's shape with a literal push: x1x2 for x0x1). Served
  frozen now -- but only where a recorded store supersedes its version: a
  push onto a *field* array carries no memory input in B::SoN, and served
  frozen the count missed it (`return scalar @items` gave 1 for 2).

## Also

- An arity die (`f()` too few for a signature) inside a block eval whose
  $@ nothing reads, in void context: a branch to the eval's catch
  (`_die_into_eval`), as a method on a non-object already was.

## Lessons

- A producer stamp change ripples through every chalk consumer that reads
  `->stamp` instead of `_repr_of`. Measure with the full check, then fix
  the consumers one regression at a time; narrow the producer rule to the
  values that actually have the hazard (parameters).
- I edited the producer while a check's suite was reading it, and ran
  `pkill -f`, which killed my own shell. Both rules exist for a reason.
