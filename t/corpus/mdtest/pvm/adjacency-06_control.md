# Every control construct, each beside another

One body holding every construct this tier introduces, each adjacent to
another -- and adjacent to tier 05's blocks, which is what this tier
depends on.

**Tier 06 control.** Introduces `cond_expr`, `die`, `enteriter`,
`entertry`, `exit`, `goto`, `iter`, `last`, `leavetry`, `next`, `redo`,
`time`, `unstack`. Depends on 05_scoping.

WHY A MIXTURE NEEDS ITS OWN CASE. The tier's other cases are one construct
each, which is what makes them diagnosable. That same property is why a
corpus of such cases cannot reach an ADJACENCY bug: a parser that handles
each construct alone and mis-handles a pair goes green over the pair.

The pairs this tier has to worry about are specific, and they are why the
order below is the order it is:

- `if`/`else` immediately before a postfix `unless`, because `else` and a
  statement modifier both end a statement without a semicolon being where
  the reader expects one.
- `while` with a postfix `last` inside it, so a jump statement sits
  directly inside a loop body rather than in a case of its own.
- `until` immediately after `while`, because the two differ by one op and
  a parser that shares their production can lose the difference only when
  both are present.
- `do BLOCK while` immediately after the block `while` and `until`,
  because the post-test loop is the one that emits `unstack` with no
  `enterloop`.
- `do BLOCK` as an expression immediately after `do BLOCK while`, which is
  the sharpest pair here. The two spell the same two tokens and open the
  same brace, and what decides the production is what FOLLOWS the closing
  brace. A parser that commits at the `do` handles whichever one it
  guessed and mis-handles the other, and only their adjacency catches it.
- `eval BLOCK` immediately after `do BLOCK`, because both put a block
  where an expression goes with no comma after it, and both are the
  position where perl's own `{` heuristic can answer "anonymous hash".
- C-style `for` immediately before `foreach`, because these are the same
  keyword over two unrelated optrees and the disambiguation happens at the
  open paren.
- `goto LABEL` last, with a dead statement between it and its label, so
  the label is adjacent to a statement it is not attached to.

## The whole tier in one body

`redo` is guarded by `$ENV{R}`, false at run time: the op compiles and
sits in the loop body next to `print`, which is the adjacency, without
making the loop non-terminating. The `exit` is a DEAD BRANCH for the same
reason -- `exit 3 if $r` -- because an `exit` that fired would end the
program before `goto DONE` and the body would measure nothing after it. An
`eval` does NOT trap it: measured, `eval { exit 0 }` exits.

The `eval` here traps a division by zero rather than a `die`, for the
budget reason the `eval BLOCK` case records.

The output runs to two lines because `die`'s message ends in a newline,
which is not decoration: a `$@` that does not end in one carries the file
and line number perl appends, and the file here is the harness's temp
path, which differs every run. `-Dx` is the trapped message and the
newline is its own.

The `-u3` is the one field worth explaining, because it looks like an
off-by-one and is not. `$i` is 2 when the `while` exits; the `until` runs
it to 4 and prints only on the pass where `$i` is 3, since the `next`
skips the rest. One line of output from that loop is the point -- a loop
that printed nothing would still emit its ops and the case would measure
the same thing while reading as a bug.

The three fields the block-valued group adds each discriminate:

- `-d2`: the post-test loop ran its body to `$n`. A `while` in its place
  with the same initial `$k` would reach the same 2, so this field is the
  WEAK one -- the `do BLOCK while` case carries the strong pin, where a
  false condition still produces one pass. Here the value is adjacency,
  not discrimination.
- `-v3`: the block-as-expression yielded its LAST statement, `$n + 1`, not
  the `$n` its first statement bound and not a hash reference. A parser
  that read `{ my $t = $n; $t + 1 }` as an anonymous hash would print
  `HASH(0x...)` here.
- `-et`: the eval frame trapped the division by zero. Without the frame
  the program aborts before any of the output after it is printed, so
  every field to its right is also evidence the frame held.

