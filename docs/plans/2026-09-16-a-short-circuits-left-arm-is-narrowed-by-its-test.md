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

## Remaining work

1. A failing test: `undef || "x"` should stamp Str, not Scalar.
2. Implement the subtraction in the Or/DefinedOr path, and measure the corpus.
   The likely win is anywhere `$x ||= default` or `$h{k} // $default` feeds a
   typed consumer -- both common, and both currently widening to Scalar.
3. Check whether any wire consumer depends on the current Scalar; chalk reads
   these stamps, and a narrower one is new information rather than a fix to it.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
