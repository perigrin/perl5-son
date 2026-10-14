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
main::__PROGRAM__: {start: 0, returns: [48], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: s}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 4
  [Assign, ~, [3, 4], 0, Str], # 5
  [PadAccess, {sigil: $, symbol: s}, [5], ~, Str], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Add, ~, [7, 7], ~, Int], # 8
  [RegexSubst, {flags: "", pattern: a, replacement: ""}, [6, 8, 5], 5, Str], # 9
  [PadAccess, {sigil: $, symbol: s}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "3*4"}, ~, ~, Str], # 11
  [RegexMatch, {flags: "", pattern: b}, [10], ~, Boolean], # 12
  [If, ~, [9, 12], 9], # 13
  [Proj, {index: 0}, [13]], # 14
  [Coerce, {from_repr: Str, to_repr: Code}, [11], 14, Code], # 15
  [Region, ~, [15]], # 16
  [Phi, {region: 16}, [15, 1], ~, Unknown], # 17
  [Proj, {index: 1}, [13]], # 18
  [Region, {head: 13}, [16, 18]], # 19
  [Phi, {predecessors: [14, 18], region: 19}, [17, 1], ~, Unknown], # 20
  [RegexSubst, {flags: "", pattern: b, replacement: ""}, [10, 20, 9], 19, Str], # 21
  [PadAccess, {sigil: $, symbol: k}, [21], ~, Unknown], # 22
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 23
  [Assign, ~, [22, 23], 21, Int], # 24
  [PadAccess, {sigil: $, symbol: s}, [24], ~, Str], # 25
  [RegexMatch, {flags: "", pattern: "2(?{ $k = 5 })"}, [25], 24, Boolean], # 26
  [PadAccess, {sigil: $, symbol: i}, [26], ~, Unknown], # 27
  [Constant, {const_type: regex, value: c}, ~, ~, Regex], # 28
  [Assign, ~, [27, 28], 26, Regex], # 29
  [PadAccess, {sigil: $, symbol: s}, [29], ~, Str], # 30
  [RegexMatch, {flags: "", pattern: "(??{ $i })"}, [30], 29, Boolean], # 31
  [PadAccess, {sigil: $, symbol: s}, [31], ~, Str], # 32
  [Coerce, {from_repr: Unknown, to_repr: Str}, [32], ~, Str], # 33
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 34
  [Concat, ~, [33, 34], ~, Str], # 35
  [PadAccess, {sigil: $, symbol: k}, [31], ~, Str], # 36
  [Coerce, {from_repr: Unknown, to_repr: Str}, [36], ~, Str], # 37
  [Concat, ~, [35, 37], ~, Str], # 38
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 39
  [Concat, ~, [38, 39], ~, Str], # 40
  [If, ~, [31, 31], 31], # 41
  [Proj, {index: 1}, [41]], # 42
  [Constant, {const_type: string, value: "hit\n"}, ~, ~, Str], # 43
  [Proj, {index: 0}, [41]], # 44
  [Print, ~, [43], 44, Scalar], # 45
  [Region, {head: 41}, [42, 45]], # 46
  [Print, ~, [40], 46, Scalar], # 47
  [Return, {implicit: true}, [1], 47], # 48
  [RegexMatch, {flags: "", pattern: a}, [6], ~, Boolean]]} # 49
```
