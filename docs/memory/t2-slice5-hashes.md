# T2 slice 5: hash references, pvm 093 (2026-11-06)

- Chosen by perigrin: "start with 093 in T2". New causes go into T2 slices,
  not Context.pm patches (T2 is the architecture; Context.pm the fallback).
- Built (chalk 4bd2ca8e); test t2-slice5-hashes.t. Census 411 -> 412.
  - `{...}` is a %Slot with tag 5 over a heap hash (pairs in an %Array):
    t2_hnew/t2_hset/t2_hget. `$h->{k}` through a %Slot; undef on a miss;
    a run-time stop when the %Slot holds no hash.
  - `!` lowers in T2.
  - An arm that jumps to a merge further on (`// return ...`) is parked in
    `$b->{jumps}` and joined there (`join_jumps`); a jump never joined
    falls back.
- Lessons:
  - reads_before hoisted `$t->{v}` above `return 0 unless $t`: a perl-safe
    read became a stop. Hash element reads stay where they are.
  - A named hash reaches T2 as Subscript over a Constant ("main::ENV").
    It looked like a reference read and stopped at run time (probes
    review2/probes/cs/e2, e3). Refused now; Context.pm still lowers it.
  - Probe names repeat across directories: find a WRONG by path, not name.
  - Tests that assert Context.pm's IR shape break when T2 takes the
    program; widen them to T2's form when the behavior tests still pass
    (CBS9, as slice 4 did for A2/A3).
- Next for T2: a named %h, hash stores, exists/delete/keys.
