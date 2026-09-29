# Hashes

Naming a hash, subscripting it with braces, and the two words -- `exists`
and `delete` -- that mostly leave no op behind.

**Tier 02 variables.** Introduces `aassign`, `aelem`, `aelemfast`,
`aelemfast_lex`, `aelemfastlex_store`, `aslice`, `av2arylen`, `delete`,
`each`, `gv`, `gvsv`, `helem`, `hslice`, `multideref`, `padav`, `padhv`,
`push`, `rv2av`, `rv2hv`, `sassign`, `unshift`, `values`. Depends on
01_literals.

Hash order is not guaranteed, so nothing below prints a hash's contents.
`scalar(keys %h)` asks how many rather than which, and that is the count
every case here pins.

## A hash, and a bareword key

A hash is named with `%` and subscripted with braces; `$h{a}` is
one element of it, and the bareword key needs no quotes.

`$h{a}` emits no `helem`. It compiles to `multideref($h{"a"})`, the op
that swallows most element access in this tier; `helem` survives only
where the subscript is an expression, which is the next case. `keys`
likewise emits no op of its own here -- it becomes a FLAG on the
`padhv`, `sM/KEYS`. That flag is a property of SCALAR context, not of
the keyword; in list context `keys` emits an op, which is why the
aggregate-operators topic writes `values` and no `keys` at all.

```perl
my %h = (a => 1, b => 2);
print scalar(keys %h), "\n";
print $h{a}, "\n";
```

```behavior
parses: yes
```

```output
2
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [HashLiteral, {sigil: "%", symbol: h}, [2, 3, 4, 5], ~, Hash], # 6
  [MemStart], # 7
  [Subscript, ~, [6, 2, 7], ~, Int], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Call, {dispatch_kind: builtin, name: keys, param_names: []}, [6, 7], ~, Int], # 11
  [Coerce, {from_repr: Int, to_repr: Str}, [11], ~, Str], # 12
  [Print, ~, [12, 10], 0, Scalar], # 13
  [Print, ~, [9, 10], 13, Scalar], # 14
  [Return, ~, [1], 14]]} # 15
```

## A bareword key may be spelled like a quote-like operator

`$h{m}` is the key `"m"`, not a match. Every name in perl's quote-like
set -- `q qq qw qx m qr s tr y` -- autoquotes as a lone bareword
subscript, measured on 5.42.0:

    $ perl -MO=Deparse -e 'my %h; my $a=$h{m}; my $b=$h{s}; my $c=$h{tr};'
      ->  $h{'m'}  $h{'s'}  $h{'tr'}

THE OPTREE CANNOT SEE THIS CASE, which is why the token fact carries it.
The ops are the same `multideref` the case above emits, so a corpus that
asserted only ops would hold `$h{m}` and `$h{a}` to be the same claim.
They are not: the LEXER has to decide whether `m` opens an operator, and
getting it wrong swallows source. Before the fix, `$h{m}` lexed as a
match whose delimiter was `}`, so the body ran to the NEXT `}` and the
emission gained a spurious `};`.

A `}` never delimits one of these operators in a program perl will
COMPILE, in any context and not only a subscript: `perl -e 'sub f { m }'`
is "Search pattern not terminated". So the subscript is the only spelling
that compiles, and a lexer needs no bracket-stack knowledge to tell the
two apart -- the byte after the name settles it. A brace-DELIMITED
operator in the same position stays an operator, because there that byte
is `{`: `$h{ m{a} }` deparses to `$h{/a/}`.

The hash is built with QUOTED keys so each bareword below appears
exactly once, which is what a `one ...` fact requires.

```perl
my %h = ("m" => 1, "s" => 2, "tr" => 3, "qw" => 4);
print $h{m}, $h{s}, $h{tr}, $h{qw}, "\n";
```

```behavior
parses: yes
```

```output
1234
```

```tokens
one word whose text is "m"
one word whose text is "s"
one word whose text is "tr"
one word whose text is "qw"
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: m}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Constant, {const_type: string, value: tr}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [Constant, {const_type: string, value: qw}, ~, ~, Str], # 8
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 9
  [HashLiteral, {sigil: "%", symbol: h}, [2, 3, 4, 5, 6, 7, 8, 9], ~, Hash], # 10
  [MemStart], # 11
  [Subscript, ~, [10, 2, 11], ~, Int], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Subscript, ~, [10, 4, 11], ~, Int], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Subscript, ~, [10, 6, 11], ~, Int], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Subscript, ~, [10, 8, 11], ~, Int], # 18
  [Coerce, {from_repr: Unknown, to_repr: Str}, [18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Print, ~, [13, 15, 17, 19, 20], 0, Scalar], # 21
  [Return, ~, [1], 21]]} # 22
```

## A computed subscript is the only route to `helem`

