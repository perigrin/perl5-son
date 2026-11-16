# Cause: constant string eval, on cells (perigrin's design, 2026-11-16)

Design: a string eval whose string is known at compile time is compiled by
B::SoN into a body that captures the outer lexicals; a string built at run
time stays refused by name. The 2026-11-04 attempt (shared by name, T1) was
backed out; this one rides closures (cells) and block eval, which T2 has.

## As built
- Producer: _const_eval compiles the string as `sub { my <lexicals in scope
  at the eval>; sub { STRING } }` in the eval's package with its $^H/%^H; the
  inner sub is the body (%ANON_BODIES, `main::__PROGRAM__::__EVAL__:LINE:N`),
  its captures cells (_capture_cells, shared with anoncode). The eval is a
  block eval (Region eval_entry/eval_id) around one direct Call with
  `string_eval: true`. Known strings: a const, or a `my $c = CONST` nothing
  else touches (s///ee's `$c`).
- Refused by name: no compile, die naming its place, warn, warnings on, @_,
  use integer, phase blocks/use/no/sub/package (text scan), braces leaving
  the wrapper (structural check), in a sub / loop / list context, arrays,
  hashes, state, names declared twice, ops outside %EVAL_BODY_OP.
- Chalk: Call.string_eval loaded; `__EVAL__` names are anonymous bodies in
  Analysis and the T2 builder; LLVM.pm refuses a string_eval call before the
  fallback (T2's alone).
- Found on the way (older, closures too): the program's stale-operand re-read
  asked _address_taken of main_cv->ROOT (none), so `$x + $f->()` read $x
  before a closure stored it (1 for 5). Fixed: main_root.
- Still wrong, older, not touched: a closure over a name the file declares
  twice (T2 DIFFERS, Deparse too) -- evals refuse that shape.

## Result
pvm 290 and 292 T2-SAME (sweep 379 -> 381, 0 DIFFERS); census ROUNDTRIP 420,
DIFFERS 0, LLI_FAIL 0. 291 stays refused ("code made at run time"); 015
stops on (??{ }) in chalk.
