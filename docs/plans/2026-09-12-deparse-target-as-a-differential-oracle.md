# A deparse target as a differential oracle

**Date:** 2026-09-12
**Status:** PROPOSED. Not started. Written for review before any code.

## The problem this solves

Every correctness check on the producer today is STRUCTURAL: read the emitted
graph, reason about whether it says what perl says. That is how this session
found its defects, and the record shows what that method is bad at.

| Defect | How found | Class |
|---|---|---|
| `sort bylen (...)` sorted 4 items, perl sorts 3 | reading the graph | wrong answer |
| stacked sort claimed `sort_cmp: string` for a numeric descending comparator | reading the graph | wrong answer |
| `@$r` substituted construction-time elements, losing mutations | reading the graph | wrong answer |
| `push @$r` took the flattened elements as operands | reading the graph | wrong answer |
| `keys`/`values`/`each` do not observe stores | noticed BESIDE other work | wrong answer |
| nested one-armed element store: memory-Phi dead | reading the graph | wrong answer |

Every one is a WRONG ANSWER from a structurally plausible graph. None was
caught by the test suite, which was green throughout. They were caught by
inspection, which only finds what the reader thinks to look at -- the
`keys`/`values`/`each` defect was found by accident while checking something
else, and is still open.

A differential oracle catches this whole class mechanically: run the original
under perl, run the graph's rendering, diff. See
[[read-generated-output-not-tests]] -- this is that discipline automated.

## The proposal

Emit PERL SOURCE from a SoN graph. Not an optree.

`B::` is introspection-only, so building real ops means XS (`newBINOP` and
friends) -- weeks of work, and a segfault surface. Emitting source costs a
fraction of that and buys the same differential signal, because the comparison
is `perl original.pl` vs `perl emitted.pl`, and perl compiles the emitted source
with the same front end either way.

It also doubles as a legibility check on the IR: a graph that cannot be
deparsed is usually one whose meaning is not fully pinned down.

An optree target remains possible later; nothing here forecloses it.

## Why the graph shape makes this tractable

Measured: `control_in` is a TOTAL ORDER over effects, and pure values hang off
it as a DAG.

    my $a = 1; my $b = $a + 2; print "$b\n"; print "second\n";
      9 Print  ctl<-0
     10 Print  ctl<-9
     11 Return ctl<-10

So the emitter is: walk the control chain, and for each effect emit its operand
tree as an expression. No scheduling algorithm, no GCM. That is the single
biggest reason this is a week and not a quarter.

## Vocabulary to cover

Measured over base+comp (33 files translating, 29 CLEAN): **67 distinct ops**,
steeply distributed.

Top of the distribution (each >100 occurrences):

    Constant 2607   Concat 982   Proj 889   Coerce 881   Print 836
    Region 767      Call 751     Phi 477    If 384       Add 264
    EntryWrite 242  Subscript 216  TernaryExpr 213  Return 204  Start 200
    PadAccess 198   EntryDef 192   StrEq 174  MemStart 126  And 118
    ArgsSource 117

The tail is mostly one-line binops (`Multiply`, `BitOr`, `NumLe`, `RightShift`,
...) -- cheap.

The genuinely hard set is small and known:

  - **Control**: `If` / `Proj` / `Region` / `Loop` -- reconstruct `if`/`else`
    and loop syntax from the CFG.
  - **Memory**: `MemStart` / `EntryWrite` / `Assign` / `Delete` / memory-`Phi` --
    these ARE the defect class the oracle exists to catch, so they must be
    emitted with real ordering.
  - **Ours, not perl's**: `EntryDef`, `CellRead`/`CellWrite`/`CellParam`,
    `MakeCell`, `Coerce`, `Count`, `RegexSubstCount`, `ArgsSource`. Vocabulary
    chosen BECAUSE the optree does not express it directly; each needs a
    deliberate spelling.

## The correctness criterion

