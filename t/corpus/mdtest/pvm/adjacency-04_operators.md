# Every operator, each beside another

One body holding every construct this tier introduces, each adjacent to
another -- and adjacent to tier 03's list operators, which is what this
tier depends on.

**Tier 04 operators.** Introduces nothing of its own; it is the mixture
that is the subject.

WHY A MIXTURE NEEDS ITS OWN CASE. The tier's other cases are one kind of
operator each, which is what makes them diagnosable: when the
associativity case prints `512 64`, the construct that broke is the only
one present. That same property is why a corpus of such cases cannot
reach an adjacency bug -- a parser that handles each operator class
alone and mishandles a mixture goes green over every isolated case, and
a mixture is exactly what real Perl is.

THE CLAIM IS THE SOURCE. Every construct the tier introduces appears
below, next to another one, and a reader can see that by reading it.
This used to be asserted by a Go map from file name to a spelling to
grep for, because a one-construct-per-file corpus had no way to say
"these are adjacent" except by naming files. A case whose body IS the
mixture needs no such map.

The adjacency here is dense on purpose. `$n + 1 - 2 * 3` mixes three
precedence levels in one expression; `($n <=> 3) . ($word cmp "ab")`
feeds two comparisons into a concatenation; `substr($edit, 0, 1) =
chr(ord($word) + 1)` puts an lvalue substr, chr and ord in one
statement.

WHAT THIS DOES NOT ESTABLISH is that the constructs are adjacent in any
stronger sense than "in the same body". Tier N beside tier N-3 is
unreached by construction, and the `t/` sweep is what finds it -- the
plan defers that deliberately and names where it goes.

## The whole tier in one body

ZERO Unknown nodes, and the whole tier in one body is why this case is
kept: every construct here also appears in a sibling case that parses on
its own, and for three successive gaps the MIXTURE was the only thing
that refused. A one-case-per-construct corpus would have gone green over
all of it and seen none of them.

### The last of those gaps, and what closed it

It was `undef @cleared` -- the unary spelling, which the parser read as a
complete term with `@cleared` stranded after it, because `undef` was
absent from `parse.namedUnary`. `01a0dd43` added the entry, classified by
that table's own deparse method: `undef $x, $y` gives `(undef($x), $y)`,
the comma outside, so it is a named unary.

### What this passage used to say, and why it was wrong three times

It said TWO nodes, the second being `$t x= 2`: the lexer emitted
`Word(x) Operator(=)` rather than forming the `x=` token, so the
statement had a Word where an operator belonged. `01a0ce57` fixed that in
the lexer -- `x=` is the only compound assignment perl spells with a
letter, which is why the punctuation scanner never reached it -- and
`compound-assignment.md` carries the case.

### What it said before that, and why it was wrong twice

It said FIVE nodes at three sites, and attributed three of them to `not`
arriving as a Word with nothing in `parseTerm` able to begin a term with
it.

The count is now two, because `01a0dbe8` taught the paren to hold a full
expression -- `and`, `or` and `xor` bind BELOW the comma, so a paren
parsing its elements at the comma's power never reached them.

The attribution was wrong before that landed. The site was the
parenthesised `xor`, not `not`: measured, `(not $a)` parses clean on its
own and always did, because `not` is PREFIX and `prefix` has it. Reading
a count off a failing case and then naming a cause for it is how that
happened; the cause was never measured separately.

The file test is the one construct NOT here. `31_file_test`'s claim is
`no operator whose text is "-"`, and this body writes `-$n ** 2` and
`~$a`, so the negative is false here and no spelling of it is not.

