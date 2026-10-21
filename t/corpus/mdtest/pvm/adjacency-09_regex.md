# Every regex construct, each beside another

One body holding every construct this tier introduces, each adjacent to
another, and every delimiter form the tier teaches.

**Tier 09 regex.** Introduces nothing of its own; it is the mixture that
is the subject. Depends on 01_literals.

The tier's other cases are one construct each, which is what makes them
diagnosable. That same property is why a corpus of such cases cannot
reach an ADJACENCY bug -- and in a tier whose operand is not Perl, the
adjacency bug is the one to expect. A lexer that delimits a pattern by
scanning for the next `/` is correct on every case here taken alone and
wrong the moment an `s{a}{z}` sits between two matches.

## The whole tier in one body

The constructs sit consecutively: a constant match, a negated match
through a bracketing delimiter, a match through a non-bracketing one, a
match through the comment character, a match whose pattern NESTS its own
delimiter, an interpolated match, a `qr//`, four substitutions delimited
by brackets, slashes, hashes and nested brackets, a `tr///`, a `split`
on a pattern, and a `//g` match read through `pos` -- then one print
that reads every result.

THE LAST THREE ARE WHERE THE ADJACENCY CLAIM EARNS ITS KEEP a second
time. `tr/./Z/` is a second two-region quote-like, and a lexer whose
table says only `s` takes two regions mis-terminates it and then
mis-terminates everything after it -- a failure a one-construct-per-case
`tr` test cannot reach, because there is nothing after it to break.
`split / /` puts a pattern in an ARGUMENT SLOT immediately following
that, which is the position a lexer recovering from a botched `tr` is
most likely to read as division. The pattern is a single space, the
least distinguishable body a slash-delimited pattern can have.

EVERY DELIMITER FORM THE TIER TEACHES APPEARS HERE, which is the part
that needed fixing. The body shipped holding `m{}`, `s{}{}` and `qr//`
alone -- so the one bug it exists to reach was unreachable for every
form most likely to produce it.

Three of the added forms are the ones that cannot NEST. `m!abc!`,
`s/c/y/` and `s#d#w#` each close with the character they opened with, so
a lexer has no bracket depth to count and must simply stop at the next
occurrence. The fourth is the opposite case and is here for the
contrast: `m{a{b}c}` and `s{a{b}c}{ok}` carry their own opening brace
inside the pattern, where a lexer MUST count depth. That pair of rules
is what GLOSSARY.md records, and neither `m{zzz}` nor `s{a}{z}`
exercises either half.

The hash forms are the sharpest pair. `#` is Perl's comment character,
so a lexer that has not yet recognised the `m` or `s` has already
discarded the rest of the line. Putting them BETWEEN other delimiter
forms rather than alone is the adjacency claim in its strongest version:
recovering from `m#abc#` is not enough if the `s#d#w#` three statements
later is then read as a comment.

The tier's dependency on 01_literals is present rather than decorative:
every pattern here is matched against a string literal bound to a pad
slot, and the final print interpolates every result into one
double-quoted string. Pairing with 08_references instead would assert
nothing.

The substitutions run LAST on purpose. They mutate `$s`, which the five
matches above them read; running any earlier would make those results
depend on statement order in a way that hides a mis-parse behind a
plausible-looking output. Each of the three that touch `$s` mutates a
DIFFERENT character -- `a`, `c` and `d` -- so the final `zbyw` records
that all three ran, where two substitutions of one character would leave
the second's failure invisible. The nested substitution needs its own
target, `$n`, because its pattern is five characters `$s` does not hold.

