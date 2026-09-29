# Named operators and argument extent

Operators spelled as words, and the question they all raise: HOW FAR
DOES THE ARGUMENT RUN.

**Tier 04 operators.** Introduces `defined`, `undef`, `chr`, `ord`,
`index`, `sprintf`, `substr`. Depends on 03_context.

Three of these fold away when their operands are constant -- `chr(74)`
arrives as `const[PV "J"]` -- so each case spells its construct with a
runtime operand, the rule the rest of this tier lives under.

WHAT MAKES THEM A TOPIC rather than seven unrelated builtins is that the
op name answers almost nothing about them. `substr` is one op for three
arities and for the lvalue form; `sprintf` is one op whose argument
count is decided by its format's CONTENTS; `undef` is one word for two
operators. In every case the extent or the arity is the claim, and the
op stream cannot carry it.

## A named unary binds looser than arithmetic

`defined $x + 1` is `defined($x + 1)`, not `(defined $x) + 1`, and the
two readings print different numbers. This is the argument-extent
question in its smallest form.

```perl
my $x = $ARGV[0] // 2;
my $loose = defined $x + 1;
my $tight = (defined $x) + 1;
print "$loose $tight\n";
```

```behavior
parses: yes
```

```output
1 2
```

```tokens
one operator whose text is "("
no operator whose text is ")"
```

```ir
main::__PROGRAM__: {start: 0, returns: [23], nodes: [
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
  [Add, ~, [8, 9], ~, Num], # 10
  [Defined, ~, [10], ~, Boolean], # 11
  [Coerce, {from_repr: Boolean, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [Defined, ~, [7], ~, Boolean], # 15
  [Coerce, {from_repr: Boolean, to_repr: Num}, [15], ~, Num], # 16
  [Add, ~, [16, 9], ~, Num], # 17
  [Coerce, {from_repr: Num, to_repr: Str}, [17], ~, Str], # 18
  [Concat, ~, [14, 18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [Print, ~, [21], 0, Scalar], # 22
  [Return, ~, [1], 22]]} # 23
```

## `undef` is two operators wearing one word

A UNARY one that clears what it is given, and a NILADIC one that is
simply the undefined value. `undef @a` empties the array; `@a = undef`
fills it with one element. One word, opposite effects on the same
variable.

```perl
my @a = ($ENV{X} // 1, 2, 3);
my @b = ($ENV{X} // 1, 2, 3);
undef @a;
@b = undef;
print scalar @a, scalar @b, "\n";
```

```behavior
parses: yes
```

```output
01
```

```tokens
one word whose text is "print"
no operator whose text is ")"
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Count, ~, [2, 3], ~, Int], # 4
  [Coerce, {from_repr: Int, to_repr: Str}, [4], ~, Str], # 5
  [ArrayLiteral, {sigil: "@", symbol: b}, [1], ~, Array], # 6
  [Count, ~, [6, 3], ~, Int], # 7
  [Coerce, {from_repr: Int, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [5, 8, 9], 0, Scalar], # 10
  [Return, ~, [1], 10]]} # 11
```

## `chr` and `ord`, folded and unfolded

Inverses over one character, and BOTH FOLD AWAY when their argument is a
literal. Each is written twice -- once on a runtime operand, once on a
constant -- so the optree holds one op where the source holds two. That
is the fold made visible rather than worked around.

```perl
my $n = $ENV{X} // 74;
my $live = chr($n);
my $folded = chr(74);
my $back = ord($live);
print "[$live][$folded][$back]\n";
```

```behavior
parses: yes
```

```output
[J][J][74]
```

```tokens
one word whose text is "ord"
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [EnvRead, {key: X}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "74"}, ~, ~, Int], # 4
  [DefinedOr, ~, [3, 4], ~, Str], # 5
  [Call, {dispatch_kind: builtin, name: chr, param_names: []}, [5], ~, Str], # 6
  [Concat, ~, [2, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "]["}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Constant, {const_type: string, value: J}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Concat, ~, [11, 8], ~, Str], # 12
  [Call, {dispatch_kind: builtin, name: ord, param_names: []}, [6], ~, Int], # 13
  [Coerce, {from_repr: Int, to_repr: Str}, [13], ~, Str], # 14
  [Concat, ~, [12, 14], ~, Str], # 15
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Print, ~, [17], 0, Scalar], # 18
  [Return, ~, [1], 18]]} # 19
```

