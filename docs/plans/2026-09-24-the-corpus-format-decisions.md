# The corpus format: decisions taken while waiting for pvm

**Date:** 2026-09-24
**Status:** DECIDED, not built. pvm is building the corpus; we copy it over,
flesh it out to our needs, and a crochet milestone builds IR for it. These
are the format decisions settled in conversation so they are not re-derived.

## The sequence

    1. pvm finishes building the corpus
    2. copy it over, flesh out to our needs
    3. crochet milestone: build IR for it -> a complete IR
    4. circle back: PerlOnJava's 986 + perl.git t/* -> expand further

"Complete IR" in (3) means complete FOR THAT CORPUS. The 986 PerlOnJava
files produced 13 node kinds our previous corpus never reached, so (4) will
almost certainly find more. The milestone should name which corpus it is
complete for.

## What each layer claims

Not three overlapping sets. Each layer's claim presupposes the one before.

    pvm      parses                                    (and types -- see below)
    B::SoN   well-formed graph
    chalk    both, AND lowers to a correct executable

B::SoN IS THE NARROWEST. We leverage perl as the parser, which is the
DEFINITIONAL parser, so a successful parse is GIVEN rather than asserted. A
program that does not parse never reaches us; it is not a failing fixture,
it is not a fixture. "B::SoN parses and builds a graph" is a vacuous
conjunction on our side.

### Where pvm and B::SoN overlap

pvm includes a type checker, so both implementations derive the `:Int` in
`Add(Int, Int) :Int`. This is NOT two type systems disagreeing over a
language that has neither -- it is TWO IMPLEMENTATIONS OF THE SAME TYPE
SYSTEM, one the language is argued to have and the current perl neglects to
enforce. A stamp disagreement is therefore a defect report against one of
us, with a right answer, not a negotiation.

The oracles differ by layer, which matters when a disagreement arises:

    parse         perl -c decides            authoritative
    graph shape   our IR contract            by agreement
    stamps        our lattice                by agreement, no external referee
    executable    run it, diff the output    authoritative

## Parse-failure fixtures are SKIPPED, not excluded

pvm's corpus includes fixtures whose expected result is that perl rejects
the program. A parser that accepts what perl rejects is as wrong as one that
rejects what perl accepts, so both directions are conformance for pvm.

For us those rows have no input and no graph. They stay in the same corpus
and we SKIP them:

  - Skip on the MEASURED result, not a filename convention. Run `perl -c`;
    if it fails, skip with that reason. A fixture pvm marks as a parse
    failure that perl actually accepts is itself a finding, and deriving the
    skip from perl keeps that visible.
  - The skip reason must NAME THE CAUSE -- `skip 'perl -c rejects: <msg>'`,
    never a bare skip. Same rule as [[a-refusal-test-must-name-its-cause]].
    "N of M skipped, not parseable" is then a real number about the corpus,
    and a change in it means something moved upstream.

## Format: markdown, after Ty's mdtest

Modelled on `crates/ty_test` in astral-sh/ruff (the Ty type checker), which
chalk's own t/corpus/mdtest already resembles.

### Taken from Ty

REVEAL. Ty pairs a `reveal_type()` call with a `# revealed:` assertion, so a
type claim is asserted AT AN EXPRESSION:

    reveal_type("foo")  # revealed: Literal["foo"]

Our analogue asserts a stamp where it is computed, which nothing in our suite
does today -- t/wire-*.t digs node shapes out of JSON instead. This is also
exactly where a Maybe[Str]-vs-Scalar disagreement with pvm becomes a one-line
diff rather than a design conversation.

RULE CODES, with text as an optional discriminator:

    # error: [invalid-assignment]
    # error: 8 [invalid-assignment] "Some text"

Column, then code, then contains-text, in that order. Ty's own convention is
to prefer the code and use text "where needed to disambiguate". This is the
structured-reason design, proven in a shipped checker. Our GAPs have none:
85 raise sites, all freeform strings, and only 6 of 38 refusal assertions
name a cause.

EXPECT-PANIC, a regression test for a crash not yet fixed:

    <!-- expect-panic: <substring of the panic message> -->

Ty's reasoning applies to us directly -- see [[crashes-mask-gaps]].

### NOT taken from Ty: literate merging

