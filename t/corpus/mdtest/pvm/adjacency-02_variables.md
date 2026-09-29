# Every construct, each beside another

One body holding every construct this tier introduces, each adjacent to
another, and adjacent to tier 01's literals.

**Tier 02 variables.** Introduces `aassign`, `aelem`, `aelemfast`,
`aelemfast_lex`, `aelemfastlex_store`, `aslice`, `av2arylen`, `delete`,
`each`, `gv`, `gvsv`, `helem`, `hslice`, `multideref`, `padav`, `padhv`,
`push`, `rv2av`, `rv2hv`, `sassign`, `unshift`, `values`. Depends on
01_literals. The mixture itself is the subject; it introduces
nothing of its own.

The tier's other sixteen cases are one construct each, which is what
makes them diagnosable: when the computed-subscript case refuses, the
construct that refused is the only one present. That same property is
why a corpus of such cases cannot reach an ADJACENCY bug -- a parser
that handles every construct alone and mis-handles a pair goes green
over the pair.

THIS TIER'S ADJACENCY HAS A SHAPE THE ONE-CONSTRUCT CASES CANNOT HAVE.
Four of the tier's ops are the SAME construct spelled four ways -- a
constant subscript, lexical or package, read or written -- and the cases
that isolate them each see one. Here all four sit in one body, so a
parser that collapses `$a[0]` read onto `$a[0]` written, or a lexical
array onto a package one, is visible.

DEPENDS ON 01_literals, so the pairing is real and not internal: the
literals are what the variables hold. `qw(x y)` binds into an array,
`"$w[0]-$w[1]"` interpolates two elements back out, and the numbers and
strings of tier 01 are the values every subscript here returns. That
pairing is checked on the SOURCE rather than the ops -- measured, a
program with no tier-01 construct in it still emits six of tier 01's
nine ops, because `print` and a statement are themselves tier 01's, so
an op-based pairing check would pass over a body holding nothing of the
prerequisite at all.

## The whole tier in one body

`delete` appears twice because it is two constructs. On the slice
it is a real `delete` op; on the element it is a FLAG on a `multideref`,
and `exists` is the same flag position with no op in any spelling. The
hash starts with four keys so the slice can remove one, the element
delete another, and two remain to be looked up.

The runs are unseparated because `$,` is unset and each `print` gets its
arguments as a list, the same reason tier 01's adjacency file prints
`qw(a b c)` as `abc`. Line by line: `$a[0]` `$a[$#a]` `$#a`
`scalar(@a)` `$tag`; then `@a[0,1]` `$h{a}` `$h{$k[0]}` `@h{"a"}`
`scalar(keys %h)`; then `exists` true, `exists` false printing nothing,
the deleted value and a braced array name; then the three package
variables; then the four aggregate-argument operators.

THE AGGREGATE OPERATORS COME AFTER THE PRINTS, which is not the layout a
reader would choose, and the reason is that they MUTATE `@a`. Placed
before, they would shift every subscript the earlier lines print and
turn a case about adjacency into a case about arithmetic on indices.
Placed after, they are still in the same compiled body -- which is all
adjacency claims -- while the four established lines stay exactly what
they were.

They are adjacent to the constructs that matter to them: `push` and
`unshift` take the `@a` the element and slice lines have been reading,
`unshift`'s argument is the `$#a` of the last-index case, and `values`
takes the `%h` the deletes have already thinned to two keys. A parser
that flattened an aggregate first slot would push the values of `%h`
into a `@a` it had also flattened, and `scalar(@a)` would not be 5.

`%one` is a SEPARATE, one-key hash, and `each` needs it. Hash order is
not guaranteed, so `each %h` over the four-key hash would return an
unpredictable pair and the pinned line would be a guess; over a one-key
hash the first iteration is determined. `values %h` is safe on the big
hash only because it is wrapped in `scalar`, which asks how many rather
than which.

`print $a[0]` rather than `print "$a[0]"` throughout: the interpolated
subscript emits `stringify` and an interpolated `@a` emits `join` plus a
`gvsv` for `$"`, none of which this tier claims. `$tag` is built by a
separate statement so the interpolation is tier 01's `multiconcat` over
two already-fetched elements rather than a fetch inside the print.