## `index` reports failure as -1, not undef

Which makes its result a NUMBER that is always defined -- so `//` cannot
test it, and a truth test is wrong at position zero. The three pinned
values are a hit, a hit at a later offset, and the sentinel.

```perl
my $s = $ENV{X} // "hello world";
my $first = index($s, "o");
my $next = index($s, "o", $first + 1);
my $none = index($s, "z");
print "[$first][$next][$none]\n";
```

```behavior
parses: yes
```

```output
[4][7][-1]
```

```tokens
one operator whose text is "+"
```

```ir
main::__PROGRAM__: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [EnvRead, {key: X}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: "hello world"}, ~, ~, Str], # 4
  [DefinedOr, ~, [3, 4], ~, Str], # 5
  [Constant, {const_type: string, value: o}, ~, ~, Str], # 6
  [Call, {dispatch_kind: builtin, name: index, param_names: []}, [5, 6], ~, Int], # 7
  [Coerce, {from_repr: Int, to_repr: Str}, [7], ~, Str], # 8
  [Concat, ~, [2, 8], ~, Str], # 9
  [Constant, {const_type: string, value: "]["}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 12
  [Add, ~, [7, 12], ~, Int], # 13
  [Call, {dispatch_kind: builtin, name: index, param_names: []}, [5, 6, 13], ~, Int], # 14
  [Coerce, {from_repr: Int, to_repr: Str}, [14], ~, Str], # 15
  [Concat, ~, [11, 15], ~, Str], # 16
  [Concat, ~, [16, 10], ~, Str], # 17
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 18
  [Call, {dispatch_kind: builtin, name: index, param_names: []}, [5, 18], ~, Int], # 19
  [Coerce, {from_repr: Int, to_repr: Str}, [19], ~, Str], # 20
  [Concat, ~, [17, 20], ~, Str], # 21
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 22
  [Concat, ~, [21, 22], ~, Str], # 23
  [Print, ~, [23], 0, Scalar], # 24
  [Return, ~, [1], 24]]} # 25
```

## `%*d` makes the format consume an argument

`sprintf`'s first argument is a FORMAT, and `%*d` makes it take an extra
argument to supply its own width -- so how many arguments a call takes
is decided by the format's contents and not by its syntax. No parser can
know the arity without reading the string.

```perl
my $n = $ENV{X} // 5;
my $zero = sprintf("%03d", $n);
my $star = sprintf("%*d", $n, $n);
my $left = sprintf("%-*d", $n, $n);
print "[$zero][$star][$left][", $n % 3, "]\n";
```

```behavior
parses: yes
```

```output
[005][    5][5    ][2]
```

```tokens
one operator whose text is "%"
no word whose text is "printf"
```

```ir
main::__PROGRAM__: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "%03d"}, ~, ~, Str], # 3
  [EnvRead, {key: X}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 5
  [DefinedOr, ~, [4, 5], ~, Str], # 6
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [3, 6], ~, Str], # 7
  [Concat, ~, [2, 7], ~, Str], # 8
  [Constant, {const_type: string, value: "]["}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "%*d"}, ~, ~, Str], # 11
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [11, 6, 6], ~, Str], # 12
  [Concat, ~, [10, 12], ~, Str], # 13
  [Concat, ~, [13, 9], ~, Str], # 14
  [Constant, {const_type: string, value: "%-*d"}, ~, ~, Str], # 15
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [15, 6, 6], ~, Str], # 16
  [Concat, ~, [14, 16], ~, Str], # 17
  [Concat, ~, [17, 9], ~, Str], # 18
  [Coerce, {from_repr: Str, to_repr: Num}, [6], ~, Num], # 19
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 20
  [Modulo, ~, [19, 20], ~, Int], # 21
  [Coerce, {from_repr: Int, to_repr: Str}, [21], ~, Str], # 22
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 23
  [Print, ~, [18, 22, 23], 0, Scalar], # 24
  [Return, ~, [1], 24]]} # 25
```

