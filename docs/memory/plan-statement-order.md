# Plan: statement order for values with run-time effects (perigrin chose, 2026-11-04)

## Why
Context lowers a pure value at its first USE. A value with a run-time
effect, such as a bitwise op that numifies its string operand, then runs
in use order, not perl's statement order (the reverted 79ecc411 printed
10 4 for 8 4). B::SoN folds `my $x = $s & 5` into a pure value, with no
statement node to anchor it.

## Design
- Producer: pin a bitwise op (& | ^ ~) or a shift (<< >>) whose operand
  isn't typed Int, onto the control chain where the walk meets it
  (set_control_in, like a code-block match).
- Chalk: process a pinned bit/shift op as a statement. Lower it there,
  in chain order, and cache it for its uses.
- The numified flag returns, allowed only when every reader of the leaf
  (found by scanning node INPUTS, not consumers) is a pinned bit/shift
  op. Any other numeric reader of a string-able leaf stays refused.
  Shift ops set the flag (perl numifies).
- Tests red first: "two statements, used in the other order" (already
  in llvm-a-bitwise-op-on-strings.t), 047, 004 with arguments, a reader
  in an arm, a dead op.
