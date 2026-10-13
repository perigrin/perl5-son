# Matching and substitution

The tier's baseline: a pattern bound to a string, negated, interpolated,
and made to mutate its target.

**Tier 09 regex.** Introduces `match`, `pos`, `qr`, `regcomp`, `split`,
`subst`, `trans`. Depends on 01_literals -- a match needs something to
match against, and the smallest such thing is a string literal.

Two measurements run through every case here. `=~` EMITS NO OP OF ITS
OWN, so the optree cannot tell you the operator was written; and a
constant pattern is compiled at COMPILE time while an interpolated one
is not, so one character of source is worth a whole op. Both are
recorded by the pairs below rather than by any single case.

## A constant pattern compiles once

A pattern with no interpolation is compiled at COMPILE time: the match
emits `match` alone, with no `regcomp` beside it. This is the tier's
baseline, and measuring the constant form first is what makes the
interpolated case's extra op attributable.

The token claims are negative, and deliberately so. GLOSSARY.md's
`quote-like operator` is defined as a quote spelled with an OPERATOR
NAME -- q, qq, m, s, qr -- or with backticks; a bare `/abc/` is neither,
so there is no positive category to assert it under and this case does
not invent one. What it can say is what a mis-lex would produce: the
hazard for a bare-slash pattern is the slash read as DIVISION and the
pattern body read as Perl, which yields an `Operator("/")` and a
`Word("abc")`. Asserting their absence is the claim that survives.

```perl
my $m = "abc" =~ /abc/;
print "$m\n";
```

```behavior
parses: yes
```

```output
1
```

```tokens
no operator whose text is "/"
no word whose text is "abc"
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 2
  [RegexMatch, {flags: "", pattern: abc}, [2], ~, Boolean], # 3
  [Coerce, {from_repr: Boolean, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Print, ~, [6], 0, Scalar], # 7
  [Return, {implicit: true}, [1], 7]]} # 8
```

## The binding operator emits nothing

`=~` emits NO OP OF ITS OWN. The binding operator is absorbed into the
match op, which carries its target in its own flags -- the stream shows
`match(/"b"/)[$s:1,3]` and no `bind` anywhere.

So this case and the bare match above differ in their OPERAND, not in
their op set. That is why the binding needs a case of its own: the
optree cannot tell you the operator was written, only that the match
found a target other than `$_`, and the token stream is what records the
operator.

```perl
my $s = "abc";
my $m = $s =~ /b/;
print "$m\n";
```

```behavior
parses: yes
```

```output
1
```

```tokens
one operator whose text is "=~"
no operator whose text is "/"
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 2
  [RegexMatch, {flags: "", pattern: b}, [2], ~, Boolean], # 3
  [Coerce, {from_repr: Boolean, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Print, ~, [6], 0, Scalar], # 7
  [Return, {implicit: true}, [1], 7]]} # 8
```

## The negated binding is two ops

`!~` is not a match op with a flag: it is `match` followed by `not`, a
second op stacked on top of the first. `not` is tier 04's op, claimed
there with the logical operators, and its appearance here is the negated
binding REUSING it rather than this tier introducing anything. The
measurement is still this tier's: reading the source would suggest a
negated match op, and there is none.

The pattern deliberately does not match, so the printed value is the
empty string rather than 0 -- Perl's false is `""` -- which is why the
brackets are there. Without them the pinned output would be a line with
nothing on it, and a mis-measured match would print the same.

```perl
my $s = "abc";
my $m = $s !~ /zzz/;
print "[$m]\n";
```

```behavior
parses: yes
```

```output
[1]
```

```tokens
one operator whose text is "!~"
no operator whose text is "!"
no operator whose text is "/"
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 3
  [RegexMatch, {flags: "", pattern: zzz}, [3], ~, Boolean], # 4
  [Not, ~, [4], ~, Boolean], # 5
  [Coerce, {from_repr: Boolean, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [2, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Print, ~, [9], 0, Scalar], # 10
  [Return, {implicit: true}, [1], 10]]} # 11
```

## Substitution mutates in place

A substitution mutates its target in place and emits one `subst` op. No
assignment, no block, no dereference -- which is the measurement behind
this tier's claim that it could sit at 03.

The replacement `z` arrives as a `const` pushed before the `subst`, not
as a second argument to it, and there is no `sassign`: `$s` is named in
the subst op's own flags exactly as the match op names its target.

```perl
my $s = "abc";
$s =~ s/a/z/;
print "$s\n";
```

```behavior
parses: yes
```

```output
zbc
```

```tokens
one quote-like operator whose text is "s/a/z/"
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: s}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 4
  [Assign, ~, [3, 4], 0, Str], # 5
  [PadAccess, {sigil: $, symbol: s}, [5], ~, Unknown], # 6
  [RegexSubst, {flags: "", pattern: a, replacement: z}, [6, 5], 5, Str], # 7
  [PadAccess, {sigil: $, symbol: s}, [7], ~, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Print, ~, [11], 7, Scalar], # 12
  [Return, {implicit: true}, [1], 12]]} # 13
```

## An interpolated pattern adds `regcomp`

