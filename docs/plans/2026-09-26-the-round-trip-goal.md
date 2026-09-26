# The goal: every corpus and perl t/* case round-trips through the IR

**Date:** 2026-09-26
**Status:** SPEC, revised against docs/assessments/0001-corpus-milestone-scope.md
and widened past one corpus. Supersedes
docs/plans/2026-09-26-corpus-milestone-scope.md.

## The goal, as stated

> The entire corpus and perl t/* suite parses and round trips through the IR;
> any missing idioms or syntax features from t/ are added to the corpus.

Three obligations, only the first of which the superseded spec covered.

## The criterion, and why a GAP count cannot express it

ROUND TRIP, not translation. Run the original under perl, render the graph back
to Perl, run that, diff. [[read-generated-output-not-tests]] automated.

The superseded spec's own measurement is the argument: over 212 cases the
producer reported 198 CLEAN, and the round trip confirmed 133 correct. All 43
of the differing cases had reported CLEAN. A GAP count is a first-failure
report and cannot defend this work.

## THREE TIERS, SEPARATE DENOMINATORS

One blended percentage would hide which population moved. Each tier reports its
own numbers.

### Tier 1 -- pvm's conformance corpus (the gate)

212 cases, 65 topics, at
`/home/perigrin/dev/pvm/.claude/worktrees/pu/conformance/mdtest/`. Owned by
pvm; ported and cut over, `.t` files deleted.

    PRODUCER    198 CLEAN    11 GAP    3 NOPARSE
    ROUND TRIP  133 correct  43 DIFFERS  31 REFUSED  2 NOJSON  3 NOPARSE

133/43 is the audited count, not the 134/42 first reported: case 025 drops a
`local` and reorders a store, so stdout matches while stderr differs.

The 209 recorded `output` blocks were verified against stock perl first --
209 match, 0 differ -- so a diff against a block is a diff against perl.

### Tier 2 -- perl's own t/base, t/comp, t/cmd

39 files. Producer, measured 2026-09-26 with `not_package=SoN`:

    24 clean    10 with a GAP    5 DEEP RECURSION

THE RECURSION CLUSTER IS NEW and appears in no earlier document: base/lex.t,
comp/colon.t, comp/parser.t, comp/require.t and cmd/subval.t all warn "Deep
recursion on anonymous subroutine at lib/SoN/FromOptree.pm line 538". It is a
FOURTH outcome, and an earlier tally of this tier missed it by counting
`grep -c 'GAP:'` over a stderr stream those warnings had flooded -- one file
came out with empty fields and 28+10 did not reach 39.

Round trip for this tier was last measured as 12 round-trips / 10 differs /
15 refused, BEFORE the `package=main` harness bug was found. Treat it as
unmeasured until re-run.

### Tier 3 -- PerlOnJava's unit corpus

986 construct-named files at
`~/dev/PerlOnJava/src/test/resources/unit/`. Producer: 857 CLEAN, 129 REFUSED,
with a ranked cause distribution in
docs/plans/2026-09-23-the-perlonjava-corpus-ranks-the-gaps.md.

Its round trip is dominated by one structural fact rather than by our defects:
891 of the 986 files `use Test::More`, and the deparser correctly refuses to
emit a call to a sub outside the graph. That makes this tier a strong PRODUCER
instrument and a poor round-trip one. It also contributed 13 node kinds no
fixture of ours had ever produced, which is what t/op-coverage.t now guards.

## OBLIGATION 3: contributing fixtures back to pvm

"Any missing idioms or syntax features from t/ are added to the corpus."

THIS INVERTS A DEPENDENCY AND NEEDS PVM'S AGREEMENT BEFORE ANY WORK.

The corpus is pvm's artifact. They have just completed a 14-tier port verified
byte-identical against the `.t` files it replaced, and their tiers carry an
op-budget lint: a case may only spell operators belonging to its tier or a tier
its own depends on. A fixture arriving from us lands in some tier and either
satisfies that lint or breaks it.

Open questions, none ours to settle alone:

  - who owns an addition, and does it go through them or land directly
  - which tier a newly-found construct belongs to, given the budget lint
  - whether a construct WE need but their parser does not yet handle is
    legitimate to add (it would fail their suite on arrival)

Their own note on the shape of a good fixture applies: a `parses: no` case
emits no ops, so it can spell an operator from a tier its own depends on where
a parsing case cannot. The two categories assert disjoint sets of facts.

## THE WORK

### Phase 0 -- the gate, and nothing before it

THE CORPUS IS NOT IN THIS REPOSITORY. Verified: no `conformance/`, no mdtest
topics under `t/corpus/`, and no test reads either. Under this project's TDD
rule EVERY fix below is untestable today, which makes this a prerequisite
phase rather than the footnote the superseded spec made it.

  1. Copy tier 1 in, with `conformance/GLOSSARY.md` -- twelve token category
     definitions the `tokens` block is written against. A corpus in our tree
     referencing undefined category names is a dangling reference.
  2. An extractor: one fenced `perl` block per case to a file. Blocks are
     SEPARATE COMPILATION UNITS -- no literate merging, because perl's
     compilation unit is the file and a merged boundary lets constants fold
     across it (`my $x = "abc"` folds into the pad slot and emits no VarDecl;
     `my $x = "abc" . $0` does not).
  3. A runner, checked into the repo. The harness that produced the headline
     numbers does not exist; three harnesses silently measured the wrong thing
     this session. See [[verify-the-harness-before-reading-its-output]].
  4. Key cases on (FILE, TITLE). The collision is present, not anticipated:
     218 headings, 205 unique, and `## The whole tier in one body` appears in
     14 files. Keying on bare title silently drops 13 cases.
  5. STATE THE STDERR CONVENTION. Case 025 matches on stdout and differs on
     stderr; whether that is a pass changes the headline count.
  6. Adopt pvm's rule: measure `perl -c` on EVERY case, not only those
     annotated `parses: no`, so an annotation disagreeing with perl is itself
     a failure.
  7. Skip non-parsing cases with the cause named, never a bare skip.

### Phase 1 -- split the omnibus fixtures before counting anything

EVERY CAUSE COUNT BELOW IS A FIRST-FAILURE REPORT UNTIL THIS IS DONE.

Cases 002 (21 lines), 003 (31 lines) and 006 (28 lines) are "whole tier in one
body" fixtures whose single GAP masks everything after it. Split into
one-construct probes, case 006 alone yields FOUR causes where the superseded
spec recorded one:

    while + last     last inside a loop body already has a loop condition
    do {} while      loop without a lowerable condition
    foreach + redo   loop control (redo) inside a loop body
    goto DONE        `goto` transfers control and is not compiled

And case 003's GAP masks BUCKET-3 defects: `localtime`, `caller` and the
`() =` count idiom are each producer-CLEAN in isolation and each round-trip
DIFFERS. So the buckets below are NOT DISJOINT until the split lands, and no
ordering over them partitions the work.

Splitting is also a tier-3 lesson: one construct per file is the property that
made PerlOnJava's 986 useful for ranking.

### Phase 2 -- renderer-only defects (cheapest, and mis-filed until now)

The superseded spec's central claim was "CHALK INHERITS ALL OF THESE". FALSE.
Case 193 is three lines:

    my @a = (10, 20);
    my $s = \@a;
    print "$$s[0] $$s[1]\n";

The graph is CORRECT -- `Ref/ArrayRef` over `ArrayLiteral`, `Subscript` into
it. The renderer emits `\@a->[0]`, which perl rejects; `(\@a)->[0]` prints 10.
Root cause `lib/SoN/Deparse.pm:361-362`, where the Ref branch does not
parenthesize and the `List` branch three lines above at :358 does -- carrying a
comment about this exact bug class.

Cases 008, 094, 193. One trigger. Chalk is unaffected.

### Phase 3 -- masked producer crashes

Cases 013 and 164 emit `{"methods":{}}` and the producer prints its own
verdict:

    INTERNAL ERROR translating main::__PROGRAM__ (masked as a silent skip --
    fix or convert to a clean GAP): Can't locate object method "NAME" via
    package "B::SPECIAL" at lib/SoN/FromOptree.pm line 4254

Reproduced in one line: `my @n = glob("*.nonexistent-xyz");`, and identically
for `<*.glob>`. Root cause `FromOptree.pm:4247` -- the `if ($gv)` guard does
not check that `$gv` is a `B::GV`, and a glob read gives `B::SPECIAL`.

The tier-2 deep-recursion cluster belongs in this phase: five files warning at
`FromOptree.pm:538` is the same class -- a producer failure that is neither a
clean graph nor an honest refusal.

[[crashes-mask-gaps]]. The producer's message contains the instruction: fix it
or convert it to a clean GAP.

### Phase 4 -- silent miscompiles in graphs that translate

Graphs that build without a GAP and are wrong. CHALK INHERITS THESE (the
qualified claim, after phase 2 removes the three that it does not).

Clusters, sizes corrected by the assessment:

    5  an lvalue-requiring op gets an inlined value      TWO causes, not one:
       "Can't modify constant item" (009, 198) and
       "Can't modify defined or (//)" (026, 180, 182)
    4  a TEXT SECTION AFTER THE PROGRAM is dropped       TWO mechanisms:
       format bodies (103, 104) and __DATA__ (161, 162)
    3  shadowed my/state collapse                        AN UNDECIDED FORK
    3  `use` neither loads nor imports                    NO FIX SHAPE YET
    3  regex-embedded code never runs                     NO FIX SHAPE YET
    2  a deref wraps the reference                        @{$r}, %{$r}
    ~  index 3-arg transposed, //= vanishing, @_ aliasing, substr lvalue,
       magic string increment, list-vs-scalar context (localtime, split,
       <$fh>), caller arity, prototype, die's list extent, \*STDOUT

THREE OF THESE ARE NOT SIZED AND MUST NOT BECOME ORDINARY ISSUES:

  - **shadowed my/state** is a DECISION, not a fix. Perl gives two distinct
    pad slots (`padsv_store[$x:1,5]` and `[$x:3,4]`); we build one PadAccess
    with no memory input and lose both stores. `Serialize/JSON.pm:150` dropped
    `targ` from the wire on the stated grounds that shadowed slots stay
    distinct via their memory inputs -- and there are none. Either build the
    memory edges or return the slot identity to the wire. Measured: the deref
    defect has one MemStart and this has zero, so they are related roots, not
    the same one.
  - **`use`** is BEGIN-time semantics: a compile-time require plus an import
    call, neither emitted. Needs a design spike.
  - **regex-embedded code** is a callee frozen into a pattern. Needs a design
    spike.

`__DATA__` and format bodies ARE NOT OPTREE OPS. A walker reading only the
optree cannot see them; the producer needs to read the FILE. A missing
mechanism, not a handler bug, and all four currently emit NOTHING -- a silent
drop.

### Phase 5 -- honest producer GAPs

Counts pending phase 1. As recorded: runtime range with a non-constant bound
(3), delete slice (2), range in a loop body, redo in a loop body, last with an
existing loop condition, multiconcat stacked destination, goto.

Case 133 is labelled `do BLOCK while COND` from its fixture TITLE, not its
message -- its GAP is the catch-all at `FromOptree.pm:917`, which a different
construct also reaches. Per [[a-refusal-test-must-name-its-cause]] it cannot be
counted as one cause.

### Phase 6 -- the goto family, and it needs chalk first

Scoped in docs/plans/2026-09-25-goto-is-polymorphic-over-its-operand.md: T1
resolves the operand type and emits distinct node kinds -- a tail call for a
CodeRef, a static control edge for a constant label, a dynamic-label jump for a
Str. Four of five forms are lowerable.

BLOCKED ON CHALK. `tail` is not a Call attribute anywhere in chalk's IR layer
and there is no label-jump class. Its NodeFactory is an explicit use-list with
kind dispatch, so an unknown kind is a hard failure, not a skip.

And chalk reads our `lib/` LIVE -- `son-corpus-wide.t:17` is
`$ENV{PERL5_SON_LIB} // "$HOME/dev/perl5-son/lib"` -- while
`Serialize/JSON.pm:568` emits `version => 1` that nothing checks. There is no
released wire between the projects, so a producer change lands in chalk's suite
with no gate. Its own corpus gate skips silently without an LLVM-15 `lli`, so
it may currently be inheriting nothing and reporting a pass.

Precondition: chalk adds the classes and declines the dynamic-label case BEFORE
the producer stops refusing. [[removing-a-gap-can-create-a-miscompile]].

### Phase 7 -- tiers 2 and 3

Re-measure tier 2's round trip with the corrected harness (the 12/10/15 predates
the `package=main` fix). Then work the ranked tier-3 causes, where
`map`/`grep` contribution arity leads at 11 files -- and re-examine its FACT
classification, since three FACTs dissolved under measurement on 2026-09-25 and
that one rests on two files where both were `&{$sub}`.

### Phase 8 -- contribute fixtures back (needs pvm's agreement, see above)

## ACCEPTANCE

Per issue, not per cause:

  - NAMED CASE IDS flip from DIFFERS/REFUSED to ROUNDTRIP, and
  - a full re-run of the affected tier shows NO REGRESSION elsewhere.

"The cause no longer reproduces" is NOT acceptance. Two cases sharing a
message may have different roots, and a fix can move one without moving the
count.

Per tier, a milestone is met when that tier's round trip is 100% of its
parseable cases, minus an explicitly listed set of honest refusals each naming
a cause.

## WHAT IS EXCLUDED, AND SAID SO

  - The 20 deparser-only refusals (measured: exactly 20, and the
    GAP-intersect-REFUSED set is all 11). Ours alone, not chalk's. Either
    triage them into a phase or state they are out of the target number --
    leaving them in makes the REFUSED count unreadable as progress.
  - The 2 NOJSON cases, undiagnosed. Note they are the same failure class as
    phase 3 and should probably move there.
  - 16 DIFFERS cases with no diagnosis: 005 008 009 025 026 048 058 061 094
    106 107 180 182 193 194 198. The companion document's "sampling COMPLETE"
    is true of ONE failure mode.

## Open, and not ours to close

  1. pvm's agreement on fixture contribution (obligation 3).
  2. chalk's agreement on the goto node kinds (phase 6).
  3. chalk's stale `ArrayRef`/`HashRef` classes. Not a live disagreement: our
     `IR/Node/ArrayLiteral.pm:13-15` records that it WAS `ArrayRef`, that chalk
     read the op name, assumed it agreed with the stamp, boxed unconditionally,
     and emitted nothing for 37 corpus cases. We renamed; chalk is stale. Its
     shape check is a SUBSET check, so extra producer nodes do not fail it --
     missing spec nodes do.
  4. Whether `son-corpus-wide.t` is currently running or skipping in chalk. Not
     observed; read from its `plan skip_all` guards.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
