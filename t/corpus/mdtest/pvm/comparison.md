# Comparison, logic and the nonassoc levels

The two comparison families, the logical operators, and the levels where
repetition is a SYNTAX ERROR rather than a grouping.

**Tier 04 operators.** Introduces `eq` `ne` `lt` `gt` `le` `ge` `ncmp`,
`seq` `sne` `slt` `sgt` `sle` `sge` `scmp`, `and` `or` `dor` `not`
`xor`, `cmpchain_and`, `cmpchain_dup`. Depends on 03_context.

THE TWO COMPARISON FAMILIES ARE THE SAME RELATION OVER THE SAME
OPERANDS, differing only in the context each imposes -- which is the
whole reason this tier sits after 03.

The last three cases are about a question no op stream can answer: which
levels ACCEPT repetition. perly.y declares eleven `%nonassoc` levels and
measurement says eight of them accept it anyway; `TestTierOperatorsNonassocMeasured`
runs all eleven against perl. What the corpus adds here is the two that
refuse, and the chaining answer that has no diagnostic either way.

## The numeric relations and `<=>`

Six relations and the three-way comparison, each imposing numeric
context on both operands.

```perl
my $a = $ARGV[0] // 3;
my $b = $ARGV[1] // 5;
print "eq [", ($a == $b), "]\n";
print "ne [", ($a != $b), "]\n";
print "lt [", ($a < $b), "]\n";
print "gt [", ($a > $b), "]\n";
print "le [", ($a <= $b), "]\n";
print "ge [", ($a >= $b), "]\n";
print "cmp [", ($a <=> $b), "]\n";
```

```behavior
parses: yes
```

```output
eq []
ne [1]
lt [1]
gt []
le [1]
ge []
cmp [-1]
```

```tokens
one operator whose text is "<=>"
```

```ir
main::__PROGRAM__: {start: 0, returns: [43], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "cmp ["}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, ~, [3, 4, 5], ~, Scalar], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [DefinedOr, ~, [6, 7], ~, Scalar], # 8
  [Coerce, {from_repr: Scalar, to_repr: Num}, [8], ~, Num], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Subscript, ~, [3, 10, 5], ~, Scalar], # 11
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 12
  [DefinedOr, ~, [11, 12], ~, Scalar], # 13
  [Coerce, {from_repr: Scalar, to_repr: Num}, [13], ~, Num], # 14
  [NumCmp, ~, [9, 14], ~, Int], # 15
  [Coerce, {from_repr: Int, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 17
  [Constant, {const_type: string, value: "ge ["}, ~, ~, Str], # 18
  [NumGe, ~, [9, 14], ~, Boolean], # 19
  [Coerce, {from_repr: Boolean, to_repr: Str}, [19], ~, Str], # 20
  [Constant, {const_type: string, value: "le ["}, ~, ~, Str], # 21
  [NumLe, ~, [9, 14], ~, Boolean], # 22
  [Coerce, {from_repr: Boolean, to_repr: Str}, [22], ~, Str], # 23
  [Constant, {const_type: string, value: "gt ["}, ~, ~, Str], # 24
  [NumGt, ~, [9, 14], ~, Boolean], # 25
  [Coerce, {from_repr: Boolean, to_repr: Str}, [25], ~, Str], # 26
  [Constant, {const_type: string, value: "lt ["}, ~, ~, Str], # 27
  [NumLt, ~, [9, 14], ~, Boolean], # 28
  [Coerce, {from_repr: Boolean, to_repr: Str}, [28], ~, Str], # 29
  [Constant, {const_type: string, value: "ne ["}, ~, ~, Str], # 30
  [NumNe, ~, [9, 14], ~, Boolean], # 31
  [Coerce, {from_repr: Boolean, to_repr: Str}, [31], ~, Str], # 32
  [Constant, {const_type: string, value: "eq ["}, ~, ~, Str], # 33
  [NumEq, ~, [9, 14], ~, Boolean], # 34
  [Coerce, {from_repr: Boolean, to_repr: Str}, [34], ~, Str], # 35
  [Print, ~, [33, 35, 17], 0, Scalar], # 36
  [Print, ~, [30, 32, 17], 36, Scalar], # 37
  [Print, ~, [27, 29, 17], 37, Scalar], # 38
  [Print, ~, [24, 26, 17], 38, Scalar], # 39
  [Print, ~, [21, 23, 17], 39, Scalar], # 40
  [Print, ~, [18, 20, 17], 40, Scalar], # 41
  [Print, ~, [2, 16, 17], 41, Scalar], # 42
  [Return, ~, [1], 42]]} # 43
```

