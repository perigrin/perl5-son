# A glob's slot is a type hint, not a layout

## The claim I got wrong

I refused `*FH = shift` as undecidable, on this measurement:

    sub f { *D = shift }
    f(\@V);   # a[array]  s[UNDEF]
    f(\$V);   # s[scalar]

One call site, two different aliased slots. I concluded T1 could not record
which slot is aliased.

That is wrong, and perigrin named why: the aliased slot is **wired to the
argument's type**. It is undecidable from the sub IN ISOLATION -- which is the
scope `_step` runs in -- but the whole-program pass holds every call site.

## What the four slots actually are

Not four storage locations to model. One name, and a type that says which
namespace a use of it lands in. `*D = \@SRC` is "alias D to this value, whose
type is ArrayRef"; the array-slot business is perl's implementation detail and
does not belong in the IR.

So the fact T1 must record is:

    GlobAlias(name, value)     with `value` carrying its stamp

and the slot follows from the stamp. Nothing in the IR enumerates slots.

## The evidence it is derivable

base/rs.t, all four call sites:

    main::test_string <- Constant value=TESTFILE stamp=Glob
    main::test_record <- Constant value=TESTFILE stamp=Glob

The stamp is already on the wire. What is missing is a pass that carries it
from the callsite INTO the callee's parameters.

## What exists and what does not

`lib/B/SoN.pm` types in one direction only:

    _stamp_calls_from_callees   callee return type -> callsite     EXISTS
    _floor_element_removals     bare `shift` -> TypeLibrary floor  EXISTS
    _floor_param_fields         class-field params -> Scalar floor EXISTS
    callsite argument -> callee parameter                          MISSING

`_floor_element_removals` is exactly where the loss happens: bare `shift` on an
`ArgsSource` has no element nodes to read, so it takes the generic `Scalar`
floor and the argument's real type is discarded.

## What the first attempt proved -- and where it failed

I built `_stamp_args_from_callsites`: collect each callee's callsite arguments,
`Stamp::join` them, and give a bare `shift` of an `ArgsSource` the result. It
worked exactly as predicted --

    sub f { my $h = shift; return $h }   f(*STDOUT);   -> shift stamped Glob
    sub f { my $n = shift; return $n }   f(7);         -> shift stamped Int
    ... plus f("x");                                   -> widened to Str

-- and `t/wire-selftyped-stamp.t` failed, correctly.

THE VISIBLE CALLSITES ARE NOT ALL THE CALLSITES. A named package sub is
reachable from outside the translation unit, and the pass assumed otherwise.
Measured:

    # Mod.pm, which B::SoN sees:  sub f { my $n = shift; $n * 2 }  f(3);
    # another file entirely:      print Mod::f(0.5);   -> 1

`f(3)` is the only callsite in the unit, so the pass derived `Int`, and the
existing test's guard -- "the product caps ITSELF at Num; f(0.5) is legal" --
is exactly the case that breaks. Reverted rather than left in.

THE ANALYSIS IS STILL RIGHT, the WORLD ASSUMPTION is what is missing. Nothing
in the wire says whether a sub is externally reachable: `not_package=` is an
emission filter, not a closed-world claim. Until something does, joining
callsites is only sound for a sub that cannot be called from outside.

Candidates, none yet measured:
  - an anonymous sub, or one never installed in a stash, has no external name
  - a `my sub`, likewise
  - an explicit closed-world flag from the caller of B::SoN

## Remaining work

1. A soundness condition for "these are all the callsites" -- see above. This
   is the blocking step; steps 2-4 are written and were reverted only for want
   of it.
2. Then the join pass, gated on that condition.
3. `GlobAlias(name, value)` as a node, replacing the current refusal, ONLY when
   the value's stamp is known. An Unknown stamp keeps the GAP -- honest, and
   consistent with [[unknown-is-write-once-not-a-sentinel]].
4. Deparse a `GlobAlias` whose value is stamped Glob as `*NAME = VALUE`.

## What stays refused, and why

An alias whose argument types DISAGREE across call sites meets to Unknown, and
that is a real refusal rather than a missing feature: the program genuinely
aliases a different namespace per call.

The alias is also program-wide and OUTLIVES the sub -- measured, a sibling sub
reading `<FH>` sees it. So the lowering is a real glob assignment, not a
rewrite to a lexical handle. base/lex.t is the case that proves a handle-only
model would be wrong: `*R::crackers = \@array`, read back as `@R::crackers`.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
