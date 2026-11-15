---
name: A pinned read is a memory version that changes nothing
description: 2026-11-15 -- pinning may-die reads through references (perigrin approved) broke 57 tests until every consumer of "the memory version" learned a read is one too, but one that changes nothing; the op stepped, not the node, says whether the program reads there.
type: feedback
---
Pinning a read through a reference makes it the memory version after it.
Every place that asked "which store is this memory?" then saw a read: the
deparser bound it as a value (`_is_memory`), bound `@$r` to a `$eff` (its
count), took a Count after it for a store's and spelled it late, and the
ternary-arm store check said "its last effect is not that store".

**Why:** a memory version used to mean "something changed". A pinned may-die
read orders, it changes nothing -- unlike a tied FETCH, which is a call.
**How to apply:** where code walks memory back to a store, step through a read
in %PINNED_MAY_DIE (producer) or a pinned Subscript/Exists/PostfixDeref/Count
(deparser). Decide "the program reads here" by the OP being stepped
(_op_derefs: helem over rv2hv), not by the node: enteriter and mapstart make
reads of the list they walk; a field hash is helem over padhv. A pinned node a
hash-cons hit returns from another arm is not this arm's (make_unique).
An arm holding a pin must merge control (_arm_advances_control), or the pin
forks the chain ("a control node with 2 successors").
