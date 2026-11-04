# Review checkpoint 2026-11-04: T2 arrays, regex code blocks, constant evals

Ranges: chalk a9628f32..b7beaa9e+, producer 6795c65..HEAD. Two fresh-context
reviewers, each finding backed by a probe (scratchpad review3/).

## Found (all fixed: producer "Review fixes" commit, chalk 4f5f75df)
- Critical: name-shared bodies bound the wrong variable when the file
  declares a name twice (the program spells the second x__2, the body
  doesn't). Now refused.
- Critical: `our` in scope bound wrongly (masking, or another package's).
  Now refused.
- Critical: the eval string was compiled under `no strict`. It now uses the
  site's strict bits.
- Critical: a loop in a code block walked to an empty body. Fixed by an
  allow-list (_refuse_unless_straight_line) for eval and code-block
  bodies. The same list covers can-die ops (substr, an element store, a
  strict deref) and a bare shift (@ARGV versus @_).
- Critical (chalk): a code-block match wasn't a memory version, so a
  read after it slid past a later store. Fixed in _is_memory_version and
  in the _freeze_memory_reads triggers.
- Important: BEGIN/use in the eval string ran in B::SoN. Braces in the
  string could escape the wrapper. Both are now refused.
- Minor (chalk): q(}) hid a block's end. Quote-like ops, comments and
  heredocs are now refused.
- Found on re-check: __FILE__/__LINE__/caller/warn and `use integer` in
  an eval (chalk ignores use integer everywhere). Refused.

## Lessons
- A DENY-LIST of "ops that can die" is the wrong shape. An allow-list of
  ops known safe made 5 findings one fix.
- Deparse re-renders a pattern's text, so a code-block bug is invisible
  to Deparse round-trips. Test code blocks through chalk or by refusal.
- Reviewers found ~12 older wrong answers too (base worktrees confirm).
  They're logged in scratchpad report-to-perigrin.txt.
- Not fixed (Minor): T2 store-die message has no " at FILE line N." (the
  producer gives a store no site); a T2 index of 1e20 reads undef.
