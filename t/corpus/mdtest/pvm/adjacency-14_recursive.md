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
main::__PROGRAM__: {start: 0, returns: [52], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 2], # 3
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 4
  [Assign, ~, [3, 4], 0, Str, 2, true], # 5
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Str, 5], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Add, ~, [7, 7], ~, Int], # 8
  [RegexSubst, {flags: "", pattern: a, replacement: ""}, [6, 8], 5, Str, 5, true], # 9
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Str, 9], # 10
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 9], # 11
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 12
  [RegexMatch, {flags: "", pattern: b}, [10], ~, Boolean], # 13
  [If, ~, [9, 13], 9], # 14
  [Proj, {index: 0}, [14]], # 15
  [EntryWrite, ~, [11, 12], 15, Unknown, 9, true], # 16
  [Call, {dispatch_kind: direct, eval_id: 1, file: "/tmp/osrpJFXK1Z/case.pl", line: 5, name: main::__PROGRAM__::__EVAL__:5:1, package: main, param_names: [], string_eval: true, want: scalar}, ~, 16, Int, 16, true], # 17
  [Region, {eval_entry: 15, eval_id: 1}, [17]], # 18
  [Phi, {region: 18}, [17, 1], ~, "Maybe[Int]"], # 19
  [Proj, {index: 1}, [14]], # 20
  [Region, {head: 14}, [18, 20]], # 21
  [Phi, {predecessors: [15, 20], region: 21}, [19, 1], ~, "Maybe[Int]"], # 22
  [Phi, {memory: true, region: 18}, [17], ~, Int], # 23
  [Phi, {memory: true, predecessors: [15, 20], region: 21}, [23, 9], ~, Str], # 24
  [RegexSubst, {flags: "", pattern: b, replacement: ""}, [10, 22], 21, Str, 24, true], # 25
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: k}, ~, ~, Unknown, 25], # 26
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 27
  [Assign, ~, [26, 27], 25, Int, 25, true], # 28
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Str, 28], # 29
  [RegexMatch, {code_bodies: [main::__PROGRAM__::__REGEXCODE__:1.0], flags: "", pattern: "2(?{ $k = 5 })"}, [29], 28, Boolean, 28, true], # 30
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: i}, ~, ~, Unknown, 30], # 31
  [Constant, {const_type: regex, value: c}, ~, ~, Regex], # 32
  [Assign, ~, [31, 32], 30, Regex, 30, true], # 33
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Str, 33], # 34
  [RegexMatch, {code_bodies: [main::__PROGRAM__::__REGEXCODE__:2.0], flags: "", pattern: "(??{ $i })"}, [34], 33, Boolean, 33, true], # 35
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Str, 35], # 36
  [Coerce, {from_repr: Unknown, to_repr: Str}, [36], ~, Str], # 37
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 38
  [Concat, ~, [37, 38], ~, Str], # 39
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: k}, ~, ~, Str, 35], # 40
  [Coerce, {from_repr: Unknown, to_repr: Str}, [40], ~, Str], # 41
  [Concat, ~, [39, 41], ~, Str], # 42
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 43
  [Concat, ~, [42, 43], ~, Str], # 44
  [If, ~, [35, 35], 35], # 45
  [Proj, {index: 1}, [45]], # 46
  [Constant, {const_type: string, value: "hit\n"}, ~, ~, Str], # 47
  [Proj, {index: 0}, [45]], # 48
  [Print, ~, [47], 48, "Maybe[Boolean]"], # 49
  [Region, {head: 45}, [46, 49]], # 50
  [Print, ~, [44], 50, "Maybe[Boolean]"], # 51
  [Return, {implicit: true}, [1], 51, ~, 35], # 52
  [RegexMatch, {flags: "", pattern: a}, [6], ~, Boolean]]} # 53
main::__PROGRAM__::__EVAL__:5:1: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "12"}, ~, ~, Int], # 1
  [MemStart], # 2
  [Return, {implicit: true}, [1], 0, ~, 2]]} # 3
main::__PROGRAM__::__REGEXCODE__:1.0: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [MemStart], # 2
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: k}, ~, ~, Unknown, 2], # 3
  [Assign, ~, [3, 1], 0, Int, 2, true], # 4
  [Return, {implicit: true}, [1], 4, ~, 4]]} # 5
main::__PROGRAM__::__REGEXCODE__:2.0: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: i}, ~, ~, Unknown, 1], # 2
  [Return, {implicit: true}, [2], 0, ~, 1]]} # 3
```
