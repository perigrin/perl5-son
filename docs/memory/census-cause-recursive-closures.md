# Census cause: recursive closures (387 -> 388)

**Cause:** "a closure that writes what it captured is not lowered". It held
134 and 135, both the `my $w; $w = sub { ... $w->(...) }` idiom. The closure
doesn't write anything there; the frame writes its own `$w`. Behind it were
"a code reference used as a value" and inlining recursion. perigrin chose
"Real closures, now".

## What changed
- B::SoN 013da8c: a capture read in an arm or loop body went through no cell
  (a PadAccess for a slot the closure doesn't own). Now it's a CellRead.
  Scouts don't see the cells, because their throwaway nodes leaked into the
  graph through the real CellParam's consumers.
- chalk 09d7158e: an inlined closure writes its captures through the
  variable's location. A cell read is cached (`return $k++` gave the new
  value). CellWrite now asks the value's repr after lowering it (it was
  storing an opaque 0). Concat converts any non-Str operand, since an inlined
  call is restamped.
- chalk dde44926: a variable given its one sub holds a CodeRef. A call
  through it resolves statically. A closure that calls itself is a define,
  `%Slot (%Slot* cells, %Slot args)`, boxed so it needs no trial return
  type. CellWrite joined %STATEMENT_EFFECT_OPS and is_fixed.
- Tests: wire-closure-cells.t (3 new), llvm-a-closure-writes-its-capture.t,
  llvm-a-recursive-closure.t.

**Round-tripped:** 134.

**Miscompile found on the way:** 09d7158e dropped a closure's store to a
capture inside an `if` arm (printed 0 for 5). It was pinned for one
commit. Fixed in dde44926, which is now pinned.

**Still refused, by name:**
- 135: its closure takes its argument through a signature.
- A bare `return` in a recursive closure: its value becomes a list.
- `$k += 2` on a capture.
- A code value that escapes the sub that made it: needs a runtime
  {fnptr, env}; a later step.
- 286-288 (regex `(?{ })`): not started.
