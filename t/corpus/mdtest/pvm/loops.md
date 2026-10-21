# Loops

`enterloop` and `leaveloop` are tier 05's, claimed there for the bare
block -- a bare `{ ... }` is a loop that runs once. What this tier adds is
`unstack`, the op that distinguishes a loop that iterates from a block
that does not, and `enteriter`/`iter`, which are the `foreach` family.

"for" names two unrelated optrees: C-style `for` emits `enterloop` like a
`while`, `foreach` emits `enteriter`/`iter` and no `enterloop` at all.
Both close with `leaveloop`. `while` and `until` differ by the same one op
as `if` and `unless` -- the test is `and` for one and `or` for the other.
What makes a loop a loop is `enterloop`/`unstack`, not the test.

**Tier 06 control.** Introduces `cond_expr`, `die`, `enteriter`,
`entertry`, `exit`, `goto`, `iter`, `last`, `leavetry`, `next`, `redo`,
`time`, `unstack`. Depends on 05_scoping.

Every case binds a runtime value and branches on it second.
A constant condition ERASES the construct: measured, `if (1) { print "y" }`
emits `pushmark`, `const` and `print` and no branch op at all, and
`while (0) { print "y" }` emits `enter`, `nextstate` and `leave` -- an
empty program. `$ENV{X}` is unset when the harness runs, so `// N` is a
stable operand the optimiser cannot see through.

## The block `while`

Measured, a block `while` emits `enterloop`, tests with tier 04's `and`,
closes each pass with `unstack` and exits through `leaveloop`. The bare
block of tier 05 emits the first and last of those and not `unstack`,
which is why `unstack` is this tier's and the frame ops are not.

`enterloop` names all three jump targets in its own dump --
`enterloop(next->k last->p redo->c)` -- which is why `next`, `last` and
`redo` are claimed in this tier rather than deferred: the loop ops and the
jump ops are one measurement.

```perl
my $n = $ENV{N} // 3;
my $i = 0;
while ($i < $n) { print $i; $i = $i + 1 }
print "\n";
```

```behavior
parses: yes
```

```output
012
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Loop, {bound: each}, [0], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [Region, {head: 3}, [4]], # 5
  [Print, ~, [2], 5, Scalar], # 6
  [Return, {implicit: true}, [1], 6], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Phi, {region: 3}, [8, 19], ~, Int], # 9
  [EnvRead, {key: "N"}, ~, ~, Str], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [DefinedOr, ~, [10, 11], ~, Str], # 12
  [Coerce, {from_repr: Str, to_repr: Num}, [12], ~, Num], # 13
  [NumLt, ~, [9, 13], 3, Boolean], # 14
  [Proj, {index: 0}, [3]], # 15
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 16
  [Print, ~, [16], 15, Scalar], # 17
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 18
  [Add, ~, [9, 18], ~, Int]]} # 19
```

## `until` is `while` with the other short-circuit

Measured, the only difference from the `while` stream is one position:
`or` where `while` has `and`. Everything else -- `enterloop`, `unstack`,
`leaveloop` -- is identical. So the loop family and the conditional family
share their branch ops entirely, and there is no negation op in either
pair.

The condition is spelled `$i >= $n` rather than `!($i < $n)` for the same
reason the `unless` case does not spell its condition `!$c`: a `not` op
would be tier 04's, would appear in the stream, and would make the case
measure a different construct from the one it names. The `ge` against the
`while` case's `lt` is the source's own inversion, not perl's.

```perl
my $n = $ENV{N} // 3;
my $i = 0;
until ($i >= $n) { print $i; $i = $i + 1 }
print "\n";
```

```behavior
parses: yes
```

```output
012
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Loop, {bound: each}, [0], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [Region, {head: 3}, [4]], # 5
  [Print, ~, [2], 5, Scalar], # 6
  [Return, {implicit: true}, [1], 6], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Phi, {region: 3}, [8, 19], ~, Int], # 9
  [EnvRead, {key: "N"}, ~, ~, Str], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [DefinedOr, ~, [10, 11], ~, Str], # 12
  [Coerce, {from_repr: Str, to_repr: Num}, [12], ~, Num], # 13
  [NumLt, ~, [9, 13], 3, Boolean], # 14
  [Proj, {index: 0}, [3]], # 15
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 16
  [Print, ~, [16], 15, Scalar], # 17
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 18
  [Add, ~, [9, 18], ~, Int], # 19
  [NumGe, ~, [9, 13], ~, Boolean]]} # 20
```

