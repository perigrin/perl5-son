# Cause: "callee writes $_[0], whose argument is a TernaryExpr" (2026-11-05)

- Held: pvm 186. `for my $x (@$l) { g($x) }`, where g does
  `$_[0] = uc $_[0]`.
- The loop variable over an array through a reference is B::SoN's alias
  ternary: `exists $a[$i] ? $$alias : $a[$i]`.
- Built (chalk 973477de): `_copy_out_written_args` stores back along the arm
  taken. It branches on the condition and assigns to `$$alias` or to the
  element.
- PRE-EXISTING MISCOMPILE this exposed: `my $m = [5, 6]; for (1, 2) {
  g($m->[0]) }`, with g writing `$_[0]`, left @$m unchanged.
  - B::SoN pins an anonymous constructor where it runs, but
    `process_control_node` ignored a pinned ArrayLiteral/HashLiteral.
  - It was made at its first use, inside the loop body. The loop's cache
    scope then dropped it, so each use built a fresh array.
  - Fix: a pinned ArrayRef/HashRef literal is made at its statement.
- Lesson: when a fix makes a shape reach new code, probe it with two
  arguments and in nested loops. t2/t6/t7 turned up wrong (they had been
  refused before), and shrinking found the older bug underneath.
- Result: 186 round-trips. Census 403 -> 404.
