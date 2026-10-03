# Increment, negation and the file tests

perlop's levels 3, 5 and 10 -- between them one file, and it was about
something else.

**Tier 04 operators.** Introduces `preinc`, `postinc`, `predec`,
`postdec`, `ftis`. Depends on 03_context.

`postinc` moved here from 07_subroutines, which had claimed it as a side
effect of a file about argument aliasing and held it "for a gap rather
than on merit". perlop puts `++` four tiers before subroutines exist.

## Pre and post, increment and decrement

Four spellings separated by their RETURN VALUE rather than their effect:
a parser reading `$a++` as `++$a` prints the same final `$a` and a
different second field. `preinc` and `postinc` are separate ops, not one
op with a flag.

```perl
my $a = $ENV{X} // 5;
my $b = $a++;
my $c = ++$a;
my $d = $a--;
my $e = --$a;
print "$a $b $c $d $e\n";
```

```behavior
parses: yes
```

```output
5 5 7 7 5
```

```tokens
no operator whose text is "+"
```

```ir
main::__PROGRAM__: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Increment, ~, [4], ~, Scalar], # 5
  [Increment, ~, [5], ~, Scalar], # 6
  [Coerce, {from_repr: Scalar, to_repr: Num}, [6], ~, Num], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Subtract, ~, [7, 8], ~, Num], # 9
  [Subtract, ~, [9, 8], ~, Num], # 10
  [Coerce, {from_repr: Num, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 14
  [DefinedOr, ~, [4, 14], ~, Scalar], # 15
  [Coerce, {from_repr: Scalar, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [13, 16], ~, Str], # 17
  [Concat, ~, [17, 12], ~, Str], # 18
  [Coerce, {from_repr: Scalar, to_repr: Str}, [6], ~, Str], # 19
  [Concat, ~, [18, 19], ~, Str], # 20
  [Concat, ~, [20, 12], ~, Str], # 21
  [Concat, ~, [21, 19], ~, Str], # 22
  [Concat, ~, [22, 12], ~, Str], # 23
  [Concat, ~, [23, 11], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [Concat, ~, [24, 25], ~, Str], # 26
  [Print, ~, [26], 0, Scalar], # 27
  [Return, {implicit: true}, [1], 27]]} # 28
```

## The magic string increment

A successor function on strings with no arithmetic in it: `"Az"` becomes
`"Ba"`, `"zz"` becomes `"aaa"`, `"a9"` becomes `"b0"`. perlop documents
it as a special case of `++` and no other operator in the language
behaves this way.

```perl
my $a = $ENV{X} // "Az";
my $b = $ENV{Y} // "zz";
my $c = $ENV{Z} // "a9";
$a++;
$b++;
$c++;
print "$a $b $c\n";
```

```behavior
parses: yes
```

```output
Ba aaa b0
```

```tokens
no operator whose text is "+"
```

```ir
main::__PROGRAM__: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: Az}, ~, ~, Str], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Increment, ~, [4], ~, Scalar], # 5
  [Coerce, {from_repr: Scalar, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [EnvRead, {key: "Y"}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: zz}, ~, ~, Str], # 10
  [DefinedOr, ~, [9, 10], ~, Str], # 11
  [Increment, ~, [11], ~, Scalar], # 12
  [Coerce, {from_repr: Scalar, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [8, 13], ~, Str], # 14
  [Concat, ~, [14, 7], ~, Str], # 15
  [EnvRead, {key: Z}, ~, ~, Str], # 16
  [Constant, {const_type: string, value: a9}, ~, ~, Str], # 17
  [DefinedOr, ~, [16, 17], ~, Str], # 18
  [Increment, ~, [18], ~, Scalar], # 19
  [Coerce, {from_repr: Scalar, to_repr: Str}, [19], ~, Str], # 20
  [Concat, ~, [15, 20], ~, Str], # 21
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 22
  [Concat, ~, [21, 22], ~, Str], # 23
  [Print, ~, [23], 0, Scalar], # 24
  [Return, {implicit: true}, [1], 24]]} # 25
```

## Unary `+` computes nothing and disambiguates

It is the only way to stop `print (...)` being read as a complete call.
`print (1+2)*3` is `(print(1+2))*3` -- the parens after a list operator
are its ARGUMENT LIST, so print takes `1+2`, prints 3, and the `*3`
multiplies print's return value and is discarded.

NEITHER READING IS AN ERROR. Both compile, both print a number, and the
number is wrong only if you meant the other one.

This case declares NO token fact, which is a decision. It carried one
and the fact was vacuous: `no operator whose text is "+("` names a
spelling absent from the lexer's operator table, so no input could ever
produce it. No replacement is honest either -- every numeric literal in
the source appears exactly twice, the source writes a bare `+`, and it
contains no `=` at all. The output is the whole claim and it is enough.

```perl
print (1+2)*3;
print "\n";
print +(1+2)*3;
print "\n";
```

```behavior
parses: yes
```

```output
3
9
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 3
  [Coerce, {from_repr: Int, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 5
  [Coerce, {from_repr: Int, to_repr: Str}, [5], ~, Str], # 6
  [Print, ~, [6], 0, Scalar], # 7
  [Print, ~, [2], 7, Scalar], # 8
  [Print, ~, [4], 8, Scalar], # 9
  [Print, ~, [2], 9, Scalar], # 10
  [Return, {implicit: true}, [1], 10], # 11
  [Multiply, ~, [7, 5], ~, Num]]} # 12
```

