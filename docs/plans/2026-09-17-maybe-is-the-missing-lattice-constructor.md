# Maybe[T] is the missing lattice constructor

perigrin, after the readline correction: really it'd be Scalar because we have
no way currently of saying Str|Undef -- or maybe `Maybe[Str]`.

That names a gap this session hit THREE times from different directions, each
time concluding "the lattice cannot say this" and stopping:

1. **readline's scalar reading.** `my $l = <$fh>` is a Str, or undef at EOF.
   join(Str, Undef) = Scalar, because Undef is a SIBLING of Str under Scalar,
   not a subtype. Scalar is correct and loose; Str would be WRONG, since the
   EOF undef is exactly what every read loop tests for.

2. **`||`'s left arm.** `$x || $y` returns the left arm only when it is TRUE,
   which eliminates Undef from it -- but "Scalar minus Undef" is not a lattice
   member, so the narrowing is expressible ONLY when the left arm is stamped
   exactly Undef. Measured: 1 node in 42 across t/base, t/comp, t/cmd. Recorded
   as not worth implementing FOR THAT REASON.

3. **the failure-returning builtins.** binmode is ok=1 / fail=undef; open,
   shift, pop, the file tests and Delete are the same shape. 12 TypeLibrary
   rows are stamped `Scalar` today, several of them purely because a failure
   undef is possible.

## Why Maybe[T] rather than a union

`Str|Undef` generalises to a union type, which needs N^2 pair members or a
real union representation. `Maybe[T]` is ONE parameterised constructor covering
all 14 scalar-ish members, and it is the only union perl actually produces at
this granularity -- every case above is "a T, or undef", never "an Int or a
Regex".

Placement, if built:

    T     <: Maybe[T]
    Undef <: Maybe[T]
    Maybe[T] <: Scalar          it is still a scalar

so join(Str, Undef) becomes Maybe[Str] instead of Scalar -- strictly narrower,
since Maybe[Str] <: Scalar. Nothing currently correct becomes wrong; answers
that are loose today become tight.

## What it would unlock

- readline stamps Maybe[Str], and a `defined` guard could narrow it to Str --
  which is the flow-sensitive narrowing case (2) actually wanted.
- The 12 Scalar rows split into the ones that are genuinely any-scalar
  (Wantarray, CellRead) and the ones that are Maybe[Bool] / Maybe[Str].
- chalk gets "this is a string or null" instead of "this is any scalar", which
  is the difference between one branch and a full scalar dispatch.

## Cost, unmeasured

- Stamp.pm's %PARENTS is a flat name -> parents map. A parameterised type needs
  either a structured representation or a naming convention ("Maybe[Str]" as a
  key, generated on demand), and join/meet/is_subtype_of must understand it.
- `%STAMP_TO_REPR` on the chalk side has to answer for it, so this is a WIRE
  CHANGE and chalk must agree before it lands.
- The write-once Unknown guard is unaffected -- Maybe[T] is a concrete member,
  not a sentinel.

## Recommendation

Worth doing, and NOT yet. It is a wire change with a peer consumer, and the
three cases above are each individually small (1 corpus node for the ||
narrowing; readline's Scalar is correct, just loose). The argument for it is
cumulative rather than any single win, which is exactly the kind of change that
should be proposed to chalk with the three cases attached rather than landed
unilaterally.

Blocking question for chalk: does its lowering distinguish "Str or null" from
"any scalar" usefully enough to pay for a parameterised stamp?

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
