# Arithmetic, precedence and associativity

The seven arithmetic operators, and the two properties of the grammar
that leave NO OP BEHIND -- precedence and associativity.

**Tier 04 operators.** Introduces `add`, `subtract`, `multiply`,
`divide`, `modulo`, `pow`, `negate`, `concat`, `repeat`. Depends on
03_context.

Every case gives its operators a runtime operand. With constants the
optimiser folds the expression and there is no operator left in the op
stream to claim.

THE PRECEDENCE CASES ARE WHY THIS TIER PINS OUTPUT. `$a + $b * $c` and
`($a + $b) * $c` emit the same four ops in the same order; so do the two
associativity groupings. Nothing in the op stream separates them, and
nothing in a token stream does either. The VALUE is the only witness,
which is what makes a wrong pin worse here than anywhere else in the
corpus -- elsewhere a bad pin leaves the op claims standing, here it
leaves the tier measuring nothing.

## The seven arithmetic operators

Each with a runtime operand: add, subtract, multiply, divide, modulo,
pow and negate, in one statement so a parser that mis-groups any of them
prints a different number.

```perl
my $a = $ARGV[0] // 12;
my $b = $ARGV[1] // 5;
my $sum = $a + $b;
my $diff = $a - $b;
my $prod = $a * $b;
my $quot = $a / $b;
my $rem = $a % $b;
my $powr = $a ** $b;
my $neg = -$a;
print "$sum $diff $prod $quot $rem $powr $neg\n";
```

```behavior
parses: yes
```

```output
17 7 60 2.4 2 248832 -12
```

```tokens
one operator whose text is "%"
one operator whose text is "**"
```

```ir
main::__PROGRAM__: {start: 0, returns: [44], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, ~, [2, 3, 4], ~, Scalar], # 5
  [Constant, {const_type: integer, value: "12"}, ~, ~, Int], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Num}, [7], ~, Num], # 8
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 9
  [Subscript, ~, [2, 9, 4], ~, Scalar], # 10
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 11
  [DefinedOr, ~, [10, 11], ~, Scalar], # 12
  [Coerce, {from_repr: Scalar, to_repr: Num}, [12], ~, Num], # 13
  [Add, ~, [8, 13], ~, Num], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Subtract, ~, [8, 13], ~, Num], # 18
  [Coerce, {from_repr: Unknown, to_repr: Str}, [18], ~, Str], # 19
  [Concat, ~, [17, 19], ~, Str], # 20
  [Concat, ~, [20, 16], ~, Str], # 21
  [Multiply, ~, [8, 13], ~, Num], # 22
  [Coerce, {from_repr: Unknown, to_repr: Str}, [22], ~, Str], # 23
  [Concat, ~, [21, 23], ~, Str], # 24
  [Concat, ~, [24, 16], ~, Str], # 25
  [Divide, ~, [8, 13], ~, Num], # 26
  [Coerce, {from_repr: Num, to_repr: Str}, [26], ~, Str], # 27
  [Concat, ~, [25, 27], ~, Str], # 28
  [Concat, ~, [28, 16], ~, Str], # 29
  [Modulo, ~, [8, 13], ~, Int], # 30
  [Coerce, {from_repr: Int, to_repr: Str}, [30], ~, Str], # 31
  [Concat, ~, [29, 31], ~, Str], # 32
  [Concat, ~, [32, 16], ~, Str], # 33
  [Power, ~, [8, 13], ~, Num], # 34
  [Coerce, {from_repr: Num, to_repr: Str}, [34], ~, Str], # 35
  [Concat, ~, [33, 35], ~, Str], # 36
  [Concat, ~, [36, 16], ~, Str], # 37
  [Negate, ~, [8], ~, Num], # 38
  [Coerce, {from_repr: Unknown, to_repr: Str}, [38], ~, Str], # 39
  [Concat, ~, [37, 39], ~, Str], # 40
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 41
  [Concat, ~, [40, 41], ~, Str], # 42
  [Print, ~, [42], 0, Scalar], # 43
  [Return, ~, [1], 43]]} # 44
```

## Concatenation and repetition

`.` compiles to `concat` only when its result is a LIST element -- here,
a direct `print` argument. `x` compiles to `repeat` either way.

```perl
my $a = $ARGV[0] // "ab";
my $b = $ARGV[1] // "cd";
print "joined: ", $a . $b, "\n";
print "repeat: ", $a x 3, "\n";
```

```behavior
parses: yes
```

```output
joined: abcd
repeat: ababab
```

