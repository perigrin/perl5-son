---
name: a-copy-is-a-location-and-a-local-has-a-way-out
description: "Branch copy-unwind: design A (a copy of a my hash is a new location, always) and B1 (a rethrow edge per may-die point under a live local, no eval open); the re-audit's classes A and B lowered; what the neighbours and the old fixtures taught"
metadata:
  type: project
---

Branch `copy-unwind` (2026-11-24; baseline section 22; plan
docs/plans/2026-11-24-copy-and-local-unwind.md, approved by perigrin).

**A.** `my %c = %h` always makes a HashLiteral of its own, read where it is
made. The elision was sound only while a syntactic write scan proved
neither side written, and class A was that scan's holes. A `my` aggregate
bound to another name's literal is a GAP by name in the padav/padhv handler
(the design put it in `_place`; the lookup is where the name is known).
**B1.** Each graph has a sub frame below its eval frames (`@EXC_FRAMES`,
`rethrow => 1`): where no eval of the graph is open and a `local` is live,
`_exc_edge` makes an Exc, the restores, and an Unwind with
`fields.rethrow`. chalk's `after_call` takes it (`rethrow_way`, walked at
once under local copies of memo/stood/passed/arm_settled) and the rethrow
returns with the dying flag set. W6 deleted; V10 and L7 hold the edges.

**Lessons:**

- **Probe the neighbours of a lifted refusal.** Removing class A's GAP
  showed two older silent wrongs of the same family that no probe had: a
  `my` hash among other pairs floated past a later store (`my %d = (%h,
  x => 1)`), and the padav list shortcut pushed an array literal's inputs,
  so `my @l = (%h); $h{a} = 2; "@l"` joined %h itself. Both were wrong at
  base (cpa21, cpa23, cpa30, cpa31).
- **A refusal hides what is behind it.** Of the 28 class-A rows two (ren26,
  ren35) and of the 24 W6 rows two (req32, req35) now meet a T2 limit that
  the same program without the copy or the `local` meets too. Probe the
  program without the feature before blaming the feature.
- **Decide "in an eval" by where the edge goes.** L7 and V10 first asked
  the thrower's `eval_id`; a die in a sort block inlined in an eval and a
  known string eval's call carry none, and two corpus cases stopped loading.
  The interval-oracle test found it (LOADFAIL), not the probes.
- **A background run reads the live tree.** A probe sweep over the
  producer's lib was mixed by B1 edits made while it ran; stopped and rerun
  on `git archive` of the A commit.
- **`git add` of a deleted path fails the whole add.** The A commit went
  in without its lib change; check `git show --stat` after every commit.
- **The guard found what the design missed.** "Arrays already always
  copy" was true only where the list shortcut flattens; an array whose
  literal holds a ternary was bound as the source's own literal (cpa33,
  cpa34 silent wrongs at base). The padav/padhv guard refused it in a
  deparser test; A now copies a `my` array too. The guard compares the name
  as spelled (`%PAD_SYMBOL`: a re-declared `@a` is `a__2`).
- **The wire cannot say a local is live.** `my $c = $G; $G = 0; ...; $G =
  $c` is the shape of `local $G = 0`. A liveness rule in chalk's L7
  refused every Test::Chalk program; L7 keeps the design's structural rule
  only, and V10 (over the ratchet's wires) keeps the liveness one -- it
  stops at any restore of the save, or a loop's back edge makes a call at
  the loop's top "live" (lo22).
- **An Exc is a consumer that takes no value** -- again (stage 8 said so for
  calls): `list_only` took a rethrow Exc on a pinned `keys %$self` for a
  scalar use (c178).
- **No eval, no observer:** with no eval in the program a die exits, so a
  restore on the way up matters only to END blocks (T2 refuses those) --
  `after_call` stays gated on `has_eval`.

Related: [[the-re-audit-s-wrong-answers-refused]], [[an-eval-s-die-has-its-way-out]],
[[a-verifier-that-reads-a-derived-flag-checks-itself]].
