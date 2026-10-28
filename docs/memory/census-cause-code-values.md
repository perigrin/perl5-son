# Census cause: a code reference used as a value

**Cause:** "a code reference used as a value -- not called where it is
made -- is not lowered" (008, 027, 126, 399). Held 4.

**Round-tripped:** 008, 027, 399 (and 396 along the way) -- 318 -> 322 at
chalk eec738dc. 126 (a method handed a code ref) needs a calling convention
for methods, which are emitted as real functions: left.

## What each one hit, and what it took

- **027** `local $SIG{__WARN__} = sub { }` then `warn`: warn had no lowering
  at all. Now: an *empty* __WARN__ handler stored on the program's straight
  line (control back to Start through plain statements only) makes every
  later warn write nothing and return 1. A warn with no handler is refused:
  perl's message names the file and line, which an lli run does not share.
  Any other %SIG store is refused (perl would call it).
- **008** next hit `&answer` (shares the caller's @_) and then a TOP: a sub
  whose loop `return`s merges with an early `return $label` of an argument
  nothing typed. Jump merges took their machine type from the Phi's stamp;
  the if-merge already took it from the arms. Now the same rule: arms of one
  repr give that repr, mixed scalar arms a Scalar, each arm boxed in its own
  block (switching current_idx to the arm's block before its terminator).
- **`&name;`** shares the inlined caller's arguments (`_frame_args`, set at
  each inline), or none at the top level. A shift/write of @_ on either side
  is refused -- the shared @_ would change under the other.
- **399** `my $show = sub {...}` read in a named sub: a shared file lexical.
  `_code_of_shared` scans every program node (plus anon-sub bodies and phase
  graphs, which `@PROGRAM` does not reach) for that name: exactly one store,
  of one capture-free AnonSub, and every other use a call through it. The
  store writes a CodeRef-tagged slot; the call checks the tag (perl dies
  before the store) and inlines the sub.

## Lessons

- An old test asserted the refusal that this lifted
  (llvm-arity-is-perls.t, `&name`): updated to assert perl's answer. When a
  refusal is lifted, grep the tests for its message.
- A use-site-typed parameter is a guess: `$f->(@_) + 1` inside a sub stays
  TOP (Analysis does not type an indirect call's result). Refused, not wrong.
