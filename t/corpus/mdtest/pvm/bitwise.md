# Bitwise and shift

Three of perlop's precedence levels -- 9 (`<< >>`), 14 (`| ^`) and 15
(`&`) -- and the pragma that silently changes what two of them mean.

**Tier 04 operators.** Introduces `bit_and`, `bit_or`, `bit_xor`,
`left_shift`, `right_shift`, `complement`, `nbit_and`. Depends on
03_context.

Every case gives its operators a RUNTIME operand. With constants the
optimiser folds the whole expression and there is no operator left in
the op stream to claim -- measured, `print 12 & 10` compiles to a single
`const`. The `$ENV{X} //` idiom is how this tier keeps an operator
alive, and it is why a `dor` appears in every case below.

## The three binary operators

`&`, `|` and `^` over a runtime integer. One case rather than three
because they share a precedence band and a failure mode: a lexer that
reads any of them as the start of a longer operator (`&&`, `||`, `^.`)
gets a different program with no diagnostic.

```perl
my $a = $ENV{X} // 12;
print $a & 10, " ", $a | 3, " ", $a ^ 3, "\n";
```

```behavior
parses: yes
```

```output
8 15 15
```

```tokens
one operator whose text is "&"
one operator whose text is "|"
one operator whose text is "^"
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "12"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Coerce, {from_repr: Str, to_repr: Int}, [4], ~, Int], # 5
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 6
  [BitAnd, ~, [5, 6], ~, Int], # 7
  [Coerce, {from_repr: Int, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 10
  [BitOr, ~, [5, 10], ~, Int], # 11
  [Coerce, {from_repr: Int, to_repr: Str}, [11], ~, Str], # 12
  [BitXor, ~, [5, 10], ~, Int], # 13
  [Coerce, {from_repr: Int, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [8, 9, 12, 9, 14, 15], 0, Scalar], # 16
  [Return, ~, [1], 16]]} # 17
```

## Bitwise precedence: `&` binds tighter than `|`

perlop puts `&` at level 15 and `|` at level 14, so `$a | $b & $c` is
`$a | ($b & $c)`. The grouped form is written beside it because
PRECEDENCE LEAVES NO OP BEHIND -- both spellings emit the same two ops
in the same order, and only the value separates them.

```perl
my $a = $ENV{X} // 6;
my $b = $ENV{Y} // 3;
my $c = $ENV{Z} // 2;
print $a | $b & $c, " ", ($a | $b) & $c, "\n";
```

```behavior
parses: yes
```

```output
6 2
```

```tokens
one operator whose text is "("
```

```ir
main::__PROGRAM__: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Coerce, {from_repr: Str, to_repr: Int}, [4], ~, Int], # 5
  [EnvRead, {key: "Y"}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [DefinedOr, ~, [6, 7], ~, Str], # 8
  [Coerce, {from_repr: Str, to_repr: Int}, [8], ~, Int], # 9
  [EnvRead, {key: Z}, ~, ~, Str], # 10
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 11
  [DefinedOr, ~, [10, 11], ~, Str], # 12
  [Coerce, {from_repr: Str, to_repr: Int}, [12], ~, Int], # 13
  [BitAnd, ~, [9, 13], ~, Int], # 14
  [BitOr, ~, [5, 14], ~, Int], # 15
  [Coerce, {from_repr: Int, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 17
  [BitOr, ~, [5, 9], ~, Int], # 18
  [BitAnd, ~, [18, 13], ~, Int], # 19
  [Coerce, {from_repr: Int, to_repr: Str}, [19], ~, Str], # 20
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 21
  [Print, ~, [16, 17, 20, 21], 0, Scalar], # 22
  [Return, ~, [1], 22]]} # 23
```

## The shift operators

`<<` and `>>` at level 9. The `<<` is the interesting half: it is also
the heredoc opener, and the lexer decides between them by what follows.

```perl
my $a = $ENV{X} // 1;
my $b = $ENV{Y} // 16;
print $a << 3, " ", $b >> 2, "\n";
```

```behavior
parses: yes
```

```output
8 4
```