```perl
my @a = (42, 0.5, 'plain');
my @w = qw(x y);
my %h = (a => 1, b => 2, c => 3, d => 4);
my @k = ("b");
my $x = 7;
$a[0] = ${x};
delete @h{"c"};
my $gone = delete $h{d};
my $tag = "$w[0]-$w[1]";
$::s = $a[0];
@::p = (8, 9);
%::g = (z => 10);
print $a[0], $a[$#a], $#a, scalar(@a), $tag, "\n";
print( (@a[0, 1]), $h{a}, $h{$k[0]}, (@h{"a"}), scalar(keys %h), "\n");
print exists $h{a}, exists $h{c}, $gone, scalar(@{w}), "\n";
print $::s, $::p[0], scalar(@::p), scalar(keys %::g), $::g{z}, "\n";
push @a, scalar(values %h);
unshift @a, $#a;
my %one = (solo => 11);
my ($ek, $ev) = each %one;
print $a[0], $a[$#a], scalar(@a), $ek, $ev, "\n";
```

```behavior
parses: yes
```

```output
7plain23x-y
70.51212
142
782110
325solo11
```

```ir
main::__PROGRAM__: {start: 0, returns: [105], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "42"}, ~, ~, Int], # 2
  [Constant, {const_type: number, value: "0.5"}, ~, ~, Num], # 3
  [Constant, {const_type: string, value: plain}, ~, ~, Str], # 4
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3, 4], ~, Array], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Constant, {const_type: string, value: solo}, ~, ~, Str], # 7
  [Constant, {const_type: integer, value: "11"}, ~, ~, Int], # 8
  [HashLiteral, {sigil: "%", symbol: one}, [7, 8], ~, Hash], # 9
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 12
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 13
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 14
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 15
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 16
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 17
  [HashLiteral, {sigil: "%", symbol: h}, [10, 11, 12, 13, 14, 15, 16, 17], ~, Hash], # 18
  [EntryDef, {package: main, sigil: "%", symbol: g}, ~, ~, Hash], # 19
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 20
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 21
  [HashLiteral, {sigil: "%", symbol: "%main::g"}, [20, 21], ~, Hash], # 22
  [EntryDef, {package: main, sigil: "@", symbol: p}, ~, ~, Array], # 23
  [Constant, {const_type: integer, value: "8"}, ~, ~, Int], # 24
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 25
  [ArrayLiteral, {sigil: "@", symbol: "@main::p"}, [24, 25], ~, Array], # 26
  [EntryDef, {package: main, sigil: $, symbol: s}, ~, ~, Scalar], # 27
  [Subscript, ~, [5, 6], ~, Str], # 28
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 29
  [Assign, ~, [28, 29], 0, Int], # 30
  [Delete, ~, [18, 14, 30], 30, Scalar], # 31
  [Delete, ~, [18, 16, 31], 31, Scalar], # 32
  [Subscript, ~, [5, 6, 32], ~, Scalar], # 33
  [EntryWrite, ~, [27, 33, 32], 32, Unknown], # 34
  [EntryWrite, ~, [23, 26, 34], 34, Unknown], # 35
  [EntryWrite, ~, [19, 22, 35], 35, Unknown], # 36
  [Call, {dispatch_kind: builtin, name: values, param_names: []}, [18, 36], ~, Int], # 37
  [EntryDef, {package: main, sigil: $, symbol: s}, [36], ~, Scalar], # 38
  [Coerce, {from_repr: Unknown, to_repr: Str}, [38], ~, Str], # 39
  [Subscript, ~, [26, 6, 36], ~, Scalar], # 40
  [Coerce, {from_repr: Unknown, to_repr: Str}, [40], ~, Str], # 41
  [Count, ~, [26, 36], ~, Int], # 42
  [Coerce, {from_repr: Int, to_repr: Str}, [42], ~, Str], # 43
  [Call, {dispatch_kind: builtin, name: keys, param_names: []}, [19, 36], ~, Int], # 44
  [Coerce, {from_repr: Int, to_repr: Str}, [44], ~, Str], # 45
  [Subscript, ~, [22, 20, 36], ~, Scalar], # 46
  [Coerce, {from_repr: Unknown, to_repr: Str}, [46], ~, Str], # 47
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 48
  [Exists, ~, [18, 10, 36], ~, Boolean], # 49
  [Coerce, {from_repr: Boolean, to_repr: Str}, [49], ~, Str], # 50
  [Exists, ~, [18, 14, 36], ~, Boolean], # 51
  [Coerce, {from_repr: Boolean, to_repr: Str}, [51], ~, Str], # 52
  [Coerce, {from_repr: Scalar, to_repr: Str}, [32], ~, Str], # 53
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 54
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 55
  [ArrayLiteral, {sigil: "@", symbol: w}, [54, 55], ~, Array], # 56
  [Count, ~, [56, 36], ~, Int], # 57
  [Coerce, {from_repr: Int, to_repr: Str}, [57], ~, Str], # 58
  [Slice, ~, [6, 11, 5], ~, List], # 59
  [Coerce, {from_repr: List, to_repr: Str}, [59], ~, Str], # 60
  [Subscript, ~, [18, 10, 36], ~, Scalar], # 61
  [Coerce, {from_repr: Unknown, to_repr: Str}, [61], ~, Str], # 62
  [ArrayLiteral, {sigil: "@", symbol: k}, [12], ~, Array], # 63
  [Subscript, ~, [63, 6, 36], ~, Scalar], # 64
  [Subscript, ~, [18, 64, 36], ~, Scalar], # 65
  [Coerce, {from_repr: Unknown, to_repr: Str}, [65], ~, Str], # 66
  [Slice, ~, [10, 18], ~, List], # 67
  [Coerce, {from_repr: List, to_repr: Str}, [67], ~, Str], # 68
  [Call, {dispatch_kind: builtin, name: keys, param_names: []}, [18, 36], ~, Int], # 69
  [Coerce, {from_repr: Int, to_repr: Str}, [69], ~, Str], # 70
  [Subscript, ~, [5, 6, 36], ~, Scalar], # 71
  [Coerce, {from_repr: Unknown, to_repr: Str}, [71], ~, Str], # 72
  [Count, ~, [5, 36], ~, Int], # 73
  [Subtract, ~, [73, 11], ~, Int], # 74
  [Subscript, ~, [5, 74, 36], ~, Str], # 75
  [Coerce, {from_repr: Int, to_repr: Str}, [74], ~, Str], # 76
  [Coerce, {from_repr: Int, to_repr: Str}, [73], ~, Str], # 77
  [Subscript, ~, [56, 6, 32], ~, Scalar], # 78
  [Coerce, {from_repr: Unknown, to_repr: Str}, [78], ~, Str], # 79
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 80
  [Concat, ~, [79, 80], ~, Str], # 81
  [Subscript, ~, [56, 11, 32], ~, Scalar], # 82
  [Coerce, {from_repr: Unknown, to_repr: Str}, [82], ~, Str], # 83
  [Concat, ~, [81, 83], ~, Str], # 84
  [Print, ~, [72, 75, 76, 77, 84, 48], 36, Scalar], # 85
  [Print, ~, [60, 62, 66, 68, 70, 48], 85, Scalar], # 86
  [Print, ~, [50, 52, 53, 58, 48], 86, Scalar], # 87
  [Print, ~, [39, 41, 43, 45, 47, 48], 87, Scalar], # 88
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [5, 37, 36], 88, Int], # 89
  [Count, ~, [5, 89], ~, Int], # 90
  [Subtract, ~, [90, 11], ~, Int], # 91
  [Call, {dispatch_kind: builtin, name: unshift, param_names: []}, [5, 91, 89], 89, Int], # 92
  [Call, {dispatch_kind: builtin, name: each, param_names: []}, [9, 92], 92, Unknown], # 93
  [Subscript, ~, [5, 6, 93], ~, Scalar], # 94
  [Coerce, {from_repr: Unknown, to_repr: Str}, [94], ~, Str], # 95
  [Count, ~, [5, 93], ~, Int], # 96
  [Subtract, ~, [96, 11], ~, Int], # 97
  [Subscript, ~, [5, 97, 93], ~, Str], # 98
  [Coerce, {from_repr: Int, to_repr: Str}, [96], ~, Str], # 99
  [PadAccess, {sigil: $, symbol: ek}, ~, ~, Str], # 100
  [Coerce, {from_repr: Unknown, to_repr: Str}, [100], ~, Str], # 101
  [PadAccess, {sigil: $, symbol: ev}, ~, ~, Str], # 102
  [Coerce, {from_repr: Unknown, to_repr: Str}, [102], ~, Str], # 103
  [Print, ~, [95, 98, 99, 101, 103, 48], 93, Scalar], # 104
  [Return, ~, [1], 104], # 105
  [Assign, ~, [100, 102, 93], ~, List], # 106
  [PadAccess, {sigil: $, symbol: tag}, ~, ~, Str], # 107
  [VarDecl, {scope: my}, [107, 84]]]} # 108
```
