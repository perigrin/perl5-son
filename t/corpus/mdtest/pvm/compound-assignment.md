# Compound assignment

perlop's level 20: thirteen operators the corpus wrote none of until
issue `01a0cc04-32c9`.

**Tier 04 operators.** Introduces `andassign`, `dorassign`, `orassign`.
The arithmetic, string and bitwise forms emit the ops their binary
counterparts do, which is why those cases could not be written before
the binary ones existed. Depends on 03_context.

EACH IS ONE OPERATOR TOKEN, not two. `$x += 2` is `Operator("+=")` and
not `+` followed by `=`, which is the claim the token facts carry and
the reason this is a topic: thirteen spellings of one lexical rule, and
twelve of them punctuation. The thirteenth is `x=`, which the lexer had
to be taught separately for exactly that reason -- see its case below.

## The arithmetic forms

`+=` `-=` `*=` `/=` and the rest, each one token.

```perl
my $a = $ENV{X} // 5;
my $b = $ENV{X} // 5;
my $c = $ENV{X} // 5;
my $d = $ENV{Y} // 6;
$a += 2;
$b -= 2;
$c *= 2;
$d /= 2;
print "$a $b $c $d\n";
```

```behavior
parses: yes
```

```output
7 3 10 3
```

```tokens
one operator whose text is "+="
one operator whose text is "-="
one operator whose text is "*="
one operator whose text is "/="
```

```ir
main::__PROGRAM__: {start: 0, returns: [30], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Coerce, {from_repr: Str, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Add, ~, [5, 6], ~, Num], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Subtract, ~, [5, 6], ~, Num], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [10, 12], ~, Str], # 13
  [Concat, ~, [13, 9], ~, Str], # 14
  [Multiply, ~, [5, 6], ~, Num], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [14, 16], ~, Str], # 17
  [Concat, ~, [17, 9], ~, Str], # 18
  [EnvRead, {key: "Y"}, ~, ~, Str], # 19
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 20
  [DefinedOr, ~, [19, 20], ~, Str], # 21
  [Coerce, {from_repr: Str, to_repr: Num}, [21], ~, Num], # 22
  [Coerce, {from_repr: Int, to_repr: Num}, [6], ~, Num], # 23
  [Divide, ~, [22, 23], ~, Num], # 24
  [Coerce, {from_repr: Num, to_repr: Str}, [24], ~, Str], # 25
  [Concat, ~, [18, 25], ~, Str], # 26
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 27
  [Concat, ~, [26, 27], ~, Str], # 28
  [Print, ~, [28], 0, Scalar], # 29
  [Return, ~, [1], 29]]} # 30
```

## `.=` emits `multiconcat`, not `concat`

Which a reader would not predict from `+=` giving `add`. The op is
chosen by what the optimiser can fuse, not by the operator's spelling.

```perl
my $s = $ENV{X} // "a";
$s .= "b";
print "$s\n";
```

```behavior
parses: yes
```

```output
ab
```

```tokens
one operator whose text is ".="
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [Print, ~, [8], 0, Scalar], # 9
  [Return, ~, [1], 9]]} # 10
```

## `x=` is word-shaped

The thirteenth compound assignment and the only one whose operator is a
WORD. The other twelve are punctuation, so an operator scanner that forms
them from punctuation runs never reaches this one: our lexer emitted
`Word(x) Operator(=)` and the statement had a Word where an operator
belongs, until `takeRepeatAssign` (`internal/lexer/scan.go`) extended a
word-position `x` into the token.

The expect state is what keeps it off the fat comma. `(x=>1)` is a
bareword and a `=>` because `x` is in TERM position there, while `$t x= 2`
is operator position -- perl's own rule, and measured: `my @a = ($t x=> 2)`
is a syntax error near `$t x`, perl having already formed `x=`.

This case bisects against `.=` and the binary `x`, both above.

```perl
my $t = $ENV{X} // "ab";
$t x= 2;
print "$t\n";
```

```behavior
parses: yes
```

```output
abab
```

```tokens
one word-shaped operator whose text is "x="
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: ab}, ~, ~, Str], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Repeat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [Print, ~, [8], 0, Scalar], # 9
  [Return, ~, [1], 9]]} # 10
```

## `//=`, `||=` and `&&=` short-circuit

The only compound assignments whose behaviour output can see: the
right-hand side is not evaluated when the left already decides the
answer. Four pinned values separate the four readings.

