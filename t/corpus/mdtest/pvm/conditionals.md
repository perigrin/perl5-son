# Conditionals

There is no `if` op, and `if` is not one thing. A bare `if` compiles to
tier 04's `and`; an `if`/`else` compiles to `cond_expr`, the same op the
ternary `?:` emits; `elsif` compiles to nested `cond_expr` and adds no op
of its own. So three source constructs share two ops between them, and
`unless` is a fourth spelling that differs from `if` by exactly one op.

**Tier 06 control.** Introduces `cond_expr`, `die`, `enteriter`,
`entertry`, `exit`, `goto`, `iter`, `last`, `leavetry`, `next`, `redo`,
`time`, `unstack`. Depends on 05_scoping.

Every case binds a runtime value and branches on it second.
A constant condition ERASES the construct: measured, `if (1) { print "y" }`
emits `pushmark`, `const` and `print` and no branch op at all, and
`while (0) { print "y" }` emits `enter`, `nextstate` and `leave` -- an
empty program. `$ENV{X}` is unset when the harness runs, so `// N` is a
stable operand the optimiser cannot see through.

## Block `if` and postfix `if` are one construct

The two statements emit the same ops in the same order, down to the
`nextstate` -- measured, the block form's braces add no `enter`/`leave`
pair at this nesting, and the `and` branches straight into `pushmark`
exactly as the postfix does.

This case asserts an EQUALITY rather than a behaviour. Both statements
print, so an output test alone passes against a parser that treats them as
unrelated grammar productions; what makes the claim checkable is that the
two halves of the measured op stream are byte-identical apart from the
`nextstate` line number.

```perl
my $c = $ENV{X} // 1;
if ($c) { print "block\n" }
print "postfix\n" if $c;
```

```behavior
parses: yes
```

```output
block
postfix
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [If, ~, [0, 4], 0], # 5
  [Proj, {index: 1}, [5]], # 6
  [Constant, {const_type: string, value: "block\n"}, ~, ~, Str], # 7
  [Proj, {index: 0}, [5]], # 8
  [Print, ~, [7], 8, Scalar], # 9
  [Region, {head: 5}, [6, 9]], # 10
  [If, ~, [10, 4], 10], # 11
  [Proj, {index: 1}, [11]], # 12
  [Constant, {const_type: string, value: "postfix\n"}, ~, ~, Str], # 13
  [Proj, {index: 0}, [11]], # 14
  [Print, ~, [13], 14, Scalar], # 15
  [Region, {head: 11}, [12, 15]], # 16
  [Return, ~, [1], 16]]} # 17
```

## `unless` is `or`, not an inverted `if`

Against the previous case's stream, position 9 is `and` there and `or`
here; every other op is the same op in the same place. There is no
negation op anywhere. Perl does not invert the condition and test it --
it picks the other short-circuit.

A parser that desugars `unless COND` to `if (!COND)` builds a tree perl
never builds, and nothing in the output distinguishes the two, which is
why this case exists. Both `and` and `or` are tier 04's ops; what this
tier contributes is the measurement that the two keywords differ by
exactly one of them.

```perl
my $c = $ENV{X} // 0;
unless ($c) { print "block\n" }
print "postfix\n" unless $c;
```

```behavior
parses: yes
```

```output
block
postfix
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [If, ~, [0, 4], 0], # 5
  [Proj, {index: 0}, [5]], # 6
  [Constant, {const_type: string, value: "block\n"}, ~, ~, Str], # 7
  [Proj, {index: 1}, [5]], # 8
  [Print, ~, [7], 8, Scalar], # 9
  [Region, {head: 5}, [6, 9]], # 10
  [If, ~, [10, 4], 10], # 11
  [Proj, {index: 0}, [11]], # 12
  [Constant, {const_type: string, value: "postfix\n"}, ~, ~, Str], # 13
  [Proj, {index: 1}, [11]], # 14
  [Print, ~, [13], 14, Scalar], # 15
  [Region, {head: 11}, [12, 15]], # 16
  [Return, ~, [1], 16]]} # 17
```

