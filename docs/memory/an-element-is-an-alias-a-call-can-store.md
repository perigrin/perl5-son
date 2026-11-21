---
name: an-element-is-an-alias-a-call-can-store
description: "SILENT WRONG fixed: `print f(1), $g, f(0), $g` said 1201 for perl's 1101 (both wires) -- a package scalar operand is now read again after a later call that may store it, return lists too; an element a call reaches by name is refused; OPEN: an element through a reference beside a call (needs a design)"
metadata:
  type: project
---

Branch `fix-alias-args` (2026-11-21). Found by the stage-5 agent
([[a-memory-edge-is-not-a-version]]).

**The rule (perl).** A list operator, a binary op or a sub's exit list
pushes `$g` ITSELF -- the variable, not a copy -- so the op reads it when the
op runs, after every later operand. Measured: print, say, join, a list
assignment (into an array or scalars), `[...]`, push, `return (...)`, `+`,
`.`, a multiconcat chain, a sub's `@_`: all 1101. `"$g"` copies (1201). An
element is an alias too, but only if it EXISTED when pushed (else undef).

**Where it was wrong.** `_reread_alias_operand_stored_later` already read a
padsv operand again after a later store or call. A package scalar was
refused for a direct store and not seen at all for a call; and the walkers
take `return`/`leavesub` before `_step`, so a sub's exit list was never asked
(`return (f(1), $g, f(0), $g)` was wrong for a lexical too).

**Fix (producer only; chalk unchanged).**
- gvsv / rv2sv(gv) record their stack slot and are stepped again (gv, then
  rv2sv). A call counts as a store of a package scalar when
  `_package_scalars_written` has it (or `*`); a string eval always.
- `_reread_exit_operands` asks a `return`, or the trailing return perl
  nulled under `leavesub`, at all three walkers' exits.
- sassign is OPf_STACKED: the op= guard took its value for an op= target.
  `$m{ $_->id } = $_` refused once `$_` (foreach writes it) counted a call.
- An element operand with a later call is refused by name where the callee
  reaches the container BY NAME: a package aggregate, a lexical one shared
  or referenced.

**OPEN: an element through a reference** (`$r->[0] . f()` where f stores it;
audit probe ag30, 1201 for 1101, kept out of chalk's probe gate). Refusing
every such pair cost corpus 009 (census 426 -> 425), seven chalk graphs
(`[ $g->{s}, $pos, $g->int_(1) ]`) and a deparse test. The options, a design
decision: (a) an effect summary -- which containers a callee may store
through, transitively, methods resolved or assumed to; (b) re-read the
element at the op, guarded by whether it existed at the first read (a new
shape the wire would have to say); (c) refuse, and accept the census loss.

**How to apply:** "read where its op stands" is right only for a copy. When
an op reads an operand perl pushes by alias, ask what later operands may
store -- including calls, and including exits the walkers intercept before
`_step`. Refusing what a call MAY reach is cheap for names and ruinous for
references: measure the census and chalk's lib before keeping a refusal.
