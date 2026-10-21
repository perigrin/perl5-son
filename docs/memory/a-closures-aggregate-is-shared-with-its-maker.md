---
name: a-closures-aggregate-is-shared-with-its-maker
description: An array or hash an anon sub captures from its sub's scope is one location in both graphs; a value binding of it misses the closure's writes
metadata:
  type: feedback
---

`my @p; my $c = sub { push @p, $_[0] }; $c->(1); "@p"` folded to the
value before the calls (`join($", 5)`), and with `@p = ()` the lifted body
declared its own `my @p`. Both baseline and branch did this silently.
chalk's Earley fills `@pending_sweeps` from a commit callback and drains it
in the maker.

**Why:** a captured scalar was a cell, but a captured aggregate was only a
pad slot in two graphs. The fix makes it a shared lexical, as a file
lexical a named sub uses is: `_captured_own_aggregates` in the maker,
`_anon_aggregate_main_slots` follows the chain to the owning sub. A shared
aggregate's binding is its container PadAccess, never a literal: a loop
then carries no value copy (seed the scout's placeholder with the
container too, or an arm's store makes a join Phi). A foreach over it
re-reads its count each pass once the loop carries memory.

**How to apply:** when a closure writes something, test the maker's read
AFTER the call and after a clear-and-refill, and inside a loop. Hoisting
to file scope shares the variable between two calls of the maker, the
same limit captured scalars have (`34` for `31`) -- still open.
