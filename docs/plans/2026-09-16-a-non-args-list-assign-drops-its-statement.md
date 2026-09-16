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

## Traced, with the mechanism confirmed

An earlier revision of this file said the walker was never reached and
guessed at a second walker. **That was wrong** — it was an artifact of
running the probe as `env SON_TRACE=1 perl ...`, which in this shell
produces no output at all, not even from a bare `print STDERR`. Dropping
the `env` prefix made every trace appear. Every "never reached"
conclusion drawn that way was measuring nothing.

With working traces, the mechanism is:

    MAIN: nextstate / pushmark / caller / padrange / aassign / ...
    PADRANGE flags=48 private=131
    AASSIGN-ENTER depth=1 mark=0
    AASSIGN-LHS: Call  remaining=0

`padrange` IS reached; its guard (`flags & 0x80`) is false, so it falls
through to OpMap's SKIP and pushes nothing. `aassign` then pops to the
mark and gets **the `caller` Call as its target list** — the RHS read as
the LHS — with an empty stack behind it.

## Two fixes tried, both REVERTED

1. **Push the targets in a non-`@_` padrange branch** (`!(flags & 0x80)
   && (private & 0x80)`, with `push_mark` under them). This WORKS as far
   as it goes: traced afterwards, `$lhs` is the three `PadAccess` nodes
   with the Call correctly left as the RHS. But the graph is still empty,
   because nothing then binds the slots and DCE removes the statement.

2. **Bind the targets by index** when one flattening source spreads over
   N targets, using `Subscript(source, i)`. This REGRESSED `sort` and
   `split`, which had been correct:

        my ($a,$b) = sort("q","p")    Can't use an undefined value as an
                                      ARRAY reference
        my ($a,$b) = split(/,/,"p,q") printed nothing

   so it is net-negative and does not survive.

## The real blocker

`caller` has **no stamp**, so `_is_aggregate_node` is false for it and
the "flattening source" path never applies. That is deliberate:
`B/SoN/TypeLibrary.pm` lists `caller` under WHAT IS DELIBERATELY ABSENT —

> CONTEXT-SENSITIVE -- one op name, two types. […] sound but vaguer than
> reading `$op->flags` at the construction site; `readline` takes that
> trade (List), these do not

so the fix is to stamp `caller` at its construction site from its own
want flag, the way `readline` is handled, rather than adding a
TypeLibrary row. That is the next step, and it is a larger piece than the
padrange change: it touches how a context-sensitive builtin is typed.

## Pin

`t/wire-padrange-non-args-source.t` holds the two failing assertions
under TODO, plus a passing guard that the `@_` form is unchanged.
