# Three operators spelled `..`

`..` is not one operator in three contexts; it is three operators
wearing one spelling, and CONTEXT chooses. In list context it builds a
list -- by arithmetic over numbers, by perl's magic increment over
strings -- and in scalar context it is a stateful flip-flop that
remembers whether it is on.

**Tier 03 context.** Introduces `range`, `flip` and `flop`. Depends on
02_variables.

Before these cases the corpus claimed none of the three. The only `..`
anywhere was `for my $i (1 .. 2)` in tier 07's adjacency file, which is
loop scaffolding rather than a claim.

ONE `..` EMITS ALL THREE OPS, which defeats the obvious discriminator:
`range`, `flip` and `flop` all appear for a plain list range, because
the optimiser builds the flip-flop machinery even where the context
means it can never be used. So the op set does NOT separate the three
readings and the weight falls on OUTPUT, which separates them cleanly.

Every endpoint below is a runtime value for a PLACEMENT reason, not a
parsing one. Measured, `my @r = (1 .. 3)` emits no range, flip or flop
op while `my @r = (1 .. scalar(@a))` emits all three; the same holds for
string endpoints. Constant folding is an OPTIMISER effect reaching only
the op stream -- `(1 .. 3)` lexes as `Operator("..")` and parses to a
range either way -- but a folded range emits nothing for the lint to
check against this tier's INTRODUCES block. `scalar(@a)` serves rather
than tier 04's `$ENV{X} // <default>` because `dor` is out of this
tier's op budget, and because a scalar-context array is this tier's own
subject.

## The numeric list range

`..` in list context builds the list between its endpoints. The
endpoint is `scalar(@a)` so that the tier's `range` declaration has
something to check.

The negative fact is the lexical half: `..` must lex as ONE operator.
A lexer that read it as two `.` concatenation operators has a different
program, and the source contains a `.` only inside the `..`, which is
what makes the negative reachable rather than vacuous.

```perl
my @a = (1, 2, 3);
my @r = (1 .. scalar(@a));
print "@r\n";
```

```behavior
parses: yes
```

```output
1 2 3
```

```tokens
one operator whose text is ".."
no operator whose text is "."
```

```ir
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [2], ~, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [ArrayLiteral, {sigil: "@", symbol: a}, [5, 6, 7], ~, Array], # 8
  [Count, ~, [8, 2], ~, Int], # 9
  [Range, ~, [5, 9], ~, List], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Print, ~, [13], 0, Scalar], # 14
  [Return, ~, [1], 14], # 15
  [ArrayLiteral, {sigil: "@", symbol: r}, [10], ~, Array]]} # 16
```

## The string range counts by magic increment

`"az" .. "bb"` is three elements and none of them is a number. It looks
like the numeric range and is a separate claim, because the SUCCESSOR
function is different: a numeric range adds one, a string range applies
the magic increment that also drives `$s++` on a string.

`az` to `ba` is the carry -- the last character wraps from `z` to `a`
and the one before it advances. A parser that read this as an arithmetic
range over numified endpoints would get `0 .. 0` and print a single
zero, since `"az"` numifies to 0.

The COUNT is the second half of the claim. `scalar(@r)` is 3, this
tier's own scalar-context idiom applied to the result -- a range in list
context producing a list whose length is then taken in scalar context,
which is the tier's subject twice over.

```perl
my @seed = ("az");
my @r = ($seed[0] .. "bb");
print "@r ", scalar(@r), "\n";
```

```behavior
parses: yes
```

```output
az ba bb 3
```

```tokens
one operator whose text is ".."
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [2], ~, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: az}, ~, ~, Str], # 5
  [ArrayLiteral, {sigil: "@", symbol: seed}, [5], ~, Array], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, ~, [6, 7, 2], ~, Str], # 8
  [Coerce, {from_repr: Str, to_repr: Int}, [8], ~, Int], # 9
  [Constant, {const_type: string, value: bb}, ~, ~, Str], # 10
  [Coerce, {from_repr: Str, to_repr: Int}, [10], ~, Int], # 11
  [Range, ~, [9, 11], ~, List], # 12
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 12], ~, Str], # 13
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [ArrayLiteral, {sigil: "@", symbol: r}, [12], ~, Array], # 16
  [Count, ~, [16, 2], ~, Int], # 17
  [Coerce, {from_repr: Int, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Print, ~, [15, 18, 19], 0, Scalar], # 20
  [Return, ~, [1], 20]]} # 21
```

