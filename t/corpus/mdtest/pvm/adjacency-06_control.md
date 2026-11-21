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
main::__PROGRAM__: {start: 0, returns: [108], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "-t"}, ~, ~, Str], # 3
  [Call, {dispatch_kind: builtin, name: time, param_names: []}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "1000000000"}, ~, ~, Int], # 5
  [NumGt, ~, [4, 5], ~, Boolean], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [TernaryExpr, ~, [6, 7, 8], ~, Int], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "-X"}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: "-D"}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: "x\n"}, ~, ~, Str], # 13
  [MemStart], # 14
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 14], # 15
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 16
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
  [Print, ~, [27], 29, "Maybe[Boolean]"], # 30
  [Constant, {const_type: string, value: else}, ~, ~, Str], # 31
  [Proj, {index: 1}, [28]], # 32
  [Print, ~, [31], 32, "Maybe[Boolean]"], # 33
  [Region, {head: 28}, [30, 33]], # 34
  [If, ~, [34, 20], 34], # 35
  [Proj, {index: 0}, [35]], # 36
  [Constant, {const_type: string, value: "-unless"}, ~, ~, Str], # 37
  [Proj, {index: 1}, [35]], # 38
  [Print, ~, [37], 38, "Maybe[Boolean]"], # 39
  [Region, {head: 35}, [36, 39]], # 40
  [Loop, {bound: each}, [40], 40], # 41
  [Proj, {index: 1}, [41]], # 42
  [Proj, {index: 0}, [41]], # 43
  [Phi, {region: 41}, [8, 130], ~, Int], # 44
  [NumGt, ~, [44, 7], ~, Boolean], # 45
  [If, ~, [43, 45], 43], # 46
  [Proj, {index: 0}, [46]], # 47
  [Region, {head: 41}, [42, 47]], # 48
  [Loop, {bound: each}, [48], 48], # 49
  [Proj, {index: 1}, [49]], # 50
  [Region, {head: 49}, [50]], # 51
  [Loop, {bound: each}, [51], 51], # 52
  [Phi, {region: 52}, [26, 132], ~, Int], # 53
  [Coerce, {from_repr: Int, to_repr: Str}, [53], ~, Str], # 54
  [Concat, ~, [25, 54], ~, Str], # 55
  [Proj, {index: 1}, [52]], # 56
  [Region, {head: 52}, [56]], # 57
  [Print, ~, [55], 57, "Maybe[Boolean]"], # 58
  [Print, ~, [24], 58, "Maybe[Boolean]"], # 59
  [EntryWrite, ~, [15, 16], 59, Unknown, 14, true], # 60
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 61
  [Coerce, {from_repr: Int, to_repr: Num}, [61], ~, Num], # 62
  [EnvRead, {key: X}, ~, ~, Str], # 63
  [DefinedOr, ~, [63, 8], ~, Str], # 64
  [Coerce, {from_repr: Str, to_repr: Num}, [64], ~, Num], # 65
  [Divide, {eval_id: 1, file: "/tmp/osrpJFXK1Z/case.pl", line: 14}, [62, 65], 60, Num], # 66
  [Region, {eval_entry: 59, eval_id: 1}, [66]], # 67
  [Phi, {memory: true, region: 67}, [60], ~, Unknown], # 68
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 68], # 69
  [Constant, {const_type: string, value: "-e"}, ~, ~, Str], # 70
  [Phi, {region: 67}, [66, 1], ~, "Maybe[Num]"], # 71
  [Constant, {const_type: string, value: t}, ~, ~, Str], # 72
  [DefinedOr, ~, [71, 72], ~, "Maybe[Str]"], # 73
  [Coerce, {from_repr: Unknown, to_repr: Str}, [73], ~, Str], # 74
  [Concat, ~, [70, 74], ~, Str], # 75
  [Print, ~, [75], 67, "Maybe[Boolean]"], # 76
  [EntryWrite, ~, [69, 16], 76, Unknown, 68, true], # 77
  [Unwind, {eval_id: 2, file: "/tmp/osrpJFXK1Z/case.pl", line: 16}, [13], 77, ~, 77], # 78
  [Region, {eval_entry: 76, eval_id: 2}, [78]], # 79
  [Phi, {memory: true, region: 79}, [77], ~, Unknown], # 80
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 79, Scalar, 80], # 81
  [Coerce, {from_repr: Unknown, to_repr: Str}, [81], ~, Str], # 82
  [Concat, ~, [12, 82], ~, Str], # 83
  [Print, ~, [83], 81, "Maybe[Boolean]"], # 84
  [EnvRead, {key: R}, ~, ~, Str], # 85
  [DefinedOr, ~, [85, 8], ~, Str], # 86
  [If, ~, [84, 86], 84], # 87
  [Proj, {index: 1}, [87]], # 88
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 89
  [Proj, {index: 0}, [87]], # 90
  [Call, {dispatch_kind: builtin, name: exit, param_names: []}, [89], 90, Unknown, 80], # 91
  [Region, {head: 87}, [88, 91]], # 92
  [Print, ~, [11], 92, "Maybe[Boolean]"], # 93
  [Print, ~, [3, 10], 93, "Maybe[Boolean]"], # 94
  [Loop, {bound: each}, [94], 94], # 95
  [Proj, {index: 1}, [95]], # 96
  [Region, {head: 95}, [96]], # 97
  [Loop, {bound: entry}, [97], 97], # 98
  [Proj, {index: 1}, [98]], # 99
  [Region, {head: 98}, [99]], # 100
  [If, ~, [100, 20], 100], # 101
  [Proj, {index: 1}, [101]], # 102
  [Constant, {const_type: string, value: "-p"}, ~, ~, Str], # 103
  [Proj, {index: 0}, [101]], # 104
  [Print, ~, [103], 104, "Maybe[Boolean]"], # 105
  [Region, {head: 101}, [102, 105]], # 106
  [Print, ~, [2], 106, "Maybe[Boolean]"], # 107
  [Return, {implicit: true}, [1], 107, ~, 80], # 108
  [EnvRead, {key: A}, ~, ~, Str], # 109
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 110
  [DefinedOr, ~, [109, 110], ~, Str], # 111
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 112
  [ArrayLiteral, {sigil: "@", symbol: l}, [111, 112], ~, Array], # 113
  [Count, ~, [113], ~, Int, 80], # 114
  [Phi, {region: 98}, [8, 127], ~, Int], # 115
  [Subscript, {kind: array}, [113, 115], ~, Scalar, 80], # 116
  [NumLt, ~, [44, 21], 41, Boolean], # 117
  [Add, ~, [21, 19], ~, Num], # 118
  [NumLt, ~, [53, 21], 52, Boolean], # 119
  [NumGt, ~, [114, 115], 98, Boolean], # 120
  [Coerce, {from_repr: Unknown, to_repr: Str}, [116], ~, Str], # 121
  [Phi, {region: 49}, [44, 125], ~, Int], # 122
  [NumGe, ~, [122, 118], ~, Boolean], # 123
  [NumLt, ~, [122, 118], 49, Boolean], # 124
  [Add, ~, [122, 7], ~, Int], # 125
  [NumGt, ~, [125, 22], ~, Boolean], # 126
  [Add, ~, [115, 7], ~, Int], # 127
  [Constant, {const_type: string, value: "-f"}, ~, ~, Str], # 128
  [Concat, ~, [128, 121], ~, Str], # 129
  [Add, ~, [44, 7], ~, Int], # 130
  [Coerce, {from_repr: Int, to_repr: Str}, [44], ~, Str], # 131
  [Add, ~, [53, 7], ~, Int], # 132
  [Phi, {region: 95}, [8, 135], ~, Int], # 133
  [NumLt, ~, [133, 7], 95, Boolean], # 134
  [Add, ~, [133, 7], ~, Int], # 135
  [Proj, {index: 0}, [49]], # 136
  [If, ~, [136, 126], 136], # 137
  [Proj, {index: 0}, [52]], # 138
  [Proj, {index: 0}, [98]], # 139
  [Loop, {bound: each}, [139], 139], # 140
  [Proj, {index: 1}, [140]], # 141
  [Region, {head: 140}, [141]], # 142
  [Print, ~, [129], 142, "Maybe[Boolean]"], # 143
  [Constant, {const_type: string, value: "-w"}, ~, ~, Str], # 144
  [Concat, ~, [144, 131], ~, Str], # 145
  [Coerce, {from_repr: Int, to_repr: Str}, [125], ~, Str], # 146
  [Proj, {index: 0}, [137]], # 147
  [Proj, {index: 1}, [137]], # 148
  [Coerce, {from_repr: Unknown, to_repr: Boolean}, [86], 140, Boolean], # 149
  [Coerce, {from_repr: Int, to_repr: Str}, [133], ~, Str], # 150
  [Proj, {index: 1}, [46]], # 151
  [Print, ~, [145], 151, "Maybe[Boolean]"], # 152
  [Constant, {const_type: string, value: "-u"}, ~, ~, Str], # 153
  [Concat, ~, [153, 146], ~, Str], # 154
  [Proj, {index: 0}, [95]], # 155
  [Print, ~, [154], 148, "Maybe[Boolean]"], # 156
  [Region, {head: 137}, [147, 156]], # 157
  [Proj, {index: 0}, [140]], # 158
  [Constant, {const_type: string, value: "-c"}, ~, ~, Str], # 159
  [Concat, ~, [159, 150], ~, Str], # 160
  [Print, ~, [160], 155, "Maybe[Boolean]"]]} # 161
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
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {memory: true, region: 3}, [2, 35], ~, Unknown], # 4
  [Proj, {index: 1}, [3]], # 5
  [Region, {head: 3}, [5]], # 6
  [Phi, {memory: true, region: 6}, [4], ~, Unknown], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 7], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [PadAccess, {sigil: "@", symbol: out}, ~, ~, Array], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [9, 10], ~, Str, 7], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Print, ~, [13], 6, "Maybe[Boolean]"], # 14
  [Return, {implicit: true}, [1], 14, ~, 7], # 15
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 16
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 17
  [Phi, {region: 3}, [17, 36], ~, Int], # 18
  [NumGt, ~, [16, 18], 3, Boolean], # 19
  [Proj, {index: 0}, [3]], # 20
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 21
  [NumEq, ~, [18, 21], ~, Boolean], # 22
  [If, ~, [20, 22], 20], # 23
  [Proj, {index: 1}, [23]], # 24
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 25
  [NumEq, ~, [18, 25], ~, Boolean], # 26
  [If, ~, [24, 26], 24], # 27
  [Proj, {index: 1}, [27]], # 28
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [10, 18], 28, Int, 4, true], # 29
  [Proj, {index: 0}, [23]], # 30
  [Region, {head: 23}, [30, 29]], # 31
  [Phi, {memory: true, predecessors: [30, 24], region: 31}, [4, 29], ~, Unknown], # 32
  [Proj, {index: 0}, [27]], # 33
  [Region, {head: 3}, [31, 33]], # 34
  [Phi, {memory: true, predecessors: [20, 33], region: 34}, [32, 4], ~, Unknown], # 35
  [Add, ~, [18, 17], ~, Int]]} # 36
```
