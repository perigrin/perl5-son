---
name: census-cause-in-memory-handles
description: 430/430 goal, "Call builtin open" (6) + readline (4) + select -- in-memory handles; handle builtins advance memory in B::SoN; 192 -> 200 of 431
metadata:
  type: project
---

**Cause:** "node op=Call builtin open repr=Scalar reached LLVM backend" (6:
295 296 298 428 430 431) and "cannot lower op=Call builtin readline" (4:
011 297 363 364). Every case is an IN-MEMORY handle: `open(my $fh, "<",
\"...")` reads a string; `open(my $out, ">", \my $buf)` writes into $buf.
`select($out)` redirects a bare print.

**Producer gap first (perl5-son):** the handle builtins were pinned on
control but did not advance MEMORY. `my @l = <$fh>; print scalar(@l)` read
@l at MemStart, so chalk built @l in the entry block, before the open, and
read an unopened handle: 0 lines. `print $buf` after a write handle read
$buf at MemStart too. %HANDLE_MEMORY_BUILTIN (open close readline eof) now
takes and advances memory, the same way require/dofile do
(t/wire-a-handle-op-is-a-memory-version.t; Deparse still round-trips it).

**chalk design:**
- A handle is a malloc'd { i8* data, i64 len, i64 pos, i8* target }.
- The variable holding it is an entry i8* cell, null until an open. One
  cell per sub (keyed by the set of subs being inlined), because two
  inlined subs each with a `my $fh` shared one cell, and the callee's open
  clobbered the caller's handle.
- readline uses memchr. It is cached: lowered at its place on the control
  chain. A list that holds it appends that array, never reads again.
- `>` empties the scalar and `>>` appends to it. `print $out` appends to
  the target %Slot.
- close nulls the cell AND marks the struct (len 0, target null), because
  select may still hold the pointer.
- select: a module global @chalk_selected (null means STDOUT). Only when
  the program selects (a pre-lowering scan, $SELECTS) does every bare
  print branch on it. Refused in a program with classes, since method
  bodies lower in their own context.
- Refused by name: a file on disk, a mode known only at run time, any
  target but a constant string or a scalar variable, a handle that isn't
  a `my $fh`, select's value used other than by select, print to STDERR.

**Also fixed:** _str_const_parts wrote the raw text into an IR comment, and
a newline in it broke the .ll.

**Result:** 192 -> 200 (295 296 297 298 428 429 430 431). Next: 011 (AnonSub,
glob assign, AUTOLOAD), 363/364 (`<DATA>`, a bareword handle whose text
B::SoN would have to carry).
