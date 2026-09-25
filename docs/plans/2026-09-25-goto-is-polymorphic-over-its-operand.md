# `goto` is polymorphic over its operand, and T1 should resolve it

**Date:** 2026-09-25
**Status:** DECIDED, not built. Scoped from measurement while sizing step 2
of the corpus plan.

## The defect in the current refusal

One message covers five constructs:

    GAP: `goto` transfers control and is not compiled; the jump, the
         statements it skips, and the label would otherwise be dropped
         with no diagnostic

pvm's own case title says it better than our message does: "`goto` is one op
name over unrelated constructs."

I classified it a FACT on the grounds that "perl defers it". THAT IS WRONG,
and wrong three times over -- measured below. It was our refusal message
read back as if it were evidence.

## Measured on 5.42.0

### The op is one name; the OPERAND decides the construct

    goto LOOP      d  <"> goto("LOOP") v        label CONSTANT on the op
    goto $where    7  <1> goto vKS/1            label a runtime OPERAND
    goto &inner    2  gv[IV \&main::inner] -> rv2cv[AMPER] -> srefgen -> goto
    goto &$c       9  padsv[$c]            -> rv2cv[AMPER] -> srefgen -> goto

`goto LABEL` defers NOTHING: the label is baked into the op and the target is
marked `nextstate(LOOP: main 2 ...)`. Both visible at compile time. The
`&name` and `&$ref` forms share an op chain and differ only in whether the
operand comes from a `gv` or a `padsv`.

### What the operand's TYPE selects, at runtime

    goto $coderef    tail call -- identical to goto &$c
    goto "i"         Can't find label i     <- a Str is tried as a LABEL,
                                               never as a sub name
    goto "T"         jumps to label T

### `goto &sub` semantics, which any lowering must preserve

    @_ passes IMPLICITLY        tail(1,2) -> inner sees (1,2)
    the frame is REPLACED       caller depth 1 via goto, 2 via call
    the callee is STATIC        for &name; a value for &$ref

The frame replacement IS OBSERVABLE, so lowering `goto &inner` as
`return inner(@_)` would be a silent miscompile:

    sub probe { join(",", map { (caller($_))[3] // 'undef' } 0..2) }
    via_goto()  ->  main::probe,undef,undef
    via_call()  ->  main::probe,main::via_call,undef

`@_` is NOT an implicit pass-through of the entry arguments -- it is whatever
the frame holds AT THE JUMP:

    sub g  { @_ = ("replaced"); goto &callee }   ->  got(replaced)
    sub g2 { push @_, "extra";  goto &callee }   ->  got(orig extra)

Good news for the lowering: reading `ArgsSource` at the goto's control
position already gives exactly that. No new vocabulary for the arguments.

### A dynamic callee is not a problem we refuse

An ordinary coderef call ALREADY lowers, with the callee as a VALUE input:

    sub o { my $c = $ENV{X} ? \&a : \&b; return $c->(@_) }

      6 TernaryExpr  Unknown        <- the callee, genuinely dynamic
      8 Call         in=[6,7]       <- callee as an input, not a static name

So "the target varies at runtime" is not a refusal criterion anywhere else in
the IR, and `goto &$ref` is the same shape plus a variable lookup.

### Labels ARE enumerable at T1

    perl -MO=Concise,-exec   ->   nextstate(A:   nextstate(B:

So even the dynamic-label case can be DESCRIBED: the label set is in the
optree. What it needs at runtime is a lookup from a string to one of them.

A dynamic label can also leave the current sub. Measured: `goto $w` inside a
sub jumped to a label in the enclosing file scope and fell through to the
call again, printing three times. Inter-procedural, and cyclic.

## THE LAYERING CORRECTION

perigrin's, and it is the reason the FACT classification kept looking
plausible: I let a LOWERING difficulty become a TRANSLATION refusal.

    A T1 GAP means "I cannot say what this program does."
    It does NOT mean "I cannot see how a backend would execute this."

By that test all five forms are lowerable at T1. The string-to-label lookup
is real, but it is a T2 cost. Refusing at T1 makes the decision for every
consumer, including ones that could handle it.

The genuine T1 FACTs are elsewhere -- `*FH = shift`, where perl itself defers
which slot is aliased and nothing in the program says.

## THE DECISION: resolve the polymorphism, emit distinct nodes

`goto` dispatches on its operand's type at runtime (pp_goto branches on the
SV). The constructs are unrelated: a tail call and a label jump differ in
what happens to the frame, what is observable afterwards, and whether the
target is a value or a program location.

T1 RESOLVES THE DISPATCH rather than preserving it, because we already carry
the operand's stamp and a polymorphic wire node would force every consumer to
re-derive a question we have the answer to -- and would stop chalk declining
the hard case without first doing the analysis to discover which case it is.

    CodeRef operand      Call(callee, ArgsSource) with tail => 1
    constant label       a static control edge
    Str operand          a dynamic-label jump node

Then chalk pattern-matches on node kind and declines what it cannot lower,
which is the refuse-or-lower contract operating at the right layer.

### The one shape that may still be a T1 FACT

An operand stamped `Scalar` or `Unknown`, where the program does not say
WHICH construct it is until runtime. Not "hard to lower" but genuinely
undetermined. UNMEASURED whether this occurs in practice or is theoretical.

### What this hands chalk

Removing a producer refusal exposes consumers that have no rule for the new
shape -- see [[removing-a-gap-can-create-a-miscompile]], where making
`*crackers = \@SRC` translate turned a refusal into a silent wrong answer.
The wire must carry enough for chalk to RECOGNISE and decline the dynamic
label case, rather than guess at it. Distinct node kinds are what make that
possible.

## Effect on the corpus milestone

pvm's `goto` case mixes `goto SKIP` and `goto $t` deliberately, so it stays
refused until the Str form lands. But `goto` moves off the "permanent FACT"
list and onto the work list.

## A pattern worth noting

Three FACT classifications dissolved under measurement in one sitting --
`goto LABEL`, `goto &$ref`, `goto $coderef`. Each was believed on the
strength of our own refusal message. The 13-kind audit's other FACTs deserve
the same treatment; `map` contribution arity, which leads the PerlOnJava
ranking at 11 files, is the next one to re-examine.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