## `..` in scalar context is stateful

The third reading, and the one that makes the operator worth three
cases. The other two build lists; this one builds nothing and carries
state between evaluations.

INDICES 2 AND 3 ARE THE CLAIM. At both of them `$on[$_]` is 0 and
`$off[$_]` is 0 -- both operands false -- and the flip-flop selects them
anyway, because it turned on at index 1 and does not turn off until
index 4. No truthiness test can produce that: a parser that read `..`
here as a list range, or as a boolean `or`, or as anything stateless,
selects only indices 1 and 4.

That is why the operands are ARRAY ELEMENTS rather than the `$_ .. $_` a
first draft used. Measured, `grep { $_ .. $_ }` over `(0,1,0,0,1,0)`
prints `1 1` -- and so does `grep { $_ }` over the same list. The
stateful reading and plain truthiness agree, so the case would have
passed against a parser that had never heard of a flip-flop. Two
separate operand arrays are what make the state observable.

The `grep` form is deliberate: the loop spelling of the same claim needs
`enteriter` and `leaveloop`, which are tiers 05 and 06, while
`grepstart` and `grepwhile` are this tier's own.

```perl
my @on = (0, 1, 0, 0, 0, 0);
my @off = (0, 0, 0, 0, 1, 0);
my @i = (0, 1, 2, 3, 4, 5);
my @o = grep { $on[$_] .. $off[$_] } @i;
print "@o\n";
```

```behavior
parses: yes
```

```output
1 2 3 4
```

```tokens
one operator whose text is ".."
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [2], ~, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [ArrayLiteral, ~, ~, ~, Array], # 5
  [Loop, {bound: entry}, [0], 0], # 6
  [Phi, {region: 6}, [5, 48], ~, Array], # 7
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Proj, {index: 1}, [6]], # 11
  [Region, {head: 6}, [11]], # 12
  [Print, ~, [10], 12, Scalar], # 13
  [Return, ~, [1], 13], # 14
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 15
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 16
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 17
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 18
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 19
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 20
  [ArrayLiteral, {sigil: "@", symbol: i}, [15, 16, 17, 18, 19, 20], ~, Array], # 21
  [Count, ~, [21, 2], ~, Int], # 22
  [Phi, {region: 6}, [15, 47], ~, Int], # 23
  [NumGt, ~, [22, 23], 6, Boolean], # 24
  [Proj, {index: 0}, [6]], # 25
  [Phi, {region: 6}, [1, 37], ~, Scalar], # 26
  [ArrayLiteral, {sigil: "@", symbol: "off"}, [15, 15, 15, 15, 16, 15], ~, Array], # 27
  [Subscript, ~, [21, 23, 2], ~, Int], # 28
  [Subscript, ~, [27, 28, 2], ~, Int], # 29
  [Coerce, {from_repr: Scalar, to_repr: Num}, [26], ~, Num], # 30
  [Add, ~, [30, 16], ~, Num], # 31
  [TernaryExpr, ~, [29, 15, 31], ~, Num], # 32
  [ArrayLiteral, {sigil: "@", symbol: "on"}, [15, 16, 15, 15, 15, 15], ~, Array], # 33
  [Subscript, ~, [33, 28, 2], ~, Int], # 34
  [TernaryExpr, ~, [29, 15, 16], ~, Int], # 35
  [TernaryExpr, ~, [34, 35, 15], ~, Int], # 36
  [TernaryExpr, ~, [26, 32, 36], ~, Num], # 37
  [Coerce, {from_repr: Int, to_repr: Str}, [31], ~, Str], # 38
  [Constant, {const_type: string, value: E0}, ~, ~, Str], # 39
  [Concat, ~, [38, 39], ~, Str], # 40
  [TernaryExpr, ~, [29, 40, 31], ~, Str], # 41
  [Constant, {const_type: string, value: "1E0"}, ~, ~, Str], # 42
  [TernaryExpr, ~, [29, 42, 16], ~, Str], # 43
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 44
  [TernaryExpr, ~, [34, 43, 44], ~, Str], # 45
  [TernaryExpr, ~, [26, 41, 45], ~, Str], # 46
  [Add, ~, [23, 16], ~, Int], # 47
  [ListAppend, {collector: grep}, [7, 28, 46], ~, Array]]} # 48
```
