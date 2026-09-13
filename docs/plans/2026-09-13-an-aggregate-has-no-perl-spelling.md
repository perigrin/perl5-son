# An aggregate has no Perl spelling, and that is the whole defect

**Date:** 2026-09-13
**Status:** OPEN. Found by the deparse oracle. Scoped here; not started.

## What I claimed, and what is actually true

I first said `Assign(Subscript(ArrayLiteral, 0), 7)` "conflates the container's
identity with its contents". **That is wrong**, and measuring it says so:

    my @a=(1,2,3); my @b=(1,2,3); $a[0]=9; print "$a[0] $b[0]"

     5 ArrayLiteral  in=[2,3,4]      <- @a
    14 ArrayLiteral  in=[2,3,4]      <- @b, a DISTINCT node

`ArrayLiteral` is not hash-consed, so two arrays with identical contents are
two nodes. Container identity is preserved exactly.

The memory chain is also sound. Measured on two arrays and two stores:

    13 Assign     target container=4    (@a)
    14 Assign     target container=8    (@b)
    15 Subscript  container=4  mem=14
    19 Subscript  container=8  mem=14

Both reads thread to the last store, `14`, so `@a`'s read is ordered against a
store into `@b`. That is CONSERVATIVE -- one global memory chain rather than one
per container -- but it never reports a wrong value. It only forbids reordering
that would have been legal.

So the graph knows which containers are distinct, and knows the store order.

## The actual defect

**There is no way to WRITE the container in Perl.** An aggregate is represented
by the `ArrayLiteral` that initialised it, and Perl has no syntax for "the array
whose initial contents were (1,2,3)". So an element store renders as

    (1,2,3)[0] = 7        not assignable

and the emitter refuses. Reads survive because a list slice `(1,2,3)[0]` is
legal; only stores need a name.

This is the same loss `keys`/`values`/`each` hit from the read side
(docs/plans/2026-09-06) -- there the container had no name to hand the builtin;
here it has no name to assign through.

## Why the fix is probably small

`PadAccess` already carries `varname` and renders as `$x`. The mechanism exists
for scalars and was never extended to aggregates:

    lib/SoN/IR/Node/PadAccess.pm:11:    field $varname :param :reader;
    lib/SoN/IR/Node/ArrayLiteral.pm     (no fields at all)

The name is available where the node is built -- `padav` carries the pad targ
and the pad carries `@a`:

    padav  targ=1  name=@a

And the NAMED case is already distinguishable from the anonymous one by the
stamp, with no new discriminator needed:

    my @a = (1,2)   ArrayLiteral stamp=Array      pad-bound
    my $r = [3,4]   ArrayLiteral stamp=ArrayRef   anonymous

There are five `make('ArrayLiteral')` sites, so this is the "one operator, N
declaration sites" shape -- add the field once, thread it at the sites that
have a slot, and leave it absent elsewhere.

## What this does NOT reopen

The hard part of `padav` is deciding WHICH OPERATION a read is, and that is
already solved. The flags do not separate the cases -- the handler documents it
with measurements:

    @a = ()          f=0xb3  REF|MOD  want=LIST     target
    my @a = (1,2,3)  f=0xb3  REF|MOD  want=LIST     target
    for my $x (@a)   f=0x32  REF|MOD  want=SCALAR   source
    shift @a         f=0x33  REF|MOD  want=LIST(!)  operand
    scalar(@a)       f=0x02  --       want=SCALAR   read

> THE FLAGS DO NOT SEPARATE THESE ... Two attempts keyed on flags each broke a
> different case (foreach sources, then shift's element stamp).

The producer settled it by looking at the CONSUMER one op away. Adding a name
field does not touch that decision, and must not be allowed to.

## What it might also close

Both of these are "the reader cannot name the container", so a name may close
them too -- to be verified, not assumed:

  - `keys`/`values`/`each` do not observe stores (docs/plans/2026-09-06)
  - the live refusal for a list-context read of a MUTATED array, whose message
    already says "the binding is the pre-mutation literal"

That last one is the more interesting test: a named, memory-threaded aggregate
read is exactly what "the elements of @a as they now are" needs, and that
refusal exists because no such node exists.

## Acceptance

The deparse oracle already has the failing cases. `t/deparse-memory.t` asserts
the refusal today; when this lands, those subtests become round-trips:

    my @a=(1,2,3); $a[0]=7; print $a[0]      perl: 7
    my %h=(k=>1); $h{k}=9; print $h{k}       perl: 9

and the emitted program must contain `@a`, not a temporary -- a temporary would
be a different container from the one the reads name, which is the failure the
refusal exists to prevent.
