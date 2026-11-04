# Plan: constant `eval STRING` (perigrin chose "constant evals now", 2026-11-04)

Census cases: pvm 290 (`s/b/$c/ee`, with $c = q{3*4}), 292
(`eval q{$i = 1}`), maybe 210 (`eval 'package Other; sub g {...} 1'`),
and 015 (a mix). pvm 291 evals a string built from %ENV at runtime: no
runtime-free binary can run it. It stays refused by name, so the honest
ceiling is 429 unless perigrin later chooses to embed libperl.

## Today
- The producer refuses any entereval while ANY lexical is in the pad
  (_refuse_unseen_lexical_access, FromOptree ~21678).
- Otherwise it builds a pinned Coerce(Str -> Code) plus a Region/Phi
  with undef. Chalk refuses that.

## Design
- When the eval's source is a Constant string, compile it at produce
  time, as
  `package P; no strict; sub { my (<names visible at the eval>); sub { CODE } }`.
  - The names are pad names whose COP_SEQ range covers the eval's
    nextstate cop_seq (B::PADNAME COP_SEQ_RANGE_LOW/HIGH).
  - Call the outer sub to get the inner CV. Its OUTER-flagged pad names
    are the lexicals it uses; match them by name to the program's
    visible slots, and refuse if a name is ambiguous.
- Lift the inner CV as a body graph (a %CODE_BODIES-like registry) that
  shares those lexicals by name with the program. Mark the program's
  slots shared (as for regex code blocks).
- The eval becomes a direct Call to the body (chalk inlines direct calls
  and shares lexicals by name). Its value is the body's Return; a
  successful eval also sets $@ to "".
- Refuse by name: a compile error in the string (perl sets $@ at runtime
  then), a body that may die (leave that to the block-eval machinery
  later), and a non-constant source (291).
- Tests red first: a producer wire test, chalk probes, and 290/292
  end to end.

## As built (2026-11-04)
- Producer: _constant_eval compiles a const-op string in
  `sub { my (<visible names>); sub { STRING } }`.
  - Visible means COP_SEQ_RANGE_LOW < the eval's cop_seq <= HIGH.
  - The inner sub's OUTER names map to program slots by name. A name
    declared twice is refused, because chalk shares by name and would
    merge them.
  - The body goes in %CODE_BODIES under `<enclosing>::__EVAL__:N`. The
    eval becomes a pinned direct Call, then an EntryWrite of "" to $@.
  - _file_lexicals_shared marks the slots it names.
  - Refused by name:
    - a string made at runtime (291);
    - a body with die/division/call/require/eval (its die would need
      $@ catching);
    - a string that doesn't compile;
    - an eval in a sub.
- Chalk: Analysis::_attach_evals gives `::__EVAL__:N` calls a MOP::Sub
  target, so the existing direct-call inlining runs the body.
- Result: pvm 292 round-trips. Census 394 -> 395 at chalk 875955e3 (3 runs
  agree, 0 DIFFERS, 0 LLI_FAIL); floor raised to 395; ratchet passes 6/6.
- 290 and 015 are `s/b/$c/ee`: an eval of $c's value (a padsv), not a
  const op, run per match. Still refused by name.
- 210 defines `Other::g` in its eval: chalk has no callee for it.
- LESSON: Deparse consumes the same graphs. An eval with no lexical in
  the pad was already round-tripping through Deparse as an opaque
  Coerce(Str -> Code). Replacing every constant eval broke 9 producer
  test files. The new path now runs only where the pad has a lexical
  (what was refused before). Deparse renders the new call as a sub over
  the shared lexicals, correctly.
- Also refused: a constant string that defines a sub (`sub NAME`, or a
  glob it assigns). Compiled at produce time, the sub went unseen and a
  call took AUTOLOAD (chalk's autoload test caught it). A refusal is
  cached and re-raised, and the shared-slot scan swallows it so other
  subs still translate.