**Observational equivalence, program by program.** A graph must be able to
produce SOME Perl program that behaves identically to the input: same outputs,
same effects, same order WHERE ORDER IS OBSERVABLE.

The obligation is on the PROGRAM, not on the node. Whether any individual node
has a Perl spelling is irrelevant -- a memory-Phi, a `Proj`, a `Region` and
`Start` are structure, and structure is discharged by WHERE things are emitted
rather than by what they translate to. The memory-Phi in

    my @a = (1,2);
    if ($cond) { $a[1] = 9 }
    my $v = $a[1];

says "this read observes whichever store the taken path made". Emitting the
`if` and then the read discharges it; the Phi needs no syntax of its own.

An earlier draft of this document claimed some nodes have "no honest Perl
spelling" and that a permanently-refusing emitter was therefore acceptable.
That is wrong, and wrong in a way worth recording: we STARTED from Perl
semantics, so if a graph cannot be rendered back to an equivalent Perl program,
the graph lost something it needed -- and that is a defect in the IR, not a
fact to design around. "No token for this node" never implies "meaning lost".

WHAT ORDER IS OBSERVABLE is exactly what the graph already encodes: `control_in`
for what is ordered, data edges for what is not. Two `print`s must stay
ordered; two pure arithmetic ops need not. So emitted programs may legitimately
differ from the input in the unordered parts -- that is the line between the
emitter being allowed to be UGLY and the emitter being allowed to be WRONG.

This also settles what a failure means. A round-trip that differs localises to
a PROGRAM, with a diff behind it, and you bisect toward the construct -- the
same debugging motion as every blocker fixed this week. There is no
node-by-node audit and no "unspellable node" register to maintain.

## The failure mode to design against

**A shared assumption cancels out.** If the emitter reproduces a fold the
walker made, the round-trip agrees with itself and the miscompile stays
invisible. `@$r` is the exact shape to fear: flatten on the way in, flatten on
the way out, output matches, bug survives.

Rule: **the emitter is deliberately dumb.** It emits what the node SAYS, never
what the source probably meant. A `Subscript` with a memory input emits an
element read at that point in the order; it never reconstructs a literal. If
that produces ugly Perl, good -- ugly and faithful is the product.

Corollary: the emitter must not import helpers from `FromOptree.pm`. Shared
code is shared assumptions.

## Phasing

The phase boundary is **`Loop`**, and it was chosen by measurement rather than
intuition. An earlier draft split at "straight-line", which carves the corpus
at an unnatural line: measured over the CLEAN corpus,

    48/115 CVs  straight-line only
    51/115      + Phi                      (a Phi without a branch is rare)
    75/115      + conditionals (If/Ternary)
    94/115      + logical (And/Or)
   100/115      + Unwind
   100/115      everything but Loop

Allowing `Phi` alone buys three CVs. Conditionals buy 27, and `And`/`Or` -- the
same merge machinery with short-circuit -- buy 19 more. Everything up to that
point is ACYCLIC control flow, reconstructible by structural recursion over the
dominator tree. A loop needs back-edge detection and a different emission
strategy. That is the real cliff.

**The unit is `main::__PROGRAM__`, not the CV.** A CV count dilutes the answer
-- a file with 60 trivial named subs and one loop-bearing program body reads as
mostly covered and still cannot be tested end to end. Measured: the files whose
`__PROGRAM__` is acyclic are EXACTLY the files that are entirely acyclic (14 of
28), so `__PROGRAM__` decides the file.

### Phase 1 -- acyclic

Values, memory, and all non-loop control: `If`, `Proj`, `Region`, `Phi`,
`TernaryExpr`, `And`, `Or`, plus the value and memory vocabulary.

**First target: `base/if.t`.** Nine lines, deterministic three-line output, no
named subs, and 12 node kinds that are exactly the Phase 1 core:

    Constant EntryDef EntryWrite If MemStart Print Proj Region Return Start
    StrEq StrNe