```perl
my $p = $ENV{X} // 0;
my $q = $ENV{X} // 0;
my $r = $ENV{Y} // 1;
my $s = $ENV{X} // 0;
$p //= 99;
$q ||= 99;
$r &&= 99;
$s &&= 99;
print "$p $q $r $s\n";
```

```behavior
parses: yes
```

```output
0 99 99 0
```

```tokens
one operator whose text is "//="
one operator whose text is "||="
```

```ir
main::__PROGRAM__: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Constant, {const_type: integer, value: "99"}, ~, ~, Int], # 5
  [DefinedOr, ~, [4, 5], ~, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Or, ~, [4, 5], ~, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Concat, ~, [9, 11], ~, Str], # 12
  [Concat, ~, [12, 8], ~, Str], # 13
  [EnvRead, {key: "Y"}, ~, ~, Str], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [DefinedOr, ~, [14, 15], ~, Str], # 16
  [And, ~, [16, 5], ~, Str], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Concat, ~, [13, 18], ~, Str], # 19
  [Concat, ~, [19, 8], ~, Str], # 20
  [And, ~, [4, 5], ~, Str], # 21
  [Coerce, {from_repr: Unknown, to_repr: Str}, [21], ~, Str], # 22
  [Concat, ~, [20, 22], ~, Str], # 23
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 24
  [Concat, ~, [23, 24], ~, Str], # 25
  [Print, ~, [25], 0, Scalar], # 26
  [Return, ~, [1], 26]]} # 27
```

## The bitwise and shift forms

`&=` `|=` `^=` `<<=` `>>=`, reusing the ops the bitwise topic
introduces.

```perl
my $a = $ENV{X} // 12;
my $b = $ENV{X} // 12;
my $c = $ENV{X} // 12;
my $d = $ENV{Y} // 1;
my $e = $ENV{Z} // 16;
$a |= 3;
$b &= 10;
$c ^= 3;
$d <<= 3;
$e >>= 2;
print "$a $b $c $d $e\n";
```

```behavior
parses: yes
```

```output
15 8 15 8 4
```

```tokens
one operator whose text is "|="
one operator whose text is "&="
one operator whose text is "^="
one operator whose text is "<<="
one operator whose text is ">>="
```

```ir
main::__PROGRAM__: {start: 0, returns: [39], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "12"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Coerce, {from_repr: Str, to_repr: Int}, [4], ~, Int], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [BitOr, ~, [5, 6], ~, Int], # 7
  [Coerce, {from_repr: Int, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 11
  [BitAnd, ~, [5, 11], ~, Int], # 12
  [Coerce, {from_repr: Int, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [10, 13], ~, Str], # 14
  [Concat, ~, [14, 9], ~, Str], # 15
  [BitXor, ~, [5, 6], ~, Int], # 16
  [Coerce, {from_repr: Int, to_repr: Str}, [16], ~, Str], # 17
  [Concat, ~, [15, 17], ~, Str], # 18
  [Concat, ~, [18, 9], ~, Str], # 19
  [EnvRead, {key: "Y"}, ~, ~, Str], # 20
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 21
  [DefinedOr, ~, [20, 21], ~, Str], # 22
  [Coerce, {from_repr: Str, to_repr: Int}, [22], ~, Int], # 23
  [LeftShift, ~, [23, 6], ~, Int], # 24
  [Coerce, {from_repr: Int, to_repr: Str}, [24], ~, Str], # 25
  [Concat, ~, [19, 25], ~, Str], # 26
  [Concat, ~, [26, 9], ~, Str], # 27
  [EnvRead, {key: Z}, ~, ~, Str], # 28
  [Constant, {const_type: integer, value: "16"}, ~, ~, Int], # 29
  [DefinedOr, ~, [28, 29], ~, Str], # 30
  [Coerce, {from_repr: Str, to_repr: Int}, [30], ~, Int], # 31
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 32
  [RightShift, ~, [31, 32], ~, Int], # 33
  [Coerce, {from_repr: Int, to_repr: Str}, [33], ~, Str], # 34
  [Concat, ~, [27, 34], ~, Str], # 35
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 36
  [Concat, ~, [35, 36], ~, Str], # 37
  [Print, ~, [37], 0, Scalar], # 38
  [Return, ~, [1], 38]]} # 39
```
