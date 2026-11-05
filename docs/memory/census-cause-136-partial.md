# Cause: "a block eval's value is a Unknown where a die makes it undef" (pvm 136), partial (2026-11-05)

- Fixed (chalk e22fd974): an eval that can die, whose value is untyped, is
  now a Scalar: the body's value boxed, or undef when a die is caught.
  - This applies only when the lowered value is a Scalar-holdable type.
  - Boxing an Unknown value made an Opaque cell, a potential wrong value.
    It is refused.
- A run-time method dispatch inside such an eval now does this when no
  class has the method:
  - branches to the eval's catch when $@ is unread;
  - is refused when $@ is read (perl's message names the file and line) or
    when the eval is not open as a branch;
  - before, it exited 255 where perl's eval catches the die.
    llvm-can-and-runtime-dispatch.t case 4 caught it.
- 136 is still refused: it reads $@ after `$s->add(...)`, and `$s` is a
  variable whose class `_static_class_of` cannot see through. That would need
  "a variable stored only `C->new`, never read before the store".
- Lesson: unlocking a shape lets every path inside it run. Each run-time
  stop in a newly reachable path (exit 255) must ask whether an eval
  encloses it.
