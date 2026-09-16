# A short-circuit's left arm is narrowed by its own test

perigrin: `||`'s return type is the type of the value that can coerce to True.

That is right, and it names a real imprecision on the wire today.

## What `||` actually returns

Measured -- the arm is returned UNCHANGED, not coerced to a boolean:

    "0 but true" || "FB"  ->  "0 but true"     left arm, true
    "0"          || "FB"  ->  "FB"             left arm false
    ""           || "FB"  ->  "FB"
    undef        || "FB"  ->  "FB"
    [1,2,3]      || "no"  ->  ARRAY(0x...)     still an ArrayRef

So the result type is "the type of whichever arm was returned", which is why
the join is T1-mandatory (see the RESULT_IS_JOIN note). But the LEFT arm is
only returned when it passes the test, and that narrows it.

## The narrowing removes values, and exactly one type

Per type, which values survive truthiness:

    Int    all but 0            -> still Int
    Num    all but 0.0          -> still Num
    Str    all but "" and "0"   -> still Str
    Ref    all refs are true    -> still Ref
    Undef  NONE                 -> ELIMINATED

For every type except Undef the narrowing is value-level and the lattice cannot
express it. Undef is the exception, and it is the one that matters: it is a
whole lattice member that the left arm can no longer be.

## The imprecision this causes

    my $u = undef; my $r = $u || "fallback";

    wire today:  Or(Undef, Str) stamp=Scalar
    truthful:    Str

`Scalar` because join(Undef,Str) = Scalar -- their only common supertype. But
the result is never Undef, so joining the left arm AS DECLARED joins a branch
that cannot be taken. Str is correct and strictly narrower.

## The rule

    Or / And:    join( left MINUS Undef, right )
    DefinedOr:   join( left MINUS Undef, right )

`//` tests definedness rather than truth -- `0 // "fb"` is 0, where
`0 || "fb"` is "fb" -- so the two differ on which VALUES they keep, but both
eliminate exactly Undef from the left arm. Same lattice operation, for two
different reasons.

`And` is the mirror: its left arm is returned only when FALSE, so what survives
is Undef, "", "0", 0 -- which spans Undef/Str/Int and does not narrow to
anything in this lattice. So And gains nothing and should keep the plain join.

## Where this is polymorphism

perigrin: this may be where true polymorphism comes back in. It is -- but of a
restricted kind. The result type is a function of the operand types (which is
what the earlier `<T <= Num>` sketch was reaching for), except the function is
not `join`, it is

    f(L, R) = join( L \ {Undef}, R )

This does NOT need a type variable in the declaration, because it is a property
of the OPERATOR, not something a caller instantiates. It is a third column in
the row -- alongside `operands` and `result` -- saying how the result is
computed from the operand types.

## CORRECTION: the desugaring is exact, and the win is ~nothing

perigrin: False || False returns False, so `$x || $y` is exactly equivalent to
`if ($x) { $x } else { $y }`.

That desugaring is exact and it corrects a sloppy sentence above. `undef ||
undef` IS undef -- but via the RIGHT arm, taken because the left was falsy. The
left arm still cannot be the result when it is undef; the RESULT can be undef
whenever the right arm is. The rule `join(L \ {Undef}, R)` already says this,
since the subtraction applies only to L. But it was easy to read the earlier
text as claiming the result is never Undef, which is false.

More importantly, the desugaring exposes how narrow the win is. The subtraction
is only EXPRESSIBLE when the left arm is stamped EXACTLY `Undef`:

    Or(Undef,  Str)  ->  Str      the whole left arm vanishes
    Or(Scalar, Str)  ->  Scalar   unchanged: "Scalar minus Undef" is not a
                                  lattice member -- there is no "defined
                                  Scalar" type to narrow to

So it is not a general narrowing at all, it is a special case for one stamp.

MEASURED over t/base, t/comp and t/cmd -- 37 files that translate, 42
Or/DefinedOr nodes:

    left arm stamped exactly Undef:  1

One node. And the common real shape has an Unknown left arm, where there is
nothing to subtract either:

    my $u = @ARGV ? $ARGV[0] : undef;
    my $a = $u || "fb";
      ->  Or(TernaryExpr/Unknown, Constant/Str) stamp=Unknown

A left arm stamped exactly Undef means the producer PROVED it undef, and then
`$x || $y` is a constant expression theprogrammer would not have written.

## Verdict

Not worth implementing. The rule is correct and it buys one node in the whole
corpus. Recorded so the reasoning is not redone: the blocker is not effort, it
is that the lattice has no "defined X" type, so the narrowing cannot generalise
past the single Undef stamp.

If a `NonUndef` or a defined-ness refinement ever enters the lattice -- which
is a real design option, and what perigrin's "true polymorphism" instinct was
pointing at -- this becomes general and worth revisiting. Until then it is a
special case dressed as a rule.

## Remaining work

NONE, as measured. Revisit only if the lattice gains a defined-ness refinement
(a `NonUndef`, or Str/Int split by definedness), at which point the subtraction
generalises beyond the single exact-Undef case and the corpus count should be
re-measured before implementing.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
