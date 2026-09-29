# Jumps

`next`, `last` and `redo` are the three targets `enterloop` and
`enteriter` already name in their own dump -- `enteriter(next->w last->z
redo->g)` -- so the loop ops and the jump ops are one measurement, not
two. A tier that claimed the loops and left the jumps for later would be
claiming half of a single line of output. `goto` joins them: it is a
loop-control statement in everything but name, the same code path as the
other three.

**Tier 06 control.** Introduces `cond_expr`, `die`, `enteriter`,
`entertry`, `exit`, `goto`, `iter`, `last`, `leavetry`, `next`, `redo`,
`time`, `unstack`. Depends on 05_scoping.

Every case binds a runtime value and branches on it second.
A constant condition ERASES the construct: measured, `if (1) { print "y" }`
emits `pushmark`, `const` and `print` and no branch op at all, and
`while (0) { print "y" }` emits `enter`, `nextstate` and `leave` -- an
empty program. `$ENV{X}` is unset when the harness runs, so `// N` is a
stable operand the optimiser cannot see through.

## The three loop-control statements

All three take no operands. The labelled forms emit the SAME op carrying a
string -- `next("OUTER")` -- so the corpus distinguishes the spellings by
the argument rather than by the op name, and a parser that produces a
different node kind for the labelled form is producing a distinction perl
does not make.

`redo` is exercised under a guard that is false at run time, which is the
only way to emit the op without writing a loop that does not terminate:
`$ENV{R}` is unset, so `// 0` is a stable false and the op is compiled,
reachable and not taken.

Measured, the `v*` flag is what marks a jump: the op never returns to its
successor, so the stream's textual order is not its execution order.

```perl
my $r = $ENV{R} // 0;
my @l = ($ENV{A} // "a", "b", "c", "d");
foreach my $x (@l) {
    redo if $r;
    next if $x eq "b";
    last if $x eq "d";
    print $x;
}
print "\n";
```

```behavior
parses: yes
```

```output
ac
```

```ir
main::__PROGRAM__: {start: 0, returns: [29], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [Proj, {index: 0}, [3]], # 5
  [Loop, {bound: each}, [5], 5], # 6
  [Proj, {index: 1}, [6]], # 7
  [Region, {head: 6}, [7]], # 8
  [EnvRead, {key: A}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 10
  [DefinedOr, ~, [9, 10], ~, Str], # 11
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 14
  [ArrayLiteral, {sigil: "@", symbol: l}, [11, 12, 13, 14], ~, Array], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Phi, {region: 3}, [16, 33], ~, Int], # 17
  [MemStart], # 18
  [Subscript, ~, [15, 17, 18], ~, Scalar], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 20
  [StrEq, ~, [20, 12], ~, Boolean], # 21
  [If, ~, [8, 21], 8], # 22
  [Proj, {index: 1}, [22]], # 23
  [StrEq, ~, [20, 14], ~, Boolean], # 24
  [If, ~, [23, 24], 23], # 25
  [Proj, {index: 0}, [25]], # 26
  [Region, {head: 3}, [4, 26]], # 27
  [Print, ~, [2], 27, Scalar], # 28
  [Return, ~, [1], 28], # 29
  [Count, ~, [15, 18], ~, Int], # 30
  [NumGt, ~, [30, 17], 3, Boolean], # 31
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 32
  [Add, ~, [17, 32], ~, Int], # 33
  [EnvRead, {key: R}, ~, ~, Str], # 34
  [DefinedOr, ~, [34, 16], ~, Str], # 35
  [Coerce, {from_repr: Unknown, to_repr: Boolean}, [35], 6, Boolean], # 36
  [Proj, {index: 0}, [6]], # 37
  [Proj, {index: 1}, [25]], # 38
  [Print, ~, [20], 38, Scalar], # 39
  [Proj, {index: 0}, [22]], # 40
  [Region, {head: 22}, [40, 39]]]} # 41
```

## `goto` is one op name over unrelated constructs

Two spellings are affordable at this tier. `goto LABEL` emits a `<">` op
-- the class B::Concise uses for an op with an SV operand baked in --
carrying the label as a constant and taking nothing from the stack.
`goto $target` emits a `<1>` unary op over the pad slot, and the label it
lands on is not known until run time. Same name, different arity,
different class: a parser that gives them one node shape with an optional
operand is modelling something perl does not.

The third spelling, `goto &sub`, is MEASURED OUT rather than forgotten. It
compiles to `rv2cv`/`srefgen`/`goto` inside the sub body, which is not
visible in the main optree at all and needs `-exec,g` to see; `rv2cv`
belongs to tier 07 and `srefgen` to tier 08, so a case spelling it here
would fail the lint on two ops the tier cannot claim. The op NAME is
claimed here because these two spellings emit it; the frame-replacing
spelling waits for the tier that supplies frames.

Both jumps go FORWARD to a label at the same scope depth. Perl warns about
`goto` into or out of a construct and the harness compares output byte for
byte, so a warning would be a diff.

The label is not an op. It is a flag on the `nextstate` of the statement
it precedes -- `nextstate(SKIP: ...)` -- so a label with no statement after
it has nowhere to live, and the jump targets a statement rather than a
position.

```perl
my $c = $ENV{X} // 0;
my $t = $ENV{T} // "TAIL";
print "a";
goto SKIP unless $c;
print "b";
SKIP:
print "c";
goto $t;
print "d";
TAIL:
print "e\n";
```

```behavior
parses: yes
```

```output
ace
```