## C-style `for` is a `while`

It emits `enterloop`, not `enteriter`. The init clause runs once before
`enterloop` as an ordinary `padsv_store`; the increment clause is compiled
into the tail of the body, ahead of the `unstack`. From the op stream's
point of view the three clauses are not three things, and the only
structural mark this form leaves that the block `while` does not is an
extra `unstack v*` between the init and `enterloop`.

Measured, `next` targets the increment clause and not the `unstack`, which
is why `next` in a C-style `for` still advances the counter and `next` in
a `while` written the same way does not.

```perl
my $n = $ENV{N} // 3;
for (my $i = 0; $i < $n; $i = $i + 1) { print $i }
print "\n";
```

```behavior
parses: yes
```

```output
012
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Loop, {bound: each}, [0], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [Region, {head: 3}, [4]], # 5
  [Print, ~, [2], 5, Scalar], # 6
  [Return, {implicit: true}, [1], 6], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Phi, {region: 3}, [8, 19], ~, Int], # 9
  [EnvRead, {key: "N"}, ~, ~, Str], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [DefinedOr, ~, [10, 11], ~, Str], # 12
  [Coerce, {from_repr: Str, to_repr: Num}, [12], ~, Num], # 13
  [NumLt, ~, [9, 13], 3, Boolean], # 14
  [Proj, {index: 0}, [3]], # 15
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 16
  [Print, ~, [16], 15, Scalar], # 17
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 18
  [Add, ~, [9, 18], ~, Int]]} # 19
```

## `foreach` emits `enteriter`/`iter` and no `enterloop`

A different optree from the C-style `for` that shares its keyword.
`enteriter` does what `enterloop` does -- it names the same three jump
targets in its own dump -- and additionally allocates the loop variable's
pad slot with `LVINTRO`, which is why this tier cannot sit before 05.

The per-pass `iter` is the op with no analogue in the `while` family: it
advances the list cursor and pushes the truth of "there was another one"
for the `and` to test, so the loop's condition is not written anywhere in
the source.

The list is built from `$ENV{A}` for the same reason every other case here
binds a runtime value, though the erasure is milder -- measured,
`foreach my $x (1, 2)` does keep its loop ops. The rule is uniform so that
no case in the tier has to be argued about individually.

```perl
my @l = ($ENV{A} // "a", "b", "c");
foreach my $x (@l) { print $x }
print "\n";
```

```behavior
parses: yes
```

```output
abc
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [Region, {head: 3}, [4]], # 5
  [Print, ~, [2], 5, Scalar], # 6
  [Return, {implicit: true}, [1], 6], # 7
  [EnvRead, {key: A}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 9
  [DefinedOr, ~, [8, 9], ~, Str], # 10
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 12
  [ArrayLiteral, {sigil: "@", symbol: l}, [10, 11, 12], ~, Array], # 13
  [MemStart], # 14
  [Count, ~, [13, 14], ~, Int], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Phi, {region: 3}, [16, 24], ~, Int], # 17
  [NumGt, ~, [15, 17], 3, Boolean], # 18
  [Proj, {index: 0}, [3]], # 19
  [Subscript, {kind: array}, [13, 17, 14], ~, Scalar], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Print, ~, [21], 19, Scalar], # 22
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 23
  [Add, ~, [17, 23], ~, Int]]} # 24
```

## `do BLOCK while COND` is a post-test loop

The body runs before the condition is ever evaluated, and this is not
`while` with the parts moved. Measured with N unset, `unstack` is the only
loop op in the stream: there is no `enterloop` and no `leaveloop`
anywhere, exactly as the postfix modifier measures. So `next` and `last`
have no frame to address here either -- perl builds a plain scope and a
backward jump.

And the ORDER is the construct. The body precedes the test, where the
block `while` puts the test first and jumps over the body. A parser that
desugars this to `while (COND) { BLOCK }` emits the same op NAMES in a
different order, which is why this case pins behaviour and not an op list.