## `substr` takes two, three or four arguments

A negative offset counts from the end, and a missing length means "to
the end" -- three meanings for one word, none visible in the op.

```perl
my $s = $ENV{X} // "hello world";
my $tail = substr($s, 6);
my $mid = substr($s, 3, 2);
my $neg = substr($s, -5, 3);
print "[$tail][$mid][$neg]\n";
```

```behavior
parses: yes
```

```output
[world][lo][wor]
```

```tokens
one operator whose text is "-"
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [EnvRead, {key: X}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: "hello world"}, ~, ~, Str], # 4
  [DefinedOr, ~, [3, 4], ~, Str], # 5
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [5, 6], ~, Str], # 7
  [Concat, ~, [2, 7], ~, Str], # 8
  [Constant, {const_type: string, value: "]["}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 12
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [5, 11, 12], ~, Str], # 13
  [Concat, ~, [10, 13], ~, Str], # 14
  [Concat, ~, [14, 9], ~, Str], # 15
  [Constant, {const_type: integer, value: "-5"}, ~, ~, Int], # 16
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [5, 16, 11], ~, Str], # 17
  [Concat, ~, [15, 17], ~, Str], # 18
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 19
  [Concat, ~, [18, 19], ~, Str], # 20
  [Print, ~, [20], 0, Scalar], # 21
  [Return, ~, [1], 21]]} # 22
```

## `substr` is an lvalue

`substr($s,0,1) = "J"` assigns INTO the string, and the four-argument
form does the same replacement while RETURNING the text it displaced.
Same op name, same result in the string, and only the return value tells
them apart.

```perl
my $a = $ENV{X} // "hello";
my $b = $ENV{X} // "hello";
substr($a, 0, 1) = "J";
my $old = substr($b, 0, 1, "J");
print "[$a][$b][$old]\n";
```

```behavior
parses: yes
```

```output
[Jello][Jello][h]
```

```tokens
one word whose text is "print"
```

```ir
main::__PROGRAM__: {start: 0, returns: [31], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: a}, [3], ~, Unknown], # 4
  [EnvRead, {key: X}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: hello}, ~, ~, Str], # 6
  [DefinedOr, ~, [5, 6], ~, Str], # 7
  [Assign, ~, [4, 7], 0, Str], # 8
  [PadAccess, {sigil: $, symbol: b}, [8], ~, Unknown], # 9
  [Assign, ~, [9, 7], 8, Str], # 10
  [PadAccess, {sigil: $, symbol: a}, [10], ~, Str], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 13
  [Constant, {const_type: string, value: J}, ~, ~, Str], # 14
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [11, 12, 13, 14], 10, Str], # 15
  [PadAccess, {sigil: $, symbol: b}, [15], ~, Str], # 16
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [16, 12, 13, 14], 15, Str], # 17
  [PadAccess, {sigil: $, symbol: a}, [17], ~, Str], # 18
  [Coerce, {from_repr: Unknown, to_repr: Str}, [18], ~, Str], # 19
  [Concat, ~, [2, 19], ~, Str], # 20
  [Constant, {const_type: string, value: "]["}, ~, ~, Str], # 21
  [Concat, ~, [20, 21], ~, Str], # 22
  [PadAccess, {sigil: $, symbol: b}, [17], ~, Str], # 23
  [Coerce, {from_repr: Unknown, to_repr: Str}, [23], ~, Str], # 24
  [Concat, ~, [22, 24], ~, Str], # 25
  [Concat, ~, [25, 21], ~, Str], # 26
  [Concat, ~, [26, 17], ~, Str], # 27
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 28
  [Concat, ~, [27, 28], ~, Str], # 29
  [Print, ~, [29], 17, Scalar], # 30
  [Return, ~, [1], 30], # 31
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [11, 12, 13], ~, Str]]} # 32
```
