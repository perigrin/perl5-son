# Cause: "Subscript container has repr=Unknown" (pvm 175), partial (2026-11-05)

- pvm 175 is still refused. Three layers were fixed (chalk 287a6c03,
  see the bson/llvm-corpus log entry "an element of a method's value"):
  1. A Subscript over a container nothing typed (a method's value) is now
     lowered first and then read as the type it became.
  2. `_pending_tag_reads` is now scoped to the inline frame, in both
     `_lower_inlined_structure` and `_lower_inlined_effects_then_value`.
     A read left waiting inside a callee had made later caller stores
     refuse.
  3. `_inline_value_repr` is now keyed by refaddr, not id. Ids are per graph
     (`Call#7`), so they collide across graphs. This was an LLI_FAIL that
     only showed once fix 2 got the probe that far.
- What 175 hits next:
  - A merge typed List (a bare `return` in a sub called in void context)
    has no machine layout.
  - Skipping it as unbuilt produced a dominance LLI_FAIL (w21), so that
    change was BACKED OUT.
  - After that, 175 needs `join` over `%{$s->{p}}` (a hash flattened).
- Lesson: a key-first change that seemed needed was not. Removing each
  fix and re-running its probe shows which ones are load-bearing.
