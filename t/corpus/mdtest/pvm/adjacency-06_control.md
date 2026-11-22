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
main::__PROGRAM__: {start: 0, returns: [116], nodes: [
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
  [MemStart], # 13
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 13], # 14
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 15
  [Constant, {const_type: string, value: "-v"}, ~, ~, Str], # 16
  [EnvRead, {key: "N"}, ~, ~, Str], # 17
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 18
  [DefinedOr, ~, [17, 18], ~, Str], # 19
  [Coerce, {from_repr: Str, to_repr: Num}, [19], ~, Num], # 20
  [Add, ~, [20, 7], ~, Num], # 21
  [Coerce, {from_repr: Unknown, to_repr: Str}, [21], ~, Str], # 22
  [Concat, ~, [16, 22], ~, Str], # 23
  [Constant, {const_type: string, value: "-d"}, ~, ~, Str], # 24
  [Add, ~, [8, 7], ~, Int], # 25
  [Constant, {const_type: string, value: if}, ~, ~, Str], # 26
  [If, ~, [0, 19], 0], # 27
  [Proj, {index: 0}, [27]], # 28
  [Print, ~, [26], 28, "Maybe[Boolean]"], # 29
  [Constant, {const_type: string, value: else}, ~, ~, Str], # 30
  [Proj, {index: 1}, [27]], # 31
  [Print, ~, [30], 31, "Maybe[Boolean]"], # 32
  [Region, {head: 27}, [29, 32]], # 33
  [If, ~, [33, 19], 33], # 34
  [Proj, {index: 0}, [34]], # 35
  [Constant, {const_type: string, value: "-unless"}, ~, ~, Str], # 36
  [Proj, {index: 1}, [34]], # 37
  [Print, ~, [36], 37, "Maybe[Boolean]"], # 38
  [Region, {head: 34}, [35, 38]], # 39
  [Loop, {bound: each}, [39], 39], # 40
  [Proj, {index: 1}, [40]], # 41
  [Proj, {index: 0}, [40]], # 42
  [Phi, {region: 40}, [8, 138], ~, Int], # 43
  [NumGt, ~, [43, 7], ~, Boolean], # 44
  [If, ~, [42, 44], 42], # 45
  [Proj, {index: 0}, [45]], # 46
  [Region, {head: 40}, [41, 46]], # 47
  [Loop, {bound: each}, [47], 47], # 48
  [Proj, {index: 1}, [48]], # 49
  [Region, {head: 48}, [49]], # 50
  [Loop, {bound: each}, [50], 50], # 51
  [Phi, {region: 51}, [25, 140], ~, Int], # 52
  [Coerce, {from_repr: Int, to_repr: Str}, [52], ~, Str], # 53
  [Concat, ~, [24, 53], ~, Str], # 54
  [Proj, {index: 1}, [51]], # 55
  [Region, {head: 51}, [55]], # 56
  [Print, ~, [54], 56, "Maybe[Boolean]"], # 57
  [Print, ~, [23], 57, "Maybe[Boolean]"], # 58
  [EntryWrite, ~, [14, 15], 58, Unknown, 13, true], # 59
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 59], # 60
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 61
  [Coerce, {from_repr: Int, to_repr: Num}, [61], ~, Num], # 62
  [EnvRead, {key: X}, ~, ~, Str], # 63
  [DefinedOr, ~, [63, 8], ~, Str], # 64
  [Coerce, {from_repr: Str, to_repr: Num}, [64], ~, Num], # 65
  [Divide, {eval_id: 1, file: "/tmp/yDlL8UMbFX/case.pl", line: 14}, [62, 65], 59, Num], # 66
  [EntryWrite, ~, [60, 15], 66, Unknown, 59, true], # 67
  [Exc, ~, [66]], # 68
  [Region, {catch: true, eval_id: 1}, [68]], # 69
  [EntryWrite, ~, [60, 68], 69, Unknown, 59, true], # 70
  [Region, {eval_entry: 58, eval_id: 1}, [67, 70]], # 71
  [Phi, {memory: true, region: 71}, [67, 70], ~, Unknown], # 72
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 72], # 73
  [Constant, {const_type: string, value: "-e"}, ~, ~, Str], # 74
  [Phi, {region: 71}, [66, 1], ~, "Maybe[Num]"], # 75
  [Constant, {const_type: string, value: t}, ~, ~, Str], # 76
  [DefinedOr, ~, [75, 76], ~, "Maybe[Str]"], # 77
  [Coerce, {from_repr: Unknown, to_repr: Str}, [77], ~, Str], # 78
  [Concat, ~, [74, 78], ~, Str], # 79
  [Print, ~, [79], 71, "Maybe[Boolean]"], # 80
  [EntryWrite, ~, [73, 15], 80, Unknown, 72, true], # 81
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 81], # 82
  [Constant, {const_type: string, value: "x\n"}, ~, ~, Str], # 83
  [Unwind, {eval_id: 2, file: "/tmp/yDlL8UMbFX/case.pl", line: 16}, [83], 81, ~, 81], # 84
  [Exc, ~, [84]], # 85
  [Region, {catch: true, eval_id: 2}, [85]], # 86
  [EntryWrite, ~, [82, 85], 86, Unknown, 81, true], # 87
  [Region, {eval_entry: 80, eval_id: 2}, [87]], # 88
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 88, Scalar, 87], # 89
  [Coerce, {from_repr: Unknown, to_repr: Str}, [89], ~, Str], # 90
  [Concat, ~, [12, 90], ~, Str], # 91
  [Print, ~, [91], 89, "Maybe[Boolean]"], # 92
  [EnvRead, {key: R}, ~, ~, Str], # 93
  [DefinedOr, ~, [93, 8], ~, Str], # 94
  [If, ~, [92, 94], 92], # 95
  [Proj, {index: 1}, [95]], # 96
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 97
  [Proj, {index: 0}, [95]], # 98
  [Call, {dispatch_kind: builtin, name: exit, param_names: []}, [97], 98, Unknown, 87], # 99
  [Region, {head: 95}, [96, 99]], # 100
  [Print, ~, [11], 100, "Maybe[Boolean]"], # 101
  [Print, ~, [3, 10], 101, "Maybe[Boolean]"], # 102
  [Loop, {bound: each}, [102], 102], # 103
  [Proj, {index: 1}, [103]], # 104
  [Region, {head: 103}, [104]], # 105
  [Loop, {bound: entry}, [105], 105], # 106
  [Proj, {index: 1}, [106]], # 107
  [Region, {head: 106}, [107]], # 108
  [If, ~, [108, 19], 108], # 109
  [Proj, {index: 1}, [109]], # 110
  [Constant, {const_type: string, value: "-p"}, ~, ~, Str], # 111
  [Proj, {index: 0}, [109]], # 112
  [Print, ~, [111], 112, "Maybe[Boolean]"], # 113
  [Region, {head: 109}, [110, 113]], # 114
  [Print, ~, [2], 114, "Maybe[Boolean]"], # 115
  [Return, {implicit: true}, [1], 115, ~, 87], # 116
  [EnvRead, {key: A}, ~, ~, Str], # 117
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 118
  [DefinedOr, ~, [117, 118], ~, Str], # 119
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 120
  [ArrayLiteral, {sigil: "@", symbol: l}, [119, 120], ~, Array], # 121
  [Count, ~, [121], ~, Int, 87], # 122
  [Phi, {region: 106}, [8, 135], ~, Int], # 123
  [Subscript, {kind: array}, [121, 123], ~, Scalar, 87], # 124
  [NumLt, ~, [43, 20], 40, Boolean], # 125
  [Add, ~, [20, 18], ~, Num], # 126
  [NumLt, ~, [52, 20], 51, Boolean], # 127
  [NumGt, ~, [122, 123], 106, Boolean], # 128
  [Coerce, {from_repr: Unknown, to_repr: Str}, [124], ~, Str], # 129
  [Phi, {region: 48}, [43, 133], ~, Int], # 130
  [NumGe, ~, [130, 126], ~, Boolean], # 131
  [NumLt, ~, [130, 126], 48, Boolean], # 132
  [Add, ~, [130, 7], ~, Int], # 133
  [NumGt, ~, [133, 21], ~, Boolean], # 134
  [Add, ~, [123, 7], ~, Int], # 135
  [Constant, {const_type: string, value: "-f"}, ~, ~, Str], # 136
  [Concat, ~, [136, 129], ~, Str], # 137
  [Add, ~, [43, 7], ~, Int], # 138
  [Coerce, {from_repr: Int, to_repr: Str}, [43], ~, Str], # 139
  [Add, ~, [52, 7], ~, Int], # 140
  [Phi, {region: 103}, [8, 143], ~, Int], # 141
  [NumLt, ~, [141, 7], 103, Boolean], # 142
  [Add, ~, [141, 7], ~, Int], # 143
  [Proj, {index: 0}, [48]], # 144
  [If, ~, [144, 134], 144], # 145
  [Proj, {index: 0}, [51]], # 146
  [Proj, {index: 0}, [106]], # 147
  [Loop, {bound: each}, [147], 147], # 148
  [Proj, {index: 1}, [148]], # 149
  [Region, {head: 148}, [149]], # 150
  [Print, ~, [137], 150, "Maybe[Boolean]"], # 151
  [Constant, {const_type: string, value: "-w"}, ~, ~, Str], # 152
  [Concat, ~, [152, 139], ~, Str], # 153
  [Coerce, {from_repr: Int, to_repr: Str}, [133], ~, Str], # 154
  [Proj, {index: 0}, [145]], # 155
  [Proj, {index: 1}, [145]], # 156
  [Coerce, {from_repr: Unknown, to_repr: Boolean}, [94], 148, Boolean], # 157
  [Coerce, {from_repr: Int, to_repr: Str}, [141], ~, Str], # 158
  [Proj, {index: 1}, [45]], # 159
  [Print, ~, [153], 159, "Maybe[Boolean]"], # 160
  [Constant, {const_type: string, value: "-u"}, ~, ~, Str], # 161
  [Concat, ~, [161, 154], ~, Str], # 162
  [Proj, {index: 0}, [103]], # 163
  [Print, ~, [162], 156, "Maybe[Boolean]"], # 164
  [Region, {head: 145}, [155, 164]], # 165
  [Proj, {index: 0}, [148]], # 166
  [Constant, {const_type: string, value: "-c"}, ~, ~, Str], # 167
  [Concat, ~, [167, 158], ~, Str], # 168
  [Print, ~, [168], 163, "Maybe[Boolean]"]]} # 169
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