The behavioural pin is the discriminating half: N is unset, so the
condition is false on its first evaluation and the body still runs once. A
`while` loop with that same false condition prints NOTHING -- measured, it
compiles to an empty program. One line of output where the desugared
spelling produces none.

The token facts count. This source holds exactly one `do` and exactly one
`while`, so a lexer that split `do` off as a separate statement, or that
read the trailing `while` as opening a second loop, would produce a count
this case refuses.

```perl
my $i = $ENV{N} // 0;
do { print "once" } while $i > 0;
print "\n";
```

```behavior
parses: yes
```

```output
once
```

```tokens
one word whose text is "do"
one word whose text is "while"
```

```ir
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: once}, ~, ~, Str], # 3
  [Print, ~, [3], 0, Scalar], # 4
  [Loop, {bound: each}, [4], 4], # 5
  [Proj, {index: 1}, [5]], # 6
  [Region, {head: 5}, [6]], # 7
  [Print, ~, [2], 7, Scalar], # 8
  [Return, {implicit: true}, [1], 8], # 9
  [Proj, {index: 0}, [5]], # 10
  [Print, ~, [3], 10, Scalar], # 11
  [EnvRead, {key: "N"}, ~, ~, Str], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [DefinedOr, ~, [12, 13], ~, Str], # 14
  [Coerce, {from_repr: Str, to_repr: Num}, [14], ~, Num], # 15
  [NumGt, ~, [15, 13], 5, Boolean]]} # 16
```

## The postfix loop modifier builds no loop frame

`EXPR while COND` emits `enter`/`leave` and `unstack` but NO `enterloop`.
This is the exception that proves postfix `if`: the conditional case
measures that postfix and block `if` are the same construct to perl, and
the loop modifiers are where that reasoning fails. Same modifier syntax,
different machinery.

A postfix loop has no block, so there is nothing for `next` and `last` to
target, so perl does not build the loop frame that names those targets.
The consequence is observable rather than cosmetic: `next` inside a
postfix `while` does not address that loop, because that loop has no
`enterloop` to address.

The body is `$i = $i - 1` rather than `$i--` because `postdec` is an op no
tier here claims, and the case's subject is the loop, not the decrement.
The lint refused the shorter spelling and was right to.

```perl
my $i = $ENV{N} // 3;
print $i = $i - 1 while $i > 0;
print "\n";
```

```behavior
parses: yes
```

```output
210
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Loop, {bound: each}, [0], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [Region, {head: 3}, [4]], # 5
  [Print, ~, [2], 5, Scalar], # 6
  [Return, {implicit: true}, [1], 6], # 7
  [EnvRead, {key: "N"}, ~, ~, Str], # 8
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 9
  [DefinedOr, ~, [8, 9], ~, Str], # 10
  [Phi, {region: 3}, [10, 16], ~, Unknown], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [NumGt, ~, [11, 12], 3, Boolean], # 13
  [Proj, {index: 0}, [3]], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Subtract, ~, [11, 15], ~, Unknown], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Print, ~, [17], 14, Scalar]]} # 18
```

## The postfix `foreach` iterates a LIST, and the list is not the body

`EXPR foreach LIST` is the modifier whose trailing operand is a list rather
than a condition, and it is the only modifier form that still builds the
`enteriter`/`iter` machinery. Measured, its op stream differs from the
block `foreach` above by exactly the ops of `$_` against `my $x` -- `gvsv`
where the block form has `padsv` -- so unlike the postfix `while` directly
above, which builds no loop frame at all, this one IS the block form's
optree under a different spelling.

WHICH HALF IS THE BODY is what this case exists to pin, and the output is
what pins it. `EXPR foreach LIST` runs EXPR once per element of LIST.

The discrimination is in the ASYMMETRY of the source, which is why `@l`
holds three DIFFERENT elements and the body accumulates them in order.
Only the correct reading can print `abc`: a reader that took the halves
the other way round iterates the one-element list `$s .= $_` and runs `@l`
as its body, which appends nothing and prints the empty string. A case
whose two halves were interchangeable would pass either way round, and
three ordered characters is what forbids that.

