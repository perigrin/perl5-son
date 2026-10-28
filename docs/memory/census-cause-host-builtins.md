# Census cause: small host-facing shapes (lock, exit status, unopened
# handles, perl's own variables)

**Causes:** "cannot lower op=Call builtin lock" (028; 008 has more),
"exit status has repr=Str" (064), "print to the handle __CLASS__" (424),
"package-scalar global '@pkg_main_' is not a legal LLVM identifier" (342).

**Round-tripped:** 028, 064, 424, 342 (pin 309).

## What was done

- **lock** is a no-op without threads (pp_lock): its argument. In void
  context nothing is lowered -- B::SoN leaves its lvalue argument unbound;
  used as a value, reading that argument still refuses by name.
- **exit STR / exit NUM** reads the status as perl's POPi does: numify,
  then truncate ("1e1" 10, "abc" 0, -2.5 254). Probed against perl's exit
  codes, not just output.
- **print to a bareword handle no `open` names** writes nothing and is
  false. `print __CLASS__;` is perl printing $_ to a handle named
  __CLASS__. STDERR/STDIN and any handle the program opens stay refused.
- **$^W, $^O, $^, $^T** read as perl sets them (0, the OS, "STDOUT_TOP",
  the time) when no Assign in the program stores them. A store is an
  Assign whose target is the EntryDef: a READ EntryDef also has an input
  (its memory version), so "an EntryDef with inputs" was every read.

## Lessons

- In a test's double-quoted perl, `$^]` is the version variable: `"[$^]"`
  is not `$^` then `]`. Keep punctuation variables outside interpolation.

Tests: chalk `llvm-lock-is-a-no-op.t`, `llvm-exit-of-a-string.t`,
`llvm-print-to-an-unopened-handle.t`, `llvm-perls-own-variables.t`.
