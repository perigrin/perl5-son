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
