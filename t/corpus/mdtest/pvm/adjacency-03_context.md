# Every construct, each beside another

One body holding every construct this tier introduces, each adjacent to
another -- and adjacent to tier 02's array, which is what this tier
depends on.

**Tier 03 context.** Introduces nothing of its own; the mixture is the
subject. Depends on 02_variables.

The tier's other cases are one construct each, which makes them
diagnosable: when the `sort` case fails, the construct that failed is
the only one present. That property is also why such cases cannot reach
an adjacency bug -- a parser that handles every construct alone and
mis-handles a pair goes green over the pair.

The constructs sit on consecutive STATEMENTS rather than nested, because
nesting them would need an operator to join them and this tier comes
before the operator tier.

## The whole tier in one body

EVERY DISCRIMINATING CONSTRUCT APPEARS IN BOTH CONTEXTS, which is what
distinguishes this from a list of the tier's constructs. The tier's
subject is not a set of constructs, it is a set of PAIRS whose halves
emit the same op and differ only by the `s` versus `l` flag. A body
holding one half of each asks the parser for one answer where the
construct has two, and a parser that collapsed the two contexts into a
single answer would go green over it.

So `@a` appears in scalar and in list context, `reverse` twice, the
empty-list count idiom twice, `localtime` twice, `caller` twice, and
`map` and `grep` twice each. Measured, that is `padav s`/`padav l`,
`reverse sK/1`/`reverse lK/1`, `aassign sKS`/`aassign lKPS`,
`localtime s`/`localtime l`, `caller s`/`caller l`,
`mapstart sK`/`mapstart lK` and `grepstart sK`/`grepstart lK` -- seven
pairs in one body, with the tier's remaining constructs in scope.

The adjacency with the earlier tier is the first line: `@a` is tier 02's
array, and every statement after it puts that same array in a different
context. Pairing this tier with the one it depends on is the array being
re-used, not a separate statement about arrays.

READING THE OUTPUT. `sort` is a default string sort, so `(3,1,2)` comes
back `1 2 3`. The reverse of that array in scalar context is `213` --
the elements joined with nothing between them, then the string reversed
-- not `2 1 3`, which is the list-context `@revd` on the next line.
`$moved` is 3 and `@kept` is empty from the SAME idiom. `$fields` is 9
because list-context `localtime` returns nine elements; `$stamp` is the
scalar half, a formatted string, and it is COUNTED rather than printed
-- pinning it would make this case depend on the clock and the timezone,
while `@seen` holds two elements whatever the time is. `$who` and
`@frame` are `caller` in the two contexts, and at file scope they return
different AMOUNTS: `$who` is undef and `@frame` is the EMPTY list, which
is the `0` after the `3`.

`@mapped` is the three elements and `$mapcount` is 3; `@kept2` is the
three elements and `$grepcount` is 3 as well, because every element of
`(3, 1, 2)` is true and nothing is filtered. That grep keeps everything
HERE is not a weakening -- the `grep` case is where grep filters, using
an element bound to `$ENV{G}`, and this body's job is adjacency.
Bringing `$ENV` in here would add an opacity it does not otherwise need.
Neither `map` nor `grep` FOLDS despite `@a` being wholly constant, which
the comma operator two statements up does: measured, a block is not
constant-foldable however constant its input.

`..`'s three readings close the body. `@ranged` is the numeric list
range, `@lettered` is the string range whose successor is the magic
increment (`az ba bb`, carrying), and `@window` is the scalar-context
FLIP-FLOP whose `1 2 3 4` selects indices 2 and 3 where both operands
are false.

Fewer ops appear than the constructs suggest. `padrange` fuses
consecutive `my` declarations, and the comma operator in scalar context
erases its own left operands -- so the op set is a UNION across the
tier's cases rather than a property of this one. It happens that this
body does emit all seven pairs, but that is a fact about this program,
not a rule the format requires.

