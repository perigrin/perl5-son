# Census cause: a method call with no class_name, `can` and `class` objects (345 -> 346, pin 368b9bde)

**Cause:** "LLVM MOP: Call(method) X has no class_name" held 3 cases: 012,
059 and 248.
- 059 round-trips in probes.
- 012 now hits `tie`.
- 248 now hits a recursive direct call (`fib`).

## What changed (chalk only)

- **`$o->can("m")->(ARGS)`:** an indirect call whose code is a `can` with
  a constant name, where every reader of that `can` calls it
  (`_is_called_can`). It lowers as a run-time dispatch of `m` on `$o`'s
  bless class with the call's own ARGS. `_lower_runtime_dispatch` gained
  `name`/`args` options for this. The `can` itself lowers to nothing.
  Refused by name in these cases:
  - no package declares `m` (perl dies);
  - inside a block eval;
  - a stored `can` result (cn2): it keeps the old GAP.
- **A method on a Scalar that holds an object of a `class`:** allowed only
  when the program has exactly one `class`, that class has the method, no
  package declares a sub of the same name, and no class is empty
  (`Chalk::IR::Analysis::_the_class_with`). Then every object is of that
  class.
  - Analysis types the call from the method's return.
  - Lowering checks the slot's tag (Object, or exit 255 as perl dies) and
    turns the payload back into the object pointer. It then runs the
    static vtable call, via `$self->{_by_tag}` keyed by the node.
  - A second `class` with the method is refused by name.

## Convention, confirmed

An uncaught die in chalk exits 255 without perl's stderr message.
- The census compares stdout and exit code.
- The known WRONG probes (ar ar2 ar3 s5 a8 d0) are this stderr-only gap.
- A no-match dispatch outside an eval follows it. Inside an eval it is
  refused, because there perl catches the die.

## Lessons

- A recursive re-entry through the same lowering (`_lower_call_method`
  from `_lower_class_method_by_tag`) must skip the branch that sent it
  there. The first run hung.
- A class named `B` collides with perl's own B module under `-MO`. Test
  classes need other names.
- Type a call where every lowering agrees (Analysis), not at one lowering.
  Readers ask a value's repr before it is lowered.