## The string relations and `cmp`

The same operands and the same relations as the numeric case above,
different ops. The difference is only the context each imposes, which is
why both cases exist and neither would be enough alone.

```perl
my $a = $ARGV[0] // "aa";
my $b = $ARGV[1] // "bb";
print "seq [", ($a eq $b), "]\n";
print "sne [", ($a ne $b), "]\n";
print "slt [", ($a lt $b), "]\n";
print "sgt [", ($a gt $b), "]\n";
print "sle [", ($a le $b), "]\n";
print "sge [", ($a ge $b), "]\n";
print "scmp [", ($a cmp $b), "]\n";
```

```behavior
parses: yes
```

```output
seq []
sne [1]
slt [1]
sgt []
sle [1]
sge []
scmp [-1]
```

```tokens
one word-shaped operator whose text is "cmp"
```

```ir
main::__PROGRAM__: {start: 0, returns: [45], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "scmp ["}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, ~, [3, 4, 5], ~, Scalar], # 6
  [Constant, {const_type: string, value: aa}, ~, ~, Str], # 7
  [DefinedOr, ~, [6, 7], ~, Scalar], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Subscript, ~, [3, 10, 5], ~, Scalar], # 11
  [Constant, {const_type: string, value: bb}, ~, ~, Str], # 12
  [DefinedOr, ~, [11, 12], ~, Scalar], # 13
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 14
  [StrCmp, ~, [9, 14], ~, Int], # 15
  [Coerce, {from_repr: Int, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 17
  [Constant, {const_type: string, value: "sge ["}, ~, ~, Str], # 18
  [StrGe, ~, [9, 14], ~, Boolean], # 19
  [Coerce, {from_repr: Boolean, to_repr: Str}, [19], ~, Str], # 20
  [Constant, {const_type: string, value: "sle ["}, ~, ~, Str], # 21
  [StrLe, ~, [9, 14], ~, Boolean], # 22
  [Coerce, {from_repr: Boolean, to_repr: Str}, [22], ~, Str], # 23
  [Constant, {const_type: string, value: "sgt ["}, ~, ~, Str], # 24
  [StrGt, ~, [9, 14], ~, Boolean], # 25
  [Coerce, {from_repr: Boolean, to_repr: Str}, [25], ~, Str], # 26
  [Constant, {const_type: string, value: "slt ["}, ~, ~, Str], # 27
  [StrLt, ~, [9, 14], ~, Boolean], # 28
  [Coerce, {from_repr: Boolean, to_repr: Str}, [28], ~, Str], # 29
  [Constant, {const_type: string, value: "sne ["}, ~, ~, Str], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 31
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 32
  [StrNe, ~, [31, 32], ~, Boolean], # 33
  [Coerce, {from_repr: Boolean, to_repr: Str}, [33], ~, Str], # 34
  [Constant, {const_type: string, value: "seq ["}, ~, ~, Str], # 35
  [StrEq, ~, [31, 32], ~, Boolean], # 36
  [Coerce, {from_repr: Boolean, to_repr: Str}, [36], ~, Str], # 37
  [Print, ~, [35, 37, 17], 0, Scalar], # 38
  [Print, ~, [30, 34, 17], 38, Scalar], # 39
  [Print, ~, [27, 29, 17], 39, Scalar], # 40
  [Print, ~, [24, 26, 17], 40, Scalar], # 41
  [Print, ~, [21, 23, 17], 41, Scalar], # 42
  [Print, ~, [18, 20, 17], 42, Scalar], # 43
  [Print, ~, [2, 16, 17], 43, Scalar], # 44
  [Return, ~, [1], 44]]} # 45
```

