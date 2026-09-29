# Delimiters and opacity

Choosing the delimiter and finding its match is the lexer's whole job in
this tier, so these are its central cases -- and every one of them is a
TOKEN claim, because delimiters erase themselves from the optree.

**Tier 09 regex.** Introduces `match`, `pos`, `qr`, `regcomp`, `split`,
`subst`, `trans`. Depends on 01_literals.

Measured under 5.42.0, `m{abc}` and `/abc/` emit byte-identical op
streams, as do `s{a}{z}` and `s/a/z/`, and `m#abc#` and `/abc/`. The
optree cannot distinguish them and neither can the printed output, so a
delimiter case asserting only ops would measure nothing the bare forms
already measure and would go green against a lexer that silently
normalised every delimiter to `/`. This is the same argument
`conformance/README.md` makes for `5e-1`.

## Bracketing and punctuation delimiters

`m{abc}` and `s{a}{z}` emit op streams BYTE-IDENTICAL to `/abc/` and
`s/a/z/` -- measured, down to the pattern text perl prints inside the
op: `match(/"abc"/) sKS`. So this case's whole measurement is its token
claims.

`s{a}{z}` is the case where the second pair's opening delimiter is free
to differ from the first's, which GLOSSARY.md records as true only when
the first pair is bracketing. `m!abc!` is the non-bracketing case, where
one character delimits both ends and nothing nests -- which is also why
its body holds no `!`.

```perl
my $a = "abc" =~ m{abc};
my $b = "abc" =~ m!abc!;
my $s = "abc";
$s =~ s{a}{z};
print "$a$b$s\n";
```

```behavior
parses: yes
```

```output
11zbc
```

```tokens
one quote-like operator whose text is "m{abc}"
one quote-like operator whose text is "m!abc!"
one quote-like operator whose text is "s{a}{z}"
no operator whose text is "{"
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 2
  [RegexMatch, {flags: "", pattern: abc}, [2], ~, Boolean], # 3
  [Coerce, {from_repr: Boolean, to_repr: Str}, [3], ~, Str], # 4
  [RegexMatch, {flags: "", pattern: abc}, [2], ~, Boolean], # 5
  [Coerce, {from_repr: Boolean, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [4, 6], ~, Str], # 7
  [MemStart], # 8
  [PadAccess, {sigil: $, symbol: s}, [8], ~, Unknown], # 9
  [Assign, ~, [9, 2], 0, Str], # 10
  [PadAccess, {sigil: $, symbol: s}, [10], ~, Unknown], # 11
  [RegexSubst, {flags: "", pattern: a, replacement: z}, [11, 10], 10, Str], # 12
  [PadAccess, {sigil: $, symbol: s}, [12], ~, Str], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Concat, ~, [7, 14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Print, ~, [17], 12, Scalar], # 18
  [Return, ~, [1], 18]]} # 19
```

## The comment character as a delimiter

`#` is PERL'S COMMENT CHARACTER, and it is also a legal delimiter. A
lexer reading left to right has already decided `m#abc#` is a comment
before it can know it was wrong. Every other delimiter in the tier is a
character with no other job at that position; `#` has one, and the two
readings differ by everything -- `m#abc#` is a match, while `m` followed
by a comment is a bareword and then nothing at all to end of line.

Measured under 5.42.0, the op stream is BYTE-IDENTICAL to the one for
`/abc/` and `s/a/z/`: `match(/"abc"/) sKS` and `subst(/"a"/)`. So
neither the optree nor the printed output can report a lexer that got
this wrong, and the token facts below are the only place the claim can
live.

Both spellings are here rather than the match alone, because the
substitution is where the hazard compounds: `s#a#z#` has THREE `#`
characters, and a lexer that recovers from the first by luck still has
two more to mis-read.

```perl
my $a = "abc" =~ m#abc#;
my $s = "abc";
$s =~ s#a#z#;
print "$a$s\n";
```

```behavior
parses: yes
```

```output
1zbc
```

```tokens
one quote-like operator whose text is "m#abc#"
one quote-like operator whose text is "s#a#z#"
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 2
  [RegexMatch, {flags: "", pattern: abc}, [2], ~, Boolean], # 3
  [Coerce, {from_repr: Boolean, to_repr: Str}, [3], ~, Str], # 4
  [MemStart], # 5
  [PadAccess, {sigil: $, symbol: s}, [5], ~, Unknown], # 6
  [Assign, ~, [6, 2], 0, Str], # 7
  [PadAccess, {sigil: $, symbol: s}, [7], ~, Unknown], # 8
  [RegexSubst, {flags: "", pattern: a, replacement: z}, [8, 7], 7, Str], # 9
  [PadAccess, {sigil: $, symbol: s}, [9], ~, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Concat, ~, [4, 11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [Print, ~, [14], 9, Scalar], # 15
  [Return, ~, [1], 15]]} # 16
```

## A bracketing delimiter nests

`m{a{b}c}` is a match on the pattern `a{b}c`: the inner braces are
CONTENT, not the terminator, and a lexer must count depth rather than
stop at the first `}`. This is the half of the tier's scope that a
delimiter FORM cannot express -- every other bracketing pattern here has
a body with no bracket in it, so all of them are satisfied by a lexer
that stops at the first closing character.

The asymmetry is what makes the rule a rule, and GLOSSARY.md records
both halves: bracketing delimiters nest, non-bracketing ones do not.
Measured, the non-bracketing counterpart is not merely different but
ILL-FORMED -- `"a!b!c" =~ m!a!b!c!` gives `Unknown regexp modifier "/b"`
and then a syntax error -- so it cannot appear in a case expected to
parse.

THE SUBSTITUTION IS WHAT PINS THE PATTERN'S EXTENT, and the `x` and `y`
around the target are why. A lexer that stopped at the first `}` would
take the pattern as `a{b` -- which still matches, so a bare match would
report 1 either way -- but the replacement would then cover three
characters instead of five and leave `}c` behind. `xoky` says the whole
five characters went, bounded on both sides by text the pattern must not
have touched.

```perl
my $hit = "a{b}c" =~ m{a{b}c};
my $s = "xa{b}cy";
$s =~ s{a{b}c}{ok};
print "[$hit][$s]\n";
```

```behavior
parses: yes
```

```output
[1][xoky]
```

```tokens
one quote-like operator whose text is "m{a{b}c}"
one quote-like operator whose text is "s{a{b}c}{ok}"
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "a{b}c"}, ~, ~, Str], # 3
  [RegexMatch, {flags: "", pattern: "a{b}c"}, [3], ~, Boolean], # 4
  [Coerce, {from_repr: Boolean, to_repr: Str}, [4], ~, Str], # 5
  [Concat, ~, [2, 5], ~, Str], # 6
  [Constant, {const_type: string, value: "]["}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [MemStart], # 9
  [PadAccess, {sigil: $, symbol: s}, [9], ~, Unknown], # 10
  [Constant, {const_type: string, value: "xa{b}cy"}, ~, ~, Str], # 11
  [Assign, ~, [10, 11], 0, Str], # 12
  [PadAccess, {sigil: $, symbol: s}, [12], ~, Unknown], # 13
  [RegexSubst, {flags: "", pattern: "a{b}c", replacement: ok}, [13, 12], 12, Str], # 14
  [PadAccess, {sigil: $, symbol: s}, [14], ~, Str], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [8, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Print, ~, [19], 14, Scalar], # 20
  [Return, ~, [1], 20]]} # 21
```