```perl
my $n = $ENV{N} // 2;
my $r = $ENV{R} // 0;
my @l = ($ENV{A} // "a", "b");
if ($n) { print "if" } else { print "else" }
print "-unless" unless $n;
my $i = 0;
while ($i < $n) { last if $i > 1; print "-w$i"; $i = $i + 1 }
until ($i >= $n + 2) { $i = $i + 1; next if $i > $n + 1; print "-u$i" }
my $k = 0;
do { $k = $k + 1 } while $k < $n;
print "-d$k";
my $v = do { my $t = $n; $t + 1 };
print "-v$v";
my $e = eval { 10 / ($ENV{X} // 0) } // "t";
print "-e$e";
eval { die "x\n" };
print "-D$@";
exit 3 if $r;
print "-X";
my $t = time;
print "-t", $t > 1000000000 ? 1 : 0;
for (my $j = 0; $j < 1; $j = $j + 1) { print "-c$j" }
foreach my $x (@l) { redo if $r; print "-f$x" }
print "-p" if $n;
goto DONE;
print "-skipped";
DONE:
print "\n";
```

```behavior
parses: yes
```

```output
if-w0-w1-u3-d2-v3-et-Dx
-X-t1-c0-fa-fb-p
```

```ir
main::__PROGRAM__: {start: 0, returns: [96], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "-t"}, ~, ~, Str], # 3
  [Call, {dispatch_kind: builtin, name: time, param_names: []}, ~, ~, Unknown], # 4
  [Constant, {const_type: integer, value: "1000000000"}, ~, ~, Int], # 5
  [NumGt, ~, [4, 5], ~, Boolean], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [TernaryExpr, ~, [6, 7, 8], ~, Int], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "-X"}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: "-D"}, ~, ~, Str], # 12
  [MemStart], # 13
  [Constant, {const_type: string, value: "x\n"}, ~, ~, Str], # 14
  [Constant, {const_type: string, value: "-e"}, ~, ~, Str], # 15
  [EnvRead, {key: X}, ~, ~, Str], # 16
  [Constant, {const_type: string, value: "-v"}, ~, ~, Str], # 17
  [EnvRead, {key: "N"}, ~, ~, Str], # 18
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 19
  [DefinedOr, ~, [18, 19], ~, Str], # 20
  [Coerce, {from_repr: Str, to_repr: Num}, [20], ~, Num], # 21
  [Add, ~, [21, 7], ~, Num], # 22
  [Coerce, {from_repr: Unknown, to_repr: Str}, [22], ~, Str], # 23
  [Concat, ~, [17, 23], ~, Str], # 24
  [Constant, {const_type: string, value: "-d"}, ~, ~, Str], # 25
  [Add, ~, [8, 7], ~, Int], # 26
  [Constant, {const_type: string, value: if}, ~, ~, Str], # 27
  [If, ~, [0, 20], 0], # 28
  [Proj, {index: 0}, [28]], # 29
  [Print, ~, [27], 29, Scalar], # 30
  [Constant, {const_type: string, value: else}, ~, ~, Str], # 31
  [Proj, {index: 1}, [28]], # 32
  [Print, ~, [31], 32, Scalar], # 33
  [Region, {head: 28}, [30, 33]], # 34
  [If, ~, [34, 20], 34], # 35
  [Proj, {index: 0}, [35]], # 36
  [Constant, {const_type: string, value: "-unless"}, ~, ~, Str], # 37
  [Proj, {index: 1}, [35]], # 38
  [Print, ~, [37], 38, Scalar], # 39
  [Region, {head: 35}, [36, 39]], # 40
  [Loop, {bound: each}, [40], 40], # 41
  [Proj, {index: 1}, [41]], # 42
  [Proj, {index: 0}, [41]], # 43
  [Phi, {region: 41}, [8, 105], ~, Int], # 44
  [NumGt, ~, [44, 7], ~, Boolean], # 45
  [If, ~, [43, 45], 43], # 46
  [Proj, {index: 0}, [46]], # 47
  [Region, {head: 41}, [42, 47]], # 48
  [Loop, {bound: each}, [48], 48], # 49
  [Proj, {index: 1}, [49]], # 50
  [Region, {head: 49}, [50]], # 51
  [Loop, {bound: each}, [51], 51], # 52
  [Phi, {region: 52}, [26, 107], ~, Int], # 53
  [Coerce, {from_repr: Int, to_repr: Str}, [53], ~, Str], # 54
  [Concat, ~, [25, 54], ~, Str], # 55
  [Proj, {index: 1}, [52]], # 56
  [Region, {head: 52}, [56]], # 57
  [Print, ~, [55], 57, Scalar], # 58
  [Print, ~, [24], 58, Scalar], # 59
  [Region, {eval_entry: 59}, [59]], # 60
  [Phi, {region: 60}, [16, 1], ~, Scalar], # 61
  [Constant, {const_type: string, value: t}, ~, ~, Str], # 62
  [DefinedOr, ~, [61, 62], ~, Scalar], # 63
  [Coerce, {from_repr: Unknown, to_repr: Str}, [63], ~, Str], # 64
  [Concat, ~, [15, 64], ~, Str], # 65
  [Print, ~, [65], 60, Scalar], # 66
  [Unwind, ~, [14], 66], # 67
  [Region, {eval_entry: 66}, [67]], # 68
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [13], 68, Scalar], # 69
  [Coerce, {from_repr: Unknown, to_repr: Str}, [69], ~, Str], # 70
  [Concat, ~, [12, 70], ~, Str], # 71
  [Print, ~, [71], 69, Scalar], # 72
  [EnvRead, {key: R}, ~, ~, Str], # 73
  [DefinedOr, ~, [73, 8], ~, Str], # 74
  [If, ~, [72, 74], 72], # 75
  [Proj, {index: 1}, [75]], # 76
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 77
  [Proj, {index: 0}, [75]], # 78
  [Call, {dispatch_kind: builtin, name: exit, param_names: []}, [77], 78, Unknown], # 79
  [Region, {head: 75}, [76, 79]], # 80
  [Print, ~, [11], 80, Scalar], # 81
  [Print, ~, [3, 10], 81, Scalar], # 82
  [Loop, {bound: each}, [82], 82], # 83
  [Proj, {index: 1}, [83]], # 84
  [Region, {head: 83}, [84]], # 85
  [Loop, {bound: entry}, [85], 85], # 86
  [Proj, {index: 1}, [86]], # 87
  [Region, {head: 86}, [87]], # 88
  [If, ~, [88, 20], 88], # 89
  [Proj, {index: 1}, [89]], # 90
  [Constant, {const_type: string, value: "-p"}, ~, ~, Str], # 91
  [Proj, {index: 0}, [89]], # 92
  [Print, ~, [91], 92, Scalar], # 93
  [Region, {head: 89}, [90, 93]], # 94
  [Print, ~, [2], 94, Scalar], # 95
  [Return, ~, [1], 95], # 96
  [NumLt, ~, [44, 21], 41, Boolean], # 97
  [Add, ~, [21, 19], ~, Num], # 98
  [NumLt, ~, [53, 21], 52, Boolean], # 99
  [Phi, {region: 49}, [44, 103], ~, Int], # 100
  [NumGe, ~, [100, 98], ~, Boolean], # 101
  [NumLt, ~, [100, 98], 49, Boolean], # 102
  [Add, ~, [100, 7], ~, Int], # 103
  [NumGt, ~, [103, 22], ~, Boolean], # 104
  [Add, ~, [44, 7], ~, Int], # 105
  [Coerce, {from_repr: Int, to_repr: Str}, [44], ~, Str], # 106
  [Add, ~, [53, 7], ~, Int], # 107
  [Phi, {region: 83}, [8, 110], ~, Int], # 108
  [NumLt, ~, [108, 7], 83, Boolean], # 109
  [Add, ~, [108, 7], ~, Int], # 110
  [Phi, {region: 86}, [8, 112], ~, Int], # 111
  [Add, ~, [111, 7], ~, Int], # 112
  [Proj, {index: 0}, [49]], # 113
  [If, ~, [113, 104], 113], # 114
  [Proj, {index: 0}, [52]], # 115
  [Constant, {const_type: string, value: "-w"}, ~, ~, Str], # 116
  [Concat, ~, [116, 106], ~, Str], # 117
  [Coerce, {from_repr: Int, to_repr: Str}, [103], ~, Str], # 118
  [Proj, {index: 0}, [114]], # 119
  [Proj, {index: 1}, [114]], # 120
  [Proj, {index: 0}, [86]], # 121
  [Loop, {bound: each}, [121], 121], # 122
  [Coerce, {from_repr: Unknown, to_repr: Boolean}, [74], 122, Boolean], # 123
  [Coerce, {from_repr: Int, to_repr: Str}, [108], ~, Str], # 124
  [EnvRead, {key: A}, ~, ~, Str], # 125
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 126
  [DefinedOr, ~, [125, 126], ~, Str], # 127
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 128
  [ArrayLiteral, {sigil: "@", symbol: l}, [127, 128], ~, Array], # 129
  [Count, ~, [129, 13], ~, Int], # 130
  [NumGt, ~, [130, 111], 86, Boolean], # 131
  [Subscript, ~, [129, 111, 13], ~, Scalar], # 132
  [Proj, {index: 1}, [46]], # 133
  [Print, ~, [117], 133, Scalar], # 134
  [Constant, {const_type: string, value: "-u"}, ~, ~, Str], # 135
  [Concat, ~, [135, 118], ~, Str], # 136
  [Proj, {index: 0}, [83]], # 137
  [Print, ~, [136], 120, Scalar], # 138
  [Region, {head: 114}, [119, 138]], # 139
  [Constant, {const_type: string, value: "-c"}, ~, ~, Str], # 140
  [Concat, ~, [140, 124], ~, Str], # 141
  [Coerce, {from_repr: Unknown, to_repr: Str}, [132], ~, Str], # 142
  [Print, ~, [141], 137, Scalar], # 143
  [Proj, {index: 0}, [122]], # 144
  [Proj, {index: 1}, [122]], # 145
  [Constant, {const_type: string, value: "-f"}, ~, ~, Str], # 146
  [Concat, ~, [146, 142], ~, Str], # 147
  [Region, {head: 122}, [145]], # 148
  [Print, ~, [147], 148, Scalar]]} # 149
```