```perl
my @nums = (3, 1, 2);
my $n = $ARGV[0] // @nums;
my $word = $ARGV[1] // "ab";
my $sum = $n + 1 - 2 * 3;
my $rel = ($n <=> 3) . ($word cmp "ab");
my $pick = ($n > 2 and $word ne "zz") || ($n % 2);
my $power = -$n ** 2 / 3;
my $loose = defined $n + 1;
my @cleared = @nums;
undef @cleared;
my @filled = undef;
my $edit = $word;
substr($edit, 0, 1) = chr(ord($word) + 1);
my $a = $ARGV[2] // 6;
my $b = $ARGV[3] // 3;
my $c = $ARGV[4] // 2;
my $bits = $a & $b;
my $prec = ($a | $b) & $c;
my $shifted = $a << 1;
my $comp = ~$a & 255;
my $acc = $ARGV[5] // 5;
$acc += 2;
my $app = $ARGV[6] // "a";
$app .= "b";
my $t = $ARGV[7] // "ab";
$t x= 2;
my $def = $ARGV[8] // 0;
$def //= 99;
my $mask = $ARGV[9] // 12;
$mask |= 3;
my $count = $ARGV[10] // 5;
$count++;
$count++;
--$count;
my $tag = $ARGV[11] // "Az";
$tag++;
my $flag = !$count;
my $group = +($n + 1) * 2;
my $chain = 9 < 1 < 5;
print "sum [$sum] rel [$rel] pick [$pick] rep [", $word x 2, "] pow [$power]\n";
print join(",", reverse sort @nums), " ", ($n >= 3 xor not $n <= 3), " $loose ", scalar(@cleared), scalar(@filled), "\n";
print sprintf("%0*d", $n, $n), " [$edit] ", index($edit, "b"), " [", substr($word, 1, 1), "]\n";
print "bits [$bits] prec [$prec] shift [$shifted] comp [$comp]\n";
print "acc [$acc] app [$app] rep [$t] def [$def] mask [$mask]\n";
print "count [$count] tag [$tag] flag [$flag] group [$group] chain [$chain]\n";
```

```behavior
parses: yes
```

```output
sum [-2] rel [00] pick [1] rep [abab] pow [-3]
3,2,1 1 1 01
003 [bb] 0 [b]
bits [2] prec [2] shift [12] comp [249]
acc [7] app [ab] rep [abab] def [0] mask [15]
count [6] tag [Ba] flag [] group [8] chain []
```