```perl
my $s = "abcd";
my $p = "b";
my $hit = $s =~ /abc/;
my $miss = $s !~ m{zzz};
my $bang = $s =~ m!abc!;
my $hash = $s =~ m#abc#;
my $nest = "a{b}c" =~ m{a{b}c};
my $interp = $s =~ /$p/;
my $re = qr/abc/;
$s =~ s{a}{z};
$s =~ s/c/y/;
$s =~ s#d#w#;
my $n = "a{b}c";
$n =~ s{a{b}c}{ok};
my $tr = "a.c";
my $cnt = ($tr =~ tr/./Z/);
my @f = split / /, "p q";
my $pos = "abcabc";
$pos =~ m/b/g;
my $at = pos($pos);
print "$hit $miss $bang $hash $nest $interp $re $s $n $tr $cnt @f $at\n";
```

```behavior
parses: yes
```

```output
1 1 1 1 1 1 (?^:abc) zbyw ok aZc 1 p q 2
```

```tokens
one quote-like operator whose text is "m{zzz}"
one quote-like operator whose text is "m!abc!"
one quote-like operator whose text is "m#abc#"
one quote-like operator whose text is "m{a{b}c}"
one quote-like operator whose text is "s{a}{z}"
one quote-like operator whose text is "s/c/y/"
one quote-like operator whose text is "s#d#w#"
one quote-like operator whose text is "s{a{b}c}{ok}"
one quote-like operator whose text is "qr/abc/"
one quote-like operator whose text is "tr/./Z/"
one quote-like operator whose text is "m/b/g"
```

