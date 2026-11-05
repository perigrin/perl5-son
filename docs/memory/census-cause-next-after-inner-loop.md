# Cause: "an inlined sub's value is made inside one of its arms" (2026-11-05)

- Held: pvm 205. Despite the message, the sub ends in `return "@o"`, not in
  an if. The refusal was a false positive.
- Shrunk to: a while loop with `if (...) { inner loop; $i = $j; next }` and
  a `push` in the body. The return reads the array after the outer loop.
- Three fixes (chalk 2df9149f):
  - `_lower_inlined_structure`: the main-chain walk back from the Return
    reached the outer Loop through the `next`'s merge Region, not through
    the loop's exit Region. The exit memory Phi then looked like an arm's.
    A Phi whose region's head is a Loop on the main chain is now accepted.
  - `_record_break_block` (a `next` arm's latch values): a `next` after an
    inner loop arrives along the inner loop's exit Region, not the arm's
    Proj. `_arm_proj_of` walks control back (Region -> head, else
    control_in) to the Proj and matches on that, but only when no exact
    match exists.
  - `_lower_loop` latch pairing (`%arm`): the same mapping, via `$of_arm`.
- Each fix exposed the next refusal. Shrinking at each stage (s4 -> s10 ->
  s13) kept the probes minimal.
- Result: 205 round-trips. Census 402 -> 403.
