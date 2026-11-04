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
