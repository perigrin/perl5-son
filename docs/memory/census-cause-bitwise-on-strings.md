# Census cause: bitwise ops perl may do on strings (366 -> 368, pin 38078c75)

**Cause:** "a bitwise & / | / ~ that perl may do on strings". It held
004, 047, 049 and 050.

## Perl's rule

`&`, `|`, `^` and `~` work on bytes when no operand holds a number.
Otherwise they work on numbers. A string that has been read as a
number holds one from then on. Example: `$s+0` first turns
`"12" & "10"` from `10` into `8`. The same holds for a numeric read of
`$ENV{X}`, and for a numeric bitwise op.

## What changed (chalk 38078c75)

- `_lower_bitop_on_strings` decides at run time.
  - The operands it can judge are an %ENV read, a string literal and
    a `//` over them. The `//` takes the %ENV defined bit of the side it
    took.
  - It computes both the byte result (`@chalk_str_bitop`) and the
    numeric one, then selects.
  - A Coerce to Str of the node reads the bytes (`bitstr:` in the
    cache).
- **Static guard.**
  - Each value that may be a string is read by this one bitwise op.
  - Nothing reads it as a number.
  - The op is not inside a loop.

## Why not a per-variable "read as a number" flag

The producer merges equal expressions into one node. Two
`$ENV{X} // 6` sites, and two variables bound to `"12"`, are one node.
A flag on the node would leak between perl variables. Tried and
dropped.

**Round-tripped:** 049, 050.

## Still refused

- **047**: each variable is read by two ops. Lowering it needs to know
  that a numeric op cannot make a later op's operands numbers.
- **004**: `$a << 1` also reads `$a`.