```perl
my @a = (3, 1, 2);
my $count = @a;
my @copy = @a;
my $interp = "@a";
my $last = (4, 5, 6);
my @sorted = sort @a;
my $moved = () = sort @a;
my @kept = (() = sort @a);
my $rev = reverse @a;
my @revd = reverse @a;
my $fields = () = localtime;
my $stamp = localtime;
my $want = wantarray;
my $who = caller;
my @frame = caller;
my @mapped = map { $_ } @a;
my $mapcount = map { $_ } @a;
my @kept2 = grep { $_ } @a;
my $grepcount = grep { $_ } @a;
my @ranged = (1 .. scalar(@a));
my @seed = ("az");
my @lettered = ($seed[0] .. "bb");
my @on = (0, 1, 0, 0, 0, 0);
my @off = (0, 0, 0, 0, 1, 0);
my @idx = (0, 1, 2, 3, 4, 5);
my @window = grep { $on[$_] .. $off[$_] } @idx;
my @seen = ($want, $stamp, $who);
print "$count @copy $interp $last @sorted $moved ", scalar(@kept),
    " $rev @revd $fields ", scalar(@seen), " ", scalar(@frame),
    " @mapped $mapcount @kept2 $grepcount",
    " @ranged @lettered @window\n";
```

```behavior
parses: yes
```

```output
3 3 1 2 3 1 2 6 1 2 3 3 0 213 2 1 3 9 3 0 3 1 2 3 3 1 2 3 1 2 3 az ba bb 1 2 3 4
```

