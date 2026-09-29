# Every re-entrant construct, each beside another

One body holding every construct this tier introduces, each adjacent to
another -- plus the deferred form `(??{ })`, which appears only here.

**Tier 14 recursive.** Introduces nothing of its own; it is the mixture
that is the subject. Depends on 09_regex.

The tier's other cases are one construct each, which is what makes them
diagnosable. That same property is why they cannot reach the bug this tier
is most exposed to. A lexer that handles re-entry by special-casing ONE
level -- remember you are inside a replacement, lex to the closing
delimiter, hand it back -- passes every isolated case and still has no
stack. Four re-entrant constructs in one statement sequence is what asks
whether the mechanism nests or merely remembers.

THE PAIRING WITH THE EARLIER TIER is with `09_regex`, this tier's declared
dependency: `qr/c/` is tier 09's plain compiled pattern, and the
`(??{ $i })` beside it is this tier's deferred re-entry interpolating that
object mid-match. Adjacent, in one pattern, which is where a lexer that
delimits `(?{` by counting braces rather than by parsing would find the
extra `?` and stop.

`(??{ })` -- the DEFERRED form -- appears here and nowhere else, because it
introduces no op and no token category the other cases do not already
cover. Measured, `/a(??{ $inner })/` is one `match` op whose pattern string
holds the block, the same shape as `(?{ })`: the difference between the two
is WHEN the engine runs the code and what it does with the result --
`(?{ })` runs it for effect, `(??{ })` uses its return value as a pattern
to match right there. That distinction is entirely inside the regex engine
and invisible to both the optree and the token stream, so it earns a place
in the adjacency case rather than a case of its own.

No `use re 'eval'` and no warnings suppression anywhere here. Measured,
LITERAL code blocks compile and run clean under `use strict; use
warnings`; the pragma is required only when the pattern itself is
interpolated from a variable. `(??{ $i })` interpolates a variable INTO the
block, not the block into the pattern, which is why it too is exempt.

## The whole tier in one body

The string walks `abc` -> `2bc` (the `/e` replacement evaluates `$n+1`) ->
`212c` (the `/ee` replacement evaluates `$c` to `3*4`, then evaluates THAT
to `12`). `$k` is 5 because the `(?{ })` block ran when the engine reached
it, and `hit` prints because the deferred block returned the compiled
`qr/c/` and the engine matched it.

The `no` claims are what the mixture buys. `+` and `5` are each unique to
a re-entrant region here, so either one surfacing as an outer token means
a lexer read into a region it was supposed to delimit -- and with four
such regions in sequence, it names which layer of re-entry lost its place.

```perl
my $s = "abc";
my $n = 1;
$s =~ s/a/$n+1/e;
my $c = q{3*4};
$s =~ s/b/$c/ee;
my $k = 0;
$s =~ /2(?{ $k = 5 })/;
my $i = qr/c/;
print "hit\n" if $s =~ /(??{ $i })/;
print "$s $k\n";
```

```behavior
parses: yes
```

```output
hit
212c 5
```

```tokens
one quote-like operator whose text is "s/a/$n+1/e"
one quote-like operator whose text is "s/b/$c/ee"
one quote-like operator whose text is "qr/c/"
no operator whose text is "+"
no numeric literal whose text is "5"
```

```ir
main::__PROGRAM__: {start: 0, returns: [45], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: s}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 4
  [Assign, ~, [3, 4], 0, Str], # 5
  [PadAccess, {sigil: $, symbol: s}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "3*4"}, ~, ~, Str], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Add, ~, [8, 8], ~, Int], # 9
  [RegexSubst, {flags: "", pattern: a, replacement: ""}, [6, 9, 5], 5, Str], # 10
  [RegexMatch, {flags: "", pattern: b}, [6], ~, Boolean], # 11
  [If, ~, [10, 11], 10], # 12
  [Proj, {index: 0}, [12]], # 13
  [Coerce, {from_repr: Str, to_repr: Code}, [7], 13, Code], # 14
  [Region, ~, [14]], # 15
  [Phi, {region: 15}, [14, 1], ~, Unknown], # 16
  [Proj, {index: 1}, [12]], # 17
  [Region, {head: 12}, [15, 17]], # 18
  [Phi, {predecessors: [13, 17], region: 18}, [16, 1], ~, Unknown], # 19
  [RegexSubst, {flags: "", pattern: b, replacement: ""}, [6, 19, 10], 18, Str], # 20
  [PadAccess, {sigil: $, symbol: k}, [20], ~, Unknown], # 21
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 22
  [Assign, ~, [21, 22], 20, Int], # 23
  [RegexMatch, {flags: "", pattern: "2(?{ $k = 5 })"}, [6], 23, Boolean], # 24
  [PadAccess, {sigil: $, symbol: i}, [24], ~, Unknown], # 25
  [Constant, {const_type: regex, value: c}, ~, ~, Regex], # 26
  [Assign, ~, [25, 26], 24, Regex], # 27
  [RegexMatch, {flags: "", pattern: "(??{ $i })"}, [6], 27, Boolean], # 28
  [PadAccess, {sigil: $, symbol: s}, [28], ~, Str], # 29
  [Coerce, {from_repr: Unknown, to_repr: Str}, [29], ~, Str], # 30
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 31
  [Concat, ~, [30, 31], ~, Str], # 32
  [PadAccess, {sigil: $, symbol: k}, [28], ~, Str], # 33
  [Coerce, {from_repr: Unknown, to_repr: Str}, [33], ~, Str], # 34
  [Concat, ~, [32, 34], ~, Str], # 35
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 36
  [Concat, ~, [35, 36], ~, Str], # 37
  [If, ~, [28, 28], 28], # 38
  [Proj, {index: 1}, [38]], # 39
  [Constant, {const_type: string, value: "hit\n"}, ~, ~, Str], # 40
  [Proj, {index: 0}, [38]], # 41
  [Print, ~, [40], 41, Scalar], # 42
  [Region, {head: 38}, [39, 42]], # 43
  [Print, ~, [37], 43, Scalar], # 44
  [Return, ~, [1], 44], # 45
  [RegexMatch, {flags: "", pattern: a}, [6], ~, Boolean]]} # 46
```