Our parser read it the swapped way while scoring ZERO refusals. The tree
was right and the EMISSION was inverted -- `$s += $_ foreach 1..3`
re-emitted as `foreach ($s += $_) 1 .. 3`, the keyword moved to the front,
the body parenthesised as though it were a condition, the `;` dropped.
That is not a parse of anything, and no refusal count could see it: 251
lines of perl.git `t/` are this shape and every one of them scored clean.
Issue 01a0dfc7.

The body is `$s .= $_` rather than `print $_` because `print $_` is a
DIFFERENT open defect -- the parenless `print $VAR` that cannot yet be
told from `print FILEHANDLE LIST` -- and a case refusing for that reason
would measure the filehandle slot rather than the modifier. `.=` compiles
to tier 01's `multiconcat`, not to a `concat` no tier here claims.

The token fact counts, and the count is the falsifying half. This source
holds exactly ONE `foreach`, so a reader that split the statement in two at
the keyword -- the body as one statement and a second loop word for the
list -- produces a count this refuses. There is no negative fact for
`for`: a negative must name a spelling REACHABLE from the source, and this
source contains no `for`, so the claim could never fail and would assert
nothing.

```perl
my @l = ($ENV{A} // "a", "b", "c");
my $s = "";
$s .= $_ foreach @l;
print "$s\n";
```

```behavior
parses: yes
```

```output
abc
```

```tokens
one word whose text is "foreach"
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 27], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Proj, {index: 1}, [3]], # 7
  [Region, {head: 3}, [7]], # 8
  [Print, ~, [6], 8, Scalar], # 9
  [Return, {implicit: true}, [1], 9], # 10
  [EnvRead, {key: A}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 12
  [DefinedOr, ~, [11, 12], ~, Str], # 13
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 14
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 15
  [ArrayLiteral, {sigil: "@", symbol: l}, [13, 14, 15], ~, Array], # 16
  [MemStart], # 17
  [Count, ~, [16, 17], ~, Int], # 18
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 19
  [Phi, {region: 3}, [19, 24], ~, Int], # 20
  [NumGt, ~, [18, 20], 3, Boolean], # 21
  [Proj, {index: 0}, [3]], # 22
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 23
  [Add, ~, [20, 23], ~, Int], # 24
  [Subscript, {kind: array}, [16, 20, 17], ~, Scalar], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 26
  [Concat, ~, [4, 26], ~, Str]]} # 27
```

## `continue BLOCK` runs on `next` and not on `last`

