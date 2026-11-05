# Cause: "a merge of a jump nothing typed, with an arm that is not a scalar" (2026-11-05)

- Held: pvm 174, `if ($c) { if ($a && $b) { ...; return } }`.
  - The sub is called both in scalar context (map, scalar(f())) and in
    list context (`my @l = f(...)`).
- B::SoN gives the Return two faces: a list Phi (`[]` against the last
  value) and a scalar Phi. The scalar face already worked; the list face was
  refused.
- Built (chalk 7a7476b3):
  - In `_close_jump_merge`, when `_inline_want` is list, each arm becomes an
    Array in its own block (a literal's elements, () for a bare return, one
    value as a one-slot array), and the Phi is an Array.
  - `_jump_merge_value` now also keeps the arm node.
  - The caller's list flattens a direct call made for a list with an Unknown
    stamp. This was needed in both `_emit_array_of` and
    `_emit_flattened_array_of` (checked by removing each).
- Still refused by name:
  - a list return merged inside an if with a scalar fall-through (l3: Region
    Phi Array->Unknown);
  - a bare return in a loop (l5).
- Result: 174 round-trips. Census 408 -> 409.