## The five logical operators

`&&` is the op `and`, `||` is `or`, `//` is `dor`. Every operator is
parenthesised here, so this measures RETURN VALUES rather than binding
-- the binding question is the next case.

```perl
my $a = $ARGV[0] // 1;
my $b = $ARGV[1] // 0;
my $and = ($a && $b);
my $or = ($a || $b);
my $dor = ($b // $a);
my $not = (not $a);
my $xor = ($a xor $b);
print "and [$and] or [$or] dor [$dor] not [$not] xor [$xor]\n";
```

```behavior
parses: yes
```

```output
and [0] or [1] dor [0] not [] xor [1]
```

```tokens
one word-shaped operator whose text is "xor"
one operator whose text is "||"
```

```ir
main::__PROGRAM__: {start: 0, returns: [37], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "and ["}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, ~, [3, 4, 5], ~, Scalar], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [DefinedOr, ~, [6, 7], ~, Scalar], # 8
  [Subscript, ~, [3, 7, 5], ~, Scalar], # 9
  [DefinedOr, ~, [9, 4], ~, Scalar], # 10
  [And, ~, [8, 10], ~, Scalar], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [2, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "] or ["}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Or, ~, [8, 10], ~, Scalar], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Concat, ~, [15, 17], ~, Str], # 18
  [Constant, {const_type: string, value: "] dor ["}, ~, ~, Str], # 19
  [Concat, ~, [18, 19], ~, Str], # 20
  [DefinedOr, ~, [10, 8], ~, Scalar], # 21
  [Coerce, {from_repr: Unknown, to_repr: Str}, [21], ~, Str], # 22
  [Concat, ~, [20, 22], ~, Str], # 23
  [Constant, {const_type: string, value: "] not ["}, ~, ~, Str], # 24
  [Concat, ~, [23, 24], ~, Str], # 25
  [Not, ~, [8], ~, Boolean], # 26
  [Coerce, {from_repr: Boolean, to_repr: Str}, [26], ~, Str], # 27
  [Concat, ~, [25, 27], ~, Str], # 28
  [Constant, {const_type: string, value: "] xor ["}, ~, ~, Str], # 29
  [Concat, ~, [28, 29], ~, Str], # 30
  [Xor, ~, [8, 10], ~, Boolean], # 31
  [Coerce, {from_repr: Boolean, to_repr: Str}, [31], ~, Str], # 32
  [Concat, ~, [30, 32], ~, Str], # 33
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 34
  [Concat, ~, [33, 34], ~, Str], # 35
  [Print, ~, [35], 0, Scalar], # 36
  [Return, ~, [1], 36]]} # 37
```

## `&&` and `and` are one op at two precedences

The same op, differing only in precedence, and the op names cannot show
it. `my $tight = $a && 9` binds tighter than `=`; `my $loose = $a and 9`
does not, so the assignment happens first and the `and` is discarded.
Different trees, different output, identical op names.

```perl
my $a = $ARGV[0] // 1;
my $tight = $a && 9;
my $loose = $a and 9;
print "$tight $loose\n";
```

```behavior
parses: yes
```

```output
9 1
```

```tokens
one operator whose text is "&&"
one word-shaped operator whose text is "and"
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, ~, [2, 3, 4], ~, Scalar], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 8
  [And, ~, [7, 8], ~, Scalar], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [Print, ~, [16], 0, Scalar], # 17
  [Return, ~, [1], 17]]} # 18
```

