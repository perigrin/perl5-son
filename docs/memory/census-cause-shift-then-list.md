# Census cause: a callee that shifts @_ and then reads it as a list (379 -> 380)

**Cause:** "callee shifts @_ and reads it as a list -- the list after a
shift is not the call's arguments". It held 147:
`package K { sub new { shift; bless {@_}, "K" } }` called with
conditional lists. This is the package-constructor idiom.

## What changed (chalk 94bd65e6)

- `_collect_positional_arg_reads` allows shifts plus a list read when
  every reader of @_ (other than the shifts) has every shift before it,
  in control order (control_in chain) or memory order (memory-input
  chain). It records the shift count in `_args_list_after_shifts`.
- At the call site, the shifts bind the first k arguments by position.
  Those must be single scalars, so the existing flatten guard runs on
  them. The list is `_emit_flattened_array_of(args[k..])`, so
  conditional lists work.
- Test: llvm-a-shift-then-the-rest-of-args.t (4). The 147 and joined
  cases were red before.

**Round-tripped:** 147.

**Still refused:** `my $class = shift; my %a = @_;`. The HashLiteral for
`%a` has no control_in and no memory input, so the graph doesn't say it
reads @_ after the shift. That's a producer gap: B::SoN should give a
read of @_ its memory position (as `join(..., @_)` gets one). Worth
doing, since it's a common constructor shape.

**Looked at, not worked:** 145 and 199 are @_ aliasing writes through a
conditional list (`g($c ? ($s, $t) : ())` writing `$_[1]`). Writes stay
inlined by design, and the inliner doesn't store back through a
TernaryExpr.
