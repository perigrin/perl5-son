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
main::__PROGRAM__: {start: 0, returns: [101], nodes: [
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
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 16
  [Coerce, {from_repr: Int, to_repr: Num}, [16], ~, Num], # 17
  [EnvRead, {key: X}, ~, ~, Str], # 18
  [DefinedOr, ~, [18, 8], ~, Str], # 19
  [Coerce, {from_repr: Str, to_repr: Num}, [19], ~, Num], # 20
  [Divide, ~, [17, 20], ~, Num], # 21
  [Constant, {const_type: string, value: "-v"}, ~, ~, Str], # 22
  [EnvRead, {key: "N"}, ~, ~, Str], # 23
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 24
  [DefinedOr, ~, [23, 24], ~, Str], # 25
  [Coerce, {from_repr: Str, to_repr: Num}, [25], ~, Num], # 26
  [Add, ~, [26, 7], ~, Num], # 27
  [Coerce, {from_repr: Unknown, to_repr: Str}, [27], ~, Str], # 28
  [Concat, ~, [22, 28], ~, Str], # 29
  [Constant, {const_type: string, value: "-d"}, ~, ~, Str], # 30
  [Add, ~, [8, 7], ~, Int], # 31
  [Constant, {const_type: string, value: if}, ~, ~, Str], # 32
  [If, ~, [0, 25], 0], # 33
  [Proj, {index: 0}, [33]], # 34
  [Print, ~, [32], 34, Scalar], # 35
  [Constant, {const_type: string, value: else}, ~, ~, Str], # 36
  [Proj, {index: 1}, [33]], # 37
  [Print, ~, [36], 37, Scalar], # 38
  [Region, {head: 33}, [35, 38]], # 39
  [If, ~, [39, 25], 39], # 40
  [Proj, {index: 0}, [40]], # 41
  [Constant, {const_type: string, value: "-unless"}, ~, ~, Str], # 42
  [Proj, {index: 1}, [40]], # 43
  [Print, ~, [42], 43, Scalar], # 44
  [Region, {head: 40}, [41, 44]], # 45
  [Loop, {bound: each}, [45], 45], # 46
  [Proj, {index: 1}, [46]], # 47
  [Proj, {index: 0}, [46]], # 48
  [Phi, {region: 46}, [8, 110], ~, Int], # 49
  [NumGt, ~, [49, 7], ~, Boolean], # 50
  [If, ~, [48, 50], 48], # 51
  [Proj, {index: 0}, [51]], # 52
  [Region, {head: 46}, [47, 52]], # 53
  [Loop, {bound: each}, [53], 53], # 54
  [Proj, {index: 1}, [54]], # 55
  [Region, {head: 54}, [55]], # 56
  [Loop, {bound: each}, [56], 56], # 57
  [Phi, {region: 57}, [31, 112], ~, Int], # 58
  [Coerce, {from_repr: Int, to_repr: Str}, [58], ~, Str], # 59
  [Concat, ~, [30, 59], ~, Str], # 60
  [Proj, {index: 1}, [57]], # 61
  [Region, {head: 57}, [61]], # 62
  [Print, ~, [60], 62, Scalar], # 63
  [Print, ~, [29], 63, Scalar], # 64
  [Region, {eval_entry: 64}, [64]], # 65
  [Phi, {region: 65}, [21, 1], ~, Scalar], # 66
  [Constant, {const_type: string, value: t}, ~, ~, Str], # 67
  [DefinedOr, ~, [66, 67], ~, Scalar], # 68
  [Coerce, {from_repr: Unknown, to_repr: Str}, [68], ~, Str], # 69
  [Concat, ~, [15, 69], ~, Str], # 70
  [Print, ~, [70], 65, Scalar], # 71
  [Unwind, ~, [14], 71], # 72
  [Region, {eval_entry: 71}, [72]], # 73
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [13], 73, Scalar], # 74
  [Coerce, {from_repr: Unknown, to_repr: Str}, [74], ~, Str], # 75
  [Concat, ~, [12, 75], ~, Str], # 76
  [Print, ~, [76], 74, Scalar], # 77
  [EnvRead, {key: R}, ~, ~, Str], # 78
  [DefinedOr, ~, [78, 8], ~, Str], # 79
  [If, ~, [77, 79], 77], # 80
  [Proj, {index: 1}, [80]], # 81
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 82
  [Proj, {index: 0}, [80]], # 83
  [Call, {dispatch_kind: builtin, name: exit, param_names: []}, [82], 83, Unknown], # 84
  [Region, {head: 80}, [81, 84]], # 85
  [Print, ~, [11], 85, Scalar], # 86
  [Print, ~, [3, 10], 86, Scalar], # 87
  [Loop, {bound: each}, [87], 87], # 88
  [Proj, {index: 1}, [88]], # 89
  [Region, {head: 88}, [89]], # 90
  [Loop, {bound: entry}, [90], 90], # 91
  [Proj, {index: 1}, [91]], # 92
  [Region, {head: 91}, [92]], # 93
  [If, ~, [93, 25], 93], # 94
  [Proj, {index: 1}, [94]], # 95
  [Constant, {const_type: string, value: "-p"}, ~, ~, Str], # 96
  [Proj, {index: 0}, [94]], # 97
  [Print, ~, [96], 97, Scalar], # 98
  [Region, {head: 94}, [95, 98]], # 99
  [Print, ~, [2], 99, Scalar], # 100
  [Return, ~, [1], 100], # 101
  [NumLt, ~, [49, 26], 46, Boolean], # 102
  [Add, ~, [26, 24], ~, Num], # 103
  [NumLt, ~, [58, 26], 57, Boolean], # 104
  [Phi, {region: 54}, [49, 108], ~, Int], # 105
  [NumGe, ~, [105, 103], ~, Boolean], # 106
  [NumLt, ~, [105, 103], 54, Boolean], # 107
  [Add, ~, [105, 7], ~, Int], # 108
  [NumGt, ~, [108, 27], ~, Boolean], # 109
  [Add, ~, [49, 7], ~, Int], # 110
  [Coerce, {from_repr: Int, to_repr: Str}, [49], ~, Str], # 111
  [Add, ~, [58, 7], ~, Int], # 112
  [Phi, {region: 88}, [8, 115], ~, Int], # 113
  [NumLt, ~, [113, 7], 88, Boolean], # 114
  [Add, ~, [113, 7], ~, Int], # 115
  [Phi, {region: 91}, [8, 117], ~, Int], # 116
  [Add, ~, [116, 7], ~, Int], # 117
  [Proj, {index: 0}, [54]], # 118
  [If, ~, [118, 109], 118], # 119
  [Proj, {index: 0}, [57]], # 120
  [Constant, {const_type: string, value: "-w"}, ~, ~, Str], # 121
  [Concat, ~, [121, 111], ~, Str], # 122
  [Coerce, {from_repr: Int, to_repr: Str}, [108], ~, Str], # 123
  [Proj, {index: 0}, [119]], # 124
  [Proj, {index: 1}, [119]], # 125
  [Proj, {index: 0}, [91]], # 126
  [Loop, {bound: each}, [126], 126], # 127
  [Coerce, {from_repr: Unknown, to_repr: Boolean}, [79], 127, Boolean], # 128
  [Coerce, {from_repr: Int, to_repr: Str}, [113], ~, Str], # 129
  [EnvRead, {key: A}, ~, ~, Str], # 130
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 131
  [DefinedOr, ~, [130, 131], ~, Str], # 132
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 133
  [ArrayLiteral, {sigil: "@", symbol: l}, [132, 133], ~, Array], # 134
  [Count, ~, [134, 13], ~, Int], # 135
  [NumGt, ~, [135, 116], 91, Boolean], # 136
  [Subscript, {kind: array}, [134, 116, 13], ~, Scalar], # 137
  [Proj, {index: 1}, [51]], # 138
  [Print, ~, [122], 138, Scalar], # 139
  [Constant, {const_type: string, value: "-u"}, ~, ~, Str], # 140
  [Concat, ~, [140, 123], ~, Str], # 141
  [Proj, {index: 0}, [88]], # 142
  [Print, ~, [141], 125, Scalar], # 143
  [Region, {head: 119}, [124, 143]], # 144
  [Constant, {const_type: string, value: "-c"}, ~, ~, Str], # 145
  [Concat, ~, [145, 129], ~, Str], # 146
  [Coerce, {from_repr: Unknown, to_repr: Str}, [137], ~, Str], # 147
  [Print, ~, [146], 142, Scalar], # 148
  [Proj, {index: 0}, [127]], # 149
  [Proj, {index: 1}, [127]], # 150
  [Constant, {const_type: string, value: "-f"}, ~, ~, Str], # 151
  [Concat, ~, [151, 147], ~, Str], # 152
  [Region, {head: 127}, [150]], # 153
  [Print, ~, [152], 153, Scalar]]} # 154
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
