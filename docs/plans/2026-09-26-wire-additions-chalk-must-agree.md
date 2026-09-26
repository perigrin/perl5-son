# Three wire fields chalk must agree to

**Date:** 2026-09-26
**Status:** PROPOSAL. Each is blocking a construct measured in pvm's corpus,
each was attempted and reverted rather than guessed, and none can be recovered
by a consumer.

## Why these three together

Three separate attempts this session ended at the same wall: a fact the
producer knows, no consumer can derive, and the wire has no field for. That is
the shape [[a-t2-difficulty-is-not-a-t1-refusal]] says is a T1 obligation --
the answer IS present in the program -- so the refusals are artifacts of the
wire, not facts about Perl.

Verified absent on both sides: `SoN::IR::Node::Call` has no enclosing-package
field, `SoN::IR::Node::Parameter` has `index`/`name`/`sigil` and no default,
and `Chalk::IR::Node::Call` has `dispatch_kind`, `name`, `paren_form`,
`target`, `param_names`, `class_name`, `resolved_graph` -- none of them these.

## 1. `Call.enclosing_package` -- for SUPER:: dispatch

    package Derived;
    our @ISA = ("Base");
    sub both { my $s = shift; return $s->SUPER::hi() . "/" . $s->hi() }

`$o->SUPER::hi()` compiles to `method_super[PV "hi"]` -- the name is a constant
on the op, the same shape as `method_named`. What differs is WHERE IT LOOKS:
the @ISA of the package the call is WRITTEN IN, not the invocant's class.

Our graph records `Call(dispatch_kind=super_method, name=hi)` with `Derived`
nowhere, so an emission placing the statement in `main` looks up main's @ISA
and dies. Attempted with the kind and the `->SUPER::name()` spelling, both
correct and both insufficient; reverted.

WHY IT MATTERS MORE THAN A REFUSAL: when the child overrides the method, a
plain call reaches the child and SUPER:: reaches the parent. A lowering that
loses the package answers with the CHILD's method -- a silent wrong answer, not
a loud failure.

## 2. `Parameter.default` -- for a signature default

    sub add_up ($a, $b = 3) { $a + $b }
    add_up(1)     # perl: 4

Our graph is

    Parameter index=0 name=$a sigil=$
    Parameter index=1 name=$b sigil=$
    Add       in=[1,2]

with the `3` nowhere, so a consumer reading the parameters gets undef for the
missing argument and computes 1. Found via pvm's corpus, and specifically the
part our own fixtures could not find: every fixture we had passed both
arguments.

The node needs somewhere to carry the default's VALUE NODE -- it is an
expression, not a literal (`$b = compute()` is legal), so a field holding a
node id rather than a scalar.

## 3. The `goto` node kinds -- scoped separately

docs/plans/2026-09-25-goto-is-polymorphic-over-its-operand.md settles that T1
should resolve `goto`'s polymorphism and emit distinct kinds: a tail call for a
CodeRef operand, a static control edge for a constant label, a dynamic-label
jump for a Str. Four of five forms are lowerable.

`tail` is not a Call attribute anywhere in chalk's IR layer and there is no
label-jump class, so this needs classes on their side before the producer stops
refusing.

## THE COORDINATION PROBLEM, stated plainly

chalk reads our `lib/` LIVE -- `son-corpus-wide.t:17` is
`$ENV{PERL5_SON_LIB} // "$HOME/dev/perl5-son/lib"` -- and
`Serialize/JSON.pm:568` emits `version => 1` that nothing on either side
checks. There is no released wire between the projects.

So a producer change lands in chalk's suite with no gate, and
[[removing-a-gap-can-create-a-miscompile]] says what happens next: a consumer
with no rule for a new shape may render something plausible and wrong rather
than refuse. Adding a field is the safe direction (an unknown field is
ignorable); adding a KIND is not, because chalk's NodeFactory dispatches on
kind and an unknown one is a hard failure.

Ordering, therefore:

    fields first   enclosing_package, Parameter.default -- additive, chalk can
                   ignore them until it wants them
    kinds second   the goto kinds and super_method, which need chalk to add
                   classes and DECLINE what it cannot lower, before the
                   producer stops refusing

## A fourth, added 2026-09-26: a DISTRIBUTIVE reference

`\(@a)` and `\@a` are different ops and different programs, and perl spells
them apart:

    my @r = \(@a);   refgen  lK/1   preceded by `pushmark sRM`
    my $r = \@a;     srefgen sK/1   no mark

`refgen` is MARK-DELIMITED and DISTRIBUTIVE -- one reference per element:

    my @a=(10,20); my @r = \(@a);  2 refs, ${$r[0]} is 10
    my @a=(10,20); my @r = (\@a);  1 ref,  ref($r[0]) is ARRAY

The OpMap gives both `[1, 'Ref', 1, 0]`, so the generic path pops ONE operand
and builds ONE `Ref`. The distinction is absent from the graph and the emitted
program dies with `Not a SCALAR reference` on `${$r[1]}`. Corpus case 195.

THIS IS A KIND, NOT A FIELD, which puts it in the second group above. `Ref`
is a `UnaryOp`: one input, one scalar reference out. A distributive ref has a
different ARITY (N operands) and a different RESULT KIND (a list of
references), so it cannot ride on the existing node.

An attempt to pass `distributive => 1` was reverted -- the constructor rejects
it, and forcing the field through would put something on the wire that no
consumer has a rule for, which is the failure this whole document exists to
avoid.

Guards are written and TODO-marked in `t/from-optree-distributive-ref.t`,
including the regression guard that `\@a` must stay a single ARRAY ref: the
`Ref` renderer's aggregate exemption exists because `*c = \@SRC` aliases the
array, and distributing there would bind the last element instead.

## Status

No chalk session was running when this was written, so none of it has been
put to them. It is recorded here so the proposal exists whenever one is.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