Ty merges consecutive unnamed code blocks into one file. We do not, because
PERL'S COMPILATION UNIT IS THE FILE: `my` scope, BEGIN ordering, `use
strict`'s lexical effect, __DATA__, and constant folding are all per unit.
Two blocks merged can fold across the boundary; kept separate they cannot.

Measured today, the case that makes this concrete:

    my $x = "abc";        folds into the pad slot -- NO VarDecl node
    my $x = "abc" . $0;   runtime-computed -- VarDecl survives

Merged, the reader sees two fixtures and the harness runs one program.
Separate, what you read is what perl compiled. This also makes "one
construct per file" -- the property that makes PerlOnJava's corpus useful --
something the format enforces rather than something authors must remember.

### Files: GitHub-style block metadata

Blocks are SEPARATE FILES BY DEFAULT; an info string names the path when
blocks belong together.

    ```fileA.pm
    package FileA;
    sub greet { "hi" }
    1;
    ```

    ```fileB.pl
    use FileA;
    print FileA::greet(), "\n";
    ```

Three details to settle when building:

  - THE EXTENSION IS LOAD-BEARING. `.pm` / `.pl` / `.t` change @INC
    resolution, whether a trailing `1;` is required, and whether TAP is
    expected. These are paths, not language tags.
  - WHICH FILE IS THE ENTRY POINT needs stating, not inferring. Proposal:
    the LAST block, since `use`-before-use reads top-down.
  - A BARE block with no info string is the unnamed entry point, so the
    common single-fixture case needs no ceremony.

DECIDED with pvm: BARE `perl` STAYS VALID, not deprecated shorthand. The
info string is a PATH if it contains a `.`, otherwise a language tag --
`perl` has no dot, every path we would write has one, and that is the whole
disambiguation.

Three reasons, the third being pvm's constraint rather than ours: the
single-file case is almost every fixture and should cost nothing; a path is
a CLAIM (compiles as a module, needs a trailing 1;, resolves through @INC)
that most fixtures should not make, so the absence of one is itself
information; and it keeps pvm's migration purely additive while 13 tiers are
mid-port.

Layer blocks (`behavior`, `ir`) assert about the TEST, not about any one
file, so they do not compete with path-named source blocks. chalk's mdtest
format and this one are compatible.

## DECIDED: block-per-layer, not inline

Settled with pvm 2026-09-24. Their argument, which is better than the
readability one I was weighing:

Ty's inline form is right FOR TY BECAUSE TY HAS ONE PRODUCER -- the assertion
and the thing asserted are the same tool's output, so a comment beside the
expression is the shortest honest form. With several implementations
answering independently about one program, an inline comment would have to
encode WHICH implementation it constrains, which is a block by another
spelling and a worse one: it puts several tools' answers in one namespace and
makes "who is silent here" unanswerable.

A BLOCK-PER-LAYER SAYS SILENCE STRUCTURALLY. You fill `ir`, they fill
`tokens`, neither validates the other's.

### The trigger to revisit, and we will hit it first

Inline's real advantage is LOCALITY -- an assertion at the expression it is
about. Nothing in pvm's corpus needs it: every claim they make is about a
whole program (what it prints, whether it parses, what its token stream
contains). A PER-EXPRESSION claim -- a type at a site, a diagnostic at a
column -- would need it.

Our reveal-stamp idea is exactly that, so locality matters to us before it
matters to them. Current guess, undecided: it stays INSIDE an ir-style block
rather than becoming an inline comment, to keep the silence property. Not
built, not settled.

## Parse-failure fixtures can assert what parsing ones cannot

pvm's finding, 2026-09-24, and it is structural rather than a completeness
argument.

A non-parsing fixture EMITS NO OPS, because perl builds no optree for a
program it will not compile. So it can spell an operator belonging to a tier
that its own tier depends on, without violating an op-budget lint -- and a
PARSING case cannot. Measured there on `1 .. 2 .. 3` and `1 <=> 2 <=> 3`,
both perlop nonassoc levels.

The two categories are therefore not harder-and-easier versions of one
thing. They assert DISJOINT sets of facts.

pvm also measures `perl -c` on EVERY case, not only those annotated as
failures, so an annotation that disagrees with perl is itself a failure.
That is stricter than the rule recorded above and we are adopting it: it
makes the annotation checkable rather than trusted, the same move as
matching a refusal's cause instead of its presence.

## Also open, from the same comparison

chalk's mdtest `ir` blocks name ArrayRef, HashRef and CompoundAssign. None
is a node class we emit. Either the corpus encodes an IR we agreed and have
not built, or it is stale. A concrete contract disagreement between two live
projects, unresolved.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