An interpolated pattern cannot be compiled at compile time, so the
stream gains `regcomp` between the `padsv` that fetches the variable and
the `match` that uses the result. This is the ONLY form in the tier that
emits `regcomp`. Against the bare match above, one character of source
differs and a whole op appears; the tier's op set is their union.

Note also what the match op loses: `match()[$s:2,4]` carries no pattern
in its own dump, because it has none until `regcomp` runs.

The token claim is the sharpest in the tier. `$p` appears TWICE in the
source and must lex as ONE variable: the declaration's, with the
pattern's occurrence staying INSIDE the pattern token. A lexer that
recurses into a pattern -- reasonable-looking, since the pattern really
does interpolate -- produces two, and this is the assertion that catches
it. The optree cannot: perl interpolates at runtime either way and
`regcomp` is emitted regardless.

```perl
my $p = "b";
my $s = "abc";
my $m = $s =~ /$p/;
print "$m\n";
```

```behavior
parses: yes
```

```output
1
```

```tokens
one variable whose text is "$p"
no operator whose text is "/"
```

```ir
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Match, ~, [2, 3], ~, Boolean], # 4
  [Coerce, {from_repr: Boolean, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Print, ~, [7], 0, Scalar], # 8
  [Return, {implicit: true}, [1], 8]]} # 9
```

## `pos` and `\G` on a signature parameter

`pos($input) = $position` and the `\G` match after it both name the
same variable: the parameter's own copy, not the caller's string. The
match anchors where `pos` was set, so each call answers from its own
starting point. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl, which compiled and gave a wrong answer; with
the next case, it was why chalk's grammar matcher never advanced.

```perl
use v5.36;
sub token_end ($input, $position, $pattern) {
    pos($input) = $position;
    return $input =~ /\G($pattern)/ ? $position + length($1) : undef;
}
print token_end("aab", 1, "a+"), " ", token_end("aab", 2, "b"), " ",
      defined token_end("aab", 0, "b") ? "matched" : "none", "\n";
```

```behavior
parses: yes
```

```output
2 3 none
```

```ir
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: aab}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: string, value: "a+"}, ~, ~, Str], # 4
  [Call, {dispatch_kind: direct, name: main::token_end, param_names: [], want: list}, [2, 3, 4], 0, Unknown], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 7
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 8
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 9
  [Call, {dispatch_kind: direct, name: main::token_end, param_names: [], want: list}, [2, 8, 9], 5, Unknown], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Call, {dispatch_kind: direct, name: main::token_end, param_names: [], want: scalar}, [2, 12, 9], 10, Unknown], # 13
  [Defined, ~, [13], ~, Boolean], # 14
  [Constant, {const_type: string, value: matched}, ~, ~, Str], # 15
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 16
  [TernaryExpr, ~, [14, 15, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [6, 7, 11, 7, 17, 18], 13, Scalar], # 19
  [Return, {implicit: true}, [1], 19]]} # 20
main::token_end: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: input}, ~, ~, Unknown], # 1
  [Constant, {const_type: string, value: "\\G("}, ~, ~, Str], # 2
  [Parameter, {index: 2, name: $pattern, sigil: $}, ~, ~, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Concat, ~, [2, 4], ~, Str], # 5
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [MemStart], # 8
  [PadAccess, {sigil: $, symbol: input}, [8], ~, Unknown], # 9
  [Parameter, {index: 0, name: $input, sigil: $}, ~, ~, Unknown], # 10
  [Assign, ~, [9, 10], 0, Unknown], # 11
  [PadAccess, {sigil: $, symbol: input}, [11], ~, Unknown], # 12
  [Call, {dispatch_kind: builtin, name: pos, param_names: []}, [12], ~, Unknown], # 13
  [Parameter, {index: 1, name: $position, sigil: $}, ~, ~, Num], # 14
  [Assign, ~, [13, 14], 11, Num], # 15
  [Match, ~, [1, 7], 15, Boolean], # 16
  [RegexCapture, {"n": 1}, [16], ~, Str], # 17
  [Length, ~, [17], ~, Int], # 18
  [Add, ~, [14, 18], ~, Num], # 19
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 20
  [TernaryExpr, ~, [16, 19, 20], ~, Unknown], # 21
  [Return, ~, [21], 16]]} # 22
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
```

## A match in void context, kept for its captures

`$s =~ /(\w+)=(\w+)/;` discards the match's value, and its captures
remain: `$1` and `$2` are set for the statements after it. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl, which compiled and gave a wrong answer; with
the previous case, it was why chalk's grammar matcher never advanced.

```perl
my $s = "key=value";
$s =~ /(\w+)=(\w+)/;
print "$2 $1\n";
```

```behavior
parses: yes
```

```output
value key
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "key=value"}, ~, ~, Str], # 2
  [RegexMatch, {flags: "", pattern: "(\\w+)=(\\w+)"}, [2], 0, Boolean], # 3
  [RegexCapture, {"n": 2}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [RegexCapture, {"n": 1}, [3], ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Print, ~, [10], 3, Scalar], # 11
  [Return, {implicit: true}, [1], 11]]} # 12
```
