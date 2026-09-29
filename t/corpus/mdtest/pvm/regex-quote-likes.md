# Quote-likes that are not matches

Two constructs wearing regex syntax that the optree says are something
else: `qr//` compiles a pattern without matching anything, and `tr///`
is not a regex at all.

**Tier 09 regex.** Introduces `match`, `pos`, `qr`, `regcomp`, `split`,
`subst`, `trans`. Depends on 01_literals.

Both sit in this tier for the same reason: the LEXER cannot tell them
from a match. `qr` and `tr` are operator names in the same table as `m`
and `s`, and `tr` needs the entry in that table saying a second region
follows. What they emit afterwards is a different question, and in both
cases the answer is one op with no `match` beside it.

## A compiled pattern, uncoupled from matching

Plain `qr/abc/` emits a single `qr` op and nothing else: no `regcomp`,
no `match`, no block, no recursion. It is closer to a literal than to
anything tier 14 does.

Tier 14 owns `qr//` WITH EMBEDDED CODE, which is a re-entry problem.
Claiming the plain form there would make tier 14 depend on this tier for
the non-recursive half of one construct, so it stays here and tier 14
claims only what embedding adds.

Printing the object is safe because its stringification is deterministic
-- and it is `(?^:abc)`, NOT `(?^u:abc)`. The `u` appears only under a
unicode_strings-like feature bundle; this case runs without one.

```perl
my $r = qr/abc/;
print "$r\n";
```

```behavior
parses: yes
```

```output
(?^:abc)
```

```tokens
one quote-like operator whose text is "qr/abc/"
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: regex, value: abc}, ~, ~, Regex], # 2
  [Coerce, {from_repr: Regex, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [Print, ~, [5], 0, Scalar], # 6
  [Return, ~, [1], 6]]} # 7
```

## `tr///` wears `s///`'s syntax and is not a regex

`tr///` is the only quote-like besides `s///` that takes TWO delimited
regions -- and neither of its regions is a pattern. That asymmetry is
the trap.

WHY THE TWO-REGION SHAPE IS THE LEXICAL CLAIM. A lexer that knows only
`s` takes a second region reads `tr/./Z/` as `tr/./` followed by the
stray tokens `Z` and `/`, which is a different token stream and a
different program. Nothing about `tr`'s first region announces that a
second one follows; the operator NAME is the only signal, so a lexer
must carry a table of which quote-like names take two regions, and `tr`
(with its synonym `y`) is the entry most often missing from it.

AND `tr` IS NOT `s` WHERE IT COUNTS. Measured under 5.42.0 on the same
subject, `$_ = "a.c"; tr/./Z/` prints `aZc` while `$_ = "a.c"; s/./Z/`
prints `Z.c`. `tr`'s `.` is the CHARACTER dot; `s`'s `.` is the
metacharacter matching anything. So a parser that desugared `tr` into
`s` -- an easy thing to do when the syntax is this similar -- produces a
program that compiles, runs, and prints the wrong answer. Both spellings
run on one subject so the results sit side by side, and a desugared `tr`
prints `Z.c 1 Z.c` instead of `aZc 1 Z.c`.

THE RETURN VALUE IS THE SECOND BEHAVIOURAL PIN. `tr` returns the COUNT
of characters it transliterated, where a bare match returns a boolean.
Measured, `"a.c" =~ tr/./Z/` is 1. The count and the boolean agree at 1
here, which is why the count is pinned beside the two strings rather
than trusted to carry the claim alone.

The op is `trans`, measured as `trans[$t:1,2]
sP/TRANS=ONLY_UTF8_INVARIANTS` -- one op, no `match`, no `regcomp`, no
`subst`, which is the optree agreeing that `tr` is not a regex construct
at all despite wearing the syntax of one.

THE REPLACEMENT CHARACTER IS `Z` AND NOT `X`, which looks arbitrary and
is not. `no word whose text is "Z"` is the fact that falsifies a lexer
leaking the second region -- and with `X` as the replacement the fact is
false before `tr` is reached, because `$ENV{X}` puts a `Word("X")` in
the source's first line. A negative token fact is only a claim about the
construct if the character it names appears nowhere else.

The subject reads `$ENV{X}`, unset when the runner executes it, because
a `tr` on a constant is a folding candidate and a folded `tr` measures
nothing.

```perl
my $s = $ENV{X} // "a.c";
my $t = $s;
my $n = ($t =~ tr/./Z/);
my $u = $s;
$u =~ s/./Z/;
print "$t $n $u\n";
```

```behavior
parses: yes
```

```output
aZc 1 Z.c
```

```tokens
one quote-like operator whose text is "tr/./Z/"
one quote-like operator whose text is "s/./Z/"
no word whose text is "Z"
```

```ir
main::__PROGRAM__: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: t}, [2], ~, Unknown], # 3
  [EnvRead, {key: X}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: a.c}, ~, ~, Str], # 5
  [DefinedOr, ~, [4, 5], ~, Str], # 6
  [Assign, ~, [3, 6], 0, Str], # 7
  [PadAccess, {sigil: $, symbol: t}, [7], ~, Unknown], # 8
  [Transliterate, {flags: "", from: ".", to: Z}, [8, 7], 7, Str], # 9
  [PadAccess, {sigil: $, symbol: u}, [9], ~, Unknown], # 10
  [Assign, ~, [10, 6], 9, Str], # 11
  [PadAccess, {sigil: $, symbol: u}, [11], ~, Unknown], # 12
  [RegexSubst, {flags: "", pattern: ".", replacement: Z}, [12, 11], 11, Str], # 13
  [PadAccess, {sigil: $, symbol: t}, [13], ~, Str], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [TransliterateCount, ~, [9], ~, Int], # 18
  [Coerce, {from_repr: Int, to_repr: Str}, [18], ~, Str], # 19
  [Concat, ~, [17, 19], ~, Str], # 20
  [Concat, ~, [20, 16], ~, Str], # 21
  [PadAccess, {sigil: $, symbol: u}, [13], ~, Str], # 22
  [Coerce, {from_repr: Unknown, to_repr: Str}, [22], ~, Str], # 23
  [Concat, ~, [21, 23], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [Concat, ~, [24, 25], ~, Str], # 26
  [Print, ~, [26], 13, Scalar], # 27
  [Return, ~, [1], 27]]} # 28
```