## Two `next` guards in a row, where the first arm carries the second

Two consecutive statement-modifier `next` guards inside one loop body.

WHY TWO AND NOT ONE. One `next if` guard is a single conditional jump and
every implementation handles it. TWO make the first guard's FALL-THROUGH ARM
carry the second, so an implementation that ends the first arm without
threading the rest of the body into it loses the second guard silently -- the
loop then runs an iteration it should have skipped, with no diagnostic. That
is an adjacency property: each guard alone is fine and the pair is not.

Measured on B::SoN, which is why this case exists: one guard translates, two
refuse. Reduced from perl's own t/cmd/switch.t:5, which wraps the same shape
in a sub with a `continue` block -- dropped here because `shift` would pin the
case to tier 11 and bury a control-flow finding in the OO tier.

The output is the assertion: 2 and 4 must be ABSENT, and an implementation
that loses the second guard prints 4.

```perl
my @out;
for my $i (1 .. 6) {
    next if $i == 2;
    next if $i == 4;
    push @out, $i;
}
print "@out\n";
```

```behavior
parses: yes
```

```output
1 3 5 6
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [2], ~, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [PadAccess, {sigil: "@", symbol: out}, ~, ~, Unknown], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [Loop, {bound: entry}, [0], 0], # 9
  [Proj, {index: 1}, [9]], # 10
  [Region, {head: 9}, [10]], # 11
  [Print, ~, [8], 11, Scalar], # 12
  [Return, ~, [1], 12], # 13
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Phi, {region: 9}, [15, 22], ~, Int], # 16
  [NumGt, ~, [14, 16], 9, Boolean], # 17
  [Proj, {index: 0}, [9]], # 18
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 19
  [NumEq, ~, [16, 19], ~, Boolean], # 20
  [If, ~, [18, 20], 18], # 21
  [Add, ~, [16, 15], ~, Int], # 22
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 23
  [NumEq, ~, [16, 23], ~, Boolean], # 24
  [Proj, {index: 1}, [21]], # 25
  [If, ~, [25, 24], 25], # 26
  [Proj, {index: 1}, [26]], # 27
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [5, 16], 27, Unknown], # 28
  [Proj, {index: 0}, [21]], # 29
  [Proj, {index: 0}, [26]], # 30
  [Region, {head: 26}, [30, 28]], # 31
  [Region, {head: 21}, [29, 31]]]} # 32
```
