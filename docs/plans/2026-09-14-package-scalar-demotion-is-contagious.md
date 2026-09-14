# Package-scalar demotion is contagious, and `$_` is a package scalar

**Date:** 2026-09-14
**Status:** FIXED.

## The setup

Reads of a package scalar stopped being value-forwarded once ANY sub in the
program writes it (`_package_scalars_written`). That change was correct and
necessary -- without it, `our $n = 0; sub bump { $n++ } bump(); print $n`
printed 0, because the read resolved to the literal the declaration bound and
the callee's write was unreachable from it.

## What it broke

`$_` IS A PACKAGE SCALAR. So a foreach body containing `$_ = ...` marks
`$main::_` written program-wide, and every read of `$_` anywhere stops
forwarding -- including the one the foreach itself just bound to the element
it aliases. Measured on `my @a=(1,2); for (@a) { $_ = $_ * 10 }`:

     8 Subscript in=[4,7]   the element the loop bound
    10 EntryDef  in=[9]     the body's read, memory = MemStart   <- unbound
    12 Multiply  in=[10,11] multiplied the UNBOUND alias
    16 Assign    in=[8,12]  stored undef*10 into the element

perl gives `10 20`; the emitted program gave `0 0`. The write-back machinery
was already correct and already fired -- only the READ was wrong.

`for (@a) { print $_ }` was correct throughout, because nothing writes `$_`
and the key is never demoted. That is what makes this the write path's bug
rather than foreach's.

## THE CONTAGION, which is the part worth remembering

The demotion is program-wide, so a write to `$_` in ONE loop broke a DIFFERENT
loop elsewhere that only READS it. Measured: a range loop `for (1..3) { ... }`
that never assigns `$_` still produced `000`, because some other loop in the
same file assigned it.

So the blast radius of "this variable is written somewhere" is every read of
that variable in the program -- and for `$_`, that is potentially every loop.
A whole-program fact used as a per-read decision has no locality, and `$_` is
the variable where that hurts most because every construct shares it.

## The fix

`@ALIAS_BOUND_KEYS` -- a counted stack of package-scalar keys an enclosing
foreach currently aliases, pushed with `local` around the body walk. A read
whose key is actively aliased is forwardable again, because the alias binding
IS the reaching definition. A pad iterator (`for my $x (@a)`) is unaffected:
its key is a targ, which no package-scalar read looks up.

Both the array and the range lowering push it. The range form had the
identical defect and no write-back to compensate, since a range has no
container to store into.

## What this suggests generally

A whole-program demotion is a blunt instrument, and the narrower question is
usually "can a write REACH this read". Where that is too expensive, the
mitigation is what was done here: let a construct that establishes a binding
say so, and let the read trust it. Any future whole-program fact used at a
read site should be checked the same way -- against a construct that binds the
same name locally.

## Tests

`t/from-optree-foreach-alias-binds.t`, covering the array form, the range
form, the contagion case (write in one loop, read in another), and the
read-only and explicit-variable forms that must not regress.

The graph assertion is deliberately NOT spelled "no EntryDef sits at
MemStart". That form goes VACUOUS once the fix lands -- no such node survives,
so it passes by finding nothing. It asserts positively that the operand is the
element Subscript, indexed by the induction Phi.
