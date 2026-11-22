# use, require and import

`use Foo LIST` locates a file, loads it, and then calls
`Foo->import(LIST)`. `require` is the same construct with the import
step removed, and `import` is an ordinary method call. Those three
statements are this whole area.

**Tier 12 packages.** Introduces `require`. Depends on 07_subroutines.

`use` EMITS NOTHING -- it is a `BEGIN` block that has finished before
there is an optree to dump. `require` is the one construct here that
reaches run time and the one op this tier introduces: `require strict;`
emits `const[PV "strict.pm"] s/BARE` and then `require`, `require $m`
emits `padsv` and the same `require`. One op, several sources. `import`
emits `pushmark`, two `const`, `method_named` and `entersub` -- tiers
01, 07 and 11 between them, with nothing left over. There is no import
op; the reason `use` is heavier than `require` is a call the op stream
cannot distinguish from any other call.

Because both halves of `use` are compile-time, the cases observe them
through `%INC` and the symbol table rather than through anything the
loaded module emits. The `04`/`05` pair is where the tier's claim
actually lives: neither case alone separates loading from importing.

## `use strict;` lexes, and that is all it establishes

A pragma is a `BEGIN` block, finished before there is a runtime optree.
The op stream for this case is the stream for `my $x = "ok"; print
"$x\n"` alone, differing only in the feature bits printed on
`nextstate`, which are a field rather than an op.

WHAT THIS CASE DOES NOT REACH, stated plainly because the pin does not
say it. Measured: delete both `use` lines and this program still prints
`ok`. So the pin establishes that the lines LEX and the statement is
delimited, and it establishes nothing about the load or the import. A
pragma cannot do better -- its effect is lexical and compile-time, and
`$^H` and `${^WARNING_BITS}` consulted at run time report the CALLER's
scope, measured OFF inside the very file that turned them on.

It is kept because `use` with a pragma is the overwhelmingly common
spelling and a lexer that mis-delimited it would fail here. The case
that reaches the rest is the next one.

```perl
use strict;
use warnings;
my $x = "ok";
print "$x\n";
```

```behavior
parses: yes
```

```output
ok
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ok}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 3
  [Concat, ~, [2, 3], ~, Str], # 4
  [Print, ~, [4], 0, "Maybe[Boolean]"], # 5
  [MemStart], # 6
  [Return, {implicit: true}, [1], 5, ~, 6]]} # 7
"BEGIN 1": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: strict}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: strict.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: strict, dispatch_kind: method, file: "/tmp/ucZOh245UI/case.pl", line: 1, name: import, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/ucZOh245UI/case.pl", line: 2, name: import, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
```

## `use POSIX;` loads the file AND calls import

This is the case that makes `use` FALSIFIABLE, through a module with an
exporter and the symbol table. `use POSIX;` puts `floor` into `main::`,
and deleting the `use` line changes both pinned lines -- so the output
measures the statement rather than its absence of syntax errors.

POSIX is core, its import list is not versioned in any way this case
observes, and nothing here depends on what it prints, because it prints
nothing.

MEASURED perl 5.42.0:

    $ perl -e 'use POSIX; print +($INC{"POSIX.pm"} ? "yes" : "no"), ($main::{"floor"} ? "yes" : "no"), "\n"'
    yesyes

```perl
use POSIX;
print "POSIX loaded: ", ($INC{"POSIX.pm"} ? "yes" : "no"), "\n";
print "floor imported: ", ($main::{"floor"} ? "yes" : "no"), "\n";
```

```behavior
parses: yes
```

```output
POSIX loaded: yes
floor imported: yes
```

```ir
Carp::_cgc: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: code, value: CORE::GLOBAL::caller}, ~, ~, Code], # 1
  [Ref, ~, [1], ~, CodeRef], # 2
  [ArrayLiteral, ~, ~, ~, List], # 3
  [Constant, {const_type: string, value: CORE::GLOBAL::caller}, ~, ~, Str], # 4
  [Defined, ~, [4], ~, Boolean], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 0}, [6]], # 7
  [Proj, {index: 1}, [6]], # 8
  [Region, {head: 6}, [7, 8]], # 9
  [Phi, {predecessors: [7, 8], region: 9}, [2, 3], ~, List], # 10
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 11
  [Phi, {predecessors: [7, 8], region: 9}, [2, 11], ~, "Maybe[CodeRef]"], # 12
  [MemStart], # 13
  [Return, ~, [10, 12], 9, ~, 13]]} # 14
Carp::_fetch_sub: {start: 0, returns: [64], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [Constant, {const_type: boolean, value: ""}, ~, ~, Boolean], # 2
  [EntryDef, {package: main, sigil: "%", symbol: "main::"}, ~, ~, Hash], # 3
  [PadAccess, {sigil: $, symbol: pack}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "::"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [MemStart], # 7
  [Exists, {kind: hash}, [3, 6], ~, Boolean, 7], # 8
  [Not, ~, [8], ~, Boolean], # 9
  [If, ~, [0, 9], 0], # 10
  [Proj, {index: 0}, [10]], # 11
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 12
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar, 7], # 13
  [Proj, {index: 1}, [10]], # 14
  [Loop, {bound: entry}, [14], 14], # 15
  [Proj, {index: 1}, [15]], # 16
  [Region, {head: 15}, [16]], # 17
  [Phi, {memory: true, region: 15}, [7, 18], ~, Unknown], # 18
  [Phi, {memory: true, region: 17}, [18], ~, Unknown], # 19
  [EntryWrite, ~, [12, 13], 17, Unknown, 19, true], # 20
  [Region, {head: 10}, [11, 20]], # 21
  [Phi, {predecessors: [11, 14], region: 21}, [1, 2], ~, List], # 22
  [ArrayLiteral, ~, ~, ~, List], # 23
  [Subscript, {kind: hash}, [3, 6], ~, Scalar], # 24
  [ArrayLiteral, ~, [24], ~, Array], # 25
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 26
  [Phi, {region: 15}, [26, 73], ~, Int], # 27
  [Subscript, {kind: array}, [25, 27], ~, Scalar, 18], # 28
  [PadAccess, {sigil: $, symbol: sub}, ~, ~, Unknown], # 29
  [Subscript, {kind: hash}, [28, 29], ~, Scalar], # 30
  [ArrayLiteral, ~, [30], ~, Array], # 31
  [Proj, {index: 0}, [15]], # 32
  [Call, {dispatch_kind: builtin, name: reftype_of_ref, param_names: []}, [28], ~, Str, 18], # 33
  [Constant, {const_type: string, value: GLOB}, ~, ~, Str], # 34
  [StrEq, ~, [33, 34], ~, Boolean], # 35
  [Constant, {const_type: string, value: HASH}, ~, ~, Str], # 36
  [Subscript, ~, [28, 36], ~, Scalar, 18], # 37
  [And, ~, [35, 37], ~, Scalar], # 38
  [If, ~, [32, 38], 32], # 39
  [Proj, {index: 0}, [39]], # 40
  [Proj, {index: 1}, [39]], # 41
  [Region, {head: 39}, [40, 41]], # 42
  [Exists, {kind: hash}, [28, 29], ~, Boolean, 18], # 43
  [Phi, {predecessors: [40, 41], region: 42}, [43, 38], ~, Scalar], # 44
  [If, ~, [42, 44], 42], # 45
  [Proj, {index: 0}, [45]], # 46
  [Loop, {bound: entry}, [46], 46], # 47
  [Phi, {region: 47}, [26, 76], ~, Int], # 48
  [Subscript, {kind: array}, [31, 48], ~, Scalar, 18], # 49
  [Call, {dispatch_kind: builtin, name: reftype_of_ref, param_names: []}, [49], ~, Str, 18], # 50
  [StrEq, ~, [50, 34], ~, Boolean], # 51
  [Constant, {const_type: string, value: CODE}, ~, ~, Str], # 52
  [Subscript, ~, [49, 52], ~, Scalar, 18], # 53
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 54
  [TernaryExpr, ~, [51, 53, 54], ~, Unknown], # 55
  [Proj, {index: 1}, [45]], # 56
  [Proj, {index: 0}, [47]], # 57
  [Region, ~, [21, 56, 57]], # 58
  [Phi, {predecessors: [21, 56, 57], region: 58}, [22, 23, 55], ~, Unknown], # 59
  [Phi, {predecessors: [11, 14], region: 21}, [54, 2], ~, "Maybe[Boolean]"], # 60
  [Phi, {predecessors: [21, 56, 57], region: 58}, [60, 54, 55], ~, Unknown], # 61
  [Phi, {exits: true, memory: true, predecessors: [11, 14], region: 21}, [7, 20], ~, Unknown], # 62
  [Phi, {exits: true, memory: true, predecessors: [21, 56, 57], region: 58}, [62, 18, 18], ~, Unknown], # 63
  [Return, ~, [59, 61], 58, ~, 63], # 64
  [Count, ~, [25], ~, Int, 18], # 65
  [Count, ~, [31], ~, Int, 18], # 66
  [NumGt, ~, [65, 27], 15, Boolean], # 67
  [NumGt, ~, [66, 48], 47, Boolean], # 68
  [Proj, {index: 1}, [47]], # 69
  [Count, ~, [25], ~, Int, 7], # 70
  [Region, {head: 47}, [69]], # 71
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 72
  [Add, ~, [27, 72], ~, Int], # 73
  [ArgsSource, ~, ~, ~, Array], # 74
  [Assign, {record: true, targets: 2}, [4, 29, 74], ~, List], # 75
  [Add, ~, [48, 72], ~, Int]]} # 76
Carp::_univ_mod_loaded: {start: 0, returns: [89], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Constant, {const_type: boolean, value: ""}, ~, ~, Boolean], # 2
  [EntryDef, {package: main, sigil: "%", symbol: "main::"}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: "UNIVERSAL::"}, ~, ~, Str], # 4
  [MemStart], # 5
  [Exists, {kind: hash}, [3, 4], ~, Boolean, 5], # 6
  [Not, ~, [6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 10
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar, 5], # 11
  [Proj, {index: 1}, [8]], # 12
  [Loop, {bound: entry}, [12], 12], # 13
  [Proj, {index: 1}, [13]], # 14
  [Region, {head: 13}, [14]], # 15
  [Phi, {memory: true, region: 13}, [5, 93], ~, Unknown], # 16
  [Phi, {memory: true, region: 15}, [16], ~, Unknown], # 17
  [EntryWrite, ~, [10, 11], 15, Unknown, 17, true], # 18
  [Region, {head: 8}, [9, 18]], # 19
  [Phi, {predecessors: [9, 12], region: 19}, [1, 2], ~, Scalar], # 20
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 21
  [ArrayLiteral, ~, [21], ~, Array], # 22
  [Phi, {region: 13}, [1, 103], ~, Int], # 23
  [Subscript, {kind: array}, [22, 23], ~, Scalar, 16], # 24
  [ArgsSource, ~, ~, ~, Array], # 25
  [Subscript, {kind: array}, [25, 1], ~, Scalar, 16], # 26
  [Coerce, {from_repr: Unknown, to_repr: Str}, [26], ~, Str], # 27
  [Constant, {const_type: string, value: "::"}, ~, ~, Str], # 28
  [Concat, ~, [27, 28], ~, Str], # 29
  [Subscript, {kind: hash}, [24, 29], ~, Scalar], # 30
  [ArrayLiteral, ~, [30], ~, Array], # 31
  [Proj, {index: 0}, [13]], # 32
  [Call, {dispatch_kind: builtin, name: reftype_of_ref, param_names: []}, [24], ~, Str, 16], # 33
  [Constant, {const_type: string, value: GLOB}, ~, ~, Str], # 34
  [StrEq, ~, [33, 34], ~, Boolean], # 35
  [Constant, {const_type: string, value: HASH}, ~, ~, Str], # 36
  [Subscript, ~, [24, 36], ~, Scalar, 16], # 37
  [And, ~, [35, 37], ~, Scalar], # 38
  [If, ~, [32, 38], 32], # 39
  [Proj, {index: 0}, [39]], # 40
  [Proj, {index: 1}, [39]], # 41
  [Region, {head: 39}, [40, 41]], # 42
  [Exists, {kind: hash}, [24, 29], ~, Boolean, 16], # 43
  [Phi, {predecessors: [40, 41], region: 42}, [43, 38], ~, Scalar], # 44
  [If, ~, [42, 44], 42], # 45
  [Proj, {index: 0}, [45]], # 46
  [Loop, {bound: entry}, [46], 46], # 47
  [Phi, {region: 47}, [1, 104], ~, Int], # 48
  [Phi, {memory: true, region: 47}, [16, 98], ~, Unknown], # 49
  [Subscript, {kind: array}, [31, 48], ~, Scalar, 49], # 50
  [Constant, {const_type: string, value: VERSION}, ~, ~, Str], # 51
  [Subscript, {kind: hash}, [50, 51], ~, Scalar], # 52
  [ArrayLiteral, ~, [52], ~, Array], # 53
  [Proj, {index: 0}, [47]], # 54
  [Call, {dispatch_kind: builtin, name: reftype_of_ref, param_names: []}, [50], ~, Str, 49], # 55
  [StrEq, ~, [55, 34], ~, Boolean], # 56
  [Subscript, ~, [50, 36], ~, Scalar, 49], # 57
  [And, ~, [56, 57], ~, Scalar], # 58
  [If, ~, [54, 58], 54], # 59
  [Proj, {index: 0}, [59]], # 60
  [Proj, {index: 1}, [59]], # 61
  [Region, {head: 59}, [60, 61]], # 62
  [Exists, {kind: hash}, [50, 51], ~, Boolean, 49], # 63
  [Phi, {predecessors: [60, 61], region: 62}, [63, 58], ~, Scalar], # 64
  [If, ~, [62, 64], 62], # 65
  [Proj, {index: 0}, [65]], # 66
  [Loop, {bound: entry}, [66], 66], # 67
  [Phi, {region: 67}, [1, 106], ~, Int], # 68
  [Phi, {memory: true, region: 67}, [49, 78], ~, Unknown], # 69
  [Subscript, {kind: array}, [53, 68], ~, Scalar, 69], # 70
  [Constant, {const_type: string, value: SCALAR}, ~, ~, Str], # 71
  [Subscript, ~, [70, 71], ~, Scalar, 69], # 72
  [Proj, {index: 0}, [67]], # 73
  [Call, {dispatch_kind: builtin, name: reftype_of_ref, param_names: []}, [70], ~, Str, 69], # 74
  [StrEq, ~, [74, 34], ~, Boolean], # 75
  [If, ~, [73, 75], 73], # 76
  [Proj, {index: 0}, [76]], # 77
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 127, package: Carp, sigil: $, strict: true}, [72], 77, Scalar, 69, true], # 78
  [Proj, {index: 1}, [76]], # 79
  [Region, {head: 76}, [79, 78]], # 80
  [Phi, {predecessors: [79, 77], region: 80}, [1, 78], ~, Scalar], # 81
  [Proj, {index: 1}, [45]], # 82
  [Proj, {index: 1}, [65]], # 83
  [Region, ~, [19, 82, 83, 80]], # 84
  [Phi, {predecessors: [19, 82, 83, 73], region: 84}, [20, 1, 1, 81], ~, Scalar], # 85
  [Phi, {exits: true, memory: true, predecessors: [9, 12], region: 19}, [5, 18], ~, Unknown], # 86
  [Phi, {exits: true, memory: true, predecessors: [79, 77], region: 80}, [69, 78], ~, Unknown], # 87
  [Phi, {exits: true, memory: true, predecessors: [19, 82, 83, 73], region: 84}, [86, 16, 49, 87], ~, Unknown], # 88
  [Return, ~, [85], 84, ~, 88], # 89
  [Proj, {index: 1}, [47]], # 90
  [Region, {head: 47}, [90]], # 91
  [Phi, {memory: true, region: 91}, [49], ~, Unknown], # 92
  [EntryWrite, ~, [10, 24], 91, Unknown, 92, true], # 93
  [Count, ~, [22], ~, Int, 16], # 94
  [Count, ~, [31], ~, Int, 16], # 95
  [Proj, {index: 1}, [67]], # 96
  [Region, {head: 67}, [96]], # 97
  [Phi, {memory: true, region: 97}, [69], ~, Unknown], # 98
  [Count, ~, [31], ~, Int, 49], # 99
  [Count, ~, [53], ~, Int, 49], # 100
  [NumGt, ~, [94, 23], 13, Boolean], # 101
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 102
  [Add, ~, [23, 102], ~, Int], # 103
  [Add, ~, [48, 102], ~, Int], # 104
  [NumGt, ~, [99, 48], 47, Boolean], # 105
  [Add, ~, [68, 102], ~, Int], # 106
  [Count, ~, [53], ~, Int, 69], # 107
  [NumGt, ~, [107, 68], 67, Boolean], # 108
  [Count, ~, [22], ~, Int, 5]]} # 109
Carp::caller_info: {start: 0, returns: [194], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [Wantarray, ~, ~, ~, Scalar], # 2
  [PadAccess, {sigil: "%", symbol: call_info}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: sub_name}, ~, ~, Str], # 4
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 5
  [Ref, ~, [3], ~, HashRef], # 6
  [Constant, {const_type: string, value: pack}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: file}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: line}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: sub}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: has_args}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: wantarray}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: evaltext}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: is_require}, ~, ~, Str], # 14
  [Slice, {kind: hash}, [7, 8, 9, 10, 11, 12, 13, 14, 3], ~, List], # 15
  [ArgsSource, ~, ~, ~, Array], # 16
  [MemStart], # 17
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [16], 0, Scalar, 17, true], # 18
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 18], # 19
  [Coerce, {from_repr: Scalar, to_repr: Num}, [18], ~, Num], # 20
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 21
  [Add, ~, [20, 21], ~, Num], # 22
  [Assign, ~, [19, 22], 18, Num, 18, true], # 23
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 308, name: Carp::_cgc, package: Carp, param_names: [], want: scalar}, ~, 23, List, 23, true], # 24
  [EntryDef, {package: DB, sigil: "@", symbol: args}, ~, ~, Array], # 25
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 24], # 26
  [Ref, ~, [26], ~, Unknown], # 27
  [ArrayLiteral, {sigil: "@", symbol: "@DB::args"}, [27], ~, Array], # 28
  [EntryWrite, ~, [25, 28], 24, Unknown, 24, true], # 29
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 29], # 30
  [If, ~, [29, 24], 29], # 31
  [Proj, {index: 0}, [31]], # 32
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 320, name: "", package: DB, param_names: [], want: list}, [24, 30], 32, Unknown, 29, true], # 33
  [Proj, {index: 1}, [31]], # 34
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, [30], 34, List, 29], # 35
  [Region, {head: 31}, [33, 35]], # 36
  [Phi, {predecessors: [32, 34], region: 36}, [33, 35], ~, Unknown], # 37
  [Phi, {memory: true, predecessors: [32, 34], region: 36}, [33, 29], ~, Unknown], # 38
  [Assign, {targets: 1}, [15, 37], 36, Unknown, 38, true], # 39
  [Subscript, {kind: hash}, [3, 8], ~, Scalar, 39], # 40
  [Defined, ~, [40], ~, Boolean], # 41
  [Not, ~, [41], ~, Boolean], # 42
  [If, ~, [39, 42], 39], # 43
  [Proj, {index: 1}, [43]], # 44
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 328, name: Carp::get_subname, package: Carp, param_names: [], want: scalar}, [6], 44, Scalar, 39, true], # 45
  [Coerce, {from_repr: Scalar, to_repr: Str}, [45], ~, Str], # 46
  [Constant, {const_type: string, value: "("}, ~, ~, Str], # 47
  [Concat, ~, [46, 47], ~, Str], # 48
  [Constant, {const_type: string, value: ", "}, ~, ~, Str], # 49
  [Constant, {const_type: string, value: "** Incomplete caller override detected"}, ~, ~, Str], # 50
  [Constant, {const_type: string, value: " in &"}, ~, ~, Str], # 51
  [Constant, {const_type: string, value: B}, ~, ~, Str], # 52
  [Constant, {const_type: string, value: svref_2object}, ~, ~, Str], # 53
  [Subscript, {kind: hash}, [3, 11], ~, Scalar, 45], # 54
  [If, ~, [45, 54], 45], # 55
  [Proj, {index: 0}, [55]], # 56
  [Loop, {bound: entry}, [56], 56], # 57
  [Phi, {memory: true, region: 57}, [45, 229], ~, Unknown], # 58
  [Proj, {index: 1}, [57]], # 59
  [Region, {head: 57}, [59]], # 60
  [Phi, {memory: true, region: 60}, [58], ~, Unknown], # 61
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 61], # 62
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 63
  [ArrayLiteral, ~, ~, ~, Array], # 64
  [Phi, {region: 57}, [64, 238], ~, Array], # 65
  [Count, ~, [65], ~, Int, 61], # 66
  [NumEq, ~, [66, 21], ~, Boolean], # 67
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 68
  [Subscript, {kind: array}, [65, 68], ~, Scalar, 61], # 69
  [RefType, ~, [69], ~, Str, 61], # 70
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 61], # 71
  [Call, {dispatch_kind: builtin, name: reftype_of_ref, param_names: []}, [71], ~, Str, 61], # 72
  [StrEq, ~, [70, 72], ~, Boolean], # 73
  [And, ~, [67, 73], ~, Boolean], # 74
  [Coerce, {from_repr: Scalar, to_repr: Num}, [69], ~, Num], # 75
  [Ref, ~, [71], ~, Unknown], # 76
  [NumEq, ~, [75, 76], ~, Boolean], # 77
  [And, ~, [74, 77], ~, Boolean], # 78
  [If, ~, [60, 78], 60], # 79
  [Proj, {index: 0}, [79]], # 80
  [EntryWrite, ~, [62, 63], 80, Unknown, 61, true], # 81
  [PadAccess, {sigil: $, symbol: func}, ~, ~, Unknown, 81], # 82
  [Assign, ~, [82, 24], 81, List, 81, true], # 83
  [If, ~, [83, 24], 83], # 84
  [Proj, {index: 0}, [84]], # 85
  [Call, {dispatch_kind: direct, eval_id: 4, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 360, name: Carp::_fetch_sub, package: Carp, param_names: [], want: scalar}, [52, 53], 85, Unknown, 83, true], # 86
  [PadAccess, {sigil: $, symbol: func}, ~, ~, Unknown, 86], # 87
  [Not, ~, [86], ~, Boolean], # 88
  [If, ~, [86, 88], 86], # 89
  [Proj, {index: 1}, [89]], # 90
  [Call, {dispatch_kind: indirect, eval_id: 4, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 360, name: "", package: Carp, param_names: [], want: scalar}, [86, 87], 90, Unknown, 86, true], # 91
  [Call, {dispatch_kind: method, eval_id: 4, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 360, name: GV, package: Carp, param_names: [], want: scalar}, [91], 91, Unknown, 91, true], # 92
  [PadAccess, {sigil: $, symbol: gv}, ~, ~, Unknown, 92], # 93
  [Assign, ~, [93, 92], 92, Unknown, 92, true], # 94
  [PadAccess, {sigil: $, symbol: gv}, ~, ~, Unknown, 94], # 95
  [Call, {dispatch_kind: method, eval_id: 4, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 363, name: STASH, package: Carp, param_names: [], want: scalar}, [95], 94, Unknown, 94, true], # 96
  [Call, {dispatch_kind: method, eval_id: 4, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 363, name: NAME, package: Carp, param_names: [], want: scalar}, [96], 96, Unknown, 96, true], # 97
  [Coerce, {from_repr: Unknown, to_repr: Str}, [97], ~, Str], # 98
  [Concat, ~, [51, 98], ~, Str], # 99
  [Constant, {const_type: string, value: "::"}, ~, ~, Str], # 100
  [Concat, ~, [99, 100], ~, Str], # 101
  [PadAccess, {sigil: $, symbol: gv}, ~, ~, Unknown, 97], # 102
  [Call, {dispatch_kind: method, eval_id: 4, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 364, name: NAME, package: Carp, param_names: [], want: scalar}, [102], 97, Unknown, 97, true], # 103
  [Coerce, {from_repr: Unknown, to_repr: Str}, [103], ~, Str], # 104
  [Concat, ~, [101, 104], ~, Str], # 105
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 106
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 103], # 107
  [Defined, ~, [97], ~, Boolean], # 108
  [Defined, ~, [103], ~, Boolean], # 109
  [And, ~, [108, 109], ~, Boolean], # 110
  [If, ~, [103, 110], 103], # 111
  [Proj, {index: 0}, [111]], # 112
  [Constant, {const_type: string, value: CORE::GLOBAL}, ~, ~, Str], # 113
  [StrEq, ~, [98, 113], ~, Boolean], # 114
  [Constant, {const_type: string, value: caller}, ~, ~, Str], # 115
  [StrEq, ~, [104, 115], ~, Boolean], # 116
  [And, ~, [114, 116], ~, Boolean], # 117
  [If, ~, [112, 117], 112], # 118
  [Proj, {index: 1}, [118]], # 119
  [EntryWrite, ~, [107, 63], 119, Unknown, 103, true], # 120
  [Proj, {index: 1}, [84]], # 121
  [Proj, {index: 0}, [89]], # 122
  [Proj, {index: 1}, [111]], # 123
  [Proj, {index: 0}, [118]], # 124
  [Exc, ~, [86]], # 125
  [Exc, ~, [91]], # 126
  [Exc, ~, [92]], # 127
  [Exc, ~, [96]], # 128
  [Exc, ~, [97]], # 129
  [Exc, ~, [103]], # 130
  [Region, {catch: true, eval_id: 4}, [125, 126, 127, 128, 129, 130]], # 131
  [Phi, {memory: true, region: 131}, [86, 91, 92, 96, 97, 103], ~, Unknown], # 132
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 132], # 133
  [Phi, {region: 131}, [125, 126, 127, 128, 129, 130], ~, Scalar], # 134
  [EntryWrite, ~, [133, 134], 131, Unknown, 132, true], # 135
  [Region, {eval_entry: 80, eval_id: 4}, [120, 121, 122, 123, 124, 135]], # 136
  [Phi, {region: 136}, [105, 63, 63, 106, 106, 106], ~, "Maybe[Str]"], # 137
  [Or, ~, [137, 63], ~, "Maybe[Str]"], # 138
  [Coerce, {from_repr: Unknown, to_repr: Str}, [138], ~, Str], # 139
  [Concat, ~, [50, 139], ~, Str], # 140
  [Constant, {const_type: string, value: "; @DB::args were not set **"}, ~, ~, Str], # 141
  [Concat, ~, [140, 141], ~, Str], # 142
  [ArrayLiteral, {sigil: "@", symbol: args}, [142], ~, Array], # 143
  [ArrayLiteral, ~, ~, ~, Array], # 144
  [Proj, {index: 1}, [79]], # 145
  [EntryDef, {package: Carp, sigil: $, symbol: MaxArgNums}, ~, ~, Scalar, 61], # 146
  [Coerce, {from_repr: Scalar, to_repr: Num}, [146], ~, Num], # 147
  [NumGt, ~, [66, 147], ~, Boolean], # 148
  [And, ~, [146, 148], ~, Scalar], # 149
  [If, ~, [145, 149], 145], # 150
  [Proj, {index: 1}, [150]], # 151
  [Subtract, ~, [147, 21], ~, Num], # 152
  [Proj, {index: 0}, [150]], # 153
  [Call, {dispatch_kind: builtin, name: set_arylen, param_names: []}, [65, 152], 153, Int, 61, true], # 154
  [Region, {head: 150}, [151, 154]], # 155
  [Loop, {bound: entry}, [155], 155], # 156
  [Phi, {region: 156}, [144, 241], ~, Array], # 157
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 158
  [Phi, {memory: true, region: 136}, [120, 83, 86, 103, 103, 135], ~, Unknown], # 159
  [EntryWrite, ~, [158, 62], 136, Unknown, 159, true], # 160
  [Proj, {index: 1}, [156]], # 161
  [Region, {head: 156}, [161]], # 162
  [Phi, {predecessors: [151, 153], region: 155}, [106, 21], ~, "Maybe[Int]"], # 163
  [If, ~, [162, 163], 162], # 164
  [Proj, {index: 1}, [164]], # 165
  [Constant, {const_type: string, value: "..."}, ~, ~, Str], # 166
  [Proj, {index: 0}, [164]], # 167
  [Phi, {memory: true, predecessors: [151, 153], region: 155}, [61, 154], ~, Unknown], # 168
  [Phi, {memory: true, region: 156}, [168, 233], ~, Unknown], # 169
  [Phi, {memory: true, region: 162}, [169], ~, Unknown], # 170
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [157, 166], 167, Int, 170, true], # 171
  [Region, {head: 164}, [165, 171]], # 172
  [Region, {head: 79}, [160, 172]], # 173
  [Phi, {region: 173}, [143, 157], ~, Array], # 174
  [Phi, {memory: true, predecessors: [165, 167], region: 172}, [170, 171], ~, Unknown], # 175
  [Phi, {memory: true, region: 173}, [160, 175], ~, Unknown], # 176
  [PostfixDeref, {sigil: "@"}, [174], ~, Array, 176], # 177
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [49, 177], ~, Str, 176], # 178
  [Concat, ~, [48, 178], ~, Str], # 179
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 180
  [Concat, ~, [179, 180], ~, Str], # 181
  [Proj, {index: 1}, [55]], # 182
  [Region, {head: 55}, [182, 173]], # 183
  [Phi, {predecessors: [182, 56], region: 183}, [45, 181], ~, Scalar], # 184
  [Phi, {memory: true, predecessors: [182, 56], region: 183}, [45, 176], ~, Unknown], # 185
  [Assign, ~, [5, 184], 183, Scalar, 185, true], # 186
  [PadAccess, {sigil: "%", symbol: call_info}, ~, ~, Hash, 186], # 187
  [TernaryExpr, ~, [2, 187, 6], ~, Unknown], # 188
  [Proj, {index: 0}, [43]], # 189
  [Region, {head: 43}, [189, 186]], # 190
  [Phi, {predecessors: [189, 44], region: 190}, [1, 188], ~, Unknown], # 191
  [Phi, {predecessors: [189, 44], region: 190}, [106, 188], ~, Unknown], # 192
  [Phi, {exits: true, memory: true, predecessors: [189, 44], region: 190}, [39, 186], ~, Unknown], # 193
  [Return, ~, [191, 192], 190, ~, 193], # 194
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 58], # 195
  [Proj, {index: 0}, [57]], # 196
  [Assign, ~, [195, 106], 196, Undef, 58, true], # 197
  [Phi, {region: 156}, [68, 217], ~, Int], # 198
  [Proj, {index: 0}, [156]], # 199
  [Exists, {kind: array}, [65, 198], 199, Boolean, 169], # 200
  [Subscript, {kind: array}, [65, 198], ~, Scalar], # 201
  [Ref, ~, [201], ~, ScalarRef], # 202
  [TernaryExpr, ~, [200, 202, 106], ~, "Maybe[ScalarRef]"], # 203
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 197], # 204
  [EntryWrite, ~, [158, 204], 197, Unknown, 197, true], # 205
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 205], # 206
  [EntryWrite, ~, [206, 63], 205, Unknown, 205, true], # 207
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 207], # 208
  [Phi, {region: 57}, [68, 216], ~, Int], # 209
  [Subscript, {kind: array}, [25, 209], ~, Scalar, 58], # 210
  [Assign, ~, [208, 210], 207, Scalar, 207, true], # 211
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 211], # 212
  [EntryWrite, ~, [212, 63], 211, Unknown, 211, true], # 213
  [Region, {eval_entry: 205, eval_id: 3}, [213]], # 214
  [Phi, {region: 214}, [21], ~, "Maybe[Int]"], # 215
  [Add, ~, [209, 21], ~, Int], # 216
  [Add, ~, [198, 21], ~, Int], # 217
  [LocalAlias, {name: _}, [203], 200, Unknown, 169], # 218
  [If, ~, [214, 215], 214], # 219
  [PadAccess, {sigil: $, symbol: func}, ~, ~, Unknown, 83], # 220
  [Count, ~, [25], ~, Int, 45], # 221
  [Proj, {index: 0}, [219]], # 222
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 213], # 223
  [Constant, {const_type: string, value: "** argument not available anymore **"}, ~, ~, Str], # 224
  [Proj, {index: 1}, [219]], # 225
  [Assign, ~, [223, 224], 225, Str, 213, true], # 226
  [Region, {head: 219}, [222, 226]], # 227
  [Phi, {memory: true, predecessors: [222, 225], region: 227}, [213, 226], ~, Unknown], # 228
  [EntryWrite, ~, [158, 204], 227, Unknown, 228, true], # 229
  [Phi, {region: 173}, [62, 204], ~, Scalar], # 230
  [Count, ~, [25], ~, Int, 58], # 231
  [Subscript, {kind: array}, [65, 198], ~, Scalar, 169], # 232
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 382, name: Carp::format_arg, package: Carp, param_names: [], want: list}, [232], 218, Unknown, 169, true], # 233
  [NumGt, ~, [231, 209], 57, Boolean], # 234
  [Count, ~, [65], ~, Int, 169], # 235
  [NumGt, ~, [235, 198], 156, Boolean], # 236
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 228], # 237
  [ListAppend, {collector: map}, [65, 237], ~, Array], # 238
  [Call, {dispatch_kind: builtin, name: arylen, param_names: []}, [65], ~, Int], # 239
  [Count, ~, [65], ~, Int, 168], # 240
  [ListAppend, {collector: map}, [157, 233], ~, Array]]} # 241
Carp::carp: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 293, name: Carp::shortmess, package: Carp, param_names: [], want: list}, [1], 0, Unknown, 2, true], # 3
  [Call, {dispatch_kind: builtin, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 293, name: warn, param_names: []}, [3], 3, Boolean, 3, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
Carp::cluck: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 294, name: Carp::longmess, package: Carp, param_names: [], want: list}, [1], 0, Unknown, 2, true], # 3
  [Call, {dispatch_kind: builtin, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 294, name: warn, param_names: []}, [3], 3, Boolean, 3, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
Carp::confess: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 292, name: Carp::longmess, package: Carp, param_names: [], want: list}, [2], 0, Unknown, 3, true], # 4
  [Unwind, {file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 292}, [4], 4, ~, 4], # 5
  [Return, {implicit: true}, [1], 5, ~, 4]]} # 6
Carp::croak: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 291, name: Carp::shortmess, package: Carp, param_names: [], want: list}, [2], 0, Unknown, 3, true], # 4
  [Unwind, {file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 291}, [4], 4, ~, 4], # 5
  [Return, {implicit: true}, [1], 5, ~, 4]]} # 6
Carp::export_fail: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Subscript, {kind: array}, [1, 4], ~, Scalar, 3], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: verbose}, ~, ~, Str], # 7
  [StrEq, ~, [6, 7], ~, Boolean], # 8
  [If, ~, [3, 8], 3], # 9
  [Proj, {index: 1}, [9]], # 10
  [EntryDef, {package: Carp, sigil: $, symbol: Verbose}, ~, ~, Scalar], # 11
  [Proj, {index: 0}, [9]], # 12
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 12, Scalar, 3, true], # 13
  [EntryWrite, ~, [11, 13], 13, Unknown, 13, true], # 14
  [Region, {head: 9}, [10, 14]], # 15
  [Phi, {memory: true, predecessors: [10, 12], region: 15}, [3, 14], ~, Unknown], # 16
  [Return, {implicit: true}, [1], 15, ~, 16]]} # 17
Carp::format_arg: {start: 0, returns: [169], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 0, Scalar, 3, true], # 4
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 4], # 5
  [Assign, ~, [5, 4], 4, Scalar, 4, true], # 6
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 6], # 7
  [Constant, {const_type: string, value: UNIVERSAL}, ~, ~, Str], # 8
  [RefType, ~, [7], ~, Str, 6], # 9
  [If, ~, [6, 9], 6], # 10
  [Proj, {index: 0}, [10]], # 11
  [EntryDef, {package: Carp, sigil: $, symbol: in_recurse}, ~, ~, Scalar, 6], # 12
  [Not, ~, [12], ~, Boolean], # 13
  [If, ~, [11, 13], 11], # 14
  [Proj, {index: 0}, [14]], # 15
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 404, name: Carp::_maybe_isa, package: Carp, param_names: [], want: scalar, xs: true}, [7, 8], 15, Unknown, 6, true], # 16
  [Proj, {index: 1}, [14]], # 17
  [Region, {head: 14}, [16, 17]], # 18
  [Phi, {memory: true, predecessors: [15, 17], region: 18}, [16, 6], ~, Unknown], # 19
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 19], # 20
  [EntryDef, {package: Carp, sigil: $, symbol: in_recurse}, ~, ~, Scalar], # 21
  [EntryDef, {package: Carp, sigil: $, symbol: in_recurse}, ~, ~, Scalar, 19], # 22
  [EntryDef, {package: main, sigil: "%", symbol: SIG}, ~, ~, Hash], # 23
  [Constant, {const_type: string, value: __DIE__}, ~, ~, Str], # 24
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 25
  [Phi, {predecessors: [15, 17], region: 18}, [16, 13], ~, Unknown], # 26
  [If, ~, [18, 26], 18], # 27
  [Proj, {index: 0}, [27]], # 28
  [EntryWrite, ~, [21, 25], 28, Unknown, 19, true], # 29
  [Subscript, {kind: hash}, [23, 24], ~, Scalar, 29], # 30
  [Exists, {kind: hash}, [23, 24], ~, Boolean, 29], # 31
  [Subscript, {kind: hash}, [23, 24], ~, Scalar], # 32
  [AnonSub, {name: Carp::format_arg::__ANON__:408:11}, ~, ~, CodeRef], # 33
  [Assign, {local: true}, [32, 33], 29, CodeRef, 29, true], # 34
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 34], # 35
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 36
  [EntryWrite, ~, [35, 36], 34, Unknown, 34, true], # 37
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 37], # 38
  [Constant, {const_type: string, value: CARP_TRACE}, ~, ~, Str], # 39
  [Call, {dispatch_kind: method, eval_id: 5, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 409, name: can, package: Carp, param_names: [], want: scalar}, [38, 39], 37, Unknown, 37, true], # 40
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 40], # 41
  [EntryWrite, ~, [41, 36], 40, Unknown, 40, true], # 42
  [Exc, ~, [40]], # 43
  [Region, {catch: true, eval_id: 5}, [43]], # 44
  [EntryWrite, ~, [41, 43], 44, Unknown, 40, true], # 45
  [Region, {eval_entry: 34, eval_id: 5}, [42, 45]], # 46
  [Phi, {memory: true, region: 46}, [42, 45], ~, Unknown], # 47
  [ElemRestore, {kind: hash}, [23, 24, 30, 31], 46, Unknown, 47, true], # 48
  [EntryWrite, ~, [21, 22], 48, Unknown, 48, true], # 49
  [EntryWrite, ~, [1, 20], 49, Unknown, 49, true], # 50
  [Proj, {index: 1}, [27]], # 51
  [Region, {head: 27}, [50, 51]], # 52
  [Phi, {memory: true, region: 52}, [50, 19], ~, Unknown], # 53
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 53], # 54
  [EntryDef, {package: Carp, sigil: $, symbol: in_recurse}, ~, ~, Scalar, 53], # 55
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 56
  [Phi, {region: 46}, [40, 56], ~, Unknown], # 57
  [Phi, {region: 52}, [57, 26], ~, Unknown], # 58
  [If, ~, [52, 58], 52], # 59
  [Proj, {index: 1}, [59]], # 60
  [Not, ~, [55], ~, Boolean], # 61
  [EntryDef, {package: Carp, sigil: $, symbol: RefArgFormatter}, ~, ~, Scalar, 53], # 62
  [Defined, ~, [62], ~, Boolean], # 63
  [And, ~, [61, 63], ~, Boolean], # 64
  [If, ~, [60, 64], 60], # 65
  [Proj, {index: 0}, [65]], # 66
  [EntryWrite, ~, [21, 25], 66, Unknown, 53, true], # 67
  [Subscript, {kind: hash}, [23, 24], ~, Scalar, 67], # 68
  [Exists, {kind: hash}, [23, 24], ~, Boolean, 67], # 69
  [AnonSub, {name: Carp::format_arg::__ANON__:419:20}, ~, ~, CodeRef], # 70
  [Assign, {local: true}, [32, 70], 67, CodeRef, 67, true], # 71
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 71], # 72
  [EntryWrite, ~, [72, 36], 71, Unknown, 71, true], # 73
  [EntryDef, {package: Carp, sigil: $, symbol: RefArgFormatter}, ~, ~, Scalar, 73], # 74
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 73], # 75
  [Call, {dispatch_kind: indirect, eval_id: 6, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 420, name: "", package: Carp, param_names: [], want: scalar}, [74, 75], 73, Unknown, 73, true], # 76
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 76], # 77
  [Assign, ~, [77, 76], 76, Unknown, 76, true], # 78
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 78], # 79
  [EntryWrite, ~, [79, 36], 78, Unknown, 78, true], # 80
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 76], # 81
  [Exc, ~, [76]], # 82
  [Region, {catch: true, eval_id: 6}, [82]], # 83
  [EntryWrite, ~, [81, 82], 83, Unknown, 76, true], # 84
  [Region, {eval_entry: 71, eval_id: 6}, [80, 84]], # 85
  [Phi, {memory: true, region: 85}, [80, 84], ~, Unknown], # 86
  [ElemRestore, {kind: hash}, [23, 24, 68, 69], 85, Unknown, 86, true], # 87
  [EntryWrite, ~, [21, 55], 87, Unknown, 87, true], # 88
  [EntryWrite, ~, [1, 54], 88, Unknown, 88, true], # 89
  [Proj, {index: 1}, [65]], # 90
  [Region, {head: 65}, [89, 90]], # 91
  [Phi, {memory: true, region: 91}, [89, 53], ~, Unknown], # 92
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 92], # 93
  [Phi, {region: 85}, [25, 56], ~, "Maybe[Int]"], # 94
  [Phi, {region: 91}, [94, 64], ~, Scalar], # 95
  [If, ~, [91, 95], 91], # 96
  [Proj, {index: 1}, [96]], # 97
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 431, name: Carp::_StrVal, package: Carp, param_names: []}, [93], 97, Unknown, 92, true], # 98
  [Proj, {index: 0}, [96]], # 99
  [Region, {head: 96}, [98, 99]], # 100
  [Phi, {predecessors: [97, 99], region: 100}, [98, 93], ~, Unknown], # 101
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 53], # 102
  [Proj, {index: 0}, [59]], # 103
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 431, name: CARP_TRACE, package: Carp, param_names: []}, [102], 103, Unknown, 53, true], # 104
  [Region, {head: 59}, [100, 104]], # 105
  [Phi, {predecessors: [60, 103], region: 105}, [101, 104], ~, Unknown], # 106
  [Constant, {const_type: string, value: undef}, ~, ~, Str], # 107
  [Proj, {index: 1}, [10]], # 108
  [Defined, ~, [7], ~, Boolean], # 109
  [Not, ~, [109], ~, Boolean], # 110
  [If, ~, [108, 110], 108], # 111
  [Proj, {index: 1}, [111]], # 112
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 435, name: Carp::downgrade, package: Carp, param_names: [], want: void, xs: true}, [7, 25], 112, Unknown, 6, true], # 113
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 113], # 114
  [Constant, {const_type: string, value: "\""}, ~, ~, Str], # 115
  [EntryDef, {package: Carp, sigil: $, symbol: MaxArgLen}, ~, ~, Scalar, 113], # 116
  [Coerce, {from_repr: Scalar, to_repr: Num}, [116], ~, Num], # 117
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 118
  [Subtract, ~, [117, 118], ~, Num], # 119
  [Length, ~, [114], ~, Int], # 120
  [RegexMatch, {flags: "", pattern: "\\A-?[0-9]+(?:\\.[0-9]*)?(?:[eE][-+]?[0-9]+)?\\z"}, [114], 113, Boolean], # 121
  [If, ~, [121, 121], 121], # 122
  [Proj, {index: 1}, [122]], # 123
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 124
  [NumLt, ~, [124, 117], ~, Boolean], # 125
  [NumLt, ~, [117, 120], ~, Boolean], # 126
  [And, ~, [125, 126], ~, Boolean], # 127
  [If, ~, [123, 127], 123], # 128
  [Proj, {index: 0}, [128]], # 129
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [114, 119, 120, 36], 129, Str, 113, true], # 130
  [Proj, {index: 1}, [128]], # 131
  [Region, {head: 128}, [131, 130]], # 132
  [Phi, {memory: true, predecessors: [131, 129], region: 132}, [113, 130], ~, Unknown], # 133
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Str, 133], # 134
  [Constant, {const_type: string, value: "\\"}, ~, ~, Str], # 135
  [RegexMatch, {flags: g, pattern: "([\\\"\\\\\\$\\@])"}, [134], ~, Boolean], # 136
  [RegexCapture, {"n": 1}, [136], ~, Str], # 137
  [Concat, ~, [135, 137], ~, Str], # 138
  [If, ~, [132, 136], 132], # 139
  [Proj, {index: 0}, [139]], # 140
  [Proj, {index: 1}, [139]], # 141
  [Region, {head: 139}, [140, 141]], # 142
  [Phi, {predecessors: [140, 141], region: 142}, [138, 56], ~, "Maybe[Str]"], # 143
  [RegexSubst, {flags: g, pattern: "([\\\"\\\\\\$\\@])", replacement: ""}, [134, 143], 142, Str, 133, true], # 144
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 144], # 145
  [RegexSubst, {flags: g, pattern: "([^ !\"#\\$\\%\\&'()*+,\\-./0123456789:;<=>?\\@ABCDEFGHIJKLMNOPQRSTUVWXYZ\\[\\\\\\]^_`abcdefghijklmnopqrstuvwxyz\\{|}~])", replacement: "", replacement_body: Carp::format_arg::__SUBSTREPL__:1}, [145], 144, Str, 144, true], # 146
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 146], # 147
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 462, name: Carp::downgrade, package: Carp, param_names: [], want: void, xs: true}, [147, 25], 146, Unknown, 146, true], # 148
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Str, 148], # 149
  [Coerce, {from_repr: Unknown, to_repr: Str}, [149], ~, Str], # 150
  [Concat, ~, [115, 150], ~, Str], # 151
  [Concat, ~, [151, 115], ~, Str], # 152
  [Constant, {const_type: string, value: "..."}, ~, ~, Str], # 153
  [Phi, {predecessors: [131, 129], region: 132}, [36, 153], ~, Str], # 154
  [Concat, ~, [152, 154], ~, Str], # 155
  [Proj, {index: 0}, [122]], # 156
  [Region, {head: 122}, [156, 148]], # 157
  [Phi, {predecessors: [156, 123], region: 157}, [114, 155], ~, Unknown], # 158
  [Proj, {index: 0}, [111]], # 159
  [Region, {head: 111}, [159, 157]], # 160
  [Phi, {predecessors: [159, 112], region: 160}, [107, 158], ~, Unknown], # 161
  [Region, {head: 10}, [105, 160]], # 162
  [Phi, {predecessors: [11, 108], region: 162}, [106, 161], ~, Unknown], # 163
  [Phi, {exits: true, memory: true, predecessors: [97, 99], region: 100}, [98, 92], ~, Unknown], # 164
  [Phi, {exits: true, memory: true, predecessors: [60, 103], region: 105}, [164, 104], ~, Unknown], # 165
  [Phi, {exits: true, memory: true, predecessors: [156, 123], region: 157}, [113, 148], ~, Unknown], # 166
  [Phi, {exits: true, memory: true, predecessors: [159, 112], region: 160}, [6, 166], ~, Unknown], # 167
  [Phi, {exits: true, memory: true, predecessors: [11, 108], region: 162}, [165, 167], ~, Unknown], # 168
  [Return, ~, [163], 162, ~, 168], # 169
  [Phi, {region: 52}, [22, 12], ~, Scalar], # 170
  [Phi, {region: 91}, [55, 170], ~, Scalar], # 171
  [Phi, {region: 91}, [54, 20], ~, Scalar], # 172
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [114, 119], ~, Str]]} # 173
Carp::format_arg::__ANON__:408:11: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Return, {implicit: true, valueless: true}, [1], 0, ~, 2]]} # 3
Carp::format_arg::__ANON__:419:20: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Return, {implicit: true, valueless: true}, [1], 0, ~, 2]]} # 3
Carp::format_arg::__SUBSTREPL__:1: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "\\x{%x}"}, ~, ~, Str], # 1
  [RegexMatch, {flags: g, pattern: "([^ !\"#\\$\\%\\&'()*+,\\-./0123456789:;<=>?\\@ABCDEFGHIJKLMNOPQRSTUVWXYZ\\[\\\\\\]^_`abcdefghijklmnopqrstuvwxyz\\{|}~])"}, ~, ~, Boolean], # 2
  [RegexCapture, {"n": 1}, [2], ~, Str], # 3
  [Call, {dispatch_kind: builtin, name: ord, param_names: []}, [3], ~, Int], # 4
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [1, 4], ~, Str], # 5
  [MemStart], # 6
  [Return, {implicit: true}, [5], 0, ~, 6]]} # 7
Carp::get_status: {start: 0, returns: [35], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 3, Scalar, 3, true], # 4
  [PadAccess, {sigil: $, symbol: pkg}, ~, ~, Unknown, 4], # 5
  [Assign, ~, [5, 4], 4, Scalar, 4, true], # 6
  [PadAccess, {sigil: $, symbol: pkg}, ~, ~, Unknown, 6], # 7
  [Subscript, {kind: hash}, [3, 7], ~, Scalar], # 8
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 9
  [Subscript, {kind: hash}, [3, 7], 6, Scalar, 6], # 10
  [Defined, ~, [10], ~, Boolean], # 11
  [If, ~, [10, 11], 10], # 12
  [Proj, {index: 1}, [12]], # 13
  [Assign, ~, [8, 9], 13, Undef, 6, true], # 14
  [Proj, {index: 0}, [12]], # 15
  [Region, {head: 12}, [15, 14]], # 16
  [Phi, {memory: true, predecessors: [15, 13], region: 16}, [6, 14], ~, Scalar], # 17
  [PadAccess, {sigil: $, symbol: pkg}, ~, ~, Unknown, 17], # 18
  [If, ~, [16, 10], 16], # 19
  [Proj, {index: 1}, [19]], # 20
  [HashLiteral, ~, [18, 18], 20, HashRef], # 21
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 499, name: Carp::trusts_directly, package: Carp, param_names: [], want: list}, [18], 21, List, 17, true], # 22
  [ArrayLiteral, ~, [22], 22, ArrayRef], # 23
  [ArrayLiteral, ~, [21, 23], 23, ArrayRef], # 24
  [Assign, ~, [8, 24], 24, ArrayRef, 22, true], # 25
  [Proj, {index: 0}, [19]], # 26
  [Region, {head: 19}, [26, 25]], # 27
  [Phi, {memory: true, predecessors: [26, 20], region: 27}, [17, 25], ~, Scalar], # 28
  [PadAccess, {sigil: $, symbol: pkg}, ~, ~, Unknown, 28], # 29
  [Subscript, {kind: hash}, [3, 29], 27, Scalar, 28, true], # 30
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 500, package: Carp, sigil: "@", strict: true}, [30], 30, Array, 30, true], # 31
  [ArrayLiteral, ~, [31], ~, List], # 32
  [Count, ~, [31], ~, Int, 31], # 33
  [Coerce, {from_repr: List, to_repr: Scalar}, [33], ~, Scalar], # 34
  [Return, ~, [32, 34], 31, ~, 31]]} # 35
Carp::get_subname: {start: 0, returns: [70], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "eval '"}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 0, Scalar, 3, true], # 4
  [Constant, {const_type: string, value: is_require}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: evaltext}, ~, ~, Str], # 6
  [Subscript, {kind: hash}, [4, 6], 4, Scalar, 4, true], # 7
  [Defined, ~, [7], ~, Boolean], # 8
  [If, ~, [7, 8], 7], # 9
  [Proj, {index: 0}, [9]], # 10
  [Subscript, {kind: hash}, [4, 6], 10, Scalar, 7, true], # 11
  [PadAccess, {sigil: $, symbol: eval}, ~, ~, Unknown, 11], # 12
  [Assign, ~, [12, 11], 11, Scalar, 11, true], # 13
  [Subscript, {kind: hash}, [4, 5], 13, Scalar, 13, true], # 14
  [PadAccess, {sigil: $, symbol: eval}, ~, ~, Str, 14], # 15
  [Constant, {const_type: string, value: "\\"}, ~, ~, Str], # 16
  [RegexMatch, {flags: g, pattern: "([\\\\\\'])"}, [15], ~, Boolean], # 17
  [RegexCapture, {"n": 1}, [17], ~, Str], # 18
  [Concat, ~, [16, 18], ~, Str], # 19
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 20
  [If, ~, [14, 14], 14], # 21
  [Proj, {index: 1}, [21]], # 22
  [If, ~, [22, 17], 22], # 23
  [Proj, {index: 0}, [23]], # 24
  [Proj, {index: 1}, [23]], # 25
  [Region, {head: 23}, [24, 25]], # 26
  [Phi, {predecessors: [24, 25], region: 26}, [19, 20], ~, "Maybe[Str]"], # 27
  [RegexSubst, {flags: g, pattern: "([\\\\\\'])", replacement: ""}, [15, 27], 26, Str, 14, true], # 28
  [PadAccess, {sigil: $, symbol: eval}, ~, ~, Unknown, 28], # 29
  [EntryDef, {package: Carp, sigil: $, symbol: MaxEvalLen}, ~, ~, Scalar, 28], # 30
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 514, name: Carp::str_len_trim, package: Carp, param_names: [], want: scalar}, [29, 30], 28, Unknown, 28, true], # 31
  [Coerce, {from_repr: Unknown, to_repr: Str}, [31], ~, Str], # 32
  [Concat, ~, [1, 32], ~, Str], # 33
  [Constant, {const_type: string, value: "'"}, ~, ~, Str], # 34
  [Concat, ~, [33, 34], ~, Str], # 35
  [Constant, {const_type: string, value: "require "}, ~, ~, Str], # 36
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 37
  [Concat, ~, [36, 37], ~, Str], # 38
  [Proj, {index: 0}, [21]], # 39
  [Region, {head: 21}, [31, 39]], # 40
  [Phi, {predecessors: [22, 39], region: 40}, [35, 38], ~, Str], # 41
  [Constant, {const_type: string, value: __ANON__::__ANON__}, ~, ~, Str], # 42
  [Constant, {const_type: string, value: "eval {...}"}, ~, ~, Str], # 43
  [Constant, {const_type: string, value: sub}, ~, ~, Str], # 44
  [Proj, {index: 1}, [9]], # 45
  [Subscript, {kind: hash}, [4, 44], 45, Scalar, 7, true], # 46
  [Defined, ~, [46], ~, Boolean], # 47
  [Not, ~, [47], ~, Boolean], # 48
  [If, ~, [46, 48], 46], # 49
  [Proj, {index: 1}, [49]], # 50
  [Subscript, {kind: hash}, [4, 44], 50, Scalar, 46, true], # 51
  [Coerce, {from_repr: Unknown, to_repr: Str}, [51], ~, Str], # 52
  [Constant, {const_type: string, value: "(eval)"}, ~, ~, Str], # 53
  [StrEq, ~, [52, 53], ~, Boolean], # 54
  [If, ~, [51, 54], 51], # 55
  [Proj, {index: 1}, [55]], # 56
  [Subscript, {kind: hash}, [4, 44], 56, Scalar, 51, true], # 57
  [Proj, {index: 0}, [55]], # 58
  [Region, {head: 55}, [58, 57]], # 59
  [Phi, {predecessors: [58, 56], region: 59}, [43, 57], ~, Scalar], # 60
  [Proj, {index: 0}, [49]], # 61
  [Region, {head: 49}, [61, 59]], # 62
  [Phi, {predecessors: [61, 50], region: 62}, [42, 60], ~, Scalar], # 63
  [Region, {head: 9}, [40, 62]], # 64
  [Phi, {predecessors: [10, 45], region: 64}, [41, 63], ~, Scalar], # 65
  [Phi, {exits: true, memory: true, predecessors: [22, 39], region: 40}, [31, 14], ~, Unknown], # 66
  [Phi, {memory: true, predecessors: [58, 56], region: 59}, [51, 57], ~, Scalar], # 67
  [Phi, {exits: true, memory: true, predecessors: [61, 50], region: 62}, [46, 67], ~, Scalar], # 68
  [Phi, {exits: true, memory: true, predecessors: [10, 45], region: 64}, [66, 68], ~, Unknown], # 69
  [Return, ~, [65], 64, ~, 69]]} # 70
Carp::long_error_loc: {start: 0, returns: [69], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 2], # 3
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 4
  [Assign, ~, [3, 4], 0, Undef, 2, true], # 5
  [Loop, {bound: each}, [5], 5], # 6
  [Phi, {memory: true, region: 6}, [5, 19], ~, Unknown], # 7
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 7], # 8
  [Increment, ~, [8], ~, Scalar], # 9
  [Assign, ~, [8, 9], 6, Scalar, 7, true], # 10
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 534, name: Carp::_cgc, package: Carp, param_names: [], want: scalar}, ~, 10, List, 10, true], # 11
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 11], # 12
  [If, ~, [11, 11], 11], # 13
  [Proj, {index: 0}, [13]], # 14
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 535, name: "", package: Carp, param_names: [], want: list}, [11, 12], 14, Unknown, 11, true], # 15
  [Proj, {index: 1}, [13]], # 16
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, [12], 16, List, 11], # 17
  [Region, {head: 13}, [15, 17]], # 18
  [Phi, {memory: true, predecessors: [14, 16], region: 18}, [15, 11], ~, Unknown], # 19
  [EntryDef, {package: Carp, sigil: "%", symbol: Internal}, ~, ~, Hash], # 20
  [EntryDef, {package: Carp, sigil: "%", symbol: Internal}, ~, ~, Hash, 19], # 21
  [Ref, ~, [21], ~, HashRef], # 22
  [HashLiteral, ~, ~, ~, HashRef], # 23
  [Phi, {predecessors: [14, 16], region: 18}, [15, 17], ~, Unknown], # 24
  [ArrayLiteral, {sigil: "@", symbol: caller}, [24], 18, Array], # 25
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 26
  [Subscript, {kind: array}, [25, 26], ~, Scalar, 19], # 27
  [Defined, ~, [27], ~, Boolean], # 28
  [If, ~, [25, 28], 25], # 29
  [Proj, {index: 1}, [29]], # 30
  [Count, ~, [20], ~, Int, 19], # 31
  [If, ~, [30, 31], 30], # 32
  [Proj, {index: 0}, [32]], # 33
  [EntryWrite, {binds: true}, [20, 23], 33, Unknown, 19, true], # 34
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 542, name: Carp::long_error_loc, package: Carp, param_names: [], want: scalar}, ~, 34, Num, 34, true], # 35
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 35], # 36
  [Assign, ~, [36, 35], 35, Num, 35, true], # 37
  [EntryWrite, {binds: true}, [20, 22], 37, Unknown, 37, true], # 38
  [Proj, {index: 1}, [32]], # 39
  [Subscript, {kind: array}, [25, 1], ~, Scalar, 19], # 40
  [Defined, ~, [40], ~, Boolean], # 41
  [If, ~, [39, 41], 39], # 42
  [Proj, {index: 0}, [42]], # 43
  [EntryDef, {package: Carp, sigil: $, symbol: CarpLevel}, ~, ~, Scalar, 5], # 44
  [Phi, {region: 6}, [44, 80], ~, Unknown], # 45
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 46
  [Subtract, ~, [45, 46], ~, Unknown], # 47
  [NumGt, ~, [26, 47], ~, Boolean], # 48
  [If, ~, [43, 48], 43], # 49
  [Proj, {index: 0}, [49]], # 50
  [Proj, {index: 0}, [29]], # 51
  [EntryDef, {package: Carp, sigil: "%", symbol: CarpInternal}, ~, ~, Hash], # 52
  [Subscript, {kind: hash}, [52, 27], ~, Scalar, 19], # 53
  [If, ~, [51, 53], 51], # 54
  [Proj, {index: 1}, [54]], # 55
  [If, ~, [55, 48], 55], # 56
  [Proj, {index: 0}, [56]], # 57
  [Subscript, {kind: hash}, [20, 27], ~, Scalar, 19], # 58
  [If, ~, [57, 58], 57], # 59
  [Proj, {index: 1}, [59]], # 60
  [Region, {head: 6}, [50, 38, 60]], # 61
  [Phi, {memory: true, region: 61}, [19, 38, 19], ~, Unknown], # 62
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Num, 62], # 63
  [Subtract, ~, [63, 46], ~, Num], # 64
  [Proj, {index: 1}, [42]], # 65
  [Region, ~, [65, 61]], # 66
  [Phi, {predecessors: [65, 61], region: 66}, [1, 64], ~, Num], # 67
  [Phi, {exits: true, memory: true, predecessors: [65, 61], region: 66}, [19, 62], ~, Unknown], # 68
  [Return, ~, [67], 66, ~, 68], # 69
  [Phi, {region: 61}, [47, 45, 47], ~, Unknown], # 70
  [Proj, {index: 0}, [54]], # 71
  [Proj, {index: 1}, [49]], # 72
  [Region, {head: 6}, [71, 72]], # 73
  [Phi, {predecessors: [71, 72], region: 73}, [45, 47], ~, Unknown], # 74
  [Proj, {index: 1}, [56]], # 75
  [Region, {head: 6}, [73, 75]], # 76
  [Phi, {region: 76}, [74, 47], ~, Unknown], # 77
  [Proj, {index: 0}, [59]], # 78
  [Region, {head: 6}, [76, 78]], # 79
  [Phi, {region: 79}, [77, 47], ~, Unknown], # 80
  [EntryDef, {package: Carp, sigil: "%", symbol: Internal}, ~, ~, Hash, 38]]} # 81
Carp::longmess: {start: 0, returns: [40], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [EntryDef, {package: Carp, sigil: $, symbol: CarpLevel}, ~, ~, Scalar], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 269, name: Carp::_cgc, package: Carp, param_names: [], want: scalar}, ~, 0, List, 3, true], # 4
  [If, ~, [4, 4], 4], # 5
  [Proj, {index: 0}, [5]], # 6
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 270, name: "", package: Carp, param_names: [], want: scalar}, [4], 6, Unknown, 4, true], # 7
  [Proj, {index: 1}, [5]], # 8
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, ~, 8, Scalar, 4], # 9
  [Region, {head: 5}, [7, 9]], # 10
  [Phi, {memory: true, predecessors: [6, 8], region: 10}, [7, 4], ~, Unknown], # 11
  [EntryDef, {package: Carp, sigil: $, symbol: CarpLevel}, ~, ~, Scalar, 11], # 12
  [Coerce, {from_repr: Scalar, to_repr: Num}, [12], ~, Num], # 13
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 14
  [Add, ~, [13, 14], ~, Num], # 15
  [EntryDef, {package: Carp, sigil: "%", symbol: Internal}, ~, ~, Hash], # 16
  [Phi, {predecessors: [6, 8], region: 10}, [7, 9], ~, Unknown], # 17
  [Subscript, {kind: hash}, [16, 17], ~, Scalar, 11], # 18
  [EntryDef, {package: Carp, sigil: "%", symbol: CarpInternal}, ~, ~, Hash], # 19
  [Subscript, {kind: hash}, [19, 17], ~, Scalar, 11], # 20
  [Or, ~, [18, 20], ~, Scalar], # 21
  [If, ~, [10, 21], 10], # 22
  [Proj, {index: 1}, [22]], # 23
  [EntryWrite, ~, [2, 15], 23, Unknown, 11, true], # 24
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 276, name: Carp::longmess_heavy, package: Carp, param_names: []}, [1], 24, Unknown, 24, true], # 25
  [Proj, {index: 0}, [22]], # 26
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 276, name: Carp::longmess_heavy, package: Carp, param_names: []}, [1], 26, Unknown, 11, true], # 27
  [EntryDef, {package: main, sigil: $, symbol: "!"}, ~, ~, Scalar], # 28
  [EntryDef, {package: main, sigil: $, symbol: "!"}, ~, ~, Scalar, 3], # 29
  [EntryDef, {package: main, sigil: $, symbol: "\u0005"}, ~, ~, Scalar], # 30
  [EntryDef, {package: main, sigil: $, symbol: "\u0005"}, ~, ~, Scalar, 3], # 31
  [EntryWrite, ~, [2, 12], 25, Unknown, 25, true], # 32
  [EntryWrite, ~, [30, 31], 32, Unknown, 32, true], # 33
  [EntryWrite, ~, [28, 29], 33, Unknown, 33, true], # 34
  [EntryWrite, ~, [30, 31], 27, Unknown, 27, true], # 35
  [EntryWrite, ~, [28, 29], 35, Unknown, 35, true], # 36
  [Region, {head: 22}, [34, 36]], # 37
  [Phi, {predecessors: [23, 26], region: 37}, [25, 27], ~, Unknown], # 38
  [Phi, {exits: true, memory: true, predecessors: [23, 26], region: 37}, [34, 36], ~, Unknown], # 39
  [Return, ~, [38], 37, ~, 39]]} # 40
Carp::longmess_heavy: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Wantarray, ~, ~, ~, Scalar], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [TernaryExpr, ~, [1, 2, 5], ~, Unknown], # 6
  [RefType, ~, [5], ~, Str, 4], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 1}, [8]], # 9
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 570, name: Carp::long_error_loc, package: Carp, param_names: [], want: scalar}, ~, 9, Num, 4, true], # 10
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 10], # 11
  [Assign, ~, [11, 10], 10, Num, 10, true], # 12
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 12], # 13
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 571, name: Carp::ret_backtrace, package: Carp, param_names: []}, [13, 2], 12, Str, 12, true], # 14
  [Proj, {index: 0}, [8]], # 15
  [Region, {head: 8}, [15, 14]], # 16
  [Phi, {predecessors: [15, 9], region: 16}, [6, 14], ~, Unknown], # 17
  [Phi, {exits: true, memory: true, predecessors: [15, 9], region: 16}, [4, 14], ~, Unknown], # 18
  [Return, ~, [17], 16, ~, 18]]} # 19
Carp::ret_backtrace: {start: 0, returns: [76], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: error}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 3], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Assign, {targets: 2}, [4, 2, 5], 0, List, 3, true], # 6
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 2], ~, Str, 6], # 7
  [Constant, {const_type: string, value: " at "}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 6], # 10
  [Increment, ~, [10], ~, Scalar], # 11
  [Assign, ~, [10, 11], 6, Scalar, 6, true], # 12
  [Constant, {const_type: string, value: threads}, ~, ~, Str], # 13
  [SubDefined, {answer: 0, name: threads::tid, unless: [Exporter::import, Fcntl::import, POSIX::AUTOLOAD, SoN::Serialize::JSON::import]}, ~, ~, Boolean], # 14
  [If, ~, [12, 14], 12], # 15
  [Proj, {index: 0}, [15]], # 16
  [Call, {class_name: threads, dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 593, name: tid, package: Carp, param_names: [], want: scalar}, [13], 16, Unknown, 12, true], # 17
  [Proj, {index: 1}, [15]], # 18
  [Region, {head: 15}, [18, 17]], # 19
  [Phi, {memory: true, predecessors: [18, 16], region: 19}, [12, 17], ~, Unknown], # 20
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 20], # 21
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 597, name: Carp::caller_info, package: Carp, param_names: [], want: list}, [21], 19, Unknown, 20, true], # 22
  [HashLiteral, {sigil: "%", symbol: i}, [22], ~, Hash], # 23
  [Constant, {const_type: string, value: file}, ~, ~, Str], # 24
  [Subscript, {kind: hash}, [23, 24], ~, Scalar, 22], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 26
  [Concat, ~, [9, 26], ~, Str], # 27
  [Constant, {const_type: string, value: " line "}, ~, ~, Str], # 28
  [Concat, ~, [27, 28], ~, Str], # 29
  [Constant, {const_type: string, value: line}, ~, ~, Str], # 30
  [Subscript, {kind: hash}, [23, 30], ~, Scalar, 22], # 31
  [Coerce, {from_repr: Unknown, to_repr: Str}, [31], ~, Str], # 32
  [Concat, ~, [29, 32], ~, Str], # 33
  [Constant, {const_type: string, value: " thread "}, ~, ~, Str], # 34
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 35
  [Concat, ~, [34, 35], ~, Str], # 36
  [TernaryExpr, ~, [17, 36, 1], ~, Str], # 37
  [Phi, {predecessors: [18, 16], region: 19}, [1, 37], ~, Str], # 38
  [Concat, ~, [33, 38], ~, Str], # 39
  [Constant, {const_type: string, value: ", <%s> %s %d"}, ~, ~, Str], # 40
  [Constant, {const_type: ref, value: ~}, ~, ~, ScalarRef], # 41
  [EntryDef, {package: main, sigil: $, symbol: "."}, ~, ~, Scalar, 22], # 42
  [If, ~, [22, 42], 22], # 43
  [Proj, {index: 0}, [43]], # 44
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 602, package: Carp, sigil: $, strict: true}, [41], 44, Scalar, 22, true], # 45
  [If, ~, [45, 45], 45], # 46
  [Proj, {index: 0}, [46]], # 47
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 605, package: Carp, sigil: $, strict: true}, [41], 47, Scalar, 45, true], # 48
  [Constant, {const_type: string, value: NAME}, ~, ~, Str], # 49
  [Subscript, ~, [48, 49], ~, Scalar, 48], # 50
  [EntryDef, {package: main, sigil: $, symbol: "/"}, ~, ~, Scalar, 48], # 51
  [Coerce, {from_repr: Unknown, to_repr: Str}, [51], ~, Str], # 52
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 53
  [StrEq, ~, [52, 53], ~, Boolean], # 54
  [Constant, {const_type: string, value: chunk}, ~, ~, Str], # 55
  [TernaryExpr, ~, [54, 30, 55], ~, Str], # 56
  [EntryDef, {package: main, sigil: $, symbol: "."}, ~, ~, Scalar, 48], # 57
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [40, 50, 56, 57], ~, Str], # 58
  [Concat, ~, [39, 58], ~, Str], # 59
  [Proj, {index: 1}, [46]], # 60
  [Region, {head: 46}, [60, 48]], # 61
  [Phi, {predecessors: [60, 47], region: 61}, [39, 59], ~, Str], # 62
  [Proj, {index: 1}, [43]], # 63
  [Region, {head: 43}, [63, 61]], # 64
  [Phi, {predecessors: [63, 44], region: 64}, [39, 62], ~, Str], # 65
  [Constant, {const_type: string, value: ".\n"}, ~, ~, Str], # 66
  [Concat, ~, [65, 66], ~, Str], # 67
  [Loop, {bound: each}, [64], 64], # 68
  [Phi, {region: 68}, [67, 98], ~, Str], # 69
  [Proj, {index: 1}, [68]], # 70
  [Region, {head: 68}, [70]], # 71
  [Phi, {memory: true, predecessors: [60, 47], region: 61}, [45, 48], ~, Scalar], # 72
  [Phi, {memory: true, predecessors: [63, 44], region: 64}, [22, 72], ~, Unknown], # 73
  [Phi, {memory: true, region: 68}, [73, 82], ~, Unknown], # 74
  [Phi, {memory: true, region: 71}, [74], ~, Unknown], # 75
  [Return, ~, [69], 71, ~, 75], # 76
  [Constant, {const_type: string, value: "\t"}, ~, ~, Str], # 77
  [Concat, ~, [69, 77], ~, Str], # 78
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 74], # 79
  [Increment, ~, [79], ~, Scalar], # 80
  [Assign, ~, [79, 80], 68, Scalar, 74, true], # 81
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 621, name: Carp::caller_info, package: Carp, param_names: [], want: list}, [80], 81, Unknown, 81, true], # 82
  [HashLiteral, {sigil: "%", symbol: i__2}, [82], 82, Hash], # 83
  [Constant, {const_type: string, value: sub_name}, ~, ~, Str], # 84
  [Subscript, {kind: hash}, [83, 84], ~, Scalar, 82], # 85
  [Coerce, {from_repr: Unknown, to_repr: Str}, [85], ~, Str], # 86
  [Concat, ~, [78, 86], ~, Str], # 87
  [Constant, {const_type: string, value: " called at "}, ~, ~, Str], # 88
  [Concat, ~, [87, 88], ~, Str], # 89
  [Subscript, {kind: hash}, [83, 24], ~, Scalar, 82], # 90
  [Coerce, {from_repr: Unknown, to_repr: Str}, [90], ~, Str], # 91
  [Concat, ~, [89, 91], ~, Str], # 92
  [Concat, ~, [92, 28], ~, Str], # 93
  [Subscript, {kind: hash}, [83, 30], ~, Scalar, 82], # 94
  [Coerce, {from_repr: Unknown, to_repr: Str}, [94], ~, Str], # 95
  [Concat, ~, [93, 95], ~, Str], # 96
  [Concat, ~, [96, 38], ~, Str], # 97
  [Concat, ~, [97, 53], ~, Str], # 98
  [ArrayLiteral, ~, [82], ~, Array], # 99
  [Count, ~, [99], ~, Int, 82], # 100
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 101
  [NumNe, ~, [100, 101], 68, Boolean], # 102
  [Proj, {index: 0}, [68]]]} # 103
Carp::ret_summary: {start: 0, returns: [42], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: error}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 3], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Assign, {targets: 2}, [4, 2, 5], 0, List, 3, true], # 6
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 2], ~, Str, 6], # 7
  [Constant, {const_type: string, value: " at "}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 6], # 10
  [Increment, ~, [10], ~, Scalar], # 11
  [Assign, ~, [10, 11], 6, Scalar, 6, true], # 12
  [Constant, {const_type: string, value: threads}, ~, ~, Str], # 13
  [SubDefined, {answer: 0, name: threads::tid, unless: [Exporter::import, Fcntl::import, POSIX::AUTOLOAD, SoN::Serialize::JSON::import]}, ~, ~, Boolean], # 14
  [If, ~, [12, 14], 12], # 15
  [Proj, {index: 0}, [15]], # 16
  [Call, {class_name: threads, dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 635, name: tid, package: Carp, param_names: [], want: scalar}, [13], 16, Unknown, 12, true], # 17
  [Proj, {index: 1}, [15]], # 18
  [Region, {head: 15}, [18, 17]], # 19
  [Phi, {memory: true, predecessors: [18, 16], region: 19}, [12, 17], ~, Unknown], # 20
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 20], # 21
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 639, name: Carp::caller_info, package: Carp, param_names: [], want: list}, [21], 19, Unknown, 20, true], # 22
  [HashLiteral, {sigil: "%", symbol: i}, [22], ~, Hash], # 23
  [Constant, {const_type: string, value: file}, ~, ~, Str], # 24
  [Subscript, {kind: hash}, [23, 24], ~, Scalar, 22], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 26
  [Concat, ~, [9, 26], ~, Str], # 27
  [Constant, {const_type: string, value: " line "}, ~, ~, Str], # 28
  [Concat, ~, [27, 28], ~, Str], # 29
  [Constant, {const_type: string, value: line}, ~, ~, Str], # 30
  [Subscript, {kind: hash}, [23, 30], ~, Scalar, 22], # 31
  [Coerce, {from_repr: Unknown, to_repr: Str}, [31], ~, Str], # 32
  [Concat, ~, [29, 32], ~, Str], # 33
  [Constant, {const_type: string, value: " thread "}, ~, ~, Str], # 34
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 35
  [Concat, ~, [34, 35], ~, Str], # 36
  [TernaryExpr, ~, [17, 36, 1], ~, Str], # 37
  [Phi, {predecessors: [18, 16], region: 19}, [1, 37], ~, Str], # 38
  [Concat, ~, [33, 38], ~, Str], # 39
  [Constant, {const_type: string, value: ".\n"}, ~, ~, Str], # 40
  [Concat, ~, [39, 40], ~, Str], # 41
  [Return, ~, [41], 22, ~, 22]]} # 42
Carp::short_error_loc: {start: 0, returns: [99], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: cache}, ~, ~, Unknown, 2], # 3
  [HashLiteral, ~, ~, 0, HashRef], # 4
  [Assign, ~, [3, 4], 4, HashRef, 2, true], # 5
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 5], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Assign, ~, [6, 7], 5, Int, 5, true], # 8
  [Loop, {bound: each}, [8], 8], # 9
  [Phi, {memory: true, region: 9}, [8, 122], ~, Unknown], # 10
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 651, name: Carp::_cgc, package: Carp, param_names: [], want: scalar}, ~, 9, List, 10, true], # 11
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 11], # 12
  [If, ~, [11, 11], 11], # 13
  [Proj, {index: 0}, [13]], # 14
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 652, name: "", package: Carp, param_names: [], want: scalar}, [11, 12], 14, Unknown, 11, true], # 15
  [Proj, {index: 1}, [13]], # 16
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, [12], 16, Scalar, 11], # 17
  [Region, {head: 13}, [15, 17]], # 18
  [Phi, {memory: true, predecessors: [14, 16], region: 18}, [15, 11], ~, Unknown], # 19
  [PadAccess, {sigil: $, symbol: called}, ~, ~, Unknown, 19], # 20
  [Phi, {predecessors: [14, 16], region: 18}, [15, 17], ~, Unknown], # 21
  [Assign, ~, [20, 21], 18, Unknown, 19, true], # 22
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 22], # 23
  [Increment, ~, [23], ~, Scalar], # 24
  [Assign, ~, [23, 24], 22, Scalar, 22, true], # 25
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 25], # 26
  [If, ~, [25, 11], 25], # 27
  [Proj, {index: 0}, [27]], # 28
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 654, name: "", package: Carp, param_names: [], want: scalar}, [11, 26], 28, Unknown, 25, true], # 29
  [Proj, {index: 1}, [27]], # 30
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, [26], 30, Scalar, 25], # 31
  [Region, {head: 27}, [29, 31]], # 32
  [Phi, {memory: true, predecessors: [28, 30], region: 32}, [29, 25], ~, Unknown], # 33
  [PadAccess, {sigil: $, symbol: caller}, ~, ~, Unknown, 33], # 34
  [Phi, {predecessors: [28, 30], region: 32}, [29, 31], ~, Unknown], # 35
  [Assign, ~, [34, 35], 32, Unknown, 33, true], # 36
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 36], # 37
  [PadAccess, {sigil: $, symbol: caller}, ~, ~, Unknown, 36], # 38
  [Defined, ~, [38], ~, Boolean], # 39
  [If, ~, [36, 39], 36], # 40
  [Proj, {index: 1}, [40]], # 41
  [If, ~, [41, 11], 41], # 42
  [Proj, {index: 0}, [42]], # 43
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 657, name: "", package: Carp, param_names: [], want: list}, [11, 37], 43, Unknown, 36, true], # 44
  [Proj, {index: 1}, [42]], # 45
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, [37], 45, List, 36], # 46
  [Region, {head: 42}, [44, 46]], # 47
  [Phi, {memory: true, predecessors: [43, 45], region: 47}, [44, 36], ~, Unknown], # 48
  [PadAccess, {sigil: $, symbol: called}, ~, ~, Unknown, 36], # 49
  [PadAccess, {sigil: $, symbol: cache}, ~, ~, Unknown, 36], # 50
  [Proj, {index: 0}, [40]], # 51
  [EntryDef, {package: Carp, sigil: "%", symbol: Internal}, ~, ~, Hash], # 52
  [Subscript, {kind: hash}, [52, 38], ~, Scalar, 36], # 53
  [If, ~, [51, 53], 51], # 54
  [Proj, {index: 1}, [54]], # 55
  [EntryDef, {package: Carp, sigil: "%", symbol: CarpInternal}, ~, ~, Hash], # 56
  [Subscript, {kind: hash}, [56, 38], ~, Scalar, 36], # 57
  [If, ~, [55, 57], 55], # 58
  [Proj, {index: 1}, [58]], # 59
  [Subscript, {kind: hash}, [56, 49], ~, Scalar, 36], # 60
  [If, ~, [59, 60], 59], # 61
  [Proj, {index: 1}, [61]], # 62
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 673, name: Carp::trusts, package: Carp, param_names: [], want: scalar}, [49, 38, 50], 62, Boolean, 36, true], # 63
  [PadAccess, {sigil: $, symbol: caller}, ~, ~, Unknown, 63], # 64
  [PadAccess, {sigil: $, symbol: called}, ~, ~, Unknown, 63], # 65
  [PadAccess, {sigil: $, symbol: cache}, ~, ~, Unknown, 63], # 66
  [If, ~, [63, 63], 63], # 67
  [Proj, {index: 1}, [67]], # 68
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 674, name: Carp::trusts, package: Carp, param_names: [], want: scalar}, [64, 65, 66], 68, Boolean, 63, true], # 69
  [Phi, {predecessors: [43, 45], region: 47}, [44, 46], ~, Unknown], # 70
  [ArrayLiteral, {sigil: "@", symbol: caller}, [70], 47, Array], # 71
  [Count, ~, [71], ~, Int, 48], # 72
  [If, ~, [71, 72], 71], # 73
  [Proj, {index: 0}, [73]], # 74
  [PadAccess, {sigil: $, symbol: called}, ~, ~, Unknown, 48], # 75
  [Defined, ~, [75], ~, Boolean], # 76
  [Subscript, {kind: hash}, [56, 75], ~, Scalar, 48], # 77
  [And, ~, [76, 77], ~, Scalar], # 78
  [If, ~, [74, 78], 74], # 79
  [Proj, {index: 1}, [79]], # 80
  [EntryDef, {package: Carp, sigil: $, symbol: CarpLevel}, ~, ~, Scalar, 8], # 81
  [Phi, {region: 9}, [81, 128], ~, Unknown], # 82
  [Subtract, ~, [82, 7], ~, Unknown], # 83
  [NumGt, ~, [1, 83], ~, Boolean], # 84
  [If, ~, [80, 84], 80], # 85
  [Proj, {index: 0}, [85]], # 86
  [If, ~, [69, 69], 69], # 87
  [Proj, {index: 1}, [87]], # 88
  [If, ~, [88, 84], 88], # 89
  [Proj, {index: 0}, [89]], # 90
  [Region, {head: 9}, [86, 90]], # 91
  [Phi, {memory: true, region: 91}, [48, 69], ~, Unknown], # 92
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Num, 92], # 93
  [Subtract, ~, [93, 7], ~, Num], # 94
  [Proj, {index: 1}, [73]], # 95
  [Region, ~, [95, 91]], # 96
  [Phi, {predecessors: [95, 91], region: 96}, [1, 94], ~, Num], # 97
  [Phi, {exits: true, memory: true, predecessors: [95, 91], region: 96}, [48, 92], ~, Unknown], # 98
  [Return, ~, [97], 96, ~, 98], # 99
  [Phi, {region: 91}, [83, 83], ~, Unknown], # 100
  [Proj, {index: 0}, [54]], # 101
  [Proj, {index: 0}, [79]], # 102
  [Region, {head: 9}, [101, 102]], # 103
  [Phi, {memory: true, predecessors: [101, 102], region: 103}, [36, 48], ~, Unknown], # 104
  [Proj, {index: 1}, [85]], # 105
  [Region, {head: 9}, [103, 105]], # 106
  [Phi, {memory: true, region: 106}, [104, 48], ~, Unknown], # 107
  [Proj, {index: 0}, [58]], # 108
  [Region, {head: 9}, [106, 108]], # 109
  [Phi, {memory: true, region: 109}, [107, 36], ~, Unknown], # 110
  [Proj, {index: 0}, [61]], # 111
  [Region, {head: 9}, [109, 111]], # 112
  [Phi, {memory: true, region: 112}, [110, 36], ~, Unknown], # 113
  [Proj, {index: 0}, [67]], # 114
  [Region, {head: 9}, [112, 114]], # 115
  [Phi, {memory: true, region: 115}, [113, 63], ~, Unknown], # 116
  [Proj, {index: 0}, [87]], # 117
  [Region, {head: 9}, [115, 117]], # 118
  [Phi, {memory: true, region: 118}, [116, 69], ~, Unknown], # 119
  [Proj, {index: 1}, [89]], # 120
  [Region, {head: 9}, [118, 120]], # 121
  [Phi, {memory: true, region: 121}, [119, 69], ~, Unknown], # 122
  [Phi, {region: 106}, [82, 83], ~, Unknown], # 123
  [Phi, {region: 109}, [123, 82], ~, Unknown], # 124
  [Phi, {region: 112}, [124, 82], ~, Unknown], # 125
  [Phi, {region: 115}, [125, 82], ~, Unknown], # 126
  [Phi, {region: 118}, [126, 82], ~, Unknown], # 127
  [Phi, {region: 121}, [127, 83], ~, Unknown]]} # 128
Carp::shortmess: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [EntryDef, {package: Carp, sigil: "@", symbol: CARP_NOT}, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 284, name: Carp::_cgc, package: Carp, param_names: [], want: scalar}, ~, 0, List, 3, true], # 4
  [If, ~, [4, 4], 4], # 5
  [Proj, {index: 0}, [5]], # 6
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 287, name: "", package: Carp, param_names: [], want: scalar}, [4], 6, Unknown, 4, true], # 7
  [Proj, {index: 1}, [5]], # 8
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, ~, 8, Scalar, 4], # 9
  [Region, {head: 5}, [7, 9]], # 10
  [Phi, {predecessors: [6, 8], region: 10}, [7, 9], ~, Unknown], # 11
  [ArrayLiteral, {sigil: "@", symbol: "@Carp::CARP_NOT"}, [11], ~, Array], # 12
  [ArrayLiteral, ~, ~, ~, ArrayRef], # 13
  [Phi, {memory: true, predecessors: [6, 8], region: 10}, [7, 4], ~, Unknown], # 14
  [EntryWrite, {binds: true}, [2, 13], 10, Unknown, 14, true], # 15
  [EntryWrite, ~, [2, 12], 15, Unknown, 15, true], # 16
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 288, name: Carp::shortmess_heavy, package: Carp, param_names: []}, [1], 16, Unknown, 16, true], # 17
  [EntryDef, {package: main, sigil: $, symbol: "!"}, ~, ~, Scalar], # 18
  [EntryDef, {package: main, sigil: $, symbol: "!"}, ~, ~, Scalar, 3], # 19
  [EntryDef, {package: main, sigil: $, symbol: "\u0005"}, ~, ~, Scalar], # 20
  [EntryDef, {package: main, sigil: $, symbol: "\u0005"}, ~, ~, Scalar, 3], # 21
  [EntryDef, {package: Carp, sigil: "@", symbol: CARP_NOT}, ~, ~, Array, 14], # 22
  [Ref, ~, [22], ~, ArrayRef], # 23
  [EntryWrite, {binds: true}, [2, 23], 17, Unknown, 17, true], # 24
  [EntryWrite, ~, [20, 21], 24, Unknown, 24, true], # 25
  [EntryWrite, ~, [18, 19], 25, Unknown, 25, true], # 26
  [Return, {implicit: true}, [17], 26, ~, 26], # 27
  [EntryDef, {package: Carp, sigil: "@", symbol: CARP_NOT}, ~, ~, Array, 24]]} # 28
Carp::shortmess_heavy: {start: 0, returns: [36], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [EntryDef, {package: Carp, sigil: $, symbol: Verbose}, ~, ~, Scalar, 2], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 0}, [4]], # 5
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 681, name: Carp::longmess_heavy, package: Carp, param_names: []}, [1], 5, Unknown, 2, true], # 6
  [ArrayLiteral, ~, [1], ~, List], # 7
  [Proj, {index: 1}, [4]], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Subscript, {kind: array}, [1, 9], ~, Scalar, 2], # 10
  [RefType, ~, [10], ~, Str, 2], # 11
  [If, ~, [8, 11], 8], # 12
  [Proj, {index: 1}, [12]], # 13
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 683, name: Carp::short_error_loc, package: Carp, param_names: [], want: scalar}, ~, 13, Num, 2, true], # 14
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 14], # 15
  [Assign, ~, [15, 14], 14, Num, 14, true], # 16
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 16], # 17
  [If, ~, [16, 17], 16], # 18
  [Proj, {index: 0}, [18]], # 19
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 688, name: Carp::ret_summary, package: Carp, param_names: []}, [17, 1], 19, Str, 16, true], # 20
  [Proj, {index: 1}, [18]], # 21
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 688, name: Carp::longmess_heavy, package: Carp, param_names: []}, [1], 21, Unknown, 16, true], # 22
  [Region, {head: 18}, [20, 22]], # 23
  [Phi, {predecessors: [19, 21], region: 23}, [20, 22], ~, Unknown], # 24
  [Proj, {index: 0}, [12]], # 25
  [Region, {head: 12}, [25, 23]], # 26
  [Phi, {predecessors: [25, 13], region: 26}, [7, 24], ~, Unknown], # 27
  [Region, {head: 4}, [6, 26]], # 28
  [Phi, {predecessors: [5, 8], region: 28}, [6, 27], ~, Unknown], # 29
  [Coerce, {from_repr: List, to_repr: Scalar}, [1], ~, Scalar], # 30
  [Phi, {predecessors: [25, 13], region: 26}, [30, 24], ~, Unknown], # 31
  [Phi, {predecessors: [5, 8], region: 28}, [6, 31], ~, Unknown], # 32
  [Phi, {memory: true, predecessors: [19, 21], region: 23}, [20, 22], ~, Unknown], # 33
  [Phi, {exits: true, memory: true, predecessors: [25, 13], region: 26}, [2, 33], ~, Unknown], # 34
  [Phi, {exits: true, memory: true, predecessors: [5, 8], region: 28}, [6, 34], ~, Unknown], # 35
  [Return, ~, [29, 32], 28, ~, 35]]} # 36
Carp::str_len_trim: {start: 0, returns: [26], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [PadAccess, {sigil: $, symbol: str}, ~, ~, Unknown, 3], # 4
  [Assign, ~, [4, 3], 3, Scalar, 3, true], # 5
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 5, Scalar, 5, true], # 6
  [PadAccess, {sigil: $, symbol: str}, ~, ~, Str, 6], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Or, ~, [6, 8], ~, Scalar], # 9
  [Coerce, {from_repr: Scalar, to_repr: Num}, [9], ~, Num], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [Subtract, ~, [10, 11], ~, Num], # 12
  [Length, ~, [7], ~, Int], # 13
  [Constant, {const_type: string, value: "..."}, ~, ~, Str], # 14
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 15
  [NumLt, ~, [15, 10], ~, Boolean], # 16
  [NumLt, ~, [10, 13], ~, Boolean], # 17
  [And, ~, [16, 17], ~, Boolean], # 18
  [If, ~, [6, 18], 6], # 19
  [Proj, {index: 0}, [19]], # 20
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [7, 12, 13, 14], 20, Str, 6, true], # 21
  [Proj, {index: 1}, [19]], # 22
  [Region, {head: 19}, [22, 21]], # 23
  [Phi, {memory: true, predecessors: [22, 20], region: 23}, [6, 21], ~, Scalar], # 24
  [PadAccess, {sigil: $, symbol: str}, ~, ~, Unknown, 24], # 25
  [Return, ~, [25], 23, ~, 24], # 26
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [7, 12], ~, Str]]} # 27
Carp::trusts: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: known}, ~, ~, Unknown], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 0, Scalar, 3, true], # 4
  [PadAccess, {sigil: $, symbol: child}, ~, ~, Unknown, 4], # 5
  [Assign, ~, [5, 4], 4, Scalar, 4, true], # 6
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 6, Scalar, 6, true], # 7
  [PadAccess, {sigil: $, symbol: partial}, ~, ~, Unknown], # 8
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 7, Scalar, 7, true], # 9
  [PadAccess, {sigil: $, symbol: cache}, ~, ~, Unknown, 9], # 10
  [Assign, ~, [10, 9], 9, Scalar, 9, true], # 11
  [PadAccess, {sigil: $, symbol: cache}, ~, ~, Unknown, 11], # 12
  [PadAccess, {sigil: $, symbol: child}, ~, ~, Unknown, 11], # 13
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 712, name: Carp::get_status, package: Carp, param_names: [], want: list}, [12, 13], 11, List, 11, true], # 14
  [Assign, {targets: 2}, [1, 8, 14], 14, List, 14, true], # 15
  [Loop, {bound: each}, [15], 15], # 16
  [Proj, {index: 1}, [16]], # 17
  [Region, {head: 16}, [17]], # 18
  [Phi, {memory: true, region: 16}, [15, 55], ~, List], # 19
  [Phi, {memory: true, region: 18}, [19], ~, List], # 20
  [Exists, {kind: hash}, [1, 7], 18, Boolean, 20, true], # 21
  [Return, ~, [21], 21, ~, 21], # 22
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 722, package: Carp, sigil: "@", strict: true}, [8], 16, Array, 19, true], # 23
  [Exists, {kind: hash}, [1, 7], ~, Boolean, 23], # 24
  [PostfixDeref, {sigil: "@"}, [8], ~, Array, 23], # 25
  [Proj, {index: 0}, [16]], # 26
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [25], 26, Scalar, 23, true], # 27
  [PadAccess, {sigil: $, symbol: anc}, ~, ~, Unknown, 27], # 28
  [Assign, ~, [28, 27], 27, Scalar, 27, true], # 29
  [PadAccess, {sigil: $, symbol: anc}, ~, ~, Unknown, 29], # 30
  [Exists, {kind: hash}, [1, 30], 29, Boolean, 29, true], # 31
  [PadAccess, {sigil: $, symbol: anc}, ~, ~, Unknown, 31], # 32
  [Subscript, {kind: hash}, [1, 32], ~, Scalar], # 33
  [If, ~, [31, 31], 31], # 34
  [Proj, {index: 1}, [34]], # 35
  [Subscript, {kind: hash}, [1, 32], 35, Scalar, 31], # 36
  [PadAccess, {sigil: $, symbol: anc_knows}, ~, ~, Unknown], # 37
  [PadAccess, {sigil: $, symbol: anc_partial}, ~, ~, Unknown], # 38
  [Increment, ~, [36], ~, Scalar], # 39
  [Assign, ~, [33, 39], 36, Scalar, 31, true], # 40
  [PadAccess, {sigil: $, symbol: cache}, ~, ~, Unknown, 40], # 41
  [PadAccess, {sigil: $, symbol: anc}, ~, ~, Unknown, 40], # 42
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 719, name: Carp::get_status, package: Carp, param_names: [], want: list}, [41, 42], 40, List, 40, true], # 43
  [Assign, {targets: 2}, [37, 38, 43], 43, List, 43, true], # 44
  [PostfixDeref, {sigil: "%"}, [37], ~, Hash, 44], # 45
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [45], ~, List, 44], # 46
  [Slice, {kind: hash}, [46, 1], ~, List], # 47
  [Not, ~, [24], ~, Boolean], # 48
  [Assign, {targets: 1}, [47], 44, Unknown, 44, true], # 49
  [PostfixDeref, {sigil: "@"}, [8], ~, Array, 49], # 50
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 722, package: Carp, sigil: "@", strict: true}, [38], ~, Array, 49], # 51
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [50, 51], 49, Int, 49, true], # 52
  [Proj, {index: 0}, [34]], # 53
  [Region, {head: 34}, [53, 52]], # 54
  [Phi, {memory: true, predecessors: [53, 35], region: 54}, [31, 52], ~, Scalar], # 55
  [Count, ~, [23], ~, Int, 23], # 56
  [If, ~, [23, 56], 23], # 57
  [Proj, {index: 0}, [57]], # 58
  [Proj, {index: 1}, [57]], # 59
  [Region, {head: 57}, [58, 59]], # 60
  [Phi, {predecessors: [58, 59], region: 60}, [48, 56], ~, Scalar], # 61
  [Not, ~, [61], ~, Boolean], # 62
  [Not, ~, [62], 16, Boolean]]} # 63
Carp::trusts_directly: {start: 0, returns: [57], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "::"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [PostfixDeref, {sigil: "%"}, [6], ~, Hash, 3], # 7
  [Ref, ~, [7], ~, HashRef], # 8
  [Constant, {const_type: string, value: CARP_NOT}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: ISA}, ~, ~, Str], # 10
  [ArrayLiteral, ~, [9, 10], ~, Array], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Loop, {bound: entry}, [3], 3], # 13
  [Phi, {region: 13}, [12, 63], ~, Int], # 14
  [Phi, {memory: true, region: 13}, [3, 18], ~, Scalar], # 15
  [Subscript, {kind: array}, [11, 14], ~, Str, 15], # 16
  [Proj, {index: 0}, [13]], # 17
  [Subscript, {kind: hash}, [8, 16], 17, Scalar, 15, true], # 18
  [Subscript, {kind: hash}, [8, 16], ~, Scalar, 18], # 19
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 735, package: Carp, sigil: "@", strict: false}, [19], ~, Array, 18], # 20
  [ArrayLiteral, ~, [20], ~, List], # 21
  [ArrayLiteral, ~, ~, ~, List], # 22
  [If, ~, [18, 18], 18], # 23
  [Proj, {index: 0}, [23]], # 24
  [Proj, {index: 1}, [23]], # 25
  [Region, {head: 23}, [24, 25]], # 26
  [Subscript, {kind: hash}, [8, 16], ~, Scalar], # 27
  [Ref, {file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 735}, [27], ~, ScalarRef, 18], # 28
  [RefType, ~, [28], ~, Str, 18], # 29
  [Constant, {const_type: string, value: GLOB}, ~, ~, Str], # 30
  [StrEq, ~, [29, 30], ~, Boolean], # 31
  [Phi, {predecessors: [24, 25], region: 26}, [31, 18], ~, Scalar], # 32
  [If, ~, [26, 32], 26], # 33
  [Proj, {index: 0}, [33]], # 34
  [Proj, {index: 1}, [33]], # 35
  [Region, {head: 33}, [34, 35]], # 36
  [Constant, {const_type: string, value: ARRAY}, ~, ~, Str], # 37
  [Subscript, ~, [19, 37], ~, Scalar, 18], # 38
  [Phi, {predecessors: [34, 35], region: 36}, [38, 32], ~, Scalar], # 39
  [If, ~, [36, 39], 36], # 40
  [Proj, {index: 0}, [40]], # 41
  [Proj, {index: 1}, [40]], # 42
  [Region, {head: 40}, [41, 42]], # 43
  [Count, ~, [20], ~, Int, 18], # 44
  [Phi, {predecessors: [41, 42], region: 43}, [44, 39], ~, Scalar], # 45
  [If, ~, [43, 45], 43], # 46
  [Proj, {index: 0}, [46]], # 47
  [Proj, {index: 1}, [13]], # 48
  [Region, {head: 13}, [48]], # 49
  [Region, ~, [47, 49]], # 50
  [Phi, {predecessors: [47, 49], region: 50}, [21, 22], ~, List], # 51
  [Coerce, {from_repr: List, to_repr: Scalar}, [20], ~, Scalar], # 52
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 53
  [Phi, {predecessors: [47, 49], region: 50}, [52, 53], ~, Scalar], # 54
  [Phi, {memory: true, region: 49}, [15], ~, Scalar], # 55
  [Phi, {exits: true, memory: true, predecessors: [47, 49], region: 50}, [18, 55], ~, Scalar], # 56
  [Return, ~, [51, 54], 50, ~, 56], # 57
  [Count, ~, [11], ~, Int, 3], # 58
  [Count, ~, [11], ~, Int, 15], # 59
  [NumGt, ~, [59, 14], 13, Boolean], # 60
  [Proj, {index: 1}, [46]], # 61
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 62
  [Add, ~, [14, 62], ~, Int]]} # 63
Exporter::as_heavy: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: Exporter::Heavy::heavy_}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: "Exporter/Heavy.pm"}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 4], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, [7], 4, List, 4], # 8
  [Slice, {index_count: 1}, [6, 8], ~, List], # 9
  [Coerce, {from_repr: List, to_repr: Scalar}, [9], ~, Scalar], # 10
  [Assign, ~, [5, 10], 8, Scalar, 4, true], # 11
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 11], # 12
  [RegexSubst, {flags: "", pattern: ".*::", replacement: ""}, [12], 11, Str, 11, true], # 13
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Str, 13], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Concat, ~, [1, 15], ~, Str], # 16
  [Ref, ~, [16], ~, ScalarRef], # 17
  [Return, {implicit: true}, [17], 13, ~, 13]]} # 18
Exporter::export_fail: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [Return, {implicit: true}, [1], 3, ~, 3]]} # 4
POSIX::SigAction::flags: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: FLAGS}, ~, ~, Str], # 4
  [Coerce, {from_repr: Array, to_repr: Num}, [1], ~, Num], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [NumGt, ~, [5, 6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 1}, [8]], # 9
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 10
  [MemStart], # 11
  [Subscript, {kind: array}, [1, 6], ~, Scalar, 11], # 12
  [Proj, {index: 0}, [8]], # 13
  [Assign, ~, [10, 12], 13, Scalar, 11, true], # 14
  [Region, {head: 8}, [9, 14]], # 15
  [Phi, {memory: true, predecessors: [9, 13], region: 15}, [11, 14], ~, Unknown], # 16
  [Subscript, {kind: hash}, [3, 4], 15, Scalar, 16, true], # 17
  [Return, {implicit: true}, [17], 17, ~, 17]]} # 18
POSIX::SigAction::handler: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: HANDLER}, ~, ~, Str], # 4
  [Coerce, {from_repr: Array, to_repr: Num}, [1], ~, Num], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [NumGt, ~, [5, 6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 1}, [8]], # 9
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 10
  [MemStart], # 11
  [Subscript, {kind: array}, [1, 6], ~, Scalar, 11], # 12
  [Proj, {index: 0}, [8]], # 13
  [Assign, ~, [10, 12], 13, Scalar, 11, true], # 14
  [Region, {head: 8}, [9, 14]], # 15
  [Phi, {memory: true, predecessors: [9, 13], region: 15}, [11, 14], ~, Unknown], # 16
  [Subscript, {kind: hash}, [3, 4], 15, Scalar, 16, true], # 17
  [Return, {implicit: true}, [17], 17, ~, 17]]} # 18
POSIX::SigAction::mask: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: MASK}, ~, ~, Str], # 4
  [Coerce, {from_repr: Array, to_repr: Num}, [1], ~, Num], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [NumGt, ~, [5, 6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 1}, [8]], # 9
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 10
  [MemStart], # 11
  [Subscript, {kind: array}, [1, 6], ~, Scalar, 11], # 12
  [Proj, {index: 0}, [8]], # 13
  [Assign, ~, [10, 12], 13, Scalar, 11, true], # 14
  [Region, {head: 8}, [9, 14]], # 15
  [Phi, {memory: true, predecessors: [9, 13], region: 15}, [11, 14], ~, Unknown], # 16
  [Subscript, {kind: hash}, [3, 4], 15, Scalar, 16, true], # 17
  [Return, {implicit: true}, [17], 17, ~, 17]]} # 18
POSIX::SigAction::new: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: HANDLER}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Constant, {const_type: string, value: MASK}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7], ~, Scalar, 4], # 8
  [Constant, {const_type: string, value: FLAGS}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [2, 10], ~, Scalar, 4], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Or, ~, [11, 12], ~, Scalar], # 13
  [Constant, {const_type: string, value: SAFE}, ~, ~, Str], # 14
  [HashLiteral, ~, [1, 5, 6, 8, 9, 13, 14, 12], 0, HashRef], # 15
  [Subscript, {kind: array}, [2, 12], ~, Scalar, 4], # 16
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [15, 16], 15, Unknown, 4, true], # 17
  [Return, {implicit: true}, [17], 17, ~, 17]]} # 18
POSIX::SigAction::safe: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: SAFE}, ~, ~, Str], # 4
  [Coerce, {from_repr: Array, to_repr: Num}, [1], ~, Num], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [NumGt, ~, [5, 6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 1}, [8]], # 9
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 10
  [MemStart], # 11
  [Subscript, {kind: array}, [1, 6], ~, Scalar, 11], # 12
  [Proj, {index: 0}, [8]], # 13
  [Assign, ~, [10, 12], 13, Scalar, 11, true], # 14
  [Region, {head: 8}, [9, 14]], # 15
  [Phi, {memory: true, predecessors: [9, 13], region: 15}, [11, 14], ~, Unknown], # 16
  [Subscript, {kind: hash}, [3, 4], 15, Scalar, 16, true], # 17
  [Return, {implicit: true}, [17], 17, ~, 17]]} # 18
POSIX::SigRt::CLEAR: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: "%", symbol: SIG}, ~, ~, Hash], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 561, name: POSIX::SigRt::_exist, package: POSIX::SigRt, param_names: [], shares_args: true, want: void}, ~, 0, List, 2, true], # 3
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 561, name: POSIX::SIGRTMAX, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar, xs: true}, ~, 3, Unknown, 3, true], # 4
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 561, name: POSIX::SIGRTMIN, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar, xs: true}, ~, 4, Unknown, 4, true], # 5
  [Range, ~, [5, 4], ~, List], # 6
  [Delete, {kind: hash}, [1, 6], 5, Scalar, 5, true], # 7
  [ArrayLiteral, ~, [7], ~, List], # 8
  [Return, {implicit: true}, [8], 7, ~, 7]]} # 9
POSIX::SigRt::DELETE: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: "%", symbol: SIG}, ~, ~, Hash], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 560, name: POSIX::SigRt::_check, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar}, ~, 0, Unknown, 2, true], # 3
  [Delete, {kind: hash}, [1, 3], 3, Scalar, 3, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
POSIX::SigRt::EXISTS: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 554, name: POSIX::SigRt::_exist, package: POSIX::SigRt, param_names: [], shares_args: true}, ~, 0, List, 1, true], # 2
  [Return, {implicit: true}, [2], 2, ~, 2]]} # 3
POSIX::SigRt::FETCH: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: POSIX::SigAction}, ~, ~, Str], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 555, name: POSIX::SigRt::_check, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar}, ~, 0, Unknown, 2, true], # 3
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 3], # 4
  [Assign, ~, [4, 3], 3, Unknown, 3, true], # 5
  [Call, {class_name: POSIX::SigAction, dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 556, name: new, package: POSIX::SigRt, param_names: [], want: scalar}, [1], 5, Object, 5, true], # 6
  [PadAccess, {sigil: $, symbol: oa}, ~, ~, Unknown, 6], # 7
  [Assign, ~, [7, 6], 6, Object, 6, true], # 8
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 8], # 9
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 10
  [PadAccess, {sigil: $, symbol: oa}, ~, ~, Unknown, 8], # 11
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 557, name: POSIX::sigaction, package: POSIX::SigRt, param_names: [], want: void, xs: true}, [9, 10, 11], 8, Unknown, 8, true], # 12
  [PadAccess, {sigil: $, symbol: oa}, ~, ~, Unknown, 12], # 13
  [Constant, {const_type: string, value: HANDLER}, ~, ~, Str], # 14
  [Subscript, {kind: hash}, [13, 14], 12, Scalar, 12, true], # 15
  [Return, ~, [15], 15, ~, 15]]} # 16
POSIX::SigRt::SCALAR: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 562, name: POSIX::SigRt::_croak, package: POSIX::SigRt, param_names: [], shares_args: true, want: void}, ~, 0, "Maybe[Boolean]", 1, true], # 2
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _sigrtn}, ~, ~, Scalar, 2], # 3
  [Coerce, {from_repr: Scalar, to_repr: Num}, [3], ~, Num], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Add, ~, [4, 5], ~, Num], # 6
  [Return, {implicit: true}, [6], 2, ~, 2]]} # 7
POSIX::SigRt::STORE: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 559, name: POSIX::SigRt::_check, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar}, ~, 0, Unknown, 1, true], # 2
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 2], # 3
  [Assign, ~, [3, 2], 2, Unknown, 2, true], # 4
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 4], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [6, 7], ~, Scalar], # 8
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: SIGACTION_FLAGS}, ~, ~, Scalar, 4], # 9
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 559, name: POSIX::SigRt::new, package: POSIX::SigRt, param_names: []}, [5, 8, 9], 4, Unknown, 4, true], # 10
  [Return, {implicit: true}, [10], 10, ~, 10]]} # 11
POSIX::SigRt::_check: {start: 0, returns: [29], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown], # 1
  [PadAccess, {sigil: $, symbol: ok}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 541, name: POSIX::SigRt::_exist, package: POSIX::SigRt, param_names: [], shares_args: true, want: list}, ~, 0, List, 3, true], # 4
  [Assign, {targets: 2}, [1, 2, 4], 4, List, 4, true], # 5
  [If, ~, [5, 2], 5], # 6
  [Proj, {index: 0}, [6]], # 7
  [Constant, {const_type: string, value: "No POSIX::SigRt signal "}, ~, ~, Str], # 8
  [ArgsSource, ~, ~, ~, Array], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [9, 10], ~, Scalar, 5], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [8, 12], ~, Str], # 13
  [Constant, {const_type: string, value: " (valid range SIGRTMIN..SIGRTMAX, or "}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMIN}, ~, ~, Scalar, 5], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Concat, ~, [15, 17], ~, Str], # 18
  [Constant, {const_type: string, value: ".."}, ~, ~, Str], # 19
  [Concat, ~, [18, 19], ~, Str], # 20
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMAX}, ~, ~, Scalar, 5], # 21
  [Coerce, {from_repr: Unknown, to_repr: Str}, [21], ~, Str], # 22
  [Concat, ~, [20, 22], ~, Str], # 23
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 24
  [Concat, ~, [23, 24], ~, Str], # 25
  [Proj, {index: 1}, [6]], # 26
  [Unwind, {file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 542}, [25], 26, ~, 5], # 27
  [Region, {head: 6}, [7, 27]], # 28
  [Return, ~, [1], 28, ~, 5]]} # 29
POSIX::SigRt::_croak: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _sigrtn}, ~, ~, Scalar, 1], # 2
  [Defined, ~, [2], ~, Boolean], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 1}, [4]], # 5
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 521, name: POSIX::SigRt::_init, package: POSIX::SigRt, param_names: [], shares_args: true, want: void}, ~, 5, Num, 1, true], # 6
  [Proj, {index: 0}, [4]], # 7
  [Region, {head: 4}, [7, 6]], # 8
  [Phi, {memory: true, predecessors: [7, 5], region: 8}, [1, 6], ~, Unknown], # 9
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _sigrtn}, ~, ~, Scalar, 9], # 10
  [Defined, ~, [10], ~, Boolean], # 11
  [Coerce, {from_repr: Scalar, to_repr: Num}, [10], ~, Num], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [NumGt, ~, [12, 13], ~, Boolean], # 14
  [And, ~, [11, 14], ~, Boolean], # 15
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 16
  [Or, ~, [15, 16], ~, "Maybe[Boolean]"], # 17
  [If, ~, [8, 15], 8], # 18
  [Proj, {index: 0}, [18]], # 19
  [Constant, {const_type: string, value: "POSIX::SigRt not available"}, ~, ~, Str], # 20
  [Proj, {index: 1}, [18]], # 21
  [Unwind, {file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 522}, [20], 21, ~, 9], # 22
  [Region, {head: 18}, [19, 22]], # 23
  [Return, {implicit: true}, [17], 23, ~, 9]]} # 24
POSIX::SigRt::_exist: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 535, name: POSIX::SigRt::_getsig, package: POSIX::SigRt, param_names: [], want: scalar}, [3], 0, Unknown, 4, true], # 5
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMIN}, ~, ~, Scalar, 5], # 6
  [Coerce, {from_repr: Scalar, to_repr: Num}, [6], ~, Num], # 7
  [NumGe, ~, [5, 7], ~, Boolean], # 8
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMAX}, ~, ~, Scalar, 5], # 9
  [Coerce, {from_repr: Scalar, to_repr: Num}, [9], ~, Num], # 10
  [NumLe, ~, [5, 10], ~, Boolean], # 11
  [And, ~, [8, 11], ~, Boolean], # 12
  [ArrayLiteral, ~, [5, 12], ~, List], # 13
  [Coerce, {from_repr: List, to_repr: Scalar}, [12], ~, Scalar], # 14
  [Return, {implicit: true}, [13, 14], 5, ~, 5]]} # 15
POSIX::SigRt::_getsig: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 526, name: POSIX::SigRt::_croak, package: POSIX::SigRt, param_names: [], shares_args: true, want: void}, ~, 0, "Maybe[Boolean]", 3, true], # 4
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 4], # 5
  [Coerce, {from_repr: Scalar, to_repr: Str}, [5], ~, Str], # 6
  [RegexMatch, {flags: "", pattern: "^(?:(?:SIG)?RT)?MIN(\\s*\\+\\s*(\\d+))?$"}, [6], ~, Boolean], # 7
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMIN}, ~, ~, Scalar, 4], # 8
  [Coerce, {from_repr: Scalar, to_repr: Num}, [8], ~, Num], # 9
  [RegexCapture, {"n": 1}, [7], ~, Str], # 10
  [Or, ~, [10, 2], ~, Str], # 11
  [Coerce, {from_repr: Str, to_repr: Num}, [11], ~, Num], # 12
  [Add, ~, [9, 12], ~, Num], # 13
  [TernaryExpr, {rebind_arm: 1}, [7, 13, 5], 4, Unknown], # 14
  [Return, ~, [14], 14, ~, 4]]} # 15
POSIX::SigRt::_init: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMAX}, ~, ~, Scalar], # 1
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMIN}, ~, ~, Scalar], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 515, name: POSIX::SIGRTMIN, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar, xs: true}, ~, 0, Unknown, 3, true], # 4
  [EntryWrite, ~, [2, 4], 4, Unknown, 4, true], # 5
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 516, name: POSIX::SIGRTMAX, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar, xs: true}, ~, 5, Unknown, 5, true], # 6
  [EntryWrite, ~, [1, 6], 6, Unknown, 6, true], # 7
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMAX}, ~, ~, Scalar, 7], # 8
  [Coerce, {from_repr: Scalar, to_repr: Num}, [8], ~, Num], # 9
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMIN}, ~, ~, Scalar, 7], # 10
  [Coerce, {from_repr: Scalar, to_repr: Num}, [10], ~, Num], # 11
  [Subtract, ~, [9, 11], ~, Num], # 12
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _sigrtn}, ~, ~, Scalar], # 13
  [EntryWrite, ~, [13, 12], 7, Unknown, 7, true], # 14
  [Return, {implicit: true}, [12], 14, ~, 14]]} # 15
POSIX::SigRt::new: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: POSIX::SigAction}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: POSIX::SigSet}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 3], # 4
  [PadAccess, {sigil: $, symbol: handler}, ~, ~, Unknown, 3], # 5
  [PadAccess, {sigil: $, symbol: flags}, ~, ~, Unknown, 3], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Assign, {targets: 3}, [4, 5, 6, 7], 0, List, 3, true], # 8
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 8], # 9
  [Call, {class_name: POSIX::SigSet, dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 549, name: new, package: POSIX::SigRt, param_names: [], want: scalar}, [2, 9], 8, Object, 8, true], # 10
  [PadAccess, {sigil: $, symbol: sigset}, ~, ~, Unknown, 10], # 11
  [Assign, ~, [11, 10], 10, Object, 10, true], # 12
  [PadAccess, {sigil: $, symbol: handler}, ~, ~, Unknown, 12], # 13
  [PadAccess, {sigil: $, symbol: sigset}, ~, ~, Unknown, 12], # 14
  [PadAccess, {sigil: $, symbol: flags}, ~, ~, Unknown, 12], # 15
  [Call, {class_name: POSIX::SigAction, dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 550, name: new, package: POSIX::SigRt, param_names: [], want: scalar}, [1, 13, 14, 15], 12, Object, 12, true], # 16
  [PadAccess, {sigil: $, symbol: sigact}, ~, ~, Unknown, 16], # 17
  [Assign, ~, [17, 16], 16, Object, 16, true], # 18
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 18], # 19
  [PadAccess, {sigil: $, symbol: sigact}, ~, ~, Unknown, 18], # 20
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 551, name: POSIX::sigaction, package: POSIX::SigRt, param_names: [], xs: true}, [19, 20], 18, Unknown, 18, true], # 21
  [Return, {implicit: true}, [21], 21, ~, 21]]} # 22
POSIX::import: {start: 0, returns: [66], nodes: [
  [Start], # 0
  [EntryDef, {package: Exporter, sigil: $, symbol: ExportLevel}, ~, ~, Scalar], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [4], 0, Scalar, 5, true], # 6
  [PadAccess, {sigil: $, symbol: pkg}, ~, ~, Unknown, 6], # 7
  [Assign, ~, [7, 6], 6, Scalar, 6, true], # 8
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: loaded}, ~, ~, Unknown, 8], # 9
  [Increment, ~, [9], ~, Scalar], # 10
  [Assign, ~, [9, 10], 8, Scalar, 8, true], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [DefinedOr, ~, [9, 12], ~, Scalar], # 13
  [If, ~, [11, 13], 11], # 14
  [Proj, {index: 1}, [14]], # 15
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 177, name: POSIX::load_imports, package: POSIX, param_names: [], want: void}, ~, 15, Unknown, 11, true], # 16
  [Proj, {index: 0}, [14]], # 17
  [Region, {head: 14}, [17, 16]], # 18
  [Phi, {memory: true, predecessors: [17, 15], region: 18}, [11, 16], ~, Unknown], # 19
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar, 19], # 20
  [Loop, {bound: entry}, [18], 18], # 21
  [Proj, {index: 1}, [21]], # 22
  [Region, {head: 21}, [22]], # 23
  [Phi, {memory: true, region: 21}, [19, 91], ~, Unknown], # 24
  [Phi, {memory: true, region: 23}, [24], ~, Unknown], # 25
  [EntryWrite, ~, [3, 20], 23, Unknown, 25, true], # 26
  [Loop, {bound: entry}, [26], 26], # 27
  [Proj, {index: 1}, [27]], # 28
  [Region, {head: 27}, [28]], # 29
  [ArrayLiteral, ~, ~, ~, Array], # 30
  [Phi, {region: 27}, [30, 80], ~, Array], # 31
  [Phi, {memory: true, region: 27}, [26, 32], ~, Unknown], # 32
  [Phi, {memory: true, region: 29}, [32], ~, Unknown], # 33
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [31], ~, List, 33], # 34
  [ArrayLiteral, {sigil: "@", symbol: unimpl}, [34], ~, Array], # 35
  [Count, ~, [35], ~, Int, 33], # 36
  [If, ~, [29, 36], 29], # 37
  [Proj, {index: 1}, [37]], # 38
  [Constant, {const_type: string, value: "Unimplemented: "}, ~, ~, Str], # 39
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 40
  [ArrayLiteral, ~, ~, ~, Array], # 41
  [Proj, {index: 0}, [37]], # 42
  [Loop, {bound: entry}, [42], 42], # 43
  [Proj, {index: 1}, [43]], # 44
  [Region, {head: 43}, [44]], # 45
  [Loop, {bound: entry}, [45], 45], # 46
  [Phi, {region: 46}, [41, 125], ~, Array], # 47
  [Phi, {memory: true, region: 43}, [33, 117], ~, Unknown], # 48
  [Phi, {memory: true, region: 45}, [48], ~, Unknown], # 49
  [Phi, {memory: true, region: 46}, [49, 50], ~, Unknown], # 50
  [Proj, {index: 1}, [46]], # 51
  [Region, {head: 46}, [51]], # 52
  [Phi, {memory: true, region: 52}, [50], ~, Unknown], # 53
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [40, 47], ~, Str, 53], # 54
  [Concat, ~, [39, 54], ~, Str], # 55
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 56
  [Concat, ~, [55, 56], ~, Str], # 57
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 188, name: POSIX::croak, package: POSIX, param_names: [], want: void}, [57], 52, Unknown, 53, true], # 58
  [Region, {head: 37}, [38, 58]], # 59
  [Phi, {memory: true, predecessors: [38, 42], region: 59}, [33, 58], ~, Unknown], # 60
  [EntryWrite, ~, [1, 2], 59, Unknown, 60, true], # 61
  [PadAccess, {sigil: $, symbol: pkg}, ~, ~, Unknown, 61], # 62
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 192, name: Exporter::import, package: POSIX, param_names: []}, [62, 4], 61, Unknown, 61, true], # 63
  [EntryDef, {package: Exporter, sigil: $, symbol: ExportLevel}, ~, ~, Scalar, 60], # 64
  [EntryWrite, ~, [1, 64], 63, Unknown, 63, true], # 65
  [Return, {implicit: true}, [63], 65, ~, 65], # 66
  [ArrayLiteral, ~, [4], ~, Array], # 67
  [Count, ~, [4], ~, Int, 26], # 68
  [Count, ~, [4], ~, Int, 32], # 69
  [Phi, {region: 27}, [12, 82], ~, Int], # 70
  [Subscript, {kind: array}, [4, 70], ~, Scalar, 32], # 71
  [Count, ~, [67], ~, Int, 19], # 72
  [Count, ~, [67], ~, Int, 24], # 73
  [Phi, {region: 21}, [12, 81], ~, Int], # 74
  [Subscript, {kind: array}, [67, 74], ~, Scalar, 24], # 75
  [Subscript, {kind: array}, [67, 74], ~, Scalar], # 76
  [NumGt, ~, [69, 70], 27, Boolean], # 77
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: replacement}, ~, ~, Hash], # 78
  [Exists, {kind: hash}, [78, 71], ~, Boolean, 32], # 79
  [ListAppend, {collector: grep}, [31, 71, 79], ~, Array], # 80
  [Add, ~, [74, 2], ~, Int], # 81
  [Add, ~, [70, 2], ~, Int], # 82
  [Phi, {region: 43}, [12, 84], ~, Int], # 83
  [Add, ~, [83, 2], ~, Int], # 84
  [Phi, {region: 46}, [12, 86], ~, Int], # 85
  [Add, ~, [85, 2], ~, Int], # 86
  [NumGt, ~, [73, 74], 21, Boolean], # 87
  [Proj, {index: 0}, [21]], # 88
  [RegexSubst, {flags: "", pattern: "^(?=\\w+_h$)", replacement: ":"}, [75], 88, Str, 24, true], # 89
  [EntryWrite, ~, [3, 89], 89, Unknown, 89, true], # 90
  [Assign, ~, [76, 89], 90, Str, 90, true], # 91
  [Proj, {index: 0}, [27]], # 92
  [Count, ~, [35], ~, Int, 48], # 93
  [NumGt, ~, [93, 83], 43, Boolean], # 94
  [Proj, {index: 0}, [43]], # 95
  [Exists, {kind: array}, [35, 83], 95, Boolean, 48], # 96
  [Subscript, {kind: array}, [35, 83], ~, Scalar], # 97
  [Subscript, {kind: array}, [35, 83], ~, Scalar, 48], # 98
  [Subscript, {kind: array}, [35, 83], ~, Scalar, 48], # 99
  [PostfixDeref, {sigil: "@"}, [35], ~, Array, 49], # 100
  [Count, ~, [100], ~, Int, 50], # 101
  [NumGt, ~, [101, 85], 46, Boolean], # 102
  [Subscript, {kind: array}, [100, 85], ~, Scalar, 50], # 103
  [Constant, {const_type: string, value: "Unimplemented: POSIX::"}, ~, ~, Str], # 104
  [Ref, ~, [97], ~, ScalarRef], # 105
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 106
  [TernaryExpr, ~, [96, 105, 106], 96, "Maybe[ScalarRef]"], # 107
  [PostfixDeref, {sigil: $}, [107], ~, Scalar, 48], # 108
  [TernaryExpr, ~, [96, 108, 98], 107, Scalar], # 109
  [Coerce, {from_repr: Scalar, to_repr: Str}, [109], ~, Str], # 110
  [Concat, ~, [104, 110], ~, Str], # 111
  [Constant, {const_type: string, value: "(): "}, ~, ~, Str], # 112
  [Concat, ~, [111, 112], ~, Str], # 113
  [PostfixDeref, {sigil: $}, [107], ~, Scalar, 48], # 114
  [TernaryExpr, ~, [96, 114, 99], ~, Scalar], # 115
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 185, name: POSIX::unimplemented_message, package: POSIX, param_names: [], want: list}, [115], 109, Str, 48, true], # 116
  [Call, {dispatch_kind: builtin, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 185, name: warn, param_names: []}, [113, 116], 116, Boolean, 116, true], # 117
  [Coerce, {from_repr: Unknown, to_repr: Str}, [103], ~, Str], # 118
  [Count, ~, [100], ~, Int, 49], # 119
  [Proj, {index: 0}, [46]], # 120
  [Constant, {const_type: string, value: "POSIX::"}, ~, ~, Str], # 121
  [Concat, ~, [121, 118], ~, Str], # 122
  [Constant, {const_type: string, value: "()"}, ~, ~, Str], # 123
  [Concat, ~, [122, 123], ~, Str], # 124
  [ListAppend, {collector: map}, [47, 124], ~, Array]]} # 125
POSIX::load_imports: {start: 0, returns: [898], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: Exporter.pm}, ~, ~, Str], # 1
  [EntryDef, {package: POSIX, sigil: "%", symbol: EXPORT_TAGS}, ~, ~, Hash], # 2
  [Constant, {const_type: string, value: assert_h}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: assert}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: NDEBUG}, ~, ~, Str], # 5
  [ArrayLiteral, ~, [4, 5], 0, ArrayRef], # 6
  [Constant, {const_type: string, value: ctype_h}, ~, ~, Str], # 7
  [ArrayLiteral, ~, ~, 6, ArrayRef], # 8
  [Constant, {const_type: string, value: dirent_h}, ~, ~, Str], # 9
  [ArrayLiteral, ~, ~, 8, ArrayRef], # 10
  [Constant, {const_type: string, value: errno_h}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: E2BIG}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: EACCES}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: EADDRINUSE}, ~, ~, Str], # 14
  [Constant, {const_type: string, value: EADDRNOTAVAIL}, ~, ~, Str], # 15
  [Constant, {const_type: string, value: EAFNOSUPPORT}, ~, ~, Str], # 16
  [Constant, {const_type: string, value: EAGAIN}, ~, ~, Str], # 17
  [Constant, {const_type: string, value: EALREADY}, ~, ~, Str], # 18
  [Constant, {const_type: string, value: EBADF}, ~, ~, Str], # 19
  [Constant, {const_type: string, value: EBADMSG}, ~, ~, Str], # 20
  [Constant, {const_type: string, value: EBUSY}, ~, ~, Str], # 21
  [Constant, {const_type: string, value: ECANCELED}, ~, ~, Str], # 22
  [Constant, {const_type: string, value: ECHILD}, ~, ~, Str], # 23
  [Constant, {const_type: string, value: ECONNABORTED}, ~, ~, Str], # 24
  [Constant, {const_type: string, value: ECONNREFUSED}, ~, ~, Str], # 25
  [Constant, {const_type: string, value: ECONNRESET}, ~, ~, Str], # 26
  [Constant, {const_type: string, value: EDEADLK}, ~, ~, Str], # 27
  [Constant, {const_type: string, value: EDESTADDRREQ}, ~, ~, Str], # 28
  [Constant, {const_type: string, value: EDOM}, ~, ~, Str], # 29
  [Constant, {const_type: string, value: EDQUOT}, ~, ~, Str], # 30
  [Constant, {const_type: string, value: EEXIST}, ~, ~, Str], # 31
  [Constant, {const_type: string, value: EFAULT}, ~, ~, Str], # 32
  [Constant, {const_type: string, value: EFBIG}, ~, ~, Str], # 33
  [Constant, {const_type: string, value: EHOSTDOWN}, ~, ~, Str], # 34
  [Constant, {const_type: string, value: EHOSTUNREACH}, ~, ~, Str], # 35
  [Constant, {const_type: string, value: EIDRM}, ~, ~, Str], # 36
  [Constant, {const_type: string, value: EILSEQ}, ~, ~, Str], # 37
  [Constant, {const_type: string, value: EINPROGRESS}, ~, ~, Str], # 38
  [Constant, {const_type: string, value: EINTR}, ~, ~, Str], # 39
  [Constant, {const_type: string, value: EINVAL}, ~, ~, Str], # 40
  [Constant, {const_type: string, value: EIO}, ~, ~, Str], # 41
  [Constant, {const_type: string, value: EISCONN}, ~, ~, Str], # 42
  [Constant, {const_type: string, value: EISDIR}, ~, ~, Str], # 43
  [Constant, {const_type: string, value: ELOOP}, ~, ~, Str], # 44
  [Constant, {const_type: string, value: EMFILE}, ~, ~, Str], # 45
  [Constant, {const_type: string, value: EMLINK}, ~, ~, Str], # 46
  [Constant, {const_type: string, value: EMSGSIZE}, ~, ~, Str], # 47
  [Constant, {const_type: string, value: ENAMETOOLONG}, ~, ~, Str], # 48
  [Constant, {const_type: string, value: ENETDOWN}, ~, ~, Str], # 49
  [Constant, {const_type: string, value: ENETRESET}, ~, ~, Str], # 50
  [Constant, {const_type: string, value: ENETUNREACH}, ~, ~, Str], # 51
  [Constant, {const_type: string, value: ENFILE}, ~, ~, Str], # 52
  [Constant, {const_type: string, value: ENOBUFS}, ~, ~, Str], # 53
  [Constant, {const_type: string, value: ENODATA}, ~, ~, Str], # 54
  [Constant, {const_type: string, value: ENODEV}, ~, ~, Str], # 55
  [Constant, {const_type: string, value: ENOENT}, ~, ~, Str], # 56
  [Constant, {const_type: string, value: ENOEXEC}, ~, ~, Str], # 57
  [Constant, {const_type: string, value: ENOLCK}, ~, ~, Str], # 58
  [Constant, {const_type: string, value: ENOLINK}, ~, ~, Str], # 59
  [Constant, {const_type: string, value: ENOMEM}, ~, ~, Str], # 60
  [Constant, {const_type: string, value: ENOMSG}, ~, ~, Str], # 61
  [Constant, {const_type: string, value: ENOPROTOOPT}, ~, ~, Str], # 62
  [Constant, {const_type: string, value: ENOSPC}, ~, ~, Str], # 63
  [Constant, {const_type: string, value: ENOSR}, ~, ~, Str], # 64
  [Constant, {const_type: string, value: ENOSTR}, ~, ~, Str], # 65
  [Constant, {const_type: string, value: ENOSYS}, ~, ~, Str], # 66
  [Constant, {const_type: string, value: ENOTBLK}, ~, ~, Str], # 67
  [Constant, {const_type: string, value: ENOTCONN}, ~, ~, Str], # 68
  [Constant, {const_type: string, value: ENOTDIR}, ~, ~, Str], # 69
  [Constant, {const_type: string, value: ENOTEMPTY}, ~, ~, Str], # 70
  [Constant, {const_type: string, value: ENOTRECOVERABLE}, ~, ~, Str], # 71
  [Constant, {const_type: string, value: ENOTSOCK}, ~, ~, Str], # 72
  [Constant, {const_type: string, value: ENOTSUP}, ~, ~, Str], # 73
  [Constant, {const_type: string, value: ENOTTY}, ~, ~, Str], # 74
  [Constant, {const_type: string, value: ENXIO}, ~, ~, Str], # 75
  [Constant, {const_type: string, value: EOPNOTSUPP}, ~, ~, Str], # 76
  [Constant, {const_type: string, value: EOTHER}, ~, ~, Str], # 77
  [Constant, {const_type: string, value: EOVERFLOW}, ~, ~, Str], # 78
  [Constant, {const_type: string, value: EOWNERDEAD}, ~, ~, Str], # 79
  [Constant, {const_type: string, value: EPERM}, ~, ~, Str], # 80
  [Constant, {const_type: string, value: EPFNOSUPPORT}, ~, ~, Str], # 81
  [Constant, {const_type: string, value: EPIPE}, ~, ~, Str], # 82
  [Constant, {const_type: string, value: EPROCLIM}, ~, ~, Str], # 83
  [Constant, {const_type: string, value: EPROTO}, ~, ~, Str], # 84
  [Constant, {const_type: string, value: EPROTONOSUPPORT}, ~, ~, Str], # 85
  [Constant, {const_type: string, value: EPROTOTYPE}, ~, ~, Str], # 86
  [Constant, {const_type: string, value: ERANGE}, ~, ~, Str], # 87
  [Constant, {const_type: string, value: EREMOTE}, ~, ~, Str], # 88
  [Constant, {const_type: string, value: ERESTART}, ~, ~, Str], # 89
  [Constant, {const_type: string, value: EROFS}, ~, ~, Str], # 90
  [Constant, {const_type: string, value: ESHUTDOWN}, ~, ~, Str], # 91
  [Constant, {const_type: string, value: ESOCKTNOSUPPORT}, ~, ~, Str], # 92
  [Constant, {const_type: string, value: ESPIPE}, ~, ~, Str], # 93
  [Constant, {const_type: string, value: ESRCH}, ~, ~, Str], # 94
  [Constant, {const_type: string, value: ESTALE}, ~, ~, Str], # 95
  [Constant, {const_type: string, value: ETIME}, ~, ~, Str], # 96
  [Constant, {const_type: string, value: ETIMEDOUT}, ~, ~, Str], # 97
  [Constant, {const_type: string, value: ETOOMANYREFS}, ~, ~, Str], # 98
  [Constant, {const_type: string, value: ETXTBSY}, ~, ~, Str], # 99
  [Constant, {const_type: string, value: EUSERS}, ~, ~, Str], # 100
  [Constant, {const_type: string, value: EWOULDBLOCK}, ~, ~, Str], # 101
  [Constant, {const_type: string, value: EXDEV}, ~, ~, Str], # 102
  [Constant, {const_type: string, value: errno}, ~, ~, Str], # 103
  [ArrayLiteral, ~, [12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103], 10, ArrayRef], # 104
  [Constant, {const_type: string, value: fcntl_h}, ~, ~, Str], # 105
  [Constant, {const_type: string, value: FD_CLOEXEC}, ~, ~, Str], # 106
  [Constant, {const_type: string, value: F_DUPFD}, ~, ~, Str], # 107
  [Constant, {const_type: string, value: F_GETFD}, ~, ~, Str], # 108
  [Constant, {const_type: string, value: F_GETFL}, ~, ~, Str], # 109
  [Constant, {const_type: string, value: F_GETLK}, ~, ~, Str], # 110
  [Constant, {const_type: string, value: F_RDLCK}, ~, ~, Str], # 111
  [Constant, {const_type: string, value: F_SETFD}, ~, ~, Str], # 112
  [Constant, {const_type: string, value: F_SETFL}, ~, ~, Str], # 113
  [Constant, {const_type: string, value: F_SETLK}, ~, ~, Str], # 114
  [Constant, {const_type: string, value: F_SETLKW}, ~, ~, Str], # 115
  [Constant, {const_type: string, value: F_UNLCK}, ~, ~, Str], # 116
  [Constant, {const_type: string, value: F_WRLCK}, ~, ~, Str], # 117
  [Constant, {const_type: string, value: O_ACCMODE}, ~, ~, Str], # 118
  [Constant, {const_type: string, value: O_APPEND}, ~, ~, Str], # 119
  [Constant, {const_type: string, value: O_CREAT}, ~, ~, Str], # 120
  [Constant, {const_type: string, value: O_EXCL}, ~, ~, Str], # 121
  [Constant, {const_type: string, value: O_NOCTTY}, ~, ~, Str], # 122
  [Constant, {const_type: string, value: O_NONBLOCK}, ~, ~, Str], # 123
  [Constant, {const_type: string, value: O_RDONLY}, ~, ~, Str], # 124
  [Constant, {const_type: string, value: O_RDWR}, ~, ~, Str], # 125
  [Constant, {const_type: string, value: O_TRUNC}, ~, ~, Str], # 126
  [Constant, {const_type: string, value: O_WRONLY}, ~, ~, Str], # 127
  [Constant, {const_type: string, value: creat}, ~, ~, Str], # 128
  [Constant, {const_type: string, value: SEEK_CUR}, ~, ~, Str], # 129
  [Constant, {const_type: string, value: SEEK_END}, ~, ~, Str], # 130
  [Constant, {const_type: string, value: SEEK_SET}, ~, ~, Str], # 131
  [Constant, {const_type: string, value: S_IRGRP}, ~, ~, Str], # 132
  [Constant, {const_type: string, value: S_IROTH}, ~, ~, Str], # 133
  [Constant, {const_type: string, value: S_IRUSR}, ~, ~, Str], # 134
  [Constant, {const_type: string, value: S_IRWXG}, ~, ~, Str], # 135
  [Constant, {const_type: string, value: S_IRWXO}, ~, ~, Str], # 136
  [Constant, {const_type: string, value: S_IRWXU}, ~, ~, Str], # 137
  [Constant, {const_type: string, value: S_ISBLK}, ~, ~, Str], # 138
  [Constant, {const_type: string, value: S_ISCHR}, ~, ~, Str], # 139
  [Constant, {const_type: string, value: S_ISDIR}, ~, ~, Str], # 140
  [Constant, {const_type: string, value: S_ISFIFO}, ~, ~, Str], # 141
  [Constant, {const_type: string, value: S_ISGID}, ~, ~, Str], # 142
  [Constant, {const_type: string, value: S_ISLNK}, ~, ~, Str], # 143
  [Constant, {const_type: string, value: S_ISREG}, ~, ~, Str], # 144
  [Constant, {const_type: string, value: S_ISSOCK}, ~, ~, Str], # 145
  [Constant, {const_type: string, value: S_ISUID}, ~, ~, Str], # 146
  [Constant, {const_type: string, value: S_IWGRP}, ~, ~, Str], # 147
  [Constant, {const_type: string, value: S_IWOTH}, ~, ~, Str], # 148
  [Constant, {const_type: string, value: S_IWUSR}, ~, ~, Str], # 149
  [ArrayLiteral, ~, [106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149], 104, ArrayRef], # 150
  [Constant, {const_type: string, value: float_h}, ~, ~, Str], # 151
  [Constant, {const_type: string, value: DBL_DIG}, ~, ~, Str], # 152
  [Constant, {const_type: string, value: DBL_EPSILON}, ~, ~, Str], # 153
  [Constant, {const_type: string, value: DBL_MANT_DIG}, ~, ~, Str], # 154
  [Constant, {const_type: string, value: DBL_MAX}, ~, ~, Str], # 155
  [Constant, {const_type: string, value: DBL_MAX_10_EXP}, ~, ~, Str], # 156
  [Constant, {const_type: string, value: DBL_MAX_EXP}, ~, ~, Str], # 157
  [Constant, {const_type: string, value: DBL_MIN}, ~, ~, Str], # 158
  [Constant, {const_type: string, value: DBL_MIN_10_EXP}, ~, ~, Str], # 159
  [Constant, {const_type: string, value: DBL_MIN_EXP}, ~, ~, Str], # 160
  [Constant, {const_type: string, value: FLT_DIG}, ~, ~, Str], # 161
  [Constant, {const_type: string, value: FLT_EPSILON}, ~, ~, Str], # 162
  [Constant, {const_type: string, value: FLT_MANT_DIG}, ~, ~, Str], # 163
  [Constant, {const_type: string, value: FLT_MAX}, ~, ~, Str], # 164
  [Constant, {const_type: string, value: FLT_MAX_10_EXP}, ~, ~, Str], # 165
  [Constant, {const_type: string, value: FLT_MAX_EXP}, ~, ~, Str], # 166
  [Constant, {const_type: string, value: FLT_MIN}, ~, ~, Str], # 167
  [Constant, {const_type: string, value: FLT_MIN_10_EXP}, ~, ~, Str], # 168
  [Constant, {const_type: string, value: FLT_MIN_EXP}, ~, ~, Str], # 169
  [Constant, {const_type: string, value: FLT_RADIX}, ~, ~, Str], # 170
  [Constant, {const_type: string, value: FLT_ROUNDS}, ~, ~, Str], # 171
  [Constant, {const_type: string, value: LDBL_DIG}, ~, ~, Str], # 172
  [Constant, {const_type: string, value: LDBL_EPSILON}, ~, ~, Str], # 173
  [Constant, {const_type: string, value: LDBL_MANT_DIG}, ~, ~, Str], # 174
  [Constant, {const_type: string, value: LDBL_MAX}, ~, ~, Str], # 175
  [Constant, {const_type: string, value: LDBL_MAX_10_EXP}, ~, ~, Str], # 176
  [Constant, {const_type: string, value: LDBL_MAX_EXP}, ~, ~, Str], # 177
  [Constant, {const_type: string, value: LDBL_MIN}, ~, ~, Str], # 178
  [Constant, {const_type: string, value: LDBL_MIN_10_EXP}, ~, ~, Str], # 179
  [Constant, {const_type: string, value: LDBL_MIN_EXP}, ~, ~, Str], # 180
  [ArrayLiteral, ~, [152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180], 150, ArrayRef], # 181
  [Constant, {const_type: string, value: grp_h}, ~, ~, Str], # 182
  [ArrayLiteral, ~, ~, 181, ArrayRef], # 183
  [Constant, {const_type: string, value: limits_h}, ~, ~, Str], # 184
  [Constant, {const_type: string, value: ARG_MAX}, ~, ~, Str], # 185
  [Constant, {const_type: string, value: CHAR_BIT}, ~, ~, Str], # 186
  [Constant, {const_type: string, value: CHAR_MAX}, ~, ~, Str], # 187
  [Constant, {const_type: string, value: CHAR_MIN}, ~, ~, Str], # 188
  [Constant, {const_type: string, value: CHILD_MAX}, ~, ~, Str], # 189
  [Constant, {const_type: string, value: INT_MAX}, ~, ~, Str], # 190
  [Constant, {const_type: string, value: INT_MIN}, ~, ~, Str], # 191
  [Constant, {const_type: string, value: LINK_MAX}, ~, ~, Str], # 192
  [Constant, {const_type: string, value: LONG_MAX}, ~, ~, Str], # 193
  [Constant, {const_type: string, value: LONG_MIN}, ~, ~, Str], # 194
  [Constant, {const_type: string, value: MAX_CANON}, ~, ~, Str], # 195
  [Constant, {const_type: string, value: MAX_INPUT}, ~, ~, Str], # 196
  [Constant, {const_type: string, value: MB_LEN_MAX}, ~, ~, Str], # 197
  [Constant, {const_type: string, value: NAME_MAX}, ~, ~, Str], # 198
  [Constant, {const_type: string, value: NGROUPS_MAX}, ~, ~, Str], # 199
  [Constant, {const_type: string, value: OPEN_MAX}, ~, ~, Str], # 200
  [Constant, {const_type: string, value: PATH_MAX}, ~, ~, Str], # 201
  [Constant, {const_type: string, value: PIPE_BUF}, ~, ~, Str], # 202
  [Constant, {const_type: string, value: SCHAR_MAX}, ~, ~, Str], # 203
  [Constant, {const_type: string, value: SCHAR_MIN}, ~, ~, Str], # 204
  [Constant, {const_type: string, value: SHRT_MAX}, ~, ~, Str], # 205
  [Constant, {const_type: string, value: SHRT_MIN}, ~, ~, Str], # 206
  [Constant, {const_type: string, value: SSIZE_MAX}, ~, ~, Str], # 207
  [Constant, {const_type: string, value: STREAM_MAX}, ~, ~, Str], # 208
  [Constant, {const_type: string, value: TZNAME_MAX}, ~, ~, Str], # 209
  [Constant, {const_type: string, value: UCHAR_MAX}, ~, ~, Str], # 210
  [Constant, {const_type: string, value: UINT_MAX}, ~, ~, Str], # 211
  [Constant, {const_type: string, value: ULONG_MAX}, ~, ~, Str], # 212
  [Constant, {const_type: string, value: USHRT_MAX}, ~, ~, Str], # 213
  [Constant, {const_type: string, value: _POSIX_ARG_MAX}, ~, ~, Str], # 214
  [Constant, {const_type: string, value: _POSIX_CHILD_MAX}, ~, ~, Str], # 215
  [Constant, {const_type: string, value: _POSIX_LINK_MAX}, ~, ~, Str], # 216
  [Constant, {const_type: string, value: _POSIX_MAX_CANON}, ~, ~, Str], # 217
  [Constant, {const_type: string, value: _POSIX_MAX_INPUT}, ~, ~, Str], # 218
  [Constant, {const_type: string, value: _POSIX_NAME_MAX}, ~, ~, Str], # 219
  [Constant, {const_type: string, value: _POSIX_NGROUPS_MAX}, ~, ~, Str], # 220
  [Constant, {const_type: string, value: _POSIX_OPEN_MAX}, ~, ~, Str], # 221
  [Constant, {const_type: string, value: _POSIX_PATH_MAX}, ~, ~, Str], # 222
  [Constant, {const_type: string, value: _POSIX_PIPE_BUF}, ~, ~, Str], # 223
  [Constant, {const_type: string, value: _POSIX_SSIZE_MAX}, ~, ~, Str], # 224
  [Constant, {const_type: string, value: _POSIX_STREAM_MAX}, ~, ~, Str], # 225
  [Constant, {const_type: string, value: _POSIX_TZNAME_MAX}, ~, ~, Str], # 226
  [ArrayLiteral, ~, [185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226], 183, ArrayRef], # 227
  [Constant, {const_type: string, value: locale_h}, ~, ~, Str], # 228
  [Constant, {const_type: string, value: LC_ALL}, ~, ~, Str], # 229
  [Constant, {const_type: string, value: LC_COLLATE}, ~, ~, Str], # 230
  [Constant, {const_type: string, value: LC_CTYPE}, ~, ~, Str], # 231
  [Constant, {const_type: string, value: LC_MESSAGES}, ~, ~, Str], # 232
  [Constant, {const_type: string, value: LC_MONETARY}, ~, ~, Str], # 233
  [Constant, {const_type: string, value: LC_NUMERIC}, ~, ~, Str], # 234
  [Constant, {const_type: string, value: LC_TIME}, ~, ~, Str], # 235
  [Constant, {const_type: string, value: LC_IDENTIFICATION}, ~, ~, Str], # 236
  [Constant, {const_type: string, value: LC_MEASUREMENT}, ~, ~, Str], # 237
  [Constant, {const_type: string, value: LC_PAPER}, ~, ~, Str], # 238
  [Constant, {const_type: string, value: LC_TELEPHONE}, ~, ~, Str], # 239
  [Constant, {const_type: string, value: LC_ADDRESS}, ~, ~, Str], # 240
  [Constant, {const_type: string, value: LC_NAME}, ~, ~, Str], # 241
  [Constant, {const_type: string, value: LC_SYNTAX}, ~, ~, Str], # 242
  [Constant, {const_type: string, value: LC_TOD}, ~, ~, Str], # 243
  [Constant, {const_type: string, value: "NULL"}, ~, ~, Str], # 244
  [Constant, {const_type: string, value: localeconv}, ~, ~, Str], # 245
  [Constant, {const_type: string, value: setlocale}, ~, ~, Str], # 246
  [ArrayLiteral, ~, [229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246], 227, ArrayRef], # 247
  [Constant, {const_type: string, value: math_h}, ~, ~, Str], # 248
  [Constant, {const_type: string, value: FP_ILOGB0}, ~, ~, Str], # 249
  [Constant, {const_type: string, value: FP_ILOGBNAN}, ~, ~, Str], # 250
  [Constant, {const_type: string, value: FP_INFINITE}, ~, ~, Str], # 251
  [Constant, {const_type: string, value: FP_NAN}, ~, ~, Str], # 252
  [Constant, {const_type: string, value: FP_NORMAL}, ~, ~, Str], # 253
  [Constant, {const_type: string, value: FP_SUBNORMAL}, ~, ~, Str], # 254
  [Constant, {const_type: string, value: FP_ZERO}, ~, ~, Str], # 255
  [Constant, {const_type: string, value: M_1_PI}, ~, ~, Str], # 256
  [Constant, {const_type: string, value: M_2_PI}, ~, ~, Str], # 257
  [Constant, {const_type: string, value: M_2_SQRTPI}, ~, ~, Str], # 258
  [Constant, {const_type: string, value: M_E}, ~, ~, Str], # 259
  [Constant, {const_type: string, value: M_LN10}, ~, ~, Str], # 260
  [Constant, {const_type: string, value: M_LN2}, ~, ~, Str], # 261
  [Constant, {const_type: string, value: M_LOG10E}, ~, ~, Str], # 262
  [Constant, {const_type: string, value: M_LOG2E}, ~, ~, Str], # 263
  [Constant, {const_type: string, value: M_PI}, ~, ~, Str], # 264
  [Constant, {const_type: string, value: M_PI_2}, ~, ~, Str], # 265
  [Constant, {const_type: string, value: M_PI_4}, ~, ~, Str], # 266
  [Constant, {const_type: string, value: M_SQRT1_2}, ~, ~, Str], # 267
  [Constant, {const_type: string, value: M_SQRT2}, ~, ~, Str], # 268
  [Constant, {const_type: string, value: HUGE_VAL}, ~, ~, Str], # 269
  [Constant, {const_type: string, value: INFINITY}, ~, ~, Str], # 270
  [Constant, {const_type: string, value: NAN}, ~, ~, Str], # 271
  [Constant, {const_type: string, value: acos}, ~, ~, Str], # 272
  [Constant, {const_type: string, value: asin}, ~, ~, Str], # 273
  [Constant, {const_type: string, value: atan}, ~, ~, Str], # 274
  [Constant, {const_type: string, value: ceil}, ~, ~, Str], # 275
  [Constant, {const_type: string, value: cosh}, ~, ~, Str], # 276
  [Constant, {const_type: string, value: fabs}, ~, ~, Str], # 277
  [Constant, {const_type: string, value: floor}, ~, ~, Str], # 278
  [Constant, {const_type: string, value: fmod}, ~, ~, Str], # 279
  [Constant, {const_type: string, value: frexp}, ~, ~, Str], # 280
  [Constant, {const_type: string, value: ldexp}, ~, ~, Str], # 281
  [Constant, {const_type: string, value: log10}, ~, ~, Str], # 282
  [Constant, {const_type: string, value: modf}, ~, ~, Str], # 283
  [Constant, {const_type: string, value: pow}, ~, ~, Str], # 284
  [Constant, {const_type: string, value: sinh}, ~, ~, Str], # 285
  [Constant, {const_type: string, value: tan}, ~, ~, Str], # 286
  [Constant, {const_type: string, value: tanh}, ~, ~, Str], # 287
  [ArrayLiteral, ~, [249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287], 247, ArrayRef], # 288
  [Constant, {const_type: string, value: pwd_h}, ~, ~, Str], # 289
  [ArrayLiteral, ~, ~, 288, ArrayRef], # 290
  [Constant, {const_type: string, value: setjmp_h}, ~, ~, Str], # 291
  [Constant, {const_type: string, value: longjmp}, ~, ~, Str], # 292
  [Constant, {const_type: string, value: setjmp}, ~, ~, Str], # 293
  [Constant, {const_type: string, value: siglongjmp}, ~, ~, Str], # 294
  [Constant, {const_type: string, value: sigsetjmp}, ~, ~, Str], # 295
  [ArrayLiteral, ~, [292, 293, 294, 295], 290, ArrayRef], # 296
  [Constant, {const_type: string, value: signal_h}, ~, ~, Str], # 297
  [Constant, {const_type: string, value: SA_NOCLDSTOP}, ~, ~, Str], # 298
  [Constant, {const_type: string, value: SA_NOCLDWAIT}, ~, ~, Str], # 299
  [Constant, {const_type: string, value: SA_NODEFER}, ~, ~, Str], # 300
  [Constant, {const_type: string, value: SA_ONSTACK}, ~, ~, Str], # 301
  [Constant, {const_type: string, value: SA_RESETHAND}, ~, ~, Str], # 302
  [Constant, {const_type: string, value: SA_RESTART}, ~, ~, Str], # 303
  [Constant, {const_type: string, value: SA_SIGINFO}, ~, ~, Str], # 304
  [Constant, {const_type: string, value: SIGABRT}, ~, ~, Str], # 305
  [Constant, {const_type: string, value: SIGALRM}, ~, ~, Str], # 306
  [Constant, {const_type: string, value: SIGCHLD}, ~, ~, Str], # 307
  [Constant, {const_type: string, value: SIGCONT}, ~, ~, Str], # 308
  [Constant, {const_type: string, value: SIGFPE}, ~, ~, Str], # 309
  [Constant, {const_type: string, value: SIGHUP}, ~, ~, Str], # 310
  [Constant, {const_type: string, value: SIGILL}, ~, ~, Str], # 311
  [Constant, {const_type: string, value: SIGINT}, ~, ~, Str], # 312
  [Constant, {const_type: string, value: SIGKILL}, ~, ~, Str], # 313
  [Constant, {const_type: string, value: SIGPIPE}, ~, ~, Str], # 314
  [Constant, {const_type: string, value: "%SIGRT"}, ~, ~, Str], # 315
  [Constant, {const_type: string, value: SIGRTMIN}, ~, ~, Str], # 316
  [Constant, {const_type: string, value: SIGRTMAX}, ~, ~, Str], # 317
  [Constant, {const_type: string, value: SIGQUIT}, ~, ~, Str], # 318
  [Constant, {const_type: string, value: SIGSEGV}, ~, ~, Str], # 319
  [Constant, {const_type: string, value: SIGSTOP}, ~, ~, Str], # 320
  [Constant, {const_type: string, value: SIGTERM}, ~, ~, Str], # 321
  [Constant, {const_type: string, value: SIGTSTP}, ~, ~, Str], # 322
  [Constant, {const_type: string, value: SIGTTIN}, ~, ~, Str], # 323
  [Constant, {const_type: string, value: SIGTTOU}, ~, ~, Str], # 324
  [Constant, {const_type: string, value: SIGUSR1}, ~, ~, Str], # 325
  [Constant, {const_type: string, value: SIGUSR2}, ~, ~, Str], # 326
  [Constant, {const_type: string, value: SIGBUS}, ~, ~, Str], # 327
  [Constant, {const_type: string, value: SIGPOLL}, ~, ~, Str], # 328
  [Constant, {const_type: string, value: SIGPROF}, ~, ~, Str], # 329
  [Constant, {const_type: string, value: SIGSYS}, ~, ~, Str], # 330
  [Constant, {const_type: string, value: SIGTRAP}, ~, ~, Str], # 331
  [Constant, {const_type: string, value: SIGURG}, ~, ~, Str], # 332
  [Constant, {const_type: string, value: SIGVTALRM}, ~, ~, Str], # 333
  [Constant, {const_type: string, value: SIGXCPU}, ~, ~, Str], # 334
  [Constant, {const_type: string, value: SIGXFSZ}, ~, ~, Str], # 335
  [Constant, {const_type: string, value: SIG_BLOCK}, ~, ~, Str], # 336
  [Constant, {const_type: string, value: SIG_DFL}, ~, ~, Str], # 337
  [Constant, {const_type: string, value: SIG_ERR}, ~, ~, Str], # 338
  [Constant, {const_type: string, value: SIG_IGN}, ~, ~, Str], # 339
  [Constant, {const_type: string, value: SIG_SETMASK}, ~, ~, Str], # 340
  [Constant, {const_type: string, value: SIG_UNBLOCK}, ~, ~, Str], # 341
  [Constant, {const_type: string, value: raise}, ~, ~, Str], # 342
  [Constant, {const_type: string, value: sigaction}, ~, ~, Str], # 343
  [Constant, {const_type: string, value: signal}, ~, ~, Str], # 344
  [Constant, {const_type: string, value: sigpending}, ~, ~, Str], # 345
  [Constant, {const_type: string, value: sigprocmask}, ~, ~, Str], # 346
  [Constant, {const_type: string, value: sigsuspend}, ~, ~, Str], # 347
  [ArrayLiteral, ~, [298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347], 296, ArrayRef], # 348
  [Constant, {const_type: string, value: stdarg_h}, ~, ~, Str], # 349
  [ArrayLiteral, ~, ~, 348, ArrayRef], # 350
  [Constant, {const_type: string, value: stddef_h}, ~, ~, Str], # 351
  [Constant, {const_type: string, value: offsetof}, ~, ~, Str], # 352
  [ArrayLiteral, ~, [244, 352], 350, ArrayRef], # 353
  [Constant, {const_type: string, value: stdio_h}, ~, ~, Str], # 354
  [Constant, {const_type: string, value: BUFSIZ}, ~, ~, Str], # 355
  [Constant, {const_type: string, value: EOF}, ~, ~, Str], # 356
  [Constant, {const_type: string, value: FILENAME_MAX}, ~, ~, Str], # 357
  [Constant, {const_type: string, value: L_ctermid}, ~, ~, Str], # 358
  [Constant, {const_type: string, value: L_cuserid}, ~, ~, Str], # 359
  [Constant, {const_type: string, value: TMP_MAX}, ~, ~, Str], # 360
  [Constant, {const_type: string, value: stderr}, ~, ~, Str], # 361
  [Constant, {const_type: string, value: stdin}, ~, ~, Str], # 362
  [Constant, {const_type: string, value: stdout}, ~, ~, Str], # 363
  [Constant, {const_type: string, value: clearerr}, ~, ~, Str], # 364
  [Constant, {const_type: string, value: fclose}, ~, ~, Str], # 365
  [Constant, {const_type: string, value: fdopen}, ~, ~, Str], # 366
  [Constant, {const_type: string, value: feof}, ~, ~, Str], # 367
  [Constant, {const_type: string, value: ferror}, ~, ~, Str], # 368
  [Constant, {const_type: string, value: fflush}, ~, ~, Str], # 369
  [Constant, {const_type: string, value: fgetc}, ~, ~, Str], # 370
  [Constant, {const_type: string, value: fgetpos}, ~, ~, Str], # 371
  [Constant, {const_type: string, value: fgets}, ~, ~, Str], # 372
  [Constant, {const_type: string, value: fopen}, ~, ~, Str], # 373
  [Constant, {const_type: string, value: fprintf}, ~, ~, Str], # 374
  [Constant, {const_type: string, value: fputc}, ~, ~, Str], # 375
  [Constant, {const_type: string, value: fputs}, ~, ~, Str], # 376
  [Constant, {const_type: string, value: fread}, ~, ~, Str], # 377
  [Constant, {const_type: string, value: freopen}, ~, ~, Str], # 378
  [Constant, {const_type: string, value: fscanf}, ~, ~, Str], # 379
  [Constant, {const_type: string, value: fseek}, ~, ~, Str], # 380
  [Constant, {const_type: string, value: fsetpos}, ~, ~, Str], # 381
  [Constant, {const_type: string, value: ftell}, ~, ~, Str], # 382
  [Constant, {const_type: string, value: fwrite}, ~, ~, Str], # 383
  [Constant, {const_type: string, value: getchar}, ~, ~, Str], # 384
  [Constant, {const_type: string, value: gets}, ~, ~, Str], # 385
  [Constant, {const_type: string, value: perror}, ~, ~, Str], # 386
  [Constant, {const_type: string, value: putc}, ~, ~, Str], # 387
  [Constant, {const_type: string, value: putchar}, ~, ~, Str], # 388
  [Constant, {const_type: string, value: puts}, ~, ~, Str], # 389
  [Constant, {const_type: string, value: remove}, ~, ~, Str], # 390
  [Constant, {const_type: string, value: rewind}, ~, ~, Str], # 391
  [Constant, {const_type: string, value: scanf}, ~, ~, Str], # 392
  [Constant, {const_type: string, value: setbuf}, ~, ~, Str], # 393
  [Constant, {const_type: string, value: setvbuf}, ~, ~, Str], # 394
  [Constant, {const_type: string, value: sscanf}, ~, ~, Str], # 395
  [Constant, {const_type: string, value: tmpfile}, ~, ~, Str], # 396
  [Constant, {const_type: string, value: tmpnam}, ~, ~, Str], # 397
  [Constant, {const_type: string, value: ungetc}, ~, ~, Str], # 398
  [Constant, {const_type: string, value: vfprintf}, ~, ~, Str], # 399
  [Constant, {const_type: string, value: vprintf}, ~, ~, Str], # 400
  [Constant, {const_type: string, value: vsprintf}, ~, ~, Str], # 401
  [ArrayLiteral, ~, [355, 356, 357, 358, 359, 244, 129, 130, 131, 208, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400, 401], 353, ArrayRef], # 402
  [Constant, {const_type: string, value: stdlib_h}, ~, ~, Str], # 403
  [Constant, {const_type: string, value: EXIT_FAILURE}, ~, ~, Str], # 404
  [Constant, {const_type: string, value: EXIT_SUCCESS}, ~, ~, Str], # 405
  [Constant, {const_type: string, value: MB_CUR_MAX}, ~, ~, Str], # 406
  [Constant, {const_type: string, value: RAND_MAX}, ~, ~, Str], # 407
  [Constant, {const_type: string, value: abort}, ~, ~, Str], # 408
  [Constant, {const_type: string, value: atexit}, ~, ~, Str], # 409
  [Constant, {const_type: string, value: atof}, ~, ~, Str], # 410
  [Constant, {const_type: string, value: atoi}, ~, ~, Str], # 411
  [Constant, {const_type: string, value: atol}, ~, ~, Str], # 412
  [Constant, {const_type: string, value: bsearch}, ~, ~, Str], # 413
  [Constant, {const_type: string, value: calloc}, ~, ~, Str], # 414
  [Constant, {const_type: string, value: div}, ~, ~, Str], # 415
  [Constant, {const_type: string, value: free}, ~, ~, Str], # 416
  [Constant, {const_type: string, value: getenv}, ~, ~, Str], # 417
  [Constant, {const_type: string, value: labs}, ~, ~, Str], # 418
  [Constant, {const_type: string, value: ldiv}, ~, ~, Str], # 419
  [Constant, {const_type: string, value: malloc}, ~, ~, Str], # 420
  [Constant, {const_type: string, value: mblen}, ~, ~, Str], # 421
  [Constant, {const_type: string, value: mbstowcs}, ~, ~, Str], # 422
  [Constant, {const_type: string, value: mbtowc}, ~, ~, Str], # 423
  [Constant, {const_type: string, value: qsort}, ~, ~, Str], # 424
  [Constant, {const_type: string, value: realloc}, ~, ~, Str], # 425
  [Constant, {const_type: string, value: strtod}, ~, ~, Str], # 426
  [Constant, {const_type: string, value: strtol}, ~, ~, Str], # 427
  [Constant, {const_type: string, value: strtoul}, ~, ~, Str], # 428
  [Constant, {const_type: string, value: wcstombs}, ~, ~, Str], # 429
  [Constant, {const_type: string, value: wctomb}, ~, ~, Str], # 430
  [ArrayLiteral, ~, [404, 405, 406, 244, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430], 402, ArrayRef], # 431
  [Constant, {const_type: string, value: string_h}, ~, ~, Str], # 432
  [Constant, {const_type: string, value: memchr}, ~, ~, Str], # 433
  [Constant, {const_type: string, value: memcmp}, ~, ~, Str], # 434
  [Constant, {const_type: string, value: memcpy}, ~, ~, Str], # 435
  [Constant, {const_type: string, value: memmove}, ~, ~, Str], # 436
  [Constant, {const_type: string, value: memset}, ~, ~, Str], # 437
  [Constant, {const_type: string, value: strcat}, ~, ~, Str], # 438
  [Constant, {const_type: string, value: strchr}, ~, ~, Str], # 439
  [Constant, {const_type: string, value: strcmp}, ~, ~, Str], # 440
  [Constant, {const_type: string, value: strcoll}, ~, ~, Str], # 441
  [Constant, {const_type: string, value: strcpy}, ~, ~, Str], # 442
  [Constant, {const_type: string, value: strcspn}, ~, ~, Str], # 443
  [Constant, {const_type: string, value: strerror}, ~, ~, Str], # 444
  [Constant, {const_type: string, value: strlen}, ~, ~, Str], # 445
  [Constant, {const_type: string, value: strncat}, ~, ~, Str], # 446
  [Constant, {const_type: string, value: strncmp}, ~, ~, Str], # 447
  [Constant, {const_type: string, value: strncpy}, ~, ~, Str], # 448
  [Constant, {const_type: string, value: strpbrk}, ~, ~, Str], # 449
  [Constant, {const_type: string, value: strrchr}, ~, ~, Str], # 450
  [Constant, {const_type: string, value: strspn}, ~, ~, Str], # 451
  [Constant, {const_type: string, value: strstr}, ~, ~, Str], # 452
  [Constant, {const_type: string, value: strtok}, ~, ~, Str], # 453
  [Constant, {const_type: string, value: strxfrm}, ~, ~, Str], # 454
  [ArrayLiteral, ~, [244, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454], 431, ArrayRef], # 455
  [Constant, {const_type: string, value: sys_stat_h}, ~, ~, Str], # 456
  [Constant, {const_type: string, value: S_IXGRP}, ~, ~, Str], # 457
  [Constant, {const_type: string, value: S_IXOTH}, ~, ~, Str], # 458
  [Constant, {const_type: string, value: S_IXUSR}, ~, ~, Str], # 459
  [Constant, {const_type: string, value: fstat}, ~, ~, Str], # 460
  [Constant, {const_type: string, value: mkfifo}, ~, ~, Str], # 461
  [ArrayLiteral, ~, [132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 457, 458, 459, 460, 461], 455, ArrayRef], # 462
  [Constant, {const_type: string, value: sys_times_h}, ~, ~, Str], # 463
  [ArrayLiteral, ~, ~, 462, ArrayRef], # 464
  [Constant, {const_type: string, value: sys_types_h}, ~, ~, Str], # 465
  [ArrayLiteral, ~, ~, 464, ArrayRef], # 466
  [Constant, {const_type: string, value: sys_utsname_h}, ~, ~, Str], # 467
  [Constant, {const_type: string, value: uname}, ~, ~, Str], # 468
  [ArrayLiteral, ~, [468], 466, ArrayRef], # 469
  [Constant, {const_type: string, value: sys_wait_h}, ~, ~, Str], # 470
  [Constant, {const_type: string, value: WEXITSTATUS}, ~, ~, Str], # 471
  [Constant, {const_type: string, value: WIFEXITED}, ~, ~, Str], # 472
  [Constant, {const_type: string, value: WIFSIGNALED}, ~, ~, Str], # 473
  [Constant, {const_type: string, value: WIFSTOPPED}, ~, ~, Str], # 474
  [Constant, {const_type: string, value: WNOHANG}, ~, ~, Str], # 475
  [Constant, {const_type: string, value: WSTOPSIG}, ~, ~, Str], # 476
  [Constant, {const_type: string, value: WTERMSIG}, ~, ~, Str], # 477
  [Constant, {const_type: string, value: WUNTRACED}, ~, ~, Str], # 478
  [ArrayLiteral, ~, [471, 472, 473, 474, 475, 476, 477, 478], 469, ArrayRef], # 479
  [Constant, {const_type: string, value: termios_h}, ~, ~, Str], # 480
  [Constant, {const_type: string, value: B0}, ~, ~, Str], # 481
  [Constant, {const_type: string, value: B110}, ~, ~, Str], # 482
  [Constant, {const_type: string, value: B1200}, ~, ~, Str], # 483
  [Constant, {const_type: string, value: B134}, ~, ~, Str], # 484
  [Constant, {const_type: string, value: B150}, ~, ~, Str], # 485
  [Constant, {const_type: string, value: B1800}, ~, ~, Str], # 486
  [Constant, {const_type: string, value: B19200}, ~, ~, Str], # 487
  [Constant, {const_type: string, value: B200}, ~, ~, Str], # 488
  [Constant, {const_type: string, value: B2400}, ~, ~, Str], # 489
  [Constant, {const_type: string, value: B300}, ~, ~, Str], # 490
  [Constant, {const_type: string, value: B38400}, ~, ~, Str], # 491
  [Constant, {const_type: string, value: B4800}, ~, ~, Str], # 492
  [Constant, {const_type: string, value: B50}, ~, ~, Str], # 493
  [Constant, {const_type: string, value: B600}, ~, ~, Str], # 494
  [Constant, {const_type: string, value: B75}, ~, ~, Str], # 495
  [Constant, {const_type: string, value: B9600}, ~, ~, Str], # 496
  [Constant, {const_type: string, value: BRKINT}, ~, ~, Str], # 497
  [Constant, {const_type: string, value: CLOCAL}, ~, ~, Str], # 498
  [Constant, {const_type: string, value: CREAD}, ~, ~, Str], # 499
  [Constant, {const_type: string, value: CS5}, ~, ~, Str], # 500
  [Constant, {const_type: string, value: CS6}, ~, ~, Str], # 501
  [Constant, {const_type: string, value: CS7}, ~, ~, Str], # 502
  [Constant, {const_type: string, value: CS8}, ~, ~, Str], # 503
  [Constant, {const_type: string, value: CSIZE}, ~, ~, Str], # 504
  [Constant, {const_type: string, value: CSTOPB}, ~, ~, Str], # 505
  [Constant, {const_type: string, value: ECHO}, ~, ~, Str], # 506
  [Constant, {const_type: string, value: ECHOE}, ~, ~, Str], # 507
  [Constant, {const_type: string, value: ECHOK}, ~, ~, Str], # 508
  [Constant, {const_type: string, value: ECHONL}, ~, ~, Str], # 509
  [Constant, {const_type: string, value: HUPCL}, ~, ~, Str], # 510
  [Constant, {const_type: string, value: ICANON}, ~, ~, Str], # 511
  [Constant, {const_type: string, value: ICRNL}, ~, ~, Str], # 512
  [Constant, {const_type: string, value: IEXTEN}, ~, ~, Str], # 513
  [Constant, {const_type: string, value: IGNBRK}, ~, ~, Str], # 514
  [Constant, {const_type: string, value: IGNCR}, ~, ~, Str], # 515
  [Constant, {const_type: string, value: IGNPAR}, ~, ~, Str], # 516
  [Constant, {const_type: string, value: INLCR}, ~, ~, Str], # 517
  [Constant, {const_type: string, value: INPCK}, ~, ~, Str], # 518
  [Constant, {const_type: string, value: ISIG}, ~, ~, Str], # 519
  [Constant, {const_type: string, value: ISTRIP}, ~, ~, Str], # 520
  [Constant, {const_type: string, value: IXOFF}, ~, ~, Str], # 521
  [Constant, {const_type: string, value: IXON}, ~, ~, Str], # 522
  [Constant, {const_type: string, value: NCCS}, ~, ~, Str], # 523
  [Constant, {const_type: string, value: NOFLSH}, ~, ~, Str], # 524
  [Constant, {const_type: string, value: OPOST}, ~, ~, Str], # 525
  [Constant, {const_type: string, value: PARENB}, ~, ~, Str], # 526
  [Constant, {const_type: string, value: PARMRK}, ~, ~, Str], # 527
  [Constant, {const_type: string, value: PARODD}, ~, ~, Str], # 528
  [Constant, {const_type: string, value: TCIFLUSH}, ~, ~, Str], # 529
  [Constant, {const_type: string, value: TCIOFF}, ~, ~, Str], # 530
  [Constant, {const_type: string, value: TCIOFLUSH}, ~, ~, Str], # 531
  [Constant, {const_type: string, value: TCION}, ~, ~, Str], # 532
  [Constant, {const_type: string, value: TCOFLUSH}, ~, ~, Str], # 533
  [Constant, {const_type: string, value: TCOOFF}, ~, ~, Str], # 534
  [Constant, {const_type: string, value: TCOON}, ~, ~, Str], # 535
  [Constant, {const_type: string, value: TCSADRAIN}, ~, ~, Str], # 536
  [Constant, {const_type: string, value: TCSAFLUSH}, ~, ~, Str], # 537
  [Constant, {const_type: string, value: TCSANOW}, ~, ~, Str], # 538
  [Constant, {const_type: string, value: TOSTOP}, ~, ~, Str], # 539
  [Constant, {const_type: string, value: VEOF}, ~, ~, Str], # 540
  [Constant, {const_type: string, value: VEOL}, ~, ~, Str], # 541
  [Constant, {const_type: string, value: VERASE}, ~, ~, Str], # 542
  [Constant, {const_type: string, value: VINTR}, ~, ~, Str], # 543
  [Constant, {const_type: string, value: VKILL}, ~, ~, Str], # 544
  [Constant, {const_type: string, value: VMIN}, ~, ~, Str], # 545
  [Constant, {const_type: string, value: VQUIT}, ~, ~, Str], # 546
  [Constant, {const_type: string, value: VSTART}, ~, ~, Str], # 547
  [Constant, {const_type: string, value: VSTOP}, ~, ~, Str], # 548
  [Constant, {const_type: string, value: VSUSP}, ~, ~, Str], # 549
  [Constant, {const_type: string, value: VTIME}, ~, ~, Str], # 550
  [Constant, {const_type: string, value: cfgetispeed}, ~, ~, Str], # 551
  [Constant, {const_type: string, value: cfgetospeed}, ~, ~, Str], # 552
  [Constant, {const_type: string, value: cfsetispeed}, ~, ~, Str], # 553
  [Constant, {const_type: string, value: cfsetospeed}, ~, ~, Str], # 554
  [Constant, {const_type: string, value: tcdrain}, ~, ~, Str], # 555
  [Constant, {const_type: string, value: tcflow}, ~, ~, Str], # 556
  [Constant, {const_type: string, value: tcflush}, ~, ~, Str], # 557
  [Constant, {const_type: string, value: tcgetattr}, ~, ~, Str], # 558
  [Constant, {const_type: string, value: tcsendbreak}, ~, ~, Str], # 559
  [Constant, {const_type: string, value: tcsetattr}, ~, ~, Str], # 560
  [ArrayLiteral, ~, [481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560], 479, ArrayRef], # 561
  [Constant, {const_type: string, value: time_h}, ~, ~, Str], # 562
  [Constant, {const_type: string, value: CLK_TCK}, ~, ~, Str], # 563
  [Constant, {const_type: string, value: CLOCKS_PER_SEC}, ~, ~, Str], # 564
  [Constant, {const_type: string, value: asctime}, ~, ~, Str], # 565
  [Constant, {const_type: string, value: clock}, ~, ~, Str], # 566
  [Constant, {const_type: string, value: ctime}, ~, ~, Str], # 567
  [Constant, {const_type: string, value: difftime}, ~, ~, Str], # 568
  [Constant, {const_type: string, value: mktime}, ~, ~, Str], # 569
  [Constant, {const_type: string, value: strftime}, ~, ~, Str], # 570
  [Constant, {const_type: string, value: tzset}, ~, ~, Str], # 571
  [Constant, {const_type: string, value: tzname}, ~, ~, Str], # 572
  [ArrayLiteral, ~, [563, 564, 244, 565, 566, 567, 568, 569, 570, 571, 572], 561, ArrayRef], # 573
  [Constant, {const_type: string, value: unistd_h}, ~, ~, Str], # 574
  [Constant, {const_type: string, value: F_OK}, ~, ~, Str], # 575
  [Constant, {const_type: string, value: R_OK}, ~, ~, Str], # 576
  [Constant, {const_type: string, value: STDERR_FILENO}, ~, ~, Str], # 577
  [Constant, {const_type: string, value: STDIN_FILENO}, ~, ~, Str], # 578
  [Constant, {const_type: string, value: STDOUT_FILENO}, ~, ~, Str], # 579
  [Constant, {const_type: string, value: W_OK}, ~, ~, Str], # 580
  [Constant, {const_type: string, value: X_OK}, ~, ~, Str], # 581
  [Constant, {const_type: string, value: _PC_CHOWN_RESTRICTED}, ~, ~, Str], # 582
  [Constant, {const_type: string, value: _PC_LINK_MAX}, ~, ~, Str], # 583
  [Constant, {const_type: string, value: _PC_MAX_CANON}, ~, ~, Str], # 584
  [Constant, {const_type: string, value: _PC_MAX_INPUT}, ~, ~, Str], # 585
  [Constant, {const_type: string, value: _PC_NAME_MAX}, ~, ~, Str], # 586
  [Constant, {const_type: string, value: _PC_NO_TRUNC}, ~, ~, Str], # 587
  [Constant, {const_type: string, value: _PC_PATH_MAX}, ~, ~, Str], # 588
  [Constant, {const_type: string, value: _PC_PIPE_BUF}, ~, ~, Str], # 589
  [Constant, {const_type: string, value: _PC_VDISABLE}, ~, ~, Str], # 590
  [Constant, {const_type: string, value: _POSIX_CHOWN_RESTRICTED}, ~, ~, Str], # 591
  [Constant, {const_type: string, value: _POSIX_JOB_CONTROL}, ~, ~, Str], # 592
  [Constant, {const_type: string, value: _POSIX_NO_TRUNC}, ~, ~, Str], # 593
  [Constant, {const_type: string, value: _POSIX_SAVED_IDS}, ~, ~, Str], # 594
  [Constant, {const_type: string, value: _POSIX_VDISABLE}, ~, ~, Str], # 595
  [Constant, {const_type: string, value: _POSIX_VERSION}, ~, ~, Str], # 596
  [Constant, {const_type: string, value: _SC_ARG_MAX}, ~, ~, Str], # 597
  [Constant, {const_type: string, value: _SC_CHILD_MAX}, ~, ~, Str], # 598
  [Constant, {const_type: string, value: _SC_CLK_TCK}, ~, ~, Str], # 599
  [Constant, {const_type: string, value: _SC_JOB_CONTROL}, ~, ~, Str], # 600
  [Constant, {const_type: string, value: _SC_NGROUPS_MAX}, ~, ~, Str], # 601
  [Constant, {const_type: string, value: _SC_OPEN_MAX}, ~, ~, Str], # 602
  [Constant, {const_type: string, value: _SC_PAGESIZE}, ~, ~, Str], # 603
  [Constant, {const_type: string, value: _SC_SAVED_IDS}, ~, ~, Str], # 604
  [Constant, {const_type: string, value: _SC_STREAM_MAX}, ~, ~, Str], # 605
  [Constant, {const_type: string, value: _SC_TZNAME_MAX}, ~, ~, Str], # 606
  [Constant, {const_type: string, value: _SC_VERSION}, ~, ~, Str], # 607
  [Constant, {const_type: string, value: _exit}, ~, ~, Str], # 608
  [Constant, {const_type: string, value: access}, ~, ~, Str], # 609
  [Constant, {const_type: string, value: ctermid}, ~, ~, Str], # 610
  [Constant, {const_type: string, value: cuserid}, ~, ~, Str], # 611
  [Constant, {const_type: string, value: dup2}, ~, ~, Str], # 612
  [Constant, {const_type: string, value: dup}, ~, ~, Str], # 613
  [Constant, {const_type: string, value: execl}, ~, ~, Str], # 614
  [Constant, {const_type: string, value: execle}, ~, ~, Str], # 615
  [Constant, {const_type: string, value: execlp}, ~, ~, Str], # 616
  [Constant, {const_type: string, value: execv}, ~, ~, Str], # 617
  [Constant, {const_type: string, value: execve}, ~, ~, Str], # 618
  [Constant, {const_type: string, value: execvp}, ~, ~, Str], # 619
  [Constant, {const_type: string, value: fpathconf}, ~, ~, Str], # 620
  [Constant, {const_type: string, value: fsync}, ~, ~, Str], # 621
  [Constant, {const_type: string, value: getcwd}, ~, ~, Str], # 622
  [Constant, {const_type: string, value: getegid}, ~, ~, Str], # 623
  [Constant, {const_type: string, value: geteuid}, ~, ~, Str], # 624
  [Constant, {const_type: string, value: getgid}, ~, ~, Str], # 625
  [Constant, {const_type: string, value: getgroups}, ~, ~, Str], # 626
  [Constant, {const_type: string, value: getpid}, ~, ~, Str], # 627
  [Constant, {const_type: string, value: getuid}, ~, ~, Str], # 628
  [Constant, {const_type: string, value: isatty}, ~, ~, Str], # 629
  [Constant, {const_type: string, value: lseek}, ~, ~, Str], # 630
  [Constant, {const_type: string, value: pathconf}, ~, ~, Str], # 631
  [Constant, {const_type: string, value: pause}, ~, ~, Str], # 632
  [Constant, {const_type: string, value: setgid}, ~, ~, Str], # 633
  [Constant, {const_type: string, value: setpgid}, ~, ~, Str], # 634
  [Constant, {const_type: string, value: setsid}, ~, ~, Str], # 635
  [Constant, {const_type: string, value: setuid}, ~, ~, Str], # 636
  [Constant, {const_type: string, value: sysconf}, ~, ~, Str], # 637
  [Constant, {const_type: string, value: tcgetpgrp}, ~, ~, Str], # 638
  [Constant, {const_type: string, value: tcsetpgrp}, ~, ~, Str], # 639
  [Constant, {const_type: string, value: ttyname}, ~, ~, Str], # 640
  [ArrayLiteral, ~, [575, 244, 576, 129, 130, 131, 577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640], 573, ArrayRef], # 641
  [Constant, {const_type: string, value: utime_h}, ~, ~, Str], # 642
  [ArrayLiteral, ~, ~, 641, ArrayRef], # 643
  [HashLiteral, {sigil: "%", symbol: default_export_tags}, [3, 6, 7, 8, 9, 10, 11, 104, 105, 150, 151, 181, 182, 183, 184, 227, 228, 247, 248, 288, 289, 290, 291, 296, 297, 348, 349, 350, 351, 353, 354, 402, 403, 431, 432, 455, 456, 462, 463, 464, 465, 466, 467, 469, 470, 479, 480, 561, 562, 573, 574, 641, 642, 643], ~, Hash], # 644
  [Constant, {const_type: string, value: fenv_h}, ~, ~, Str], # 645
  [Constant, {const_type: string, value: FE_DOWNWARD}, ~, ~, Str], # 646
  [Constant, {const_type: string, value: FE_TONEAREST}, ~, ~, Str], # 647
  [Constant, {const_type: string, value: FE_TOWARDZERO}, ~, ~, Str], # 648
  [Constant, {const_type: string, value: FE_UPWARD}, ~, ~, Str], # 649
  [Constant, {const_type: string, value: fegetround}, ~, ~, Str], # 650
  [Constant, {const_type: string, value: fesetround}, ~, ~, Str], # 651
  [MemStart], # 652
  [EntryDef, {package: main, sigil: $, symbol: "\u000f"}, ~, ~, Scalar, 652], # 653
  [Coerce, {from_repr: Unknown, to_repr: Str}, [653], ~, Str], # 654
  [Constant, {const_type: string, value: MSWin32}, ~, ~, Str], # 655
  [StrEq, ~, [654, 655], ~, Boolean], # 656
  [If, ~, [643, 656], 643], # 657
  [Proj, {index: 1}, [657]], # 658
  [Constant, {const_type: string, value: winsock_h}, ~, ~, Str], # 659
  [Subscript, {kind: hash}, [644, 659], ~, Undef], # 660
  [Constant, {const_type: string, value: WSAEINTR}, ~, ~, Str], # 661
  [Constant, {const_type: string, value: WSAEBADF}, ~, ~, Str], # 662
  [Constant, {const_type: string, value: WSAEACCES}, ~, ~, Str], # 663
  [Constant, {const_type: string, value: WSAEFAULT}, ~, ~, Str], # 664
  [Constant, {const_type: string, value: WSAEINVAL}, ~, ~, Str], # 665
  [Constant, {const_type: string, value: WSAEMFILE}, ~, ~, Str], # 666
  [Constant, {const_type: string, value: WSAEWOULDBLOCK}, ~, ~, Str], # 667
  [Constant, {const_type: string, value: WSAEINPROGRESS}, ~, ~, Str], # 668
  [Constant, {const_type: string, value: WSAEALREADY}, ~, ~, Str], # 669
  [Constant, {const_type: string, value: WSAENOTSOCK}, ~, ~, Str], # 670
  [Constant, {const_type: string, value: WSAEDESTADDRREQ}, ~, ~, Str], # 671
  [Constant, {const_type: string, value: WSAEMSGSIZE}, ~, ~, Str], # 672
  [Constant, {const_type: string, value: WSAEPROTOTYPE}, ~, ~, Str], # 673
  [Constant, {const_type: string, value: WSAENOPROTOOPT}, ~, ~, Str], # 674
  [Constant, {const_type: string, value: WSAEPROTONOSUPPORT}, ~, ~, Str], # 675
  [Constant, {const_type: string, value: WSAESOCKTNOSUPPORT}, ~, ~, Str], # 676
  [Constant, {const_type: string, value: WSAEOPNOTSUPP}, ~, ~, Str], # 677
  [Constant, {const_type: string, value: WSAEPFNOSUPPORT}, ~, ~, Str], # 678
  [Constant, {const_type: string, value: WSAEAFNOSUPPORT}, ~, ~, Str], # 679
  [Constant, {const_type: string, value: WSAEADDRINUSE}, ~, ~, Str], # 680
  [Constant, {const_type: string, value: WSAEADDRNOTAVAIL}, ~, ~, Str], # 681
  [Constant, {const_type: string, value: WSAENETDOWN}, ~, ~, Str], # 682
  [Constant, {const_type: string, value: WSAENETUNREACH}, ~, ~, Str], # 683
  [Constant, {const_type: string, value: WSAENETRESET}, ~, ~, Str], # 684
  [Constant, {const_type: string, value: WSAECONNABORTED}, ~, ~, Str], # 685
  [Constant, {const_type: string, value: WSAECONNRESET}, ~, ~, Str], # 686
  [Constant, {const_type: string, value: WSAENOBUFS}, ~, ~, Str], # 687
  [Constant, {const_type: string, value: WSAEISCONN}, ~, ~, Str], # 688
  [Constant, {const_type: string, value: WSAENOTCONN}, ~, ~, Str], # 689
  [Constant, {const_type: string, value: WSAESHUTDOWN}, ~, ~, Str], # 690
  [Constant, {const_type: string, value: WSAETOOMANYREFS}, ~, ~, Str], # 691
  [Constant, {const_type: string, value: WSAETIMEDOUT}, ~, ~, Str], # 692
  [Constant, {const_type: string, value: WSAECONNREFUSED}, ~, ~, Str], # 693
  [Constant, {const_type: string, value: WSAELOOP}, ~, ~, Str], # 694
  [Constant, {const_type: string, value: WSAENAMETOOLONG}, ~, ~, Str], # 695
  [Constant, {const_type: string, value: WSAEHOSTDOWN}, ~, ~, Str], # 696
  [Constant, {const_type: string, value: WSAEHOSTUNREACH}, ~, ~, Str], # 697
  [Constant, {const_type: string, value: WSAENOTEMPTY}, ~, ~, Str], # 698
  [Constant, {const_type: string, value: WSAEPROCLIM}, ~, ~, Str], # 699
  [Constant, {const_type: string, value: WSAEUSERS}, ~, ~, Str], # 700
  [Constant, {const_type: string, value: WSAEDQUOT}, ~, ~, Str], # 701
  [Constant, {const_type: string, value: WSAESTALE}, ~, ~, Str], # 702
  [Constant, {const_type: string, value: WSAEREMOTE}, ~, ~, Str], # 703
  [Constant, {const_type: string, value: WSAEDISCON}, ~, ~, Str], # 704
  [Constant, {const_type: string, value: WSAENOMORE}, ~, ~, Str], # 705
  [Constant, {const_type: string, value: WSAECANCELLED}, ~, ~, Str], # 706
  [Constant, {const_type: string, value: WSAEINVALIDPROCTABLE}, ~, ~, Str], # 707
  [Constant, {const_type: string, value: WSAEINVALIDPROVIDER}, ~, ~, Str], # 708
  [Constant, {const_type: string, value: WSAEPROVIDERFAILEDINIT}, ~, ~, Str], # 709
  [Constant, {const_type: string, value: WSAEREFUSED}, ~, ~, Str], # 710
  [Proj, {index: 0}, [657]], # 711
  [ArrayLiteral, ~, [661, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 672, 673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688, 689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710], 711, ArrayRef], # 712
  [Assign, ~, [660, 712], 712, ArrayRef, 652, true], # 713
  [Region, {head: 657}, [658, 713]], # 714
  [ArrayLiteral, ~, [646, 647, 648, 649, 650, 651], 714, ArrayRef], # 715
  [Constant, {const_type: string, value: math_h_c99}, ~, ~, Str], # 716
  [Phi, {memory: true, predecessors: [658, 711], region: 714}, [652, 713], ~, Unknown], # 717
  [Subscript, {kind: hash}, [644, 248], ~, Scalar, 717], # 718
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 440, package: POSIX, sigil: "@", strict: true}, [718], 715, Array, 717, true], # 719
  [Constant, {const_type: string, value: Inf}, ~, ~, Str], # 720
  [Constant, {const_type: string, value: NaN}, ~, ~, Str], # 721
  [Constant, {const_type: string, value: acosh}, ~, ~, Str], # 722
  [Constant, {const_type: string, value: asinh}, ~, ~, Str], # 723
  [Constant, {const_type: string, value: atanh}, ~, ~, Str], # 724
  [Constant, {const_type: string, value: cbrt}, ~, ~, Str], # 725
  [Constant, {const_type: string, value: copysign}, ~, ~, Str], # 726
  [Constant, {const_type: string, value: erf}, ~, ~, Str], # 727
  [Constant, {const_type: string, value: erfc}, ~, ~, Str], # 728
  [Constant, {const_type: string, value: exp2}, ~, ~, Str], # 729
  [Constant, {const_type: string, value: expm1}, ~, ~, Str], # 730
  [Constant, {const_type: string, value: fdim}, ~, ~, Str], # 731
  [Constant, {const_type: string, value: fma}, ~, ~, Str], # 732
  [Constant, {const_type: string, value: fmax}, ~, ~, Str], # 733
  [Constant, {const_type: string, value: fmin}, ~, ~, Str], # 734
  [Constant, {const_type: string, value: fpclassify}, ~, ~, Str], # 735
  [Constant, {const_type: string, value: hypot}, ~, ~, Str], # 736
  [Constant, {const_type: string, value: ilogb}, ~, ~, Str], # 737
  [Constant, {const_type: string, value: isfinite}, ~, ~, Str], # 738
  [Constant, {const_type: string, value: isgreater}, ~, ~, Str], # 739
  [Constant, {const_type: string, value: isgreaterequal}, ~, ~, Str], # 740
  [Constant, {const_type: string, value: isinf}, ~, ~, Str], # 741
  [Constant, {const_type: string, value: isless}, ~, ~, Str], # 742
  [Constant, {const_type: string, value: islessequal}, ~, ~, Str], # 743
  [Constant, {const_type: string, value: islessgreater}, ~, ~, Str], # 744
  [Constant, {const_type: string, value: isnan}, ~, ~, Str], # 745
  [Constant, {const_type: string, value: isnormal}, ~, ~, Str], # 746
  [Constant, {const_type: string, value: isunordered}, ~, ~, Str], # 747
  [Constant, {const_type: string, value: j0}, ~, ~, Str], # 748
  [Constant, {const_type: string, value: j1}, ~, ~, Str], # 749
  [Constant, {const_type: string, value: jn}, ~, ~, Str], # 750
  [Constant, {const_type: string, value: lgamma}, ~, ~, Str], # 751
  [Constant, {const_type: string, value: log1p}, ~, ~, Str], # 752
  [Constant, {const_type: string, value: log2}, ~, ~, Str], # 753
  [Constant, {const_type: string, value: logb}, ~, ~, Str], # 754
  [Constant, {const_type: string, value: lrint}, ~, ~, Str], # 755
  [Constant, {const_type: string, value: lround}, ~, ~, Str], # 756
  [Constant, {const_type: string, value: nan}, ~, ~, Str], # 757
  [Constant, {const_type: string, value: nearbyint}, ~, ~, Str], # 758
  [Constant, {const_type: string, value: nextafter}, ~, ~, Str], # 759
  [Constant, {const_type: string, value: nexttoward}, ~, ~, Str], # 760
  [Constant, {const_type: string, value: remainder}, ~, ~, Str], # 761
  [Constant, {const_type: string, value: remquo}, ~, ~, Str], # 762
  [Constant, {const_type: string, value: rint}, ~, ~, Str], # 763
  [Constant, {const_type: string, value: round}, ~, ~, Str], # 764
  [Constant, {const_type: string, value: scalbn}, ~, ~, Str], # 765
  [Constant, {const_type: string, value: signbit}, ~, ~, Str], # 766
  [Constant, {const_type: string, value: tgamma}, ~, ~, Str], # 767
  [Constant, {const_type: string, value: trunc}, ~, ~, Str], # 768
  [Constant, {const_type: string, value: y0}, ~, ~, Str], # 769
  [Constant, {const_type: string, value: y1}, ~, ~, Str], # 770
  [Constant, {const_type: string, value: yn}, ~, ~, Str], # 771
  [ArrayLiteral, ~, [719, 720, 721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736, 737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752, 753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768, 769, 770, 771], 719, ArrayRef], # 772
  [Constant, {const_type: string, value: netdb_h}, ~, ~, Str], # 773
  [Constant, {const_type: string, value: EAI_AGAIN}, ~, ~, Str], # 774
  [Constant, {const_type: string, value: EAI_BADFLAGS}, ~, ~, Str], # 775
  [Constant, {const_type: string, value: EAI_FAIL}, ~, ~, Str], # 776
  [Constant, {const_type: string, value: EAI_FAMILY}, ~, ~, Str], # 777
  [Constant, {const_type: string, value: EAI_MEMORY}, ~, ~, Str], # 778
  [Constant, {const_type: string, value: EAI_NONAME}, ~, ~, Str], # 779
  [Constant, {const_type: string, value: EAI_OVERFLOW}, ~, ~, Str], # 780
  [Constant, {const_type: string, value: EAI_SERVICE}, ~, ~, Str], # 781
  [Constant, {const_type: string, value: EAI_SOCKTYPE}, ~, ~, Str], # 782
  [Constant, {const_type: string, value: EAI_SYSTEM}, ~, ~, Str], # 783
  [ArrayLiteral, ~, [774, 775, 776, 777, 778, 779, 780, 781, 782, 783], 772, ArrayRef], # 784
  [Constant, {const_type: string, value: stdlib_h_c99}, ~, ~, Str], # 785
  [Subscript, {kind: hash}, [644, 403], ~, Scalar, 719], # 786
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 440, package: POSIX, sigil: "@", strict: true}, [786], 784, Array, 719, true], # 787
  [Constant, {const_type: string, value: strtold}, ~, ~, Str], # 788
  [ArrayLiteral, ~, [787, 788], 787, ArrayRef], # 789
  [Constant, {const_type: string, value: sys_resource_h}, ~, ~, Str], # 790
  [Constant, {const_type: string, value: PRIO_PROCESS}, ~, ~, Str], # 791
  [Constant, {const_type: string, value: PRIO_PGRP}, ~, ~, Str], # 792
  [Constant, {const_type: string, value: PRIO_USER}, ~, ~, Str], # 793
  [ArrayLiteral, ~, [791, 792, 793], 789, ArrayRef], # 794
  [Constant, {const_type: string, value: sys_socket_h}, ~, ~, Str], # 795
  [Constant, {const_type: string, value: MSG_CTRUNC}, ~, ~, Str], # 796
  [Constant, {const_type: string, value: MSG_DONTROUTE}, ~, ~, Str], # 797
  [Constant, {const_type: string, value: MSG_EOR}, ~, ~, Str], # 798
  [Constant, {const_type: string, value: MSG_OOB}, ~, ~, Str], # 799
  [Constant, {const_type: string, value: MSG_PEEK}, ~, ~, Str], # 800
  [Constant, {const_type: string, value: MSG_TRUNC}, ~, ~, Str], # 801
  [Constant, {const_type: string, value: MSG_WAITALL}, ~, ~, Str], # 802
  [ArrayLiteral, ~, [796, 797, 798, 799, 800, 801, 802], 794, ArrayRef], # 803
  [Constant, {const_type: string, value: nan_payload}, ~, ~, Str], # 804
  [Constant, {const_type: string, value: getpayload}, ~, ~, Str], # 805
  [Constant, {const_type: string, value: setpayload}, ~, ~, Str], # 806
  [Constant, {const_type: string, value: setpayloadsig}, ~, ~, Str], # 807
  [Constant, {const_type: string, value: issignaling}, ~, ~, Str], # 808
  [ArrayLiteral, ~, [805, 806, 807, 808], 803, ArrayRef], # 809
  [Constant, {const_type: string, value: signal_h_si_code}, ~, ~, Str], # 810
  [Constant, {const_type: string, value: ILL_ILLOPC}, ~, ~, Str], # 811
  [Constant, {const_type: string, value: ILL_ILLOPN}, ~, ~, Str], # 812
  [Constant, {const_type: string, value: ILL_ILLADR}, ~, ~, Str], # 813
  [Constant, {const_type: string, value: ILL_ILLTRP}, ~, ~, Str], # 814
  [Constant, {const_type: string, value: ILL_PRVOPC}, ~, ~, Str], # 815
  [Constant, {const_type: string, value: ILL_PRVREG}, ~, ~, Str], # 816
  [Constant, {const_type: string, value: ILL_COPROC}, ~, ~, Str], # 817
  [Constant, {const_type: string, value: ILL_BADSTK}, ~, ~, Str], # 818
  [Constant, {const_type: string, value: FPE_INTDIV}, ~, ~, Str], # 819
  [Constant, {const_type: string, value: FPE_INTOVF}, ~, ~, Str], # 820
  [Constant, {const_type: string, value: FPE_FLTDIV}, ~, ~, Str], # 821
  [Constant, {const_type: string, value: FPE_FLTOVF}, ~, ~, Str], # 822
  [Constant, {const_type: string, value: FPE_FLTUND}, ~, ~, Str], # 823
  [Constant, {const_type: string, value: FPE_FLTRES}, ~, ~, Str], # 824
  [Constant, {const_type: string, value: FPE_FLTINV}, ~, ~, Str], # 825
  [Constant, {const_type: string, value: FPE_FLTSUB}, ~, ~, Str], # 826
  [Constant, {const_type: string, value: SEGV_MAPERR}, ~, ~, Str], # 827
  [Constant, {const_type: string, value: SEGV_ACCERR}, ~, ~, Str], # 828
  [Constant, {const_type: string, value: BUS_ADRALN}, ~, ~, Str], # 829
  [Constant, {const_type: string, value: BUS_ADRERR}, ~, ~, Str], # 830
  [Constant, {const_type: string, value: BUS_OBJERR}, ~, ~, Str], # 831
  [Constant, {const_type: string, value: TRAP_BRKPT}, ~, ~, Str], # 832
  [Constant, {const_type: string, value: TRAP_TRACE}, ~, ~, Str], # 833
  [Constant, {const_type: string, value: CLD_EXITED}, ~, ~, Str], # 834
  [Constant, {const_type: string, value: CLD_KILLED}, ~, ~, Str], # 835
  [Constant, {const_type: string, value: CLD_DUMPED}, ~, ~, Str], # 836
  [Constant, {const_type: string, value: CLD_TRAPPED}, ~, ~, Str], # 837
  [Constant, {const_type: string, value: CLD_STOPPED}, ~, ~, Str], # 838
  [Constant, {const_type: string, value: CLD_CONTINUED}, ~, ~, Str], # 839
  [Constant, {const_type: string, value: POLL_IN}, ~, ~, Str], # 840
  [Constant, {const_type: string, value: POLL_OUT}, ~, ~, Str], # 841
  [Constant, {const_type: string, value: POLL_MSG}, ~, ~, Str], # 842
  [Constant, {const_type: string, value: POLL_ERR}, ~, ~, Str], # 843
  [Constant, {const_type: string, value: POLL_PRI}, ~, ~, Str], # 844
  [Constant, {const_type: string, value: POLL_HUP}, ~, ~, Str], # 845
  [Constant, {const_type: string, value: SI_USER}, ~, ~, Str], # 846
  [Constant, {const_type: string, value: SI_QUEUE}, ~, ~, Str], # 847
  [Constant, {const_type: string, value: SI_TIMER}, ~, ~, Str], # 848
  [Constant, {const_type: string, value: SI_ASYNCIO}, ~, ~, Str], # 849
  [Constant, {const_type: string, value: SI_MESGQ}, ~, ~, Str], # 850
  [ArrayLiteral, ~, [811, 812, 813, 814, 815, 816, 817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832, 833, 834, 835, 836, 837, 838, 839, 840, 841, 842, 843, 844, 845, 846, 847, 848, 849, 850], 809, ArrayRef], # 851
  [HashLiteral, {sigil: "%", symbol: other_export_tags}, [645, 715, 716, 772, 773, 784, 785, 789, 790, 794, 795, 803, 804, 809, 810, 851], ~, Hash], # 852
  [HashLiteral, {sigil: "%", symbol: "%POSIX::EXPORT_TAGS"}, [644, 852], ~, Hash], # 853
  [EntryDef, {package: POSIX, sigil: "@", symbol: EXPORT_OK}, ~, ~, Array], # 854
  [Constant, {const_type: string, value: close}, ~, ~, Str], # 855
  [Constant, {const_type: string, value: lchown}, ~, ~, Str], # 856
  [Constant, {const_type: string, value: nice}, ~, ~, Str], # 857
  [Constant, {const_type: string, value: open}, ~, ~, Str], # 858
  [Constant, {const_type: string, value: pipe}, ~, ~, Str], # 859
  [Constant, {const_type: string, value: read}, ~, ~, Str], # 860
  [Constant, {const_type: string, value: sleep}, ~, ~, Str], # 861
  [Constant, {const_type: string, value: times}, ~, ~, Str], # 862
  [Constant, {const_type: string, value: write}, ~, ~, Str], # 863
  [Constant, {const_type: string, value: printf}, ~, ~, Str], # 864
  [Constant, {const_type: string, value: sprintf}, ~, ~, Str], # 865
  [ArrayLiteral, ~, ~, ~, Array], # 866
  [EntryDef, {package: POSIX, sigil: "@", symbol: EXPORT}, ~, ~, Array], # 867
  [PadAccess, {sigil: "%", symbol: export}, ~, ~, Hash], # 868
  [ArrayLiteral, ~, ~, ~, Array], # 869
  [ArrayLiteral, ~, ~, ~, Array], # 870
  [Loop, {bound: entry}, [851], 851], # 871
  [Phi, {region: 871}, [870, 921], ~, Array], # 872
  [Slice, {kind: hash}, [872, 868], ~, List], # 873
  [Proj, {index: 1}, [871]], # 874
  [Region, {head: 871}, [874]], # 875
  [Phi, {memory: true, region: 871}, [787, 907], ~, Array], # 876
  [Phi, {memory: true, region: 875}, [876], ~, Array], # 877
  [Assign, {targets: 1}, [873], 875, Unknown, 877, true], # 878
  [Loop, {bound: entry}, [878], 878], # 879
  [Phi, {region: 879}, [869, 935], ~, Array], # 880
  [PadAccess, {sigil: "%", symbol: export_ok}, ~, ~, Hash], # 881
  [Slice, {kind: hash}, [880, 881], ~, List], # 882
  [Proj, {index: 1}, [879]], # 883
  [Region, {head: 879}, [883]], # 884
  [Phi, {memory: true, region: 879}, [878, 932], ~, Unknown], # 885
  [Phi, {memory: true, region: 884}, [885], ~, Unknown], # 886
  [Assign, {targets: 1}, [882], 884, Unknown, 886, true], # 887
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [868], ~, List, 887], # 888
  [EntryWrite, ~, [867, 888], 887, Unknown, 887, true], # 889
  [Loop, {bound: entry}, [889], 889], # 890
  [Phi, {region: 890}, [866, 927], ~, Array], # 891
  [ArrayLiteral, {sigil: "@", symbol: "@POSIX::EXPORT_OK"}, [855, 856, 857, 858, 859, 860, 861, 862, 863, 864, 865, 891], ~, Array], # 892
  [Proj, {index: 1}, [890]], # 893
  [Region, {head: 890}, [893]], # 894
  [EntryWrite, ~, [854, 892], 894, Unknown, 889, true], # 895
  [EntryWrite, ~, [2, 853], 895, Unknown, 895, true], # 896
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 896, Unknown, 896, true], # 897
  [Return, {implicit: true}, [897], 897, ~, 897], # 898
  [Call, {dispatch_kind: builtin, name: values, param_names: [], want: list}, [644], ~, List, 787], # 899
  [Count, ~, [899], ~, Int, 787], # 900
  [Count, ~, [899], ~, Int, 876], # 901
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 902
  [Phi, {region: 871}, [902, 920], ~, Int], # 903
  [Subscript, {kind: array}, [899, 903], ~, Scalar, 876], # 904
  [NumGt, ~, [901, 903], 871, Boolean], # 905
  [Proj, {index: 0}, [871]], # 906
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 471, package: POSIX, sigil: "@", strict: true}, [904], 906, Array, 876, true], # 907
  [Call, {dispatch_kind: builtin, name: values, param_names: [], want: list}, [852], ~, List, 878], # 908
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: reimpl}, ~, ~, Hash], # 909
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [909], ~, List, 889], # 910
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: replacement}, ~, ~, Hash], # 911
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [911], ~, List, 889], # 912
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [881], ~, List, 889], # 913
  [ArrayLiteral, ~, [910, 912, 913], ~, List], # 914
  [Count, ~, [914], ~, Int, 889], # 915
  [Phi, {region: 890}, [902, 933], ~, Int], # 916
  [Subscript, {kind: array}, [914, 916], ~, Scalar, 889], # 917
  [Exists, {kind: hash}, [868, 917], ~, Boolean, 889], # 918
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 919
  [Add, ~, [903, 919], ~, Int], # 920
  [ListAppend, {collector: map}, [872, 907], ~, Array], # 921
  [Count, ~, [908], ~, Int, 878], # 922
  [Count, ~, [908], ~, Int, 885], # 923
  [Phi, {region: 879}, [902, 934], ~, Int], # 924
  [Subscript, {kind: array}, [908, 924], ~, Scalar, 885], # 925
  [Not, ~, [918], ~, Boolean], # 926
  [ListAppend, {collector: grep}, [891, 917, 926], ~, Array], # 927
  [NumGt, ~, [915, 916], 890, Boolean], # 928
  [Proj, {index: 0}, [890]], # 929
  [NumGt, ~, [923, 924], 879, Boolean], # 930
  [Proj, {index: 0}, [879]], # 931
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 472, package: POSIX, sigil: "@", strict: true}, [925], 931, Array, 885, true], # 932
  [Add, ~, [916, 919], ~, Int], # 933
  [Add, ~, [924, 919], ~, Int], # 934
  [ListAppend, {collector: map}, [880, 932], ~, Array]]} # 935
POSIX::perror: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: glob, value: STDERR}, ~, ~, Glob], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "!"}, ~, ~, Scalar, 2], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [If, ~, [0, 6], 0], # 7
  [Proj, {index: 1}, [7]], # 8
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 2], # 9
  [Coerce, {from_repr: Scalar, to_repr: Str}, [9], ~, Str], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [10, 6], ~, Str, 2], # 11
  [Constant, {const_type: string, value: ": "}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Proj, {index: 0}, [7]], # 14
  [Print, {has_filehandle: true}, [1, 13], 14, "Maybe[Boolean]"], # 15
  [Region, {head: 7}, [8, 15]], # 16
  [Print, {has_filehandle: true}, [1, 4, 5], 16, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [17], 17, ~, 2]]} # 18
POSIX::printf: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: glob, value: STDOUT}, ~, ~, Glob], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Coerce, {from_repr: Array, to_repr: Num}, [2], ~, Num], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [NumLt, ~, [3, 4], ~, Boolean], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 1}, [6]], # 7
  [Constant, {const_type: string, value: "printf(pattern, args...)"}, ~, ~, Str], # 8
  [Proj, {index: 0}, [6]], # 9
  [MemStart], # 10
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 241, name: POSIX::usage, package: POSIX, param_names: [], want: void}, [8], 9, Unknown, 10, true], # 11
  [Region, {head: 6}, [7, 11]], # 12
  [Phi, {memory: true, predecessors: [7, 9], region: 12}, [10, 11], ~, Unknown], # 13
  [Call, {dispatch_kind: builtin, name: prtf, param_names: []}, [1, 2], 12, Scalar, 13], # 14
  [Return, {implicit: true}, [14], 14, ~, 13]]} # 15
POSIX::sprintf: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Coerce, {from_repr: Array, to_repr: Num}, [1], ~, Num], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [NumEq, ~, [2, 3], ~, Boolean], # 4
  [If, ~, [0, 4], 0], # 5
  [Proj, {index: 1}, [5]], # 6
  [Constant, {const_type: string, value: "sprintf(pattern, args...)"}, ~, ~, Str], # 7
  [Proj, {index: 0}, [5]], # 8
  [MemStart], # 9
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 246, name: POSIX::usage, package: POSIX, param_names: [], want: void}, [7], 8, Unknown, 9, true], # 10
  [Region, {head: 5}, [6, 10]], # 11
  [Phi, {memory: true, predecessors: [6, 8], region: 11}, [9, 10], ~, Unknown], # 12
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 11, Scalar, 12, true], # 13
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [13, 1], ~, Str, 13], # 14
  [Return, {implicit: true}, [14], 13, ~, 13]]} # 15
POSIX::unimplemented_message: {start: 0, returns: [47], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "C-specific, stopped"}, ~, ~, Str], # 1
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: replacement}, ~, ~, Hash], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [3], 0, Scalar, 4, true], # 5
  [Subscript, {kind: hash}, [2, 5], ~, Scalar, 5], # 6
  [Defined, ~, [6], ~, Boolean], # 7
  [Not, ~, [7], ~, Boolean], # 8
  [If, ~, [5, 8], 5], # 9
  [Proj, {index: 1}, [9]], # 10
  [RefType, ~, [6], ~, Str, 5], # 11
  [If, ~, [10, 11], 10], # 12
  [Proj, {index: 0}, [12]], # 13
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 201, package: POSIX, sigil: $, strict: true}, [6], 13, Scalar, 5, true], # 14
  [Coerce, {from_repr: Scalar, to_repr: Str}, [14], ~, Str], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 16
  [Constant, {const_type: string, value: " instead"}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [Constant, {const_type: string, value: "Use method "}, ~, ~, Str], # 19
  [Concat, ~, [19, 16], ~, Str], # 20
  [Constant, {const_type: string, value: "() instead"}, ~, ~, Str], # 21
  [Concat, ~, [20, 21], ~, Str], # 22
  [Constant, {const_type: string, value: "C-specific: use "}, ~, ~, Str], # 23
  [Concat, ~, [23, 16], ~, Str], # 24
  [Concat, ~, [24, 17], ~, Str], # 25
  [Proj, {index: 1}, [12]], # 26
  [Coerce, {from_repr: Scalar, to_repr: Str}, [6], ~, Str], # 27
  [RegexMatch, {flags: "", pattern: "^use "}, [27], ~, Boolean], # 28
  [If, ~, [26, 28], 26], # 29
  [Proj, {index: 1}, [29]], # 30
  [RegexMatch, {flags: "", pattern: "::"}, [27], ~, Boolean], # 31
  [If, ~, [30, 31], 30], # 32
  [Proj, {index: 0}, [32]], # 33
  [Proj, {index: 1}, [32]], # 34
  [Region, {head: 32}, [33, 34]], # 35
  [Phi, {predecessors: [33, 34], region: 35}, [22, 25], ~, Str], # 36
  [Proj, {index: 0}, [29]], # 37
  [Region, {head: 29}, [37, 35]], # 38
  [Phi, {predecessors: [37, 30], region: 38}, [18, 36], ~, Str], # 39
  [Region, {head: 12}, [14, 38]], # 40
  [Phi, {predecessors: [13, 26], region: 40}, [15, 39], ~, Str], # 41
  [Proj, {index: 0}, [9]], # 42
  [Region, {head: 9}, [42, 40]], # 43
  [Phi, {predecessors: [42, 10], region: 43}, [1, 41], ~, Str], # 44
  [Phi, {exits: true, memory: true, predecessors: [13, 26], region: 40}, [14, 5], ~, Scalar], # 45
  [Phi, {exits: true, memory: true, predecessors: [42, 10], region: 43}, [5, 45], ~, Scalar], # 46
  [Return, ~, [44], 43, ~, 46]]} # 47
POSIX::usage: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "Usage: POSIX::"}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 22, name: POSIX::croak, package: POSIX, param_names: []}, [7], 0, Unknown, 4, true], # 8
  [Return, {implicit: true}, [8], 8, ~, 8]]} # 9
Regexp::CARP_TRACE: {start: 0, returns: [54], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "qr("}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 2], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [4, 5], ~, Scalar, 2], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Assign, ~, [3, 7], 0, Str, 2, true], # 8
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 8], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 468, name: Carp::downgrade, package: Carp, param_names: [], want: void, xs: true}, [9, 10], 8, Unknown, 8, true], # 11
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 11], # 12
  [RegexSubst, {flags: g, pattern: "([^ !\"#\\$\\%\\&'()*+,\\-./0123456789:;<=>?\\@ABCDEFGHIJKLMNOPQRSTUVWXYZ\\[\\\\\\]^_`abcdefghijklmnopqrstuvwxyz\\{|}~])", replacement: "", replacement_body: Regexp::CARP_TRACE::__SUBSTREPL__:1}, [12], 11, Str, 11, true], # 13
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 13], # 14
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 480, name: Carp::downgrade, package: Carp, param_names: [], want: void, xs: true}, [14, 10], 13, Unknown, 13, true], # 15
  [PadAccess, {sigil: $, symbol: suffix}, ~, ~, Unknown], # 16
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Str, 15], # 17
  [RegexMatch, {flags: s, pattern: "\\A\\(\\?\\^?([a-z]*)(?:-[a-z]*)?:(.*)\\)\\z"}, [17], 15, Boolean], # 18
  [RegexCapture, {"n": 1}, [18], ~, Str], # 19
  [RegexCapture, {"n": 2}, [18], ~, Str], # 20
  [If, ~, [18, 18], 18], # 21
  [Proj, {index: 0}, [21]], # 22
  [Assign, {targets: 2}, [16, 17, 19, 20], 22, List, 15, true], # 23
  [Proj, {index: 1}, [21]], # 24
  [Region, {head: 21}, [24, 23]], # 25
  [Phi, {memory: true, predecessors: [24, 22], region: 25}, [15, 23], ~, Unknown], # 26
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Str, 26], # 27
  [EntryDef, {package: Carp, sigil: $, symbol: MaxArgLen}, ~, ~, Scalar, 26], # 28
  [Coerce, {from_repr: Scalar, to_repr: Num}, [28], ~, Num], # 29
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 30
  [Subtract, ~, [29, 30], ~, Num], # 31
  [Length, ~, [27], ~, Int], # 32
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 33
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 34
  [NumLt, ~, [34, 29], ~, Boolean], # 35
  [NumLt, ~, [29, 32], ~, Boolean], # 36
  [And, ~, [35, 36], ~, Boolean], # 37
  [If, ~, [25, 37], 25], # 38
  [Proj, {index: 0}, [38]], # 39
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [27, 31, 32, 33], 39, Str, 26, true], # 40
  [Proj, {index: 1}, [38]], # 41
  [Region, {head: 38}, [41, 40]], # 42
  [Phi, {memory: true, predecessors: [41, 39], region: 42}, [26, 40], ~, Unknown], # 43
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Str, 43], # 44
  [Coerce, {from_repr: Unknown, to_repr: Str}, [44], ~, Str], # 45
  [Concat, ~, [1, 45], ~, Str], # 46
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 47
  [Concat, ~, [46, 47], ~, Str], # 48
  [Phi, {predecessors: [24, 22], region: 25}, [33, 19], ~, Str], # 49
  [Constant, {const_type: string, value: "..."}, ~, ~, Str], # 50
  [Concat, ~, [50, 49], ~, Str], # 51
  [Phi, {predecessors: [41, 39], region: 42}, [49, 51], ~, Str], # 52
  [Concat, ~, [48, 52], ~, Str], # 53
  [Return, ~, [53], 42, ~, 43], # 54
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [27, 31], ~, Str]]} # 55
Regexp::CARP_TRACE::__SUBSTREPL__:1: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "\\x{%x}"}, ~, ~, Str], # 1
  [RegexMatch, {flags: g, pattern: "([^ !\"#\\$\\%\\&'()*+,\\-./0123456789:;<=>?\\@ABCDEFGHIJKLMNOPQRSTUVWXYZ\\[\\\\\\]^_`abcdefghijklmnopqrstuvwxyz\\{|}~])"}, ~, ~, Boolean], # 2
  [RegexCapture, {"n": 1}, [2], ~, Str], # 3
  [Call, {dispatch_kind: builtin, name: ord, param_names: []}, [3], ~, Int], # 4
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [1, 4], ~, Str], # 5
  [MemStart], # 6
  [Return, {implicit: true}, [5], 0, ~, 6]]} # 7
Tie::ExtraHash::CLEAR: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [3, 2], 0, Scalar, 4], # 5
  [HashLiteral, ~, ~, 5, HashRef], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Subscript, {kind: array}, [3, 2], ~, Scalar], # 8
  [Assign, ~, [8, 7], 6, Scalar, 4, true], # 9
  [PostfixDeref, {sigil: "%"}, [7], ~, Hash, 9], # 10
  [Assign, {targets: 1}, [10], 9, Unknown, 9, true], # 11
  [Return, {implicit: true}, [11], 11, ~, 11]]} # 12
Tie::ExtraHash::DELETE: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Subscript, {kind: array}, [3, 2], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Subscript, {kind: array}, [1, 5], ~, Scalar, 6], # 7
  [Delete, {kind: hash}, [4, 7], 0, Scalar, 6, true], # 8
  [Return, {implicit: true}, [8], 8, ~, 8]]} # 9
Tie::ExtraHash::EXISTS: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Subscript, {kind: array}, [3, 2], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Subscript, {kind: array}, [1, 5], ~, Scalar, 6], # 7
  [Exists, {kind: hash}, [4, 7], 0, Boolean, 6, true], # 8
  [Return, {implicit: true}, [8], 8, ~, 8]]} # 9
Tie::ExtraHash::FETCH: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Subscript, {kind: array}, [3, 2], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Subscript, {kind: array}, [1, 5], ~, Scalar, 6], # 7
  [Subscript, {kind: hash}, [4, 7], 0, Scalar, 6, true], # 8
  [Return, {implicit: true}, [8], 8, ~, 8]]} # 9
Tie::ExtraHash::FIRSTKEY: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [3, 2], 0, Scalar, 4], # 5
  [HashLiteral, ~, ~, 5, HashRef], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Subscript, {kind: array}, [3, 2], ~, Scalar], # 8
  [Assign, ~, [8, 7], 6, Scalar, 4, true], # 9
  [PostfixDeref, {sigil: "%"}, [7], 9, Hash, 9, true], # 10
  [Subscript, {kind: array}, [3, 2], 10, Scalar, 10], # 11
  [HashLiteral, ~, ~, 11, HashRef], # 12
  [DefinedOr, ~, [11, 12], ~, Scalar], # 13
  [Assign, ~, [8, 13], 12, Scalar, 10, true], # 14
  [PostfixDeref, {sigil: "%"}, [13], ~, Hash, 14], # 15
  [Call, {dispatch_kind: builtin, name: each, param_names: []}, [15], 14, Unknown, 14, true], # 16
  [Return, {implicit: true}, [16], 16, ~, 16], # 17
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: scalar}, [10], ~, Int, 10]]} # 18
Tie::ExtraHash::NEXTKEY: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [3, 2], 0, Scalar, 4], # 5
  [HashLiteral, ~, ~, 5, HashRef], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Subscript, {kind: array}, [3, 2], ~, Scalar], # 8
  [Assign, ~, [8, 7], 6, Scalar, 4, true], # 9
  [PostfixDeref, {sigil: "%"}, [7], ~, Hash, 9], # 10
  [Call, {dispatch_kind: builtin, name: each, param_names: []}, [10], 9, Unknown, 9, true], # 11
  [Return, {implicit: true}, [11], 11, ~, 11]]} # 12
Tie::ExtraHash::SCALAR: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [3, 2], 0, Scalar, 4, true], # 5
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 268, package: Tie::ExtraHash, sigil: "%", strict: false}, [5], 5, Hash, 5, true], # 6
  [Count, ~, [6], ~, Int, 6], # 7
  [Return, {implicit: true}, [7], 6, ~, 6]]} # 8
Tie::ExtraHash::STORE: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [1, 5], ~, Scalar], # 6
  [Subscript, {kind: array}, [6, 5], 0, Scalar, 3], # 7
  [HashLiteral, ~, ~, 7, HashRef], # 8
  [DefinedOr, ~, [7, 8], ~, Scalar], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [6, 5], ~, Scalar], # 11
  [Assign, ~, [11, 9], 8, Scalar, 3, true], # 12
  [Subscript, {kind: array}, [1, 10], ~, Scalar, 12], # 13
  [Subscript, {kind: hash}, [9, 13], ~, Scalar], # 14
  [Assign, ~, [14, 4], 12, Scalar, 12, true], # 15
  [Return, {implicit: true}, [4], 15, ~, 15]]} # 16
Tie::ExtraHash::TIEHASH: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [HashLiteral, ~, ~, 3, HashRef], # 4
  [ArrayLiteral, ~, [4, 1], 4, ArrayRef], # 5
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [5, 3], 5, Unknown, 3, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
Tie::Hash::CLEAR: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: boolean, value: ""}, ~, ~, Boolean], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 0, Scalar, 3, true], # 4
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 229, name: FIRSTKEY, package: Tie::Hash, param_names: [], want: scalar}, [4, 2], 4, Unknown, 4, true], # 5
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 5], # 6
  [Assign, ~, [6, 5], 5, Unknown, 5, true], # 7
  [Loop, {bound: each}, [7], 7], # 8
  [Proj, {index: 1}, [8]], # 9
  [Region, {head: 8}, [9]], # 10
  [Loop, {bound: entry}, [10], 10], # 11
  [Proj, {index: 1}, [11]], # 12
  [Region, {head: 11}, [12]], # 13
  [Phi, {memory: true, region: 8}, [7, 34], ~, Unknown], # 14
  [Phi, {memory: true, region: 10}, [14], ~, Unknown], # 15
  [Phi, {memory: true, region: 11}, [15, 37], ~, Unknown], # 16
  [Phi, {memory: true, region: 13}, [16], ~, Unknown], # 17
  [Return, {implicit: true}, [1], 13, ~, 17], # 18
  [PadAccess, {sigil: "@", symbol: keys}, ~, ~, Array], # 19
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 14], # 20
  [Proj, {index: 0}, [8]], # 21
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [19, 20], 21, Int, 14, true], # 22
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 22], # 23
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 234, name: NEXTKEY, package: Tie::Hash, param_names: [], want: scalar}, [4, 2, 23], 22, Unknown, 22, true], # 24
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 16], # 25
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 26
  [Phi, {region: 11}, [26, 43], ~, Int], # 27
  [Subscript, {kind: array}, [19, 27], ~, Scalar, 16], # 28
  [Proj, {index: 0}, [11]], # 29
  [Assign, ~, [25, 28], 29, Scalar, 16, true], # 30
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 30], # 31
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 237, name: DELETE, package: Tie::Hash, param_names: [], want: void}, [4, 2, 31], 30, Unknown, 30, true], # 32
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 24], # 33
  [Assign, ~, [33, 24], 24, Unknown, 24, true], # 34
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 32], # 35
  [Subscript, {kind: array}, [19, 27], ~, Scalar], # 36
  [Assign, {if_changed: true}, [36, 35], 32, Unknown, 32, true], # 37
  [Count, ~, [19], ~, Int, 16], # 38
  [NumGt, ~, [38, 27], 11, Boolean], # 39
  [Count, ~, [19], ~, Int, 15], # 40
  [Defined, ~, [20], 8, Boolean], # 41
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 42
  [Add, ~, [27, 42], ~, Int]]} # 43
Tie::Hash::EXISTS: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [RefType, ~, [4], ~, Str, 3], # 5
  [Constant, {const_type: string, value: " doesn't define an EXISTS method"}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 224, name: Carp::croak, package: Tie::Hash, param_names: []}, [7], 0, Undef, 3, true], # 8
  [Return, {implicit: true}, [8], 8, ~, 8]]} # 9
Tie::Hash::TIEHASH: {start: 0, returns: [38], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [Constant, {const_type: string, value: "WARNING: calling "}, ~, ~, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: "->new since "}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [Constant, {const_type: string, value: "->TIEHASH is missing"}, ~, ~, Str], # 9
  [Concat, ~, [5, 9], ~, Str], # 10
  [Concat, ~, [8, 10], ~, Str], # 11
  [Constant, {const_type: string, value: Tie::Hash}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: new}, ~, ~, Str], # 13
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 202, name: can, package: Tie::Hash, param_names: [], want: scalar}, [3, 13], 3, Unknown, 3, true], # 14
  [StrNe, ~, [5, 12], ~, Boolean], # 15
  [And, ~, [14, 15], ~, Unknown], # 16
  [If, ~, [14, 16], 14], # 17
  [Proj, {index: 0}, [17]], # 18
  [Call, {class_name: Tie::Hash, dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 205, name: can, package: Tie::Hash, param_names: [], want: scalar}, [12, 13], 18, Unknown, 14, true], # 19
  [NumEq, ~, [14, 19], ~, Boolean], # 20
  [If, ~, [19, 20], 19], # 21
  [Proj, {index: 1}, [21]], # 22
  [Constant, {const_type: string, value: " must define either a TIEHASH() or a new() method"}, ~, ~, Str], # 23
  [Concat, ~, [5, 23], ~, Str], # 24
  [Proj, {index: 0}, [21]], # 25
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 206, name: Carp::croak, package: Tie::Hash, param_names: [], want: void}, [24], 25, Undef, 19, true], # 26
  [Region, {head: 21}, [22, 26]], # 27
  [Phi, {memory: true, predecessors: [22, 25], region: 27}, [19, 26], ~, Unknown], # 28
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 213, name: warnings::warnif, package: Tie::Hash, param_names: [], want: void}, [11], 27, Unknown, 28, true], # 29
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 215, name: new, package: Tie::Hash, param_names: []}, [3, 1], 29, Unknown, 29, true], # 30
  [Constant, {const_type: string, value: " doesn't define a TIEHASH method"}, ~, ~, Str], # 31
  [Concat, ~, [5, 31], ~, Str], # 32
  [Proj, {index: 1}, [17]], # 33
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 218, name: Carp::croak, package: Tie::Hash, param_names: []}, [32], 33, Undef, 14, true], # 34
  [Region, {head: 17}, [30, 34]], # 35
  [Phi, {predecessors: [18, 33], region: 35}, [30, 34], ~, Unknown], # 36
  [Phi, {memory: true, predecessors: [18, 33], region: 35}, [30, 34], ~, Unknown], # 37
  [Return, {implicit: true}, [36], 35, ~, 37]]} # 38
Tie::Hash::new: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 195, name: TIEHASH, package: Tie::Hash, param_names: []}, [3, 1], 3, Unknown, 3, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
Tie::StdHash::CLEAR: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [PostfixDeref, {sigil: "%"}, [3], ~, Hash, 4], # 5
  [Assign, {targets: 1}, [5], 0, Unknown, 4, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
Tie::StdHash::DELETE: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [1, 4], ~, Scalar, 5], # 6
  [Delete, {kind: hash}, [3, 6], 0, Scalar, 5, true], # 7
  [Return, {implicit: true}, [7], 7, ~, 7]]} # 8
Tie::StdHash::EXISTS: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [1, 4], ~, Scalar, 5], # 6
  [Exists, {kind: hash}, [3, 6], 0, Boolean, 5, true], # 7
  [Return, {implicit: true}, [7], 7, ~, 7]]} # 8
Tie::StdHash::FETCH: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [1, 4], ~, Scalar, 5], # 6
  [Subscript, {kind: hash}, [3, 6], 0, Scalar, 5, true], # 7
  [Return, {implicit: true}, [7], 7, ~, 7]]} # 8
Tie::StdHash::FIRSTKEY: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [PostfixDeref, {sigil: "%"}, [3], 0, Hash, 4, true], # 5
  [PostfixDeref, {sigil: "%"}, [3], ~, Hash, 5], # 6
  [Call, {dispatch_kind: builtin, name: each, param_names: []}, [6], 5, Unknown, 5, true], # 7
  [Return, {implicit: true}, [7], 7, ~, 7], # 8
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: scalar}, [5], ~, Int, 5]]} # 9
Tie::StdHash::NEXTKEY: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [PostfixDeref, {sigil: "%"}, [3], ~, Hash, 4], # 5
  [Call, {dispatch_kind: builtin, name: each, param_names: []}, [5], 0, Unknown, 4, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
Tie::StdHash::SCALAR: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 256, package: Tie::StdHash, sigil: "%", strict: false}, [4], 0, Hash, 3, true], # 5
  [Count, ~, [5], ~, Int, 5], # 6
  [Return, {implicit: true}, [6], 5, ~, 5]]} # 7
Tie::StdHash::STORE: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [1, 5], ~, Scalar], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [1, 7], ~, Scalar, 3], # 8
  [Subscript, {kind: hash}, [6, 8], ~, Scalar], # 9
  [Assign, ~, [9, 4], 0, Scalar, 3, true], # 10
  [Return, {implicit: true}, [4], 10, ~, 10]]} # 11
Tie::StdHash::TIEHASH: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [HashLiteral, ~, ~, 0, HashRef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [1, 5], 1, Unknown, 4, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "floor imported: "}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "%", symbol: "main::"}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: floor}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash, stash_has: 1}, [3, 4], ~, Scalar, 5], # 6
  [Constant, {const_type: string, value: "yes"}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: "no"}, ~, ~, Str], # 8
  [TernaryExpr, ~, [6, 7, 8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: "POSIX loaded: "}, ~, ~, Str], # 11
  [EntryDef, {package: main, sigil: "%", symbol: INC}, ~, ~, Hash], # 12
  [Constant, {const_type: string, value: POSIX.pm}, ~, ~, Str], # 13
  [Subscript, {kind: hash}, [12, 13], ~, Scalar, 5], # 14
  [TernaryExpr, ~, [14, 7, 8], ~, Str], # 15
  [Print, ~, [11, 15, 10], 0, "Maybe[Boolean]"], # 16
  [Print, ~, [2, 9, 10], 16, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [1], 17, ~, 5]]} # 18
"BEGIN 1": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: POSIX}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: POSIX.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: POSIX, dispatch_kind: method, file: "/tmp/ucZOh245UI/case.pl", line: 1, name: import, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
```

## `use POSIX ();` loads the file and suppresses import

The empty parentheses are not an empty argument list but the absence of
one. Same module and the same two observations as the case above, one
statement apart:

    use POSIX;      loaded yes    imported yes
    use POSIX ();   loaded yes    imported no

The first column is `require`'s half of `use`, the second is `import`'s.
The two cases' op streams are byte-identical to each other and to the
two `print` statements alone, which is why the symbol table is where the
difference is visible at all. That is the tier's defining difficulty
stated as a measurement: `use` is real, and no optree records it.

A pragma could not stand in here, because a pragma's whole effect IS its
import and there would be nothing left to observe.

MEASURED perl 5.42.0:

    $ perl -e 'use POSIX (); print +($INC{"POSIX.pm"} ? "yes" : "no"), ($main::{"floor"} ? "yes" : "no"), "\n"'
    yesno

```perl
use POSIX ();
print "POSIX loaded: ", ($INC{"POSIX.pm"} ? "yes" : "no"), "\n";
print "floor imported: ", ($main::{"floor"} ? "yes" : "no"), "\n";
```

```behavior
parses: yes
```

```output
POSIX loaded: yes
floor imported: no
```

```ir
Carp::_cgc: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: code, value: CORE::GLOBAL::caller}, ~, ~, Code], # 1
  [Ref, ~, [1], ~, CodeRef], # 2
  [ArrayLiteral, ~, ~, ~, List], # 3
  [Constant, {const_type: string, value: CORE::GLOBAL::caller}, ~, ~, Str], # 4
  [Defined, ~, [4], ~, Boolean], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 0}, [6]], # 7
  [Proj, {index: 1}, [6]], # 8
  [Region, {head: 6}, [7, 8]], # 9
  [Phi, {predecessors: [7, 8], region: 9}, [2, 3], ~, List], # 10
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 11
  [Phi, {predecessors: [7, 8], region: 9}, [2, 11], ~, "Maybe[CodeRef]"], # 12
  [MemStart], # 13
  [Return, ~, [10, 12], 9, ~, 13]]} # 14
Carp::_fetch_sub: {start: 0, returns: [64], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [Constant, {const_type: boolean, value: ""}, ~, ~, Boolean], # 2
  [EntryDef, {package: main, sigil: "%", symbol: "main::"}, ~, ~, Hash], # 3
  [PadAccess, {sigil: $, symbol: pack}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "::"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [MemStart], # 7
  [Exists, {kind: hash}, [3, 6], ~, Boolean, 7], # 8
  [Not, ~, [8], ~, Boolean], # 9
  [If, ~, [0, 9], 0], # 10
  [Proj, {index: 0}, [10]], # 11
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 12
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar, 7], # 13
  [Proj, {index: 1}, [10]], # 14
  [Loop, {bound: entry}, [14], 14], # 15
  [Proj, {index: 1}, [15]], # 16
  [Region, {head: 15}, [16]], # 17
  [Phi, {memory: true, region: 15}, [7, 18], ~, Unknown], # 18
  [Phi, {memory: true, region: 17}, [18], ~, Unknown], # 19
  [EntryWrite, ~, [12, 13], 17, Unknown, 19, true], # 20
  [Region, {head: 10}, [11, 20]], # 21
  [Phi, {predecessors: [11, 14], region: 21}, [1, 2], ~, List], # 22
  [ArrayLiteral, ~, ~, ~, List], # 23
  [Subscript, {kind: hash}, [3, 6], ~, Scalar], # 24
  [ArrayLiteral, ~, [24], ~, Array], # 25
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 26
  [Phi, {region: 15}, [26, 73], ~, Int], # 27
  [Subscript, {kind: array}, [25, 27], ~, Scalar, 18], # 28
  [PadAccess, {sigil: $, symbol: sub}, ~, ~, Unknown], # 29
  [Subscript, {kind: hash}, [28, 29], ~, Scalar], # 30
  [ArrayLiteral, ~, [30], ~, Array], # 31
  [Proj, {index: 0}, [15]], # 32
  [Call, {dispatch_kind: builtin, name: reftype_of_ref, param_names: []}, [28], ~, Str, 18], # 33
  [Constant, {const_type: string, value: GLOB}, ~, ~, Str], # 34
  [StrEq, ~, [33, 34], ~, Boolean], # 35
  [Constant, {const_type: string, value: HASH}, ~, ~, Str], # 36
  [Subscript, ~, [28, 36], ~, Scalar, 18], # 37
  [And, ~, [35, 37], ~, Scalar], # 38
  [If, ~, [32, 38], 32], # 39
  [Proj, {index: 0}, [39]], # 40
  [Proj, {index: 1}, [39]], # 41
  [Region, {head: 39}, [40, 41]], # 42
  [Exists, {kind: hash}, [28, 29], ~, Boolean, 18], # 43
  [Phi, {predecessors: [40, 41], region: 42}, [43, 38], ~, Scalar], # 44
  [If, ~, [42, 44], 42], # 45
  [Proj, {index: 0}, [45]], # 46
  [Loop, {bound: entry}, [46], 46], # 47
  [Phi, {region: 47}, [26, 76], ~, Int], # 48
  [Subscript, {kind: array}, [31, 48], ~, Scalar, 18], # 49
  [Call, {dispatch_kind: builtin, name: reftype_of_ref, param_names: []}, [49], ~, Str, 18], # 50
  [StrEq, ~, [50, 34], ~, Boolean], # 51
  [Constant, {const_type: string, value: CODE}, ~, ~, Str], # 52
  [Subscript, ~, [49, 52], ~, Scalar, 18], # 53
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 54
  [TernaryExpr, ~, [51, 53, 54], ~, Unknown], # 55
  [Proj, {index: 1}, [45]], # 56
  [Proj, {index: 0}, [47]], # 57
  [Region, ~, [21, 56, 57]], # 58
  [Phi, {predecessors: [21, 56, 57], region: 58}, [22, 23, 55], ~, Unknown], # 59
  [Phi, {predecessors: [11, 14], region: 21}, [54, 2], ~, "Maybe[Boolean]"], # 60
  [Phi, {predecessors: [21, 56, 57], region: 58}, [60, 54, 55], ~, Unknown], # 61
  [Phi, {exits: true, memory: true, predecessors: [11, 14], region: 21}, [7, 20], ~, Unknown], # 62
  [Phi, {exits: true, memory: true, predecessors: [21, 56, 57], region: 58}, [62, 18, 18], ~, Unknown], # 63
  [Return, ~, [59, 61], 58, ~, 63], # 64
  [Count, ~, [25], ~, Int, 18], # 65
  [Count, ~, [31], ~, Int, 18], # 66
  [NumGt, ~, [65, 27], 15, Boolean], # 67
  [NumGt, ~, [66, 48], 47, Boolean], # 68
  [Proj, {index: 1}, [47]], # 69
  [Count, ~, [25], ~, Int, 7], # 70
  [Region, {head: 47}, [69]], # 71
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 72
  [Add, ~, [27, 72], ~, Int], # 73
  [ArgsSource, ~, ~, ~, Array], # 74
  [Assign, {record: true, targets: 2}, [4, 29, 74], ~, List], # 75
  [Add, ~, [48, 72], ~, Int]]} # 76
Carp::_univ_mod_loaded: {start: 0, returns: [89], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Constant, {const_type: boolean, value: ""}, ~, ~, Boolean], # 2
  [EntryDef, {package: main, sigil: "%", symbol: "main::"}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: "UNIVERSAL::"}, ~, ~, Str], # 4
  [MemStart], # 5
  [Exists, {kind: hash}, [3, 4], ~, Boolean, 5], # 6
  [Not, ~, [6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 10
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar, 5], # 11
  [Proj, {index: 1}, [8]], # 12
  [Loop, {bound: entry}, [12], 12], # 13
  [Proj, {index: 1}, [13]], # 14
  [Region, {head: 13}, [14]], # 15
  [Phi, {memory: true, region: 13}, [5, 93], ~, Unknown], # 16
  [Phi, {memory: true, region: 15}, [16], ~, Unknown], # 17
  [EntryWrite, ~, [10, 11], 15, Unknown, 17, true], # 18
  [Region, {head: 8}, [9, 18]], # 19
  [Phi, {predecessors: [9, 12], region: 19}, [1, 2], ~, Scalar], # 20
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 21
  [ArrayLiteral, ~, [21], ~, Array], # 22
  [Phi, {region: 13}, [1, 103], ~, Int], # 23
  [Subscript, {kind: array}, [22, 23], ~, Scalar, 16], # 24
  [ArgsSource, ~, ~, ~, Array], # 25
  [Subscript, {kind: array}, [25, 1], ~, Scalar, 16], # 26
  [Coerce, {from_repr: Unknown, to_repr: Str}, [26], ~, Str], # 27
  [Constant, {const_type: string, value: "::"}, ~, ~, Str], # 28
  [Concat, ~, [27, 28], ~, Str], # 29
  [Subscript, {kind: hash}, [24, 29], ~, Scalar], # 30
  [ArrayLiteral, ~, [30], ~, Array], # 31
  [Proj, {index: 0}, [13]], # 32
  [Call, {dispatch_kind: builtin, name: reftype_of_ref, param_names: []}, [24], ~, Str, 16], # 33
  [Constant, {const_type: string, value: GLOB}, ~, ~, Str], # 34
  [StrEq, ~, [33, 34], ~, Boolean], # 35
  [Constant, {const_type: string, value: HASH}, ~, ~, Str], # 36
  [Subscript, ~, [24, 36], ~, Scalar, 16], # 37
  [And, ~, [35, 37], ~, Scalar], # 38
  [If, ~, [32, 38], 32], # 39
  [Proj, {index: 0}, [39]], # 40
  [Proj, {index: 1}, [39]], # 41
  [Region, {head: 39}, [40, 41]], # 42
  [Exists, {kind: hash}, [24, 29], ~, Boolean, 16], # 43
  [Phi, {predecessors: [40, 41], region: 42}, [43, 38], ~, Scalar], # 44
  [If, ~, [42, 44], 42], # 45
  [Proj, {index: 0}, [45]], # 46
  [Loop, {bound: entry}, [46], 46], # 47
  [Phi, {region: 47}, [1, 104], ~, Int], # 48
  [Phi, {memory: true, region: 47}, [16, 98], ~, Unknown], # 49
  [Subscript, {kind: array}, [31, 48], ~, Scalar, 49], # 50
  [Constant, {const_type: string, value: VERSION}, ~, ~, Str], # 51
  [Subscript, {kind: hash}, [50, 51], ~, Scalar], # 52
  [ArrayLiteral, ~, [52], ~, Array], # 53
  [Proj, {index: 0}, [47]], # 54
  [Call, {dispatch_kind: builtin, name: reftype_of_ref, param_names: []}, [50], ~, Str, 49], # 55
  [StrEq, ~, [55, 34], ~, Boolean], # 56
  [Subscript, ~, [50, 36], ~, Scalar, 49], # 57
  [And, ~, [56, 57], ~, Scalar], # 58
  [If, ~, [54, 58], 54], # 59
  [Proj, {index: 0}, [59]], # 60
  [Proj, {index: 1}, [59]], # 61
  [Region, {head: 59}, [60, 61]], # 62
  [Exists, {kind: hash}, [50, 51], ~, Boolean, 49], # 63
  [Phi, {predecessors: [60, 61], region: 62}, [63, 58], ~, Scalar], # 64
  [If, ~, [62, 64], 62], # 65
  [Proj, {index: 0}, [65]], # 66
  [Loop, {bound: entry}, [66], 66], # 67
  [Phi, {region: 67}, [1, 106], ~, Int], # 68
  [Phi, {memory: true, region: 67}, [49, 78], ~, Unknown], # 69
  [Subscript, {kind: array}, [53, 68], ~, Scalar, 69], # 70
  [Constant, {const_type: string, value: SCALAR}, ~, ~, Str], # 71
  [Subscript, ~, [70, 71], ~, Scalar, 69], # 72
  [Proj, {index: 0}, [67]], # 73
  [Call, {dispatch_kind: builtin, name: reftype_of_ref, param_names: []}, [70], ~, Str, 69], # 74
  [StrEq, ~, [74, 34], ~, Boolean], # 75
  [If, ~, [73, 75], 73], # 76
  [Proj, {index: 0}, [76]], # 77
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 127, package: Carp, sigil: $, strict: true}, [72], 77, Scalar, 69, true], # 78
  [Proj, {index: 1}, [76]], # 79
  [Region, {head: 76}, [79, 78]], # 80
  [Phi, {predecessors: [79, 77], region: 80}, [1, 78], ~, Scalar], # 81
  [Proj, {index: 1}, [45]], # 82
  [Proj, {index: 1}, [65]], # 83
  [Region, ~, [19, 82, 83, 80]], # 84
  [Phi, {predecessors: [19, 82, 83, 73], region: 84}, [20, 1, 1, 81], ~, Scalar], # 85
  [Phi, {exits: true, memory: true, predecessors: [9, 12], region: 19}, [5, 18], ~, Unknown], # 86
  [Phi, {exits: true, memory: true, predecessors: [79, 77], region: 80}, [69, 78], ~, Unknown], # 87
  [Phi, {exits: true, memory: true, predecessors: [19, 82, 83, 73], region: 84}, [86, 16, 49, 87], ~, Unknown], # 88
  [Return, ~, [85], 84, ~, 88], # 89
  [Proj, {index: 1}, [47]], # 90
  [Region, {head: 47}, [90]], # 91
  [Phi, {memory: true, region: 91}, [49], ~, Unknown], # 92
  [EntryWrite, ~, [10, 24], 91, Unknown, 92, true], # 93
  [Count, ~, [22], ~, Int, 16], # 94
  [Count, ~, [31], ~, Int, 16], # 95
  [Proj, {index: 1}, [67]], # 96
  [Region, {head: 67}, [96]], # 97
  [Phi, {memory: true, region: 97}, [69], ~, Unknown], # 98
  [Count, ~, [31], ~, Int, 49], # 99
  [Count, ~, [53], ~, Int, 49], # 100
  [NumGt, ~, [94, 23], 13, Boolean], # 101
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 102
  [Add, ~, [23, 102], ~, Int], # 103
  [Add, ~, [48, 102], ~, Int], # 104
  [NumGt, ~, [99, 48], 47, Boolean], # 105
  [Add, ~, [68, 102], ~, Int], # 106
  [Count, ~, [53], ~, Int, 69], # 107
  [NumGt, ~, [107, 68], 67, Boolean], # 108
  [Count, ~, [22], ~, Int, 5]]} # 109
Carp::caller_info: {start: 0, returns: [194], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [Wantarray, ~, ~, ~, Scalar], # 2
  [PadAccess, {sigil: "%", symbol: call_info}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: sub_name}, ~, ~, Str], # 4
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 5
  [Ref, ~, [3], ~, HashRef], # 6
  [Constant, {const_type: string, value: pack}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: file}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: line}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: sub}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: has_args}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: wantarray}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: evaltext}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: is_require}, ~, ~, Str], # 14
  [Slice, {kind: hash}, [7, 8, 9, 10, 11, 12, 13, 14, 3], ~, List], # 15
  [ArgsSource, ~, ~, ~, Array], # 16
  [MemStart], # 17
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [16], 0, Scalar, 17, true], # 18
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 18], # 19
  [Coerce, {from_repr: Scalar, to_repr: Num}, [18], ~, Num], # 20
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 21
  [Add, ~, [20, 21], ~, Num], # 22
  [Assign, ~, [19, 22], 18, Num, 18, true], # 23
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 308, name: Carp::_cgc, package: Carp, param_names: [], want: scalar}, ~, 23, List, 23, true], # 24
  [EntryDef, {package: DB, sigil: "@", symbol: args}, ~, ~, Array], # 25
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 24], # 26
  [Ref, ~, [26], ~, Unknown], # 27
  [ArrayLiteral, {sigil: "@", symbol: "@DB::args"}, [27], ~, Array], # 28
  [EntryWrite, ~, [25, 28], 24, Unknown, 24, true], # 29
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 29], # 30
  [If, ~, [29, 24], 29], # 31
  [Proj, {index: 0}, [31]], # 32
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 320, name: "", package: DB, param_names: [], want: list}, [24, 30], 32, Unknown, 29, true], # 33
  [Proj, {index: 1}, [31]], # 34
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, [30], 34, List, 29], # 35
  [Region, {head: 31}, [33, 35]], # 36
  [Phi, {predecessors: [32, 34], region: 36}, [33, 35], ~, Unknown], # 37
  [Phi, {memory: true, predecessors: [32, 34], region: 36}, [33, 29], ~, Unknown], # 38
  [Assign, {targets: 1}, [15, 37], 36, Unknown, 38, true], # 39
  [Subscript, {kind: hash}, [3, 8], ~, Scalar, 39], # 40
  [Defined, ~, [40], ~, Boolean], # 41
  [Not, ~, [41], ~, Boolean], # 42
  [If, ~, [39, 42], 39], # 43
  [Proj, {index: 1}, [43]], # 44
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 328, name: Carp::get_subname, package: Carp, param_names: [], want: scalar}, [6], 44, Scalar, 39, true], # 45
  [Coerce, {from_repr: Scalar, to_repr: Str}, [45], ~, Str], # 46
  [Constant, {const_type: string, value: "("}, ~, ~, Str], # 47
  [Concat, ~, [46, 47], ~, Str], # 48
  [Constant, {const_type: string, value: ", "}, ~, ~, Str], # 49
  [Constant, {const_type: string, value: "** Incomplete caller override detected"}, ~, ~, Str], # 50
  [Constant, {const_type: string, value: " in &"}, ~, ~, Str], # 51
  [Constant, {const_type: string, value: B}, ~, ~, Str], # 52
  [Constant, {const_type: string, value: svref_2object}, ~, ~, Str], # 53
  [Subscript, {kind: hash}, [3, 11], ~, Scalar, 45], # 54
  [If, ~, [45, 54], 45], # 55
  [Proj, {index: 0}, [55]], # 56
  [Loop, {bound: entry}, [56], 56], # 57
  [Phi, {memory: true, region: 57}, [45, 229], ~, Unknown], # 58
  [Proj, {index: 1}, [57]], # 59
  [Region, {head: 57}, [59]], # 60
  [Phi, {memory: true, region: 60}, [58], ~, Unknown], # 61
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 61], # 62
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 63
  [ArrayLiteral, ~, ~, ~, Array], # 64
  [Phi, {region: 57}, [64, 238], ~, Array], # 65
  [Count, ~, [65], ~, Int, 61], # 66
  [NumEq, ~, [66, 21], ~, Boolean], # 67
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 68
  [Subscript, {kind: array}, [65, 68], ~, Scalar, 61], # 69
  [RefType, ~, [69], ~, Str, 61], # 70
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 61], # 71
  [Call, {dispatch_kind: builtin, name: reftype_of_ref, param_names: []}, [71], ~, Str, 61], # 72
  [StrEq, ~, [70, 72], ~, Boolean], # 73
  [And, ~, [67, 73], ~, Boolean], # 74
  [Coerce, {from_repr: Scalar, to_repr: Num}, [69], ~, Num], # 75
  [Ref, ~, [71], ~, Unknown], # 76
  [NumEq, ~, [75, 76], ~, Boolean], # 77
  [And, ~, [74, 77], ~, Boolean], # 78
  [If, ~, [60, 78], 60], # 79
  [Proj, {index: 0}, [79]], # 80
  [EntryWrite, ~, [62, 63], 80, Unknown, 61, true], # 81
  [PadAccess, {sigil: $, symbol: func}, ~, ~, Unknown, 81], # 82
  [Assign, ~, [82, 24], 81, List, 81, true], # 83
  [If, ~, [83, 24], 83], # 84
  [Proj, {index: 0}, [84]], # 85
  [Call, {dispatch_kind: direct, eval_id: 4, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 360, name: Carp::_fetch_sub, package: Carp, param_names: [], want: scalar}, [52, 53], 85, Unknown, 83, true], # 86
  [PadAccess, {sigil: $, symbol: func}, ~, ~, Unknown, 86], # 87
  [Not, ~, [86], ~, Boolean], # 88
  [If, ~, [86, 88], 86], # 89
  [Proj, {index: 1}, [89]], # 90
  [Call, {dispatch_kind: indirect, eval_id: 4, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 360, name: "", package: Carp, param_names: [], want: scalar}, [86, 87], 90, Unknown, 86, true], # 91
  [Call, {dispatch_kind: method, eval_id: 4, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 360, name: GV, package: Carp, param_names: [], want: scalar}, [91], 91, Unknown, 91, true], # 92
  [PadAccess, {sigil: $, symbol: gv}, ~, ~, Unknown, 92], # 93
  [Assign, ~, [93, 92], 92, Unknown, 92, true], # 94
  [PadAccess, {sigil: $, symbol: gv}, ~, ~, Unknown, 94], # 95
  [Call, {dispatch_kind: method, eval_id: 4, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 363, name: STASH, package: Carp, param_names: [], want: scalar}, [95], 94, Unknown, 94, true], # 96
  [Call, {dispatch_kind: method, eval_id: 4, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 363, name: NAME, package: Carp, param_names: [], want: scalar}, [96], 96, Unknown, 96, true], # 97
  [Coerce, {from_repr: Unknown, to_repr: Str}, [97], ~, Str], # 98
  [Concat, ~, [51, 98], ~, Str], # 99
  [Constant, {const_type: string, value: "::"}, ~, ~, Str], # 100
  [Concat, ~, [99, 100], ~, Str], # 101
  [PadAccess, {sigil: $, symbol: gv}, ~, ~, Unknown, 97], # 102
  [Call, {dispatch_kind: method, eval_id: 4, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 364, name: NAME, package: Carp, param_names: [], want: scalar}, [102], 97, Unknown, 97, true], # 103
  [Coerce, {from_repr: Unknown, to_repr: Str}, [103], ~, Str], # 104
  [Concat, ~, [101, 104], ~, Str], # 105
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 106
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 103], # 107
  [Defined, ~, [97], ~, Boolean], # 108
  [Defined, ~, [103], ~, Boolean], # 109
  [And, ~, [108, 109], ~, Boolean], # 110
  [If, ~, [103, 110], 103], # 111
  [Proj, {index: 0}, [111]], # 112
  [Constant, {const_type: string, value: CORE::GLOBAL}, ~, ~, Str], # 113
  [StrEq, ~, [98, 113], ~, Boolean], # 114
  [Constant, {const_type: string, value: caller}, ~, ~, Str], # 115
  [StrEq, ~, [104, 115], ~, Boolean], # 116
  [And, ~, [114, 116], ~, Boolean], # 117
  [If, ~, [112, 117], 112], # 118
  [Proj, {index: 1}, [118]], # 119
  [EntryWrite, ~, [107, 63], 119, Unknown, 103, true], # 120
  [Proj, {index: 1}, [84]], # 121
  [Proj, {index: 0}, [89]], # 122
  [Proj, {index: 1}, [111]], # 123
  [Proj, {index: 0}, [118]], # 124
  [Exc, ~, [86]], # 125
  [Exc, ~, [91]], # 126
  [Exc, ~, [92]], # 127
  [Exc, ~, [96]], # 128
  [Exc, ~, [97]], # 129
  [Exc, ~, [103]], # 130
  [Region, {catch: true, eval_id: 4}, [125, 126, 127, 128, 129, 130]], # 131
  [Phi, {memory: true, region: 131}, [86, 91, 92, 96, 97, 103], ~, Unknown], # 132
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 132], # 133
  [Phi, {region: 131}, [125, 126, 127, 128, 129, 130], ~, Scalar], # 134
  [EntryWrite, ~, [133, 134], 131, Unknown, 132, true], # 135
  [Region, {eval_entry: 80, eval_id: 4}, [120, 121, 122, 123, 124, 135]], # 136
  [Phi, {region: 136}, [105, 63, 63, 106, 106, 106], ~, "Maybe[Str]"], # 137
  [Or, ~, [137, 63], ~, "Maybe[Str]"], # 138
  [Coerce, {from_repr: Unknown, to_repr: Str}, [138], ~, Str], # 139
  [Concat, ~, [50, 139], ~, Str], # 140
  [Constant, {const_type: string, value: "; @DB::args were not set **"}, ~, ~, Str], # 141
  [Concat, ~, [140, 141], ~, Str], # 142
  [ArrayLiteral, {sigil: "@", symbol: args}, [142], ~, Array], # 143
  [ArrayLiteral, ~, ~, ~, Array], # 144
  [Proj, {index: 1}, [79]], # 145
  [EntryDef, {package: Carp, sigil: $, symbol: MaxArgNums}, ~, ~, Scalar, 61], # 146
  [Coerce, {from_repr: Scalar, to_repr: Num}, [146], ~, Num], # 147
  [NumGt, ~, [66, 147], ~, Boolean], # 148
  [And, ~, [146, 148], ~, Scalar], # 149
  [If, ~, [145, 149], 145], # 150
  [Proj, {index: 1}, [150]], # 151
  [Subtract, ~, [147, 21], ~, Num], # 152
  [Proj, {index: 0}, [150]], # 153
  [Call, {dispatch_kind: builtin, name: set_arylen, param_names: []}, [65, 152], 153, Int, 61, true], # 154
  [Region, {head: 150}, [151, 154]], # 155
  [Loop, {bound: entry}, [155], 155], # 156
  [Phi, {region: 156}, [144, 241], ~, Array], # 157
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 158
  [Phi, {memory: true, region: 136}, [120, 83, 86, 103, 103, 135], ~, Unknown], # 159
  [EntryWrite, ~, [158, 62], 136, Unknown, 159, true], # 160
  [Proj, {index: 1}, [156]], # 161
  [Region, {head: 156}, [161]], # 162
  [Phi, {predecessors: [151, 153], region: 155}, [106, 21], ~, "Maybe[Int]"], # 163
  [If, ~, [162, 163], 162], # 164
  [Proj, {index: 1}, [164]], # 165
  [Constant, {const_type: string, value: "..."}, ~, ~, Str], # 166
  [Proj, {index: 0}, [164]], # 167
  [Phi, {memory: true, predecessors: [151, 153], region: 155}, [61, 154], ~, Unknown], # 168
  [Phi, {memory: true, region: 156}, [168, 233], ~, Unknown], # 169
  [Phi, {memory: true, region: 162}, [169], ~, Unknown], # 170
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [157, 166], 167, Int, 170, true], # 171
  [Region, {head: 164}, [165, 171]], # 172
  [Region, {head: 79}, [160, 172]], # 173
  [Phi, {region: 173}, [143, 157], ~, Array], # 174
  [Phi, {memory: true, predecessors: [165, 167], region: 172}, [170, 171], ~, Unknown], # 175
  [Phi, {memory: true, region: 173}, [160, 175], ~, Unknown], # 176
  [PostfixDeref, {sigil: "@"}, [174], ~, Array, 176], # 177
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [49, 177], ~, Str, 176], # 178
  [Concat, ~, [48, 178], ~, Str], # 179
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 180
  [Concat, ~, [179, 180], ~, Str], # 181
  [Proj, {index: 1}, [55]], # 182
  [Region, {head: 55}, [182, 173]], # 183
  [Phi, {predecessors: [182, 56], region: 183}, [45, 181], ~, Scalar], # 184
  [Phi, {memory: true, predecessors: [182, 56], region: 183}, [45, 176], ~, Unknown], # 185
  [Assign, ~, [5, 184], 183, Scalar, 185, true], # 186
  [PadAccess, {sigil: "%", symbol: call_info}, ~, ~, Hash, 186], # 187
  [TernaryExpr, ~, [2, 187, 6], ~, Unknown], # 188
  [Proj, {index: 0}, [43]], # 189
  [Region, {head: 43}, [189, 186]], # 190
  [Phi, {predecessors: [189, 44], region: 190}, [1, 188], ~, Unknown], # 191
  [Phi, {predecessors: [189, 44], region: 190}, [106, 188], ~, Unknown], # 192
  [Phi, {exits: true, memory: true, predecessors: [189, 44], region: 190}, [39, 186], ~, Unknown], # 193
  [Return, ~, [191, 192], 190, ~, 193], # 194
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 58], # 195
  [Proj, {index: 0}, [57]], # 196
  [Assign, ~, [195, 106], 196, Undef, 58, true], # 197
  [Phi, {region: 156}, [68, 217], ~, Int], # 198
  [Proj, {index: 0}, [156]], # 199
  [Exists, {kind: array}, [65, 198], 199, Boolean, 169], # 200
  [Subscript, {kind: array}, [65, 198], ~, Scalar], # 201
  [Ref, ~, [201], ~, ScalarRef], # 202
  [TernaryExpr, ~, [200, 202, 106], ~, "Maybe[ScalarRef]"], # 203
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 197], # 204
  [EntryWrite, ~, [158, 204], 197, Unknown, 197, true], # 205
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 205], # 206
  [EntryWrite, ~, [206, 63], 205, Unknown, 205, true], # 207
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 207], # 208
  [Phi, {region: 57}, [68, 216], ~, Int], # 209
  [Subscript, {kind: array}, [25, 209], ~, Scalar, 58], # 210
  [Assign, ~, [208, 210], 207, Scalar, 207, true], # 211
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 211], # 212
  [EntryWrite, ~, [212, 63], 211, Unknown, 211, true], # 213
  [Region, {eval_entry: 205, eval_id: 3}, [213]], # 214
  [Phi, {region: 214}, [21], ~, "Maybe[Int]"], # 215
  [Add, ~, [209, 21], ~, Int], # 216
  [Add, ~, [198, 21], ~, Int], # 217
  [LocalAlias, {name: _}, [203], 200, Unknown, 169], # 218
  [If, ~, [214, 215], 214], # 219
  [PadAccess, {sigil: $, symbol: func}, ~, ~, Unknown, 83], # 220
  [Count, ~, [25], ~, Int, 45], # 221
  [Proj, {index: 0}, [219]], # 222
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 213], # 223
  [Constant, {const_type: string, value: "** argument not available anymore **"}, ~, ~, Str], # 224
  [Proj, {index: 1}, [219]], # 225
  [Assign, ~, [223, 224], 225, Str, 213, true], # 226
  [Region, {head: 219}, [222, 226]], # 227
  [Phi, {memory: true, predecessors: [222, 225], region: 227}, [213, 226], ~, Unknown], # 228
  [EntryWrite, ~, [158, 204], 227, Unknown, 228, true], # 229
  [Phi, {region: 173}, [62, 204], ~, Scalar], # 230
  [Count, ~, [25], ~, Int, 58], # 231
  [Subscript, {kind: array}, [65, 198], ~, Scalar, 169], # 232
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 382, name: Carp::format_arg, package: Carp, param_names: [], want: list}, [232], 218, Unknown, 169, true], # 233
  [NumGt, ~, [231, 209], 57, Boolean], # 234
  [Count, ~, [65], ~, Int, 169], # 235
  [NumGt, ~, [235, 198], 156, Boolean], # 236
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 228], # 237
  [ListAppend, {collector: map}, [65, 237], ~, Array], # 238
  [Call, {dispatch_kind: builtin, name: arylen, param_names: []}, [65], ~, Int], # 239
  [Count, ~, [65], ~, Int, 168], # 240
  [ListAppend, {collector: map}, [157, 233], ~, Array]]} # 241
Carp::carp: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 293, name: Carp::shortmess, package: Carp, param_names: [], want: list}, [1], 0, Unknown, 2, true], # 3
  [Call, {dispatch_kind: builtin, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 293, name: warn, param_names: []}, [3], 3, Boolean, 3, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
Carp::cluck: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 294, name: Carp::longmess, package: Carp, param_names: [], want: list}, [1], 0, Unknown, 2, true], # 3
  [Call, {dispatch_kind: builtin, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 294, name: warn, param_names: []}, [3], 3, Boolean, 3, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
Carp::confess: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 292, name: Carp::longmess, package: Carp, param_names: [], want: list}, [2], 0, Unknown, 3, true], # 4
  [Unwind, {file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 292}, [4], 4, ~, 4], # 5
  [Return, {implicit: true}, [1], 5, ~, 4]]} # 6
Carp::croak: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 291, name: Carp::shortmess, package: Carp, param_names: [], want: list}, [2], 0, Unknown, 3, true], # 4
  [Unwind, {file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 291}, [4], 4, ~, 4], # 5
  [Return, {implicit: true}, [1], 5, ~, 4]]} # 6
Carp::export_fail: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Subscript, {kind: array}, [1, 4], ~, Scalar, 3], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: verbose}, ~, ~, Str], # 7
  [StrEq, ~, [6, 7], ~, Boolean], # 8
  [If, ~, [3, 8], 3], # 9
  [Proj, {index: 1}, [9]], # 10
  [EntryDef, {package: Carp, sigil: $, symbol: Verbose}, ~, ~, Scalar], # 11
  [Proj, {index: 0}, [9]], # 12
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 12, Scalar, 3, true], # 13
  [EntryWrite, ~, [11, 13], 13, Unknown, 13, true], # 14
  [Region, {head: 9}, [10, 14]], # 15
  [Phi, {memory: true, predecessors: [10, 12], region: 15}, [3, 14], ~, Unknown], # 16
  [Return, {implicit: true}, [1], 15, ~, 16]]} # 17
Carp::format_arg: {start: 0, returns: [169], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 0, Scalar, 3, true], # 4
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 4], # 5
  [Assign, ~, [5, 4], 4, Scalar, 4, true], # 6
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 6], # 7
  [Constant, {const_type: string, value: UNIVERSAL}, ~, ~, Str], # 8
  [RefType, ~, [7], ~, Str, 6], # 9
  [If, ~, [6, 9], 6], # 10
  [Proj, {index: 0}, [10]], # 11
  [EntryDef, {package: Carp, sigil: $, symbol: in_recurse}, ~, ~, Scalar, 6], # 12
  [Not, ~, [12], ~, Boolean], # 13
  [If, ~, [11, 13], 11], # 14
  [Proj, {index: 0}, [14]], # 15
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 404, name: Carp::_maybe_isa, package: Carp, param_names: [], want: scalar, xs: true}, [7, 8], 15, Unknown, 6, true], # 16
  [Proj, {index: 1}, [14]], # 17
  [Region, {head: 14}, [16, 17]], # 18
  [Phi, {memory: true, predecessors: [15, 17], region: 18}, [16, 6], ~, Unknown], # 19
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 19], # 20
  [EntryDef, {package: Carp, sigil: $, symbol: in_recurse}, ~, ~, Scalar], # 21
  [EntryDef, {package: Carp, sigil: $, symbol: in_recurse}, ~, ~, Scalar, 19], # 22
  [EntryDef, {package: main, sigil: "%", symbol: SIG}, ~, ~, Hash], # 23
  [Constant, {const_type: string, value: __DIE__}, ~, ~, Str], # 24
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 25
  [Phi, {predecessors: [15, 17], region: 18}, [16, 13], ~, Unknown], # 26
  [If, ~, [18, 26], 18], # 27
  [Proj, {index: 0}, [27]], # 28
  [EntryWrite, ~, [21, 25], 28, Unknown, 19, true], # 29
  [Subscript, {kind: hash}, [23, 24], ~, Scalar, 29], # 30
  [Exists, {kind: hash}, [23, 24], ~, Boolean, 29], # 31
  [Subscript, {kind: hash}, [23, 24], ~, Scalar], # 32
  [AnonSub, {name: Carp::format_arg::__ANON__:408:11}, ~, ~, CodeRef], # 33
  [Assign, {local: true}, [32, 33], 29, CodeRef, 29, true], # 34
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 34], # 35
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 36
  [EntryWrite, ~, [35, 36], 34, Unknown, 34, true], # 37
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 37], # 38
  [Constant, {const_type: string, value: CARP_TRACE}, ~, ~, Str], # 39
  [Call, {dispatch_kind: method, eval_id: 5, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 409, name: can, package: Carp, param_names: [], want: scalar}, [38, 39], 37, Unknown, 37, true], # 40
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 40], # 41
  [EntryWrite, ~, [41, 36], 40, Unknown, 40, true], # 42
  [Exc, ~, [40]], # 43
  [Region, {catch: true, eval_id: 5}, [43]], # 44
  [EntryWrite, ~, [41, 43], 44, Unknown, 40, true], # 45
  [Region, {eval_entry: 34, eval_id: 5}, [42, 45]], # 46
  [Phi, {memory: true, region: 46}, [42, 45], ~, Unknown], # 47
  [ElemRestore, {kind: hash}, [23, 24, 30, 31], 46, Unknown, 47, true], # 48
  [EntryWrite, ~, [21, 22], 48, Unknown, 48, true], # 49
  [EntryWrite, ~, [1, 20], 49, Unknown, 49, true], # 50
  [Proj, {index: 1}, [27]], # 51
  [Region, {head: 27}, [50, 51]], # 52
  [Phi, {memory: true, region: 52}, [50, 19], ~, Unknown], # 53
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 53], # 54
  [EntryDef, {package: Carp, sigil: $, symbol: in_recurse}, ~, ~, Scalar, 53], # 55
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 56
  [Phi, {region: 46}, [40, 56], ~, Unknown], # 57
  [Phi, {region: 52}, [57, 26], ~, Unknown], # 58
  [If, ~, [52, 58], 52], # 59
  [Proj, {index: 1}, [59]], # 60
  [Not, ~, [55], ~, Boolean], # 61
  [EntryDef, {package: Carp, sigil: $, symbol: RefArgFormatter}, ~, ~, Scalar, 53], # 62
  [Defined, ~, [62], ~, Boolean], # 63
  [And, ~, [61, 63], ~, Boolean], # 64
  [If, ~, [60, 64], 60], # 65
  [Proj, {index: 0}, [65]], # 66
  [EntryWrite, ~, [21, 25], 66, Unknown, 53, true], # 67
  [Subscript, {kind: hash}, [23, 24], ~, Scalar, 67], # 68
  [Exists, {kind: hash}, [23, 24], ~, Boolean, 67], # 69
  [AnonSub, {name: Carp::format_arg::__ANON__:419:20}, ~, ~, CodeRef], # 70
  [Assign, {local: true}, [32, 70], 67, CodeRef, 67, true], # 71
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 71], # 72
  [EntryWrite, ~, [72, 36], 71, Unknown, 71, true], # 73
  [EntryDef, {package: Carp, sigil: $, symbol: RefArgFormatter}, ~, ~, Scalar, 73], # 74
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 73], # 75
  [Call, {dispatch_kind: indirect, eval_id: 6, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 420, name: "", package: Carp, param_names: [], want: scalar}, [74, 75], 73, Unknown, 73, true], # 76
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 76], # 77
  [Assign, ~, [77, 76], 76, Unknown, 76, true], # 78
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 78], # 79
  [EntryWrite, ~, [79, 36], 78, Unknown, 78, true], # 80
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 76], # 81
  [Exc, ~, [76]], # 82
  [Region, {catch: true, eval_id: 6}, [82]], # 83
  [EntryWrite, ~, [81, 82], 83, Unknown, 76, true], # 84
  [Region, {eval_entry: 71, eval_id: 6}, [80, 84]], # 85
  [Phi, {memory: true, region: 85}, [80, 84], ~, Unknown], # 86
  [ElemRestore, {kind: hash}, [23, 24, 68, 69], 85, Unknown, 86, true], # 87
  [EntryWrite, ~, [21, 55], 87, Unknown, 87, true], # 88
  [EntryWrite, ~, [1, 54], 88, Unknown, 88, true], # 89
  [Proj, {index: 1}, [65]], # 90
  [Region, {head: 65}, [89, 90]], # 91
  [Phi, {memory: true, region: 91}, [89, 53], ~, Unknown], # 92
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 92], # 93
  [Phi, {region: 85}, [25, 56], ~, "Maybe[Int]"], # 94
  [Phi, {region: 91}, [94, 64], ~, Scalar], # 95
  [If, ~, [91, 95], 91], # 96
  [Proj, {index: 1}, [96]], # 97
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 431, name: Carp::_StrVal, package: Carp, param_names: []}, [93], 97, Unknown, 92, true], # 98
  [Proj, {index: 0}, [96]], # 99
  [Region, {head: 96}, [98, 99]], # 100
  [Phi, {predecessors: [97, 99], region: 100}, [98, 93], ~, Unknown], # 101
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 53], # 102
  [Proj, {index: 0}, [59]], # 103
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 431, name: CARP_TRACE, package: Carp, param_names: []}, [102], 103, Unknown, 53, true], # 104
  [Region, {head: 59}, [100, 104]], # 105
  [Phi, {predecessors: [60, 103], region: 105}, [101, 104], ~, Unknown], # 106
  [Constant, {const_type: string, value: undef}, ~, ~, Str], # 107
  [Proj, {index: 1}, [10]], # 108
  [Defined, ~, [7], ~, Boolean], # 109
  [Not, ~, [109], ~, Boolean], # 110
  [If, ~, [108, 110], 108], # 111
  [Proj, {index: 1}, [111]], # 112
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 435, name: Carp::downgrade, package: Carp, param_names: [], want: void, xs: true}, [7, 25], 112, Unknown, 6, true], # 113
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 113], # 114
  [Constant, {const_type: string, value: "\""}, ~, ~, Str], # 115
  [EntryDef, {package: Carp, sigil: $, symbol: MaxArgLen}, ~, ~, Scalar, 113], # 116
  [Coerce, {from_repr: Scalar, to_repr: Num}, [116], ~, Num], # 117
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 118
  [Subtract, ~, [117, 118], ~, Num], # 119
  [Length, ~, [114], ~, Int], # 120
  [RegexMatch, {flags: "", pattern: "\\A-?[0-9]+(?:\\.[0-9]*)?(?:[eE][-+]?[0-9]+)?\\z"}, [114], 113, Boolean], # 121
  [If, ~, [121, 121], 121], # 122
  [Proj, {index: 1}, [122]], # 123
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 124
  [NumLt, ~, [124, 117], ~, Boolean], # 125
  [NumLt, ~, [117, 120], ~, Boolean], # 126
  [And, ~, [125, 126], ~, Boolean], # 127
  [If, ~, [123, 127], 123], # 128
  [Proj, {index: 0}, [128]], # 129
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [114, 119, 120, 36], 129, Str, 113, true], # 130
  [Proj, {index: 1}, [128]], # 131
  [Region, {head: 128}, [131, 130]], # 132
  [Phi, {memory: true, predecessors: [131, 129], region: 132}, [113, 130], ~, Unknown], # 133
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Str, 133], # 134
  [Constant, {const_type: string, value: "\\"}, ~, ~, Str], # 135
  [RegexMatch, {flags: g, pattern: "([\\\"\\\\\\$\\@])"}, [134], ~, Boolean], # 136
  [RegexCapture, {"n": 1}, [136], ~, Str], # 137
  [Concat, ~, [135, 137], ~, Str], # 138
  [If, ~, [132, 136], 132], # 139
  [Proj, {index: 0}, [139]], # 140
  [Proj, {index: 1}, [139]], # 141
  [Region, {head: 139}, [140, 141]], # 142
  [Phi, {predecessors: [140, 141], region: 142}, [138, 56], ~, "Maybe[Str]"], # 143
  [RegexSubst, {flags: g, pattern: "([\\\"\\\\\\$\\@])", replacement: ""}, [134, 143], 142, Str, 133, true], # 144
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 144], # 145
  [RegexSubst, {flags: g, pattern: "([^ !\"#\\$\\%\\&'()*+,\\-./0123456789:;<=>?\\@ABCDEFGHIJKLMNOPQRSTUVWXYZ\\[\\\\\\]^_`abcdefghijklmnopqrstuvwxyz\\{|}~])", replacement: "", replacement_body: Carp::format_arg::__SUBSTREPL__:1}, [145], 144, Str, 144, true], # 146
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 146], # 147
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 462, name: Carp::downgrade, package: Carp, param_names: [], want: void, xs: true}, [147, 25], 146, Unknown, 146, true], # 148
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Str, 148], # 149
  [Coerce, {from_repr: Unknown, to_repr: Str}, [149], ~, Str], # 150
  [Concat, ~, [115, 150], ~, Str], # 151
  [Concat, ~, [151, 115], ~, Str], # 152
  [Constant, {const_type: string, value: "..."}, ~, ~, Str], # 153
  [Phi, {predecessors: [131, 129], region: 132}, [36, 153], ~, Str], # 154
  [Concat, ~, [152, 154], ~, Str], # 155
  [Proj, {index: 0}, [122]], # 156
  [Region, {head: 122}, [156, 148]], # 157
  [Phi, {predecessors: [156, 123], region: 157}, [114, 155], ~, Unknown], # 158
  [Proj, {index: 0}, [111]], # 159
  [Region, {head: 111}, [159, 157]], # 160
  [Phi, {predecessors: [159, 112], region: 160}, [107, 158], ~, Unknown], # 161
  [Region, {head: 10}, [105, 160]], # 162
  [Phi, {predecessors: [11, 108], region: 162}, [106, 161], ~, Unknown], # 163
  [Phi, {exits: true, memory: true, predecessors: [97, 99], region: 100}, [98, 92], ~, Unknown], # 164
  [Phi, {exits: true, memory: true, predecessors: [60, 103], region: 105}, [164, 104], ~, Unknown], # 165
  [Phi, {exits: true, memory: true, predecessors: [156, 123], region: 157}, [113, 148], ~, Unknown], # 166
  [Phi, {exits: true, memory: true, predecessors: [159, 112], region: 160}, [6, 166], ~, Unknown], # 167
  [Phi, {exits: true, memory: true, predecessors: [11, 108], region: 162}, [165, 167], ~, Unknown], # 168
  [Return, ~, [163], 162, ~, 168], # 169
  [Phi, {region: 52}, [22, 12], ~, Scalar], # 170
  [Phi, {region: 91}, [55, 170], ~, Scalar], # 171
  [Phi, {region: 91}, [54, 20], ~, Scalar], # 172
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [114, 119], ~, Str]]} # 173
Carp::format_arg::__ANON__:408:11: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Return, {implicit: true, valueless: true}, [1], 0, ~, 2]]} # 3
Carp::format_arg::__ANON__:419:20: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Return, {implicit: true, valueless: true}, [1], 0, ~, 2]]} # 3
Carp::format_arg::__SUBSTREPL__:1: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "\\x{%x}"}, ~, ~, Str], # 1
  [RegexMatch, {flags: g, pattern: "([^ !\"#\\$\\%\\&'()*+,\\-./0123456789:;<=>?\\@ABCDEFGHIJKLMNOPQRSTUVWXYZ\\[\\\\\\]^_`abcdefghijklmnopqrstuvwxyz\\{|}~])"}, ~, ~, Boolean], # 2
  [RegexCapture, {"n": 1}, [2], ~, Str], # 3
  [Call, {dispatch_kind: builtin, name: ord, param_names: []}, [3], ~, Int], # 4
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [1, 4], ~, Str], # 5
  [MemStart], # 6
  [Return, {implicit: true}, [5], 0, ~, 6]]} # 7
Carp::get_status: {start: 0, returns: [35], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 3, Scalar, 3, true], # 4
  [PadAccess, {sigil: $, symbol: pkg}, ~, ~, Unknown, 4], # 5
  [Assign, ~, [5, 4], 4, Scalar, 4, true], # 6
  [PadAccess, {sigil: $, symbol: pkg}, ~, ~, Unknown, 6], # 7
  [Subscript, {kind: hash}, [3, 7], ~, Scalar], # 8
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 9
  [Subscript, {kind: hash}, [3, 7], 6, Scalar, 6], # 10
  [Defined, ~, [10], ~, Boolean], # 11
  [If, ~, [10, 11], 10], # 12
  [Proj, {index: 1}, [12]], # 13
  [Assign, ~, [8, 9], 13, Undef, 6, true], # 14
  [Proj, {index: 0}, [12]], # 15
  [Region, {head: 12}, [15, 14]], # 16
  [Phi, {memory: true, predecessors: [15, 13], region: 16}, [6, 14], ~, Scalar], # 17
  [PadAccess, {sigil: $, symbol: pkg}, ~, ~, Unknown, 17], # 18
  [If, ~, [16, 10], 16], # 19
  [Proj, {index: 1}, [19]], # 20
  [HashLiteral, ~, [18, 18], 20, HashRef], # 21
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 499, name: Carp::trusts_directly, package: Carp, param_names: [], want: list}, [18], 21, List, 17, true], # 22
  [ArrayLiteral, ~, [22], 22, ArrayRef], # 23
  [ArrayLiteral, ~, [21, 23], 23, ArrayRef], # 24
  [Assign, ~, [8, 24], 24, ArrayRef, 22, true], # 25
  [Proj, {index: 0}, [19]], # 26
  [Region, {head: 19}, [26, 25]], # 27
  [Phi, {memory: true, predecessors: [26, 20], region: 27}, [17, 25], ~, Scalar], # 28
  [PadAccess, {sigil: $, symbol: pkg}, ~, ~, Unknown, 28], # 29
  [Subscript, {kind: hash}, [3, 29], 27, Scalar, 28, true], # 30
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 500, package: Carp, sigil: "@", strict: true}, [30], 30, Array, 30, true], # 31
  [ArrayLiteral, ~, [31], ~, List], # 32
  [Count, ~, [31], ~, Int, 31], # 33
  [Coerce, {from_repr: List, to_repr: Scalar}, [33], ~, Scalar], # 34
  [Return, ~, [32, 34], 31, ~, 31]]} # 35
Carp::get_subname: {start: 0, returns: [70], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "eval '"}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 0, Scalar, 3, true], # 4
  [Constant, {const_type: string, value: is_require}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: evaltext}, ~, ~, Str], # 6
  [Subscript, {kind: hash}, [4, 6], 4, Scalar, 4, true], # 7
  [Defined, ~, [7], ~, Boolean], # 8
  [If, ~, [7, 8], 7], # 9
  [Proj, {index: 0}, [9]], # 10
  [Subscript, {kind: hash}, [4, 6], 10, Scalar, 7, true], # 11
  [PadAccess, {sigil: $, symbol: eval}, ~, ~, Unknown, 11], # 12
  [Assign, ~, [12, 11], 11, Scalar, 11, true], # 13
  [Subscript, {kind: hash}, [4, 5], 13, Scalar, 13, true], # 14
  [PadAccess, {sigil: $, symbol: eval}, ~, ~, Str, 14], # 15
  [Constant, {const_type: string, value: "\\"}, ~, ~, Str], # 16
  [RegexMatch, {flags: g, pattern: "([\\\\\\'])"}, [15], ~, Boolean], # 17
  [RegexCapture, {"n": 1}, [17], ~, Str], # 18
  [Concat, ~, [16, 18], ~, Str], # 19
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 20
  [If, ~, [14, 14], 14], # 21
  [Proj, {index: 1}, [21]], # 22
  [If, ~, [22, 17], 22], # 23
  [Proj, {index: 0}, [23]], # 24
  [Proj, {index: 1}, [23]], # 25
  [Region, {head: 23}, [24, 25]], # 26
  [Phi, {predecessors: [24, 25], region: 26}, [19, 20], ~, "Maybe[Str]"], # 27
  [RegexSubst, {flags: g, pattern: "([\\\\\\'])", replacement: ""}, [15, 27], 26, Str, 14, true], # 28
  [PadAccess, {sigil: $, symbol: eval}, ~, ~, Unknown, 28], # 29
  [EntryDef, {package: Carp, sigil: $, symbol: MaxEvalLen}, ~, ~, Scalar, 28], # 30
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 514, name: Carp::str_len_trim, package: Carp, param_names: [], want: scalar}, [29, 30], 28, Unknown, 28, true], # 31
  [Coerce, {from_repr: Unknown, to_repr: Str}, [31], ~, Str], # 32
  [Concat, ~, [1, 32], ~, Str], # 33
  [Constant, {const_type: string, value: "'"}, ~, ~, Str], # 34
  [Concat, ~, [33, 34], ~, Str], # 35
  [Constant, {const_type: string, value: "require "}, ~, ~, Str], # 36
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 37
  [Concat, ~, [36, 37], ~, Str], # 38
  [Proj, {index: 0}, [21]], # 39
  [Region, {head: 21}, [31, 39]], # 40
  [Phi, {predecessors: [22, 39], region: 40}, [35, 38], ~, Str], # 41
  [Constant, {const_type: string, value: __ANON__::__ANON__}, ~, ~, Str], # 42
  [Constant, {const_type: string, value: "eval {...}"}, ~, ~, Str], # 43
  [Constant, {const_type: string, value: sub}, ~, ~, Str], # 44
  [Proj, {index: 1}, [9]], # 45
  [Subscript, {kind: hash}, [4, 44], 45, Scalar, 7, true], # 46
  [Defined, ~, [46], ~, Boolean], # 47
  [Not, ~, [47], ~, Boolean], # 48
  [If, ~, [46, 48], 46], # 49
  [Proj, {index: 1}, [49]], # 50
  [Subscript, {kind: hash}, [4, 44], 50, Scalar, 46, true], # 51
  [Coerce, {from_repr: Unknown, to_repr: Str}, [51], ~, Str], # 52
  [Constant, {const_type: string, value: "(eval)"}, ~, ~, Str], # 53
  [StrEq, ~, [52, 53], ~, Boolean], # 54
  [If, ~, [51, 54], 51], # 55
  [Proj, {index: 1}, [55]], # 56
  [Subscript, {kind: hash}, [4, 44], 56, Scalar, 51, true], # 57
  [Proj, {index: 0}, [55]], # 58
  [Region, {head: 55}, [58, 57]], # 59
  [Phi, {predecessors: [58, 56], region: 59}, [43, 57], ~, Scalar], # 60
  [Proj, {index: 0}, [49]], # 61
  [Region, {head: 49}, [61, 59]], # 62
  [Phi, {predecessors: [61, 50], region: 62}, [42, 60], ~, Scalar], # 63
  [Region, {head: 9}, [40, 62]], # 64
  [Phi, {predecessors: [10, 45], region: 64}, [41, 63], ~, Scalar], # 65
  [Phi, {exits: true, memory: true, predecessors: [22, 39], region: 40}, [31, 14], ~, Unknown], # 66
  [Phi, {memory: true, predecessors: [58, 56], region: 59}, [51, 57], ~, Scalar], # 67
  [Phi, {exits: true, memory: true, predecessors: [61, 50], region: 62}, [46, 67], ~, Scalar], # 68
  [Phi, {exits: true, memory: true, predecessors: [10, 45], region: 64}, [66, 68], ~, Unknown], # 69
  [Return, ~, [65], 64, ~, 69]]} # 70
Carp::long_error_loc: {start: 0, returns: [69], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 2], # 3
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 4
  [Assign, ~, [3, 4], 0, Undef, 2, true], # 5
  [Loop, {bound: each}, [5], 5], # 6
  [Phi, {memory: true, region: 6}, [5, 19], ~, Unknown], # 7
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 7], # 8
  [Increment, ~, [8], ~, Scalar], # 9
  [Assign, ~, [8, 9], 6, Scalar, 7, true], # 10
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 534, name: Carp::_cgc, package: Carp, param_names: [], want: scalar}, ~, 10, List, 10, true], # 11
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 11], # 12
  [If, ~, [11, 11], 11], # 13
  [Proj, {index: 0}, [13]], # 14
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 535, name: "", package: Carp, param_names: [], want: list}, [11, 12], 14, Unknown, 11, true], # 15
  [Proj, {index: 1}, [13]], # 16
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, [12], 16, List, 11], # 17
  [Region, {head: 13}, [15, 17]], # 18
  [Phi, {memory: true, predecessors: [14, 16], region: 18}, [15, 11], ~, Unknown], # 19
  [EntryDef, {package: Carp, sigil: "%", symbol: Internal}, ~, ~, Hash], # 20
  [EntryDef, {package: Carp, sigil: "%", symbol: Internal}, ~, ~, Hash, 19], # 21
  [Ref, ~, [21], ~, HashRef], # 22
  [HashLiteral, ~, ~, ~, HashRef], # 23
  [Phi, {predecessors: [14, 16], region: 18}, [15, 17], ~, Unknown], # 24
  [ArrayLiteral, {sigil: "@", symbol: caller}, [24], 18, Array], # 25
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 26
  [Subscript, {kind: array}, [25, 26], ~, Scalar, 19], # 27
  [Defined, ~, [27], ~, Boolean], # 28
  [If, ~, [25, 28], 25], # 29
  [Proj, {index: 1}, [29]], # 30
  [Count, ~, [20], ~, Int, 19], # 31
  [If, ~, [30, 31], 30], # 32
  [Proj, {index: 0}, [32]], # 33
  [EntryWrite, {binds: true}, [20, 23], 33, Unknown, 19, true], # 34
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 542, name: Carp::long_error_loc, package: Carp, param_names: [], want: scalar}, ~, 34, Num, 34, true], # 35
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 35], # 36
  [Assign, ~, [36, 35], 35, Num, 35, true], # 37
  [EntryWrite, {binds: true}, [20, 22], 37, Unknown, 37, true], # 38
  [Proj, {index: 1}, [32]], # 39
  [Subscript, {kind: array}, [25, 1], ~, Scalar, 19], # 40
  [Defined, ~, [40], ~, Boolean], # 41
  [If, ~, [39, 41], 39], # 42
  [Proj, {index: 0}, [42]], # 43
  [EntryDef, {package: Carp, sigil: $, symbol: CarpLevel}, ~, ~, Scalar, 5], # 44
  [Phi, {region: 6}, [44, 80], ~, Unknown], # 45
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 46
  [Subtract, ~, [45, 46], ~, Unknown], # 47
  [NumGt, ~, [26, 47], ~, Boolean], # 48
  [If, ~, [43, 48], 43], # 49
  [Proj, {index: 0}, [49]], # 50
  [Proj, {index: 0}, [29]], # 51
  [EntryDef, {package: Carp, sigil: "%", symbol: CarpInternal}, ~, ~, Hash], # 52
  [Subscript, {kind: hash}, [52, 27], ~, Scalar, 19], # 53
  [If, ~, [51, 53], 51], # 54
  [Proj, {index: 1}, [54]], # 55
  [If, ~, [55, 48], 55], # 56
  [Proj, {index: 0}, [56]], # 57
  [Subscript, {kind: hash}, [20, 27], ~, Scalar, 19], # 58
  [If, ~, [57, 58], 57], # 59
  [Proj, {index: 1}, [59]], # 60
  [Region, {head: 6}, [50, 38, 60]], # 61
  [Phi, {memory: true, region: 61}, [19, 38, 19], ~, Unknown], # 62
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Num, 62], # 63
  [Subtract, ~, [63, 46], ~, Num], # 64
  [Proj, {index: 1}, [42]], # 65
  [Region, ~, [65, 61]], # 66
  [Phi, {predecessors: [65, 61], region: 66}, [1, 64], ~, Num], # 67
  [Phi, {exits: true, memory: true, predecessors: [65, 61], region: 66}, [19, 62], ~, Unknown], # 68
  [Return, ~, [67], 66, ~, 68], # 69
  [Phi, {region: 61}, [47, 45, 47], ~, Unknown], # 70
  [Proj, {index: 0}, [54]], # 71
  [Proj, {index: 1}, [49]], # 72
  [Region, {head: 6}, [71, 72]], # 73
  [Phi, {predecessors: [71, 72], region: 73}, [45, 47], ~, Unknown], # 74
  [Proj, {index: 1}, [56]], # 75
  [Region, {head: 6}, [73, 75]], # 76
  [Phi, {region: 76}, [74, 47], ~, Unknown], # 77
  [Proj, {index: 0}, [59]], # 78
  [Region, {head: 6}, [76, 78]], # 79
  [Phi, {region: 79}, [77, 47], ~, Unknown], # 80
  [EntryDef, {package: Carp, sigil: "%", symbol: Internal}, ~, ~, Hash, 38]]} # 81
Carp::longmess: {start: 0, returns: [40], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [EntryDef, {package: Carp, sigil: $, symbol: CarpLevel}, ~, ~, Scalar], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 269, name: Carp::_cgc, package: Carp, param_names: [], want: scalar}, ~, 0, List, 3, true], # 4
  [If, ~, [4, 4], 4], # 5
  [Proj, {index: 0}, [5]], # 6
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 270, name: "", package: Carp, param_names: [], want: scalar}, [4], 6, Unknown, 4, true], # 7
  [Proj, {index: 1}, [5]], # 8
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, ~, 8, Scalar, 4], # 9
  [Region, {head: 5}, [7, 9]], # 10
  [Phi, {memory: true, predecessors: [6, 8], region: 10}, [7, 4], ~, Unknown], # 11
  [EntryDef, {package: Carp, sigil: $, symbol: CarpLevel}, ~, ~, Scalar, 11], # 12
  [Coerce, {from_repr: Scalar, to_repr: Num}, [12], ~, Num], # 13
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 14
  [Add, ~, [13, 14], ~, Num], # 15
  [EntryDef, {package: Carp, sigil: "%", symbol: Internal}, ~, ~, Hash], # 16
  [Phi, {predecessors: [6, 8], region: 10}, [7, 9], ~, Unknown], # 17
  [Subscript, {kind: hash}, [16, 17], ~, Scalar, 11], # 18
  [EntryDef, {package: Carp, sigil: "%", symbol: CarpInternal}, ~, ~, Hash], # 19
  [Subscript, {kind: hash}, [19, 17], ~, Scalar, 11], # 20
  [Or, ~, [18, 20], ~, Scalar], # 21
  [If, ~, [10, 21], 10], # 22
  [Proj, {index: 1}, [22]], # 23
  [EntryWrite, ~, [2, 15], 23, Unknown, 11, true], # 24
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 276, name: Carp::longmess_heavy, package: Carp, param_names: []}, [1], 24, Unknown, 24, true], # 25
  [Proj, {index: 0}, [22]], # 26
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 276, name: Carp::longmess_heavy, package: Carp, param_names: []}, [1], 26, Unknown, 11, true], # 27
  [EntryDef, {package: main, sigil: $, symbol: "!"}, ~, ~, Scalar], # 28
  [EntryDef, {package: main, sigil: $, symbol: "!"}, ~, ~, Scalar, 3], # 29
  [EntryDef, {package: main, sigil: $, symbol: "\u0005"}, ~, ~, Scalar], # 30
  [EntryDef, {package: main, sigil: $, symbol: "\u0005"}, ~, ~, Scalar, 3], # 31
  [EntryWrite, ~, [2, 12], 25, Unknown, 25, true], # 32
  [EntryWrite, ~, [30, 31], 32, Unknown, 32, true], # 33
  [EntryWrite, ~, [28, 29], 33, Unknown, 33, true], # 34
  [EntryWrite, ~, [30, 31], 27, Unknown, 27, true], # 35
  [EntryWrite, ~, [28, 29], 35, Unknown, 35, true], # 36
  [Region, {head: 22}, [34, 36]], # 37
  [Phi, {predecessors: [23, 26], region: 37}, [25, 27], ~, Unknown], # 38
  [Phi, {exits: true, memory: true, predecessors: [23, 26], region: 37}, [34, 36], ~, Unknown], # 39
  [Return, ~, [38], 37, ~, 39]]} # 40
Carp::longmess_heavy: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Wantarray, ~, ~, ~, Scalar], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [TernaryExpr, ~, [1, 2, 5], ~, Unknown], # 6
  [RefType, ~, [5], ~, Str, 4], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 1}, [8]], # 9
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 570, name: Carp::long_error_loc, package: Carp, param_names: [], want: scalar}, ~, 9, Num, 4, true], # 10
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 10], # 11
  [Assign, ~, [11, 10], 10, Num, 10, true], # 12
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 12], # 13
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 571, name: Carp::ret_backtrace, package: Carp, param_names: []}, [13, 2], 12, Str, 12, true], # 14
  [Proj, {index: 0}, [8]], # 15
  [Region, {head: 8}, [15, 14]], # 16
  [Phi, {predecessors: [15, 9], region: 16}, [6, 14], ~, Unknown], # 17
  [Phi, {exits: true, memory: true, predecessors: [15, 9], region: 16}, [4, 14], ~, Unknown], # 18
  [Return, ~, [17], 16, ~, 18]]} # 19
Carp::ret_backtrace: {start: 0, returns: [76], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: error}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 3], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Assign, {targets: 2}, [4, 2, 5], 0, List, 3, true], # 6
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 2], ~, Str, 6], # 7
  [Constant, {const_type: string, value: " at "}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 6], # 10
  [Increment, ~, [10], ~, Scalar], # 11
  [Assign, ~, [10, 11], 6, Scalar, 6, true], # 12
  [Constant, {const_type: string, value: threads}, ~, ~, Str], # 13
  [SubDefined, {answer: 0, name: threads::tid, unless: [Exporter::import, Fcntl::import, POSIX::AUTOLOAD, SoN::Serialize::JSON::import]}, ~, ~, Boolean], # 14
  [If, ~, [12, 14], 12], # 15
  [Proj, {index: 0}, [15]], # 16
  [Call, {class_name: threads, dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 593, name: tid, package: Carp, param_names: [], want: scalar}, [13], 16, Unknown, 12, true], # 17
  [Proj, {index: 1}, [15]], # 18
  [Region, {head: 15}, [18, 17]], # 19
  [Phi, {memory: true, predecessors: [18, 16], region: 19}, [12, 17], ~, Unknown], # 20
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 20], # 21
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 597, name: Carp::caller_info, package: Carp, param_names: [], want: list}, [21], 19, Unknown, 20, true], # 22
  [HashLiteral, {sigil: "%", symbol: i}, [22], ~, Hash], # 23
  [Constant, {const_type: string, value: file}, ~, ~, Str], # 24
  [Subscript, {kind: hash}, [23, 24], ~, Scalar, 22], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 26
  [Concat, ~, [9, 26], ~, Str], # 27
  [Constant, {const_type: string, value: " line "}, ~, ~, Str], # 28
  [Concat, ~, [27, 28], ~, Str], # 29
  [Constant, {const_type: string, value: line}, ~, ~, Str], # 30
  [Subscript, {kind: hash}, [23, 30], ~, Scalar, 22], # 31
  [Coerce, {from_repr: Unknown, to_repr: Str}, [31], ~, Str], # 32
  [Concat, ~, [29, 32], ~, Str], # 33
  [Constant, {const_type: string, value: " thread "}, ~, ~, Str], # 34
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 35
  [Concat, ~, [34, 35], ~, Str], # 36
  [TernaryExpr, ~, [17, 36, 1], ~, Str], # 37
  [Phi, {predecessors: [18, 16], region: 19}, [1, 37], ~, Str], # 38
  [Concat, ~, [33, 38], ~, Str], # 39
  [Constant, {const_type: string, value: ", <%s> %s %d"}, ~, ~, Str], # 40
  [Constant, {const_type: ref, value: ~}, ~, ~, ScalarRef], # 41
  [EntryDef, {package: main, sigil: $, symbol: "."}, ~, ~, Scalar, 22], # 42
  [If, ~, [22, 42], 22], # 43
  [Proj, {index: 0}, [43]], # 44
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 602, package: Carp, sigil: $, strict: true}, [41], 44, Scalar, 22, true], # 45
  [If, ~, [45, 45], 45], # 46
  [Proj, {index: 0}, [46]], # 47
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 605, package: Carp, sigil: $, strict: true}, [41], 47, Scalar, 45, true], # 48
  [Constant, {const_type: string, value: NAME}, ~, ~, Str], # 49
  [Subscript, ~, [48, 49], ~, Scalar, 48], # 50
  [EntryDef, {package: main, sigil: $, symbol: "/"}, ~, ~, Scalar, 48], # 51
  [Coerce, {from_repr: Unknown, to_repr: Str}, [51], ~, Str], # 52
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 53
  [StrEq, ~, [52, 53], ~, Boolean], # 54
  [Constant, {const_type: string, value: chunk}, ~, ~, Str], # 55
  [TernaryExpr, ~, [54, 30, 55], ~, Str], # 56
  [EntryDef, {package: main, sigil: $, symbol: "."}, ~, ~, Scalar, 48], # 57
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [40, 50, 56, 57], ~, Str], # 58
  [Concat, ~, [39, 58], ~, Str], # 59
  [Proj, {index: 1}, [46]], # 60
  [Region, {head: 46}, [60, 48]], # 61
  [Phi, {predecessors: [60, 47], region: 61}, [39, 59], ~, Str], # 62
  [Proj, {index: 1}, [43]], # 63
  [Region, {head: 43}, [63, 61]], # 64
  [Phi, {predecessors: [63, 44], region: 64}, [39, 62], ~, Str], # 65
  [Constant, {const_type: string, value: ".\n"}, ~, ~, Str], # 66
  [Concat, ~, [65, 66], ~, Str], # 67
  [Loop, {bound: each}, [64], 64], # 68
  [Phi, {region: 68}, [67, 98], ~, Str], # 69
  [Proj, {index: 1}, [68]], # 70
  [Region, {head: 68}, [70]], # 71
  [Phi, {memory: true, predecessors: [60, 47], region: 61}, [45, 48], ~, Scalar], # 72
  [Phi, {memory: true, predecessors: [63, 44], region: 64}, [22, 72], ~, Unknown], # 73
  [Phi, {memory: true, region: 68}, [73, 82], ~, Unknown], # 74
  [Phi, {memory: true, region: 71}, [74], ~, Unknown], # 75
  [Return, ~, [69], 71, ~, 75], # 76
  [Constant, {const_type: string, value: "\t"}, ~, ~, Str], # 77
  [Concat, ~, [69, 77], ~, Str], # 78
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 74], # 79
  [Increment, ~, [79], ~, Scalar], # 80
  [Assign, ~, [79, 80], 68, Scalar, 74, true], # 81
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 621, name: Carp::caller_info, package: Carp, param_names: [], want: list}, [80], 81, Unknown, 81, true], # 82
  [HashLiteral, {sigil: "%", symbol: i__2}, [82], 82, Hash], # 83
  [Constant, {const_type: string, value: sub_name}, ~, ~, Str], # 84
  [Subscript, {kind: hash}, [83, 84], ~, Scalar, 82], # 85
  [Coerce, {from_repr: Unknown, to_repr: Str}, [85], ~, Str], # 86
  [Concat, ~, [78, 86], ~, Str], # 87
  [Constant, {const_type: string, value: " called at "}, ~, ~, Str], # 88
  [Concat, ~, [87, 88], ~, Str], # 89
  [Subscript, {kind: hash}, [83, 24], ~, Scalar, 82], # 90
  [Coerce, {from_repr: Unknown, to_repr: Str}, [90], ~, Str], # 91
  [Concat, ~, [89, 91], ~, Str], # 92
  [Concat, ~, [92, 28], ~, Str], # 93
  [Subscript, {kind: hash}, [83, 30], ~, Scalar, 82], # 94
  [Coerce, {from_repr: Unknown, to_repr: Str}, [94], ~, Str], # 95
  [Concat, ~, [93, 95], ~, Str], # 96
  [Concat, ~, [96, 38], ~, Str], # 97
  [Concat, ~, [97, 53], ~, Str], # 98
  [ArrayLiteral, ~, [82], ~, Array], # 99
  [Count, ~, [99], ~, Int, 82], # 100
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 101
  [NumNe, ~, [100, 101], 68, Boolean], # 102
  [Proj, {index: 0}, [68]]]} # 103
Carp::ret_summary: {start: 0, returns: [42], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: error}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 3], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Assign, {targets: 2}, [4, 2, 5], 0, List, 3, true], # 6
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 2], ~, Str, 6], # 7
  [Constant, {const_type: string, value: " at "}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 6], # 10
  [Increment, ~, [10], ~, Scalar], # 11
  [Assign, ~, [10, 11], 6, Scalar, 6, true], # 12
  [Constant, {const_type: string, value: threads}, ~, ~, Str], # 13
  [SubDefined, {answer: 0, name: threads::tid, unless: [Exporter::import, Fcntl::import, POSIX::AUTOLOAD, SoN::Serialize::JSON::import]}, ~, ~, Boolean], # 14
  [If, ~, [12, 14], 12], # 15
  [Proj, {index: 0}, [15]], # 16
  [Call, {class_name: threads, dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 635, name: tid, package: Carp, param_names: [], want: scalar}, [13], 16, Unknown, 12, true], # 17
  [Proj, {index: 1}, [15]], # 18
  [Region, {head: 15}, [18, 17]], # 19
  [Phi, {memory: true, predecessors: [18, 16], region: 19}, [12, 17], ~, Unknown], # 20
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 20], # 21
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 639, name: Carp::caller_info, package: Carp, param_names: [], want: list}, [21], 19, Unknown, 20, true], # 22
  [HashLiteral, {sigil: "%", symbol: i}, [22], ~, Hash], # 23
  [Constant, {const_type: string, value: file}, ~, ~, Str], # 24
  [Subscript, {kind: hash}, [23, 24], ~, Scalar, 22], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 26
  [Concat, ~, [9, 26], ~, Str], # 27
  [Constant, {const_type: string, value: " line "}, ~, ~, Str], # 28
  [Concat, ~, [27, 28], ~, Str], # 29
  [Constant, {const_type: string, value: line}, ~, ~, Str], # 30
  [Subscript, {kind: hash}, [23, 30], ~, Scalar, 22], # 31
  [Coerce, {from_repr: Unknown, to_repr: Str}, [31], ~, Str], # 32
  [Concat, ~, [29, 32], ~, Str], # 33
  [Constant, {const_type: string, value: " thread "}, ~, ~, Str], # 34
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 35
  [Concat, ~, [34, 35], ~, Str], # 36
  [TernaryExpr, ~, [17, 36, 1], ~, Str], # 37
  [Phi, {predecessors: [18, 16], region: 19}, [1, 37], ~, Str], # 38
  [Concat, ~, [33, 38], ~, Str], # 39
  [Constant, {const_type: string, value: ".\n"}, ~, ~, Str], # 40
  [Concat, ~, [39, 40], ~, Str], # 41
  [Return, ~, [41], 22, ~, 22]]} # 42
Carp::short_error_loc: {start: 0, returns: [99], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: cache}, ~, ~, Unknown, 2], # 3
  [HashLiteral, ~, ~, 0, HashRef], # 4
  [Assign, ~, [3, 4], 4, HashRef, 2, true], # 5
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 5], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Assign, ~, [6, 7], 5, Int, 5, true], # 8
  [Loop, {bound: each}, [8], 8], # 9
  [Phi, {memory: true, region: 9}, [8, 122], ~, Unknown], # 10
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 651, name: Carp::_cgc, package: Carp, param_names: [], want: scalar}, ~, 9, List, 10, true], # 11
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 11], # 12
  [If, ~, [11, 11], 11], # 13
  [Proj, {index: 0}, [13]], # 14
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 652, name: "", package: Carp, param_names: [], want: scalar}, [11, 12], 14, Unknown, 11, true], # 15
  [Proj, {index: 1}, [13]], # 16
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, [12], 16, Scalar, 11], # 17
  [Region, {head: 13}, [15, 17]], # 18
  [Phi, {memory: true, predecessors: [14, 16], region: 18}, [15, 11], ~, Unknown], # 19
  [PadAccess, {sigil: $, symbol: called}, ~, ~, Unknown, 19], # 20
  [Phi, {predecessors: [14, 16], region: 18}, [15, 17], ~, Unknown], # 21
  [Assign, ~, [20, 21], 18, Unknown, 19, true], # 22
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 22], # 23
  [Increment, ~, [23], ~, Scalar], # 24
  [Assign, ~, [23, 24], 22, Scalar, 22, true], # 25
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 25], # 26
  [If, ~, [25, 11], 25], # 27
  [Proj, {index: 0}, [27]], # 28
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 654, name: "", package: Carp, param_names: [], want: scalar}, [11, 26], 28, Unknown, 25, true], # 29
  [Proj, {index: 1}, [27]], # 30
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, [26], 30, Scalar, 25], # 31
  [Region, {head: 27}, [29, 31]], # 32
  [Phi, {memory: true, predecessors: [28, 30], region: 32}, [29, 25], ~, Unknown], # 33
  [PadAccess, {sigil: $, symbol: caller}, ~, ~, Unknown, 33], # 34
  [Phi, {predecessors: [28, 30], region: 32}, [29, 31], ~, Unknown], # 35
  [Assign, ~, [34, 35], 32, Unknown, 33, true], # 36
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 36], # 37
  [PadAccess, {sigil: $, symbol: caller}, ~, ~, Unknown, 36], # 38
  [Defined, ~, [38], ~, Boolean], # 39
  [If, ~, [36, 39], 36], # 40
  [Proj, {index: 1}, [40]], # 41
  [If, ~, [41, 11], 41], # 42
  [Proj, {index: 0}, [42]], # 43
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 657, name: "", package: Carp, param_names: [], want: list}, [11, 37], 43, Unknown, 36, true], # 44
  [Proj, {index: 1}, [42]], # 45
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, [37], 45, List, 36], # 46
  [Region, {head: 42}, [44, 46]], # 47
  [Phi, {memory: true, predecessors: [43, 45], region: 47}, [44, 36], ~, Unknown], # 48
  [PadAccess, {sigil: $, symbol: called}, ~, ~, Unknown, 36], # 49
  [PadAccess, {sigil: $, symbol: cache}, ~, ~, Unknown, 36], # 50
  [Proj, {index: 0}, [40]], # 51
  [EntryDef, {package: Carp, sigil: "%", symbol: Internal}, ~, ~, Hash], # 52
  [Subscript, {kind: hash}, [52, 38], ~, Scalar, 36], # 53
  [If, ~, [51, 53], 51], # 54
  [Proj, {index: 1}, [54]], # 55
  [EntryDef, {package: Carp, sigil: "%", symbol: CarpInternal}, ~, ~, Hash], # 56
  [Subscript, {kind: hash}, [56, 38], ~, Scalar, 36], # 57
  [If, ~, [55, 57], 55], # 58
  [Proj, {index: 1}, [58]], # 59
  [Subscript, {kind: hash}, [56, 49], ~, Scalar, 36], # 60
  [If, ~, [59, 60], 59], # 61
  [Proj, {index: 1}, [61]], # 62
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 673, name: Carp::trusts, package: Carp, param_names: [], want: scalar}, [49, 38, 50], 62, Boolean, 36, true], # 63
  [PadAccess, {sigil: $, symbol: caller}, ~, ~, Unknown, 63], # 64
  [PadAccess, {sigil: $, symbol: called}, ~, ~, Unknown, 63], # 65
  [PadAccess, {sigil: $, symbol: cache}, ~, ~, Unknown, 63], # 66
  [If, ~, [63, 63], 63], # 67
  [Proj, {index: 1}, [67]], # 68
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 674, name: Carp::trusts, package: Carp, param_names: [], want: scalar}, [64, 65, 66], 68, Boolean, 63, true], # 69
  [Phi, {predecessors: [43, 45], region: 47}, [44, 46], ~, Unknown], # 70
  [ArrayLiteral, {sigil: "@", symbol: caller}, [70], 47, Array], # 71
  [Count, ~, [71], ~, Int, 48], # 72
  [If, ~, [71, 72], 71], # 73
  [Proj, {index: 0}, [73]], # 74
  [PadAccess, {sigil: $, symbol: called}, ~, ~, Unknown, 48], # 75
  [Defined, ~, [75], ~, Boolean], # 76
  [Subscript, {kind: hash}, [56, 75], ~, Scalar, 48], # 77
  [And, ~, [76, 77], ~, Scalar], # 78
  [If, ~, [74, 78], 74], # 79
  [Proj, {index: 1}, [79]], # 80
  [EntryDef, {package: Carp, sigil: $, symbol: CarpLevel}, ~, ~, Scalar, 8], # 81
  [Phi, {region: 9}, [81, 128], ~, Unknown], # 82
  [Subtract, ~, [82, 7], ~, Unknown], # 83
  [NumGt, ~, [1, 83], ~, Boolean], # 84
  [If, ~, [80, 84], 80], # 85
  [Proj, {index: 0}, [85]], # 86
  [If, ~, [69, 69], 69], # 87
  [Proj, {index: 1}, [87]], # 88
  [If, ~, [88, 84], 88], # 89
  [Proj, {index: 0}, [89]], # 90
  [Region, {head: 9}, [86, 90]], # 91
  [Phi, {memory: true, region: 91}, [48, 69], ~, Unknown], # 92
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Num, 92], # 93
  [Subtract, ~, [93, 7], ~, Num], # 94
  [Proj, {index: 1}, [73]], # 95
  [Region, ~, [95, 91]], # 96
  [Phi, {predecessors: [95, 91], region: 96}, [1, 94], ~, Num], # 97
  [Phi, {exits: true, memory: true, predecessors: [95, 91], region: 96}, [48, 92], ~, Unknown], # 98
  [Return, ~, [97], 96, ~, 98], # 99
  [Phi, {region: 91}, [83, 83], ~, Unknown], # 100
  [Proj, {index: 0}, [54]], # 101
  [Proj, {index: 0}, [79]], # 102
  [Region, {head: 9}, [101, 102]], # 103
  [Phi, {memory: true, predecessors: [101, 102], region: 103}, [36, 48], ~, Unknown], # 104
  [Proj, {index: 1}, [85]], # 105
  [Region, {head: 9}, [103, 105]], # 106
  [Phi, {memory: true, region: 106}, [104, 48], ~, Unknown], # 107
  [Proj, {index: 0}, [58]], # 108
  [Region, {head: 9}, [106, 108]], # 109
  [Phi, {memory: true, region: 109}, [107, 36], ~, Unknown], # 110
  [Proj, {index: 0}, [61]], # 111
  [Region, {head: 9}, [109, 111]], # 112
  [Phi, {memory: true, region: 112}, [110, 36], ~, Unknown], # 113
  [Proj, {index: 0}, [67]], # 114
  [Region, {head: 9}, [112, 114]], # 115
  [Phi, {memory: true, region: 115}, [113, 63], ~, Unknown], # 116
  [Proj, {index: 0}, [87]], # 117
  [Region, {head: 9}, [115, 117]], # 118
  [Phi, {memory: true, region: 118}, [116, 69], ~, Unknown], # 119
  [Proj, {index: 1}, [89]], # 120
  [Region, {head: 9}, [118, 120]], # 121
  [Phi, {memory: true, region: 121}, [119, 69], ~, Unknown], # 122
  [Phi, {region: 106}, [82, 83], ~, Unknown], # 123
  [Phi, {region: 109}, [123, 82], ~, Unknown], # 124
  [Phi, {region: 112}, [124, 82], ~, Unknown], # 125
  [Phi, {region: 115}, [125, 82], ~, Unknown], # 126
  [Phi, {region: 118}, [126, 82], ~, Unknown], # 127
  [Phi, {region: 121}, [127, 83], ~, Unknown]]} # 128
Carp::shortmess: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [EntryDef, {package: Carp, sigil: "@", symbol: CARP_NOT}, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 284, name: Carp::_cgc, package: Carp, param_names: [], want: scalar}, ~, 0, List, 3, true], # 4
  [If, ~, [4, 4], 4], # 5
  [Proj, {index: 0}, [5]], # 6
  [Call, {dispatch_kind: indirect, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 287, name: "", package: Carp, param_names: [], want: scalar}, [4], 6, Unknown, 4, true], # 7
  [Proj, {index: 1}, [5]], # 8
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, ~, 8, Scalar, 4], # 9
  [Region, {head: 5}, [7, 9]], # 10
  [Phi, {predecessors: [6, 8], region: 10}, [7, 9], ~, Unknown], # 11
  [ArrayLiteral, {sigil: "@", symbol: "@Carp::CARP_NOT"}, [11], ~, Array], # 12
  [ArrayLiteral, ~, ~, ~, ArrayRef], # 13
  [Phi, {memory: true, predecessors: [6, 8], region: 10}, [7, 4], ~, Unknown], # 14
  [EntryWrite, {binds: true}, [2, 13], 10, Unknown, 14, true], # 15
  [EntryWrite, ~, [2, 12], 15, Unknown, 15, true], # 16
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 288, name: Carp::shortmess_heavy, package: Carp, param_names: []}, [1], 16, Unknown, 16, true], # 17
  [EntryDef, {package: main, sigil: $, symbol: "!"}, ~, ~, Scalar], # 18
  [EntryDef, {package: main, sigil: $, symbol: "!"}, ~, ~, Scalar, 3], # 19
  [EntryDef, {package: main, sigil: $, symbol: "\u0005"}, ~, ~, Scalar], # 20
  [EntryDef, {package: main, sigil: $, symbol: "\u0005"}, ~, ~, Scalar, 3], # 21
  [EntryDef, {package: Carp, sigil: "@", symbol: CARP_NOT}, ~, ~, Array, 14], # 22
  [Ref, ~, [22], ~, ArrayRef], # 23
  [EntryWrite, {binds: true}, [2, 23], 17, Unknown, 17, true], # 24
  [EntryWrite, ~, [20, 21], 24, Unknown, 24, true], # 25
  [EntryWrite, ~, [18, 19], 25, Unknown, 25, true], # 26
  [Return, {implicit: true}, [17], 26, ~, 26], # 27
  [EntryDef, {package: Carp, sigil: "@", symbol: CARP_NOT}, ~, ~, Array, 24]]} # 28
Carp::shortmess_heavy: {start: 0, returns: [36], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [EntryDef, {package: Carp, sigil: $, symbol: Verbose}, ~, ~, Scalar, 2], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 0}, [4]], # 5
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 681, name: Carp::longmess_heavy, package: Carp, param_names: []}, [1], 5, Unknown, 2, true], # 6
  [ArrayLiteral, ~, [1], ~, List], # 7
  [Proj, {index: 1}, [4]], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Subscript, {kind: array}, [1, 9], ~, Scalar, 2], # 10
  [RefType, ~, [10], ~, Str, 2], # 11
  [If, ~, [8, 11], 8], # 12
  [Proj, {index: 1}, [12]], # 13
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 683, name: Carp::short_error_loc, package: Carp, param_names: [], want: scalar}, ~, 13, Num, 2, true], # 14
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 14], # 15
  [Assign, ~, [15, 14], 14, Num, 14, true], # 16
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 16], # 17
  [If, ~, [16, 17], 16], # 18
  [Proj, {index: 0}, [18]], # 19
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 688, name: Carp::ret_summary, package: Carp, param_names: []}, [17, 1], 19, Str, 16, true], # 20
  [Proj, {index: 1}, [18]], # 21
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 688, name: Carp::longmess_heavy, package: Carp, param_names: []}, [1], 21, Unknown, 16, true], # 22
  [Region, {head: 18}, [20, 22]], # 23
  [Phi, {predecessors: [19, 21], region: 23}, [20, 22], ~, Unknown], # 24
  [Proj, {index: 0}, [12]], # 25
  [Region, {head: 12}, [25, 23]], # 26
  [Phi, {predecessors: [25, 13], region: 26}, [7, 24], ~, Unknown], # 27
  [Region, {head: 4}, [6, 26]], # 28
  [Phi, {predecessors: [5, 8], region: 28}, [6, 27], ~, Unknown], # 29
  [Coerce, {from_repr: List, to_repr: Scalar}, [1], ~, Scalar], # 30
  [Phi, {predecessors: [25, 13], region: 26}, [30, 24], ~, Unknown], # 31
  [Phi, {predecessors: [5, 8], region: 28}, [6, 31], ~, Unknown], # 32
  [Phi, {memory: true, predecessors: [19, 21], region: 23}, [20, 22], ~, Unknown], # 33
  [Phi, {exits: true, memory: true, predecessors: [25, 13], region: 26}, [2, 33], ~, Unknown], # 34
  [Phi, {exits: true, memory: true, predecessors: [5, 8], region: 28}, [6, 34], ~, Unknown], # 35
  [Return, ~, [29, 32], 28, ~, 35]]} # 36
Carp::str_len_trim: {start: 0, returns: [26], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [PadAccess, {sigil: $, symbol: str}, ~, ~, Unknown, 3], # 4
  [Assign, ~, [4, 3], 3, Scalar, 3, true], # 5
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 5, Scalar, 5, true], # 6
  [PadAccess, {sigil: $, symbol: str}, ~, ~, Str, 6], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Or, ~, [6, 8], ~, Scalar], # 9
  [Coerce, {from_repr: Scalar, to_repr: Num}, [9], ~, Num], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [Subtract, ~, [10, 11], ~, Num], # 12
  [Length, ~, [7], ~, Int], # 13
  [Constant, {const_type: string, value: "..."}, ~, ~, Str], # 14
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 15
  [NumLt, ~, [15, 10], ~, Boolean], # 16
  [NumLt, ~, [10, 13], ~, Boolean], # 17
  [And, ~, [16, 17], ~, Boolean], # 18
  [If, ~, [6, 18], 6], # 19
  [Proj, {index: 0}, [19]], # 20
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [7, 12, 13, 14], 20, Str, 6, true], # 21
  [Proj, {index: 1}, [19]], # 22
  [Region, {head: 19}, [22, 21]], # 23
  [Phi, {memory: true, predecessors: [22, 20], region: 23}, [6, 21], ~, Scalar], # 24
  [PadAccess, {sigil: $, symbol: str}, ~, ~, Unknown, 24], # 25
  [Return, ~, [25], 23, ~, 24], # 26
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [7, 12], ~, Str]]} # 27
Carp::trusts: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: known}, ~, ~, Unknown], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 0, Scalar, 3, true], # 4
  [PadAccess, {sigil: $, symbol: child}, ~, ~, Unknown, 4], # 5
  [Assign, ~, [5, 4], 4, Scalar, 4, true], # 6
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 6, Scalar, 6, true], # 7
  [PadAccess, {sigil: $, symbol: partial}, ~, ~, Unknown], # 8
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 7, Scalar, 7, true], # 9
  [PadAccess, {sigil: $, symbol: cache}, ~, ~, Unknown, 9], # 10
  [Assign, ~, [10, 9], 9, Scalar, 9, true], # 11
  [PadAccess, {sigil: $, symbol: cache}, ~, ~, Unknown, 11], # 12
  [PadAccess, {sigil: $, symbol: child}, ~, ~, Unknown, 11], # 13
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 712, name: Carp::get_status, package: Carp, param_names: [], want: list}, [12, 13], 11, List, 11, true], # 14
  [Assign, {targets: 2}, [1, 8, 14], 14, List, 14, true], # 15
  [Loop, {bound: each}, [15], 15], # 16
  [Proj, {index: 1}, [16]], # 17
  [Region, {head: 16}, [17]], # 18
  [Phi, {memory: true, region: 16}, [15, 55], ~, List], # 19
  [Phi, {memory: true, region: 18}, [19], ~, List], # 20
  [Exists, {kind: hash}, [1, 7], 18, Boolean, 20, true], # 21
  [Return, ~, [21], 21, ~, 21], # 22
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 722, package: Carp, sigil: "@", strict: true}, [8], 16, Array, 19, true], # 23
  [Exists, {kind: hash}, [1, 7], ~, Boolean, 23], # 24
  [PostfixDeref, {sigil: "@"}, [8], ~, Array, 23], # 25
  [Proj, {index: 0}, [16]], # 26
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [25], 26, Scalar, 23, true], # 27
  [PadAccess, {sigil: $, symbol: anc}, ~, ~, Unknown, 27], # 28
  [Assign, ~, [28, 27], 27, Scalar, 27, true], # 29
  [PadAccess, {sigil: $, symbol: anc}, ~, ~, Unknown, 29], # 30
  [Exists, {kind: hash}, [1, 30], 29, Boolean, 29, true], # 31
  [PadAccess, {sigil: $, symbol: anc}, ~, ~, Unknown, 31], # 32
  [Subscript, {kind: hash}, [1, 32], ~, Scalar], # 33
  [If, ~, [31, 31], 31], # 34
  [Proj, {index: 1}, [34]], # 35
  [Subscript, {kind: hash}, [1, 32], 35, Scalar, 31], # 36
  [PadAccess, {sigil: $, symbol: anc_knows}, ~, ~, Unknown], # 37
  [PadAccess, {sigil: $, symbol: anc_partial}, ~, ~, Unknown], # 38
  [Increment, ~, [36], ~, Scalar], # 39
  [Assign, ~, [33, 39], 36, Scalar, 31, true], # 40
  [PadAccess, {sigil: $, symbol: cache}, ~, ~, Unknown, 40], # 41
  [PadAccess, {sigil: $, symbol: anc}, ~, ~, Unknown, 40], # 42
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 719, name: Carp::get_status, package: Carp, param_names: [], want: list}, [41, 42], 40, List, 40, true], # 43
  [Assign, {targets: 2}, [37, 38, 43], 43, List, 43, true], # 44
  [PostfixDeref, {sigil: "%"}, [37], ~, Hash, 44], # 45
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [45], ~, List, 44], # 46
  [Slice, {kind: hash}, [46, 1], ~, List], # 47
  [Not, ~, [24], ~, Boolean], # 48
  [Assign, {targets: 1}, [47], 44, Unknown, 44, true], # 49
  [PostfixDeref, {sigil: "@"}, [8], ~, Array, 49], # 50
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 722, package: Carp, sigil: "@", strict: true}, [38], ~, Array, 49], # 51
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [50, 51], 49, Int, 49, true], # 52
  [Proj, {index: 0}, [34]], # 53
  [Region, {head: 34}, [53, 52]], # 54
  [Phi, {memory: true, predecessors: [53, 35], region: 54}, [31, 52], ~, Scalar], # 55
  [Count, ~, [23], ~, Int, 23], # 56
  [If, ~, [23, 56], 23], # 57
  [Proj, {index: 0}, [57]], # 58
  [Proj, {index: 1}, [57]], # 59
  [Region, {head: 57}, [58, 59]], # 60
  [Phi, {predecessors: [58, 59], region: 60}, [48, 56], ~, Scalar], # 61
  [Not, ~, [61], ~, Boolean], # 62
  [Not, ~, [62], 16, Boolean]]} # 63
Carp::trusts_directly: {start: 0, returns: [57], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "::"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [PostfixDeref, {sigil: "%"}, [6], ~, Hash, 3], # 7
  [Ref, ~, [7], ~, HashRef], # 8
  [Constant, {const_type: string, value: CARP_NOT}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: ISA}, ~, ~, Str], # 10
  [ArrayLiteral, ~, [9, 10], ~, Array], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Loop, {bound: entry}, [3], 3], # 13
  [Phi, {region: 13}, [12, 63], ~, Int], # 14
  [Phi, {memory: true, region: 13}, [3, 18], ~, Scalar], # 15
  [Subscript, {kind: array}, [11, 14], ~, Str, 15], # 16
  [Proj, {index: 0}, [13]], # 17
  [Subscript, {kind: hash}, [8, 16], 17, Scalar, 15, true], # 18
  [Subscript, {kind: hash}, [8, 16], ~, Scalar, 18], # 19
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 735, package: Carp, sigil: "@", strict: false}, [19], ~, Array, 18], # 20
  [ArrayLiteral, ~, [20], ~, List], # 21
  [ArrayLiteral, ~, ~, ~, List], # 22
  [If, ~, [18, 18], 18], # 23
  [Proj, {index: 0}, [23]], # 24
  [Proj, {index: 1}, [23]], # 25
  [Region, {head: 23}, [24, 25]], # 26
  [Subscript, {kind: hash}, [8, 16], ~, Scalar], # 27
  [Ref, {file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 735}, [27], ~, ScalarRef, 18], # 28
  [RefType, ~, [28], ~, Str, 18], # 29
  [Constant, {const_type: string, value: GLOB}, ~, ~, Str], # 30
  [StrEq, ~, [29, 30], ~, Boolean], # 31
  [Phi, {predecessors: [24, 25], region: 26}, [31, 18], ~, Scalar], # 32
  [If, ~, [26, 32], 26], # 33
  [Proj, {index: 0}, [33]], # 34
  [Proj, {index: 1}, [33]], # 35
  [Region, {head: 33}, [34, 35]], # 36
  [Constant, {const_type: string, value: ARRAY}, ~, ~, Str], # 37
  [Subscript, ~, [19, 37], ~, Scalar, 18], # 38
  [Phi, {predecessors: [34, 35], region: 36}, [38, 32], ~, Scalar], # 39
  [If, ~, [36, 39], 36], # 40
  [Proj, {index: 0}, [40]], # 41
  [Proj, {index: 1}, [40]], # 42
  [Region, {head: 40}, [41, 42]], # 43
  [Count, ~, [20], ~, Int, 18], # 44
  [Phi, {predecessors: [41, 42], region: 43}, [44, 39], ~, Scalar], # 45
  [If, ~, [43, 45], 43], # 46
  [Proj, {index: 0}, [46]], # 47
  [Proj, {index: 1}, [13]], # 48
  [Region, {head: 13}, [48]], # 49
  [Region, ~, [47, 49]], # 50
  [Phi, {predecessors: [47, 49], region: 50}, [21, 22], ~, List], # 51
  [Coerce, {from_repr: List, to_repr: Scalar}, [20], ~, Scalar], # 52
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 53
  [Phi, {predecessors: [47, 49], region: 50}, [52, 53], ~, Scalar], # 54
  [Phi, {memory: true, region: 49}, [15], ~, Scalar], # 55
  [Phi, {exits: true, memory: true, predecessors: [47, 49], region: 50}, [18, 55], ~, Scalar], # 56
  [Return, ~, [51, 54], 50, ~, 56], # 57
  [Count, ~, [11], ~, Int, 3], # 58
  [Count, ~, [11], ~, Int, 15], # 59
  [NumGt, ~, [59, 14], 13, Boolean], # 60
  [Proj, {index: 1}, [46]], # 61
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 62
  [Add, ~, [14, 62], ~, Int]]} # 63
Exporter::as_heavy: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: Exporter::Heavy::heavy_}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: "Exporter/Heavy.pm"}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 4], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: builtin, name: caller, param_names: []}, [7], 4, List, 4], # 8
  [Slice, {index_count: 1}, [6, 8], ~, List], # 9
  [Coerce, {from_repr: List, to_repr: Scalar}, [9], ~, Scalar], # 10
  [Assign, ~, [5, 10], 8, Scalar, 4, true], # 11
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 11], # 12
  [RegexSubst, {flags: "", pattern: ".*::", replacement: ""}, [12], 11, Str, 11, true], # 13
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Str, 13], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Concat, ~, [1, 15], ~, Str], # 16
  [Ref, ~, [16], ~, ScalarRef], # 17
  [Return, {implicit: true}, [17], 13, ~, 13]]} # 18
Exporter::export_fail: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [Return, {implicit: true}, [1], 3, ~, 3]]} # 4
POSIX::SigAction::flags: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: FLAGS}, ~, ~, Str], # 4
  [Coerce, {from_repr: Array, to_repr: Num}, [1], ~, Num], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [NumGt, ~, [5, 6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 1}, [8]], # 9
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 10
  [MemStart], # 11
  [Subscript, {kind: array}, [1, 6], ~, Scalar, 11], # 12
  [Proj, {index: 0}, [8]], # 13
  [Assign, ~, [10, 12], 13, Scalar, 11, true], # 14
  [Region, {head: 8}, [9, 14]], # 15
  [Phi, {memory: true, predecessors: [9, 13], region: 15}, [11, 14], ~, Unknown], # 16
  [Subscript, {kind: hash}, [3, 4], 15, Scalar, 16, true], # 17
  [Return, {implicit: true}, [17], 17, ~, 17]]} # 18
POSIX::SigAction::handler: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: HANDLER}, ~, ~, Str], # 4
  [Coerce, {from_repr: Array, to_repr: Num}, [1], ~, Num], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [NumGt, ~, [5, 6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 1}, [8]], # 9
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 10
  [MemStart], # 11
  [Subscript, {kind: array}, [1, 6], ~, Scalar, 11], # 12
  [Proj, {index: 0}, [8]], # 13
  [Assign, ~, [10, 12], 13, Scalar, 11, true], # 14
  [Region, {head: 8}, [9, 14]], # 15
  [Phi, {memory: true, predecessors: [9, 13], region: 15}, [11, 14], ~, Unknown], # 16
  [Subscript, {kind: hash}, [3, 4], 15, Scalar, 16, true], # 17
  [Return, {implicit: true}, [17], 17, ~, 17]]} # 18
POSIX::SigAction::mask: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: MASK}, ~, ~, Str], # 4
  [Coerce, {from_repr: Array, to_repr: Num}, [1], ~, Num], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [NumGt, ~, [5, 6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 1}, [8]], # 9
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 10
  [MemStart], # 11
  [Subscript, {kind: array}, [1, 6], ~, Scalar, 11], # 12
  [Proj, {index: 0}, [8]], # 13
  [Assign, ~, [10, 12], 13, Scalar, 11, true], # 14
  [Region, {head: 8}, [9, 14]], # 15
  [Phi, {memory: true, predecessors: [9, 13], region: 15}, [11, 14], ~, Unknown], # 16
  [Subscript, {kind: hash}, [3, 4], 15, Scalar, 16, true], # 17
  [Return, {implicit: true}, [17], 17, ~, 17]]} # 18
POSIX::SigAction::new: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: HANDLER}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Constant, {const_type: string, value: MASK}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7], ~, Scalar, 4], # 8
  [Constant, {const_type: string, value: FLAGS}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [2, 10], ~, Scalar, 4], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Or, ~, [11, 12], ~, Scalar], # 13
  [Constant, {const_type: string, value: SAFE}, ~, ~, Str], # 14
  [HashLiteral, ~, [1, 5, 6, 8, 9, 13, 14, 12], 0, HashRef], # 15
  [Subscript, {kind: array}, [2, 12], ~, Scalar, 4], # 16
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [15, 16], 15, Unknown, 4, true], # 17
  [Return, {implicit: true}, [17], 17, ~, 17]]} # 18
POSIX::SigAction::safe: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: SAFE}, ~, ~, Str], # 4
  [Coerce, {from_repr: Array, to_repr: Num}, [1], ~, Num], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [NumGt, ~, [5, 6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 1}, [8]], # 9
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 10
  [MemStart], # 11
  [Subscript, {kind: array}, [1, 6], ~, Scalar, 11], # 12
  [Proj, {index: 0}, [8]], # 13
  [Assign, ~, [10, 12], 13, Scalar, 11, true], # 14
  [Region, {head: 8}, [9, 14]], # 15
  [Phi, {memory: true, predecessors: [9, 13], region: 15}, [11, 14], ~, Unknown], # 16
  [Subscript, {kind: hash}, [3, 4], 15, Scalar, 16, true], # 17
  [Return, {implicit: true}, [17], 17, ~, 17]]} # 18
POSIX::SigRt::CLEAR: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: "%", symbol: SIG}, ~, ~, Hash], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 561, name: POSIX::SigRt::_exist, package: POSIX::SigRt, param_names: [], shares_args: true, want: void}, ~, 0, List, 2, true], # 3
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 561, name: POSIX::SIGRTMAX, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar, xs: true}, ~, 3, Unknown, 3, true], # 4
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 561, name: POSIX::SIGRTMIN, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar, xs: true}, ~, 4, Unknown, 4, true], # 5
  [Range, ~, [5, 4], ~, List], # 6
  [Delete, {kind: hash}, [1, 6], 5, Scalar, 5, true], # 7
  [ArrayLiteral, ~, [7], ~, List], # 8
  [Return, {implicit: true}, [8], 7, ~, 7]]} # 9
POSIX::SigRt::DELETE: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: "%", symbol: SIG}, ~, ~, Hash], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 560, name: POSIX::SigRt::_check, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar}, ~, 0, Unknown, 2, true], # 3
  [Delete, {kind: hash}, [1, 3], 3, Scalar, 3, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
POSIX::SigRt::EXISTS: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 554, name: POSIX::SigRt::_exist, package: POSIX::SigRt, param_names: [], shares_args: true}, ~, 0, List, 1, true], # 2
  [Return, {implicit: true}, [2], 2, ~, 2]]} # 3
POSIX::SigRt::FETCH: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: POSIX::SigAction}, ~, ~, Str], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 555, name: POSIX::SigRt::_check, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar}, ~, 0, Unknown, 2, true], # 3
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 3], # 4
  [Assign, ~, [4, 3], 3, Unknown, 3, true], # 5
  [Call, {class_name: POSIX::SigAction, dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 556, name: new, package: POSIX::SigRt, param_names: [], want: scalar}, [1], 5, Object, 5, true], # 6
  [PadAccess, {sigil: $, symbol: oa}, ~, ~, Unknown, 6], # 7
  [Assign, ~, [7, 6], 6, Object, 6, true], # 8
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 8], # 9
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 10
  [PadAccess, {sigil: $, symbol: oa}, ~, ~, Unknown, 8], # 11
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 557, name: POSIX::sigaction, package: POSIX::SigRt, param_names: [], want: void, xs: true}, [9, 10, 11], 8, Unknown, 8, true], # 12
  [PadAccess, {sigil: $, symbol: oa}, ~, ~, Unknown, 12], # 13
  [Constant, {const_type: string, value: HANDLER}, ~, ~, Str], # 14
  [Subscript, {kind: hash}, [13, 14], 12, Scalar, 12, true], # 15
  [Return, ~, [15], 15, ~, 15]]} # 16
POSIX::SigRt::SCALAR: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 562, name: POSIX::SigRt::_croak, package: POSIX::SigRt, param_names: [], shares_args: true, want: void}, ~, 0, "Maybe[Boolean]", 1, true], # 2
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _sigrtn}, ~, ~, Scalar, 2], # 3
  [Coerce, {from_repr: Scalar, to_repr: Num}, [3], ~, Num], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Add, ~, [4, 5], ~, Num], # 6
  [Return, {implicit: true}, [6], 2, ~, 2]]} # 7
POSIX::SigRt::STORE: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 559, name: POSIX::SigRt::_check, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar}, ~, 0, Unknown, 1, true], # 2
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 2], # 3
  [Assign, ~, [3, 2], 2, Unknown, 2, true], # 4
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 4], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [6, 7], ~, Scalar], # 8
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: SIGACTION_FLAGS}, ~, ~, Scalar, 4], # 9
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 559, name: POSIX::SigRt::new, package: POSIX::SigRt, param_names: []}, [5, 8, 9], 4, Unknown, 4, true], # 10
  [Return, {implicit: true}, [10], 10, ~, 10]]} # 11
POSIX::SigRt::_check: {start: 0, returns: [29], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown], # 1
  [PadAccess, {sigil: $, symbol: ok}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 541, name: POSIX::SigRt::_exist, package: POSIX::SigRt, param_names: [], shares_args: true, want: list}, ~, 0, List, 3, true], # 4
  [Assign, {targets: 2}, [1, 2, 4], 4, List, 4, true], # 5
  [If, ~, [5, 2], 5], # 6
  [Proj, {index: 0}, [6]], # 7
  [Constant, {const_type: string, value: "No POSIX::SigRt signal "}, ~, ~, Str], # 8
  [ArgsSource, ~, ~, ~, Array], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [9, 10], ~, Scalar, 5], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [8, 12], ~, Str], # 13
  [Constant, {const_type: string, value: " (valid range SIGRTMIN..SIGRTMAX, or "}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMIN}, ~, ~, Scalar, 5], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Concat, ~, [15, 17], ~, Str], # 18
  [Constant, {const_type: string, value: ".."}, ~, ~, Str], # 19
  [Concat, ~, [18, 19], ~, Str], # 20
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMAX}, ~, ~, Scalar, 5], # 21
  [Coerce, {from_repr: Unknown, to_repr: Str}, [21], ~, Str], # 22
  [Concat, ~, [20, 22], ~, Str], # 23
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 24
  [Concat, ~, [23, 24], ~, Str], # 25
  [Proj, {index: 1}, [6]], # 26
  [Unwind, {file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 542}, [25], 26, ~, 5], # 27
  [Region, {head: 6}, [7, 27]], # 28
  [Return, ~, [1], 28, ~, 5]]} # 29
POSIX::SigRt::_croak: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _sigrtn}, ~, ~, Scalar, 1], # 2
  [Defined, ~, [2], ~, Boolean], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 1}, [4]], # 5
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 521, name: POSIX::SigRt::_init, package: POSIX::SigRt, param_names: [], shares_args: true, want: void}, ~, 5, Num, 1, true], # 6
  [Proj, {index: 0}, [4]], # 7
  [Region, {head: 4}, [7, 6]], # 8
  [Phi, {memory: true, predecessors: [7, 5], region: 8}, [1, 6], ~, Unknown], # 9
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _sigrtn}, ~, ~, Scalar, 9], # 10
  [Defined, ~, [10], ~, Boolean], # 11
  [Coerce, {from_repr: Scalar, to_repr: Num}, [10], ~, Num], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [NumGt, ~, [12, 13], ~, Boolean], # 14
  [And, ~, [11, 14], ~, Boolean], # 15
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 16
  [Or, ~, [15, 16], ~, "Maybe[Boolean]"], # 17
  [If, ~, [8, 15], 8], # 18
  [Proj, {index: 0}, [18]], # 19
  [Constant, {const_type: string, value: "POSIX::SigRt not available"}, ~, ~, Str], # 20
  [Proj, {index: 1}, [18]], # 21
  [Unwind, {file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 522}, [20], 21, ~, 9], # 22
  [Region, {head: 18}, [19, 22]], # 23
  [Return, {implicit: true}, [17], 23, ~, 9]]} # 24
POSIX::SigRt::_exist: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 535, name: POSIX::SigRt::_getsig, package: POSIX::SigRt, param_names: [], want: scalar}, [3], 0, Unknown, 4, true], # 5
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMIN}, ~, ~, Scalar, 5], # 6
  [Coerce, {from_repr: Scalar, to_repr: Num}, [6], ~, Num], # 7
  [NumGe, ~, [5, 7], ~, Boolean], # 8
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMAX}, ~, ~, Scalar, 5], # 9
  [Coerce, {from_repr: Scalar, to_repr: Num}, [9], ~, Num], # 10
  [NumLe, ~, [5, 10], ~, Boolean], # 11
  [And, ~, [8, 11], ~, Boolean], # 12
  [ArrayLiteral, ~, [5, 12], ~, List], # 13
  [Coerce, {from_repr: List, to_repr: Scalar}, [12], ~, Scalar], # 14
  [Return, {implicit: true}, [13, 14], 5, ~, 5]]} # 15
POSIX::SigRt::_getsig: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 526, name: POSIX::SigRt::_croak, package: POSIX::SigRt, param_names: [], shares_args: true, want: void}, ~, 0, "Maybe[Boolean]", 3, true], # 4
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 4], # 5
  [Coerce, {from_repr: Scalar, to_repr: Str}, [5], ~, Str], # 6
  [RegexMatch, {flags: "", pattern: "^(?:(?:SIG)?RT)?MIN(\\s*\\+\\s*(\\d+))?$"}, [6], ~, Boolean], # 7
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMIN}, ~, ~, Scalar, 4], # 8
  [Coerce, {from_repr: Scalar, to_repr: Num}, [8], ~, Num], # 9
  [RegexCapture, {"n": 1}, [7], ~, Str], # 10
  [Or, ~, [10, 2], ~, Str], # 11
  [Coerce, {from_repr: Str, to_repr: Num}, [11], ~, Num], # 12
  [Add, ~, [9, 12], ~, Num], # 13
  [TernaryExpr, {rebind_arm: 1}, [7, 13, 5], 4, Unknown], # 14
  [Return, ~, [14], 14, ~, 4]]} # 15
POSIX::SigRt::_init: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMAX}, ~, ~, Scalar], # 1
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMIN}, ~, ~, Scalar], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 515, name: POSIX::SIGRTMIN, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar, xs: true}, ~, 0, Unknown, 3, true], # 4
  [EntryWrite, ~, [2, 4], 4, Unknown, 4, true], # 5
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 516, name: POSIX::SIGRTMAX, package: POSIX::SigRt, param_names: [], shares_args: true, want: scalar, xs: true}, ~, 5, Unknown, 5, true], # 6
  [EntryWrite, ~, [1, 6], 6, Unknown, 6, true], # 7
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMAX}, ~, ~, Scalar, 7], # 8
  [Coerce, {from_repr: Scalar, to_repr: Num}, [8], ~, Num], # 9
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _SIGRTMIN}, ~, ~, Scalar, 7], # 10
  [Coerce, {from_repr: Scalar, to_repr: Num}, [10], ~, Num], # 11
  [Subtract, ~, [9, 11], ~, Num], # 12
  [EntryDef, {package: POSIX::SigRt, sigil: $, symbol: _sigrtn}, ~, ~, Scalar], # 13
  [EntryWrite, ~, [13, 12], 7, Unknown, 7, true], # 14
  [Return, {implicit: true}, [12], 14, ~, 14]]} # 15
POSIX::SigRt::new: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: POSIX::SigAction}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: POSIX::SigSet}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 3], # 4
  [PadAccess, {sigil: $, symbol: handler}, ~, ~, Unknown, 3], # 5
  [PadAccess, {sigil: $, symbol: flags}, ~, ~, Unknown, 3], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Assign, {targets: 3}, [4, 5, 6, 7], 0, List, 3, true], # 8
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 8], # 9
  [Call, {class_name: POSIX::SigSet, dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 549, name: new, package: POSIX::SigRt, param_names: [], want: scalar}, [2, 9], 8, Object, 8, true], # 10
  [PadAccess, {sigil: $, symbol: sigset}, ~, ~, Unknown, 10], # 11
  [Assign, ~, [11, 10], 10, Object, 10, true], # 12
  [PadAccess, {sigil: $, symbol: handler}, ~, ~, Unknown, 12], # 13
  [PadAccess, {sigil: $, symbol: sigset}, ~, ~, Unknown, 12], # 14
  [PadAccess, {sigil: $, symbol: flags}, ~, ~, Unknown, 12], # 15
  [Call, {class_name: POSIX::SigAction, dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 550, name: new, package: POSIX::SigRt, param_names: [], want: scalar}, [1, 13, 14, 15], 12, Object, 12, true], # 16
  [PadAccess, {sigil: $, symbol: sigact}, ~, ~, Unknown, 16], # 17
  [Assign, ~, [17, 16], 16, Object, 16, true], # 18
  [PadAccess, {sigil: $, symbol: rtsig}, ~, ~, Unknown, 18], # 19
  [PadAccess, {sigil: $, symbol: sigact}, ~, ~, Unknown, 18], # 20
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 551, name: POSIX::sigaction, package: POSIX::SigRt, param_names: [], xs: true}, [19, 20], 18, Unknown, 18, true], # 21
  [Return, {implicit: true}, [21], 21, ~, 21]]} # 22
POSIX::import: {start: 0, returns: [66], nodes: [
  [Start], # 0
  [EntryDef, {package: Exporter, sigil: $, symbol: ExportLevel}, ~, ~, Scalar], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [4], 0, Scalar, 5, true], # 6
  [PadAccess, {sigil: $, symbol: pkg}, ~, ~, Unknown, 6], # 7
  [Assign, ~, [7, 6], 6, Scalar, 6, true], # 8
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: loaded}, ~, ~, Unknown, 8], # 9
  [Increment, ~, [9], ~, Scalar], # 10
  [Assign, ~, [9, 10], 8, Scalar, 8, true], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [DefinedOr, ~, [9, 12], ~, Scalar], # 13
  [If, ~, [11, 13], 11], # 14
  [Proj, {index: 1}, [14]], # 15
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 177, name: POSIX::load_imports, package: POSIX, param_names: [], want: void}, ~, 15, Unknown, 11, true], # 16
  [Proj, {index: 0}, [14]], # 17
  [Region, {head: 14}, [17, 16]], # 18
  [Phi, {memory: true, predecessors: [17, 15], region: 18}, [11, 16], ~, Unknown], # 19
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar, 19], # 20
  [Loop, {bound: entry}, [18], 18], # 21
  [Proj, {index: 1}, [21]], # 22
  [Region, {head: 21}, [22]], # 23
  [Phi, {memory: true, region: 21}, [19, 91], ~, Unknown], # 24
  [Phi, {memory: true, region: 23}, [24], ~, Unknown], # 25
  [EntryWrite, ~, [3, 20], 23, Unknown, 25, true], # 26
  [Loop, {bound: entry}, [26], 26], # 27
  [Proj, {index: 1}, [27]], # 28
  [Region, {head: 27}, [28]], # 29
  [ArrayLiteral, ~, ~, ~, Array], # 30
  [Phi, {region: 27}, [30, 80], ~, Array], # 31
  [Phi, {memory: true, region: 27}, [26, 32], ~, Unknown], # 32
  [Phi, {memory: true, region: 29}, [32], ~, Unknown], # 33
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [31], ~, List, 33], # 34
  [ArrayLiteral, {sigil: "@", symbol: unimpl}, [34], ~, Array], # 35
  [Count, ~, [35], ~, Int, 33], # 36
  [If, ~, [29, 36], 29], # 37
  [Proj, {index: 1}, [37]], # 38
  [Constant, {const_type: string, value: "Unimplemented: "}, ~, ~, Str], # 39
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 40
  [ArrayLiteral, ~, ~, ~, Array], # 41
  [Proj, {index: 0}, [37]], # 42
  [Loop, {bound: entry}, [42], 42], # 43
  [Proj, {index: 1}, [43]], # 44
  [Region, {head: 43}, [44]], # 45
  [Loop, {bound: entry}, [45], 45], # 46
  [Phi, {region: 46}, [41, 125], ~, Array], # 47
  [Phi, {memory: true, region: 43}, [33, 117], ~, Unknown], # 48
  [Phi, {memory: true, region: 45}, [48], ~, Unknown], # 49
  [Phi, {memory: true, region: 46}, [49, 50], ~, Unknown], # 50
  [Proj, {index: 1}, [46]], # 51
  [Region, {head: 46}, [51]], # 52
  [Phi, {memory: true, region: 52}, [50], ~, Unknown], # 53
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [40, 47], ~, Str, 53], # 54
  [Concat, ~, [39, 54], ~, Str], # 55
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 56
  [Concat, ~, [55, 56], ~, Str], # 57
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 188, name: POSIX::croak, package: POSIX, param_names: [], want: void}, [57], 52, Unknown, 53, true], # 58
  [Region, {head: 37}, [38, 58]], # 59
  [Phi, {memory: true, predecessors: [38, 42], region: 59}, [33, 58], ~, Unknown], # 60
  [EntryWrite, ~, [1, 2], 59, Unknown, 60, true], # 61
  [PadAccess, {sigil: $, symbol: pkg}, ~, ~, Unknown, 61], # 62
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 192, name: Exporter::import, package: POSIX, param_names: []}, [62, 4], 61, Unknown, 61, true], # 63
  [EntryDef, {package: Exporter, sigil: $, symbol: ExportLevel}, ~, ~, Scalar, 60], # 64
  [EntryWrite, ~, [1, 64], 63, Unknown, 63, true], # 65
  [Return, {implicit: true}, [63], 65, ~, 65], # 66
  [ArrayLiteral, ~, [4], ~, Array], # 67
  [Count, ~, [4], ~, Int, 26], # 68
  [Count, ~, [4], ~, Int, 32], # 69
  [Phi, {region: 27}, [12, 82], ~, Int], # 70
  [Subscript, {kind: array}, [4, 70], ~, Scalar, 32], # 71
  [Count, ~, [67], ~, Int, 19], # 72
  [Count, ~, [67], ~, Int, 24], # 73
  [Phi, {region: 21}, [12, 81], ~, Int], # 74
  [Subscript, {kind: array}, [67, 74], ~, Scalar, 24], # 75
  [Subscript, {kind: array}, [67, 74], ~, Scalar], # 76
  [NumGt, ~, [69, 70], 27, Boolean], # 77
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: replacement}, ~, ~, Hash], # 78
  [Exists, {kind: hash}, [78, 71], ~, Boolean, 32], # 79
  [ListAppend, {collector: grep}, [31, 71, 79], ~, Array], # 80
  [Add, ~, [74, 2], ~, Int], # 81
  [Add, ~, [70, 2], ~, Int], # 82
  [Phi, {region: 43}, [12, 84], ~, Int], # 83
  [Add, ~, [83, 2], ~, Int], # 84
  [Phi, {region: 46}, [12, 86], ~, Int], # 85
  [Add, ~, [85, 2], ~, Int], # 86
  [NumGt, ~, [73, 74], 21, Boolean], # 87
  [Proj, {index: 0}, [21]], # 88
  [RegexSubst, {flags: "", pattern: "^(?=\\w+_h$)", replacement: ":"}, [75], 88, Str, 24, true], # 89
  [EntryWrite, ~, [3, 89], 89, Unknown, 89, true], # 90
  [Assign, ~, [76, 89], 90, Str, 90, true], # 91
  [Proj, {index: 0}, [27]], # 92
  [Count, ~, [35], ~, Int, 48], # 93
  [NumGt, ~, [93, 83], 43, Boolean], # 94
  [Proj, {index: 0}, [43]], # 95
  [Exists, {kind: array}, [35, 83], 95, Boolean, 48], # 96
  [Subscript, {kind: array}, [35, 83], ~, Scalar], # 97
  [Subscript, {kind: array}, [35, 83], ~, Scalar, 48], # 98
  [Subscript, {kind: array}, [35, 83], ~, Scalar, 48], # 99
  [PostfixDeref, {sigil: "@"}, [35], ~, Array, 49], # 100
  [Count, ~, [100], ~, Int, 50], # 101
  [NumGt, ~, [101, 85], 46, Boolean], # 102
  [Subscript, {kind: array}, [100, 85], ~, Scalar, 50], # 103
  [Constant, {const_type: string, value: "Unimplemented: POSIX::"}, ~, ~, Str], # 104
  [Ref, ~, [97], ~, ScalarRef], # 105
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 106
  [TernaryExpr, ~, [96, 105, 106], 96, "Maybe[ScalarRef]"], # 107
  [PostfixDeref, {sigil: $}, [107], ~, Scalar, 48], # 108
  [TernaryExpr, ~, [96, 108, 98], 107, Scalar], # 109
  [Coerce, {from_repr: Scalar, to_repr: Str}, [109], ~, Str], # 110
  [Concat, ~, [104, 110], ~, Str], # 111
  [Constant, {const_type: string, value: "(): "}, ~, ~, Str], # 112
  [Concat, ~, [111, 112], ~, Str], # 113
  [PostfixDeref, {sigil: $}, [107], ~, Scalar, 48], # 114
  [TernaryExpr, ~, [96, 114, 99], ~, Scalar], # 115
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 185, name: POSIX::unimplemented_message, package: POSIX, param_names: [], want: list}, [115], 109, Str, 48, true], # 116
  [Call, {dispatch_kind: builtin, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 185, name: warn, param_names: []}, [113, 116], 116, Boolean, 116, true], # 117
  [Coerce, {from_repr: Unknown, to_repr: Str}, [103], ~, Str], # 118
  [Count, ~, [100], ~, Int, 49], # 119
  [Proj, {index: 0}, [46]], # 120
  [Constant, {const_type: string, value: "POSIX::"}, ~, ~, Str], # 121
  [Concat, ~, [121, 118], ~, Str], # 122
  [Constant, {const_type: string, value: "()"}, ~, ~, Str], # 123
  [Concat, ~, [122, 123], ~, Str], # 124
  [ListAppend, {collector: map}, [47, 124], ~, Array]]} # 125
POSIX::load_imports: {start: 0, returns: [898], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: Exporter.pm}, ~, ~, Str], # 1
  [EntryDef, {package: POSIX, sigil: "%", symbol: EXPORT_TAGS}, ~, ~, Hash], # 2
  [Constant, {const_type: string, value: assert_h}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: assert}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: NDEBUG}, ~, ~, Str], # 5
  [ArrayLiteral, ~, [4, 5], 0, ArrayRef], # 6
  [Constant, {const_type: string, value: ctype_h}, ~, ~, Str], # 7
  [ArrayLiteral, ~, ~, 6, ArrayRef], # 8
  [Constant, {const_type: string, value: dirent_h}, ~, ~, Str], # 9
  [ArrayLiteral, ~, ~, 8, ArrayRef], # 10
  [Constant, {const_type: string, value: errno_h}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: E2BIG}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: EACCES}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: EADDRINUSE}, ~, ~, Str], # 14
  [Constant, {const_type: string, value: EADDRNOTAVAIL}, ~, ~, Str], # 15
  [Constant, {const_type: string, value: EAFNOSUPPORT}, ~, ~, Str], # 16
  [Constant, {const_type: string, value: EAGAIN}, ~, ~, Str], # 17
  [Constant, {const_type: string, value: EALREADY}, ~, ~, Str], # 18
  [Constant, {const_type: string, value: EBADF}, ~, ~, Str], # 19
  [Constant, {const_type: string, value: EBADMSG}, ~, ~, Str], # 20
  [Constant, {const_type: string, value: EBUSY}, ~, ~, Str], # 21
  [Constant, {const_type: string, value: ECANCELED}, ~, ~, Str], # 22
  [Constant, {const_type: string, value: ECHILD}, ~, ~, Str], # 23
  [Constant, {const_type: string, value: ECONNABORTED}, ~, ~, Str], # 24
  [Constant, {const_type: string, value: ECONNREFUSED}, ~, ~, Str], # 25
  [Constant, {const_type: string, value: ECONNRESET}, ~, ~, Str], # 26
  [Constant, {const_type: string, value: EDEADLK}, ~, ~, Str], # 27
  [Constant, {const_type: string, value: EDESTADDRREQ}, ~, ~, Str], # 28
  [Constant, {const_type: string, value: EDOM}, ~, ~, Str], # 29
  [Constant, {const_type: string, value: EDQUOT}, ~, ~, Str], # 30
  [Constant, {const_type: string, value: EEXIST}, ~, ~, Str], # 31
  [Constant, {const_type: string, value: EFAULT}, ~, ~, Str], # 32
  [Constant, {const_type: string, value: EFBIG}, ~, ~, Str], # 33
  [Constant, {const_type: string, value: EHOSTDOWN}, ~, ~, Str], # 34
  [Constant, {const_type: string, value: EHOSTUNREACH}, ~, ~, Str], # 35
  [Constant, {const_type: string, value: EIDRM}, ~, ~, Str], # 36
  [Constant, {const_type: string, value: EILSEQ}, ~, ~, Str], # 37
  [Constant, {const_type: string, value: EINPROGRESS}, ~, ~, Str], # 38
  [Constant, {const_type: string, value: EINTR}, ~, ~, Str], # 39
  [Constant, {const_type: string, value: EINVAL}, ~, ~, Str], # 40
  [Constant, {const_type: string, value: EIO}, ~, ~, Str], # 41
  [Constant, {const_type: string, value: EISCONN}, ~, ~, Str], # 42
  [Constant, {const_type: string, value: EISDIR}, ~, ~, Str], # 43
  [Constant, {const_type: string, value: ELOOP}, ~, ~, Str], # 44
  [Constant, {const_type: string, value: EMFILE}, ~, ~, Str], # 45
  [Constant, {const_type: string, value: EMLINK}, ~, ~, Str], # 46
  [Constant, {const_type: string, value: EMSGSIZE}, ~, ~, Str], # 47
  [Constant, {const_type: string, value: ENAMETOOLONG}, ~, ~, Str], # 48
  [Constant, {const_type: string, value: ENETDOWN}, ~, ~, Str], # 49
  [Constant, {const_type: string, value: ENETRESET}, ~, ~, Str], # 50
  [Constant, {const_type: string, value: ENETUNREACH}, ~, ~, Str], # 51
  [Constant, {const_type: string, value: ENFILE}, ~, ~, Str], # 52
  [Constant, {const_type: string, value: ENOBUFS}, ~, ~, Str], # 53
  [Constant, {const_type: string, value: ENODATA}, ~, ~, Str], # 54
  [Constant, {const_type: string, value: ENODEV}, ~, ~, Str], # 55
  [Constant, {const_type: string, value: ENOENT}, ~, ~, Str], # 56
  [Constant, {const_type: string, value: ENOEXEC}, ~, ~, Str], # 57
  [Constant, {const_type: string, value: ENOLCK}, ~, ~, Str], # 58
  [Constant, {const_type: string, value: ENOLINK}, ~, ~, Str], # 59
  [Constant, {const_type: string, value: ENOMEM}, ~, ~, Str], # 60
  [Constant, {const_type: string, value: ENOMSG}, ~, ~, Str], # 61
  [Constant, {const_type: string, value: ENOPROTOOPT}, ~, ~, Str], # 62
  [Constant, {const_type: string, value: ENOSPC}, ~, ~, Str], # 63
  [Constant, {const_type: string, value: ENOSR}, ~, ~, Str], # 64
  [Constant, {const_type: string, value: ENOSTR}, ~, ~, Str], # 65
  [Constant, {const_type: string, value: ENOSYS}, ~, ~, Str], # 66
  [Constant, {const_type: string, value: ENOTBLK}, ~, ~, Str], # 67
  [Constant, {const_type: string, value: ENOTCONN}, ~, ~, Str], # 68
  [Constant, {const_type: string, value: ENOTDIR}, ~, ~, Str], # 69
  [Constant, {const_type: string, value: ENOTEMPTY}, ~, ~, Str], # 70
  [Constant, {const_type: string, value: ENOTRECOVERABLE}, ~, ~, Str], # 71
  [Constant, {const_type: string, value: ENOTSOCK}, ~, ~, Str], # 72
  [Constant, {const_type: string, value: ENOTSUP}, ~, ~, Str], # 73
  [Constant, {const_type: string, value: ENOTTY}, ~, ~, Str], # 74
  [Constant, {const_type: string, value: ENXIO}, ~, ~, Str], # 75
  [Constant, {const_type: string, value: EOPNOTSUPP}, ~, ~, Str], # 76
  [Constant, {const_type: string, value: EOTHER}, ~, ~, Str], # 77
  [Constant, {const_type: string, value: EOVERFLOW}, ~, ~, Str], # 78
  [Constant, {const_type: string, value: EOWNERDEAD}, ~, ~, Str], # 79
  [Constant, {const_type: string, value: EPERM}, ~, ~, Str], # 80
  [Constant, {const_type: string, value: EPFNOSUPPORT}, ~, ~, Str], # 81
  [Constant, {const_type: string, value: EPIPE}, ~, ~, Str], # 82
  [Constant, {const_type: string, value: EPROCLIM}, ~, ~, Str], # 83
  [Constant, {const_type: string, value: EPROTO}, ~, ~, Str], # 84
  [Constant, {const_type: string, value: EPROTONOSUPPORT}, ~, ~, Str], # 85
  [Constant, {const_type: string, value: EPROTOTYPE}, ~, ~, Str], # 86
  [Constant, {const_type: string, value: ERANGE}, ~, ~, Str], # 87
  [Constant, {const_type: string, value: EREMOTE}, ~, ~, Str], # 88
  [Constant, {const_type: string, value: ERESTART}, ~, ~, Str], # 89
  [Constant, {const_type: string, value: EROFS}, ~, ~, Str], # 90
  [Constant, {const_type: string, value: ESHUTDOWN}, ~, ~, Str], # 91
  [Constant, {const_type: string, value: ESOCKTNOSUPPORT}, ~, ~, Str], # 92
  [Constant, {const_type: string, value: ESPIPE}, ~, ~, Str], # 93
  [Constant, {const_type: string, value: ESRCH}, ~, ~, Str], # 94
  [Constant, {const_type: string, value: ESTALE}, ~, ~, Str], # 95
  [Constant, {const_type: string, value: ETIME}, ~, ~, Str], # 96
  [Constant, {const_type: string, value: ETIMEDOUT}, ~, ~, Str], # 97
  [Constant, {const_type: string, value: ETOOMANYREFS}, ~, ~, Str], # 98
  [Constant, {const_type: string, value: ETXTBSY}, ~, ~, Str], # 99
  [Constant, {const_type: string, value: EUSERS}, ~, ~, Str], # 100
  [Constant, {const_type: string, value: EWOULDBLOCK}, ~, ~, Str], # 101
  [Constant, {const_type: string, value: EXDEV}, ~, ~, Str], # 102
  [Constant, {const_type: string, value: errno}, ~, ~, Str], # 103
  [ArrayLiteral, ~, [12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103], 10, ArrayRef], # 104
  [Constant, {const_type: string, value: fcntl_h}, ~, ~, Str], # 105
  [Constant, {const_type: string, value: FD_CLOEXEC}, ~, ~, Str], # 106
  [Constant, {const_type: string, value: F_DUPFD}, ~, ~, Str], # 107
  [Constant, {const_type: string, value: F_GETFD}, ~, ~, Str], # 108
  [Constant, {const_type: string, value: F_GETFL}, ~, ~, Str], # 109
  [Constant, {const_type: string, value: F_GETLK}, ~, ~, Str], # 110
  [Constant, {const_type: string, value: F_RDLCK}, ~, ~, Str], # 111
  [Constant, {const_type: string, value: F_SETFD}, ~, ~, Str], # 112
  [Constant, {const_type: string, value: F_SETFL}, ~, ~, Str], # 113
  [Constant, {const_type: string, value: F_SETLK}, ~, ~, Str], # 114
  [Constant, {const_type: string, value: F_SETLKW}, ~, ~, Str], # 115
  [Constant, {const_type: string, value: F_UNLCK}, ~, ~, Str], # 116
  [Constant, {const_type: string, value: F_WRLCK}, ~, ~, Str], # 117
  [Constant, {const_type: string, value: O_ACCMODE}, ~, ~, Str], # 118
  [Constant, {const_type: string, value: O_APPEND}, ~, ~, Str], # 119
  [Constant, {const_type: string, value: O_CREAT}, ~, ~, Str], # 120
  [Constant, {const_type: string, value: O_EXCL}, ~, ~, Str], # 121
  [Constant, {const_type: string, value: O_NOCTTY}, ~, ~, Str], # 122
  [Constant, {const_type: string, value: O_NONBLOCK}, ~, ~, Str], # 123
  [Constant, {const_type: string, value: O_RDONLY}, ~, ~, Str], # 124
  [Constant, {const_type: string, value: O_RDWR}, ~, ~, Str], # 125
  [Constant, {const_type: string, value: O_TRUNC}, ~, ~, Str], # 126
  [Constant, {const_type: string, value: O_WRONLY}, ~, ~, Str], # 127
  [Constant, {const_type: string, value: creat}, ~, ~, Str], # 128
  [Constant, {const_type: string, value: SEEK_CUR}, ~, ~, Str], # 129
  [Constant, {const_type: string, value: SEEK_END}, ~, ~, Str], # 130
  [Constant, {const_type: string, value: SEEK_SET}, ~, ~, Str], # 131
  [Constant, {const_type: string, value: S_IRGRP}, ~, ~, Str], # 132
  [Constant, {const_type: string, value: S_IROTH}, ~, ~, Str], # 133
  [Constant, {const_type: string, value: S_IRUSR}, ~, ~, Str], # 134
  [Constant, {const_type: string, value: S_IRWXG}, ~, ~, Str], # 135
  [Constant, {const_type: string, value: S_IRWXO}, ~, ~, Str], # 136
  [Constant, {const_type: string, value: S_IRWXU}, ~, ~, Str], # 137
  [Constant, {const_type: string, value: S_ISBLK}, ~, ~, Str], # 138
  [Constant, {const_type: string, value: S_ISCHR}, ~, ~, Str], # 139
  [Constant, {const_type: string, value: S_ISDIR}, ~, ~, Str], # 140
  [Constant, {const_type: string, value: S_ISFIFO}, ~, ~, Str], # 141
  [Constant, {const_type: string, value: S_ISGID}, ~, ~, Str], # 142
  [Constant, {const_type: string, value: S_ISLNK}, ~, ~, Str], # 143
  [Constant, {const_type: string, value: S_ISREG}, ~, ~, Str], # 144
  [Constant, {const_type: string, value: S_ISSOCK}, ~, ~, Str], # 145
  [Constant, {const_type: string, value: S_ISUID}, ~, ~, Str], # 146
  [Constant, {const_type: string, value: S_IWGRP}, ~, ~, Str], # 147
  [Constant, {const_type: string, value: S_IWOTH}, ~, ~, Str], # 148
  [Constant, {const_type: string, value: S_IWUSR}, ~, ~, Str], # 149
  [ArrayLiteral, ~, [106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149], 104, ArrayRef], # 150
  [Constant, {const_type: string, value: float_h}, ~, ~, Str], # 151
  [Constant, {const_type: string, value: DBL_DIG}, ~, ~, Str], # 152
  [Constant, {const_type: string, value: DBL_EPSILON}, ~, ~, Str], # 153
  [Constant, {const_type: string, value: DBL_MANT_DIG}, ~, ~, Str], # 154
  [Constant, {const_type: string, value: DBL_MAX}, ~, ~, Str], # 155
  [Constant, {const_type: string, value: DBL_MAX_10_EXP}, ~, ~, Str], # 156
  [Constant, {const_type: string, value: DBL_MAX_EXP}, ~, ~, Str], # 157
  [Constant, {const_type: string, value: DBL_MIN}, ~, ~, Str], # 158
  [Constant, {const_type: string, value: DBL_MIN_10_EXP}, ~, ~, Str], # 159
  [Constant, {const_type: string, value: DBL_MIN_EXP}, ~, ~, Str], # 160
  [Constant, {const_type: string, value: FLT_DIG}, ~, ~, Str], # 161
  [Constant, {const_type: string, value: FLT_EPSILON}, ~, ~, Str], # 162
  [Constant, {const_type: string, value: FLT_MANT_DIG}, ~, ~, Str], # 163
  [Constant, {const_type: string, value: FLT_MAX}, ~, ~, Str], # 164
  [Constant, {const_type: string, value: FLT_MAX_10_EXP}, ~, ~, Str], # 165
  [Constant, {const_type: string, value: FLT_MAX_EXP}, ~, ~, Str], # 166
  [Constant, {const_type: string, value: FLT_MIN}, ~, ~, Str], # 167
  [Constant, {const_type: string, value: FLT_MIN_10_EXP}, ~, ~, Str], # 168
  [Constant, {const_type: string, value: FLT_MIN_EXP}, ~, ~, Str], # 169
  [Constant, {const_type: string, value: FLT_RADIX}, ~, ~, Str], # 170
  [Constant, {const_type: string, value: FLT_ROUNDS}, ~, ~, Str], # 171
  [Constant, {const_type: string, value: LDBL_DIG}, ~, ~, Str], # 172
  [Constant, {const_type: string, value: LDBL_EPSILON}, ~, ~, Str], # 173
  [Constant, {const_type: string, value: LDBL_MANT_DIG}, ~, ~, Str], # 174
  [Constant, {const_type: string, value: LDBL_MAX}, ~, ~, Str], # 175
  [Constant, {const_type: string, value: LDBL_MAX_10_EXP}, ~, ~, Str], # 176
  [Constant, {const_type: string, value: LDBL_MAX_EXP}, ~, ~, Str], # 177
  [Constant, {const_type: string, value: LDBL_MIN}, ~, ~, Str], # 178
  [Constant, {const_type: string, value: LDBL_MIN_10_EXP}, ~, ~, Str], # 179
  [Constant, {const_type: string, value: LDBL_MIN_EXP}, ~, ~, Str], # 180
  [ArrayLiteral, ~, [152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180], 150, ArrayRef], # 181
  [Constant, {const_type: string, value: grp_h}, ~, ~, Str], # 182
  [ArrayLiteral, ~, ~, 181, ArrayRef], # 183
  [Constant, {const_type: string, value: limits_h}, ~, ~, Str], # 184
  [Constant, {const_type: string, value: ARG_MAX}, ~, ~, Str], # 185
  [Constant, {const_type: string, value: CHAR_BIT}, ~, ~, Str], # 186
  [Constant, {const_type: string, value: CHAR_MAX}, ~, ~, Str], # 187
  [Constant, {const_type: string, value: CHAR_MIN}, ~, ~, Str], # 188
  [Constant, {const_type: string, value: CHILD_MAX}, ~, ~, Str], # 189
  [Constant, {const_type: string, value: INT_MAX}, ~, ~, Str], # 190
  [Constant, {const_type: string, value: INT_MIN}, ~, ~, Str], # 191
  [Constant, {const_type: string, value: LINK_MAX}, ~, ~, Str], # 192
  [Constant, {const_type: string, value: LONG_MAX}, ~, ~, Str], # 193
  [Constant, {const_type: string, value: LONG_MIN}, ~, ~, Str], # 194
  [Constant, {const_type: string, value: MAX_CANON}, ~, ~, Str], # 195
  [Constant, {const_type: string, value: MAX_INPUT}, ~, ~, Str], # 196
  [Constant, {const_type: string, value: MB_LEN_MAX}, ~, ~, Str], # 197
  [Constant, {const_type: string, value: NAME_MAX}, ~, ~, Str], # 198
  [Constant, {const_type: string, value: NGROUPS_MAX}, ~, ~, Str], # 199
  [Constant, {const_type: string, value: OPEN_MAX}, ~, ~, Str], # 200
  [Constant, {const_type: string, value: PATH_MAX}, ~, ~, Str], # 201
  [Constant, {const_type: string, value: PIPE_BUF}, ~, ~, Str], # 202
  [Constant, {const_type: string, value: SCHAR_MAX}, ~, ~, Str], # 203
  [Constant, {const_type: string, value: SCHAR_MIN}, ~, ~, Str], # 204
  [Constant, {const_type: string, value: SHRT_MAX}, ~, ~, Str], # 205
  [Constant, {const_type: string, value: SHRT_MIN}, ~, ~, Str], # 206
  [Constant, {const_type: string, value: SSIZE_MAX}, ~, ~, Str], # 207
  [Constant, {const_type: string, value: STREAM_MAX}, ~, ~, Str], # 208
  [Constant, {const_type: string, value: TZNAME_MAX}, ~, ~, Str], # 209
  [Constant, {const_type: string, value: UCHAR_MAX}, ~, ~, Str], # 210
  [Constant, {const_type: string, value: UINT_MAX}, ~, ~, Str], # 211
  [Constant, {const_type: string, value: ULONG_MAX}, ~, ~, Str], # 212
  [Constant, {const_type: string, value: USHRT_MAX}, ~, ~, Str], # 213
  [Constant, {const_type: string, value: _POSIX_ARG_MAX}, ~, ~, Str], # 214
  [Constant, {const_type: string, value: _POSIX_CHILD_MAX}, ~, ~, Str], # 215
  [Constant, {const_type: string, value: _POSIX_LINK_MAX}, ~, ~, Str], # 216
  [Constant, {const_type: string, value: _POSIX_MAX_CANON}, ~, ~, Str], # 217
  [Constant, {const_type: string, value: _POSIX_MAX_INPUT}, ~, ~, Str], # 218
  [Constant, {const_type: string, value: _POSIX_NAME_MAX}, ~, ~, Str], # 219
  [Constant, {const_type: string, value: _POSIX_NGROUPS_MAX}, ~, ~, Str], # 220
  [Constant, {const_type: string, value: _POSIX_OPEN_MAX}, ~, ~, Str], # 221
  [Constant, {const_type: string, value: _POSIX_PATH_MAX}, ~, ~, Str], # 222
  [Constant, {const_type: string, value: _POSIX_PIPE_BUF}, ~, ~, Str], # 223
  [Constant, {const_type: string, value: _POSIX_SSIZE_MAX}, ~, ~, Str], # 224
  [Constant, {const_type: string, value: _POSIX_STREAM_MAX}, ~, ~, Str], # 225
  [Constant, {const_type: string, value: _POSIX_TZNAME_MAX}, ~, ~, Str], # 226
  [ArrayLiteral, ~, [185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226], 183, ArrayRef], # 227
  [Constant, {const_type: string, value: locale_h}, ~, ~, Str], # 228
  [Constant, {const_type: string, value: LC_ALL}, ~, ~, Str], # 229
  [Constant, {const_type: string, value: LC_COLLATE}, ~, ~, Str], # 230
  [Constant, {const_type: string, value: LC_CTYPE}, ~, ~, Str], # 231
  [Constant, {const_type: string, value: LC_MESSAGES}, ~, ~, Str], # 232
  [Constant, {const_type: string, value: LC_MONETARY}, ~, ~, Str], # 233
  [Constant, {const_type: string, value: LC_NUMERIC}, ~, ~, Str], # 234
  [Constant, {const_type: string, value: LC_TIME}, ~, ~, Str], # 235
  [Constant, {const_type: string, value: LC_IDENTIFICATION}, ~, ~, Str], # 236
  [Constant, {const_type: string, value: LC_MEASUREMENT}, ~, ~, Str], # 237
  [Constant, {const_type: string, value: LC_PAPER}, ~, ~, Str], # 238
  [Constant, {const_type: string, value: LC_TELEPHONE}, ~, ~, Str], # 239
  [Constant, {const_type: string, value: LC_ADDRESS}, ~, ~, Str], # 240
  [Constant, {const_type: string, value: LC_NAME}, ~, ~, Str], # 241
  [Constant, {const_type: string, value: LC_SYNTAX}, ~, ~, Str], # 242
  [Constant, {const_type: string, value: LC_TOD}, ~, ~, Str], # 243
  [Constant, {const_type: string, value: "NULL"}, ~, ~, Str], # 244
  [Constant, {const_type: string, value: localeconv}, ~, ~, Str], # 245
  [Constant, {const_type: string, value: setlocale}, ~, ~, Str], # 246
  [ArrayLiteral, ~, [229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246], 227, ArrayRef], # 247
  [Constant, {const_type: string, value: math_h}, ~, ~, Str], # 248
  [Constant, {const_type: string, value: FP_ILOGB0}, ~, ~, Str], # 249
  [Constant, {const_type: string, value: FP_ILOGBNAN}, ~, ~, Str], # 250
  [Constant, {const_type: string, value: FP_INFINITE}, ~, ~, Str], # 251
  [Constant, {const_type: string, value: FP_NAN}, ~, ~, Str], # 252
  [Constant, {const_type: string, value: FP_NORMAL}, ~, ~, Str], # 253
  [Constant, {const_type: string, value: FP_SUBNORMAL}, ~, ~, Str], # 254
  [Constant, {const_type: string, value: FP_ZERO}, ~, ~, Str], # 255
  [Constant, {const_type: string, value: M_1_PI}, ~, ~, Str], # 256
  [Constant, {const_type: string, value: M_2_PI}, ~, ~, Str], # 257
  [Constant, {const_type: string, value: M_2_SQRTPI}, ~, ~, Str], # 258
  [Constant, {const_type: string, value: M_E}, ~, ~, Str], # 259
  [Constant, {const_type: string, value: M_LN10}, ~, ~, Str], # 260
  [Constant, {const_type: string, value: M_LN2}, ~, ~, Str], # 261
  [Constant, {const_type: string, value: M_LOG10E}, ~, ~, Str], # 262
  [Constant, {const_type: string, value: M_LOG2E}, ~, ~, Str], # 263
  [Constant, {const_type: string, value: M_PI}, ~, ~, Str], # 264
  [Constant, {const_type: string, value: M_PI_2}, ~, ~, Str], # 265
  [Constant, {const_type: string, value: M_PI_4}, ~, ~, Str], # 266
  [Constant, {const_type: string, value: M_SQRT1_2}, ~, ~, Str], # 267
  [Constant, {const_type: string, value: M_SQRT2}, ~, ~, Str], # 268
  [Constant, {const_type: string, value: HUGE_VAL}, ~, ~, Str], # 269
  [Constant, {const_type: string, value: INFINITY}, ~, ~, Str], # 270
  [Constant, {const_type: string, value: NAN}, ~, ~, Str], # 271
  [Constant, {const_type: string, value: acos}, ~, ~, Str], # 272
  [Constant, {const_type: string, value: asin}, ~, ~, Str], # 273
  [Constant, {const_type: string, value: atan}, ~, ~, Str], # 274
  [Constant, {const_type: string, value: ceil}, ~, ~, Str], # 275
  [Constant, {const_type: string, value: cosh}, ~, ~, Str], # 276
  [Constant, {const_type: string, value: fabs}, ~, ~, Str], # 277
  [Constant, {const_type: string, value: floor}, ~, ~, Str], # 278
  [Constant, {const_type: string, value: fmod}, ~, ~, Str], # 279
  [Constant, {const_type: string, value: frexp}, ~, ~, Str], # 280
  [Constant, {const_type: string, value: ldexp}, ~, ~, Str], # 281
  [Constant, {const_type: string, value: log10}, ~, ~, Str], # 282
  [Constant, {const_type: string, value: modf}, ~, ~, Str], # 283
  [Constant, {const_type: string, value: pow}, ~, ~, Str], # 284
  [Constant, {const_type: string, value: sinh}, ~, ~, Str], # 285
  [Constant, {const_type: string, value: tan}, ~, ~, Str], # 286
  [Constant, {const_type: string, value: tanh}, ~, ~, Str], # 287
  [ArrayLiteral, ~, [249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287], 247, ArrayRef], # 288
  [Constant, {const_type: string, value: pwd_h}, ~, ~, Str], # 289
  [ArrayLiteral, ~, ~, 288, ArrayRef], # 290
  [Constant, {const_type: string, value: setjmp_h}, ~, ~, Str], # 291
  [Constant, {const_type: string, value: longjmp}, ~, ~, Str], # 292
  [Constant, {const_type: string, value: setjmp}, ~, ~, Str], # 293
  [Constant, {const_type: string, value: siglongjmp}, ~, ~, Str], # 294
  [Constant, {const_type: string, value: sigsetjmp}, ~, ~, Str], # 295
  [ArrayLiteral, ~, [292, 293, 294, 295], 290, ArrayRef], # 296
  [Constant, {const_type: string, value: signal_h}, ~, ~, Str], # 297
  [Constant, {const_type: string, value: SA_NOCLDSTOP}, ~, ~, Str], # 298
  [Constant, {const_type: string, value: SA_NOCLDWAIT}, ~, ~, Str], # 299
  [Constant, {const_type: string, value: SA_NODEFER}, ~, ~, Str], # 300
  [Constant, {const_type: string, value: SA_ONSTACK}, ~, ~, Str], # 301
  [Constant, {const_type: string, value: SA_RESETHAND}, ~, ~, Str], # 302
  [Constant, {const_type: string, value: SA_RESTART}, ~, ~, Str], # 303
  [Constant, {const_type: string, value: SA_SIGINFO}, ~, ~, Str], # 304
  [Constant, {const_type: string, value: SIGABRT}, ~, ~, Str], # 305
  [Constant, {const_type: string, value: SIGALRM}, ~, ~, Str], # 306
  [Constant, {const_type: string, value: SIGCHLD}, ~, ~, Str], # 307
  [Constant, {const_type: string, value: SIGCONT}, ~, ~, Str], # 308
  [Constant, {const_type: string, value: SIGFPE}, ~, ~, Str], # 309
  [Constant, {const_type: string, value: SIGHUP}, ~, ~, Str], # 310
  [Constant, {const_type: string, value: SIGILL}, ~, ~, Str], # 311
  [Constant, {const_type: string, value: SIGINT}, ~, ~, Str], # 312
  [Constant, {const_type: string, value: SIGKILL}, ~, ~, Str], # 313
  [Constant, {const_type: string, value: SIGPIPE}, ~, ~, Str], # 314
  [Constant, {const_type: string, value: "%SIGRT"}, ~, ~, Str], # 315
  [Constant, {const_type: string, value: SIGRTMIN}, ~, ~, Str], # 316
  [Constant, {const_type: string, value: SIGRTMAX}, ~, ~, Str], # 317
  [Constant, {const_type: string, value: SIGQUIT}, ~, ~, Str], # 318
  [Constant, {const_type: string, value: SIGSEGV}, ~, ~, Str], # 319
  [Constant, {const_type: string, value: SIGSTOP}, ~, ~, Str], # 320
  [Constant, {const_type: string, value: SIGTERM}, ~, ~, Str], # 321
  [Constant, {const_type: string, value: SIGTSTP}, ~, ~, Str], # 322
  [Constant, {const_type: string, value: SIGTTIN}, ~, ~, Str], # 323
  [Constant, {const_type: string, value: SIGTTOU}, ~, ~, Str], # 324
  [Constant, {const_type: string, value: SIGUSR1}, ~, ~, Str], # 325
  [Constant, {const_type: string, value: SIGUSR2}, ~, ~, Str], # 326
  [Constant, {const_type: string, value: SIGBUS}, ~, ~, Str], # 327
  [Constant, {const_type: string, value: SIGPOLL}, ~, ~, Str], # 328
  [Constant, {const_type: string, value: SIGPROF}, ~, ~, Str], # 329
  [Constant, {const_type: string, value: SIGSYS}, ~, ~, Str], # 330
  [Constant, {const_type: string, value: SIGTRAP}, ~, ~, Str], # 331
  [Constant, {const_type: string, value: SIGURG}, ~, ~, Str], # 332
  [Constant, {const_type: string, value: SIGVTALRM}, ~, ~, Str], # 333
  [Constant, {const_type: string, value: SIGXCPU}, ~, ~, Str], # 334
  [Constant, {const_type: string, value: SIGXFSZ}, ~, ~, Str], # 335
  [Constant, {const_type: string, value: SIG_BLOCK}, ~, ~, Str], # 336
  [Constant, {const_type: string, value: SIG_DFL}, ~, ~, Str], # 337
  [Constant, {const_type: string, value: SIG_ERR}, ~, ~, Str], # 338
  [Constant, {const_type: string, value: SIG_IGN}, ~, ~, Str], # 339
  [Constant, {const_type: string, value: SIG_SETMASK}, ~, ~, Str], # 340
  [Constant, {const_type: string, value: SIG_UNBLOCK}, ~, ~, Str], # 341
  [Constant, {const_type: string, value: raise}, ~, ~, Str], # 342
  [Constant, {const_type: string, value: sigaction}, ~, ~, Str], # 343
  [Constant, {const_type: string, value: signal}, ~, ~, Str], # 344
  [Constant, {const_type: string, value: sigpending}, ~, ~, Str], # 345
  [Constant, {const_type: string, value: sigprocmask}, ~, ~, Str], # 346
  [Constant, {const_type: string, value: sigsuspend}, ~, ~, Str], # 347
  [ArrayLiteral, ~, [298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347], 296, ArrayRef], # 348
  [Constant, {const_type: string, value: stdarg_h}, ~, ~, Str], # 349
  [ArrayLiteral, ~, ~, 348, ArrayRef], # 350
  [Constant, {const_type: string, value: stddef_h}, ~, ~, Str], # 351
  [Constant, {const_type: string, value: offsetof}, ~, ~, Str], # 352
  [ArrayLiteral, ~, [244, 352], 350, ArrayRef], # 353
  [Constant, {const_type: string, value: stdio_h}, ~, ~, Str], # 354
  [Constant, {const_type: string, value: BUFSIZ}, ~, ~, Str], # 355
  [Constant, {const_type: string, value: EOF}, ~, ~, Str], # 356
  [Constant, {const_type: string, value: FILENAME_MAX}, ~, ~, Str], # 357
  [Constant, {const_type: string, value: L_ctermid}, ~, ~, Str], # 358
  [Constant, {const_type: string, value: L_cuserid}, ~, ~, Str], # 359
  [Constant, {const_type: string, value: TMP_MAX}, ~, ~, Str], # 360
  [Constant, {const_type: string, value: stderr}, ~, ~, Str], # 361
  [Constant, {const_type: string, value: stdin}, ~, ~, Str], # 362
  [Constant, {const_type: string, value: stdout}, ~, ~, Str], # 363
  [Constant, {const_type: string, value: clearerr}, ~, ~, Str], # 364
  [Constant, {const_type: string, value: fclose}, ~, ~, Str], # 365
  [Constant, {const_type: string, value: fdopen}, ~, ~, Str], # 366
  [Constant, {const_type: string, value: feof}, ~, ~, Str], # 367
  [Constant, {const_type: string, value: ferror}, ~, ~, Str], # 368
  [Constant, {const_type: string, value: fflush}, ~, ~, Str], # 369
  [Constant, {const_type: string, value: fgetc}, ~, ~, Str], # 370
  [Constant, {const_type: string, value: fgetpos}, ~, ~, Str], # 371
  [Constant, {const_type: string, value: fgets}, ~, ~, Str], # 372
  [Constant, {const_type: string, value: fopen}, ~, ~, Str], # 373
  [Constant, {const_type: string, value: fprintf}, ~, ~, Str], # 374
  [Constant, {const_type: string, value: fputc}, ~, ~, Str], # 375
  [Constant, {const_type: string, value: fputs}, ~, ~, Str], # 376
  [Constant, {const_type: string, value: fread}, ~, ~, Str], # 377
  [Constant, {const_type: string, value: freopen}, ~, ~, Str], # 378
  [Constant, {const_type: string, value: fscanf}, ~, ~, Str], # 379
  [Constant, {const_type: string, value: fseek}, ~, ~, Str], # 380
  [Constant, {const_type: string, value: fsetpos}, ~, ~, Str], # 381
  [Constant, {const_type: string, value: ftell}, ~, ~, Str], # 382
  [Constant, {const_type: string, value: fwrite}, ~, ~, Str], # 383
  [Constant, {const_type: string, value: getchar}, ~, ~, Str], # 384
  [Constant, {const_type: string, value: gets}, ~, ~, Str], # 385
  [Constant, {const_type: string, value: perror}, ~, ~, Str], # 386
  [Constant, {const_type: string, value: putc}, ~, ~, Str], # 387
  [Constant, {const_type: string, value: putchar}, ~, ~, Str], # 388
  [Constant, {const_type: string, value: puts}, ~, ~, Str], # 389
  [Constant, {const_type: string, value: remove}, ~, ~, Str], # 390
  [Constant, {const_type: string, value: rewind}, ~, ~, Str], # 391
  [Constant, {const_type: string, value: scanf}, ~, ~, Str], # 392
  [Constant, {const_type: string, value: setbuf}, ~, ~, Str], # 393
  [Constant, {const_type: string, value: setvbuf}, ~, ~, Str], # 394
  [Constant, {const_type: string, value: sscanf}, ~, ~, Str], # 395
  [Constant, {const_type: string, value: tmpfile}, ~, ~, Str], # 396
  [Constant, {const_type: string, value: tmpnam}, ~, ~, Str], # 397
  [Constant, {const_type: string, value: ungetc}, ~, ~, Str], # 398
  [Constant, {const_type: string, value: vfprintf}, ~, ~, Str], # 399
  [Constant, {const_type: string, value: vprintf}, ~, ~, Str], # 400
  [Constant, {const_type: string, value: vsprintf}, ~, ~, Str], # 401
  [ArrayLiteral, ~, [355, 356, 357, 358, 359, 244, 129, 130, 131, 208, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400, 401], 353, ArrayRef], # 402
  [Constant, {const_type: string, value: stdlib_h}, ~, ~, Str], # 403
  [Constant, {const_type: string, value: EXIT_FAILURE}, ~, ~, Str], # 404
  [Constant, {const_type: string, value: EXIT_SUCCESS}, ~, ~, Str], # 405
  [Constant, {const_type: string, value: MB_CUR_MAX}, ~, ~, Str], # 406
  [Constant, {const_type: string, value: RAND_MAX}, ~, ~, Str], # 407
  [Constant, {const_type: string, value: abort}, ~, ~, Str], # 408
  [Constant, {const_type: string, value: atexit}, ~, ~, Str], # 409
  [Constant, {const_type: string, value: atof}, ~, ~, Str], # 410
  [Constant, {const_type: string, value: atoi}, ~, ~, Str], # 411
  [Constant, {const_type: string, value: atol}, ~, ~, Str], # 412
  [Constant, {const_type: string, value: bsearch}, ~, ~, Str], # 413
  [Constant, {const_type: string, value: calloc}, ~, ~, Str], # 414
  [Constant, {const_type: string, value: div}, ~, ~, Str], # 415
  [Constant, {const_type: string, value: free}, ~, ~, Str], # 416
  [Constant, {const_type: string, value: getenv}, ~, ~, Str], # 417
  [Constant, {const_type: string, value: labs}, ~, ~, Str], # 418
  [Constant, {const_type: string, value: ldiv}, ~, ~, Str], # 419
  [Constant, {const_type: string, value: malloc}, ~, ~, Str], # 420
  [Constant, {const_type: string, value: mblen}, ~, ~, Str], # 421
  [Constant, {const_type: string, value: mbstowcs}, ~, ~, Str], # 422
  [Constant, {const_type: string, value: mbtowc}, ~, ~, Str], # 423
  [Constant, {const_type: string, value: qsort}, ~, ~, Str], # 424
  [Constant, {const_type: string, value: realloc}, ~, ~, Str], # 425
  [Constant, {const_type: string, value: strtod}, ~, ~, Str], # 426
  [Constant, {const_type: string, value: strtol}, ~, ~, Str], # 427
  [Constant, {const_type: string, value: strtoul}, ~, ~, Str], # 428
  [Constant, {const_type: string, value: wcstombs}, ~, ~, Str], # 429
  [Constant, {const_type: string, value: wctomb}, ~, ~, Str], # 430
  [ArrayLiteral, ~, [404, 405, 406, 244, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430], 402, ArrayRef], # 431
  [Constant, {const_type: string, value: string_h}, ~, ~, Str], # 432
  [Constant, {const_type: string, value: memchr}, ~, ~, Str], # 433
  [Constant, {const_type: string, value: memcmp}, ~, ~, Str], # 434
  [Constant, {const_type: string, value: memcpy}, ~, ~, Str], # 435
  [Constant, {const_type: string, value: memmove}, ~, ~, Str], # 436
  [Constant, {const_type: string, value: memset}, ~, ~, Str], # 437
  [Constant, {const_type: string, value: strcat}, ~, ~, Str], # 438
  [Constant, {const_type: string, value: strchr}, ~, ~, Str], # 439
  [Constant, {const_type: string, value: strcmp}, ~, ~, Str], # 440
  [Constant, {const_type: string, value: strcoll}, ~, ~, Str], # 441
  [Constant, {const_type: string, value: strcpy}, ~, ~, Str], # 442
  [Constant, {const_type: string, value: strcspn}, ~, ~, Str], # 443
  [Constant, {const_type: string, value: strerror}, ~, ~, Str], # 444
  [Constant, {const_type: string, value: strlen}, ~, ~, Str], # 445
  [Constant, {const_type: string, value: strncat}, ~, ~, Str], # 446
  [Constant, {const_type: string, value: strncmp}, ~, ~, Str], # 447
  [Constant, {const_type: string, value: strncpy}, ~, ~, Str], # 448
  [Constant, {const_type: string, value: strpbrk}, ~, ~, Str], # 449
  [Constant, {const_type: string, value: strrchr}, ~, ~, Str], # 450
  [Constant, {const_type: string, value: strspn}, ~, ~, Str], # 451
  [Constant, {const_type: string, value: strstr}, ~, ~, Str], # 452
  [Constant, {const_type: string, value: strtok}, ~, ~, Str], # 453
  [Constant, {const_type: string, value: strxfrm}, ~, ~, Str], # 454
  [ArrayLiteral, ~, [244, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454], 431, ArrayRef], # 455
  [Constant, {const_type: string, value: sys_stat_h}, ~, ~, Str], # 456
  [Constant, {const_type: string, value: S_IXGRP}, ~, ~, Str], # 457
  [Constant, {const_type: string, value: S_IXOTH}, ~, ~, Str], # 458
  [Constant, {const_type: string, value: S_IXUSR}, ~, ~, Str], # 459
  [Constant, {const_type: string, value: fstat}, ~, ~, Str], # 460
  [Constant, {const_type: string, value: mkfifo}, ~, ~, Str], # 461
  [ArrayLiteral, ~, [132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 457, 458, 459, 460, 461], 455, ArrayRef], # 462
  [Constant, {const_type: string, value: sys_times_h}, ~, ~, Str], # 463
  [ArrayLiteral, ~, ~, 462, ArrayRef], # 464
  [Constant, {const_type: string, value: sys_types_h}, ~, ~, Str], # 465
  [ArrayLiteral, ~, ~, 464, ArrayRef], # 466
  [Constant, {const_type: string, value: sys_utsname_h}, ~, ~, Str], # 467
  [Constant, {const_type: string, value: uname}, ~, ~, Str], # 468
  [ArrayLiteral, ~, [468], 466, ArrayRef], # 469
  [Constant, {const_type: string, value: sys_wait_h}, ~, ~, Str], # 470
  [Constant, {const_type: string, value: WEXITSTATUS}, ~, ~, Str], # 471
  [Constant, {const_type: string, value: WIFEXITED}, ~, ~, Str], # 472
  [Constant, {const_type: string, value: WIFSIGNALED}, ~, ~, Str], # 473
  [Constant, {const_type: string, value: WIFSTOPPED}, ~, ~, Str], # 474
  [Constant, {const_type: string, value: WNOHANG}, ~, ~, Str], # 475
  [Constant, {const_type: string, value: WSTOPSIG}, ~, ~, Str], # 476
  [Constant, {const_type: string, value: WTERMSIG}, ~, ~, Str], # 477
  [Constant, {const_type: string, value: WUNTRACED}, ~, ~, Str], # 478
  [ArrayLiteral, ~, [471, 472, 473, 474, 475, 476, 477, 478], 469, ArrayRef], # 479
  [Constant, {const_type: string, value: termios_h}, ~, ~, Str], # 480
  [Constant, {const_type: string, value: B0}, ~, ~, Str], # 481
  [Constant, {const_type: string, value: B110}, ~, ~, Str], # 482
  [Constant, {const_type: string, value: B1200}, ~, ~, Str], # 483
  [Constant, {const_type: string, value: B134}, ~, ~, Str], # 484
  [Constant, {const_type: string, value: B150}, ~, ~, Str], # 485
  [Constant, {const_type: string, value: B1800}, ~, ~, Str], # 486
  [Constant, {const_type: string, value: B19200}, ~, ~, Str], # 487
  [Constant, {const_type: string, value: B200}, ~, ~, Str], # 488
  [Constant, {const_type: string, value: B2400}, ~, ~, Str], # 489
  [Constant, {const_type: string, value: B300}, ~, ~, Str], # 490
  [Constant, {const_type: string, value: B38400}, ~, ~, Str], # 491
  [Constant, {const_type: string, value: B4800}, ~, ~, Str], # 492
  [Constant, {const_type: string, value: B50}, ~, ~, Str], # 493
  [Constant, {const_type: string, value: B600}, ~, ~, Str], # 494
  [Constant, {const_type: string, value: B75}, ~, ~, Str], # 495
  [Constant, {const_type: string, value: B9600}, ~, ~, Str], # 496
  [Constant, {const_type: string, value: BRKINT}, ~, ~, Str], # 497
  [Constant, {const_type: string, value: CLOCAL}, ~, ~, Str], # 498
  [Constant, {const_type: string, value: CREAD}, ~, ~, Str], # 499
  [Constant, {const_type: string, value: CS5}, ~, ~, Str], # 500
  [Constant, {const_type: string, value: CS6}, ~, ~, Str], # 501
  [Constant, {const_type: string, value: CS7}, ~, ~, Str], # 502
  [Constant, {const_type: string, value: CS8}, ~, ~, Str], # 503
  [Constant, {const_type: string, value: CSIZE}, ~, ~, Str], # 504
  [Constant, {const_type: string, value: CSTOPB}, ~, ~, Str], # 505
  [Constant, {const_type: string, value: ECHO}, ~, ~, Str], # 506
  [Constant, {const_type: string, value: ECHOE}, ~, ~, Str], # 507
  [Constant, {const_type: string, value: ECHOK}, ~, ~, Str], # 508
  [Constant, {const_type: string, value: ECHONL}, ~, ~, Str], # 509
  [Constant, {const_type: string, value: HUPCL}, ~, ~, Str], # 510
  [Constant, {const_type: string, value: ICANON}, ~, ~, Str], # 511
  [Constant, {const_type: string, value: ICRNL}, ~, ~, Str], # 512
  [Constant, {const_type: string, value: IEXTEN}, ~, ~, Str], # 513
  [Constant, {const_type: string, value: IGNBRK}, ~, ~, Str], # 514
  [Constant, {const_type: string, value: IGNCR}, ~, ~, Str], # 515
  [Constant, {const_type: string, value: IGNPAR}, ~, ~, Str], # 516
  [Constant, {const_type: string, value: INLCR}, ~, ~, Str], # 517
  [Constant, {const_type: string, value: INPCK}, ~, ~, Str], # 518
  [Constant, {const_type: string, value: ISIG}, ~, ~, Str], # 519
  [Constant, {const_type: string, value: ISTRIP}, ~, ~, Str], # 520
  [Constant, {const_type: string, value: IXOFF}, ~, ~, Str], # 521
  [Constant, {const_type: string, value: IXON}, ~, ~, Str], # 522
  [Constant, {const_type: string, value: NCCS}, ~, ~, Str], # 523
  [Constant, {const_type: string, value: NOFLSH}, ~, ~, Str], # 524
  [Constant, {const_type: string, value: OPOST}, ~, ~, Str], # 525
  [Constant, {const_type: string, value: PARENB}, ~, ~, Str], # 526
  [Constant, {const_type: string, value: PARMRK}, ~, ~, Str], # 527
  [Constant, {const_type: string, value: PARODD}, ~, ~, Str], # 528
  [Constant, {const_type: string, value: TCIFLUSH}, ~, ~, Str], # 529
  [Constant, {const_type: string, value: TCIOFF}, ~, ~, Str], # 530
  [Constant, {const_type: string, value: TCIOFLUSH}, ~, ~, Str], # 531
  [Constant, {const_type: string, value: TCION}, ~, ~, Str], # 532
  [Constant, {const_type: string, value: TCOFLUSH}, ~, ~, Str], # 533
  [Constant, {const_type: string, value: TCOOFF}, ~, ~, Str], # 534
  [Constant, {const_type: string, value: TCOON}, ~, ~, Str], # 535
  [Constant, {const_type: string, value: TCSADRAIN}, ~, ~, Str], # 536
  [Constant, {const_type: string, value: TCSAFLUSH}, ~, ~, Str], # 537
  [Constant, {const_type: string, value: TCSANOW}, ~, ~, Str], # 538
  [Constant, {const_type: string, value: TOSTOP}, ~, ~, Str], # 539
  [Constant, {const_type: string, value: VEOF}, ~, ~, Str], # 540
  [Constant, {const_type: string, value: VEOL}, ~, ~, Str], # 541
  [Constant, {const_type: string, value: VERASE}, ~, ~, Str], # 542
  [Constant, {const_type: string, value: VINTR}, ~, ~, Str], # 543
  [Constant, {const_type: string, value: VKILL}, ~, ~, Str], # 544
  [Constant, {const_type: string, value: VMIN}, ~, ~, Str], # 545
  [Constant, {const_type: string, value: VQUIT}, ~, ~, Str], # 546
  [Constant, {const_type: string, value: VSTART}, ~, ~, Str], # 547
  [Constant, {const_type: string, value: VSTOP}, ~, ~, Str], # 548
  [Constant, {const_type: string, value: VSUSP}, ~, ~, Str], # 549
  [Constant, {const_type: string, value: VTIME}, ~, ~, Str], # 550
  [Constant, {const_type: string, value: cfgetispeed}, ~, ~, Str], # 551
  [Constant, {const_type: string, value: cfgetospeed}, ~, ~, Str], # 552
  [Constant, {const_type: string, value: cfsetispeed}, ~, ~, Str], # 553
  [Constant, {const_type: string, value: cfsetospeed}, ~, ~, Str], # 554
  [Constant, {const_type: string, value: tcdrain}, ~, ~, Str], # 555
  [Constant, {const_type: string, value: tcflow}, ~, ~, Str], # 556
  [Constant, {const_type: string, value: tcflush}, ~, ~, Str], # 557
  [Constant, {const_type: string, value: tcgetattr}, ~, ~, Str], # 558
  [Constant, {const_type: string, value: tcsendbreak}, ~, ~, Str], # 559
  [Constant, {const_type: string, value: tcsetattr}, ~, ~, Str], # 560
  [ArrayLiteral, ~, [481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560], 479, ArrayRef], # 561
  [Constant, {const_type: string, value: time_h}, ~, ~, Str], # 562
  [Constant, {const_type: string, value: CLK_TCK}, ~, ~, Str], # 563
  [Constant, {const_type: string, value: CLOCKS_PER_SEC}, ~, ~, Str], # 564
  [Constant, {const_type: string, value: asctime}, ~, ~, Str], # 565
  [Constant, {const_type: string, value: clock}, ~, ~, Str], # 566
  [Constant, {const_type: string, value: ctime}, ~, ~, Str], # 567
  [Constant, {const_type: string, value: difftime}, ~, ~, Str], # 568
  [Constant, {const_type: string, value: mktime}, ~, ~, Str], # 569
  [Constant, {const_type: string, value: strftime}, ~, ~, Str], # 570
  [Constant, {const_type: string, value: tzset}, ~, ~, Str], # 571
  [Constant, {const_type: string, value: tzname}, ~, ~, Str], # 572
  [ArrayLiteral, ~, [563, 564, 244, 565, 566, 567, 568, 569, 570, 571, 572], 561, ArrayRef], # 573
  [Constant, {const_type: string, value: unistd_h}, ~, ~, Str], # 574
  [Constant, {const_type: string, value: F_OK}, ~, ~, Str], # 575
  [Constant, {const_type: string, value: R_OK}, ~, ~, Str], # 576
  [Constant, {const_type: string, value: STDERR_FILENO}, ~, ~, Str], # 577
  [Constant, {const_type: string, value: STDIN_FILENO}, ~, ~, Str], # 578
  [Constant, {const_type: string, value: STDOUT_FILENO}, ~, ~, Str], # 579
  [Constant, {const_type: string, value: W_OK}, ~, ~, Str], # 580
  [Constant, {const_type: string, value: X_OK}, ~, ~, Str], # 581
  [Constant, {const_type: string, value: _PC_CHOWN_RESTRICTED}, ~, ~, Str], # 582
  [Constant, {const_type: string, value: _PC_LINK_MAX}, ~, ~, Str], # 583
  [Constant, {const_type: string, value: _PC_MAX_CANON}, ~, ~, Str], # 584
  [Constant, {const_type: string, value: _PC_MAX_INPUT}, ~, ~, Str], # 585
  [Constant, {const_type: string, value: _PC_NAME_MAX}, ~, ~, Str], # 586
  [Constant, {const_type: string, value: _PC_NO_TRUNC}, ~, ~, Str], # 587
  [Constant, {const_type: string, value: _PC_PATH_MAX}, ~, ~, Str], # 588
  [Constant, {const_type: string, value: _PC_PIPE_BUF}, ~, ~, Str], # 589
  [Constant, {const_type: string, value: _PC_VDISABLE}, ~, ~, Str], # 590
  [Constant, {const_type: string, value: _POSIX_CHOWN_RESTRICTED}, ~, ~, Str], # 591
  [Constant, {const_type: string, value: _POSIX_JOB_CONTROL}, ~, ~, Str], # 592
  [Constant, {const_type: string, value: _POSIX_NO_TRUNC}, ~, ~, Str], # 593
  [Constant, {const_type: string, value: _POSIX_SAVED_IDS}, ~, ~, Str], # 594
  [Constant, {const_type: string, value: _POSIX_VDISABLE}, ~, ~, Str], # 595
  [Constant, {const_type: string, value: _POSIX_VERSION}, ~, ~, Str], # 596
  [Constant, {const_type: string, value: _SC_ARG_MAX}, ~, ~, Str], # 597
  [Constant, {const_type: string, value: _SC_CHILD_MAX}, ~, ~, Str], # 598
  [Constant, {const_type: string, value: _SC_CLK_TCK}, ~, ~, Str], # 599
  [Constant, {const_type: string, value: _SC_JOB_CONTROL}, ~, ~, Str], # 600
  [Constant, {const_type: string, value: _SC_NGROUPS_MAX}, ~, ~, Str], # 601
  [Constant, {const_type: string, value: _SC_OPEN_MAX}, ~, ~, Str], # 602
  [Constant, {const_type: string, value: _SC_PAGESIZE}, ~, ~, Str], # 603
  [Constant, {const_type: string, value: _SC_SAVED_IDS}, ~, ~, Str], # 604
  [Constant, {const_type: string, value: _SC_STREAM_MAX}, ~, ~, Str], # 605
  [Constant, {const_type: string, value: _SC_TZNAME_MAX}, ~, ~, Str], # 606
  [Constant, {const_type: string, value: _SC_VERSION}, ~, ~, Str], # 607
  [Constant, {const_type: string, value: _exit}, ~, ~, Str], # 608
  [Constant, {const_type: string, value: access}, ~, ~, Str], # 609
  [Constant, {const_type: string, value: ctermid}, ~, ~, Str], # 610
  [Constant, {const_type: string, value: cuserid}, ~, ~, Str], # 611
  [Constant, {const_type: string, value: dup2}, ~, ~, Str], # 612
  [Constant, {const_type: string, value: dup}, ~, ~, Str], # 613
  [Constant, {const_type: string, value: execl}, ~, ~, Str], # 614
  [Constant, {const_type: string, value: execle}, ~, ~, Str], # 615
  [Constant, {const_type: string, value: execlp}, ~, ~, Str], # 616
  [Constant, {const_type: string, value: execv}, ~, ~, Str], # 617
  [Constant, {const_type: string, value: execve}, ~, ~, Str], # 618
  [Constant, {const_type: string, value: execvp}, ~, ~, Str], # 619
  [Constant, {const_type: string, value: fpathconf}, ~, ~, Str], # 620
  [Constant, {const_type: string, value: fsync}, ~, ~, Str], # 621
  [Constant, {const_type: string, value: getcwd}, ~, ~, Str], # 622
  [Constant, {const_type: string, value: getegid}, ~, ~, Str], # 623
  [Constant, {const_type: string, value: geteuid}, ~, ~, Str], # 624
  [Constant, {const_type: string, value: getgid}, ~, ~, Str], # 625
  [Constant, {const_type: string, value: getgroups}, ~, ~, Str], # 626
  [Constant, {const_type: string, value: getpid}, ~, ~, Str], # 627
  [Constant, {const_type: string, value: getuid}, ~, ~, Str], # 628
  [Constant, {const_type: string, value: isatty}, ~, ~, Str], # 629
  [Constant, {const_type: string, value: lseek}, ~, ~, Str], # 630
  [Constant, {const_type: string, value: pathconf}, ~, ~, Str], # 631
  [Constant, {const_type: string, value: pause}, ~, ~, Str], # 632
  [Constant, {const_type: string, value: setgid}, ~, ~, Str], # 633
  [Constant, {const_type: string, value: setpgid}, ~, ~, Str], # 634
  [Constant, {const_type: string, value: setsid}, ~, ~, Str], # 635
  [Constant, {const_type: string, value: setuid}, ~, ~, Str], # 636
  [Constant, {const_type: string, value: sysconf}, ~, ~, Str], # 637
  [Constant, {const_type: string, value: tcgetpgrp}, ~, ~, Str], # 638
  [Constant, {const_type: string, value: tcsetpgrp}, ~, ~, Str], # 639
  [Constant, {const_type: string, value: ttyname}, ~, ~, Str], # 640
  [ArrayLiteral, ~, [575, 244, 576, 129, 130, 131, 577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640], 573, ArrayRef], # 641
  [Constant, {const_type: string, value: utime_h}, ~, ~, Str], # 642
  [ArrayLiteral, ~, ~, 641, ArrayRef], # 643
  [HashLiteral, {sigil: "%", symbol: default_export_tags}, [3, 6, 7, 8, 9, 10, 11, 104, 105, 150, 151, 181, 182, 183, 184, 227, 228, 247, 248, 288, 289, 290, 291, 296, 297, 348, 349, 350, 351, 353, 354, 402, 403, 431, 432, 455, 456, 462, 463, 464, 465, 466, 467, 469, 470, 479, 480, 561, 562, 573, 574, 641, 642, 643], ~, Hash], # 644
  [Constant, {const_type: string, value: fenv_h}, ~, ~, Str], # 645
  [Constant, {const_type: string, value: FE_DOWNWARD}, ~, ~, Str], # 646
  [Constant, {const_type: string, value: FE_TONEAREST}, ~, ~, Str], # 647
  [Constant, {const_type: string, value: FE_TOWARDZERO}, ~, ~, Str], # 648
  [Constant, {const_type: string, value: FE_UPWARD}, ~, ~, Str], # 649
  [Constant, {const_type: string, value: fegetround}, ~, ~, Str], # 650
  [Constant, {const_type: string, value: fesetround}, ~, ~, Str], # 651
  [MemStart], # 652
  [EntryDef, {package: main, sigil: $, symbol: "\u000f"}, ~, ~, Scalar, 652], # 653
  [Coerce, {from_repr: Unknown, to_repr: Str}, [653], ~, Str], # 654
  [Constant, {const_type: string, value: MSWin32}, ~, ~, Str], # 655
  [StrEq, ~, [654, 655], ~, Boolean], # 656
  [If, ~, [643, 656], 643], # 657
  [Proj, {index: 1}, [657]], # 658
  [Constant, {const_type: string, value: winsock_h}, ~, ~, Str], # 659
  [Subscript, {kind: hash}, [644, 659], ~, Undef], # 660
  [Constant, {const_type: string, value: WSAEINTR}, ~, ~, Str], # 661
  [Constant, {const_type: string, value: WSAEBADF}, ~, ~, Str], # 662
  [Constant, {const_type: string, value: WSAEACCES}, ~, ~, Str], # 663
  [Constant, {const_type: string, value: WSAEFAULT}, ~, ~, Str], # 664
  [Constant, {const_type: string, value: WSAEINVAL}, ~, ~, Str], # 665
  [Constant, {const_type: string, value: WSAEMFILE}, ~, ~, Str], # 666
  [Constant, {const_type: string, value: WSAEWOULDBLOCK}, ~, ~, Str], # 667
  [Constant, {const_type: string, value: WSAEINPROGRESS}, ~, ~, Str], # 668
  [Constant, {const_type: string, value: WSAEALREADY}, ~, ~, Str], # 669
  [Constant, {const_type: string, value: WSAENOTSOCK}, ~, ~, Str], # 670
  [Constant, {const_type: string, value: WSAEDESTADDRREQ}, ~, ~, Str], # 671
  [Constant, {const_type: string, value: WSAEMSGSIZE}, ~, ~, Str], # 672
  [Constant, {const_type: string, value: WSAEPROTOTYPE}, ~, ~, Str], # 673
  [Constant, {const_type: string, value: WSAENOPROTOOPT}, ~, ~, Str], # 674
  [Constant, {const_type: string, value: WSAEPROTONOSUPPORT}, ~, ~, Str], # 675
  [Constant, {const_type: string, value: WSAESOCKTNOSUPPORT}, ~, ~, Str], # 676
  [Constant, {const_type: string, value: WSAEOPNOTSUPP}, ~, ~, Str], # 677
  [Constant, {const_type: string, value: WSAEPFNOSUPPORT}, ~, ~, Str], # 678
  [Constant, {const_type: string, value: WSAEAFNOSUPPORT}, ~, ~, Str], # 679
  [Constant, {const_type: string, value: WSAEADDRINUSE}, ~, ~, Str], # 680
  [Constant, {const_type: string, value: WSAEADDRNOTAVAIL}, ~, ~, Str], # 681
  [Constant, {const_type: string, value: WSAENETDOWN}, ~, ~, Str], # 682
  [Constant, {const_type: string, value: WSAENETUNREACH}, ~, ~, Str], # 683
  [Constant, {const_type: string, value: WSAENETRESET}, ~, ~, Str], # 684
  [Constant, {const_type: string, value: WSAECONNABORTED}, ~, ~, Str], # 685
  [Constant, {const_type: string, value: WSAECONNRESET}, ~, ~, Str], # 686
  [Constant, {const_type: string, value: WSAENOBUFS}, ~, ~, Str], # 687
  [Constant, {const_type: string, value: WSAEISCONN}, ~, ~, Str], # 688
  [Constant, {const_type: string, value: WSAENOTCONN}, ~, ~, Str], # 689
  [Constant, {const_type: string, value: WSAESHUTDOWN}, ~, ~, Str], # 690
  [Constant, {const_type: string, value: WSAETOOMANYREFS}, ~, ~, Str], # 691
  [Constant, {const_type: string, value: WSAETIMEDOUT}, ~, ~, Str], # 692
  [Constant, {const_type: string, value: WSAECONNREFUSED}, ~, ~, Str], # 693
  [Constant, {const_type: string, value: WSAELOOP}, ~, ~, Str], # 694
  [Constant, {const_type: string, value: WSAENAMETOOLONG}, ~, ~, Str], # 695
  [Constant, {const_type: string, value: WSAEHOSTDOWN}, ~, ~, Str], # 696
  [Constant, {const_type: string, value: WSAEHOSTUNREACH}, ~, ~, Str], # 697
  [Constant, {const_type: string, value: WSAENOTEMPTY}, ~, ~, Str], # 698
  [Constant, {const_type: string, value: WSAEPROCLIM}, ~, ~, Str], # 699
  [Constant, {const_type: string, value: WSAEUSERS}, ~, ~, Str], # 700
  [Constant, {const_type: string, value: WSAEDQUOT}, ~, ~, Str], # 701
  [Constant, {const_type: string, value: WSAESTALE}, ~, ~, Str], # 702
  [Constant, {const_type: string, value: WSAEREMOTE}, ~, ~, Str], # 703
  [Constant, {const_type: string, value: WSAEDISCON}, ~, ~, Str], # 704
  [Constant, {const_type: string, value: WSAENOMORE}, ~, ~, Str], # 705
  [Constant, {const_type: string, value: WSAECANCELLED}, ~, ~, Str], # 706
  [Constant, {const_type: string, value: WSAEINVALIDPROCTABLE}, ~, ~, Str], # 707
  [Constant, {const_type: string, value: WSAEINVALIDPROVIDER}, ~, ~, Str], # 708
  [Constant, {const_type: string, value: WSAEPROVIDERFAILEDINIT}, ~, ~, Str], # 709
  [Constant, {const_type: string, value: WSAEREFUSED}, ~, ~, Str], # 710
  [Proj, {index: 0}, [657]], # 711
  [ArrayLiteral, ~, [661, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 672, 673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688, 689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710], 711, ArrayRef], # 712
  [Assign, ~, [660, 712], 712, ArrayRef, 652, true], # 713
  [Region, {head: 657}, [658, 713]], # 714
  [ArrayLiteral, ~, [646, 647, 648, 649, 650, 651], 714, ArrayRef], # 715
  [Constant, {const_type: string, value: math_h_c99}, ~, ~, Str], # 716
  [Phi, {memory: true, predecessors: [658, 711], region: 714}, [652, 713], ~, Unknown], # 717
  [Subscript, {kind: hash}, [644, 248], ~, Scalar, 717], # 718
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 440, package: POSIX, sigil: "@", strict: true}, [718], 715, Array, 717, true], # 719
  [Constant, {const_type: string, value: Inf}, ~, ~, Str], # 720
  [Constant, {const_type: string, value: NaN}, ~, ~, Str], # 721
  [Constant, {const_type: string, value: acosh}, ~, ~, Str], # 722
  [Constant, {const_type: string, value: asinh}, ~, ~, Str], # 723
  [Constant, {const_type: string, value: atanh}, ~, ~, Str], # 724
  [Constant, {const_type: string, value: cbrt}, ~, ~, Str], # 725
  [Constant, {const_type: string, value: copysign}, ~, ~, Str], # 726
  [Constant, {const_type: string, value: erf}, ~, ~, Str], # 727
  [Constant, {const_type: string, value: erfc}, ~, ~, Str], # 728
  [Constant, {const_type: string, value: exp2}, ~, ~, Str], # 729
  [Constant, {const_type: string, value: expm1}, ~, ~, Str], # 730
  [Constant, {const_type: string, value: fdim}, ~, ~, Str], # 731
  [Constant, {const_type: string, value: fma}, ~, ~, Str], # 732
  [Constant, {const_type: string, value: fmax}, ~, ~, Str], # 733
  [Constant, {const_type: string, value: fmin}, ~, ~, Str], # 734
  [Constant, {const_type: string, value: fpclassify}, ~, ~, Str], # 735
  [Constant, {const_type: string, value: hypot}, ~, ~, Str], # 736
  [Constant, {const_type: string, value: ilogb}, ~, ~, Str], # 737
  [Constant, {const_type: string, value: isfinite}, ~, ~, Str], # 738
  [Constant, {const_type: string, value: isgreater}, ~, ~, Str], # 739
  [Constant, {const_type: string, value: isgreaterequal}, ~, ~, Str], # 740
  [Constant, {const_type: string, value: isinf}, ~, ~, Str], # 741
  [Constant, {const_type: string, value: isless}, ~, ~, Str], # 742
  [Constant, {const_type: string, value: islessequal}, ~, ~, Str], # 743
  [Constant, {const_type: string, value: islessgreater}, ~, ~, Str], # 744
  [Constant, {const_type: string, value: isnan}, ~, ~, Str], # 745
  [Constant, {const_type: string, value: isnormal}, ~, ~, Str], # 746
  [Constant, {const_type: string, value: isunordered}, ~, ~, Str], # 747
  [Constant, {const_type: string, value: j0}, ~, ~, Str], # 748
  [Constant, {const_type: string, value: j1}, ~, ~, Str], # 749
  [Constant, {const_type: string, value: jn}, ~, ~, Str], # 750
  [Constant, {const_type: string, value: lgamma}, ~, ~, Str], # 751
  [Constant, {const_type: string, value: log1p}, ~, ~, Str], # 752
  [Constant, {const_type: string, value: log2}, ~, ~, Str], # 753
  [Constant, {const_type: string, value: logb}, ~, ~, Str], # 754
  [Constant, {const_type: string, value: lrint}, ~, ~, Str], # 755
  [Constant, {const_type: string, value: lround}, ~, ~, Str], # 756
  [Constant, {const_type: string, value: nan}, ~, ~, Str], # 757
  [Constant, {const_type: string, value: nearbyint}, ~, ~, Str], # 758
  [Constant, {const_type: string, value: nextafter}, ~, ~, Str], # 759
  [Constant, {const_type: string, value: nexttoward}, ~, ~, Str], # 760
  [Constant, {const_type: string, value: remainder}, ~, ~, Str], # 761
  [Constant, {const_type: string, value: remquo}, ~, ~, Str], # 762
  [Constant, {const_type: string, value: rint}, ~, ~, Str], # 763
  [Constant, {const_type: string, value: round}, ~, ~, Str], # 764
  [Constant, {const_type: string, value: scalbn}, ~, ~, Str], # 765
  [Constant, {const_type: string, value: signbit}, ~, ~, Str], # 766
  [Constant, {const_type: string, value: tgamma}, ~, ~, Str], # 767
  [Constant, {const_type: string, value: trunc}, ~, ~, Str], # 768
  [Constant, {const_type: string, value: y0}, ~, ~, Str], # 769
  [Constant, {const_type: string, value: y1}, ~, ~, Str], # 770
  [Constant, {const_type: string, value: yn}, ~, ~, Str], # 771
  [ArrayLiteral, ~, [719, 720, 721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736, 737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752, 753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768, 769, 770, 771], 719, ArrayRef], # 772
  [Constant, {const_type: string, value: netdb_h}, ~, ~, Str], # 773
  [Constant, {const_type: string, value: EAI_AGAIN}, ~, ~, Str], # 774
  [Constant, {const_type: string, value: EAI_BADFLAGS}, ~, ~, Str], # 775
  [Constant, {const_type: string, value: EAI_FAIL}, ~, ~, Str], # 776
  [Constant, {const_type: string, value: EAI_FAMILY}, ~, ~, Str], # 777
  [Constant, {const_type: string, value: EAI_MEMORY}, ~, ~, Str], # 778
  [Constant, {const_type: string, value: EAI_NONAME}, ~, ~, Str], # 779
  [Constant, {const_type: string, value: EAI_OVERFLOW}, ~, ~, Str], # 780
  [Constant, {const_type: string, value: EAI_SERVICE}, ~, ~, Str], # 781
  [Constant, {const_type: string, value: EAI_SOCKTYPE}, ~, ~, Str], # 782
  [Constant, {const_type: string, value: EAI_SYSTEM}, ~, ~, Str], # 783
  [ArrayLiteral, ~, [774, 775, 776, 777, 778, 779, 780, 781, 782, 783], 772, ArrayRef], # 784
  [Constant, {const_type: string, value: stdlib_h_c99}, ~, ~, Str], # 785
  [Subscript, {kind: hash}, [644, 403], ~, Scalar, 719], # 786
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 440, package: POSIX, sigil: "@", strict: true}, [786], 784, Array, 719, true], # 787
  [Constant, {const_type: string, value: strtold}, ~, ~, Str], # 788
  [ArrayLiteral, ~, [787, 788], 787, ArrayRef], # 789
  [Constant, {const_type: string, value: sys_resource_h}, ~, ~, Str], # 790
  [Constant, {const_type: string, value: PRIO_PROCESS}, ~, ~, Str], # 791
  [Constant, {const_type: string, value: PRIO_PGRP}, ~, ~, Str], # 792
  [Constant, {const_type: string, value: PRIO_USER}, ~, ~, Str], # 793
  [ArrayLiteral, ~, [791, 792, 793], 789, ArrayRef], # 794
  [Constant, {const_type: string, value: sys_socket_h}, ~, ~, Str], # 795
  [Constant, {const_type: string, value: MSG_CTRUNC}, ~, ~, Str], # 796
  [Constant, {const_type: string, value: MSG_DONTROUTE}, ~, ~, Str], # 797
  [Constant, {const_type: string, value: MSG_EOR}, ~, ~, Str], # 798
  [Constant, {const_type: string, value: MSG_OOB}, ~, ~, Str], # 799
  [Constant, {const_type: string, value: MSG_PEEK}, ~, ~, Str], # 800
  [Constant, {const_type: string, value: MSG_TRUNC}, ~, ~, Str], # 801
  [Constant, {const_type: string, value: MSG_WAITALL}, ~, ~, Str], # 802
  [ArrayLiteral, ~, [796, 797, 798, 799, 800, 801, 802], 794, ArrayRef], # 803
  [Constant, {const_type: string, value: nan_payload}, ~, ~, Str], # 804
  [Constant, {const_type: string, value: getpayload}, ~, ~, Str], # 805
  [Constant, {const_type: string, value: setpayload}, ~, ~, Str], # 806
  [Constant, {const_type: string, value: setpayloadsig}, ~, ~, Str], # 807
  [Constant, {const_type: string, value: issignaling}, ~, ~, Str], # 808
  [ArrayLiteral, ~, [805, 806, 807, 808], 803, ArrayRef], # 809
  [Constant, {const_type: string, value: signal_h_si_code}, ~, ~, Str], # 810
  [Constant, {const_type: string, value: ILL_ILLOPC}, ~, ~, Str], # 811
  [Constant, {const_type: string, value: ILL_ILLOPN}, ~, ~, Str], # 812
  [Constant, {const_type: string, value: ILL_ILLADR}, ~, ~, Str], # 813
  [Constant, {const_type: string, value: ILL_ILLTRP}, ~, ~, Str], # 814
  [Constant, {const_type: string, value: ILL_PRVOPC}, ~, ~, Str], # 815
  [Constant, {const_type: string, value: ILL_PRVREG}, ~, ~, Str], # 816
  [Constant, {const_type: string, value: ILL_COPROC}, ~, ~, Str], # 817
  [Constant, {const_type: string, value: ILL_BADSTK}, ~, ~, Str], # 818
  [Constant, {const_type: string, value: FPE_INTDIV}, ~, ~, Str], # 819
  [Constant, {const_type: string, value: FPE_INTOVF}, ~, ~, Str], # 820
  [Constant, {const_type: string, value: FPE_FLTDIV}, ~, ~, Str], # 821
  [Constant, {const_type: string, value: FPE_FLTOVF}, ~, ~, Str], # 822
  [Constant, {const_type: string, value: FPE_FLTUND}, ~, ~, Str], # 823
  [Constant, {const_type: string, value: FPE_FLTRES}, ~, ~, Str], # 824
  [Constant, {const_type: string, value: FPE_FLTINV}, ~, ~, Str], # 825
  [Constant, {const_type: string, value: FPE_FLTSUB}, ~, ~, Str], # 826
  [Constant, {const_type: string, value: SEGV_MAPERR}, ~, ~, Str], # 827
  [Constant, {const_type: string, value: SEGV_ACCERR}, ~, ~, Str], # 828
  [Constant, {const_type: string, value: BUS_ADRALN}, ~, ~, Str], # 829
  [Constant, {const_type: string, value: BUS_ADRERR}, ~, ~, Str], # 830
  [Constant, {const_type: string, value: BUS_OBJERR}, ~, ~, Str], # 831
  [Constant, {const_type: string, value: TRAP_BRKPT}, ~, ~, Str], # 832
  [Constant, {const_type: string, value: TRAP_TRACE}, ~, ~, Str], # 833
  [Constant, {const_type: string, value: CLD_EXITED}, ~, ~, Str], # 834
  [Constant, {const_type: string, value: CLD_KILLED}, ~, ~, Str], # 835
  [Constant, {const_type: string, value: CLD_DUMPED}, ~, ~, Str], # 836
  [Constant, {const_type: string, value: CLD_TRAPPED}, ~, ~, Str], # 837
  [Constant, {const_type: string, value: CLD_STOPPED}, ~, ~, Str], # 838
  [Constant, {const_type: string, value: CLD_CONTINUED}, ~, ~, Str], # 839
  [Constant, {const_type: string, value: POLL_IN}, ~, ~, Str], # 840
  [Constant, {const_type: string, value: POLL_OUT}, ~, ~, Str], # 841
  [Constant, {const_type: string, value: POLL_MSG}, ~, ~, Str], # 842
  [Constant, {const_type: string, value: POLL_ERR}, ~, ~, Str], # 843
  [Constant, {const_type: string, value: POLL_PRI}, ~, ~, Str], # 844
  [Constant, {const_type: string, value: POLL_HUP}, ~, ~, Str], # 845
  [Constant, {const_type: string, value: SI_USER}, ~, ~, Str], # 846
  [Constant, {const_type: string, value: SI_QUEUE}, ~, ~, Str], # 847
  [Constant, {const_type: string, value: SI_TIMER}, ~, ~, Str], # 848
  [Constant, {const_type: string, value: SI_ASYNCIO}, ~, ~, Str], # 849
  [Constant, {const_type: string, value: SI_MESGQ}, ~, ~, Str], # 850
  [ArrayLiteral, ~, [811, 812, 813, 814, 815, 816, 817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832, 833, 834, 835, 836, 837, 838, 839, 840, 841, 842, 843, 844, 845, 846, 847, 848, 849, 850], 809, ArrayRef], # 851
  [HashLiteral, {sigil: "%", symbol: other_export_tags}, [645, 715, 716, 772, 773, 784, 785, 789, 790, 794, 795, 803, 804, 809, 810, 851], ~, Hash], # 852
  [HashLiteral, {sigil: "%", symbol: "%POSIX::EXPORT_TAGS"}, [644, 852], ~, Hash], # 853
  [EntryDef, {package: POSIX, sigil: "@", symbol: EXPORT_OK}, ~, ~, Array], # 854
  [Constant, {const_type: string, value: close}, ~, ~, Str], # 855
  [Constant, {const_type: string, value: lchown}, ~, ~, Str], # 856
  [Constant, {const_type: string, value: nice}, ~, ~, Str], # 857
  [Constant, {const_type: string, value: open}, ~, ~, Str], # 858
  [Constant, {const_type: string, value: pipe}, ~, ~, Str], # 859
  [Constant, {const_type: string, value: read}, ~, ~, Str], # 860
  [Constant, {const_type: string, value: sleep}, ~, ~, Str], # 861
  [Constant, {const_type: string, value: times}, ~, ~, Str], # 862
  [Constant, {const_type: string, value: write}, ~, ~, Str], # 863
  [Constant, {const_type: string, value: printf}, ~, ~, Str], # 864
  [Constant, {const_type: string, value: sprintf}, ~, ~, Str], # 865
  [ArrayLiteral, ~, ~, ~, Array], # 866
  [EntryDef, {package: POSIX, sigil: "@", symbol: EXPORT}, ~, ~, Array], # 867
  [PadAccess, {sigil: "%", symbol: export}, ~, ~, Hash], # 868
  [ArrayLiteral, ~, ~, ~, Array], # 869
  [ArrayLiteral, ~, ~, ~, Array], # 870
  [Loop, {bound: entry}, [851], 851], # 871
  [Phi, {region: 871}, [870, 921], ~, Array], # 872
  [Slice, {kind: hash}, [872, 868], ~, List], # 873
  [Proj, {index: 1}, [871]], # 874
  [Region, {head: 871}, [874]], # 875
  [Phi, {memory: true, region: 871}, [787, 907], ~, Array], # 876
  [Phi, {memory: true, region: 875}, [876], ~, Array], # 877
  [Assign, {targets: 1}, [873], 875, Unknown, 877, true], # 878
  [Loop, {bound: entry}, [878], 878], # 879
  [Phi, {region: 879}, [869, 935], ~, Array], # 880
  [PadAccess, {sigil: "%", symbol: export_ok}, ~, ~, Hash], # 881
  [Slice, {kind: hash}, [880, 881], ~, List], # 882
  [Proj, {index: 1}, [879]], # 883
  [Region, {head: 879}, [883]], # 884
  [Phi, {memory: true, region: 879}, [878, 932], ~, Unknown], # 885
  [Phi, {memory: true, region: 884}, [885], ~, Unknown], # 886
  [Assign, {targets: 1}, [882], 884, Unknown, 886, true], # 887
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [868], ~, List, 887], # 888
  [EntryWrite, ~, [867, 888], 887, Unknown, 887, true], # 889
  [Loop, {bound: entry}, [889], 889], # 890
  [Phi, {region: 890}, [866, 927], ~, Array], # 891
  [ArrayLiteral, {sigil: "@", symbol: "@POSIX::EXPORT_OK"}, [855, 856, 857, 858, 859, 860, 861, 862, 863, 864, 865, 891], ~, Array], # 892
  [Proj, {index: 1}, [890]], # 893
  [Region, {head: 890}, [893]], # 894
  [EntryWrite, ~, [854, 892], 894, Unknown, 889, true], # 895
  [EntryWrite, ~, [2, 853], 895, Unknown, 895, true], # 896
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 896, Unknown, 896, true], # 897
  [Return, {implicit: true}, [897], 897, ~, 897], # 898
  [Call, {dispatch_kind: builtin, name: values, param_names: [], want: list}, [644], ~, List, 787], # 899
  [Count, ~, [899], ~, Int, 787], # 900
  [Count, ~, [899], ~, Int, 876], # 901
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 902
  [Phi, {region: 871}, [902, 920], ~, Int], # 903
  [Subscript, {kind: array}, [899, 903], ~, Scalar, 876], # 904
  [NumGt, ~, [901, 903], 871, Boolean], # 905
  [Proj, {index: 0}, [871]], # 906
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 471, package: POSIX, sigil: "@", strict: true}, [904], 906, Array, 876, true], # 907
  [Call, {dispatch_kind: builtin, name: values, param_names: [], want: list}, [852], ~, List, 878], # 908
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: reimpl}, ~, ~, Hash], # 909
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [909], ~, List, 889], # 910
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: replacement}, ~, ~, Hash], # 911
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [911], ~, List, 889], # 912
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [881], ~, List, 889], # 913
  [ArrayLiteral, ~, [910, 912, 913], ~, List], # 914
  [Count, ~, [914], ~, Int, 889], # 915
  [Phi, {region: 890}, [902, 933], ~, Int], # 916
  [Subscript, {kind: array}, [914, 916], ~, Scalar, 889], # 917
  [Exists, {kind: hash}, [868, 917], ~, Boolean, 889], # 918
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 919
  [Add, ~, [903, 919], ~, Int], # 920
  [ListAppend, {collector: map}, [872, 907], ~, Array], # 921
  [Count, ~, [908], ~, Int, 878], # 922
  [Count, ~, [908], ~, Int, 885], # 923
  [Phi, {region: 879}, [902, 934], ~, Int], # 924
  [Subscript, {kind: array}, [908, 924], ~, Scalar, 885], # 925
  [Not, ~, [918], ~, Boolean], # 926
  [ListAppend, {collector: grep}, [891, 917, 926], ~, Array], # 927
  [NumGt, ~, [915, 916], 890, Boolean], # 928
  [Proj, {index: 0}, [890]], # 929
  [NumGt, ~, [923, 924], 879, Boolean], # 930
  [Proj, {index: 0}, [879]], # 931
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 472, package: POSIX, sigil: "@", strict: true}, [925], 931, Array, 885, true], # 932
  [Add, ~, [916, 919], ~, Int], # 933
  [Add, ~, [924, 919], ~, Int], # 934
  [ListAppend, {collector: map}, [880, 932], ~, Array]]} # 935
POSIX::perror: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: glob, value: STDERR}, ~, ~, Glob], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "!"}, ~, ~, Scalar, 2], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [If, ~, [0, 6], 0], # 7
  [Proj, {index: 1}, [7]], # 8
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 2], # 9
  [Coerce, {from_repr: Scalar, to_repr: Str}, [9], ~, Str], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [10, 6], ~, Str, 2], # 11
  [Constant, {const_type: string, value: ": "}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Proj, {index: 0}, [7]], # 14
  [Print, {has_filehandle: true}, [1, 13], 14, "Maybe[Boolean]"], # 15
  [Region, {head: 7}, [8, 15]], # 16
  [Print, {has_filehandle: true}, [1, 4, 5], 16, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [17], 17, ~, 2]]} # 18
POSIX::printf: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: glob, value: STDOUT}, ~, ~, Glob], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Coerce, {from_repr: Array, to_repr: Num}, [2], ~, Num], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [NumLt, ~, [3, 4], ~, Boolean], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 1}, [6]], # 7
  [Constant, {const_type: string, value: "printf(pattern, args...)"}, ~, ~, Str], # 8
  [Proj, {index: 0}, [6]], # 9
  [MemStart], # 10
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 241, name: POSIX::usage, package: POSIX, param_names: [], want: void}, [8], 9, Unknown, 10, true], # 11
  [Region, {head: 6}, [7, 11]], # 12
  [Phi, {memory: true, predecessors: [7, 9], region: 12}, [10, 11], ~, Unknown], # 13
  [Call, {dispatch_kind: builtin, name: prtf, param_names: []}, [1, 2], 12, Scalar, 13], # 14
  [Return, {implicit: true}, [14], 14, ~, 13]]} # 15
POSIX::sprintf: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Coerce, {from_repr: Array, to_repr: Num}, [1], ~, Num], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [NumEq, ~, [2, 3], ~, Boolean], # 4
  [If, ~, [0, 4], 0], # 5
  [Proj, {index: 1}, [5]], # 6
  [Constant, {const_type: string, value: "sprintf(pattern, args...)"}, ~, ~, Str], # 7
  [Proj, {index: 0}, [5]], # 8
  [MemStart], # 9
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 246, name: POSIX::usage, package: POSIX, param_names: [], want: void}, [7], 8, Unknown, 9, true], # 10
  [Region, {head: 5}, [6, 10]], # 11
  [Phi, {memory: true, predecessors: [6, 8], region: 11}, [9, 10], ~, Unknown], # 12
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 11, Scalar, 12, true], # 13
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [13, 1], ~, Str, 13], # 14
  [Return, {implicit: true}, [14], 13, ~, 13]]} # 15
POSIX::unimplemented_message: {start: 0, returns: [47], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "C-specific, stopped"}, ~, ~, Str], # 1
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: replacement}, ~, ~, Hash], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [3], 0, Scalar, 4, true], # 5
  [Subscript, {kind: hash}, [2, 5], ~, Scalar, 5], # 6
  [Defined, ~, [6], ~, Boolean], # 7
  [Not, ~, [7], ~, Boolean], # 8
  [If, ~, [5, 8], 5], # 9
  [Proj, {index: 1}, [9]], # 10
  [RefType, ~, [6], ~, Str, 5], # 11
  [If, ~, [10, 11], 10], # 12
  [Proj, {index: 0}, [12]], # 13
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 201, package: POSIX, sigil: $, strict: true}, [6], 13, Scalar, 5, true], # 14
  [Coerce, {from_repr: Scalar, to_repr: Str}, [14], ~, Str], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 16
  [Constant, {const_type: string, value: " instead"}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [Constant, {const_type: string, value: "Use method "}, ~, ~, Str], # 19
  [Concat, ~, [19, 16], ~, Str], # 20
  [Constant, {const_type: string, value: "() instead"}, ~, ~, Str], # 21
  [Concat, ~, [20, 21], ~, Str], # 22
  [Constant, {const_type: string, value: "C-specific: use "}, ~, ~, Str], # 23
  [Concat, ~, [23, 16], ~, Str], # 24
  [Concat, ~, [24, 17], ~, Str], # 25
  [Proj, {index: 1}, [12]], # 26
  [Coerce, {from_repr: Scalar, to_repr: Str}, [6], ~, Str], # 27
  [RegexMatch, {flags: "", pattern: "^use "}, [27], ~, Boolean], # 28
  [If, ~, [26, 28], 26], # 29
  [Proj, {index: 1}, [29]], # 30
  [RegexMatch, {flags: "", pattern: "::"}, [27], ~, Boolean], # 31
  [If, ~, [30, 31], 30], # 32
  [Proj, {index: 0}, [32]], # 33
  [Proj, {index: 1}, [32]], # 34
  [Region, {head: 32}, [33, 34]], # 35
  [Phi, {predecessors: [33, 34], region: 35}, [22, 25], ~, Str], # 36
  [Proj, {index: 0}, [29]], # 37
  [Region, {head: 29}, [37, 35]], # 38
  [Phi, {predecessors: [37, 30], region: 38}, [18, 36], ~, Str], # 39
  [Region, {head: 12}, [14, 38]], # 40
  [Phi, {predecessors: [13, 26], region: 40}, [15, 39], ~, Str], # 41
  [Proj, {index: 0}, [9]], # 42
  [Region, {head: 9}, [42, 40]], # 43
  [Phi, {predecessors: [42, 10], region: 43}, [1, 41], ~, Str], # 44
  [Phi, {exits: true, memory: true, predecessors: [13, 26], region: 40}, [14, 5], ~, Scalar], # 45
  [Phi, {exits: true, memory: true, predecessors: [42, 10], region: 43}, [5, 45], ~, Scalar], # 46
  [Return, ~, [44], 43, ~, 46]]} # 47
POSIX::usage: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "Usage: POSIX::"}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/POSIX.pm", line: 22, name: POSIX::croak, package: POSIX, param_names: []}, [7], 0, Unknown, 4, true], # 8
  [Return, {implicit: true}, [8], 8, ~, 8]]} # 9
Regexp::CARP_TRACE: {start: 0, returns: [54], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "qr("}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 2], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [4, 5], ~, Scalar, 2], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Assign, ~, [3, 7], 0, Str, 2, true], # 8
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 8], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 468, name: Carp::downgrade, package: Carp, param_names: [], want: void, xs: true}, [9, 10], 8, Unknown, 8, true], # 11
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 11], # 12
  [RegexSubst, {flags: g, pattern: "([^ !\"#\\$\\%\\&'()*+,\\-./0123456789:;<=>?\\@ABCDEFGHIJKLMNOPQRSTUVWXYZ\\[\\\\\\]^_`abcdefghijklmnopqrstuvwxyz\\{|}~])", replacement: "", replacement_body: Regexp::CARP_TRACE::__SUBSTREPL__:1}, [12], 11, Str, 11, true], # 13
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Unknown, 13], # 14
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Carp.pm", line: 480, name: Carp::downgrade, package: Carp, param_names: [], want: void, xs: true}, [14, 10], 13, Unknown, 13, true], # 15
  [PadAccess, {sigil: $, symbol: suffix}, ~, ~, Unknown], # 16
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Str, 15], # 17
  [RegexMatch, {flags: s, pattern: "\\A\\(\\?\\^?([a-z]*)(?:-[a-z]*)?:(.*)\\)\\z"}, [17], 15, Boolean], # 18
  [RegexCapture, {"n": 1}, [18], ~, Str], # 19
  [RegexCapture, {"n": 2}, [18], ~, Str], # 20
  [If, ~, [18, 18], 18], # 21
  [Proj, {index: 0}, [21]], # 22
  [Assign, {targets: 2}, [16, 17, 19, 20], 22, List, 15, true], # 23
  [Proj, {index: 1}, [21]], # 24
  [Region, {head: 21}, [24, 23]], # 25
  [Phi, {memory: true, predecessors: [24, 22], region: 25}, [15, 23], ~, Unknown], # 26
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Str, 26], # 27
  [EntryDef, {package: Carp, sigil: $, symbol: MaxArgLen}, ~, ~, Scalar, 26], # 28
  [Coerce, {from_repr: Scalar, to_repr: Num}, [28], ~, Num], # 29
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 30
  [Subtract, ~, [29, 30], ~, Num], # 31
  [Length, ~, [27], ~, Int], # 32
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 33
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 34
  [NumLt, ~, [34, 29], ~, Boolean], # 35
  [NumLt, ~, [29, 32], ~, Boolean], # 36
  [And, ~, [35, 36], ~, Boolean], # 37
  [If, ~, [25, 37], 25], # 38
  [Proj, {index: 0}, [38]], # 39
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [27, 31, 32, 33], 39, Str, 26, true], # 40
  [Proj, {index: 1}, [38]], # 41
  [Region, {head: 38}, [41, 40]], # 42
  [Phi, {memory: true, predecessors: [41, 39], region: 42}, [26, 40], ~, Unknown], # 43
  [PadAccess, {sigil: $, symbol: arg}, ~, ~, Str, 43], # 44
  [Coerce, {from_repr: Unknown, to_repr: Str}, [44], ~, Str], # 45
  [Concat, ~, [1, 45], ~, Str], # 46
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 47
  [Concat, ~, [46, 47], ~, Str], # 48
  [Phi, {predecessors: [24, 22], region: 25}, [33, 19], ~, Str], # 49
  [Constant, {const_type: string, value: "..."}, ~, ~, Str], # 50
  [Concat, ~, [50, 49], ~, Str], # 51
  [Phi, {predecessors: [41, 39], region: 42}, [49, 51], ~, Str], # 52
  [Concat, ~, [48, 52], ~, Str], # 53
  [Return, ~, [53], 42, ~, 43], # 54
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [27, 31], ~, Str]]} # 55
Regexp::CARP_TRACE::__SUBSTREPL__:1: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "\\x{%x}"}, ~, ~, Str], # 1
  [RegexMatch, {flags: g, pattern: "([^ !\"#\\$\\%\\&'()*+,\\-./0123456789:;<=>?\\@ABCDEFGHIJKLMNOPQRSTUVWXYZ\\[\\\\\\]^_`abcdefghijklmnopqrstuvwxyz\\{|}~])"}, ~, ~, Boolean], # 2
  [RegexCapture, {"n": 1}, [2], ~, Str], # 3
  [Call, {dispatch_kind: builtin, name: ord, param_names: []}, [3], ~, Int], # 4
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [1, 4], ~, Str], # 5
  [MemStart], # 6
  [Return, {implicit: true}, [5], 0, ~, 6]]} # 7
Tie::ExtraHash::CLEAR: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [3, 2], 0, Scalar, 4], # 5
  [HashLiteral, ~, ~, 5, HashRef], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Subscript, {kind: array}, [3, 2], ~, Scalar], # 8
  [Assign, ~, [8, 7], 6, Scalar, 4, true], # 9
  [PostfixDeref, {sigil: "%"}, [7], ~, Hash, 9], # 10
  [Assign, {targets: 1}, [10], 9, Unknown, 9, true], # 11
  [Return, {implicit: true}, [11], 11, ~, 11]]} # 12
Tie::ExtraHash::DELETE: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Subscript, {kind: array}, [3, 2], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Subscript, {kind: array}, [1, 5], ~, Scalar, 6], # 7
  [Delete, {kind: hash}, [4, 7], 0, Scalar, 6, true], # 8
  [Return, {implicit: true}, [8], 8, ~, 8]]} # 9
Tie::ExtraHash::EXISTS: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Subscript, {kind: array}, [3, 2], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Subscript, {kind: array}, [1, 5], ~, Scalar, 6], # 7
  [Exists, {kind: hash}, [4, 7], 0, Boolean, 6, true], # 8
  [Return, {implicit: true}, [8], 8, ~, 8]]} # 9
Tie::ExtraHash::FETCH: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Subscript, {kind: array}, [3, 2], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Subscript, {kind: array}, [1, 5], ~, Scalar, 6], # 7
  [Subscript, {kind: hash}, [4, 7], 0, Scalar, 6, true], # 8
  [Return, {implicit: true}, [8], 8, ~, 8]]} # 9
Tie::ExtraHash::FIRSTKEY: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [3, 2], 0, Scalar, 4], # 5
  [HashLiteral, ~, ~, 5, HashRef], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Subscript, {kind: array}, [3, 2], ~, Scalar], # 8
  [Assign, ~, [8, 7], 6, Scalar, 4, true], # 9
  [PostfixDeref, {sigil: "%"}, [7], 9, Hash, 9, true], # 10
  [Subscript, {kind: array}, [3, 2], 10, Scalar, 10], # 11
  [HashLiteral, ~, ~, 11, HashRef], # 12
  [DefinedOr, ~, [11, 12], ~, Scalar], # 13
  [Assign, ~, [8, 13], 12, Scalar, 10, true], # 14
  [PostfixDeref, {sigil: "%"}, [13], ~, Hash, 14], # 15
  [Call, {dispatch_kind: builtin, name: each, param_names: []}, [15], 14, Unknown, 14, true], # 16
  [Return, {implicit: true}, [16], 16, ~, 16], # 17
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: scalar}, [10], ~, Int, 10]]} # 18
Tie::ExtraHash::NEXTKEY: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [3, 2], 0, Scalar, 4], # 5
  [HashLiteral, ~, ~, 5, HashRef], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Subscript, {kind: array}, [3, 2], ~, Scalar], # 8
  [Assign, ~, [8, 7], 6, Scalar, 4, true], # 9
  [PostfixDeref, {sigil: "%"}, [7], ~, Hash, 9], # 10
  [Call, {dispatch_kind: builtin, name: each, param_names: []}, [10], 9, Unknown, 9, true], # 11
  [Return, {implicit: true}, [11], 11, ~, 11]]} # 12
Tie::ExtraHash::SCALAR: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [3, 2], 0, Scalar, 4, true], # 5
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 268, package: Tie::ExtraHash, sigil: "%", strict: false}, [5], 5, Hash, 5, true], # 6
  [Count, ~, [6], ~, Int, 6], # 7
  [Return, {implicit: true}, [7], 6, ~, 6]]} # 8
Tie::ExtraHash::STORE: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [1, 5], ~, Scalar], # 6
  [Subscript, {kind: array}, [6, 5], 0, Scalar, 3], # 7
  [HashLiteral, ~, ~, 7, HashRef], # 8
  [DefinedOr, ~, [7, 8], ~, Scalar], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [6, 5], ~, Scalar], # 11
  [Assign, ~, [11, 9], 8, Scalar, 3, true], # 12
  [Subscript, {kind: array}, [1, 10], ~, Scalar, 12], # 13
  [Subscript, {kind: hash}, [9, 13], ~, Scalar], # 14
  [Assign, ~, [14, 4], 12, Scalar, 12, true], # 15
  [Return, {implicit: true}, [4], 15, ~, 15]]} # 16
Tie::ExtraHash::TIEHASH: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [HashLiteral, ~, ~, 3, HashRef], # 4
  [ArrayLiteral, ~, [4, 1], 4, ArrayRef], # 5
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [5, 3], 5, Unknown, 3, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
Tie::Hash::CLEAR: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: boolean, value: ""}, ~, ~, Boolean], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 0, Scalar, 3, true], # 4
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 229, name: FIRSTKEY, package: Tie::Hash, param_names: [], want: scalar}, [4, 2], 4, Unknown, 4, true], # 5
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 5], # 6
  [Assign, ~, [6, 5], 5, Unknown, 5, true], # 7
  [Loop, {bound: each}, [7], 7], # 8
  [Proj, {index: 1}, [8]], # 9
  [Region, {head: 8}, [9]], # 10
  [Loop, {bound: entry}, [10], 10], # 11
  [Proj, {index: 1}, [11]], # 12
  [Region, {head: 11}, [12]], # 13
  [Phi, {memory: true, region: 8}, [7, 34], ~, Unknown], # 14
  [Phi, {memory: true, region: 10}, [14], ~, Unknown], # 15
  [Phi, {memory: true, region: 11}, [15, 37], ~, Unknown], # 16
  [Phi, {memory: true, region: 13}, [16], ~, Unknown], # 17
  [Return, {implicit: true}, [1], 13, ~, 17], # 18
  [PadAccess, {sigil: "@", symbol: keys}, ~, ~, Array], # 19
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 14], # 20
  [Proj, {index: 0}, [8]], # 21
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [19, 20], 21, Int, 14, true], # 22
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 22], # 23
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 234, name: NEXTKEY, package: Tie::Hash, param_names: [], want: scalar}, [4, 2, 23], 22, Unknown, 22, true], # 24
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 16], # 25
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 26
  [Phi, {region: 11}, [26, 43], ~, Int], # 27
  [Subscript, {kind: array}, [19, 27], ~, Scalar, 16], # 28
  [Proj, {index: 0}, [11]], # 29
  [Assign, ~, [25, 28], 29, Scalar, 16, true], # 30
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 30], # 31
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 237, name: DELETE, package: Tie::Hash, param_names: [], want: void}, [4, 2, 31], 30, Unknown, 30, true], # 32
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 24], # 33
  [Assign, ~, [33, 24], 24, Unknown, 24, true], # 34
  [PadAccess, {sigil: $, symbol: key}, ~, ~, Unknown, 32], # 35
  [Subscript, {kind: array}, [19, 27], ~, Scalar], # 36
  [Assign, {if_changed: true}, [36, 35], 32, Unknown, 32, true], # 37
  [Count, ~, [19], ~, Int, 16], # 38
  [NumGt, ~, [38, 27], 11, Boolean], # 39
  [Count, ~, [19], ~, Int, 15], # 40
  [Defined, ~, [20], 8, Boolean], # 41
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 42
  [Add, ~, [27, 42], ~, Int]]} # 43
Tie::Hash::EXISTS: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [RefType, ~, [4], ~, Str, 3], # 5
  [Constant, {const_type: string, value: " doesn't define an EXISTS method"}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 224, name: Carp::croak, package: Tie::Hash, param_names: []}, [7], 0, Undef, 3, true], # 8
  [Return, {implicit: true}, [8], 8, ~, 8]]} # 9
Tie::Hash::TIEHASH: {start: 0, returns: [38], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [Constant, {const_type: string, value: "WARNING: calling "}, ~, ~, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: "->new since "}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [Constant, {const_type: string, value: "->TIEHASH is missing"}, ~, ~, Str], # 9
  [Concat, ~, [5, 9], ~, Str], # 10
  [Concat, ~, [8, 10], ~, Str], # 11
  [Constant, {const_type: string, value: Tie::Hash}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: new}, ~, ~, Str], # 13
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 202, name: can, package: Tie::Hash, param_names: [], want: scalar}, [3, 13], 3, Unknown, 3, true], # 14
  [StrNe, ~, [5, 12], ~, Boolean], # 15
  [And, ~, [14, 15], ~, Unknown], # 16
  [If, ~, [14, 16], 14], # 17
  [Proj, {index: 0}, [17]], # 18
  [Call, {class_name: Tie::Hash, dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 205, name: can, package: Tie::Hash, param_names: [], want: scalar}, [12, 13], 18, Unknown, 14, true], # 19
  [NumEq, ~, [14, 19], ~, Boolean], # 20
  [If, ~, [19, 20], 19], # 21
  [Proj, {index: 1}, [21]], # 22
  [Constant, {const_type: string, value: " must define either a TIEHASH() or a new() method"}, ~, ~, Str], # 23
  [Concat, ~, [5, 23], ~, Str], # 24
  [Proj, {index: 0}, [21]], # 25
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 206, name: Carp::croak, package: Tie::Hash, param_names: [], want: void}, [24], 25, Undef, 19, true], # 26
  [Region, {head: 21}, [22, 26]], # 27
  [Phi, {memory: true, predecessors: [22, 25], region: 27}, [19, 26], ~, Unknown], # 28
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 213, name: warnings::warnif, package: Tie::Hash, param_names: [], want: void}, [11], 27, Unknown, 28, true], # 29
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 215, name: new, package: Tie::Hash, param_names: []}, [3, 1], 29, Unknown, 29, true], # 30
  [Constant, {const_type: string, value: " doesn't define a TIEHASH method"}, ~, ~, Str], # 31
  [Concat, ~, [5, 31], ~, Str], # 32
  [Proj, {index: 1}, [17]], # 33
  [Call, {dispatch_kind: direct, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 218, name: Carp::croak, package: Tie::Hash, param_names: []}, [32], 33, Undef, 14, true], # 34
  [Region, {head: 17}, [30, 34]], # 35
  [Phi, {predecessors: [18, 33], region: 35}, [30, 34], ~, Unknown], # 36
  [Phi, {memory: true, predecessors: [18, 33], region: 35}, [30, 34], ~, Unknown], # 37
  [Return, {implicit: true}, [36], 35, ~, 37]]} # 38
Tie::Hash::new: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [Call, {dispatch_kind: method, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 195, name: TIEHASH, package: Tie::Hash, param_names: []}, [3, 1], 3, Unknown, 3, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
Tie::StdHash::CLEAR: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [PostfixDeref, {sigil: "%"}, [3], ~, Hash, 4], # 5
  [Assign, {targets: 1}, [5], 0, Unknown, 4, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
Tie::StdHash::DELETE: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [1, 4], ~, Scalar, 5], # 6
  [Delete, {kind: hash}, [3, 6], 0, Scalar, 5, true], # 7
  [Return, {implicit: true}, [7], 7, ~, 7]]} # 8
Tie::StdHash::EXISTS: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [1, 4], ~, Scalar, 5], # 6
  [Exists, {kind: hash}, [3, 6], 0, Boolean, 5, true], # 7
  [Return, {implicit: true}, [7], 7, ~, 7]]} # 8
Tie::StdHash::FETCH: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [1, 4], ~, Scalar, 5], # 6
  [Subscript, {kind: hash}, [3, 6], 0, Scalar, 5, true], # 7
  [Return, {implicit: true}, [7], 7, ~, 7]]} # 8
Tie::StdHash::FIRSTKEY: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [PostfixDeref, {sigil: "%"}, [3], 0, Hash, 4, true], # 5
  [PostfixDeref, {sigil: "%"}, [3], ~, Hash, 5], # 6
  [Call, {dispatch_kind: builtin, name: each, param_names: []}, [6], 5, Unknown, 5, true], # 7
  [Return, {implicit: true}, [7], 7, ~, 7], # 8
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: scalar}, [5], ~, Int, 5]]} # 9
Tie::StdHash::NEXTKEY: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [PostfixDeref, {sigil: "%"}, [3], ~, Hash, 4], # 5
  [Call, {dispatch_kind: builtin, name: each, param_names: []}, [5], 0, Unknown, 4, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
Tie::StdHash::SCALAR: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [PostfixDeref, {eval_id: ~, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/Tie/Hash.pm", line: 256, package: Tie::StdHash, sigil: "%", strict: false}, [4], 0, Hash, 3, true], # 5
  [Count, ~, [5], ~, Int, 5], # 6
  [Return, {implicit: true}, [6], 5, ~, 5]]} # 7
Tie::StdHash::STORE: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [1, 5], ~, Scalar], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [1, 7], ~, Scalar, 3], # 8
  [Subscript, {kind: hash}, [6, 8], ~, Scalar], # 9
  [Assign, ~, [9, 4], 0, Scalar, 3, true], # 10
  [Return, {implicit: true}, [4], 10, ~, 10]]} # 11
Tie::StdHash::TIEHASH: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [HashLiteral, ~, ~, 0, HashRef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [1, 5], 1, Unknown, 4, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "floor imported: "}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "%", symbol: "main::"}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: floor}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash, stash_has: 0}, [3, 4], ~, Scalar, 5], # 6
  [Constant, {const_type: string, value: "yes"}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: "no"}, ~, ~, Str], # 8
  [TernaryExpr, ~, [6, 7, 8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: "POSIX loaded: "}, ~, ~, Str], # 11
  [EntryDef, {package: main, sigil: "%", symbol: INC}, ~, ~, Hash], # 12
  [Constant, {const_type: string, value: POSIX.pm}, ~, ~, Str], # 13
  [Subscript, {kind: hash}, [12, 13], ~, Scalar, 5], # 14
  [TernaryExpr, ~, [14, 7, 8], ~, Str], # 15
  [Print, ~, [11, 15, 10], 0, "Maybe[Boolean]"], # 16
  [Print, ~, [2, 9, 10], 16, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [1], 17, ~, 5]]} # 18
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: POSIX.pm}, ~, ~, Str], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## `require strict;` -- the tier's one runtime op

The bareword-to-filename rewrite is the compiler's: by the time the op
runs, `strict` has become the string `"strict.pm"`, emitted as
`const[PV "strict.pm"] s/BARE` and consumed by `require`. So `require`
takes a filename, never a package name, and the bareword spelling is
sugar the op stream cannot see.

`strict` is chosen because it is core, prints nothing, and its version
does not reach the output. The load is observed through `%INC` rather
than through anything the module itself emits.

MEASURED perl 5.42.0:

    $ perl -e 'require strict; print +($INC{"strict.pm"} ? "yes" : "no"), "\n"'
    yes

```perl
require strict;
print "loaded ", ($INC{"strict.pm"} ? "yes" : "no"), "\n";
```

```behavior
parses: yes
```

```output
loaded yes
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "loaded "}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "%", symbol: INC}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: strict.pm}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [4], 0, Unknown, 5, true], # 6
  [Subscript, {kind: hash}, [3, 4], ~, Scalar, 6], # 7
  [Constant, {const_type: string, value: "yes"}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: "no"}, ~, ~, Str], # 9
  [TernaryExpr, ~, [7, 8, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [2, 10, 11], 6, "Maybe[Boolean]"], # 12
  [Return, {implicit: true}, [1], 12, ~, 6]]} # 13
```

## `require $m;` takes the filename from a variable

This is the case that shows the bareword form was sugar. `require
strict` emits `const[PV "strict.pm"] s/BARE` then `require`; this emits
`padsv` then `require`. One op, two sources, and only the operand
differs -- which is also why `require Foo::Bar` and `require
"Foo/Bar.pm"` are the same statement and `require $m` with `$m` holding
`"Foo::Bar"` is not.

MEASURED perl 5.42.0:

    $ perl -e 'my $m = "warnings.pm"; require $m; print +($INC{$m} ? "yes" : "no"), "\n"'
    yes

```perl
my $m = "warnings.pm";
require $m;
print "loaded ", ($INC{$m} ? "yes" : "no"), "\n";
```

```behavior
parses: yes
```

```output
loaded yes
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "loaded "}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "%", symbol: INC}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [4], 0, Unknown, 5, true], # 6
  [Subscript, {kind: hash}, [3, 4], ~, Scalar, 6], # 7
  [Constant, {const_type: string, value: "yes"}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: "no"}, ~, ~, Str], # 9
  [TernaryExpr, ~, [7, 8, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [2, 10, 11], 6, "Maybe[Boolean]"], # 12
  [Return, {implicit: true}, [1], 12, ~, 6]]} # 13
```

## `import` is an ordinary method call

`Marker->import("tag")` emits `pushmark`, `const[PV "Marker"] sM/BARE`,
`const[PV "tag"] sM`, `method_named[PV "import"]`, `entersub` -- tiers
01, 07 and 11 between them and nothing left over. The claim is that
`import` is not special, and the way to demonstrate it is to call it
directly and get the same stream `use` would have produced.

Called at run time rather than from `BEGIN` so the output order is the
source order. Under `BEGIN` the same call runs during compilation and
prints first, which is true of any BEGIN block and is tier 05's
business, not this tier's.

MEASURED perl 5.42.0:

    $ perl -e 'package Marker; sub import { print "import $_[0] $_[1]\n" } package main; Marker->import("tag"); print "after\n"'
    import Marker tag
    after

```perl
package Marker;
sub import { print "import $_[0] $_[1]\n" }
package main;
Marker->import("tag");
print "after\n";
```

```behavior
parses: yes
```

```output
import Marker tag
after
```

```ir
Marker::import: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "import "}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [2, 10], ~, Scalar, 4], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [9, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Print, ~, [15], 0, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [16], 16, ~, 4]]} # 17
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "after\n"}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: Marker}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: tag}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {class_name: Marker, dispatch_kind: method, file: "/tmp/ucZOh245UI/case.pl", line: 4, name: import, package: main, param_names: [], want: void}, [3, 4], 0, "Maybe[Boolean]", 5, true], # 6
  [Print, ~, [2], 6, "Maybe[Boolean]"], # 7
  [Return, {implicit: true}, [1], 7, ~, 6]]} # 8
```