```ir
main::__PROGRAM__: {start: 0, returns: [211], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "count ["}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 4
  [MemStart], # 5
  [PadAccess, {sigil: $, symbol: edit}, [5], ~, Unknown], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Subscript, ~, [3, 7, 5], ~, Scalar], # 8
  [Constant, {const_type: string, value: ab}, ~, ~, Str], # 9
  [DefinedOr, ~, [8, 9], ~, Scalar], # 10
  [Assign, ~, [6, 10], 0, Scalar], # 11
  [PadAccess, {sigil: $, symbol: edit}, [11], ~, Str], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [Call, {dispatch_kind: builtin, name: ord, param_names: []}, [10], ~, Int], # 14
  [Add, ~, [14, 7], ~, Int], # 15
  [Call, {dispatch_kind: builtin, name: chr, param_names: []}, [15], ~, Str], # 16
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [12, 13, 7, 16], 11, Str], # 17
  [Subscript, ~, [3, 4, 17], ~, Scalar], # 18
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 19
  [DefinedOr, ~, [18, 19], ~, Scalar], # 20
  [Increment, ~, [20], ~, Scalar], # 21
  [Increment, ~, [21], ~, Scalar], # 22
  [Coerce, {from_repr: Scalar, to_repr: Num}, [22], ~, Num], # 23
  [Subtract, ~, [23, 7], ~, Num], # 24
  [Coerce, {from_repr: Num, to_repr: Str}, [24], ~, Str], # 25
  [Concat, ~, [2, 25], ~, Str], # 26
  [Constant, {const_type: string, value: "] tag ["}, ~, ~, Str], # 27
  [Concat, ~, [26, 27], ~, Str], # 28
  [Constant, {const_type: integer, value: "11"}, ~, ~, Int], # 29
  [Subscript, ~, [3, 29, 17], ~, Scalar], # 30
  [Constant, {const_type: string, value: Az}, ~, ~, Str], # 31
  [DefinedOr, ~, [30, 31], ~, Scalar], # 32
  [Increment, ~, [32], ~, Scalar], # 33
  [Coerce, {from_repr: Scalar, to_repr: Str}, [33], ~, Str], # 34
  [Concat, ~, [28, 34], ~, Str], # 35
  [Constant, {const_type: string, value: "] flag ["}, ~, ~, Str], # 36
  [Concat, ~, [35, 36], ~, Str], # 37
  [Not, ~, [24], ~, Boolean], # 38
  [Coerce, {from_repr: Boolean, to_repr: Str}, [38], ~, Str], # 39
  [Concat, ~, [37, 39], ~, Str], # 40
  [Constant, {const_type: string, value: "] group ["}, ~, ~, Str], # 41
  [Concat, ~, [40, 41], ~, Str], # 42
  [Subscript, ~, [3, 13, 5], ~, Scalar], # 43
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 44
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 45
  [ArrayLiteral, {sigil: "@", symbol: nums}, [44, 7, 45], ~, Array], # 46
  [Count, ~, [46, 5], ~, Int], # 47
  [DefinedOr, ~, [43, 47], ~, Scalar], # 48
  [Coerce, {from_repr: Scalar, to_repr: Num}, [48], ~, Num], # 49
  [Add, ~, [49, 7], ~, Num], # 50
  [Multiply, ~, [50, 45], ~, Num], # 51
  [Coerce, {from_repr: Unknown, to_repr: Str}, [51], ~, Str], # 52
  [Concat, ~, [42, 52], ~, Str], # 53
  [Constant, {const_type: string, value: "] chain ["}, ~, ~, Str], # 54
  [Concat, ~, [53, 54], ~, Str], # 55
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 56
  [NumLt, ~, [56, 7], ~, Boolean], # 57
  [Coerce, {from_repr: Boolean, to_repr: Str}, [57], ~, Str], # 58
  [Concat, ~, [55, 58], ~, Str], # 59
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 60
  [Concat, ~, [59, 60], ~, Str], # 61
  [Constant, {const_type: string, value: "acc ["}, ~, ~, Str], # 62
  [Subscript, ~, [3, 19, 17], ~, Scalar], # 63
  [DefinedOr, ~, [63, 19], ~, Scalar], # 64
  [Coerce, {from_repr: Scalar, to_repr: Num}, [64], ~, Num], # 65
  [Add, ~, [65, 45], ~, Num], # 66
  [Coerce, {from_repr: Unknown, to_repr: Str}, [66], ~, Str], # 67
  [Concat, ~, [62, 67], ~, Str], # 68
  [Constant, {const_type: string, value: "] app ["}, ~, ~, Str], # 69
  [Concat, ~, [68, 69], ~, Str], # 70
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 71
  [Subscript, ~, [3, 71, 17], ~, Scalar], # 72
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 73
  [DefinedOr, ~, [72, 73], ~, Scalar], # 74
  [Coerce, {from_repr: Scalar, to_repr: Str}, [74], ~, Str], # 75
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 76
  [Concat, ~, [75, 76], ~, Str], # 77
  [Concat, ~, [70, 77], ~, Str], # 78
  [Constant, {const_type: string, value: "] rep ["}, ~, ~, Str], # 79
  [Concat, ~, [78, 79], ~, Str], # 80
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 81
  [Subscript, ~, [3, 81, 17], ~, Scalar], # 82
  [DefinedOr, ~, [82, 9], ~, Scalar], # 83
  [Coerce, {from_repr: Scalar, to_repr: Str}, [83], ~, Str], # 84
  [Repeat, ~, [84, 45], ~, Str], # 85
  [Concat, ~, [80, 85], ~, Str], # 86
  [Constant, {const_type: string, value: "] def ["}, ~, ~, Str], # 87
  [Concat, ~, [86, 87], ~, Str], # 88
  [Constant, {const_type: integer, value: "8"}, ~, ~, Int], # 89
  [Subscript, ~, [3, 89, 17], ~, Scalar], # 90
  [DefinedOr, ~, [90, 13], ~, Scalar], # 91
  [Constant, {const_type: integer, value: "99"}, ~, ~, Int], # 92
  [DefinedOr, ~, [91, 92], ~, Scalar], # 93
  [Coerce, {from_repr: Unknown, to_repr: Str}, [93], ~, Str], # 94
  [Concat, ~, [88, 94], ~, Str], # 95
  [Constant, {const_type: string, value: "] mask ["}, ~, ~, Str], # 96
  [Concat, ~, [95, 96], ~, Str], # 97
  [Subscript, ~, [3, 56, 17], ~, Scalar], # 98
  [Constant, {const_type: integer, value: "12"}, ~, ~, Int], # 99
  [DefinedOr, ~, [98, 99], ~, Scalar], # 100
  [Coerce, {from_repr: Scalar, to_repr: Int}, [100], ~, Int], # 101
  [BitOr, ~, [101, 44], ~, Int], # 102
  [Coerce, {from_repr: Int, to_repr: Str}, [102], ~, Str], # 103
  [Concat, ~, [97, 103], ~, Str], # 104
  [Concat, ~, [104, 60], ~, Str], # 105
  [Constant, {const_type: string, value: "bits ["}, ~, ~, Str], # 106
  [Subscript, ~, [3, 45, 17], ~, Scalar], # 107
  [DefinedOr, ~, [107, 71], ~, Scalar], # 108
  [Coerce, {from_repr: Scalar, to_repr: Int}, [108], ~, Int], # 109
  [Subscript, ~, [3, 44, 17], ~, Scalar], # 110
  [DefinedOr, ~, [110, 44], ~, Scalar], # 111
  [Coerce, {from_repr: Scalar, to_repr: Int}, [111], ~, Int], # 112
  [BitAnd, ~, [109, 112], ~, Int], # 113
  [Coerce, {from_repr: Int, to_repr: Str}, [113], ~, Str], # 114
  [Concat, ~, [106, 114], ~, Str], # 115
  [Constant, {const_type: string, value: "] prec ["}, ~, ~, Str], # 116
  [Concat, ~, [115, 116], ~, Str], # 117
  [BitOr, ~, [109, 112], ~, Int], # 118
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 119
  [Subscript, ~, [3, 119, 17], ~, Scalar], # 120
  [DefinedOr, ~, [120, 45], ~, Scalar], # 121
  [Coerce, {from_repr: Scalar, to_repr: Int}, [121], ~, Int], # 122
  [BitAnd, ~, [118, 122], ~, Int], # 123
  [Coerce, {from_repr: Int, to_repr: Str}, [123], ~, Str], # 124
  [Concat, ~, [117, 124], ~, Str], # 125
  [Constant, {const_type: string, value: "] shift ["}, ~, ~, Str], # 126
  [Concat, ~, [125, 126], ~, Str], # 127
  [LeftShift, ~, [109, 7], ~, Int], # 128
  [Coerce, {from_repr: Int, to_repr: Str}, [128], ~, Str], # 129
  [Concat, ~, [127, 129], ~, Str], # 130
  [Constant, {const_type: string, value: "] comp ["}, ~, ~, Str], # 131
  [Concat, ~, [130, 131], ~, Str], # 132
  [Complement, ~, [109], ~, Int], # 133
  [Constant, {const_type: integer, value: "255"}, ~, ~, Int], # 134
  [BitAnd, ~, [133, 134], ~, Int], # 135
  [Coerce, {from_repr: Int, to_repr: Str}, [135], ~, Str], # 136
  [Concat, ~, [132, 136], ~, Str], # 137
  [Concat, ~, [137, 60], ~, Str], # 138
  [Constant, {const_type: string, value: "%0*d"}, ~, ~, Str], # 139
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [139, 48, 48], ~, Str], # 140
  [Constant, {const_type: string, value: " ["}, ~, ~, Str], # 141
  [PadAccess, {sigil: $, symbol: edit}, [17], ~, Str], # 142
  [Coerce, {from_repr: Unknown, to_repr: Str}, [142], ~, Str], # 143
  [Concat, ~, [141, 143], ~, Str], # 144
  [Constant, {const_type: string, value: "] "}, ~, ~, Str], # 145
  [Concat, ~, [144, 145], ~, Str], # 146
  [Call, {dispatch_kind: builtin, name: index, param_names: []}, [142, 76], ~, Int], # 147
  [Coerce, {from_repr: Int, to_repr: Str}, [147], ~, Str], # 148
  [Coerce, {from_repr: Scalar, to_repr: Str}, [10], ~, Str], # 149
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [149, 7, 7], ~, Str], # 150
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 151
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [44, 7, 45], ~, List], # 152
  [Call, {dispatch_kind: builtin, name: reverse, param_names: []}, [152], ~, List], # 153
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [151, 153], ~, Str], # 154
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 155
  [NumGe, ~, [49, 44], ~, Boolean], # 156
  [NumLe, ~, [49, 44], ~, Boolean], # 157
  [Not, ~, [157], ~, Boolean], # 158
  [Xor, ~, [156, 158], ~, Boolean], # 159
  [Coerce, {from_repr: Boolean, to_repr: Str}, [159], ~, Str], # 160
  [Defined, ~, [50], ~, Boolean], # 161
  [Coerce, {from_repr: Boolean, to_repr: Str}, [161], ~, Str], # 162
  [Concat, ~, [155, 162], ~, Str], # 163
  [Concat, ~, [163, 155], ~, Str], # 164
  [ArrayLiteral, ~, ~, ~, Array], # 165
  [Count, ~, [165, 17], ~, Int], # 166
  [Coerce, {from_repr: Int, to_repr: Str}, [166], ~, Str], # 167
  [ArrayLiteral, {sigil: "@", symbol: filled}, [1], ~, Array], # 168
  [Count, ~, [168, 17], ~, Int], # 169
  [Coerce, {from_repr: Int, to_repr: Str}, [169], ~, Str], # 170
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 171
  [Constant, {const_type: string, value: "sum ["}, ~, ~, Str], # 172
  [Subtract, ~, [50, 71], ~, Num], # 173
  [Coerce, {from_repr: Unknown, to_repr: Str}, [173], ~, Str], # 174
  [Concat, ~, [172, 174], ~, Str], # 175
  [Constant, {const_type: string, value: "] rel ["}, ~, ~, Str], # 176
  [Concat, ~, [175, 176], ~, Str], # 177
  [NumCmp, ~, [49, 44], ~, Int], # 178
  [Coerce, {from_repr: Int, to_repr: Str}, [178], ~, Str], # 179
  [StrCmp, ~, [149, 9], ~, Int], # 180
  [Coerce, {from_repr: Int, to_repr: Str}, [180], ~, Str], # 181
  [Concat, ~, [179, 181], ~, Str], # 182
  [Concat, ~, [177, 182], ~, Str], # 183
  [Constant, {const_type: string, value: "] pick ["}, ~, ~, Str], # 184
  [Concat, ~, [183, 184], ~, Str], # 185
  [NumGt, ~, [49, 45], ~, Boolean], # 186
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 187
  [Constant, {const_type: string, value: zz}, ~, ~, Str], # 188
  [StrNe, ~, [187, 188], ~, Boolean], # 189
  [And, ~, [186, 189], ~, Boolean], # 190
  [Modulo, ~, [49, 45], ~, Int], # 191
  [Or, ~, [190, 191], ~, Scalar], # 192
  [Coerce, {from_repr: Unknown, to_repr: Str}, [192], ~, Str], # 193
  [Concat, ~, [185, 193], ~, Str], # 194
  [Concat, ~, [194, 79], ~, Str], # 195
  [Repeat, ~, [149, 45], ~, Str], # 196
  [Constant, {const_type: string, value: "] pow ["}, ~, ~, Str], # 197
  [Power, ~, [49, 45], ~, Num], # 198
  [Negate, ~, [198], ~, Num], # 199
  [Coerce, {from_repr: Int, to_repr: Num}, [44], ~, Num], # 200
  [Divide, ~, [199, 200], ~, Num], # 201
  [Coerce, {from_repr: Num, to_repr: Str}, [201], ~, Str], # 202
  [Concat, ~, [197, 202], ~, Str], # 203
  [Concat, ~, [203, 60], ~, Str], # 204
  [Print, ~, [195, 196, 204], 17, Scalar], # 205
  [Print, ~, [154, 155, 160, 164, 167, 170, 171], 205, Scalar], # 206
  [Print, ~, [140, 146, 148, 141, 150, 60], 206, Scalar], # 207
  [Print, ~, [138], 207, Scalar], # 208
  [Print, ~, [105], 208, Scalar], # 209
  [Print, ~, [61], 209, Scalar], # 210
  [Return, ~, [1], 210], # 211
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [12, 13, 7], ~, Str], # 212
  [ArrayLiteral, {sigil: "@", symbol: cleared}, [44, 7, 45], ~, Array], # 213
  [PadAccess, {sigil: $, symbol: rel}, ~, ~, Str], # 214
  [VarDecl, {scope: my}, [214, 182]]]} # 215
```