```tokens
one operator whose text is "<<"
one operator whose text is ">>"
no heredoc opener whose text is "<< 3"
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Coerce, {from_repr: Str, to_repr: Int}, [4], ~, Int], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [LeftShift, ~, [5, 6], ~, Int], # 7
  [Coerce, {from_repr: Int, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [EnvRead, {key: "Y"}, ~, ~, Str], # 10
  [Constant, {const_type: integer, value: "16"}, ~, ~, Int], # 11
  [DefinedOr, ~, [10, 11], ~, Str], # 12
  [Coerce, {from_repr: Str, to_repr: Int}, [12], ~, Int], # 13
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 14
  [RightShift, ~, [13, 14], ~, Int], # 15
  [Coerce, {from_repr: Int, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [8, 9, 16, 17], 0, Scalar], # 18
  [Return, ~, [1], 18]]} # 19
```

## Complement

`~` is unary and at level 4, far above the binary band. Masked with
`& 255` so the answer does not depend on integer width.

```perl
my $a = $ENV{X} // 12;
print ~$a & 255, "\n";
```

```behavior
parses: yes
```

```output
243
```

```tokens
one operator whose text is "~"
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "12"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Coerce, {from_repr: Str, to_repr: Int}, [4], ~, Int], # 5
  [Complement, ~, [5], ~, Int], # 6
  [Constant, {const_type: integer, value: "255"}, ~, ~, Int], # 7
  [BitAnd, ~, [6, 7], ~, Int], # 8
  [Coerce, {from_repr: Int, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [9, 10], 0, Scalar], # 11
  [Return, ~, [1], 11]]} # 12
```

## `&` on strings, ungated: the string bitwise operation

Without the `bitwise` feature, `&` is POLYMORPHIC. String operands get a
STRING bitwise operation: `'1' & '1'` is `'1'`, `'2' & '0'` is `'0'`, so
`"12" & "10"` is the string `"10"`.

This case and the next differ by ONE LINE and by the answer they print.
Neither means anything alone, which is why the old one-construct-per-file
format could not hold them together -- a file-scoped pragma cannot be
scoped to half a file.

```perl
my $s1 = $ENV{X} // "12";
my $s2 = $ENV{Y} // "10";
print $s1 & $s2, "\n";
```

```behavior
parses: yes
```

```output
10
```

```tokens
one operator whose text is "&"
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "12"}, ~, ~, Str], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Coerce, {from_repr: Str, to_repr: Int}, [4], ~, Int], # 5
  [EnvRead, {key: "Y"}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: "10"}, ~, ~, Str], # 7
  [DefinedOr, ~, [6, 7], ~, Str], # 8
  [Coerce, {from_repr: Str, to_repr: Int}, [8], ~, Int], # 9
  [BitAnd, ~, [5, 9], ~, Int], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [11, 12], 0, Scalar], # 13
  [Return, ~, [1], 13]]} # 14
```

## `&` on strings, gated: the numeric operation

The same three lines under `use v5.28`. Now `&` is numeric: `12 & 10` is
`8`.

THE HAZARD IS THAT NEITHER READING WARNS. `say` without its feature is a
method call and dies. `isa` without its feature is a filehandle print
and dies. `state` without its feature dies on an undefined invocant. All
three fail loudly enough to notice. This one SUCCEEDS with a different
answer, and every test that does not pin the pragma agrees with whatever
the parser chose.

The optree sees it too, which was not obvious: ungated emits `bit_and`
and gated emits `nbit_and` -- two ops, not one op with a flag. So the
dependency lint distinguishes the pair as well as the output does, but
only because both cases exist.

```perl
use v5.28;
my $s1 = $ENV{X} // "12";
my $s2 = $ENV{Y} // "10";
print $s1 & $s2, "\n";
```

```behavior
parses: yes
```

```output
8
```

```tokens
one word whose text is "use"
one operator whose text is "&"
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "12"}, ~, ~, Str], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Coerce, {from_repr: Str, to_repr: Int}, [4], ~, Int], # 5
  [EnvRead, {key: "Y"}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: "10"}, ~, ~, Str], # 7
  [DefinedOr, ~, [6, 7], ~, Str], # 8
  [Coerce, {from_repr: Str, to_repr: Int}, [8], ~, Int], # 9
  [BitAnd, {flavor: numeric}, [5, 9], ~, Int], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [11, 12], 0, Scalar], # 13
  [Return, ~, [1], 13]]} # 14
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.028"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
```
