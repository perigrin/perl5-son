# The round trip over pvm's corpus: 47 defects, and the producer is at fault

**Date:** 2026-09-26
**Status:** IN PROGRESS. 11 of 29 wrong-output cases sampled and diagnosed;
18 remain. Written down as it goes so the diagnoses are not lost.

## The numbers

Producer only (optree -> IR), over pvm's 212 cases:

    198 CLEAN    11 GAP    3 NOPARSE

Round trip (producer -> deparser -> run -> diff against the recorded output):

    ROUNDTRIP  127
    DIFFERS     47
    REFUSED     33
    NOJSON       2
    NOPARSE      3

THE PAIRING IS TRUSTWORTHY. All 209 `output` blocks were checked against real
perl first: 209 match, 0 differ. So a diff against a recorded block is a diff
against perl.

The 47 DIFFERS by failure mode:

    29  RUNS_WRONG_OUTPUT     compiles, runs, prints the wrong answer
    10  RUNS_BUT_DIES
     8  EMITS_INVALID_PERL    the emission does not even compile

## THE PRODUCER CENSUS OVERSTATED HEALTH

Every case diagnosed below reported CLEAN in the producer pass. They translate
with no GAP and build a WRONG GRAPH -- a silent miscompile, which
[[a-silent-drop-is-worse-than-a-refusal]] ranks below an honest refusal.

So "198 of 209 translate" is not a health measure. The honest framing:

    209 parseable
    198 produce a graph
    127 confirmed correct by round trip
    >=11 produce a WRONG graph (measured, sampled)

THIS IS CHALK'S PROBLEM TOO. None of the sampled defects is a deparser
rendering artifact -- the graphs are wrong, so any consumer gets them wrong.

## Diagnosed: 8 distinct causes in 11 cases

### 1. Shadowed `my`/`state` collapse (086, 088, 096)

The largest cluster and one cause. Perl gives TWO DISTINCT PAD SLOTS:

    my $x = 1; { my $x = 2; print "$x\n" } print "$x\n"

    4  <1> padsv_store[$x:1,5] vKS/LVINTRO     outer slot
    9  <1> padsv_store[$x:3,4] vKS/LVINTRO     inner slot, a different entry

What we build:

    6 PadAccess in=[] sigil=$ symbol=x
    any MemStart / EntryWrite / VarDecl?  NONE

Two defects compounding: both `my` stores VANISH (node 6 reads an `$x` nothing
ever wrote), and the two slots collapse to one identity keyed on `symbol`
alone. Measured on 096: `in _ out 2` where perl says `in 2 out 1` -- the inner
value leaked outward and the inner read got nothing.

THIS FALSIFIES A DESIGN COMMENT. Serialize/JSON.pm:150 drops `targ` from the
wire on the stated grounds:

    "two shadowed `my $x` stay distinct on the wire because their MEMORY
     inputs differ, not because of the slot number"

Measured: the PadAccess has NO memory input, and the graph holds no memory
node at all. The mechanism the comment relies on is not firing, so dropping
`targ` left nothing distinguishing the slots. Either the memory edges must be
built, or the wire needs the slot identity back.

### 2. `@{$r}` wraps the reference instead of dereferencing (091)

    my @a = (10,20,30); my $r = \@a; my @c = @{$r};

     5 ArrayLiteral Array    in=[2,3,4]
     6 Ref          ArrayRef in=[5]
     7 ArrayLiteral Array    in=[6]      <- the DEREF, holding the REF

`scalar(@c)` is 1 where perl says 3. Same family as the `@$r` defects in
[[a-list-is-not-a-reference-or-an-array]].

### 3. `index` 3-arg arguments transposed (138)

Emission: `index("o", (index($s,"o") + 1))` -- subject and needle swapped, so
the position argument lands as the needle. perl `[4][7][-1]`, we print
`[4][-1][-1]`.

### 4. `//=`, `||=`, `&&=` vanish entirely (078)

The emission reads the original values with no assignment ops present at all.
perl `0 99 99 0`, we print `0 0 1 0`.

### 5. `@_` aliasing does not write through (029)

`$_[0]++` in a callee does not reach the caller's variable. perl `2 1`, we
print `1 1`.

### 6. `substr` as an lvalue loses the assignment (141)

perl `[Jello][Jello][h]`, we print `[hello][hello][]`.

### 7. Magic string increment (200)

`"Az"++` and friends. perl `Ba aaa b0`, we print `1 1 1` -- numeric increment
applied to a string.

### 8. `sort` / the `() =` count idiom loses a value (119)

perl `1 2 3 3 0`, we print `1 2 3 _ 3`.

## A METHOD NOTE THAT NEARLY COST A WRONG ANSWER

Case 188 looked IDENTICAL in a two-line preview and is a real defect on line
three -- `[1 2]` where we print `[]`. Only a byte diff caught it. That is
[[truncated-output-manufactures-facts]] firing in the middle of this
investigation; every classification here that rests on a preview rather than a
full diff should be re-checked.

## Remaining work

18 of the 29 wrong-output cases are unsampled, plus 10 RUNS_BUT_DIES and 8
EMITS_INVALID_PERL which have not been diagnosed at all. Expect more distinct
causes -- the 11 sampled produced 8.

Topics still unsampled include formats, loading, embedded-code, tie,
bless-dispatch (4 cases), taking-references, pod-and-data, handles,
symbol-table, regex-pattern-positions.

## What this does to the milestone shape

Step 3 was scoped as "build IR for the corpus". That was wrong. The IR mostly
exists; what is missing is CORRECTNESS in graphs that already translate. The
work is:

    1. ~8+ producer defects that currently pass SILENTLY  (this document)
    2. 11 honest producer GAPs                            (the census)
    3. the goto family                                    (2026-09-25 doc)

Item 1 did not appear in any GAP count, which is the argument for the round
trip being the gate rather than the census.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