## Punctuation `!`, and the double negative

`!0` is 1 and `!!0` is the EMPTY STRING, not 0 -- perl's false is a
dual-valued empty-string-and-zero and `print` shows the string half. A
parser folding `!!` to a no-op prints `[1][0]`.

Measured, `!!$a` lexes as TWO `Operator("!")` tokens. There is no `!!`
entry in the lexer's operator table and there should not be, but the
source writes the bytes adjacently, so they are there for a greedy scan
to fuse.

```perl
my $a = $ENV{X} // 0;
print "[", !$a, "][", !!$a, "]\n";
```

```behavior
parses: yes
```

```output
[1][]
```

```tokens
no operator whose text is "!!"
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [EnvRead, {key: X}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [DefinedOr, ~, [3, 4], ~, Str], # 5
  [Not, ~, [5], ~, Boolean], # 6
  [Coerce, {from_repr: Boolean, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "]["}, ~, ~, Str], # 8
  [Not, ~, [6], ~, Boolean], # 9
  [Coerce, {from_repr: Boolean, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 11
  [Print, ~, [2, 7, 8, 10, 11], 0, Scalar], # 12
  [Return, ~, [1], 12]]} # 13
```

## Comparisons chain, and the answer flips

`9 < 1 < 5` is FALSE. Chained it is `9 < 1 && 1 < 5`; read
left-associatively it is `("") < 5`, which is `0 < 5` and TRUE. One
source, opposite answers, no diagnostic either way.

The second line is the control and has to ASCEND: `1 < 5 < 9` is true
both ways, so a parser that prints the empty string twice fails it.
`1 < 9 < 5` would not serve -- false under both readings.

Constants are correct here, which is the one place in this tier that is
true: chaining is a PARSE-time n-ary grouping, not a foldable binary
expression, and `cmpchain_dup` survives constant operands.

```perl
print "[", (9 < 1 < 5), "]\n";
print "[", (1 < 5 < 9), "]\n";
```

```behavior
parses: yes
```

```output
[]
[1]
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 4
  [NumLt, ~, [3, 4], ~, Boolean], # 5
  [Coerce, {from_repr: Boolean, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 7
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 8
  [NumLt, ~, [8, 3], ~, Boolean], # 9
  [Coerce, {from_repr: Boolean, to_repr: Str}, [9], ~, Str], # 10
  [Print, ~, [2, 10, 7], 0, Scalar], # 11
  [Print, ~, [2, 6, 7], 11, Scalar], # 12
  [Return, ~, [1], 12]]} # 13
```

## Level 13 is `chain/na` and the halves differ

`1 == 1 == 1` compiles. `1 <=> 2 <=> 3` does not, nor does
`"a" cmp "b" cmp "c"`. A parser modelling perlop's level 13 as ONE
associativity class is wrong whichever it picks.

This is a `parses: no` case, which is what the claim IS: perl rejects
the source, so there is no output to pin and no tree to describe.

```perl
print 1 <=> 2 <=> 3;
```

```behavior
parses: no
```

```tokens
no operator whose text is "<="
no operator whose text is ">"
```

## Level 11 is the one true `%nonassoc`

`1 .. 2 .. 3` is a syntax error, and level 11 is the ONE `%nonassoc`
level in perly.y that means what the keyword suggests -- eight of the
eleven accept the repetition, because a conflict needs a left operand to
fight over and those are prefix forms whose second occurrence is the
first one's argument.

Without this case the corpus claims only the ACCEPTING direction, and a
parser refusing nothing would pass.

A `parses: no` case emits NO OPS, which is what makes this legal here:
`..` is tier 03's `range`/`flip`/`flop` and a parsing case spelling it
would fail the dependency lint.

```perl
my @x = (1 .. 2 .. 3);
```

```behavior
parses: no
```

```tokens
no operator whose text is "."
```
