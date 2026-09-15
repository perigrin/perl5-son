# `Transliterate` and `TransliterateCount`

Two new node kinds for `tr///` and `y///`. Before them, a transliteration
reached the wire as `Call(name="trans", inputs=[target])` — the 522-byte
translation table the op carries was dropped, so the operation was
unrecoverable.

## What an un-updated consumer sees

A node kind it does not know. That is the intended failure: the previous
shape was a `Call` naming a builtin `trans` that no consumer could lower
correctly, because nothing on the wire said which characters mapped to
which. An unknown kind refuses; a `Call` with no table silently does the
wrong thing.

## `Transliterate`

    inputs  [target, memory?]
    from    the SOURCE character set, as written
    to      the replacement set, as written
    flags   any of c d s r

`from` and `to` are the source spelling, decoded back from the op's table:
a range comes back `a-z`, not its 26 expanded members.

**They are SETS, not patterns.** `tr/a-z/A-Z/` maps each lowercase letter
to its uppercase; the same text compiled as a regex is a character class
matching one letter. A consumer that hands these to a regex engine has
miscompiled the program. This is why the operation is its own kind rather
than a flag on `RegexSubst`.

**The memory input is last and optional.** A destructive `tr///` stores
into its target, so it advances the memory chain and names the version it
supersedes. The `r` form stores nothing and carries no memory.

**Flags cannot be inferred from the sets.** `tr/x//` maps x to itself;
`tr/x//d` deletes it. Both leave `to` empty, so `d` must be read from
`flags`.

## `TransliterateCount`

    inputs  [the Transliterate]
    stamp   Int

`tr///` in non-void context yields how many characters matched, not the
transliterated string. Void context reads neither; `r` yields the rewritten
copy and no count.

**Its stamp is Int, unlike `RegexSubstCount`.** Measured on 5.42.0:

    "aab" =~ tr/a//    ->  2
    "xyz" =~ tr/a//    ->  0     a real zero, length 1
    "xyz" =~ s/a/b/    ->  ""    the EMPTY STRING

so the two counts are different types and cannot share a node: a stamp
true of one is false of the other.

## Still refused

A `tr///` whose map lives in the pad (`PADOP`) rather than in the op —
reaching it needs the CV's pad, which the producer does not thread here.