A package scalar write, reads that must observe it, an If/Proj/Region diamond
taken both ways, and `Print` so there is output to diff. Notably NO `Phi` --
both arms print and neither yields a value -- so it is the control diamond
without the value merge, one step rather than all of acyclic control at once.

`comp/filter_exception.t` has fewer nodes (18 vs 27) but prints NOTHING, so a
round-trip on it compares two silences. Smallest is not simplest.

The ladder, each rung adding roughly one thing:

  1. `base/if.t`   -- control diamond, package memory, printed output
  2. `base/pat.t`  -- the same shape with `RegexMatch` for `StrEq`
  3. `base/cond.t`, `comp/colon.t`, `comp/term.t`, ... -- `Phi`, `Coerce`,
     `TernaryExpr`, `And`/`Or`
  4. the rest of the 14

**Gate:** all 14 acyclic CLEAN files round-trip to observationally equivalent
output:

    base/cond.t  base/if.t  base/num.t  base/pat.t  comp/cmdopt.t
    comp/colon.t  comp/filter_exception.t  comp/opsubs.t  comp/our.t
    comp/package.t  comp/package_block.t  comp/redef.t  comp/term.t
    comp/uproto.t

**Go/no-go inside Phase 1:** the oracle must rediscover
`keys`/`values`/`each` (docs/plans/2026-09-06) WITHOUT being told where to
look. That defect lives in acyclic code, so it is reachable here. If the oracle
cannot find a defect already known to be present, it is not earning its tax --
say so and go back to clearing blockers by hand.

### Phase 2 -- loops

`Loop`, loop-carried Phis, `Unwind`. Gate: the remaining 14 files.

### Phase 3 -- suite integration

Wire the round-trip in as a corpus gate, so a producer change that breaks
equivalence fails a test rather than waiting to be noticed.

## What this is NOT

  - Not a compiler backend. chalk owns lowering; this is a producer test
    harness and it must never become a second consumer with opinions.
  - Not a pretty-printer. Output is read by `perl`, not by people.
  - Not a replacement for the corpus survey. The survey says WHICH files
    translate; the oracle says whether what translated is TRUE.

## Cost and the honest caveat

Phase 1 is bigger than the "few days" an earlier draft assumed, because
acyclic control is in it rather than deferred -- If/Phi/Region emission was
always going to be written, and doing it first is what makes the gate
meaningful instead of vacuous. It also grows with the IR: every new node kind
needs an emission rule or an explicit refusal. That is a real ongoing tax.

The case for paying it: the last three defects found were all "the reader does
not observe the store", the class where the graph looks complete and computes
the wrong answer. Inspection is worst at exactly that, and one of the three is
still open.

## Open questions for review

1. RESOLVED during review: the boundary is `Loop`, the unit is
   `main::__PROGRAM__`, and Phase 1 gates on the 14 acyclic CLEAN files with
   `base/if.t` first. The go/no-go is rediscovering keys/values/each.
2. RESOLVED during review: `lib/SoN/Deparse.pm`, in-repo, reading the JSON
   wire format rather than producer internals -- coupled to the wire (which
   chalk consumes too) rather than to FromOptree.pm.
3. RESOLVED during review: the criterion is observational equivalence per
   PROGRAM, not a spelling per node (see The correctness criterion). An
   emitter refusal is scaffolding -- "no rule written yet" -- and the measure
   is simply how many corpus files round-trip to identical output.
4. RESOLVED during review: build the oracle first, because it is the TOOL for
   the partials. It helps memory- and control-shaped blockers directly
   (comp/use.t is exactly "the read does not observe the store"), and helps
   every blocker indirectly by replacing "read the graph and reason" -- the
   slow, error-prone step, mis-read twice in one sitting on comp/use.t -- with
   "run it and diff". It does NOT help where the construct is simply
   unmodelled (comp/decl.t's `write`/$~, comp/form_scope.t's undef(*glob)):
   there is no graph to round-trip until the lowering exists.