```ir
main::__PROGRAM__: {start: 0, returns: [35], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "e\n"}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: "Can't find label "}, ~, ~, Str], # 4
  [EnvRead, {key: T}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: TAIL}, ~, ~, Str], # 6
  [DefinedOr, ~, [5, 6], ~, Str], # 7
  [Concat, ~, [4, 7], ~, Str], # 8
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 11
  [Print, ~, [11], 0, Scalar], # 12
  [EnvRead, {key: X}, ~, ~, Str], # 13
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 14
  [DefinedOr, ~, [13, 14], ~, Str], # 15
  [If, ~, [12, 15], 12], # 16
  [Proj, {index: 0}, [16]], # 17
  [Print, ~, [10], 17, Scalar], # 18
  [Proj, {index: 1}, [16]], # 19
  [Region, ~, [18, 19]], # 20
  [Loop, {bound: each}, [20], 20], # 21
  [Print, ~, [9], 21, Scalar], # 22
  [Constant, {const_type: string, value: SKIP}, ~, ~, Str], # 23
  [StrNe, ~, [7, 23], ~, Boolean], # 24
  [If, ~, [22, 24], 22], # 25
  [Proj, {index: 0}, [25]], # 26
  [StrEq, ~, [7, 6], ~, Boolean], # 27
  [If, ~, [26, 27], 26], # 28
  [Proj, {index: 1}, [28]], # 29
  [Unwind, ~, [8], 29], # 30
  [Print, ~, [3], 30, Scalar], # 31
  [Proj, {index: 0}, [28]], # 32
  [Region, ~, [31, 32]], # 33
  [Print, ~, [2], 33, Scalar], # 34
  [Return, ~, [1], 34], # 35
  [Proj, {index: 1}, [25]]]} # 36
```

## A label AND a statement modifier on one jump

`next OUTER if $y eq "b"` carries both: the LABEL names which loop to jump
in, and the MODIFIER decides whether to jump at all. They are different
things in different places and a parser has to keep them apart.

Measured 5.42.0, the label is the jump op's SV operand and the modifier is
an ordinary conditional around it -- `next("OUTER")` inside the branch --
so this case claims no op tier 06 has not already introduced. The inner
loop is what makes the label observable: `next` with no label would
continue the INNER loop, and the output would differ.

This is where issue 01a0dee8 was measured. `last if $x;` parsed as THREE
statements with ZERO Unknown nodes, because `parseLoopControl` asked only
whether the next word was a statement keyword and `if` is not one -- so
`if` became the LABEL, and the real condition was left as a statement of
its own. `parseGoto` already made the extra test and said so in its own
comment; `parseLoopControl` did not, and nothing applied the modifier
either way.

THE LABELLED FORM IS WHY THIS IS A SEPARATE CASE from the three unlabelled
jumps above. A parser that takes the modifier word as the label passes an
unlabelled `last if $x` by accident -- there is no label to be wrong about
-- and here it must choose between two words that are both barewords in the
same position.

`last OUTER if $c` is compiled and NOT TAKEN: `$ENV{X}` is unset, so `// 0`
is a stable false the optimiser cannot see through, and the op is present,
reachable and not reached. Same technique as `redo` above.

```perl
my $c = $ENV{X} // 0;
my @l = ($ENV{A} // "a", "b", "c");
OUTER: foreach my $x (@l) {
    foreach my $y (@l) {
        next OUTER if $y eq "b";
        last OUTER if $c;
        print $y;
    }
}
print "\n";
```

```behavior
parses: yes
```

```output
aaa
```

```ir
main::__PROGRAM__: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [Proj, {index: 0}, [3]], # 5
  [Loop, {bound: entry}, [5], 5], # 6
  [Proj, {index: 0}, [6]], # 7
  [EnvRead, {key: A}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 9
  [DefinedOr, ~, [8, 9], ~, Str], # 10
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 12
  [ArrayLiteral, {sigil: "@", symbol: l}, [10, 11, 12], ~, Array], # 13
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 14
  [Phi, {region: 6}, [14, 39], ~, Int], # 15
  [MemStart], # 16
  [Subscript, ~, [13, 15, 16], ~, Scalar], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [StrEq, ~, [18, 11], ~, Boolean], # 19
  [If, ~, [7, 19], 7], # 20
  [Proj, {index: 1}, [20]], # 21
  [EnvRead, {key: X}, ~, ~, Str], # 22
  [DefinedOr, ~, [22, 14], ~, Str], # 23
  [If, ~, [21, 23], 21], # 24
  [Proj, {index: 0}, [24]], # 25
  [Region, {head: 3}, [4, 25]], # 26
  [Print, ~, [2], 26, Scalar], # 27
  [Return, ~, [1], 27], # 28
  [Count, ~, [13, 16], ~, Int], # 29
  [Phi, {region: 3}, [14, 34], ~, Int], # 30
  [NumGt, ~, [29, 30], 3, Boolean], # 31
  [NumGt, ~, [29, 15], 6, Boolean], # 32
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 33
  [Add, ~, [30, 33], ~, Int], # 34
  [Subscript, ~, [13, 30, 16], ~, Scalar], # 35
  [Proj, {index: 1}, [6]], # 36
  [Region, {head: 6}, [36]], # 37
  [Proj, {index: 1}, [24]], # 38
  [Add, ~, [15, 33], ~, Int], # 39
  [Proj, {index: 0}, [20]], # 40
  [Region, {head: 3}, [37, 40]], # 41
  [Print, ~, [18], 38, Scalar]]} # 42
```
