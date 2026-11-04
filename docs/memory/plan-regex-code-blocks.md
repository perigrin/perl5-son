# Plan: regex code blocks `(?{ ... })` (perigrin chose "closures", 2026-11-04)

The census's largest cause: pvm 286, 287 and 288 (embedded-code.md).
Before this, chalk refused them in its regex parser, and B::SoN dropped
the block's code, keeping only the pattern text.

## What perl has
- A literal pattern's blocks are ops in the ENCLOSING CV:
  `$match->code_list` is
  list(pushmark, const "b", null(...block ops...), const "").
  `$k` is a padsv of the outer pad, not a capture. qr// (287) is
  similar; check whether it has its own CV.
- A block runs each time matching passes its point, backtracking
  included. Its value is $^R (not used by these cases).

## Design
- Producer: lift each block as a body graph, the way translate_sort_body
  and translate_subst_body do (a subtree in the enclosing CV's pad). Name
  it deterministically per site. The RegexMatch carries the names in
  pattern order.
- The block's outer lexicals: for program-level blocks, add their main-pad
  slots to _file_lexicals_shared. Then both graphs read and write them by
  name (shared PadAccess), as named subs do with file lexicals. A block
  inside a sub that reaches the sub's own lexicals: refuse by name.
- Chalk: the regex parser makes a `code` atom (zero width). The matcher
  calls the body's function there each time matching passes, and its
  value is dropped.
- Tests red first: producer (the graph carries the bodies, the shared
  marking) and chalk (a code atom is called; a backtracking case counts
  calls as perl does).

## As built (2026-11-04)
- Producer:
  - _regex_code_bodies lifts each block as `<site>.<n>`.
  - A literal pattern's blocks come from code_list in the enclosing CV.
  - A qr's blocks come from `$qr->pmregexp->qr_anoncv`, the anon CV's qr
    op's code_list. Its captures go through _outer_main_slots(..., 1)
    (anon allowed).
  - A qr's names ride on its Constant (%QR_CODE_BODIES) to the Match
    that applies it.
  - Program slots: _code_list_slots counts any op whose targ names a
    variable (`$t .= "x"` is concat[$t]).
  - A code-block match the walk can't pin (a loop body) is refused by
    name.
- Chalk:
  - The loader keeps %CODE_GRAPHS.
  - The parser makes a zero-width `code` atom; quoted strings in the
    block are skipped.
  - Each body is `@chalk_rxcode_N`, emitted like an END block.
- HOW OFTEN A BLOCK RUNS IS PERL'S OPTIMIZER'S. perl searches for the
  fixed text first and runs a block on each try that reaches it.
  `/a(?{$t++})b/` on "aab" runs it once, not twice, and on "xay" never.
  So only an all-literal pattern is lowered: its blocks run on the hit,
  once each, in order. A class, a quantifier, or (??{}) is refused by
  name.
- Bugs found on the way:
  - The minimum match length counted the zero-width atom.
  - The Match(qr) subject wasn't read as a Str when held in memory
    (shared _regex_subject_str).
- Result: pvm 286, 287, 288 lower. Census count after: see the pin.
- Next: a block in a loop body (needs the producer to pin the match
  there), or in a sub over its own lexicals.
