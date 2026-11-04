# Cause: a bitwise op on what may be a string, read by two ops (2026-11-04)

- Cause: "a bitwise op on what may be a string, which another bitwise op
  also reads". It held pvm 047 (bitwise.md). pvm 004 hits it too, through
  `$ARGV[n] // default` (stamped Scalar, not an %ENV read), which isn't
  lowered.
- Perl's rule: a bitwise op done on numbers numifies a string operand
  variable, and every later op reads it as a number.
- Built (chalk 79ecc411): _bit_numified_slot, an i1 alloca per leaf (a
  `//` copy or an %ENV read), initialised false in entry.
  - _bit_string_of reads "still a string" as is-a-string AND NOT
    numified.
  - Each op done on numbers sets the flag: the strings path when its
    operands aren't both strings, and the numeric path (an integer
    operand) always.
- Refused: a bitwise op whose value nothing uses, if it shares a leaf.
  It is never lowered, so it never sets the flag, though perl runs it
  (probe bwp3). A numeric read other than a bitwise op stays refused, as
  does a loop.
- Result: 047 round-trips. Census 394 -> 395.
- Next for 004: an @ARGV element `//` default as a bitwise leaf. Its
  defined bit comes from the slot, and an @ARGV element is a string when
  defined. 004 also has <<, ~, |=, x=, //=, and a lot more.

## REVERTED (chalk 8dfdac3e), a miscompile pinned at 79ecc411
The numified flag assumed the bitwise ops run in the order they're
lowered. Context lowers a pure value at its first USE, not at its
statement. So `my $x = $s & 5; my $y = $s & "10"; print "$y $x"`
lowered $y's op first and printed 10 4 (perl: 8 4). The census pin went
back to 394.
- Also seen: any numeric read numifies (`$a << 1`, then `~$a`), and a
  Coerce(Int) node shared by `<<` and `~` listed only `~` among its
  consumers. Consumer lists are incomplete, as noted before.
- To retry: order the ops as perl runs them. Either pin every reader of
  such a leaf to its statement, or allow only readers inside ONE
  statement (lowered left to right in perl's order), with readers found
  by scanning inputs, not consumers.
- LESSON: run-time state threaded through PURE values needs those
  values lowered in program order. Context doesn't do that; T2 pins
  statements. Probe "two statements, used in the other order" before
  calling any stateful lowering done.