```ir
main::__PROGRAM__: {start: 0, returns: [89], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: s}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: abcd}, ~, ~, Str], # 4
  [Assign, ~, [3, 4], 0, Str], # 5
  [PadAccess, {sigil: $, symbol: s}, [5], ~, Str], # 6
  [RegexMatch, {flags: "", pattern: abc}, [6], 5, Boolean], # 7
  [Coerce, {from_repr: Boolean, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [RegexMatch, {flags: "", pattern: zzz}, [6], 7, Boolean], # 11
  [Not, ~, [11], ~, Boolean], # 12
  [Coerce, {from_repr: Boolean, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [10, 13], ~, Str], # 14
  [Concat, ~, [14, 9], ~, Str], # 15
  [RegexMatch, {flags: "", pattern: abc}, [6], 11, Boolean], # 16
  [Coerce, {from_repr: Boolean, to_repr: Str}, [16], ~, Str], # 17
  [Concat, ~, [15, 17], ~, Str], # 18
  [Concat, ~, [18, 9], ~, Str], # 19
  [RegexMatch, {flags: "", pattern: abc}, [6], 16, Boolean], # 20
  [Coerce, {from_repr: Boolean, to_repr: Str}, [20], ~, Str], # 21
  [Concat, ~, [19, 21], ~, Str], # 22
  [Concat, ~, [22, 9], ~, Str], # 23
  [Constant, {const_type: string, value: "a{b}c"}, ~, ~, Str], # 24
  [RegexMatch, {flags: "", pattern: "a{b}c"}, [24], ~, Boolean], # 25
  [Coerce, {from_repr: Boolean, to_repr: Str}, [25], ~, Str], # 26
  [Concat, ~, [23, 26], ~, Str], # 27
  [Concat, ~, [27, 9], ~, Str], # 28
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 29
  [Match, ~, [6, 29], 20, Boolean], # 30
  [Coerce, {from_repr: Boolean, to_repr: Str}, [30], ~, Str], # 31
  [Concat, ~, [28, 31], ~, Str], # 32
  [Concat, ~, [32, 9], ~, Str], # 33
  [Constant, {const_type: regex, value: abc}, ~, ~, Regex], # 34
  [Coerce, {from_repr: Regex, to_repr: Str}, [34], ~, Str], # 35
  [Concat, ~, [33, 35], ~, Str], # 36
  [Concat, ~, [36, 9], ~, Str], # 37
  [RegexSubst, {flags: "", pattern: a, replacement: z}, [6, 5], 30, Str], # 38
  [PadAccess, {sigil: $, symbol: s}, [38], ~, Unknown], # 39
  [RegexSubst, {flags: "", pattern: c, replacement: "y"}, [39, 38], 38, Str], # 40
  [PadAccess, {sigil: $, symbol: s}, [40], ~, Unknown], # 41
  [RegexSubst, {flags: "", pattern: d, replacement: w}, [41, 40], 40, Str], # 42
  [PadAccess, {sigil: $, symbol: "n"}, [42], ~, Unknown], # 43
  [Assign, ~, [43, 24], 42, Str], # 44
  [PadAccess, {sigil: $, symbol: "n"}, [44], ~, Unknown], # 45
  [RegexSubst, {flags: "", pattern: "a{b}c", replacement: ok}, [45, 44], 44, Str], # 46
  [PadAccess, {sigil: $, symbol: tr}, [46], ~, Unknown], # 47
  [Constant, {const_type: string, value: a.c}, ~, ~, Str], # 48
  [Assign, ~, [47, 48], 46, Str], # 49
  [PadAccess, {sigil: $, symbol: tr}, [49], ~, Unknown], # 50
  [Transliterate, {flags: "", from: ".", to: Z}, [50, 49], 49, Str], # 51
  [PadAccess, {sigil: $, symbol: pos}, [51], ~, Unknown], # 52
  [Constant, {const_type: string, value: abcabc}, ~, ~, Str], # 53
  [Assign, ~, [52, 53], 51, Str], # 54
  [PadAccess, {sigil: $, symbol: pos}, [54], ~, Str], # 55
  [RegexMatch, {flags: g, pattern: b}, [55], 54, Boolean], # 56
  [PadAccess, {sigil: $, symbol: s}, [56], ~, Str], # 57
  [Coerce, {from_repr: Unknown, to_repr: Str}, [57], ~, Str], # 58
  [Concat, ~, [37, 58], ~, Str], # 59
  [Concat, ~, [59, 9], ~, Str], # 60
  [PadAccess, {sigil: $, symbol: "n"}, [56], ~, Str], # 61
  [Coerce, {from_repr: Unknown, to_repr: Str}, [61], ~, Str], # 62
  [Concat, ~, [60, 62], ~, Str], # 63
  [Concat, ~, [63, 9], ~, Str], # 64
  [PadAccess, {sigil: $, symbol: tr}, [56], ~, Str], # 65
  [Coerce, {from_repr: Unknown, to_repr: Str}, [65], ~, Str], # 66
  [Concat, ~, [64, 66], ~, Str], # 67
  [Concat, ~, [67, 9], ~, Str], # 68
  [TransliterateCount, ~, [51], ~, Int], # 69
  [Coerce, {from_repr: Int, to_repr: Str}, [69], ~, Str], # 70
  [Concat, ~, [68, 70], ~, Str], # 71
  [Concat, ~, [71, 9], ~, Str], # 72
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [56], ~, Scalar], # 73
  [Coerce, {from_repr: Scalar, to_repr: Str}, [73], ~, Str], # 74
  [Constant, {const_type: regex, value: " "}, ~, ~, Regex], # 75
  [Constant, {const_type: string, value: "p q"}, ~, ~, Str], # 76
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 77
  [Call, {dispatch_kind: builtin, name: split, param_names: []}, [75, 76, 77], ~, List], # 78
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [74, 78, 56], ~, Str], # 79
  [Concat, ~, [72, 79], ~, Str], # 80
  [Concat, ~, [80, 9], ~, Str], # 81
  [PadAccess, {sigil: $, symbol: pos}, [56], ~, Unknown], # 82
  [Call, {dispatch_kind: builtin, name: pos, param_names: []}, [82], 56, Unknown], # 83
  [Coerce, {from_repr: Unknown, to_repr: Str}, [83], ~, Str], # 84
  [Concat, ~, [81, 84], ~, Str], # 85
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 86
  [Concat, ~, [85, 86], ~, Str], # 87
  [Print, ~, [87], 83, Scalar], # 88
  [Return, {implicit: true}, [1], 88]]} # 89
```
