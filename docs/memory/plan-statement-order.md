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

## As built (2026-11-04/05)
- Producer: pin_bit. On the main walk, & | ^ ~ << >> whose operand (looked
  through Coerce) isn't typed Int/Num/Boolean is made with make_unique
  and pinned to the chain. It is NOT pinned when an operand's node is
  bound to more than one variable, or its variable is stored more than
  once (_stores_of_slot; the program's ops hang off main_root, not
  main_cv->ROOT). Numifying belongs to the variable, and a copy, merged
  identical `//`s, or a reassignment share one node (review5 C2).
- Chalk:
  - process_control_node lowers a pinned bit/shift op in place.
    _pinned_made serves later uses, since a pure value over a read
    re-lowers at each use and ran AFTER a later shift.
  - _bit_numified_slot is set by every op done on numbers, shifts
    included.
  - Readers are found by scanning the program's inputs
    (_bit_readers_of, via $ctx->{_program_return}). More than one
    reader is allowed only if all are pinned.
  - _value_users ignores the next statement that names a pinned op
    through control_in.
  - An @ARGV element `//` a default is a leaf (_argv_element).
- Result: pvm 004 and 047 round-trip. Census 394 -> 396 (chalk 91be0c1d).
- The review5 reviewer found C1/C3/C4 too. All are older than this
  branch (base wrong too) and are in the scratchpad report: a string
  result read by most consumers gives 0; &. |. under feature bitwise;
  string->int through a double.
- Review5's older bugs, fixed (chalk f9db1c16):
  - C1: a string bitwise result read by anything but a stringify, a
    numeric read or a bitwise op is now refused.
  - C3: the feature flavour forces bytes or numbers; Complement's
    flavour is now loaded.
  - C4: @chalk_str_to_int reads an integer string exactly (strtoll when
    it's the whole numeric prefix and fits).
  - Run-time stops print "chalk: refused at run time: ..." on stderr.
  - Still open: `use integer` signed bitwise (chalk ignores
    `use integer`); `~` results past an i64 stop at run time (now named).
