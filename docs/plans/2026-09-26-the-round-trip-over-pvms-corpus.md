# The round trip over pvm's corpus: 47 defects, and the producer is at fault

**Date:** 2026-09-26
**Status:** IN PROGRESS. All 29 RUNS_WRONG_OUTPUT cases sampled and
diagnosed. The other two failure modes -- 10 RUNS_BUT_DIES and 8
EMITS_INVALID_PERL -- are untouched.

TWO DIFFERENT COUNTS OF 18 COLLIDED while this was written, so to be explicit:
the 18 still owed is 10 + 8 from the other failure modes, NOT unsampled
wrong-output cases. An earlier draft said "11 of 29 sampled, 18 remain"; the
done-list held 12, so 17 remained, and the run confirmed 17. That count is
closed.

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

## The remaining 17, diffed in full

Sampling of RUNS_WRONG_OUTPUT is now COMPLETE: 29 of 29. Five more clusters
and six singletons, for 19 distinct causes in total.

### 9. A TEXT SECTION AFTER THE PROGRAM IS DROPPED (161, 162, 103, 104)

The biggest remaining cluster, and one shape: content that is NOT Perl but
belongs to the file.

    161  __DATA__ read through <DATA>     emits nothing; perl prints one two
    162  __DATA__ holding non-Perl bytes  emits nothing
    103  a format declaration + write     emits nothing
    104  a format picture line            emits nothing

`__DATA__` and a format body are not optree ops, so a walker that only reads
the optree cannot see them. The producer must read them from the FILE.
Related to the existing `write` refusal, but these cases produce NO output
rather than refusing -- a silent drop, the worst outcome.

### 10. `use` does not load or import (124, 125, 128)

    124  use POSIX;      "POSIX loaded: no / floor imported: no"  (perl: yes/yes)
    125  use POSIX ();   "POSIX loaded: no"                        (perl: yes)
    128  import as an ordinary method call -> dies, undefined import method

A `use` is a compile-time require plus an import call; we emit neither. 128 is
the sharpest: the emission DIES rather than printing, so a caller cannot tell
a missing import from a broken one.

### 11. Regex-embedded code does not run (097, 098, 099)

    097  (?{ }) statement inside a pattern    0 where perl says 5
    098  qr// carrying a block                0 where perl says 7
    099  hostile contents, region parsed      3bc 0 where perl says 3bc 5

A code block frozen into a pattern is a callee the graph does not carry.

### 12. Six singletons

    044  `&` on strings, numeric gate     10 where perl says 8
    055  `die` as a list operator         a line missing from the output
    062  `prototype` reads its own input  [] where perl says [$]
    085  `caller` amount by context       1 1 where perl says 1 0
    120  `localtime` list vs string       returns the STRING in list context
    179  `split` first-arg as a pattern   4 [  a b] 4 [  a b] vs 2 [a b]
    191  `\*STDOUT` ref type             SCALAR where perl says GLOB

179 and 120 are the same family as the deref defects: a list-context read
returning the scalar-context answer.

## Still undiagnosed

    10  RUNS_BUT_DIES
     8  EMITS_INVALID_PERL

Not looked at. One EMITS_INVALID_PERL shape is already known from the earlier
sample -- `tr[.][Z])` with a stray paren, from adjacency-09_regex.

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
