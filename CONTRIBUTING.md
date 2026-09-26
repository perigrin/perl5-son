# Contributing to B::SoN

B::SoN is a compiler FRONT END. It leverages perl's own parser to turn an
optree into a Sea of Nodes IR, which a backend (part of chalk) lowers.
`lib/SoN/Deparse.pm` renders a graph back to Perl; that is a testing backend
for differential comparison, not a production consumer.

## Tech stack

Perl 5.42.0, managed with plenv. `perl` on PATH is 5.42.0.

## Commands that check it

    prove -Ilib -j8 t/            the full suite
    perl -Ilib t/<one>.t          a single file
    perl -Ilib -MO=SoN,json,not_package=SoN F.pl    the wire for one program

Use `not_package=SoN` rather than `package=main`: the latter FILTERS OUT every
other package, which silently drops a fixture's classes from the graph.

## The correctness criterion

Observational equivalence, program by program. A graph must be able to produce
SOME Perl program that behaves identically to the input. The gate is
behavioural: run the original under perl, run the graph's rendering, diff.

A structural check on the wire is the first line of defence and is not
sufficient -- six live miscompiles once passed a green suite because every
check read the graph and none ran the program.

## Refuse or lower

A GAP -- an honest refusal naming its cause -- is acceptable. A silent wrong
answer is not, and a silent DROP is worst. A GAP means "the program does not
say", never "a backend would find this hard to execute".

<!-- covers: docs/assessments/ -->
## Assessments

Gate records from `crochet:assess`. Each is the minute of a discernment
session over a spec, with its findings and outcome.

- [0001 the corpus milestone scope](docs/assessments/0001-corpus-milestone-scope.md)
  — MODIFY; five blocking findings, including that the spec's own
  "chalk inherits all of these" claim is falsified by a renderer-only defect.

<!-- covers: docs/plans/ -->
## Plans

Design and investigation records under `docs/plans/`, dated, kept as written
rather than rewritten -- a withdrawn argument stays visible next to why it
failed, because a spec outlives the decision it justified.
