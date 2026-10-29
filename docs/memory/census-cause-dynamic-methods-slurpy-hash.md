# Census causes: a method named by a value, a slurpy hash, `can` as a truth (350 -> ?)

**Causes and cases**
- "cannot lower op=Call dynamic_method" held 012 and 055. Both round-trip
  in probes.
- "callee's `my (...) = @_` has a slurpy target" held 068 and 127.
  - 127 round-trips.
  - 068 next hit `$n->can('kind')` read as a truth, which this batch also
    lowers, and then round-trips.

## What changed (chalk only)

- **`$o->$m(ARGS)`:** the producer emits `Call(dynamic_method, [obj, name,
  ARGS])` and constant-propagates `$m`. A constant string name lowers as a
  run-time dispatch of that name, with arguments `[obj, ARGS]`. Refused by
  name in these cases:
  - a name that is not a constant;
  - a name no package declares;
  - inside an eval.
- **A slurpy hash `my ($c, %o) = @_`:** the call builds `%o` from the
  arguments after the scalars, as a transient HashLiteral lowered by
  `_lower_hash_ref` and bitcast to `%Hash*`. Every `%o` PadAccess in the
  callee is bound to it, as the slurpy array already was.
- **A package `new` stamped Object by B::SoN:** a `->new` is stamped
  Object even when the package sub returns `$o{ix}`. `_resolve_direct_calls`
  now re-stamps it from its body's return when that is any narrowed type,
  or Scalar (127).
- **`->can("m")` read only as a truth** (`_is_can_read_as_truth`). This
  is true when every value reader, through value Phis, is one of:
  - an If condition, Not, Defined or a ternary's condition;
  - a Coerce to Boolean.

  Not counted as value readers: memory Phis, Region/Loop control inputs,
  and nodes that take the call only as their memory version. It lowers to
  an i1: blessed (or a class string), and its class is one that declares
  m. Refused by name in these cases:
  - any class inherits or has AUTOLOAD;
  - a UNIVERSAL name;
  - a `class` method;
  - inside an eval.
- **`_dispatch_invocant($obj)`** is extracted from `_lower_runtime_dispatch`
  and shared with `can`: a class string, or a blessed reference's
  bless-table class, with exit 255 for what is not a reference.

## Lessons

- A method call ending an arm is the Region's control input. A reader
  scan must skip control (Region/Loop) and memory uses, or it counts them
  as value reads.
- `llvm-a-sub-takes-its-arguments.t` passes a case when it is refused by
  name, so a new case there cannot fail first. Put the cases that must
  lower in a strict loop.
