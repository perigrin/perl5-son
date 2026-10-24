---
name: census-cause-block-eval
description: 430/430 goal, cause "Phi node before its enclosing structure" (eval part) — block eval lowered as a branch, every die it reaches being inlined; $@ made explicit; dying values that are dropped from the graph; ROUNDTRIP 166 -> 168 of 431
metadata:
  type: project
---

**Cause:** "Phi node encountered in lower_value before its enclosing
if/loop structure" held 11 cases at 05bb1a05, mostly block evals. Three
more `Call(method) 'state'/'field'/'defer' has no class_name` cases are
evals too (without the feature, `state $n` is `$n->state`, which dies).

**Built (chalk):** a block eval is a BRANCH, not an unwind. chalk
inlines what the body calls, so every die the body can reach is in the
function being lowered. The control chain opens the eval at its body's
first node and closes it at its join (the Region with eval_entry). A
die inside stores $@ and branches to the catch block; the join's Phi
takes the body's value or undef. perl's `$@` starts "", is cleared when
an eval begins and when it ends without dying.

**Built (B::SoN):** what the consumer cannot see is made explicit:
- the clear at the eval's start is an EntryWrite `$@ = ""`;
- each die and its eval carry an `eval_id`, so a die in an eval the
  consumer did not lower as a branch (in an arm, a loop body) is refused
  rather than sent to an enclosing eval or out of the program;
- `eval_may_die`: the body made a value that dies on some input (a
  division by what may be zero, an array-element reference). If unused it
  is not in the graph -- and perl still died making it.

**Refused by name:** a die message without "\n" (perl adds " at FILE
line N."), a multi-argument die, a list/caller-context eval that can die
(it yields (), not undef), a class method call or ADJUST inside an eval
(a separate function: its die would exit), and perl's own dies inside an
eval (deref of a non-ref, element ref, zero divisor).

**Pre-existing miscompiles found on the way (base, not this branch):**
- `1 / $z` with `$z == 0` printed Inf where perl dies -- fixed: the
  divisor is checked, exit 255 as perl's die.
- An unused `my $q = 1 / $z` or `\$a[-5]` is dropped from the graph by
  B::SoN, so the program goes on where perl dies. Outside an eval this is
  still wrong for every consumer (Deparse too). The real fix: a value that
  may die is an effect, kept on the control chain.

**Result (chalk f657340b, three census runs agree):** ROUNDTRIP 166 ->
168 (113 and 402 new; 156 round-tripped mid-way, then refused on an
inlined value made in an arm when the join stopped being a memory
version). What the eval cases hit next:
- eval_may_die (006, 062): needs the producer to keep a dying value as an
  effect on the chain, so it is never dropped -- then the marker goes;
- a die of two arguments (063), a list-context eval that can die (091);
- 422/423/425 are method calls on an undef invocant (`state $n` without
  the feature): perl dies "Can't call method on an undefined value";
- the rest are other causes inside the body (sort, Chomp, If.cond...).

**Tried and reverted:** making the eval's join the memory version after
it. It ordered $@ right for chalk, but SoN::Deparse orders by memory in
~150 places and rendered three programs wrong. The producer already pins
each main-walk `$@` read as its own node (corpus 056); chalk lowers a
pinned read where it stands instead.

**Why:** a feature that looks like it needs a runtime (unwinding) did
not, because the consumer had already closed the world (everything the
body calls is inlined). **How to apply:** before refusing a feature as
"needs a runtime", ask what the static structure already guarantees.
