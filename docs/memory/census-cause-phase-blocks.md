# Census cause: BEGIN and END blocks with effects

**Cause:** "from_json failed: GAP: a BEGIN block with effects of its own is
not lowered" (258, 013).

**Round-tripped:** 258 (317 -> 318, pin pending). 013 has more in it
(%INC, %main:: stash, POSIX, Fcntl).

## What was done

- **Loader:** main's BEGIN/END blocks with effects (not a `use`) are kept
  as graphs `main::__BEGIN_n` / `main::__END_n`, in the wire's order --
  END already in perl's run order (last defined first): reversing them was
  a wrong order caught by the test.
- **BEGIN** bodies lower before the main line, each with its own cache and
  var_table: phase graphs number nodes from their own factory, so sharing
  the main line's cache made `Print#2` of one hit the other's (the main
  line's print vanished).
- **END** bodies are functions; `@chalk_ends` runs them once, called before
  `@main` returns and from `@chalk_exit`, which every `exit(3)` call in the
  module is rewritten to (die, exit, a runtime stop). atexit(3) was tried
  first: lli does not run its handlers when the JIT program calls exit.
- A block reading a main-line lexical is refused: it read it unbound
  (`my $x; BEGIN { $x = 5 }` printed undef for 5).
- Emitted function bodies without an invocant prefix their string globals
  (`_in_function_body`), as methods do: END's `@str_const_0` collided with
  @main's.

## A pre-existing producer bug found by an END probe

`exit N` as a sub's (or END's) last statement runs in the caller's context
(`exit sK`), so no gate pinned it and it vanished: `sub f { print "e\n";
exit 4 } f(); print "after\n"` printed "after" and exited 0. Pinned in any
context now (producer 6c5e3ed).

## Lessons

- A probe that checks the exit code, not just stdout, found the dropped
  exit. Compare both whenever the shape can end the program.
- Graph ids are per-graph: lowering a second graph in the same context
  needs its own cache, or a node of one serves the other.

Tests: chalk `llvm-begin-and-end-blocks.t`, `llvm-a-phase-block-with-effects.t`;
producer `from-optree-an-exit-ends-a-sub.t`.