There is NO `continue` op. The block is part of the loop it follows, and
the whole construct is two facts already in this tier: the `next` target on
`enterloop` points AT the continue block, and the `last` target points past
it. Measured, and the dump says it in one line:

    d  <{> enterloop(next->12 last->1c redo->e) v
    ...
    12     <0> pushmark s              <- the continue block starts HERE
    13     <0> padav[@s:3,10] lRM
    ...
    17     <0> unstack v
    1c <2> leaveloop vKP/2             <- and `last` lands HERE

So `next` reaches the continue block and `last` jumps over it. That is
the whole semantics, and it needs no op this tier does not already claim --
which is the contrast with `given`/`when`, whose five ops are unclaimed.

The OUTPUT is the discriminating half, and it discriminates in both
directions at once. `c2` with no `b2` is the pass `next` skipped, and the
continue block still ran. No `c4` at all is the pass `last` left, and the
continue block did not. A reader that attaches the block correctly but runs
it on every exit prints a `c4` this refuses; one that treats it as a second
bare block after the loop runs it ONCE, after the loop is over, and prints a
single trailing `c4` for the same reason. Three `c` entries for four passes
is what only the real semantics produces.

`while` is not the only form that takes one. Measured on 5.42.0, `until`
and the LIST form of `foreach` take one too, and a BARE block takes one --
a bare block is a loop that runs once, so it runs its continue once:

    { push @s,"b" } continue { push @s,"c" }          ->  b c

The C-style head is the exception, and perl REJECTS it rather than
accepting it with different semantics:

    $ perl -e 'for (my $i=0; $i<3; $i++) { } continue { }'
    syntax error at -e line 1, near "} continue "

The token facts count because the word is not always this construct. Bare
`continue;` is a DIFFERENT statement form -- the jump out of a `when` block,
which perl reports as `Can't "continue" outside a when block` -- so a reader
that took the word alone as a loop clause would read the wrong one. This
source holds exactly one `continue`, and it is followed by a block.

```perl
my $n = $ENV{N} // 5;
my $i = 0;
my @s;
while ($i < $n) {
    $i = $i + 1;
    next if $i == 2;
    last if $i == 4;
    push @s, "b$i";
} continue {
    push @s, "c$i";
}
print "@s\n";
```

```behavior
parses: yes
```

```output
b1 c1 c2 b3 c3
```

```tokens
one word whose text is "continue"
one word whose text is "next"
one word whose text is "last"
```

```ir
main::__PROGRAM__: {start: 0, returns: [38], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {sigil: "@", symbol: s}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Loop, {bound: each}, [0], 0], # 5
  [Phi, {region: 5}, [4, 8], ~, Int], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Add, ~, [6, 7], ~, Int], # 8
  [Coerce, {from_repr: Int, to_repr: Str}, [8], ~, Str], # 9
  [Concat, ~, [3, 9], ~, Str], # 10
  [MemStart], # 11
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 12
  [Concat, ~, [12, 9], ~, Str], # 13
  [Proj, {index: 0}, [5]], # 14
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 15
  [NumEq, ~, [8, 15], ~, Boolean], # 16
  [If, ~, [14, 16], 14], # 17
  [Proj, {index: 1}, [17]], # 18
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 19
  [NumEq, ~, [8, 19], ~, Boolean], # 20
  [If, ~, [18, 20], 18], # 21
  [Proj, {index: 1}, [21]], # 22
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 13, 11], 22, Int], # 23
  [Proj, {index: 0}, [17]], # 24
  [Region, {head: 17}, [24, 23]], # 25
  [Phi, {memory: true, predecessors: [24, 18], region: 25}, [11, 23], ~, Unknown], # 26
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 10, 26], 25, Int], # 27
  [Proj, {index: 1}, [5]], # 28
  [Proj, {index: 0}, [21]], # 29
  [Region, {head: 5}, [28, 29]], # 30
  [Phi, {memory: true, region: 30}, [27, 11], ~, Unknown], # 31
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [31], ~, Scalar], # 32
  [Coerce, {from_repr: Scalar, to_repr: Str}, [32], ~, Str], # 33
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [33, 2, 31], ~, Str], # 34
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 35
  [Concat, ~, [34, 35], ~, Str], # 36
  [Print, ~, [36], 30, Scalar], # 37
  [Return, {implicit: true}, [1], 37], # 38
  [EnvRead, {key: "N"}, ~, ~, Str], # 39
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 40
  [DefinedOr, ~, [39, 40], ~, Str], # 41
  [Coerce, {from_repr: Str, to_repr: Num}, [41], ~, Num], # 42
  [NumLt, ~, [6, 42], 5, Boolean], # 43
  [Phi, {region: 30}, [6, 8], ~, Int]]} # 44
```

## The seen-hash idiom

`$seen{$k}++` yields the element's value from before the store. A reader that reads the element where the value is used -- after the store -- skips every key. chalk's T2 type-narrowing pass is exactly this loop, and it narrowed nothing. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl.

```perl
my %seen;
my $out = "";
for my $k (qw(a a b a c)) {
    next if $seen{$k}++;
    $out .= $k;
}
print "$out\n";
```

```behavior
parses: yes
```

```output
abc
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 37], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Proj, {index: 1}, [3]], # 7
  [Region, {head: 3}, [7]], # 8
  [Print, ~, [6], 8, Scalar], # 9
  [Return, {implicit: true}, [1], 9], # 10
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 13
  [ArrayLiteral, ~, [11, 11, 12, 11, 13], ~, Array], # 14
  [MemStart], # 15
  [Phi, {memory: true, region: 3}, [15, 30], ~, Unknown], # 16
  [Count, ~, [14, 16], ~, Int], # 17
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 18
  [Phi, {region: 3}, [18, 27], ~, Int], # 19
  [NumGt, ~, [17, 19], 3, Boolean], # 20
  [Proj, {index: 0}, [3]], # 21
  [PadAccess, {sigil: "%", symbol: seen}, ~, ~, Unknown], # 22
  [Subscript, {kind: array}, [14, 19, 16], ~, Str], # 23
  [Subscript, {kind: hash}, [22, 23, 16], 21, Scalar], # 24
  [Phi, {memory: true, region: 8}, [16], ~, Unknown], # 25
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 26
  [Add, ~, [19, 26], ~, Int], # 27
  [Increment, ~, [24], ~, Scalar], # 28
  [Subscript, {kind: hash}, [22, 23], ~, Scalar], # 29
  [Assign, ~, [29, 28], 24, Scalar], # 30
  [DefinedOr, ~, [24, 18], ~, Scalar], # 31
  [Concat, ~, [4, 23], ~, Str], # 32
  [If, ~, [30, 31], 30], # 33
  [Proj, {index: 0}, [33]], # 34
  [Proj, {index: 1}, [33]], # 35
  [Region, {head: 33}, [34, 35]], # 36
  [Phi, {predecessors: [34, 35], region: 36}, [4, 32], ~, Str], # 37
  [Count, ~, [14, 15], ~, Int]]} # 38
```

## A post-increment of undef yields 0

`pp_postinc` sets its result to 0 when the old value is not defined. A post-decrement does not, and a string comes back as it was. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl.

```perl
my ($x, $y, %h);
my $p = $x++;
my $q = $y--;
my $r = $h{k}++;
my $s = "aa";
my $t = $s++;
print join(",", map { defined $_ ? "[$_]" : "undef" } $p, $q, $r, $t), "\n";
```

```behavior
parses: yes
```

```output
[0],undef,[0],[aa]
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [PadAccess, {sigil: "%", symbol: h}, ~, ~, Unknown], # 4
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 5
  [Subscript, {kind: hash}, [4, 5], ~, Scalar], # 6
  [MemStart], # 7
  [Subscript, {kind: hash}, [4, 5, 7], 0, Scalar], # 8
  [Increment, ~, [8], ~, Scalar], # 9
  [Assign, ~, [6, 9], 8, Scalar], # 10
  [Loop, {bound: entry}, [10], 10], # 11
  [Phi, {region: 11}, [3, 44], ~, Array], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [2, 12, 10], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Proj, {index: 1}, [11]], # 15
  [Region, {head: 11}, [15]], # 16
  [Print, ~, [13, 14], 16, Scalar], # 17
  [Return, {implicit: true}, [1], 17], # 18
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 19
  [DefinedOr, ~, [8, 19], ~, Scalar], # 20
  [Increment, ~, [1], ~, Scalar], # 21
  [DefinedOr, ~, [1, 19], ~, Scalar], # 22
  [Coerce, {from_repr: Undef, to_repr: Num}, [1], ~, Num], # 23
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 24
  [Subtract, ~, [23, 24], ~, Num], # 25
  [Constant, {const_type: string, value: aa}, ~, ~, Str], # 26
  [DefinedOr, ~, [26, 19], ~, Scalar], # 27
  [ArrayLiteral, ~, [22, 1, 20, 27], ~, List], # 28
  [Phi, {region: 11}, [19, 41], ~, Int], # 29
  [Subscript, {kind: array}, [28, 29, 10], ~, Scalar], # 30
  [Defined, ~, [30], ~, Boolean], # 31
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 32
  [Coerce, {from_repr: Scalar, to_repr: Str}, [30], ~, Str], # 33
  [Concat, ~, [32, 33], ~, Str], # 34
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 35
  [Concat, ~, [34, 35], ~, Str], # 36
  [TernaryExpr, ~, [31, 36, 1], ~, Scalar], # 37
  [Count, ~, [28, 10], ~, Int], # 38
  [NumGt, ~, [38, 29], 11, Boolean], # 39
  [Proj, {index: 0}, [11]], # 40
  [Add, ~, [29, 24], ~, Int], # 41
  [Constant, {const_type: string, value: undef}, ~, ~, Str], # 42
  [TernaryExpr, ~, [31, 36, 42], ~, Str], # 43
  [ListAppend, {collector: map}, [12, 43], ~, Array], # 44
  [Increment, ~, [26], ~, Scalar]]} # 45
```

## Named scalars in a map, grep or foreach list

Each list element is aliased to `$_` or the loop variable, so perl flags the operand as a modifiable lvalue. It is still read for its value. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl.

```perl
my $p = 1 + time() * 0;
my $q = 2 + time() * 0;
my $o = "";
for my $v ($p, $q) { $o .= "[$v]" }
print join(",", map { "[$_]" } $p, $q), " ", join(",", grep { $_ > 1 } $p, $q), " $o\n";
```

```behavior
parses: yes
```

```output
[1],[2] 2 [1][2]
```

```ir
main::__PROGRAM__: {start: 0, returns: [26], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [Loop, {bound: entry}, [0], 0], # 4
  [Proj, {index: 1}, [4]], # 5
  [Region, {head: 4}, [5]], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [3, 51], ~, Array], # 8
  [MemStart], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [2, 8, 9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [ArrayLiteral, ~, ~, ~, Array], # 12
  [Proj, {index: 1}, [7]], # 13
  [Region, {head: 7}, [13]], # 14
  [Loop, {bound: entry}, [14], 14], # 15
  [Phi, {region: 15}, [12, 59], ~, Array], # 16
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [2, 16, 9], ~, Str], # 17
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 18
  [Phi, {region: 4}, [18, 66], ~, Str], # 19
  [Concat, ~, [11, 19], ~, Str], # 20
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 21
  [Concat, ~, [20, 21], ~, Str], # 22
  [Proj, {index: 1}, [15]], # 23
  [Region, {head: 15}, [23]], # 24
  [Print, ~, [10, 11, 17, 22], 24, Scalar], # 25
  [Return, {implicit: true}, [1], 25], # 26
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 27
  [Call, {dispatch_kind: builtin, name: time, param_names: []}, ~, ~, Unknown], # 28
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 29
  [Multiply, ~, [28, 29], ~, Unknown], # 30
  [Add, ~, [27, 30], ~, Unknown], # 31
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 32
  [Call, {dispatch_kind: builtin, name: time, param_names: []}, ~, ~, Unknown], # 33
  [Multiply, ~, [33, 29], ~, Unknown], # 34
  [Add, ~, [32, 34], ~, Unknown], # 35
  [ArrayLiteral, ~, [31, 35], ~, Array], # 36
  [Count, ~, [36, 9], ~, Int], # 37
  [Phi, {region: 4}, [29, 41], ~, Int], # 38
  [NumGt, ~, [37, 38], 4, Boolean], # 39
  [Proj, {index: 0}, [4]], # 40
  [Add, ~, [38, 27], ~, Int], # 41
  [Subscript, {kind: array}, [36, 38, 9], ~, Scalar], # 42
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 43
  [ArrayLiteral, ~, [31, 35], ~, List], # 44
  [Phi, {region: 7}, [29, 68], ~, Int], # 45
  [Subscript, {kind: array}, [44, 45, 9], ~, Scalar], # 46
  [Coerce, {from_repr: Unknown, to_repr: Str}, [46], ~, Str], # 47
  [Concat, ~, [43, 47], ~, Str], # 48
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 49
  [Concat, ~, [48, 49], ~, Str], # 50
  [ListAppend, {collector: map}, [8, 50], ~, Array], # 51
  [Count, ~, [44, 9], ~, Int], # 52
  [ArrayLiteral, ~, [31, 35], ~, List], # 53
  [Count, ~, [53, 9], ~, Int], # 54
  [Phi, {region: 15}, [29, 69], ~, Int], # 55
  [Subscript, {kind: array}, [53, 55, 9], ~, Scalar], # 56
  [Coerce, {from_repr: Scalar, to_repr: Num}, [56], ~, Num], # 57
  [NumGt, ~, [57, 27], ~, Boolean], # 58
  [ListAppend, {collector: grep}, [16, 56, 58], ~, Array], # 59
  [Coerce, {from_repr: Unknown, to_repr: Str}, [42], ~, Str], # 60
  [NumGt, ~, [52, 45], 7, Boolean], # 61
  [Proj, {index: 0}, [7]], # 62
  [NumGt, ~, [54, 55], 15, Boolean], # 63
  [Concat, ~, [19, 43], ~, Str], # 64
  [Concat, ~, [64, 60], ~, Str], # 65
  [Concat, ~, [65, 49], ~, Str], # 66
  [Proj, {index: 0}, [15]], # 67
  [Add, ~, [45, 27], ~, Int], # 68
  [Add, ~, [55, 27], ~, Int]]} # 69
```