```tokens
one word-shaped operator whose text is "x"
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "repeat: "}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, ~, [3, 4, 5], ~, Scalar], # 6
  [Constant, {const_type: string, value: ab}, ~, ~, Str], # 7
  [DefinedOr, ~, [6, 7], ~, Scalar], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 10
  [Repeat, ~, [9, 10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: "joined: "}, ~, ~, Str], # 13
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 14
  [Subscript, ~, [3, 14, 5], ~, Scalar], # 15
  [Constant, {const_type: string, value: cd}, ~, ~, Str], # 16
  [DefinedOr, ~, [15, 16], ~, Scalar], # 17
  [Coerce, {from_repr: Scalar, to_repr: Str}, [17], ~, Str], # 18
  [Concat, ~, [9, 18], ~, Str], # 19
  [Print, ~, [13, 19, 12], 0, Scalar], # 20
  [Print, ~, [2, 11, 12], 20, Scalar], # 21
  [Return, ~, [1], 21]]} # 22
```

## `*` binds tighter than `+`

The only evidence is behavioural. Both groupings emit the same four ops
in the same order, so the two printed numbers are the whole claim.

```perl
my $a = $ARGV[0] // 2;
my $b = $ARGV[1] // 3;
my $c = $ARGV[2] // 4;
my $default = $a + $b * $c;
my $grouped = ($a + $b) * $c;
print "$default $grouped\n";
```

```behavior
parses: yes
```

```output
14 20
```

```tokens
one operator whose text is "("
```

```ir
main::__PROGRAM__: {start: 0, returns: [30], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, ~, [2, 3, 4], ~, Scalar], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Num}, [7], ~, Num], # 8
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 9
  [Subscript, ~, [2, 9, 4], ~, Scalar], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [DefinedOr, ~, [10, 11], ~, Scalar], # 12
  [Coerce, {from_repr: Scalar, to_repr: Num}, [12], ~, Num], # 13
  [Subscript, ~, [2, 6, 4], ~, Scalar], # 14
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 15
  [DefinedOr, ~, [14, 15], ~, Scalar], # 16
  [Coerce, {from_repr: Scalar, to_repr: Num}, [16], ~, Num], # 17
  [Multiply, ~, [13, 17], ~, Num], # 18
  [Add, ~, [8, 18], ~, Num], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 20
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 21
  [Concat, ~, [20, 21], ~, Str], # 22
  [Add, ~, [8, 13], ~, Num], # 23
  [Multiply, ~, [23, 17], ~, Num], # 24
  [Coerce, {from_repr: Unknown, to_repr: Str}, [24], ~, Str], # 25
  [Concat, ~, [22, 25], ~, Str], # 26
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 27
  [Concat, ~, [26, 27], ~, Str], # 28
  [Print, ~, [28], 0, Scalar], # 29
  [Return, ~, [1], 29]]} # 30
```

## `**` is right associative, `-` is left

As with precedence the op stream shows neither: two `pow` ops and two
`subtract` ops in source order, either way. `2 ** 3 ** 2` is 512 right
associatively and 64 left. `2 - 3 - 2` is -3 left associatively and 1
right, so the third number separates those too.

```perl
my $a = $ARGV[0] // 2;
my $b = $ARGV[1] // 3;
my $c = $ARGV[2] // 2;
my $right = $a ** $b ** $c;
my $left = ($a ** $b) ** $c;
my $minus = $a - $b - $c;
print "$right $left $minus\n";
```

```behavior
parses: yes
```

```output
512 64 -3
```

```tokens
no operator whose text is "*"
```

```ir
main::__PROGRAM__: {start: 0, returns: [34], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, ~, [2, 3, 4], ~, Scalar], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Num}, [7], ~, Num], # 8
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 9
  [Subscript, ~, [2, 9, 4], ~, Scalar], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [DefinedOr, ~, [10, 11], ~, Scalar], # 12
  [Coerce, {from_repr: Scalar, to_repr: Num}, [12], ~, Num], # 13
  [Subscript, ~, [2, 6, 4], ~, Scalar], # 14
  [DefinedOr, ~, [14, 6], ~, Scalar], # 15
  [Coerce, {from_repr: Scalar, to_repr: Num}, [15], ~, Num], # 16
  [Power, ~, [13, 16], ~, Num], # 17
  [Power, ~, [8, 17], ~, Num], # 18
  [Coerce, {from_repr: Num, to_repr: Str}, [18], ~, Str], # 19
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [Power, ~, [8, 13], ~, Num], # 22
  [Power, ~, [22, 16], ~, Num], # 23
  [Coerce, {from_repr: Num, to_repr: Str}, [23], ~, Str], # 24
  [Concat, ~, [21, 24], ~, Str], # 25
  [Concat, ~, [25, 20], ~, Str], # 26
  [Subtract, ~, [8, 13], ~, Num], # 27
  [Subtract, ~, [27, 16], ~, Num], # 28
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 29
  [Concat, ~, [26, 29], ~, Str], # 30
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 31
  [Concat, ~, [30, 31], ~, Str], # 32
  [Print, ~, [32], 0, Scalar], # 33
  [Return, ~, [1], 33]]} # 34
```
