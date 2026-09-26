# Assessment: the corpus milestone scope

**Subject:** docs/plans/2026-09-26-corpus-milestone-scope.md
**Date:** 2026-09-26
**Gate:** crochet:assess
**Outcome:** MODIFY. Do not refine as written.

## Session

Three participants, dispatched as fresh subagents (not forks, so none carried
the author's reasoning). The author's session drafted this minute and held a
view, so it is NOT counted as an independent judgment.

| participant | lens | recommendation |
|---|---|---|
| code-auditor | does the spec's claim about the codebase hold | MODIFY |
| project-plan-reviewer | is this decomposable as written | MODIFY |
| code-reviewer | the cross-project contract | MODIFY |

All three reported. One round; it did NOT reach a fixed point -- each
participant raised findings the others did not, so a second round is owed if
the spec is revised substantially. Every blocking finding below was
re-verified by the author's session against the code before being recorded.

## The thesis survives

Reframing "build IR for the corpus" as a CORRECTNESS problem rather than a
coverage one is correct, and no participant disputed it. The round-trip gate
is the right deliverable. The load-bearing measurement -- 209 of 209 recorded
output blocks matching stock perl, so a diff against a block is a diff against
perl -- was independently re-derived and holds under both stderr conventions.

Also re-derived exactly: the producer census 198 CLEAN / 11 GAP / 3 NOPARSE,
with the 11 GAP ids enumerated (002 003 006 112 116 117 121 133 168 169 170),
and NOPARSE = 3 (024 069 070) confirmed as deliberate syntax-error fixtures.

## BLOCKING

### B1. "CHALK INHERITS ALL OF THESE" is false, and it is the spec's own argument

The spec asserts in capitals that none of the 42 is a deparser artifact, and
uses that to order bucket 1 first. Falsified on a three-line case (193):

    my @a = (10, 20);
    my $s = \@a;
    print "$$s[0] $$s[1]\n";

Re-verified by the author's session. The GRAPH IS CORRECT --
`5 Ref/ArrayRef in=[4]` over `4 ArrayLiteral/Array`, with `8 Subscript` into
it. The RENDERER emits `\@a->[0]`, which perl rejects ("Can't use an array as
a reference"); `(\@a)->[0]` prints 10.

Root cause `lib/SoN/Deparse.pm:361-362` -- the Ref branch does not
parenthesize, while the `List` branch three lines above at :358 does, carrying
a comment about exactly this class of bug. Cases 008, 094, 193 share the
trigger.

Consequence: three of the 42 are renderer-only, chalk is unaffected by them,
and they are the CHEAPEST fix in the document while being filed as chalk work.
A fourth bucket is needed for renderer-only defects.

### B2. Two cases counted CLEAN are masked producer crashes

Cases 013 and 164 emit `{"methods":{}}`. The producer prints its own verdict:

    B::SoN: INTERNAL ERROR translating main::__PROGRAM__ (masked as a silent
    skip -- fix or convert to a clean GAP): Can't locate object method "NAME"
    via package "B::SPECIAL" at lib/SoN/FromOptree.pm line 4254.

Re-verified in one line: `my @n = glob("*.nonexistent-xyz");` reproduces it,
as does the `<*.glob>` spelling. Root cause `FromOptree.pm:4247` -- the
`if ($gv)` guard does not check that `$gv` is a `B::GV`, and a glob read gives
`B::SPECIAL`.

The spec filed these under deparser refusals, "ours alone rather than
chalk's". They are neither refusals nor deparser defects. This is
[[crashes-mask-gaps]] recurring, and the producer's own message contains the
instruction the spec lost: fix it or convert it to a clean GAP.

### B3. Cause counts are first-failure reports, so the buckets do not partition

Three of the 11 GAP cases are omnibus "whole tier in one body" fixtures: 002
(21 lines), 003 (31 lines), 006 (28 lines). One GAP message masks everything
after it.

Split into one-construct probes, case 006 alone yields FOUR causes where the
spec records one:

    while + last     last inside a loop body already has a loop condition
    do {} while      loop without a lowerable condition
    foreach + redo   loop control (redo) inside a loop body
    goto DONE        `goto` transfers control and is not compiled

Worse, case 003's GAP masks BUCKET 1 defects -- `localtime`, `caller` and the
`() =` count idiom are each producer-CLEAN in isolation and each round-trip
DIFFERS. So a GAP case can hide silent miscompiles, which means bucket 1 and
bucket 2 are not disjoint and the ordering rationale does not partition the
work. [[clean-counts-cannot-measure-progress]] applied to GAP counts.

### B4. The corpus is not in the repository, so nothing in the spec is testable

Verified: no `conformance/`, no mdtest topics under `t/corpus/`, and no test
reads either. Under this project's TDD rule every fix in all three buckets is
untestable today.

The spec files the corpus copy, the extractor, the runner and the
duplicate-title guard in a trailing "What must come with it" section. They are
the FIRST PHASE and every other issue depends on them.

### B5. The goto wire change has no counterparty and no agreement

The goto doc decides three new node kinds. Checked against chalk: `tail` is
not a Call attribute anywhere in its IR layer, and there is no label-jump node
class. Chalk's NodeFactory is an explicit use-list with kind dispatch, so an
unknown kind is a hard failure rather than a skip.

Compounding it, chalk reads our `lib/` LIVE -- `son-corpus-wide.t:17` is
`$ENV{PERL5_SON_LIB} // "$HOME/dev/perl5-son/lib"` -- and
`Serialize/JSON.pm:568` emits `version => 1` which nothing on either side
checks. There is no released wire between the projects. Shipping the producer
side first turns chalk's gate red with no coordination point.

Precondition: chalk adds the classes and declines the dynamic-label case
BEFORE the producer stops refusing. Same ordering
[[removing-a-gap-can-create-a-miscompile]] already teaches.

## PARTIAL

### P1. The lvalue cluster is 5 cases and 2 causes, not 8 and 1

The spec's "ONE CAUSE, EIGHT CASES ... cheapest big win" sets the work order.
Measured: five compile-time `Can't modify` failures (009, 026, 180, 182, 198),
in two sub-causes -- "constant item" (a folded literal reached the lvalue slot)
and "defined or (//)" (an inlined `//` expression did).

### P2. The headline is 133/43, not 134/42

Case 025 is a deterministic miss across three runs. `local $SIG{__WARN__}` is
DROPPED and the store is reordered below both `warn` calls, so stdout matches
(`12`) while stderr gains two warnings perl suppresses. A stdout-only
comparison scores it clean.

Consequence: the gate's stderr convention is unstated in the spec and changes
the headline. Also, the per-mode breakdown 29/10/8 in the companion document
was never republished after the `not_package` fix; measured now it is 28
wrong-output / 6 dying / 8 invalid-Perl / 1 stdout-ok-stderr-diff.

### P3. 16 DIFFERS cases have no diagnosis

005 008 009 025 026 048 058 061 094 106 107 180 182 193 194 198. The companion
doc's "sampling COMPLETE: 29 of 29" is true of one failure mode; bucket 1's
cluster table reads as exhaustive over all 42 and is not.

### P4. The harness that produced the headline does not exist

`rt2.txt` has no generating script. The surviving harnesses are `oracle.pl`
(compares against live perl, not the recorded blocks) and a `count.sh` still
carrying the `package=main` bug. Three harnesses silently measured the wrong
thing this session; an unreproducible measurement is not one. The auditor could
only re-derive by writing a fresh harness, which is how P2 surfaced.

### P5. One bucket-2 entry is named from a fixture title, not a message

Case 133's GAP is the catch-all at `FromOptree.pm:917`. The spec labels it
`do BLOCK while COND` from the fixture title; isolated, that construct gives a
different message. Per [[a-refusal-test-must-name-its-cause]], a catch-all two
constructs reach cannot be counted as one cause.

## READY, and better than the spec claimed

  - "~20 of 31 refusals are deparser-only" is EXACTLY 20, and the
    GAP-intersect-REFUSED set is all 11. The hedge can be dropped.
  - No DIFFERS case is also a producer GAP -- intersection empty, confirmed.
  - The text-section cluster (103 104 161 162) is confirmed, though it is TWO
    mechanisms (format bodies, `__DATA__`) rather than one.

## Stale items the spec carries as open

  - **ArrayRef/HashRef/CompoundAssign.** Not an open disagreement. Our
    `IR/Node/ArrayLiteral.pm:13-15` records that it WAS `ArrayRef`, that chalk
    read the op name, assumed it agreed with the stamp, boxed unconditionally,
    and emitted nothing for 37 corpus cases. We renamed deliberately; chalk's
    class is stale. `CompoundAssign` exists in both. The real diff is 20 nodes
    we emit that chalk has no class for -- and chalk's checker is a SUBSET
    check, so extra producer nodes do not fail it. Missing spec nodes do.
  - **The block-per-layer locality tradeoff.** pvm's `FORMAT.md:30,36` already
    settled it: "An unknown block tag is IGNORED. B::SoN fills `ir`, we fill
    `tokens`, and neither is the other's to check", and "the `ir` block ... we
    do not fill it and do not validate it." The question is OURS ALONE and
    non-blocking. Our format doc should cite FORMAT.md as authoritative and
    adopt the unknown-tag rule.
  - **The duplicate-title guard.** Present, not anticipated: 218 headings, 205
    unique, and `## The whole tier in one body` appears in 14 files. Key on
    (file, title).

## Required before refinement

1. Add a renderer-only bucket; move 008, 094, 193 into it (B1).
2. Reclassify 013 and 164 as producer crashes at `FromOptree.pm:4253` (B2).
3. Split the omnibus fixtures 002, 003, 006 before counting anything (B3).
4. Promote the infrastructure to a prerequisite phase gating every other
   issue (B4).
5. Get chalk's agreement on the goto node kinds, landed before the producer
   change (B5).
6. State the gate's stderr convention, re-publish the mode breakdown, and
   check the harness into the repo with the corpus (P2, P4).
7. State per-issue acceptance as "named case ids flip to ROUNDTRIP and a full
   corpus re-run shows no regression", not "the cause no longer reproduces".
8. Either scope the 20 deparser-only refusals out of the milestone's target
   number, or triage them first.

## Note on this minute

The author's session drafted it and is not an independent judgment. Two of the
three participants' blocking findings were re-verified here against the code
(B1 on case 193's graph, B2 by reproducing the crash in one line, plus the
chalk coupling, the ArrayLiteral history, pvm's FORMAT.md rules and the title
collision count). The third participant's numeric re-derivations were not
re-run a second time; its harness is at
`AUDIT_rt.txt` / `audit_rt.pl` in this session's scratchpad and should be
checked into the repo per P4.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
