---
name: a-trap-body-write-lives-in-memory
description: A lexical an eval or try body writes is demoted to memory; the trap's join cannot carry what the body stored before a die, but perl's own variable can
metadata:
  type: feedback
---

`my $n = 0; eval { $n = 5; die }; $n` is 5 in perl: the store before the die
survives the unwind. As an SSA rebind it could not be expressed (the join
has the pre-eval value and the body's last, nothing in between), so every
such body was refused -- chalk's Target::C `try { $result = ... } catch`.

**Why:** a package variable already round-tripped, because its store goes
through memory and the emitted `eval { }` spells it by name. A demoted
lexical is the same thing.

**How to apply:** `_address_taken` demotes a pad scalar written under
`poptry` (try body) or `leavetry` (eval body), not its own `my`s and not a
dereference's operand (`push @$x` is OPf_MOD on `$x`). Demoting more
variables turns iterator write-backs on: a foreach iterator passed to a call
is demoted, and its array must then be a container -- `my @n = sort ...`
bound as the sort value emitted `(sort(@n))[$i] = $x`, which perl refuses.
_mutated_aggregate_slots marks such an array mutated.