## Adding an `else` changes the op

A bare `if` emits `and`; an `if`/`else` emits `cond_expr` -- the same op
the ternary `?:` emits. One source-level keyword maps to two different ops
depending on whether an `else` is present, and only one of them is new to
this tier. The corpus needs both this case and the postfix one; neither
alone lints the tier, and a parser that emits one shape for both spellings
passes either in isolation.

The `else` arm is what brings back the `enter`/`leave` pair the bare `if`
does not emit: `cond_expr` jumps into a second block, and a second block
is a scope.

The erasure this case exists to avoid is sharp here. Measured,
`if (1) { print "y" } else { print "n" }` emits `pushmark`, `const` and
`print` and NO branch op -- the else arm is gone from the binary. Such a
case would pass its output test while measuring none of this tier.

```perl
my $c = $ENV{X} // 0;
if ($c) { print "taken\n" } else { print "else\n" }
```

```behavior
parses: yes
```

```output
else
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "taken\n"}, ~, ~, Str], # 2
  [EnvRead, {key: X}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [DefinedOr, ~, [3, 4], ~, Str], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 0}, [6]], # 7
  [Print, ~, [2], 7, Scalar], # 8
  [Constant, {const_type: string, value: "else\n"}, ~, ~, Str], # 9
  [Proj, {index: 1}, [6]], # 10
  [Print, ~, [9], 10, Scalar], # 11
  [Region, {head: 6}, [8, 11]], # 12
  [Return, ~, [1], 12]]} # 13
```

## `elsif` is a third form, not `else` followed by `if`

The tier shipped with `if`, `unless` and `if`/`else` and no `elsif`
anywhere, while 14 of T1's 986 files use it. Measured, the chain compiles
to NESTED `cond_expr`, one per condition, and adds no op of its own -- so
`cond_expr`, already claimed for `if`/`else`, covers it and the INTRODUCES
set does not grow.

What distinguishes `elsif` is the SHAPE of the nesting, which ops cannot
show, so the case pins the branch behaviourally instead: the MIDDLE branch
is the one taken, which neither a lone `if` nor an `else` can produce.

The token facts count rather than forbid, and the counting is the
falsifying half. This source holds exactly ONE `elsif` and ONE `else`, so
a lexer that read `elsif` as `else` followed by `if` would produce TWO
words spelled `else` and fail the second fact. Measured, ours emits
`Word("elsif")` whole.

```perl
my $c = $ENV{X} // 0;
if ($c == 1) { print "one\n" } elsif ($c == 0) { print "zero\n" } else { print "other\n" }
```

```behavior
parses: yes
```

```output
zero
```

```tokens
one word whose text is "elsif"
one word whose text is "else"
```

```ir
main::__PROGRAM__: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "one\n"}, ~, ~, Str], # 2
  [EnvRead, {key: X}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [DefinedOr, ~, [3, 4], ~, Str], # 5
  [Coerce, {from_repr: Str, to_repr: Num}, [5], ~, Num], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [NumEq, ~, [6, 7], ~, Boolean], # 8
  [If, ~, [0, 8], 0], # 9
  [Proj, {index: 0}, [9]], # 10
  [Print, ~, [2], 10, Scalar], # 11
  [Constant, {const_type: string, value: "zero\n"}, ~, ~, Str], # 12
  [Proj, {index: 1}, [9]], # 13
  [NumEq, ~, [6, 4], ~, Boolean], # 14
  [If, ~, [13, 14], 13], # 15
  [Proj, {index: 0}, [15]], # 16
  [Print, ~, [12], 16, Scalar], # 17
  [Constant, {const_type: string, value: "other\n"}, ~, ~, Str], # 18
  [Proj, {index: 1}, [15]], # 19
  [Print, ~, [18], 19, Scalar], # 20
  [Region, {head: 15}, [17, 20]], # 21
  [Region, {head: 9}, [11, 21]], # 22
  [Return, ~, [1], 22]]} # 23
```
