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
main::__PROGRAM__: {start: 0, returns: [87], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: s}, [3], ~, Unknown], # 4
  [Constant, {const_type: string, value: abcd}, ~, ~, Str], # 5
  [Assign, ~, [4, 5], 0, Str], # 6
  [RegexMatch, {flags: "", pattern: abc}, [2], 6, Boolean], # 7
  [Coerce, {from_repr: Boolean, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [RegexMatch, {flags: "", pattern: zzz}, [2], 7, Boolean], # 11
  [Not, ~, [11], ~, Boolean], # 12
  [Coerce, {from_repr: Boolean, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [10, 13], ~, Str], # 14
  [Concat, ~, [14, 9], ~, Str], # 15
  [RegexMatch, {flags: "", pattern: abc}, [2], 11, Boolean], # 16
  [Coerce, {from_repr: Boolean, to_repr: Str}, [16], ~, Str], # 17
  [Concat, ~, [15, 17], ~, Str], # 18
  [Concat, ~, [18, 9], ~, Str], # 19
  [RegexMatch, {flags: "", pattern: abc}, [2], 16, Boolean], # 20
  [Coerce, {from_repr: Boolean, to_repr: Str}, [20], ~, Str], # 21
  [Concat, ~, [19, 21], ~, Str], # 22
  [Concat, ~, [22, 9], ~, Str], # 23
  [Constant, {const_type: string, value: "a{b}c"}, ~, ~, Str], # 24
  [RegexMatch, {flags: "", pattern: "a{b}c"}, [24], ~, Boolean], # 25
  [Coerce, {from_repr: Boolean, to_repr: Str}, [25], ~, Str], # 26
  [Concat, ~, [23, 26], ~, Str], # 27
  [Concat, ~, [27, 9], ~, Str], # 28
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 29
  [Match, ~, [2, 29], 20, Boolean], # 30
  [Coerce, {from_repr: Boolean, to_repr: Str}, [30], ~, Str], # 31
  [Concat, ~, [28, 31], ~, Str], # 32
  [Concat, ~, [32, 9], ~, Str], # 33
  [Constant, {const_type: regex, value: abc}, ~, ~, Regex], # 34
  [Coerce, {from_repr: Regex, to_repr: Str}, [34], ~, Str], # 35
  [Concat, ~, [33, 35], ~, Str], # 36
  [Concat, ~, [36, 9], ~, Str], # 37
  [PadAccess, {sigil: $, symbol: pos}, ~, ~, Str], # 38
  [RegexSubst, {flags: "", pattern: a, replacement: z}, [2, 6], 30, Str], # 39
  [RegexSubst, {flags: "", pattern: c, replacement: "y"}, [2, 39], 39, Str], # 40
  [RegexSubst, {flags: "", pattern: d, replacement: w}, [2, 40], 40, Str], # 41
  [PadAccess, {sigil: $, symbol: "n"}, [41], ~, Unknown], # 42
  [Assign, ~, [42, 24], 41, Str], # 43
  [PadAccess, {sigil: $, symbol: "n"}, [43], ~, Unknown], # 44
  [RegexSubst, {flags: "", pattern: "a{b}c", replacement: ok}, [44, 43], 43, Str], # 45
  [PadAccess, {sigil: $, symbol: tr}, [45], ~, Unknown], # 46
  [Constant, {const_type: string, value: a.c}, ~, ~, Str], # 47
  [Assign, ~, [46, 47], 45, Str], # 48
  [PadAccess, {sigil: $, symbol: tr}, [48], ~, Unknown], # 49
  [Transliterate, {flags: "", from: ".", to: Z}, [49, 48], 48, Str], # 50
  [PadAccess, {sigil: $, symbol: pos}, [50], ~, Unknown], # 51
  [Constant, {const_type: string, value: abcabc}, ~, ~, Str], # 52
  [Assign, ~, [51, 52], 50, Str], # 53
  [RegexMatch, {flags: g, pattern: b}, [38], 53, Boolean], # 54
  [PadAccess, {sigil: $, symbol: s}, [54], ~, Str], # 55
  [Coerce, {from_repr: Unknown, to_repr: Str}, [55], ~, Str], # 56
  [Concat, ~, [37, 56], ~, Str], # 57
  [Concat, ~, [57, 9], ~, Str], # 58
  [PadAccess, {sigil: $, symbol: "n"}, [54], ~, Str], # 59
  [Coerce, {from_repr: Unknown, to_repr: Str}, [59], ~, Str], # 60
  [Concat, ~, [58, 60], ~, Str], # 61
  [Concat, ~, [61, 9], ~, Str], # 62
  [PadAccess, {sigil: $, symbol: tr}, [54], ~, Str], # 63
  [Coerce, {from_repr: Unknown, to_repr: Str}, [63], ~, Str], # 64
  [Concat, ~, [62, 64], ~, Str], # 65
  [Concat, ~, [65, 9], ~, Str], # 66
  [TransliterateCount, ~, [50], ~, Int], # 67
  [Coerce, {from_repr: Int, to_repr: Str}, [67], ~, Str], # 68
  [Concat, ~, [66, 68], ~, Str], # 69
  [Concat, ~, [69, 9], ~, Str], # 70
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [54], ~, Scalar], # 71
  [Coerce, {from_repr: Scalar, to_repr: Str}, [71], ~, Str], # 72
  [Constant, {const_type: regex, value: " "}, ~, ~, Regex], # 73
  [Constant, {const_type: string, value: "p q"}, ~, ~, Str], # 74
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 75
  [Call, {dispatch_kind: builtin, name: split, param_names: []}, [73, 74, 75], ~, List], # 76
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [72, 76], ~, Str], # 77
  [Concat, ~, [70, 77], ~, Str], # 78
  [Concat, ~, [78, 9], ~, Str], # 79
  [PadAccess, {sigil: $, symbol: pos}, [54], ~, Unknown], # 80
  [Call, {dispatch_kind: builtin, name: pos, param_names: []}, [80], 54, Unknown], # 81
  [Coerce, {from_repr: Unknown, to_repr: Str}, [81], ~, Str], # 82
  [Concat, ~, [79, 82], ~, Str], # 83
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 84
  [Concat, ~, [83, 84], ~, Str], # 85
  [Print, ~, [85], 81, Scalar], # 86
  [Return, ~, [1], 86]]} # 87
```