`$h{a}` is `multideref`. `$h{$k[0]}` is `helem` over an
`aelemfast_lex` -- same construct in the source, different op, decided
entirely by what is inside the braces. This case exists because it is
the only way to reach `helem` at all, and a tier that claimed `helem`
without it would be claiming an op no file emits.

```perl
my %h = (a => 1, b => 2);
my @k = ("b");
print $h{$k[0]}, "\n";
```

```behavior
parses: yes
```

```output
2
```

```ir
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [HashLiteral, {sigil: "%", symbol: h}, [2, 3, 4, 5], ~, Hash], # 6
  [ArrayLiteral, {sigil: "@", symbol: k}, [4], ~, Array], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [MemStart], # 9
  [Subscript, ~, [7, 8, 9], ~, Str], # 10
  [Subscript, ~, [6, 10, 9], ~, Scalar], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [12, 13], 0, Scalar], # 14
  [Return, ~, [1], 14]]} # 15
```

## `exists` and `delete` on an element leave no op of their own

Measured, `exists $h{a}` compiles to `multideref($h{"a"})
sK/EXISTS` and `delete $h{a}` to `multideref($h{"a"}) sK/DELETE`: both
survive only as a FLAG on an op named after something else. A tier
derived from op names alone would contain no notion of `exists` at all,
and the slice case below would be the only evidence `delete` exists --
for the wrong reason, since the slice is the spelling where the
optimiser DECLINES to fold. This case is the common path; that one is
the exception.

BOTH TRUTH VALUES OF `exists` ARE HERE because the false one is a
different claim. Perl's false is the empty string, so `print exists
$h{z}` prints NOTHING and the pinned output carries a blank line -- a
case that tested only the true value could not tell `exists` from a
construct that always yields 1.

`print exists $h{a}` rather than `print exists $h{a} ? 1 : 0`: measured,
the conditional adds `cond_expr` and `0+(...)` adds `add`, and both are
ops later tiers introduce. The plain print is the only spelling of this
construct that stays inside the tier.

`delete` in scalar context returns the value removed, which is what
makes it observable without printing the hash.

```perl
my %h = (a => 1, b => 2);
print exists $h{a}, "\n";
print exists $h{z}, "\n";
my $gone = delete $h{a};
print $gone, "\n";
print scalar(keys %h), "\n";
```

```behavior
parses: yes
```

```output
1

1
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [HashLiteral, {sigil: "%", symbol: h}, [2, 3, 4, 5], ~, Hash], # 6
  [MemStart], # 7
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 8
  [Exists, ~, [6, 8, 7], ~, Boolean], # 9
  [Coerce, {from_repr: Boolean, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Exists, ~, [6, 2, 7], ~, Boolean], # 12
  [Coerce, {from_repr: Boolean, to_repr: Str}, [12], ~, Str], # 13
  [Print, ~, [13, 11], 0, Scalar], # 14
  [Print, ~, [10, 11], 14, Scalar], # 15
  [Delete, ~, [6, 2, 7], 15, Scalar], # 16
  [Call, {dispatch_kind: builtin, name: keys, param_names: []}, [6, 16], ~, Int], # 17
  [Coerce, {from_repr: Int, to_repr: Str}, [17], ~, Str], # 18
  [Coerce, {from_repr: Scalar, to_repr: Str}, [16], ~, Str], # 19
  [Print, ~, [19, 11], 16, Scalar], # 20
  [Print, ~, [18, 11], 20, Scalar], # 21
  [Return, ~, [1], 21]]} # 22
```

## A hash slice, where `delete` becomes a real op

`@h{...}` is a hash slice. `delete $h{a}` emits NO delete op, but
deleting a SLICE is different: the optimiser declines to build a
multideref for it, so `delete vK/SLICE` appears as a real op. That is
why the tier claims `delete` for the slice and not for the element, and
why `exists` is not claimed at all -- it has no op in any spelling.

```perl
my %h = (a => 1, b => 2, c => 3);
delete @h{"a", "b"};
print scalar(keys %h), "\n";
print( (@h{"c"}), "\n");
```

```behavior
parses: yes
```

```output
1
3
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [HashLiteral, {sigil: "%", symbol: h}, [3, 4, 5, 6, 2, 7], ~, Hash], # 8
  [Slice, ~, [2, 8], ~, List], # 9
  [Coerce, {from_repr: List, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [MemStart], # 12
  [Delete, ~, [8, 3, 12], 0, Scalar], # 13
  [Delete, ~, [8, 5, 13], 13, Scalar], # 14
  [Call, {dispatch_kind: builtin, name: keys, param_names: []}, [8, 14], ~, Int], # 15
  [Coerce, {from_repr: Int, to_repr: Str}, [15], ~, Str], # 16
  [Print, ~, [16, 11], 14, Scalar], # 17
  [Print, ~, [10, 11], 17, Scalar], # 18
  [Return, ~, [1], 18]]} # 19
```
