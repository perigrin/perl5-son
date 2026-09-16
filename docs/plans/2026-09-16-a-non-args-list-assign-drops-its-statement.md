# A non-@_ list assign drops its whole statement

`sub c { my ($p,$f,$l) = caller; return $l }` translates to

    Start, Constant undef, Return

The `caller` Call, the `Assign`, and all three `PadAccess` nodes are
absent. The sub body is gone, with **no diagnostic at all** — the silent
DROP category.

perl says `defined($l)` is true; the emitted program says false.

## Scope

Not specific to `caller`. Measured across list-valued right-hand sides:

| RHS | body survives? |
|---|---|
| `caller` | NO |
| `localtime` | NO |
| `localtime(0)` | NO |
| `times` | NO |
| `stat("/tmp")` | NO |
| `sort("q","p")` | yes |
| `(7,8)` | yes |
| `split(/,/,"p,q")` | yes |
| `@_` | yes |

## What is established

The op chain is intact and reaches everything:

    nextstate -> pushmark -> caller -> padrange -> aassign
              -> nextstate -> padsv -> leavesub

`padrange` for this shape is **flags=48, private=131**. The handler in
`_step` guards on `$op->flags & 0x80` (OPf_SPECIAL = the elided-`@_`
form), which is FALSE here, so it falls through to OpMap — which declares
`padrange => SKIP`. The targets are never pushed.

`aassign` then finds an empty mark and its guard

    if (!$lhs->@*) { return ($op->next, 'handled') }

emits nothing. That guard's assumption ("padrange already bound them") is
true only for the `@_` form.

## What is NOT established

Two fixes were tried and neither took effect:

1. A second `padrange` branch handling `!(flags & 0x80) && (private &
   0x80)`, pushing each target. Inert — no observable change, and no
   regression either.
2. Making the empty-`$lhs` guard refuse when the stack is above the mark.
   Never fired, so at that point the RHS is not on the stack either.

Instrumentation added to `_step`'s dispatch and to the main walk loop
produced NO output for this sub, while the graph is nonetheless built —
so the trace was landing in the wrong walker. **There are two walkers**
(the main one and the loop-body one) and the next step is to determine
which one handles a plain sub body, then instrument that one.

Both attempts were reverted rather than left in place: inert code with a
confident comment is worse than none.

## Pin

`t/wire-padrange-non-args-source.t` holds the two failing assertions
under TODO, plus a passing guard that the `@_` form is unchanged.
