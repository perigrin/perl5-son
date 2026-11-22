# Every construct, each beside another

One body holding every construct this tier introduces, each adjacent to
another, and adjacent to tier 01's literals.

**Tier 02 variables.** Introduces `aassign`, `aelem`, `aelemfast`,
`aelemfast_lex`, `aelemfastlex_store`, `aslice`, `av2arylen`, `delete`,
`each`, `gv`, `gvsv`, `helem`, `hslice`, `keys`, `multideref`, `padav`,
`padhv`, `push`, `rv2av`, `rv2hv`, `sassign`, `shift`, `unshift`,
`values`. Depends on 01_literals. The mixture itself is the subject; it introduces
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
main::__PROGRAM__: {start: 0, returns: [107], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "42"}, ~, ~, Int], # 2
  [Constant, {const_type: number, value: "0.5"}, ~, ~, Num], # 3
  [Constant, {const_type: string, value: plain}, ~, ~, Str], # 4
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3, 4], ~, Array], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [PadAccess, {sigil: $, symbol: ek}, ~, ~, Str], # 7
  [PadAccess, {sigil: $, symbol: ev}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: solo}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "11"}, ~, ~, Int], # 10
  [HashLiteral, {sigil: "%", symbol: one}, [9, 10], ~, Hash], # 11
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 12
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 13
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 14
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 15
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 16
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 17
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 18
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 19
  [HashLiteral, {sigil: "%", symbol: h}, [12, 13, 14, 15, 16, 17, 18, 19], ~, Hash], # 20
  [EntryDef, {package: main, sigil: "%", symbol: g}, ~, ~, Hash], # 21
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 22
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 23
  [HashLiteral, {sigil: "%", symbol: "%main::g"}, [22, 23], ~, Hash], # 24
  [EntryDef, {package: main, sigil: "@", symbol: p}, ~, ~, Array], # 25
  [Constant, {const_type: integer, value: "8"}, ~, ~, Int], # 26
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 27
  [ArrayLiteral, {sigil: "@", symbol: "@main::p"}, [26, 27], ~, Array], # 28
  [EntryDef, {package: main, sigil: $, symbol: s}, ~, ~, Scalar], # 29
  [Subscript, {kind: array}, [5, 6], ~, Str], # 30
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 31
  [MemStart], # 32
  [Assign, ~, [30, 31], 0, Int, 32, true], # 33
  [Delete, {kind: hash}, [20, 16], 33, Scalar, 33, true], # 34
  [Delete, {kind: hash}, [20, 18], 34, Scalar, 34, true], # 35
  [Subscript, {kind: array}, [5, 6], ~, Scalar, 35], # 36
  [EntryWrite, ~, [29, 36], 35, Unknown, 35, true], # 37
  [EntryWrite, ~, [25, 28], 37, Unknown, 37, true], # 38
  [EntryWrite, ~, [21, 24], 38, Unknown, 38, true], # 39
  [Call, {dispatch_kind: builtin, name: values, param_names: [], want: scalar}, [20], ~, Int, 39], # 40
  [EntryDef, {package: main, sigil: $, symbol: s}, ~, ~, Scalar, 39], # 41
  [Coerce, {from_repr: Unknown, to_repr: Str}, [41], ~, Str], # 42
  [Subscript, {kind: array}, [28, 6], ~, Scalar, 39], # 43
  [Coerce, {from_repr: Unknown, to_repr: Str}, [43], ~, Str], # 44
  [Count, ~, [28], ~, Int, 39], # 45
  [Coerce, {from_repr: Int, to_repr: Str}, [45], ~, Str], # 46
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: scalar}, [21], ~, Int, 39], # 47
  [Coerce, {from_repr: Int, to_repr: Str}, [47], ~, Str], # 48
  [Subscript, {kind: hash}, [24, 22], ~, Scalar, 39], # 49
  [Coerce, {from_repr: Unknown, to_repr: Str}, [49], ~, Str], # 50
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 51
  [Exists, {kind: hash}, [20, 12], ~, Boolean, 39], # 52
  [Coerce, {from_repr: Boolean, to_repr: Str}, [52], ~, Str], # 53
  [Exists, {kind: hash}, [20, 16], ~, Boolean, 39], # 54
  [Coerce, {from_repr: Boolean, to_repr: Str}, [54], ~, Str], # 55
  [Coerce, {from_repr: Scalar, to_repr: Str}, [35], ~, Str], # 56
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 57
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 58
  [ArrayLiteral, {sigil: "@", symbol: w}, [57, 58], ~, Array], # 59
  [Count, ~, [59], ~, Int, 39], # 60
  [Coerce, {from_repr: Int, to_repr: Str}, [60], ~, Str], # 61
  [Slice, {kind: array}, [6, 13, 5], ~, List, 39], # 62
  [Coerce, {from_repr: List, to_repr: Str}, [62], ~, Str], # 63
  [Subscript, {kind: hash}, [20, 12], ~, Scalar, 39], # 64
  [Coerce, {from_repr: Unknown, to_repr: Str}, [64], ~, Str], # 65
  [ArrayLiteral, {sigil: "@", symbol: k}, [14], ~, Array], # 66
  [Subscript, {kind: array}, [66, 6], ~, Scalar, 39], # 67
  [Subscript, {kind: hash}, [20, 67], ~, Scalar, 39], # 68
  [Coerce, {from_repr: Unknown, to_repr: Str}, [68], ~, Str], # 69
  [Slice, {kind: hash}, [12, 20], ~, List, 39], # 70
  [Coerce, {from_repr: List, to_repr: Str}, [70], ~, Str], # 71
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: scalar}, [20], ~, Int, 39], # 72
  [Coerce, {from_repr: Int, to_repr: Str}, [72], ~, Str], # 73
  [Subscript, {kind: array}, [5, 6], ~, Scalar, 39], # 74
  [Coerce, {from_repr: Unknown, to_repr: Str}, [74], ~, Str], # 75
  [Count, ~, [5], ~, Int, 39], # 76
  [Subtract, ~, [76, 13], ~, Int], # 77
  [Subscript, {kind: array}, [5, 77], ~, Str, 39], # 78
  [Coerce, {from_repr: Int, to_repr: Str}, [77], ~, Str], # 79
  [Coerce, {from_repr: Int, to_repr: Str}, [76], ~, Str], # 80
  [Subscript, {kind: array}, [59, 6], ~, Scalar, 35], # 81
  [Coerce, {from_repr: Unknown, to_repr: Str}, [81], ~, Str], # 82
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 83
  [Concat, ~, [82, 83], ~, Str], # 84
  [Subscript, {kind: array}, [59, 13], ~, Scalar, 35], # 85
  [Coerce, {from_repr: Unknown, to_repr: Str}, [85], ~, Str], # 86
  [Concat, ~, [84, 86], ~, Str], # 87
  [Print, ~, [75, 78, 79, 80, 87, 51], 39, "Maybe[Boolean]"], # 88
  [Print, ~, [63, 65, 69, 71, 73, 51], 88, "Maybe[Boolean]"], # 89
  [Print, ~, [53, 55, 56, 61, 51], 89, "Maybe[Boolean]"], # 90
  [Print, ~, [42, 44, 46, 48, 50, 51], 90, "Maybe[Boolean]"], # 91
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [5, 40], 91, Int, 39, true], # 92
  [Count, ~, [5], ~, Int, 92], # 93
  [Subtract, ~, [93, 13], ~, Int], # 94
  [Call, {dispatch_kind: builtin, name: unshift, param_names: []}, [5, 94], 92, Int, 92, true], # 95
  [Call, {dispatch_kind: builtin, name: each, param_names: [], want: list}, [11], 95, Unknown, 95, true], # 96
  [Assign, {targets: 2}, [7, 8, 96], 96, List, 96, true], # 97
  [Subscript, {kind: array}, [5, 6], ~, Scalar, 97], # 98
  [Coerce, {from_repr: Unknown, to_repr: Str}, [98], ~, Str], # 99
  [Count, ~, [5], ~, Int, 97], # 100
  [Subtract, ~, [100, 13], ~, Int], # 101
  [Subscript, {kind: array}, [5, 101], ~, Str, 97], # 102
  [Coerce, {from_repr: Int, to_repr: Str}, [100], ~, Str], # 103
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 104
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 105
  [Print, ~, [99, 102, 103, 104, 105, 51], 97, "Maybe[Boolean]"], # 106
  [Return, {implicit: true}, [1], 106, ~, 97], # 107
  [PadAccess, {sigil: $, symbol: tag}, ~, ~, Str], # 108
  [VarDecl, {scope: my}, [108, 87]]]} # 109
```
