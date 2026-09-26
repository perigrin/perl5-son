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

    ROUND TRIP  154 correct  36 DIFFERS  21 REFUSED  2 NOJSON

**154 of 213 as of 2026-09-26 evening**, from 135 at the start of that day.

THE DENOMINATOR MOVES, and this is the second time it has caught someone. The
corpus is pvm's and grows while we measure: it went 210 -> 213 output blocks in
one afternoon, and reading the harness against a remembered 210 made its own
correct output look like a parse defect for a few minutes. Measure it every
run --

    grep -c '^```output$' $SON_CORPUS/*.md | awk -F: '{s+=$2} END {print s}'

-- and check it against the `cases:` line before reading anything below it.
`tools/corpus-roundtrip.pl` says so in its header for the same reason.

The count is OUTPUT BLOCKS rather than perl blocks: a few cases carry
`parses: no` and pin no output at all, because perl builds no optree for a
program it will not compile. pvm reached 3 for that set by parsing the blocks
after `grep -c 'parses: no'` gave 5 -- the phrase appears in prose too.

    EMITS_INVALID_PERL  5 -> 0

Every emission in the corpus now COMPILES, which is the floor worth tracking
separately from the round-trip percentage.

THE NAME HAS A SUBJECT AND IT IS US. This counts programs THE DEPARSER
PRODUCED that perl refuses -- not corpus cases we failed to read. An input
parse failure is impossible by construction here: perl itself compiled the
case to build the optree B::SoN walks, so a successful parse is GIVEN rather
than asserted. Shortened to `INVALID_PERL` it reads as a claim about our
parsing, which is not a thing we do.

    corpus case (valid perl) -> B::SoN -> IR -> deparser -> emitted perl
                                                            ^ the invalid one

The five that did not compile were four causes:

  - `is_compound` claimed a ONE-OPERAND op. `lock`, `pos` and `tied` take a
    variable, and the compound-assignment input swap replaced it with the
    slot's bound value. Every compound-assignment op is a BINOP -- measured --
    so `@inputs >= 2` is the fact. (4e9b758)
  - A destructive s/// or tr/// on a LEXICAL had no lvalue. Fixed by demoting
    the slot the way `\$x` already does; see
    2026-09-26-a-destructive-subst-on-a-lexical.md for why it took four parts.
  - `\(&twice)->(21)` -- `->` binds tighter than `\`, so the arrow landed
    inside the reference and called `&twice` with no arguments. An indirect
    call parenthesises a callee that is not a simple variable.
  - A folded `\"x\n"` records the REFERENT, and the renderer supplied only the
    backslash: `\x` plus a literal newline, which COMPILES and opens a handle
    on the wrong string. Numeric referents stay bare (`$/ = \3`).

THREE OF THOSE FOUR COMPILED OR LOOKED RIGHT at the check below the one that
caught them. Recorded as [[compiling-is-not-running]].

A fifth, which compiled and ran and gave a different answer:

  - `split " "` is AWK MODE -- leading whitespace stripped, runs collapsed --
    and `split / /` is a literal one-space pattern. Measured on `"  a b "`,
    4 fields against 2. Both reached the producer as `split(qr{ }, ...)`.
    The separator is PMf_SKIPWHITE (2048) in the op's pmflags, WHICH B::CONCISE
    DOES NOT PRINT: both forms render as `split(/" "/ => @a)` in a dump, so the
    optree looked identical until the bit was read directly. Emitted now as a
    STRING constant, which is how the source spells awk mode.

THE TWO HARNESSES DISAGREE BY ONE CASE, and the difference is the stderr
convention rather than a defect either found. Ours compares STDOUT ONLY, so it
scores case 025 ROUNDTRIP; the auditor's compares stderr too and scores it
DIFFERS, giving 133/43. An earlier revision of this document wrote 133 without
reconciling the two, which is the error this note replaces.

The auditor is right about the underlying defect and our gate cannot see it:
025 emits two warnings real perl suppresses, because `local $SIG{__WARN__}` is
DROPPED and the store reordered below both `warn` calls. Measured:

    stdout only   12                        matches the recorded block
    with stderr   ab at line 3 / a at line 4 / 12

So the gate needs a decision, recorded in phase 0: compare stderr and take
133 as the honest baseline, or compare stdout and carry a list of cases whose
stderr is known to differ. Scoring on stdout alone while calling the result a
round trip is the weaker of the two and should not be the silent default.

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

Round trip, re-run 2026-09-26 against HEAD and confirming an earlier figure
that predated two harness fixes:

    12 round-trips    10 differs    15 refused

Baseline before the short-circuit control fixes in 2fd1215 was 7/11/19, so
those bought +5 round-trips and took the successor-refusal class from 4 files
to 1.

`comp/package.t` is now a DIFFERS THAT A REFUSAL USED TO HIDE: the emitted
program dies on `xyz->new` because `sub new` declared inside `package xyz` is
emitted into `main`. A pre-existing package/method-declaration defect the
removed refusal was masking -- [[removing-a-gap-can-create-a-miscompile]]
caught in the act.

RE-MEASURED after the five fixes of 2026-09-26 (ref-subscript parens, the two
gv/stash fixes, Negate/Complement, the runtime range): STILL 12/10/15. None of
those causes appears in this tier, so tier 1 progress does not transfer and the
two tiers need separate work.

### Re-measured 2026-09-26 evening with tools/perl-t-roundtrip.pl: 12 / 39

STILL 12, after the six emission fixes that took tier 1 from 135 to 154. None
of those causes appears in this tier, which confirms across two measurements
that TIER 1 PROGRESS DOES NOT TRANSFER. The tiers need separate work, and a
corpus percentage is not a proxy for this one.

The census is in the repo now (it was ad-hoc): 12 ROUNDTRIP, 10 DIFFERS,
10 REFUSED, 6 GAP, 1 NOJSON. Per tier -- base 7/9, comp 4/25, cmd 1/5. The
bucketing differs from the 12/10/15 above only in splitting GAP and NOJSON out
of REFUSED; the round-trip count is the same number.

Its FIRST run reported 9 of 9 REFUSED for t/base, every one of which renders:
a `require SoN::Deparse` inside `eval`, with `-I` passed only to the child
processes. A uniform result is a harness bug until proven otherwise, and this
one was caught by running it against a tier whose answer was already known.

### A REFUSAL CAN BE SECOND-ORDER, and the mechanism is worth knowing

`a call to X, which is not in the graph` is the most common single refusal
message, and it has two unrelated causes. The mechanism, reproduced minimally:

    sub helper { my $x = shift; *FH = \*STDOUT; return $x + 1 }
    print helper(1), "\n";

      skipped main::helper: GAP: assigning to a glob (*FH)
      REFUSED: GAP: a call to `main::helper`, which is not in the graph

ONE SUB GAPS AND TAKES ITS CALLER DOWN. The producer's per-sub skip is honest,
and the deparser's refusal is honest, but the reported cause names the CALLER
and the fixable defect is in the CALLEE. Of the ten refusals, three are this
shape (base/rs.t, cmd/switch.t, comp/proto.t -- 2, 3 and 3 skipped subs).

The other cause is a callee in a DIFFERENT COMPILATION UNIT -- `plan` reached
through `require './test.pl'` in a BEGIN block, as comp/filter_exception.t does.
Nothing is skipped there and nothing is defective; B::SoN sees one unit at a
time.

A FIRST PASS AT THIS SECTION GOT IT WRONG, by grouping files from a `=== `
header list without checking which BUCKET each fell in: comp/fold.t and
comp/our.t were counted as refusals when they are DIFFERS, and comp/decl.t and
comp/hints.t were counted here when they do not refuse at all. Both halves were
overstated. The corrected split is 3 second-order and 1 cross-unit, with the
remaining 6 refusals having causes of their own.

### The actionable list: 14 GAPs over 9 files, no cluster above 2

Every sub skipped across base+comp+cmd, by its GAP. NOT all of these block a
round trip -- a skipped sub only refuses the program when something CALLS it,
which is why nine files carry skips and only three refuse for that reason:

    2  map body contribution of unknown arity
    2  assigning to a glob (*FH)
    1  `write` whose format is not installed on the handle
    1  void-context 'or' arm did not converge
    1  void-context 'and' arm did not converge
    1  untranslatable op inside an if/else arm (stopped at `return`)
    1  untranslatable op inside an if/else arm (stopped at `range`)
    1  undef(EXPR) on a glob (rv2gv)
    1  loop-carried value loses its stamp (unstamped back-edge)
    1  function exit inside a loop body
    1  an element store inside a nested one-armed branch
    1  a loop control (`next`) inside a branch arm
    1  a bare block with a `continue` block and a next/last/redo

### FACT vs ARTIFACT, first two classified

**`map body contribution of unknown arity` -- ARTIFACT, fixed.** The arity is
not in the program, which sounds like a FACT until you ask who needs it. perl
does not count either: a map body's contribution is FLATTENED at runtime. The
refusal was a property of OUR DESUGARING -- map into a loop with a counted
ListAppend accumulator -- and the mechanism to describe it already existed:

    my @src=(1,2); map { @src } (0,0)
      my @phi4_next = (@phi4, 1, 2);   prints 4

An aggregate body has equally unknown length and flattens correctly, because
ListAppend renders `(acc, contribution)` -- a plain list, so the emission defers
to perl exactly as the source does. A list-returning Call is the same shape.

The tell that it was an artifact: it ALSO refused `sub one { return 7 }`, whose
arity is one. The producer could not NAME the arity, which is a different thing
from needing it.

GREP KEEPS THE CHECK. Its body is a PREDICATE -- the contribution is the
ELEMENT, and the body's value only decides whether to take it -- so a
multi-value body there would append the wrong thing and the arity question is
real. Same refusal, opposite classification, one `if ($collect ne 'map')` apart.

Effect on the tier: `comp/utf.t` went 1 GAP -> 0 and `comp/proto.t` 3 skipped
subs -> 1, but NEITHER round-trips yet -- each has a distinct downstream cause
(`PostfixDeref` with no aggregate sigil; `a control node with 2 successors`).
So the count stayed 12/39, which is what a tier with no clusters looks like
when one cause is removed.

**`assigning to a glob (*FH)` -- FIRST CALLED A FACT; IT IS AN ARTIFACT.**
Corrected below; the original reasoning is kept because the way it was wrong is
the reusable part. See docs/plans/2026-09-26-the-slot-is-the-stamp.md.

THE CORRECTION: THE STAMP NAMES THE SLOT. `*X = EXPR` binds the slot given by
EXPR's TYPE, and the lattice already relates those types --

    exactly one ref kind under the stamp  -> that slot, statically resolved
    five (Scalar, Ref)                    -> one slot, kind chosen at runtime
    none, and Glob/GlobRef/Str            -> every slot

-- so nothing is missing. `_resolve_glob_slots` reads the stamp correctly and
then looks it up in an EXACT-MATCH hash of four keys; anything else deletes the
graph. Probed on base/rs.t: `type=Scalar`, which is not "unknown" but the honest
position of a value whose ref-kind has not narrowed.

WHAT MADE THE FIRST ANSWER WRONG: I measured that one callsite binds different
slots per call, concluded "nothing in the program says which", and stopped. The
missing question was WHO NEEDS TO KNOW -- the same question that had just
dissolved the map-arity refusal an hour earlier. The stamp is the answer at
whatever precision inference reached, and a backend either narrows it or
declines the node. Our refusal message even says "perl itself defers the
choice", which is verbatim the sentence
[[a-t2-difficulty-is-not-a-t1-refusal]] was written about.

The original reasoning follows. It is accurate about perl and wrong about us:

**The other two-file cluster, and what looked like the opposite answer.** `*FH = shift` in base/rs.t aliases
the slot chosen by the RUNTIME TYPE of the value. Measured:

    sub s1 { *X = shift; ... }  open(my $h,"<",...); s1($h)   aliases IO
    sub s2 { *Y = shift; ... }  our @A=(1,2);        s2(\@A)   aliases ARRAY

Two calls, one callsite, different slots. Nothing in the program says which, so
the refusal message is accurate as written and this is a genuine T1 GAP.

AND IT IS NOT OVER-REFUSING, which is the part worth checking rather than
assuming. Where the RHS type IS known the same construct lowers and
round-trips:

    our @SRC = (1,2,3); *crackers = \@SRC;
      *main::crackers = \@main::SRC;        prints `1 2 3`

`_resolve_glob_slots` resolves a leaf ref type and refuses everything else --
which is not the same as "refuses when the type is Unknown", and that elision is
where the first classification went wrong. `Scalar` and `Ref` are not Unknown.

**`untranslatable op inside an if/else arm (stopped at `range`)` -- ARTIFACT,
but a big one, and the MESSAGE NAMES THE WRONG OP.** From comp/proto.t's
`sub list_or_scalar { wantarray ? (1..10) : [] }`. Reduced:

    sub f { wantarray ? (1..3) : [] }   GAP: ... stopped at `range`
    sub f { wantarray ? (7, 8) : [] }   GAP: a ternary with a multi-element
                                             list arm not yet lowered

It is NOT the range. ANY multi-element list arm refuses; the range case merely
hits a different message first, which would have sent a reader to
`_handle_range` (already written, and irrelevant here).

The optree names both arms completely --

    3  <|> cond_expr(other->4) K/1
    4      pushmark; const 7; const 8; list
    9      emptyavhv

-- so the program says exactly what each arm is, and by the layering rule this
is an ARTIFACT. But the refusal is honest about its own mechanism: the arm-value
handling detects a stack depth-delta != 1 and GAPs rather than silently dropping
the extra values. Expressing it needs PER-ARM VALUE LISTS through the Phi merge,
which does not exist -- this is real work, not a missing delegation.

Recorded rather than started. The message should name the list arm rather than
whichever op the walk stopped on.

THERE IS NO CHEAP WIN HERE, and that is the finding. Tier 1's work was
profitable because five emission causes covered nineteen cases; this tier is
fourteen causes for nine files, and several are control-flow shapes (loop exits,
branch arms, memory-Phi merges) rather than spellings. Ranking by cluster size
picks nothing; the honest order is by whether a GAP is a FACT about the program
or an ARTIFACT of the walker, and that has not been classified yet.

### The 15 refusals, and why the headline cause is not what it says

    5  "a call to X, which is not in the graph"
    5  no main::__PROGRAM__ / NO GRAPH
    2  a `caller` bound to a list
    3  singletons (PostfixDeref sigil, Assign with no targets, 2 successors)

THE DOMINANT CAUSE IS A DOWNSTREAM SYMPTOM. Measured per file, the five
"not in the graph" refusals split:

    cmd/switch.t   3 producer GAPs upstream   next-in-a-branch-arm, and two more
    base/rs.t      2 producer GAPs upstream   assigning to a glob (*FH)
    comp/parser_run.t        0   genuinely external -- require ./test.pl
    comp/filter_exception.t  0   genuinely external
    comp/require.t           0   genuinely external

So `main::foo1` is "not in the graph" because the PRODUCER skipped it -- it is
defined at cmd/switch.t:5 and holds `next if ...` inside an `until` with a
`continue` block, which is the 14th GAP kind. The deparser's message names a
missing sub where the cause is an unlowered construct one layer up.

Consequence for reading this tier: 3 of 15 refusals are an external-dependency
fact about perl's own test harness (`require ./test.pl` defines `plan`), not a
defect. The other 12 are ours, and at least 2 chain from producer GAPs that
also appear in tier 1's bucket 5.

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

### Phase 8 -- contribute fixtures back (ASKED 2026-09-26, awaiting pvm)

Three questions sent to pvm, because none is ours to settle:

  1. OWNERSHIP -- does an addition go through them, or can we land one directly
     in conformance/mdtest/ and let their suite judge it?
  2. TIER PLACEMENT AND THE OP BUDGET -- a construct found in perl's t/ arrives
     without a tier, and their lint only permits operators from a case's own
     tier or one it depends on. Who decides, and is "spells a later tier's
     operator" a reason to reject the case or to move the operator earlier?
  3. A CONSTRUCT THEIR PARSER CANNOT YET HANDLE -- adding it as `parses: yes`
     would fail their suite on arrival. Is a known-failing conformance case
     legitimate, or does it wait?

THE WORKED EXAMPLE SENT WITH THE QUESTION, so it is concrete rather than
hypothetical: perl's t/cmd/switch.t:5 holds `next` inside a branch arm, in an
`until` with a `continue` block, with `return` inside both. We refuse it
honestly; their corpus has no case of that shape. It is exactly what the goal's
third clause means and it has no obvious tier.

Also flagged to them: their own unknown-tag rule means a case we contribute
could carry an `ir` block they never validate, so they should know we would use
it rather than discover it.

UNTIL AN ANSWER ARRIVES this phase is blocked in a way no amount of work here
changes -- which is worth stating plainly, because a goal containing it will
read as unmet regardless of tier 1 and tier 2 progress.

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

## A citation hygiene finding, from pvm's side and ours

pvm found that THREE of their corpus cases cited issues in state DONE --
corpus-construction issues that never owned a parser gap. Their
`TestRefusalCitationMustResolve` passed all three because the citations RESOLVE;
they were simply the wrong issues. Their guard checks existence, not state.

OURS IS WEAKER. 22 distinct `zhi <id>` citations appear across t/ and lib/, and
`git zhi issue list` here returns `[]` -- the chain is empty, so NONE of them
resolves. They are provenance notes referencing a chain that does not exist in
this repository.

That is not urgent and not wrong in the way a stale citation is wrong: a note
saying "zhi 019f26a5" records where a defect was found, and nothing in the suite
claims otherwise. But it does mean the citations cannot be checked, and a reader
following one gets nothing. Worth either dropping them, or landing the chain
they refer to, rather than leaving them as unverifiable provenance.

Noted rather than acted on -- it touches 22 sites across two directories and
changes no behaviour.
