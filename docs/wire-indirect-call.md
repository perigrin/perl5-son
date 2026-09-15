# Call.dispatch_kind = "indirect" — node contract

A fourth `dispatch_kind` landed in this session. A consumer pinned before it
sees such calls as `dispatch_kind="direct"` with `name="unknown"` and **no
inputs** — a call to a sub nothing defines.

## Signature

    op:     "Call"
    inputs: [ callee, arg... ]
    fields: { dispatch_kind: "indirect", name: "" }

## What it says

The callee is a **value**, not a name. Input 0 is that value; the rest are the
arguments.

The other three kinds all name their callee:

    builtin    name is the perl builtin        inputs are args (+ memory)
    direct     name is a `methods` key         inputs are args
    method     name is the method              inputs are [invocant, args...]
    indirect   name is EMPTY                   inputs are [callee, args...]

## Why it exists

`$f->()` where `$f` is a parameter, an element, or a field has no name to
resolve. The producer resolves a callee three ways — a stash name, a pad
binding to an AnonSub, the entersub's own callee gv — and fell back to the
literal string `'unknown'` when none applied, dropping the callee entirely:

    sub take { my $f = shift; return $f->() }

    3 Call builtin shift    in=[ArgsSource, MemStart]
    4 Call direct  unknown  in=[]          <- the callee is gone

A consumer emitting that calls `unknown()`. The producer's own comment at the
fallback already said what it cost: "the AnonSub was popped and dropped -- the
exact silent wrong answer the old refusal was written to prevent."

## Consuming it

`$callee->(args)`. The callee is an ordinary value input, so whatever spells it
— a variable, an element read, another call's result — spells it here.

NOTE that a `Call` with an empty `name` is well-formed ONLY for this kind. For
the other three an empty name is a real defect, so a reader should key the
allowance on the kind rather than on the name being absent.
