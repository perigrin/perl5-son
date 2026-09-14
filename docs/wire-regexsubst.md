# RegexSubst — node contract

`RegexSubst` gained a `pattern_is_input` field in `fe39ec2`. A consumer pinned
before that commit reads every graph correctly EXCEPT one whose s/// pattern is
computed at runtime — and on those it reads an empty pattern, which matches
everywhere.

## Signature

    op:     "RegexSubst"
    inputs: [ target, pattern?, replacement? ]
    fields: {
      pattern:          string,        the pattern, when it is literal
      replacement:      string,        the replacement, when it is literal
      flags:            string,
      pattern_is_input: true           present ONLY when true
    }
    stamp:  Str

## `pattern_is_input`

A pattern that interpolates is not known until runtime:

    $s =~ s/$P b$/X/

so it cannot ride on the `pattern` string field. It is built as a value and
passed as **input 1**, and `pattern_is_input` says so.

    pattern_is_input absent   inputs are [target, replacement?]
                              `pattern` holds the pattern
    pattern_is_input true     inputs are [target, pattern, replacement?]
                              `pattern` is the empty string

The flag is necessary because position alone cannot answer it: the optional
replacement occupies the same slot under `/e`, so a two-input node is
`[target, pattern]` or `[target, replacement]` and nothing else distinguishes
them.

This mirrors `Match`, which has taken a runtime pattern as its second input all
along — measured, `$s =~ /${P}b/` is `Match(subject, Concat("a","b"))` with no
pattern field at all. `RegexSubst` could not simply follow suit because its
second slot was already taken.

## Why it matters

Before this, an interpolated pattern was DROPPED and a fragment of it landed in
the `replacement` slot. Measured on perl's own `t/base/lex.t`:

    source:  s/${s|||;\""}not //
    graph:   pattern=''  replacement='not '

The pattern gone, and a piece of it inserted as text the source never wrote —
a substitution matching everywhere. `comp/parser.t` and `comp/redef.t` had it
too.

ALL-CONSTANT PARTS STILL FOLD to the `pattern` string field. An empty
`precomp` means the pattern went through `regcomp`, not that it is unknown:
rpeep suppression is why the pieces arrive separate, and `\Q...\E` splits text
perl would otherwise have folded. `comp/parser.t` is exactly that case
(`"A" . "\{"`), and it carries no `pattern_is_input`.

## Rendering it back

A computed pattern has to be turned into a pattern again, which interpolation
does — perl compiles the string. It must be **wrapped in `(?:...)`**: the value
is a whole pattern and the text around it is not, so a value like `a|z` would
bind past its own extent and swallow what follows.

## Known gap: no memory input

`RegexSubst` ADVANCES the memory chain — a destructive s/// stores into its
target and a later read must observe it — but takes no memory input, so it is
a memory point invisible to a structural reader. Measured on
`our $g = "aaa"; $g =~ s/a/b/; $g =~ s/b/c/`:

    11 RegexSubst in=[3]    no memory input
    12 RegexSubst in=[11]   chained through its TARGET, not through memory

Every other memory point names the version it supersedes. Fixing this needs a
second flag or always-present slots, for the same positional reason
`pattern_is_input` exists, so it is deliberately OPEN rather than half-done.
Pinned in `t/wire-global-state-call-carries-memory.t`; see
`docs/plans/2026-09-14-a-memory-point-must-carry-memory.md`.

A consumer relying on memory edges to order substitutions against other stores
should know it will not find one here.
