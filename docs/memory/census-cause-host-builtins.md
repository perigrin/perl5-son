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

## prototype, wantarray, caller (pin 314)

**Round-tripped:** 251, 271, 272, 003.

- **prototype(\&f)** of a sub the program defines: the loader records each
  sub's prototype from `classes/<pkg>/subs/<name>/prototype`
  (`%Chalk::IR::Serialize::JSON::PROTOTYPES`, the `%USED_MODULES` pattern);
  undef for one with none. A builtin (`CORE::push`), an anon sub, or a name
  the program does not define is refused by name.
- **wantarray** is the context of the call being inlined (the Call's `want`:
  1, false, undef), and undef at the program's top level. Refused in a body
  lowered out of line. The want is set at the top of `_lower_call_direct`:
  set at ONE of its inlining paths, a call through another read "void" for
  both a list and a scalar call ("void void" for "list scalar") -- caught by
  the test before commit.
- **caller** at the top level: undef, or the empty list. Inside a sub it
  names the caller's package, file and line: refused.

Tests: chalk `llvm-prototype-of-a-sub.t`, `llvm-wantarray-is-the-calls-context.t`.

## -e, pack of C items, NUL bytes in print (pin 316, chalk 5e0c9341)

**Round-tripped:** 420, 367 (314 -> 316).

- **-e PATH** through access(2): 1, or undef (perl's false file test is
  undef, not ""). The producer stamps ftis Scalar (with pos and blessed):
  Unknown, `defined(-e $missing)` read as always defined -- a wrong answer
  the chalk test caught.
- **pack** with a constant template of C items (C, C3, C*): one byte per
  value, wrapped mod 256 (337 is "Q", -1 is 255). Other templates refused.
- **A pre-existing wrong answer found by a pack probe:** print wrote a Str
  with printf("%.*s"), which stops at a NUL -- `print "a\0b"` printed "a",
  a folded pack("N", 1) printed nothing. Print now fwrites exactly len bytes
  to the same stdout (so output order is kept).
- Lesson: a probe whose output has NUL bytes cannot be compared through a
  shell `$(...)` (bash drops them); compare with od or in Perl.

Tests: chalk `llvm-a-file-exists-test.t`, `llvm-pack-c-bytes.t`,
`llvm-print-keeps-nul-bytes.t`; producer `wire-a-file-test-is-a-scalar.t`.

## 4-argument / lvalue substr on a variable kept in memory (chalk e708f796)

**Round-tripped:** 338 (316 -> 317). 004 next hits a bitwise & over two
`$ENV{..} // N` values -- perl does it on numbers or strings by what each
value IS at run time, and chalk types the `//` Str.

- The part replaced is 3-argument substr's read (`@chalk_substr`); the
  variable becomes before . replacement . after, stored back to its cell.
  An offset past the end stops the program (perl dies, exit 255 both).
- The in-place-write refusal no longer names substr; a 4-argument substr on
  anything but a location is still refused by _lower_substr.

Test: chalk `llvm-substr-replaces-in-place.t`.
