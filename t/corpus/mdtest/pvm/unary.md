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
main::__PROGRAM__: {start: 0, returns: [26], nodes: [
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
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Concat, ~, [15, 12], ~, Str], # 16
  [Coerce, {from_repr: Scalar, to_repr: Str}, [6], ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [Concat, ~, [18, 12], ~, Str], # 19
  [Concat, ~, [19, 17], ~, Str], # 20
  [Concat, ~, [20, 12], ~, Str], # 21
  [Concat, ~, [21, 11], ~, Str], # 22
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 23
  [Concat, ~, [22, 23], ~, Str], # 24
  [Print, ~, [24], 0, Scalar], # 25
  [Return, ~, [1], 25]]} # 26
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
  [Return, ~, [1], 24]]} # 25
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
  [Return, ~, [1], 10], # 11
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
  [Return, ~, [1], 12]]} # 13
```