## The file-test operators

`-e` is a NAMED UNARY whose name is punctuation, and the whole family
(`-e -d -f -s -z -r -w -x -M -A -C`) is 27 letters wide. The set was
measured from the optree rather than transcribed: a letter belongs iff
`my $v = -L $f;` compiles to an `ft*` op, which admits `o` and `O` --
both real file tests that Deparse prints back as `-O`.

WHAT A PARSER GETS WRONG IS THE MINUS. `-e $f` is a file test; `-$e` is
negation; `-bareword` is the string `"-bareword"`. Three readings of one
character, decided by what follows it.

Both spellings are written, and the parenthesised one is what makes the
fork actual: `e($f)` would be a call to an undeclared sub, so that form
has no reading where `-e` is a minus applied to something.

THE DECIDING BYTES ARE THE TWO THEMSELVES, not the position. This case
used to refuse in a shape the corpus had not recorded -- no Unknown node
at all, only the token fact failing, because the lexer split `-e` into
`Operator(-) Word(e)` and the parser glued the pair back together. What
made that glue removable is that there is no subtraction reading to
choose between: `1 -e "/etc"` is a SYNTAX ERROR, perl having formed `-e`
and then found nowhere to put it. So the lexer forms the operator whole
and this case passes on both spellings.

Three boundaries keep the minus honest, and each is a separate
measurement: `-e1` is `-$f->e1`, a method call, so the letter must not
begin a longer word; `- e $f` is `-$f->e`, so the two bytes must be
adjacent; and `{ -e => 1 }` is the string `'-e'`, so a fat comma
autoquotes the whole thing.

```perl
my $f = $ENV{X} // "/etc/hostname";
print "[", (-e $f), "][", (-e($f)), "]\n";
```

```behavior
parses: yes
```

```output
[1][1]
```

```tokens
no operator whose text is "-"
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [EnvRead, {key: X}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: "/etc/hostname"}, ~, ~, Str], # 4
  [DefinedOr, ~, [3, 4], ~, Str], # 5
  [Call, {dispatch_kind: builtin, name: ftis, param_names: []}, [5], ~, Unknown], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "]["}, ~, ~, Str], # 8
  [Call, {dispatch_kind: builtin, name: ftis, param_names: []}, [5], ~, Unknown], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 11
  [Print, ~, [2, 7, 8, 10, 11], 0, Scalar], # 12
  [Return, {implicit: true}, [1], 12]]} # 13
```

## Pre- and post-increment of an element, used

The post form yields the old value and the pre form the new one, each exactly once; the second `++$h{a}` sees the first's store. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl.

```perl
my %h;
my $a1 = $h{a}++;
my $a2 = $h{a}++;
my $b1 = ++$h{b};
my $b2 = ++$h{b};
print "$a1 $a2 $h{a} $b1 $b2 $h{b}\n";
```

```behavior
parses: yes
```

```output
0 1 2 1 2 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [45], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {sigil: "%", symbol: h}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [MemStart], # 4
  [Subscript, {kind: hash}, [2, 3, 4], 0, Scalar], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 11
  [Increment, ~, [5], ~, Scalar], # 12
  [Assign, ~, [11, 12], 5, Scalar], # 13
  [Subscript, {kind: hash}, [2, 3, 13], 13, Scalar], # 14
  [DefinedOr, ~, [14, 6], ~, Scalar], # 15
  [Coerce, {from_repr: Scalar, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [10, 16], ~, Str], # 17
  [Concat, ~, [17, 9], ~, Str], # 18
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 19
  [Subscript, {kind: hash}, [2, 19], ~, Scalar], # 20
  [Increment, ~, [14], ~, Scalar], # 21
  [Assign, ~, [11, 21], 14, Scalar], # 22
  [Subscript, {kind: hash}, [2, 19, 22], 22, Scalar], # 23
  [Increment, ~, [23], ~, Scalar], # 24
  [Assign, ~, [20, 24], 23, Scalar], # 25
  [Subscript, {kind: hash}, [2, 19, 25], 25, Scalar], # 26
  [Increment, ~, [26], ~, Scalar], # 27
  [Assign, ~, [20, 27], 26, Scalar], # 28
  [Subscript, {kind: hash}, [2, 3, 28], ~, Scalar], # 29
  [Coerce, {from_repr: Unknown, to_repr: Str}, [29], ~, Str], # 30
  [Concat, ~, [18, 30], ~, Str], # 31
  [Concat, ~, [31, 9], ~, Str], # 32
  [Coerce, {from_repr: Scalar, to_repr: Str}, [24], ~, Str], # 33
  [Concat, ~, [32, 33], ~, Str], # 34
  [Concat, ~, [34, 9], ~, Str], # 35
  [Coerce, {from_repr: Scalar, to_repr: Str}, [27], ~, Str], # 36
  [Concat, ~, [35, 36], ~, Str], # 37
  [Concat, ~, [37, 9], ~, Str], # 38
  [Subscript, {kind: hash}, [2, 19, 28], ~, Scalar], # 39
  [Coerce, {from_repr: Unknown, to_repr: Str}, [39], ~, Str], # 40
  [Concat, ~, [38, 40], ~, Str], # 41
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 42
  [Concat, ~, [41, 42], ~, Str], # 43
  [Print, ~, [43], 28, Scalar], # 44
  [Return, {implicit: true}, [1], 44]]} # 45
```