```ir
main::__PROGRAM__: {start: 0, returns: [115], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3, 4], ~, Array], # 5
  [MemStart], # 6
  [Count, ~, [5], ~, Int, 6], # 7
  [Coerce, {from_repr: Int, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 6], # 11
  [Coerce, {from_repr: Scalar, to_repr: Str}, [11], ~, Str], # 12
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 2, 3, 4], ~, Str], # 13
  [Concat, ~, [10, 13], ~, Str], # 14
  [Concat, ~, [14, 9], ~, Str], # 15
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 2, 3, 4], ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Concat, ~, [17, 9], ~, Str], # 18
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 19
  [Coerce, {from_repr: Int, to_repr: Str}, [19], ~, Str], # 20
  [Concat, ~, [18, 20], ~, Str], # 21
  [Concat, ~, [21, 9], ~, Str], # 22
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [2, 3, 4], ~, List], # 23
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 23], ~, Str, 6], # 24
  [Concat, ~, [22, 24], ~, Str], # 25
  [Concat, ~, [25, 9], ~, Str], # 26
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [2, 3, 4], ~, List], # 27
  [Count, ~, [27], ~, Int, 6], # 28
  [Coerce, {from_repr: Int, to_repr: Str}, [28], ~, Str], # 29
  [Concat, ~, [26, 29], ~, Str], # 30
  [Concat, ~, [30, 9], ~, Str], # 31
  [ArrayLiteral, {sigil: "@", symbol: kept}, ~, ~, Array], # 32
  [Count, ~, [32], ~, Int, 6], # 33
  [Coerce, {from_repr: Int, to_repr: Str}, [33], ~, Str], # 34
  [Call, {dispatch_kind: builtin, name: reverse, param_names: []}, [2, 3, 4], ~, Str], # 35
  [Concat, ~, [9, 35], ~, Str], # 36
  [Concat, ~, [36, 9], ~, Str], # 37
  [Call, {dispatch_kind: builtin, name: reverse, param_names: []}, [2, 3, 4], ~, List], # 38
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 38], ~, Str, 6], # 39
  [Concat, ~, [37, 39], ~, Str], # 40
  [Concat, ~, [40, 9], ~, Str], # 41
  [Call, {dispatch_kind: builtin, name: localtime, param_names: []}, ~, ~, List, 6], # 42
  [Count, ~, [42], ~, Int, 6], # 43
  [Coerce, {from_repr: Int, to_repr: Str}, [43], ~, Str], # 44
  [Concat, ~, [41, 44], ~, Str], # 45
  [Concat, ~, [45, 9], ~, Str], # 46
  [Wantarray, ~, ~, ~, Scalar], # 47
  [Call, {dispatch_kind: builtin, name: localtime, param_names: []}, ~, ~, Scalar, 6], # 48
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, ~, 0, Scalar, 6], # 49
  [ArrayLiteral, {sigil: "@", symbol: seen}, [47, 48, 49], ~, Array], # 50
  [Count, ~, [50], ~, Int, 6], # 51
  [Coerce, {from_repr: Int, to_repr: Str}, [51], ~, Str], # 52
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, ~, 49, List, 6], # 53
  [ArrayLiteral, {sigil: "@", symbol: frame}, [53], ~, Array], # 54
  [Count, ~, [54], ~, Int, 6], # 55
  [Coerce, {from_repr: Int, to_repr: Str}, [55], ~, Str], # 56
  [ArrayLiteral, ~, ~, ~, Array], # 57
  [Loop, {bound: entry}, [53], 53], # 58
  [Phi, {region: 58}, [57, 154], ~, Array], # 59
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 59], ~, Str, 6], # 60
  [Concat, ~, [9, 60], ~, Str], # 61
  [Concat, ~, [61, 9], ~, Str], # 62
  [ArrayLiteral, ~, ~, ~, Array], # 63
  [Proj, {index: 1}, [58]], # 64
  [Region, {head: 58}, [64]], # 65
  [Loop, {bound: entry}, [65], 65], # 66
  [Phi, {region: 66}, [63, 155], ~, Array], # 67
  [Count, ~, [67], ~, Int], # 68
  [Coerce, {from_repr: Int, to_repr: Str}, [68], ~, Str], # 69
  [Concat, ~, [62, 69], ~, Str], # 70
  [Concat, ~, [70, 9], ~, Str], # 71
  [ArrayLiteral, ~, ~, ~, Array], # 72
  [Proj, {index: 1}, [66]], # 73
  [Region, {head: 66}, [73]], # 74
  [Loop, {bound: entry}, [74], 74], # 75
  [Phi, {region: 75}, [72, 156], ~, Array], # 76
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 76], ~, Str, 6], # 77
  [Concat, ~, [71, 77], ~, Str], # 78
  [Concat, ~, [78, 9], ~, Str], # 79
  [ArrayLiteral, ~, ~, ~, Array], # 80
  [Proj, {index: 1}, [75]], # 81
  [Region, {head: 75}, [81]], # 82
  [Loop, {bound: entry}, [82], 82], # 83
  [Phi, {region: 83}, [80, 157], ~, Array], # 84
  [Count, ~, [84], ~, Int], # 85
  [Coerce, {from_repr: Int, to_repr: Str}, [85], ~, Str], # 86
  [Concat, ~, [79, 86], ~, Str], # 87
  [Range, ~, [3, 7], ~, List], # 88
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 88], ~, Str, 6], # 89
  [Concat, ~, [9, 89], ~, Str], # 90
  [Concat, ~, [90, 9], ~, Str], # 91
  [Constant, {const_type: string, value: az}, ~, ~, Str], # 92
  [ArrayLiteral, {sigil: "@", symbol: seed}, [92], ~, Array], # 93
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 94
  [Subscript, {kind: array}, [93, 94], ~, Str, 6], # 95
  [Coerce, {from_repr: Str, to_repr: Int}, [95], ~, Int], # 96
  [Constant, {const_type: string, value: bb}, ~, ~, Str], # 97
  [Coerce, {from_repr: Str, to_repr: Int}, [97], ~, Int], # 98
  [Range, ~, [96, 98], ~, List], # 99
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 99], ~, Str, 6], # 100
  [Concat, ~, [91, 100], ~, Str], # 101
  [Concat, ~, [101, 9], ~, Str], # 102
  [ArrayLiteral, ~, ~, ~, Array], # 103
  [Proj, {index: 1}, [83]], # 104
  [Region, {head: 83}, [104]], # 105
  [Loop, {bound: entry}, [105], 105], # 106
  [Phi, {region: 106}, [103, 159], ~, Array], # 107
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 107], ~, Str, 6], # 108
  [Concat, ~, [102, 108], ~, Str], # 109
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 110
  [Concat, ~, [109, 110], ~, Str], # 111
  [Proj, {index: 1}, [106]], # 112
  [Region, {head: 106}, [112]], # 113
  [Print, ~, [31, 34, 46, 52, 9, 56, 87, 111], 113, "Maybe[Boolean]"], # 114
  [Return, {implicit: true}, [1], 114, ~, 6], # 115
  [Phi, {region: 106}, [1, 140], ~, "Maybe[Int]"], # 116
  [Phi, {region: 58}, [94, 162], ~, Int], # 117
  [Subscript, {kind: array}, [5, 117], ~, Int, 6], # 118
  [Phi, {region: 66}, [94, 163], ~, Int], # 119
  [Subscript, {kind: array}, [5, 119], ~, Int, 6], # 120
  [Phi, {region: 75}, [94, 164], ~, Int], # 121
  [Subscript, {kind: array}, [5, 121], ~, Int, 6], # 122
  [Phi, {region: 83}, [94, 165], ~, Int], # 123
  [Subscript, {kind: array}, [5, 123], ~, Int, 6], # 124
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 125
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 126
  [ArrayLiteral, {sigil: "@", symbol: idx}, [94, 3, 4, 2, 125, 126], ~, Array], # 127
  [Count, ~, [127], ~, Int, 6], # 128
  [Phi, {region: 106}, [94, 167], ~, Int], # 129
  [Subscript, {kind: array}, [127, 129], ~, Int, 6], # 130
  [ArrayLiteral, {sigil: "@", symbol: "off"}, [94, 94, 94, 94, 3, 94], ~, Array], # 131
  [Subscript, {kind: array}, [131, 130], ~, Int, 6], # 132
  [ArrayLiteral, {sigil: "@", symbol: "on"}, [94, 3, 94, 94, 94, 94], ~, Array], # 133
  [Subscript, {kind: array}, [133, 130], ~, Int, 6], # 134
  [Coerce, {from_repr: "Maybe[Int]", to_repr: Num}, [116], ~, Num], # 135
  [Add, ~, [135, 3], ~, Num], # 136
  [TernaryExpr, ~, [132, 94, 136], ~, Int], # 137
  [TernaryExpr, ~, [132, 94, 3], ~, Int], # 138
  [TernaryExpr, ~, [134, 138, 94], ~, Int], # 139
  [TernaryExpr, ~, [116, 137, 139], ~, Int], # 140
  [Coerce, {from_repr: Int, to_repr: Str}, [136], ~, Str], # 141
  [Constant, {const_type: string, value: E0}, ~, ~, Str], # 142
  [Concat, ~, [141, 142], ~, Str], # 143
  [TernaryExpr, ~, [132, 143, 136], ~, Str], # 144
  [Constant, {const_type: string, value: "1E0"}, ~, ~, Str], # 145
  [TernaryExpr, ~, [132, 145, 3], ~, Str], # 146
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 147
  [TernaryExpr, ~, [134, 146, 147], ~, Str], # 148
  [TernaryExpr, ~, [116, 144, 148], ~, Str], # 149
  [NumGt, ~, [7, 117], 58, Boolean], # 150
  [NumGt, ~, [7, 119], 66, Boolean], # 151
  [NumGt, ~, [7, 121], 75, Boolean], # 152
  [NumGt, ~, [7, 123], 83, Boolean], # 153
  [ListAppend, {collector: map}, [59, 118], ~, Array], # 154
  [ListAppend, {collector: map}, [67, 120], ~, Array], # 155
  [ListAppend, {collector: grep}, [76, 122, 122], ~, Array], # 156
  [ListAppend, {collector: grep}, [84, 124, 124], ~, Array], # 157
  [NumGt, ~, [128, 129], 106, Boolean], # 158
  [ListAppend, {collector: grep}, [107, 130, 149], ~, Array], # 159
  [Proj, {index: 0}, [58]], # 160
  [ArrayLiteral, {sigil: "@", symbol: ranged}, [88], ~, Array], # 161
  [Add, ~, [117, 3], ~, Int], # 162
  [Add, ~, [119, 3], ~, Int], # 163
  [Add, ~, [121, 3], ~, Int], # 164
  [Add, ~, [123, 3], ~, Int], # 165
  [ArrayLiteral, {sigil: "@", symbol: lettered}, [99], ~, Array], # 166
  [Add, ~, [129, 3], ~, Int], # 167
  [ArrayLiteral, {sigil: "@", symbol: copy}, [2, 3, 4], ~, Array], # 168
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [2, 3, 4], ~, List], # 169
  [Proj, {index: 0}, [106]], # 170
  [Proj, {index: 0}, [66]], # 171
  [Proj, {index: 0}, [75]], # 172
  [Proj, {index: 0}, [83]]]} # 173
```
