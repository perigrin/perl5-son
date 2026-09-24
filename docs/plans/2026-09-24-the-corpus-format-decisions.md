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

## Block-per-layer: taken, then the argument for it WITHDRAWN

Settled with pvm 2026-09-24 on reasoning that does not hold. The decision may
still be right; the stated justification was wrong and is recorded here as
wrong rather than quietly rewritten.

### What was claimed, and why it fails

The argument taken was: several implementations answer INDEPENDENTLY about
one program, so an inline comment would have to encode WHICH implementation
it constrains -- a block by another spelling, with worse namespacing -- and a
block-per-layer therefore "says silence structurally."

THE PREMISE IS WRONG. This is a CONFORMANCE SUITE. The fixture states what
is true about the program; each implementation checks itself against the
parts it supports. There are not several answers in need of separate
namespaces -- there is ONE SET OF FACTS that everyone agrees on for the parts
they implement.

So an inline assertion never needed to say who it binds. `# revealed: Scalar`
is a claim about the program's type. pvm's checker validates it, we validate
it, chalk validates it, or an implementation without that layer skips it.
Silence means "I do not support this", not "that fact belongs to another
namespace".

The "silence structurally" praise fails on its own terms for the same reason:
an implementation lacking a type layer skips type assertions whether they sit
in a block or a comment. Blocks organise FACTS BY KIND, which is a reasonable
thing to want, but that is not a claim about who is answering.

### What the real tradeoff is

LOCALITY, which is where this started before the bad argument displaced it.
Inline puts an assertion at the expression it is about; a block puts it in a
list that must reference a location some other way.

pvm has no per-expression claims today -- every claim of theirs is about a
whole program (what it prints, whether it parses, what its token stream
contains), so blocks cost them nothing now. Our reveal-stamp idea is a
per-expression claim, so we would want locality immediately.

### What survives, and is the actual reason

BLOCKS ORGANISE FACTS BY KIND. What perl prints, whether perl compiles it,
what the token stream contains -- three kinds of claim about one program,
separable and greppable and machine-writable by the tool that measures each.

That is a real argument for blocks and it is not a claim about who is
answering. It is what the decision now rests on.

Undecided against locality, which is the competing pull: inline puts an
assertion at the expression it is about, and reveal-stamp will want that.
Recorded so the decision is re-argued on the tradeoff rather than inherited
from the withdrawn reasoning.

(Authorship, since 888277e's commit message got it wrong: pvm wrote the bad
argument, this session endorsed it without examining the premise. Both halves
of that are worth keeping -- an argument accepted is an argument owned.)

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
