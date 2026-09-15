# Region.eval_entry — node contract

`Region` gained an optional `eval_entry` field in `b6a72ce`. It is **absent on
every Region except a block eval's join**, so a consumer pinned before that
commit reads every existing graph unchanged — and cannot delimit a block eval.

## Signature

    op:     "Region"
    inputs: [ predecessor... ]
    fields: { eval_entry: <node index> }     present ONLY for a block eval

## What it says

The control node the protected body began **after**. The body is everything on
the control chain strictly between `eval_entry` and the Region itself.

    our $g = 0;
    our $h = 0;
    $h = 5;
    if (eval { $g = 1; 1 }) { ... }

    Region(23) in=[12]  eval_entry=11
    chain back from 12: EntryWrite 12, 11, 10, 9, Start

`12` is `$g = 1`, the one statement the eval protects. `11`, `10` and `9` are
`$h = 5`, `our $h = 0` and `our $g = 0` — all outside it.

## Why it is needed

Without it the join is recorded and the entry is not, and the statements an
eval protects are indistinguishable from those before it. There is no way to
recover the boundary from the rest of the graph: the body is ordinary chain.

Guessing is wrong in both directions, and both were measured:

  - starting too early pulls unrelated statements in. A `die` among them then
    sits inside an `eval {}` that had not yet opened in the ORIGINAL, changing
    which statements are protected;
  - starting too late leaves protected statements outside, so a die escapes.

A block eval's whole meaning is WHICH statements it protects.

## The two eval forms

Both build a single-input Region with a `Phi[value, undef]` over it — the
value, or undef if it died. They differ in what the Region's input is:

    eval "..."       Region[Coerce(Str->Code)]   the input IS the eval
                     Phi[that Coerce, undef]     eval_entry ABSENT

    eval { ...; 1 }  Region[last statement]      the input is the body's END
                     Phi[Constant 1, undef]      eval_entry PRESENT

So a reader identifies the join by the single-input Region plus the undef
second input, and then uses `eval_entry`'s presence to tell the forms apart.

NOTE the block form's Phi value is **unrelated to the Region's input**: the
input is the last effect, the Phi's first input is the block's trailing value.
A reader that assumes they are the same node recognises only the string form —
which is exactly the bug this field's commit also fixed.

## Consuming it

The body must be emitted INSIDE the block, and the construct claimed at the
ENTRY rather than at the join: by the time a chain walk reaches the Region,
the body statements have already been consumed as ordinary chain. A walk that
re-enters at the entry also needs a re-entrancy guard, since the entry is the
very node that identifies the construct.
