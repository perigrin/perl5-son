# The memory model's aliasing and ordering cases

Programs from the memory-model work: what a `local`, an alias (`$_[N]`, a
foreach iterator, a reference) and a later store do to a read, and the
order of effects a read must keep. One case per class of the audits
(docs/research/son-ir-audit-2026-11-19/REPORT.md W1-W10; the 2026-11-23
re-audit A-H; the 2026-11-24 final audit A-I; the 2026-11-25 second final
audit K1-K8) and of the wire-v2 baseline's sections 20-27. Until now they
lived only in the audit probes, which compare output only. A local
addition by B::SoN, like chalk-found-gaps.md.

**Tier 07 subroutines.** Introduces nothing. Depends on 06_control.

## local: the caller's $_[0] keeps the saved value

A sub localizes the package scalar its caller handed it. `$_[0]` is an alias to the scalar that was there at the call, which `local` saved aside; it reads 1, not the new 2.

```perl
our $x = 1; sub f { local $x = 2; print "$_[0]\n" } f($x);
```

```behavior
parses: yes
```

```output
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [EntryWrite, ~, [2, 3], 0, Unknown, 4, true, true], # 5
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 5, ~, true], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::f, package: main, param_names: [], want: void}, [6], 5, "Maybe[Boolean]", 5, true], # 7
  [Return, {implicit: true}, [1], 7, ~, 7]]} # 8
main::f: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [MemStart], # 5
  [EntryWrite, ~, [3, 4], 0, Unknown, 5, true, true], # 6
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 6, ~, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Print, ~, [10], 6, "Maybe[Boolean]"], # 11
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar, 5, ~, true], # 12
  [EntryWrite, ~, [3, 12], 11, Unknown, 6, true, true], # 13
  [Return, {implicit: true}, [11], 13, ~, 13]]} # 14
```

## local: a callee sees the new value, $_[0] the saved one

The same `local`, read two ways inside it: by name from a callee (the new value) and through `$_[0]` (the saved scalar).

```perl
our $x = 1; sub g { print "$x\n" } sub f { local $x = 2; g(); print "$_[0]\n" } f($x);
```

```behavior
parses: yes
```

```output
2
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [EntryWrite, ~, [2, 3], 0, Unknown, 4, true, true], # 5
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 5, ~, true], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::f, package: main, param_names: [], want: void}, [6], 5, "Maybe[Boolean]", 5, true], # 7
  [Return, {implicit: true}, [1], 7, ~, 7]]} # 8
main::f: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [MemStart], # 5
  [EntryWrite, ~, [3, 4], 0, Unknown, 5, true, true], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::g, package: main, param_names: [], want: void}, ~, 6, "Maybe[Boolean]", 6, true], # 7
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 7, ~, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Print, ~, [11], 7, "Maybe[Boolean]"], # 12
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar, 5, ~, true], # 13
  [EntryWrite, ~, [3, 13], 12, Unknown, 7, true, true], # 14
  [Return, {implicit: true}, [12], 14, ~, 14], # 15
  [Exc, ~, [7]], # 16
  [EntryWrite, ~, [3, 13], 16, Unknown, 7, true, true], # 17
  [Unwind, {rethrow: true}, [16], 17, ~, 17]]} # 18
main::g: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar, 1, ~, true], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [Print, ~, [5], 0, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [6], 6, ~, 1]]} # 7
```

## local: a reference taken before it follows the saved scalar

A reference to `$x` made before the `local` names the saved scalar, inside the block and after it.

```perl
our $x=1; my $r=\$x; { local $x=2; print "$$r $x\n" } print "$$r $x\n";
```

```behavior
parses: yes
```

```output
1 2
1 1
```

```ir
main::__PROGRAM__: {start: 0, returns: [29], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 2
  [Ref, ~, [2], ~, ScalarRef], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [EntryWrite, ~, [2, 4], 0, Unknown, 5, true, true], # 6
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 6, ~, true], # 7
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 8
  [EntryWrite, ~, [2, 8], 6, Unknown, 6, true, true], # 9
  [PostfixDeref, {eval_id: ~, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, package: main, sigil: $, strict: false}, [3], ~, Scalar, 9, ~, true], # 10
  [Coerce, {from_repr: Scalar, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 9, ~, true], # 14
  [Coerce, {from_repr: Int, to_repr: Str}, [14], ~, Str], # 15
  [Concat, ~, [13, 15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [Print, ~, [18], 9, "Maybe[Boolean]"], # 19
  [EntryWrite, ~, [2, 7], 19, Unknown, 9, true, true], # 20
  [PostfixDeref, {eval_id: ~, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, package: main, sigil: $, strict: false}, [3], ~, Scalar, 20, ~, true], # 21
  [Coerce, {from_repr: Scalar, to_repr: Str}, [21], ~, Str], # 22
  [Concat, ~, [22, 12], ~, Str], # 23
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 20, ~, true], # 24
  [Coerce, {from_repr: Int, to_repr: Str}, [24], ~, Str], # 25
  [Concat, ~, [23, 25], ~, Str], # 26
  [Concat, ~, [26, 17], ~, Str], # 27
  [Print, ~, [27], 20, "Maybe[Boolean]"], # 28
  [Return, {implicit: true}, [1], 28, ~, 20], # 29
  [Exc, ~, [19]], # 30
  [EntryWrite, ~, [2, 7], 30, Unknown, 9, true, true], # 31
  [Unwind, {rethrow: true}, [30], 31, ~, 31]]} # 32
```

## local: a reference to the localized scalar outlives the block

A reference taken inside the `local` names the temporary scalar; the store through it after the block does not reach `$x`, which is back to 1.

```perl
our $x=1; my $r; { local $x=2; $r=\$x } $$r=5; print "$$r $x\n";
```

```behavior
parses: yes
```

```output
5 1
```

```ir
main::__PROGRAM__: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 2
  [Ref, ~, [2], ~, ScalarRef], # 3
  [PostfixDeref, {eval_id: ~, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, package: main, sigil: $, strict: false}, [3], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [MemStart], # 7
  [EntryWrite, ~, [2, 6], 0, Unknown, 7, true, true], # 8
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 8, ~, true], # 9
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 10
  [EntryWrite, ~, [2, 10], 8, Unknown, 8, true, true], # 11
  [EntryWrite, ~, [2, 9], 11, Unknown, 11, true, true], # 12
  [Assign, ~, [4, 5], 12, Int, 12, true], # 13
  [PostfixDeref, {eval_id: ~, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, package: main, sigil: $, strict: false}, [3], ~, Scalar, 13, ~, true], # 14
  [Coerce, {from_repr: Scalar, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 13, ~, true], # 18
  [Coerce, {from_repr: Int, to_repr: Str}, [18], ~, Str], # 19
  [Concat, ~, [17, 19], ~, Str], # 20
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 21
  [Concat, ~, [20, 21], ~, Str], # 22
  [Print, ~, [22], 13, "Maybe[Boolean]"], # 23
  [Return, {implicit: true}, [1], 23, ~, 13]]} # 24
```

## local: hash elements, an existing key and a new one, seen from a callee

A callee sees both localized elements; after the sub, the existing key is put back and the new one is deleted.

```perl
our %h=(k=>1); sub show { print join(",", map { "$_=$h{$_}" } sort keys %h), "\n" } sub f { local $h{k}=2; local $h{n}=3; show() } f(); show();
```

```behavior
parses: yes
```

```output
k=2,n=3
k=1
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: "%", symbol: h}, ~, ~, Hash], # 2
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [HashLiteral, {sigil: "%", symbol: "%main::h"}, [3, 4], ~, Hash], # 5
  [MemStart], # 6
  [EntryWrite, ~, [2, 5], 0, Unknown, 6, true, true], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::f, package: main, param_names: [], want: void}, ~, 7, "Maybe[Boolean]", 7, true], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::show, package: main, param_names: [], want: void}, ~, 8, "Maybe[Boolean]", 8, true], # 9
  [Return, {implicit: true}, [1], 9, ~, 9]]} # 10
main::f: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: "%", symbol: h}, ~, ~, Hash], # 1
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 2
  [Subscript, {kind: hash}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 5
  [Subscript, {kind: hash}, [1, 5], ~, Scalar], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [MemStart], # 8
  [Assign, {local: true}, [6, 7], 0, Int, 8, true], # 9
  [Assign, {local: true}, [3, 4], 9, Int, 9, true], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::show, package: main, param_names: []}, ~, 10, "Maybe[Boolean]", 10, true], # 11
  [Subscript, {kind: hash}, [1, 5], ~, Scalar, 8, ~, true], # 12
  [Exists, {kind: hash}, [1, 5], ~, Boolean, 8, ~, true], # 13
  [Subscript, {kind: hash}, [1, 2], ~, Scalar, 9, ~, true], # 14
  [Exists, {kind: hash}, [1, 2], ~, Boolean, 9, ~, true], # 15
  [ElemRestore, {at_return: 1, kind: hash}, [1, 2, 14, 15], 11, Unknown, 11, true, true], # 16
  [ElemRestore, {at_return: 1, kind: hash}, [1, 5, 12, 13], 16, Unknown, 16, true, true], # 17
  [Return, {implicit: true}, [11], 17, ~, 17], # 18
  [Exc, ~, [11]], # 19
  [ElemRestore, {at_return: 1, kind: hash}, [1, 2, 14, 15], 19, Unknown, 11, true, true], # 20
  [ElemRestore, {at_return: 1, kind: hash}, [1, 5, 12, 13], 20, Unknown, 20, true, true], # 21
  [Unwind, {rethrow: true}, [19], 21, ~, 21]]} # 22
main::show: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Loop, {bound: entry}, [0, 20]], # 3
  [Phi, {region: 3}, [2, 31], ~, Array], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 4], ~, Str, 5, ~, true], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [EntryDef, {package: main, sigil: "%", symbol: h}, ~, ~, Hash], # 8
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [8], ~, List, 5, ~, true], # 9
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [9], ~, List, 5, ~, true], # 10
  [Count, ~, [10], ~, Int, 5, ~, true], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Phi, {region: 3}, [12, 23], ~, Int], # 13
  [NumGt, ~, [11, 13], ~, Boolean], # 14
  [If, ~, [3, 14], 3], # 15
  [Proj, {index: 1}, [15]], # 16
  [Region, {head: 3}, [16]], # 17
  [Print, ~, [6, 7], 17, "Maybe[Boolean]"], # 18
  [Return, {implicit: true}, [18], 18, ~, 5], # 19
  [Proj, {index: 0}, [15]], # 20
  [Count, ~, [10], ~, Int, 5, ~, true], # 21
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 22
  [Add, ~, [13, 22], ~, Int], # 23
  [Subscript, {kind: array}, [10, 13], ~, Scalar, 5, ~, true], # 24
  [Coerce, {from_repr: Unknown, to_repr: Str}, [24], ~, Str], # 25
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 26
  [Concat, ~, [25, 26], ~, Str], # 27
  [Subscript, {kind: hash}, [8, 24], ~, Scalar, 5, ~, true], # 28
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 29
  [Concat, ~, [27, 29], ~, Str], # 30
  [ListAppend, {collector: map}, [4, 30], ~, Array]]} # 31
```

## local: put back on a die in a sub with no eval

The fault is in the sub that made the `local`, with no eval of its own; the eval that catches it is the caller's. The `local` is put back on the way out.

```perl
our $g=1; sub f { local $g=2; 1/$_[0] } eval { f(0) }; print "$g\n";
```

```behavior
parses: yes
```

```output
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [EntryWrite, ~, [3, 4], 0, Unknown, 5, true, true], # 6
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 6, ~, true], # 7
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 8
  [EntryWrite, ~, [7, 8], 6, Unknown, 6, true, true], # 9
  [Call, {dispatch_kind: direct, eval_id: 1, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::f, package: main, param_names: [], want: void}, [2], 9, Num, 9, true], # 10
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 10, ~, true], # 11
  [EntryWrite, ~, [11, 8], 10, Unknown, 10, true, true], # 12
  [Exc, ~, [10]], # 13
  [Region, {catch: true, eval_id: 1}, [13]], # 14
  [EntryWrite, ~, [11, 13], 14, Unknown, 10, true, true], # 15
  [Region, {eval_entry: 6, eval_id: 1}, [12, 15]], # 16
  [Phi, {memory: true, region: 16}, [12, 15], ~, Unknown], # 17
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Int, 17, ~, true], # 18
  [Coerce, {from_repr: Int, to_repr: Str}, [18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [Print, ~, [21], 16, "Maybe[Boolean]"], # 22
  [Return, {implicit: true}, [1], 22, ~, 17]]} # 23
main::f: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Coerce, {from_repr: Int, to_repr: Num}, [1], ~, Num], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [MemStart], # 7
  [EntryWrite, ~, [5, 6], 0, Unknown, 7, true, true], # 8
  [Subscript, {kind: array}, [3, 4], ~, Scalar, 8, ~, true], # 9
  [Coerce, {from_repr: Scalar, to_repr: Num}, [9], ~, Num], # 10
  [Divide, {file: "/tmp/a8EfE9GJC0/case.pl", line: 1}, [2, 10], 8, Num], # 11
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar, 7, ~, true], # 12
  [EntryWrite, ~, [5, 12], 11, Unknown, 8, true, true], # 13
  [Return, {implicit: true}, [11], 13, ~, 13], # 14
  [Exc, ~, [11]], # 15
  [EntryWrite, ~, [5, 12], 15, Unknown, 8, true, true], # 16
  [Unwind, {rethrow: true}, [15], 16, ~, 16]]} # 17
```

## A copy through a reference, then a push through it

The copy is made where it stands: the later push does not reach it.

```perl
my $l=[1,2]; my @c=@$l; push @$l,3; print scalar(@c),"\n";
```

```behavior
parses: yes
```

```output
2
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [2, 3], 0, ArrayRef], # 4
  [MemStart], # 5
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, package: main, sigil: "@", strict: false}, [4], ~, Array, 5, ~, true], # 6
  [PostfixDeref, {sigil: "@"}, [4], ~, Array, 5, ~, true], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [7, 8], 4, Int, 5, true, true], # 9
  [Count, ~, [6], ~, Int, 9, ~, true], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [11, 12], 9, "Maybe[Boolean]"], # 13
  [Return, {implicit: true}, [1], 13, ~, 9], # 14
  [PostfixDeref, {eval_id: ~, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, package: main, sigil: "@", strict: false}, [4], ~, Array, 5, ~, true]]} # 15
```

## A hash copy, then a write to the copy

A copy of a hash is a new hash; a write to it does not reach the source.

```perl
my %h=(a=>1); my %c=%h; $c{a}=2; print "$h{a}\n";
```

```behavior
parses: yes
```

```output
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [HashLiteral, {sigil: "%", symbol: h}, [2, 3], ~, Hash], # 4
  [HashLiteral, {sigil: "%", symbol: c}, [4], 0, Hash], # 5
  [Subscript, {kind: hash}, [5, 2], ~, Scalar], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [MemStart], # 8
  [Assign, ~, [6, 7], 5, Int, 8, true], # 9
  [Subscript, {kind: hash}, [4, 2], ~, Scalar, 9, ~, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Print, ~, [13], 9, "Maybe[Boolean]"], # 14
  [Return, {implicit: true}, [1], 14, ~, 9]]} # 15
```

## foreach over package scalars aliases them

The iterator is each package scalar in turn; `$v *= 3` stores through it.

```perl
our ($x,$y)=(1,2); for my $v ($x,$y) { $v*=3 } print "$x $y\n";
```

```behavior
parses: yes
```

```output
3 6
```

```ir
main::__PROGRAM__: {start: 0, returns: [32], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: $, symbol: "y"}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [MemStart], # 6
  [EntryWrite, ~, [4, 5], 0, Unknown, 6, true, true], # 7
  [EntryWrite, ~, [2, 3], 7, Unknown, 7, true, true], # 8
  [Loop, {bound: entry}, [8, 43]], # 9
  [Phi, {memory: true, region: 9}, [8, 43], ~, Unknown], # 10
  [EntryDef, {package: main, place: true, sigil: $, symbol: x}, ~, ~, Scalar], # 11
  [EntryDef, {package: main, place: true, sigil: $, symbol: "y"}, ~, ~, Scalar], # 12
  [ArrayLiteral, ~, [11, 12], ~, Array], # 13
  [Count, ~, [13], ~, Int, 10, ~, true], # 14
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 15
  [Phi, {region: 9}, [15, 33], ~, Int], # 16
  [NumGt, ~, [14, 16], ~, Boolean], # 17
  [If, ~, [9, 17], 9], # 18
  [Proj, {index: 1}, [18]], # 19
  [Region, {head: 9}, [19]], # 20
  [Phi, {memory: true, region: 20}, [10], ~, Unknown], # 21
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 21, ~, true], # 22
  [Coerce, {from_repr: Int, to_repr: Str}, [22], ~, Str], # 23
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 24
  [Concat, ~, [23, 24], ~, Str], # 25
  [EntryDef, {package: main, sigil: $, symbol: "y"}, ~, ~, Int, 21, ~, true], # 26
  [Coerce, {from_repr: Int, to_repr: Str}, [26], ~, Str], # 27
  [Concat, ~, [25, 27], ~, Str], # 28
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 29
  [Concat, ~, [28, 29], ~, Str], # 30
  [Print, ~, [30], 20, "Maybe[Boolean]"], # 31
  [Return, {implicit: true}, [1], 31, ~, 21], # 32
  [Add, ~, [16, 5], ~, Int], # 33
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar, 8, ~, true], # 34
  [EntryDef, {package: main, sigil: $, symbol: "y"}, ~, ~, Scalar, 8, ~, true], # 35
  [Count, ~, [13], ~, Int, 8, ~, true], # 36
  [Subscript, {kind: array}, [13, 16], ~, Scalar], # 37
  [Proj, {index: 0}, [18]], # 38
  [Subscript, {kind: array}, [13, 16], 38, Scalar, 10, ~, true], # 39
  [Coerce, {from_repr: Scalar, to_repr: Num}, [39], ~, Num], # 40
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 41
  [Multiply, ~, [40, 41], ~, Num], # 42
  [Assign, ~, [37, 42], 39, Num, 10, true]]} # 43
```

## A foreach write before a die stays written

The alias write is a store to the element where it stands, so the die that leaves the pass does not lose it.

```perl
my @a=(1,2); eval { for my $x (@a) { $x.="!"; die "x\n" } }; print "@a\n";
```

```behavior
parses: yes
```

```output
1! 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [43], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 2, ~, true], # 3
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 4
  [EntryWrite, ~, [3, 4], 0, Unknown, 2, true, true], # 5
  [Loop, {bound: entry}, [5, 30]], # 6
  [Phi, {memory: true, region: 6}, [5, 27], ~, Unknown], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 9
  [ArrayLiteral, {sigil: "@", symbol: a}, [8, 9], ~, Array], # 10
  [Count, ~, [10], ~, Int, 7, ~, true], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Phi, {region: 6}, [12, 47], ~, Int], # 13
  [NumGt, ~, [11, 13], ~, Boolean], # 14
  [If, ~, [6, 14], 6], # 15
  [Proj, {index: 1}, [15]], # 16
  [Region, {head: 6}, [16]], # 17
  [Phi, {memory: true, region: 17}, [7], ~, Unknown], # 18
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 18, ~, true], # 19
  [EntryWrite, ~, [19, 4], 17, Unknown, 18, true, true], # 20
  [Subscript, {kind: array}, [10, 13], ~, Int, 7, ~, true], # 21
  [DefinedOr, ~, [21, 4], ~, Str], # 22
  [Coerce, {from_repr: Unknown, to_repr: Str}, [22], ~, Str], # 23
  [Constant, {const_type: string, value: "!"}, ~, ~, Str], # 24
  [Concat, ~, [23, 24], ~, Str], # 25
  [Proj, {index: 0}, [15]], # 26
  [Assign, ~, [21, 25], 26, Str, 7, true], # 27
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 27, ~, true], # 28
  [Constant, {const_type: string, value: "x\n"}, ~, ~, Str], # 29
  [Unwind, {eval_id: 1, file: "/tmp/a8EfE9GJC0/case.pl", line: 1}, [29], 27, ~, 27], # 30
  [Exc, ~, [30]], # 31
  [Region, {catch: true, eval_id: 1}, [31]], # 32
  [EntryWrite, ~, [28, 31], 32, Unknown, 27, true, true], # 33
  [Region, {eval_entry: 0, eval_id: 1}, [20, 33]], # 34
  [Phi, {memory: true, region: 34}, [20, 33], ~, Unknown], # 35
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 35, ~, true], # 36
  [Coerce, {from_repr: Scalar, to_repr: Str}, [36], ~, Str], # 37
  [PostfixDeref, {sigil: "@"}, [10], ~, Array, 35, ~, true], # 38
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [37, 38], ~, Str, 35, ~, true], # 39
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 40
  [Concat, ~, [39, 40], ~, Str], # 41
  [Print, ~, [41], 34, "Maybe[Boolean]"], # 42
  [Return, {implicit: true}, [1], 42, ~, 35], # 43
  [Count, ~, [10], ~, Int, 5, ~, true], # 44
  [Subscript, {kind: array}, [10, 13], ~, Scalar], # 45
  [Subscript, {kind: array}, [10, 13], ~, Str, 27, ~, true], # 46
  [Add, ~, [13, 8], ~, Int]]} # 47
```

## $_[0] after the callee stores the same variable by name

`$_[0]` is the caller's variable, so the callee's store by name is what it reads.

```perl
our $x=1; sub f { $x=5; print "$_[0]\n" } f($x);
```

```behavior
parses: yes
```

```output
5
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, place: true, sigil: $, symbol: x}, ~, ~, Scalar], # 2
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [EntryWrite, ~, [3, 4], 0, Unknown, 5, true, true], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::f, package: main, param_names: [], want: void}, [2], 6, "Maybe[Boolean]", 6, true], # 7
  [Return, {implicit: true}, [1], 7, ~, 7], # 8
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 6, ~, true]]} # 9
main::f: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 3
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 4
  [MemStart], # 5
  [EntryWrite, ~, [3, 4], 0, Unknown, 5, true, true], # 6
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 6, ~, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Print, ~, [10], 6, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [11], 11, ~, 6]]} # 12
```

## An op= on an assignment: ($x += 2) *= 3

The value of an assignment is its target, so the `*=` stores into `$x`.

```perl
my $x=1; ($x += 2) *= 3; print "$x\n";
```

```behavior
parses: yes
```

```output
9
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Add, ~, [2, 3], ~, Int], # 4
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 5
  [Multiply, ~, [4, 5], ~, Int], # 6
  [Coerce, {from_repr: Int, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Print, ~, [9], 0, "Maybe[Boolean]"], # 10
  [MemStart], # 11
  [Return, {implicit: true}, [1], 10, ~, 11]]} # 12
```

## An op= on a my declaration copied from an element

`(my $t = $a[0]) *= 10` stores into `$t`; the element is untouched.

```perl
my @a=(4); (my $t = $a[0]) *= 10; print "$t $a[0]\n";
```

```behavior
parses: yes
```

```output
40 4
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 2
  [ArrayLiteral, {sigil: "@", symbol: a}, [2], ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [3, 4], ~, Int, 5, ~, true], # 6
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 7
  [Multiply, ~, [6, 7], ~, Int], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Print, ~, [15], 0, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 5]]} # 17
```

## A ?: as the target of an assignment

The condition picks the variable the assignment stores into.

```perl
my ($a,$b)=(1,2); my $c=1; ($c ? $a : $b) = 9; print "$a$b\n";
```

```behavior
parses: yes
```

```output
92
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 3
  [TernaryExpr, ~, [2, 3, 2], ~, Unknown], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [TernaryExpr, ~, [2, 6, 3], ~, Unknown], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Concat, ~, [5, 8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Print, ~, [11], 0, "Maybe[Boolean]"], # 12
  [MemStart], # 13
  [Return, {implicit: true}, [1], 12, ~, 13], # 14
  [PadAccess, {sigil: $, symbol: a}, ~, ~, Unknown], # 15
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Unknown], # 16
  [Assign, {record: true, targets: 2}, [15, 16, 2, 6], ~, List], # 17
  [TernaryExpr, ~, [2, 15, 16], ~, Unknown]]} # 18
```

## A ?: as the operand of ++

The condition picks the variable `++` increments.

```perl
my ($a,$b)=(1,2); my $c=0; ($c ? $a : $b)++; print "$a$b\n";
```

```behavior
parses: yes
```

```output
13
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Add, ~, [3, 3], ~, Int], # 4
  [TernaryExpr, ~, [2, 4, 3], ~, Unknown], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Add, ~, [7, 3], ~, Int], # 8
  [TernaryExpr, ~, [2, 7, 8], ~, Unknown], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Concat, ~, [6, 10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Print, ~, [13], 0, "Maybe[Boolean]"], # 14
  [MemStart], # 15
  [Return, {implicit: true}, [1], 14, ~, 15], # 16
  [PadAccess, {sigil: $, symbol: a}, ~, ~, Unknown], # 17
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Unknown], # 18
  [TernaryExpr, ~, [2, 17, 18], ~, Unknown], # 19
  [Assign, {record: true, targets: 2}, [17, 18, 3, 7], ~, List], # 20
  [Increment, ~, [19], ~, Scalar]]} # 21
```

## An assignment handed to a sub that writes $_[0]

`inc($x += 1)` hands the sub `$x` itself, so its `$_[0]++` reaches `$x`.

```perl
sub inc { $_[0]++ } my $x=1; inc($x += 1); print "$x\n";
```

```behavior
parses: yes
```

```output
3
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {place: true, sigil: $, symbol: x}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 3, ~, true], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int, 3, true], # 6
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Num, 6, ~, true], # 7
  [Add, ~, [7, 5], ~, Num], # 8
  [Assign, ~, [7, 8], 6, Num, 6, true], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::inc, package: main, param_names: [], want: void}, [2], 9, Scalar, 9, true], # 10
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Str, 10, ~, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [Print, ~, [14], 10, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 10]]} # 16
main::inc: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], 0, Scalar, 3, ~, true], # 4
  [DefinedOr, ~, [4, 2], ~, Scalar], # 5
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 6
  [Increment, ~, [4], ~, Scalar], # 7
  [Assign, ~, [6, 7], 4, Scalar, 3, true], # 8
  [Return, {implicit: true}, [5], 8, ~, 8]]} # 9
```

## The value of chop is the character removed

`chop` returns what it removed, not a count.

```perl
my $s="abc"; my $d=chop($s); print "$d $s\n";
```

```behavior
parses: yes
```

```output
c ab
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 2
  [ChompValue, {kind: chop}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [Chomp, {kind: chop}, [2], ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Print, ~, [9], 0, "Maybe[Boolean]"], # 10
  [MemStart], # 11
  [Return, {implicit: true}, [1], 10, ~, 11]]} # 12
```

## $1 is put back at a block's end

A match inside a block sets `$1` for that block only.

```perl
"ab"=~/(a)/; { "xy"=~/(y)/; } print "$1\n";
```

```behavior
parses: yes
```

```output
a
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ab}, ~, ~, Str], # 2
  [RegexMatch, {flags: "", pattern: "(a)"}, [2], 0, Boolean], # 3
  [RegexCapture, {"n": 1}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: xy}, ~, ~, Str], # 7
  [RegexMatch, {flags: "", pattern: "(y)"}, [7], 3, Boolean], # 8
  [Print, ~, [6], 8, "Maybe[Boolean]"], # 9
  [MemStart], # 10
  [Return, {implicit: true}, [1], 9, ~, 10]]} # 11
```

## time, sleep, time: the reads stay in order

Both reads of the clock are made where they stand; a second read after `sleep 1` is later.

```perl
my $t0=time; sleep 1; my $t1=time; print $t1 > $t0 ? "later\n" : "same\n";
```

```behavior
parses: yes
```

```output
later
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: time, param_names: []}, ~, 0, Int, 3], # 4
  [Call, {dispatch_kind: builtin, name: sleep, param_names: []}, [2], 4, Int, 3], # 5
  [Call, {dispatch_kind: builtin, name: time, param_names: []}, ~, 5, Int, 3], # 6
  [NumGt, ~, [6, 4], ~, Boolean], # 7
  [Constant, {const_type: string, value: "later\n"}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: "same\n"}, ~, ~, Str], # 9
  [TernaryExpr, ~, [7, 8, 9], ~, Str], # 10
  [Print, ~, [10], 6, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 3]]} # 12
```

## W1: a package scalar carried round a loop while a callee writes it

son-ir-audit-2026-11-19 W1, probe pg1.

```perl
our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; bump(); } print "$g\n";
```

```behavior
parses: yes
```

```output
33
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [EntryWrite, ~, [2, 3], 0, Unknown, 4, true, true], # 5
  [Loop, {bound: entry}, [5, 26]], # 6
  [Phi, {memory: true, region: 6}, [5, 26], ~, Unknown], # 7
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 8
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 9
  [Phi, {region: 6}, [9, 27], ~, Int], # 10
  [NumGt, ~, [8, 10], ~, Boolean], # 11
  [If, ~, [6, 11], 6], # 12
  [Proj, {index: 1}, [12]], # 13
  [Region, {head: 6}, [13]], # 14
  [Phi, {memory: true, region: 14}, [7], ~, Unknown], # 15
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Int, 15, ~, true], # 16
  [Coerce, {from_repr: Int, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Print, ~, [19], 14, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 15], # 21
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Int, 7, ~, true], # 22
  [Add, ~, [22, 9], ~, Int], # 23
  [Proj, {index: 0}, [12]], # 24
  [EntryWrite, ~, [2, 23], 24, Unknown, 7, true, true], # 25
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::bump, package: main, param_names: [], want: void}, ~, 25, Num, 25, true], # 26
  [Add, ~, [10, 9], ~, Int]]} # 27
main::bump: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar, 1, ~, true], # 2
  [Coerce, {from_repr: Scalar, to_repr: Num}, [2], ~, Num], # 3
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 4
  [Add, ~, [3, 4], ~, Num], # 5
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar], # 6
  [EntryWrite, ~, [6, 5], 0, Unknown, 1, true, true], # 7
  [Return, {implicit: true}, [5], 7, ~, 7]]} # 8
```

## W2: a list assignment swapping two elements

son-ir-audit-2026-11-19 W2, probe swap1.

```perl
my @a = (1,2); ($a[0], $a[1]) = ($a[1], $a[0]); print "@a\n";
```

```behavior
parses: yes
```

```output
2 1
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3], ~, Array], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [4, 5], ~, Int], # 6
  [Subscript, {kind: array}, [4, 2], ~, Int], # 7
  [MemStart], # 8
  [Subscript, {kind: array}, [4, 2], ~, Int, 8, ~, true], # 9
  [Subscript, {kind: array}, [4, 5], ~, Int, 8, ~, true], # 10
  [Assign, {targets: 2}, [6, 7, 9, 10], 0, List, 8, true], # 11
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 11, ~, true], # 12
  [Coerce, {from_repr: Scalar, to_repr: Str}, [12], ~, Str], # 13
  [PostfixDeref, {sigil: "@"}, [4], ~, Array, 11, ~, true], # 14
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [13, 14], ~, Str, 11, ~, true], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Print, ~, [17], 11, "Maybe[Boolean]"], # 18
  [Return, {implicit: true}, [1], 18, ~, 11]]} # 19
```

## W3: a dynamic method call that stores

son-ir-audit-2026-11-19 W3, probe dyn1.

```perl
package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; return } package main; my $o = C->new; my $m = "inc"; $o->$m(); print $o->{n}, "\n";
```

```behavior
parses: yes
```

```output
1
```

```ir
C::inc: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Subscript, {kind: array}, [3, 4], ~, Scalar], # 5
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 6
  [Subscript, {kind: hash}, [5, 6], ~, Scalar], # 7
  [MemStart], # 8
  [Subscript, {kind: hash}, [5, 6], 0, Scalar, 8, ~, true], # 9
  [Increment, ~, [9], ~, Scalar], # 10
  [Assign, ~, [7, 10], 9, Scalar, 8, true], # 11
  [Return, ~, [1, 2], 11, ~, 11]]} # 12
C::new: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [HashLiteral, ~, [1, 2], 0, HashRef], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [4], 3, Scalar, 5, true, true], # 6
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [3, 6], 6, Unknown, 6, true, true], # 7
  [Return, {implicit: true}, [7], 7, ~, 7]]} # 8
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: C}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: new, package: main, param_names: [], want: scalar}, [2], 0, Object, 3, true], # 4
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: inc}, ~, ~, Str], # 6
  [Call, {dispatch_kind: dynamic_method, name: "", param_names: [], want: void}, [4, 6], 4, Unknown, 4, true], # 7
  [Subscript, {kind: hash}, [4, 5], 7, Scalar, 7, true, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
```

## W4: ref read before and after a bless

son-ir-audit-2026-11-19 W4, probe ef9.

```perl
my $o = {}; my $c = ref($o); bless $o, "K"; my $d = ref($o); print "$c $d\n";
```

```behavior
parses: yes
```

```output
HASH K
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [HashLiteral, ~, ~, 0, HashRef], # 2
  [MemStart], # 3
  [RefType, ~, [2], ~, Str, 3, ~, true], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: K}, ~, ~, Str], # 7
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [2, 7], 2, Unknown, 3, true, true], # 8
  [RefType, ~, [2], ~, Str, 8, ~, true], # 9
  [Concat, ~, [6, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Print, ~, [12], 8, "Maybe[Boolean]"], # 13
  [Return, {implicit: true}, [1], 13, ~, 8], # 14
  [PadAccess, {sigil: $, symbol: o}, ~, ~, HashRef], # 15
  [VarDecl, {scope: my}, [15, 2]]]} # 16
```

## W5: a captured variable written through $_[0]

son-ir-audit-2026-11-19 W5, probe cl23.

```perl
my $x = 1; my $g = sub { $x }; sub setx { $_[0] = 12 } setx($x); print $g->(), "\n";
```

```behavior
parses: yes
```

```output
12
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 2, ~, true], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Assign, ~, [3, 4], 0, Int, 2, true], # 5
  [MakeCell, {captured_written: false, cell_name: $x}, [1], 5, Ref, 5, true, true], # 6
  [CellRead, {place: true}, [6], ~, Scalar], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::setx, package: main, param_names: [], want: void}, [7], 6, Int, 6, true], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::__PROGRAM__::__ANON__:1:3, package: main, param_names: [], want: list}, ~, 8, Unknown, 8, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [10, 11], 9, "Maybe[Boolean]"], # 12
  [Return, {implicit: true}, [1], 12, ~, 9], # 13
  [AnonSub, {captures: [$x], name: main::__PROGRAM__::__ANON__:1:3}, [6], ~, CodeRef], # 14
  [CellRead, ~, [6], ~, Unknown, 6, ~, true]]} # 15
main::__PROGRAM__::__ANON__:1:3: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [CellParam, {index: 0, name: $x}, ~, ~, Ref], # 1
  [MemStart], # 2
  [CellRead, ~, [1], ~, Unknown, 2, ~, true], # 3
  [Return, {implicit: true}, [3], 0, ~, 2]]} # 4
main::setx: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "12"}, ~, ~, Int], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Assign, ~, [4, 1], 0, Int, 5, true], # 6
  [Return, {implicit: true}, [1], 6, ~, 6]]} # 7
```

## W6: a local in a loop body left by last

son-ir-audit-2026-11-19 W6, probe lo3.

```perl
our $g = 1; for my $i (1..2) { local $g = $g + $i; last if $i == 2 } print "$g\n";
```

```behavior
parses: yes
```

```output
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [29], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [EntryWrite, ~, [2, 3], 0, Unknown, 4, true, true], # 5
  [Loop, {bound: entry}, [5, 31]], # 6
  [Phi, {memory: true, region: 6}, [5, 31], ~, Unknown], # 7
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Int, 7, ~, true], # 8
  [Phi, {region: 6}, [3, 32], ~, Int], # 9
  [Add, ~, [8, 9], ~, Int], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [NumGt, ~, [11, 9], ~, Boolean], # 12
  [If, ~, [6, 12], 6], # 13
  [Proj, {index: 0}, [13]], # 14
  [EntryWrite, ~, [2, 10], 14, Unknown, 7, true, true], # 15
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 16
  [NumEq, ~, [9, 16], ~, Boolean], # 17
  [If, ~, [15, 17], 15], # 18
  [Proj, {index: 0}, [18]], # 19
  [EntryWrite, ~, [2, 8], 19, Unknown, 15, true, true], # 20
  [Proj, {index: 1}, [13]], # 21
  [Region, {head: 6}, [21, 20]], # 22
  [Phi, {memory: true, region: 22}, [7, 20], ~, Unknown], # 23
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Int, 23, ~, true], # 24
  [Coerce, {from_repr: Int, to_repr: Str}, [24], ~, Str], # 25
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 26
  [Concat, ~, [25, 26], ~, Str], # 27
  [Print, ~, [27], 22, "Maybe[Boolean]"], # 28
  [Return, {implicit: true}, [1], 28, ~, 23], # 29
  [Proj, {index: 1}, [18]], # 30
  [EntryWrite, ~, [2, 8], 30, Unknown, 15, true, true], # 31
  [Add, ~, [9, 3], ~, Int], # 32
  [Phi, {region: 22}, [8, 10], ~, Int]]} # 33
```

## W7: a division by zero faults before the print after it

son-ir-audit-2026-11-19 W7, probe fl1, inside an eval so the program exits 0.

```perl
my $d = @ARGV; my $ok = eval { my $q = 1 / $d; print "before\n"; print "$q\n"; 1 }; print $ok ? "ok\n" : "died\n";
```

```behavior
parses: yes
```

```output
died
```

```ir
main::__PROGRAM__: {start: 0, returns: [30], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 3, ~, true], # 4
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 5
  [EntryWrite, ~, [4, 5], 0, Unknown, 3, true, true], # 6
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 6, ~, true], # 7
  [Coerce, {from_repr: Int, to_repr: Num}, [2], ~, Num], # 8
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 9
  [Count, ~, [9], ~, Int, 3, ~, true], # 10
  [Coerce, {from_repr: Int, to_repr: Num}, [10], ~, Num], # 11
  [Divide, {eval_id: 1, file: "/tmp/a8EfE9GJC0/case.pl", line: 1}, [8, 11], 6, Num], # 12
  [Coerce, {from_repr: Num, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Constant, {const_type: string, value: "before\n"}, ~, ~, Str], # 16
  [Print, ~, [16], 12, "Maybe[Boolean]"], # 17
  [Print, ~, [15], 17, "Maybe[Boolean]"], # 18
  [EntryWrite, ~, [7, 5], 18, Unknown, 6, true, true], # 19
  [Exc, ~, [12]], # 20
  [Region, {catch: true, eval_id: 1}, [20]], # 21
  [EntryWrite, ~, [7, 20], 21, Unknown, 6, true, true], # 22
  [Region, {eval_entry: 0, eval_id: 1}, [19, 22]], # 23
  [Phi, {region: 23}, [2, 1], ~, "Maybe[Int]"], # 24
  [Constant, {const_type: string, value: "ok\n"}, ~, ~, Str], # 25
  [Constant, {const_type: string, value: "died\n"}, ~, ~, Str], # 26
  [TernaryExpr, ~, [24, 25, 26], ~, Str], # 27
  [Print, ~, [27], 23, "Maybe[Boolean]"], # 28
  [Phi, {memory: true, region: 23}, [19, 22], ~, Unknown], # 29
  [Return, {implicit: true}, [1], 28, ~, 29]]} # 30
```

## W7: die with a hash reference

son-ir-audit-2026-11-19 W7, probe ex1.

```perl
eval { die { code => 7 } }; print ref($@), " ", (ref $@ ? $@->{code} : "str"), "\n";
```

```behavior
parses: yes
```

```output
HASH 7
```

```ir
main::__PROGRAM__: {start: 0, returns: [32], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 2, ~, true], # 3
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 4
  [EntryWrite, ~, [3, 4], 0, Unknown, 2, true, true], # 5
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 5, ~, true], # 6
  [Constant, {const_type: string, value: code}, ~, ~, Str], # 7
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 8
  [HashLiteral, ~, [7, 8], 5, HashRef], # 9
  [Unwind, {eval_id: 1, file: "/tmp/a8EfE9GJC0/case.pl", line: 1}, [9], 9, ~, 5], # 10
  [Exc, ~, [10]], # 11
  [Region, {catch: true, eval_id: 1}, [11]], # 12
  [EntryWrite, ~, [6, 11], 12, Unknown, 5, true, true], # 13
  [Region, {eval_entry: 0, eval_id: 1}, [13]], # 14
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 14, Scalar, 13, ~, true], # 15
  [RefType, ~, [15], ~, Str, 13, ~, true], # 16
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 17
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 13, ~, true], # 18
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 15, Scalar, 13, ~, true], # 19
  [RefType, ~, [19], ~, Str, 13, ~, true], # 20
  [If, ~, [19, 20], 19], # 21
  [Proj, {index: 0}, [21]], # 22
  [Subscript, {kind: hash}, [18, 7], 22, Scalar, 13, true, true], # 23
  [Constant, {const_type: string, value: str}, ~, ~, Str], # 24
  [Proj, {index: 1}, [21]], # 25
  [Region, {head: 21}, [23, 25]], # 26
  [Phi, {predecessors: [22, 25], region: 26}, [23, 24], ~, Scalar], # 27
  [Coerce, {from_repr: Unknown, to_repr: Str}, [27], ~, Str], # 28
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 29
  [Print, ~, [16, 17, 28, 29], 26, "Maybe[Boolean]"], # 30
  [Phi, {memory: true, predecessors: [22, 25], region: 26}, [23, 13], ~, Unknown], # 31
  [Return, {implicit: true}, [1], 30, ~, 31]]} # 32
```

## W8: DESTROY runs at a scope's end

son-ir-audit-2026-11-19 W8, probe ca29.

```perl
my @o; sub DESTROY { push @o, "d" } { my $x = bless [], "main"; } print "@o\n";
```

```behavior
parses: yes
```

```output
d
```

```ir
main::DESTROY: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: o}, ~, ~, Array], # 1
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [1, 2], 0, Int, 3, true, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [ArrayLiteral, ~, ~, 0, ArrayRef], # 2
  [Constant, {const_type: string, value: main}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [2, 3], 2, Unknown, 4, true, true], # 5
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 5, ~, true], # 6
  [Coerce, {from_repr: Scalar, to_repr: Str}, [6], ~, Str], # 7
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: o}, ~, ~, Array, 5, ~, true], # 8
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [7, 8], ~, Str, 5, ~, true], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Print, ~, [11], 5, "Maybe[Boolean]"], # 12
  [Return, {implicit: true}, [1], 12, ~, 5]]} # 13
```

## W9: a nested read autovivifies

son-ir-audit-2026-11-19 W9, probe fl11.

```perl
my $h = { a => 1 }; my $v = $h->{b}{c}; print exists $h->{b} ? "viv" : "none", "\n";
```

```behavior
parses: yes
```

```output
viv
```

```ir
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [HashLiteral, ~, [2, 3], 0, HashRef], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [MemStart], # 6
  [Subscript, {kind: hash}, [4, 5], 4, Undef, 6, ~, true], # 7
  [HashLiteral, ~, ~, 7, HashRef], # 8
  [DefinedOr, ~, [7, 8], ~, "Maybe[HashRef]"], # 9
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 10
  [Subscript, {kind: hash}, [4, 5], ~, Undef], # 11
  [Assign, ~, [11, 9], 8, "Maybe[HashRef]", 6, true], # 12
  [Subscript, {kind: hash}, [9, 10], 12, Scalar, 12, true, true], # 13
  [Exists, {kind: hash}, [4, 5], ~, Boolean, 13, ~, true], # 14
  [Constant, {const_type: string, value: viv}, ~, ~, Str], # 15
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 16
  [TernaryExpr, ~, [14, 15, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [17, 18], 13, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [1], 19, ~, 13]]} # 20
```

## W10: a package array flattened into a list, then cleared

son-ir-audit-2026-11-19 W10, probe nv1.

```perl
our @st = (1); my @c = (@st, 2); @st = (); print "@c\n";
```

```behavior
parses: yes
```

```output
1 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: "@", symbol: st}, ~, ~, Array], # 2
  [ArrayLiteral, {sigil: "@", symbol: "@main::st"}, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [ArrayLiteral, {sigil: "@", symbol: "@main::st"}, [4], ~, Array], # 5
  [MemStart], # 6
  [EntryWrite, ~, [2, 5], 0, Unknown, 6, true, true], # 7
  [EntryWrite, ~, [2, 3], 7, Unknown, 7, true, true], # 8
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 8, ~, true], # 9
  [Coerce, {from_repr: Scalar, to_repr: Str}, [9], ~, Str], # 10
  [EntryDef, {package: main, sigil: "@", symbol: st}, ~, ~, Array, 7, ~, true], # 11
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 12
  [ArrayLiteral, {sigil: "@", symbol: c}, [11, 12], ~, Array], # 13
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [10, 13], ~, Str, 8, ~, true], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [Print, ~, [16], 8, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [1], 17, ~, 8]]} # 18
```

## re-audit A: a hash copy of defaults

2026-11-23 re-audit class A.

```perl
my %defaults=(color=>"red",size=>1); my %opt=%defaults; $opt{color}="blue"; print "$defaults{color} $opt{color}\n";
```

```behavior
parses: yes
```

```output
red blue
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: color}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: red}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: size}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [HashLiteral, {sigil: "%", symbol: defaults}, [2, 3, 4, 5], ~, Hash], # 6
  [HashLiteral, {sigil: "%", symbol: opt}, [6], 0, Hash], # 7
  [Subscript, {kind: hash}, [7, 2], ~, Scalar], # 8
  [Constant, {const_type: string, value: blue}, ~, ~, Str], # 9
  [MemStart], # 10
  [Assign, ~, [8, 9], 7, Str, 10, true], # 11
  [Subscript, {kind: hash}, [6, 2], ~, Scalar, 11, ~, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Subscript, {kind: hash}, [7, 2], ~, Str, 11, ~, true], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Concat, ~, [15, 17], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Concat, ~, [18, 19], ~, Str], # 20
  [Print, ~, [20], 11, "Maybe[Boolean]"], # 21
  [Return, {implicit: true}, [1], 21, ~, 11]]} # 22
```

## re-audit B: local @g put back on a fault in a sub with no eval

2026-11-23 re-audit class B.

```perl
our @g=(1); sub f { local @g=(2,3); my $z=shift; 1/$z } eval { f(0) }; print "@g\n";
```

```behavior
parses: yes
```

```output
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [26], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [EntryDef, {package: main, sigil: "@", symbol: g}, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [ArrayLiteral, {sigil: "@", symbol: "@main::g"}, [4], ~, Array], # 5
  [MemStart], # 6
  [EntryWrite, ~, [3, 5], 0, Unknown, 6, true, true], # 7
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 7, ~, true], # 8
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 9
  [EntryWrite, ~, [8, 9], 7, Unknown, 7, true, true], # 10
  [Call, {dispatch_kind: direct, eval_id: 1, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::f, package: main, param_names: [], want: void}, [2], 10, Num, 10, true], # 11
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 11, ~, true], # 12
  [EntryWrite, ~, [12, 9], 11, Unknown, 11, true, true], # 13
  [Exc, ~, [11]], # 14
  [Region, {catch: true, eval_id: 1}, [14]], # 15
  [EntryWrite, ~, [12, 14], 15, Unknown, 11, true, true], # 16
  [Region, {eval_entry: 7, eval_id: 1}, [13, 16]], # 17
  [Phi, {memory: true, region: 17}, [13, 16], ~, Unknown], # 18
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 18, ~, true], # 19
  [Coerce, {from_repr: Scalar, to_repr: Str}, [19], ~, Str], # 20
  [EntryDef, {package: main, sigil: "@", symbol: g}, ~, ~, Array, 18, ~, true], # 21
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [20, 21], ~, Str, 18, ~, true], # 22
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 23
  [Concat, ~, [22, 23], ~, Str], # 24
  [Print, ~, [24], 17, "Maybe[Boolean]"], # 25
  [Return, {implicit: true}, [1], 25, ~, 18]]} # 26
main::f: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Coerce, {from_repr: Int, to_repr: Num}, [1], ~, Num], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [EntryDef, {package: main, sigil: "@", symbol: g}, ~, ~, Array], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [ArrayLiteral, {sigil: "@", symbol: "@main::g"}, [5, 6], ~, Array], # 7
  [ArrayLiteral, ~, ~, ~, ArrayRef], # 8
  [MemStart], # 9
  [EntryWrite, {binds: true}, [4, 8], 0, Unknown, 9, true, true], # 10
  [EntryWrite, ~, [4, 7], 10, Unknown, 10, true, true], # 11
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [3], 11, Scalar, 11, true, true], # 12
  [Coerce, {from_repr: Scalar, to_repr: Num}, [12], ~, Num], # 13
  [Divide, {file: "/tmp/a8EfE9GJC0/case.pl", line: 1}, [2, 13], 12, Num], # 14
  [EntryDef, {package: main, sigil: "@", symbol: g}, ~, ~, Array, 9, ~, true], # 15
  [Ref, ~, [15], ~, ArrayRef], # 16
  [EntryWrite, {binds: true}, [4, 16], 14, Unknown, 12, true, true], # 17
  [Return, {implicit: true}, [14], 17, ~, 17], # 18
  [Exc, ~, [14]], # 19
  [EntryDef, {package: main, sigil: "@", symbol: g}, ~, ~, Array, 17, ~, true], # 20
  [EntryWrite, {binds: true}, [4, 16], 19, Unknown, 12, true, true], # 21
  [Unwind, {rethrow: true}, [19], 21, ~, 21], # 22
  [EntryDef, {package: main, sigil: "@", symbol: g}, ~, ~, Array, 21, ~, true]]} # 23
```

## re-audit C: a finally block runs

2026-11-23 re-audit class C.

```perl
use feature "try"; no warnings; my $x=0; try { $x=1 } catch ($e) { $x=9 } finally { $x.=3 } print "$x\n";
```

```behavior
parses: yes
```

```output
13
```

```ir
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: try}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true, true], # 4
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: unimport, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
refused: [
  "skipped main::__PROGRAM__: GAP: a `defer` or `finally` block is not yet lowered -- it runs on every way out of its scope, and nothing puts it on those ways"]
```

## re-audit D: a state variable with no initializer

2026-11-23 re-audit class D.

```perl
use feature "state"; sub c { state $n; $n.="x"; $n } c(); print c(),"\n";
```

```behavior
parses: yes
```

```output
xx
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::c, package: main, param_names: [], want: void}, ~, 0, Unknown, 2, true], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::c, package: main, param_names: [], want: list}, ~, 3, Unknown, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, "Maybe[Boolean]"], # 7
  [Return, {implicit: true}, [1], 7, ~, 4]]} # 8
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: state}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
refused: [
  "skipped main::c: GAP: a `state` variable with no initialiser, where it can be reached more than once, is not yet lowered -- it keeps its value between runs, and the walk makes it a `my`"]
```

## re-audit E: a foreach over a scalar variable aliases it

2026-11-23 re-audit class E.

```perl
my $x=5; for my $y ($x) { $x=1; print "$y\n" }
```

```behavior
parses: yes
```

```output
1
```

```ir
refused: [
  "skipped main::__PROGRAM__: GAP: a foreach over a scalar variable its body may write is not yet lowered -- the iterator is perl's alias of the variable, and the walk binds it to the value"]
```

## re-audit F: grep returns aliases its block wrote

2026-11-23 re-audit class F.

```perl
my @a=(1,2,3); my @g = grep { $_ *= 2 } @a; print "@a|@g\n";
```

```behavior
parses: yes
```

```output
2 4 6|2 4 6
```

```ir
refused: [
  "skipped main::__PROGRAM__: GAP: a grep whose block writes $_, read as a list, is not yet lowered -- what grep returns are the elements, written after the walk read them"]
```

## re-audit G: a my scalar read by alias, written later in the expression

2026-11-23 re-audit class G.

```perl
my $x=1; my $r=\$x; my $v = $x + ($$r=5); print "$v\n";
```

```behavior
parses: yes
```

```output
10
```

```ir
refused: [
  "skipped main::__PROGRAM__: GAP: a scalar operand is read by alias and a later operand stores it through a reference"]
```

## re-audit H: a singleton made by //= into a package scalar

2026-11-23 re-audit class H.

```perl
package C; our $inst; sub get { $inst //= bless {n=>0}, shift } package main; C->get->{n}++; C->get->{n}++; print C->get->{n},"\n";
```

```behavior
parses: yes
```

```output
2
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: C}, ~, ~, Str], # 2
  [PackageMark, {package: C}, ~, 0], # 3
  [PackageMark, {package: main}, ~, 3], # 4
  [MemStart], # 5
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: get, package: main, param_names: [], want: scalar}, [2], 4, Unknown, 5, true], # 6
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 7
  [Subscript, {kind: hash}, [6, 7], ~, Scalar], # 8
  [Subscript, {kind: hash}, [6, 7], 6, Scalar, 6, ~, true], # 9
  [Increment, ~, [9], ~, Scalar], # 10
  [Assign, ~, [8, 10], 9, Scalar, 6, true], # 11
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: get, package: main, param_names: [], want: scalar}, [2], 11, Unknown, 11, true], # 12
  [Subscript, {kind: hash}, [12, 7], ~, Scalar], # 13
  [Subscript, {kind: hash}, [12, 7], 12, Scalar, 12, ~, true], # 14
  [Increment, ~, [14], ~, Scalar], # 15
  [Assign, ~, [13, 15], 14, Scalar, 12, true], # 16
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: get, package: main, param_names: [], want: scalar}, [2], 16, Unknown, 16, true], # 17
  [Subscript, {kind: hash}, [17, 7], 17, Scalar, 17, true, true], # 18
  [Coerce, {from_repr: Unknown, to_repr: Str}, [18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Print, ~, [19, 20], 18, "Maybe[Boolean]"], # 21
  [Return, {implicit: true}, [1], 21, ~, 18], # 22
  [EntryDef, {package: C, sigil: $, symbol: inst}, ~, ~, Unknown, 5, ~, true]]} # 23
refused: [
  "skipped C::get: GAP: `//=` into something other than a lexical scalar or an element"]
```

## final audit A: a copy of an array a sub then stores

2026-11-24 final audit class A, probe f/c56.

```perl
my @a=(1,2); sub w { $a[0]=9 } my @c=@a; w(); print "@c\n";
```

```behavior
parses: yes
```

```output
1 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: a}, ~, ~, Array, 2, ~, true], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [ArrayLiteral, {sigil: "@", symbol: a}, [4, 5], 0, Array], # 6
  [Assign, ~, [3, 6], 6, List, 2, true], # 7
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: a}, ~, ~, Array, 7, ~, true], # 8
  [ArrayLiteral, {sigil: "@", symbol: c}, [8], 7, Array], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::w, package: main, param_names: [], want: void}, ~, 9, Int, 7, true], # 10
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 10, ~, true], # 11
  [Coerce, {from_repr: Scalar, to_repr: Str}, [11], ~, Str], # 12
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 9], ~, Str, 10, ~, true], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Print, ~, [15], 10, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 10]]} # 17
main::w: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 1
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: a}, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Assign, ~, [4, 1], 0, Int, 5, true], # 6
  [Return, {implicit: true}, [1], 6, ~, 6]]} # 7
```

## final audit B: a copy through a reference in a hash

2026-11-24 final audit class B, probe f/c52.

```perl
my @a=(1,2); my %h=(k=>\@a); my @c=@{$h{k}}; push @a,3; print scalar(@c), scalar(@{$h{k}}),"\n";
```

```behavior
parses: yes
```

```output
23
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [ArrayLiteral, {sigil: "@", symbol: a}, [3, 4], ~, Array], # 5
  [Ref, ~, [5], ~, ArrayRef], # 6
  [HashLiteral, {sigil: "%", symbol: h}, [2, 6], ~, Hash], # 7
  [MemStart], # 8
  [Subscript, {kind: hash}, [7, 2], ~, ArrayRef, 8, ~, true], # 9
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, package: main, sigil: "@", strict: false}, [9], ~, Array, 8, ~, true], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [PostfixDeref, {eval_id: ~, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, package: main, sigil: "@", strict: false}, [9], 0, Array, 8, true, true], # 12
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [5, 11], 12, Int, 12, true, true], # 13
  [Count, ~, [10], ~, Int, 13, ~, true], # 14
  [Coerce, {from_repr: Int, to_repr: Str}, [14], ~, Str], # 15
  [Subscript, {kind: hash}, [7, 2], ~, Scalar, 13, ~, true], # 16
  [PostfixDeref, {eval_id: ~, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, package: main, sigil: "@", strict: false}, [16], 13, Array, 13, true, true], # 17
  [Count, ~, [17], ~, Int, 17, ~, true], # 18
  [Coerce, {from_repr: Int, to_repr: Str}, [18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Print, ~, [15, 19, 20], 17, "Maybe[Boolean]"], # 21
  [Return, {implicit: true}, [1], 21, ~, 17]]} # 22
```

## final audit C: a callee stores a my variable, then returns $_[0]

2026-11-24 final audit class C, probe f/a30.

```perl
my $x=1; sub f { $x=2; $_[0] } print f($x), "\n";
```

```behavior
parses: yes
```

```output
2
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {file: 1, place: true, shared: 1, sigil: $, symbol: x}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: x}, ~, ~, Unknown, 3, ~, true], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int, 3, true], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::f, package: main, param_names: [], want: list}, [2], 6, Scalar, 6, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7], # 11
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: x}, ~, ~, Unknown, 6, ~, true]]} # 12
main::f: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: x}, ~, ~, Unknown, 3, ~, true], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int, 3, true], # 6
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 6, ~, true], # 7
  [Return, {implicit: true}, [7], 6, ~, 6]]} # 8
```

## final audit E: foreach over a new element vivifies it

2026-11-24 final audit class E, probe f/a67.

```perl
my @a; for my $x ($a[2]) { } print scalar(@a),"\n";
```

```behavior
parses: yes
```

```output
3
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {sigil: "@", symbol: a}, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Subscript, {kind: array, place: true, vivify: true}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [ArrayLiteral, ~, [4], 0, Array, 5, true], # 6
  [Count, ~, [2], ~, Int, 6, ~, true], # 7
  [Coerce, {from_repr: Int, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Loop, {bound: entry}, [6, 21]], # 10
  [Count, ~, [6], ~, Int, 6, ~, true], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Phi, {region: 10}, [12, 24], ~, Int], # 13
  [NumGt, ~, [11, 13], ~, Boolean], # 14
  [If, ~, [10, 14], 10], # 15
  [Proj, {index: 1}, [15]], # 16
  [Region, {head: 10}, [16]], # 17
  [Print, ~, [8, 9], 17, "Maybe[Boolean]"], # 18
  [Return, {implicit: true}, [1], 18, ~, 6], # 19
  [Count, ~, [6], ~, Int, 6, ~, true], # 20
  [Proj, {index: 0}, [15]], # 21
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 22
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 23
  [Add, ~, [13, 23], ~, Int]]} # 24
```

## final audit F: chop in a loop builds the reversed string

2026-11-24 final audit class F, probe f/l68.

```perl
my $s="abc"; my $o=""; while (length $s) { $o.=chop $s; } print "$o [$s]\n";
```

```behavior
parses: yes
```

```output
cba []
```

```ir
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: each}, [0, 21]], # 3
  [Phi, {region: 3}, [2, 24], ~, Str], # 4
  [Constant, {const_type: string, value: " ["}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 7
  [Phi, {region: 3}, [7, 22], ~, Str], # 8
  [Concat, ~, [6, 8], ~, Str], # 9
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Length, ~, [8], ~, Int], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [NumNe, ~, [12, 13], ~, Boolean], # 14
  [If, ~, [3, 14], 3], # 15
  [Proj, {index: 1}, [15]], # 16
  [Region, {head: 3}, [16]], # 17
  [Print, ~, [11], 17, "Maybe[Boolean]"], # 18
  [MemStart], # 19
  [Return, {implicit: true}, [1], 18, ~, 19], # 20
  [Proj, {index: 0}, [15]], # 21
  [Chomp, {kind: chop}, [8], ~, Str], # 22
  [ChompValue, {kind: chop}, [8], ~, Str], # 23
  [Concat, ~, [4, 23], ~, Str]]} # 24
```

## final audit G: a foreach write before a callee dies

2026-11-24 final audit class G, probe f/n04.

```perl
my @a=(1,2); sub d { die "x\n" } eval { for my $x (@a) { $x.="!"; d() } }; print "@a\n";
```

```behavior
parses: yes
```

```output
1! 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [42], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 2, ~, true], # 3
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 4
  [EntryWrite, ~, [3, 4], 0, Unknown, 2, true, true], # 5
  [Loop, {bound: entry}, [5, 28]], # 6
  [Phi, {memory: true, region: 6}, [5, 28], ~, Unknown], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 9
  [ArrayLiteral, {sigil: "@", symbol: a}, [8, 9], ~, Array], # 10
  [Count, ~, [10], ~, Int, 7, ~, true], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Phi, {region: 6}, [12, 46], ~, Int], # 13
  [NumGt, ~, [11, 13], ~, Boolean], # 14
  [If, ~, [6, 14], 6], # 15
  [Proj, {index: 1}, [15]], # 16
  [Region, {head: 6}, [16]], # 17
  [Phi, {memory: true, region: 17}, [7], ~, Unknown], # 18
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 18, ~, true], # 19
  [EntryWrite, ~, [19, 4], 17, Unknown, 18, true, true], # 20
  [Subscript, {kind: array}, [10, 13], ~, Int, 7, ~, true], # 21
  [DefinedOr, ~, [21, 4], ~, Str], # 22
  [Coerce, {from_repr: Unknown, to_repr: Str}, [22], ~, Str], # 23
  [Constant, {const_type: string, value: "!"}, ~, ~, Str], # 24
  [Concat, ~, [23, 24], ~, Str], # 25
  [Proj, {index: 0}, [15]], # 26
  [Assign, ~, [21, 25], 26, Str, 7, true], # 27
  [Call, {dispatch_kind: direct, eval_id: 1, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::d, package: main, param_names: [], want: void}, ~, 27, Undef, 27, true], # 28
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 28, ~, true], # 29
  [Exc, ~, [28]], # 30
  [Region, {catch: true, eval_id: 1}, [30]], # 31
  [EntryWrite, ~, [29, 30], 31, Unknown, 28, true, true], # 32
  [Region, {eval_entry: 0, eval_id: 1}, [20, 32]], # 33
  [Phi, {memory: true, region: 33}, [20, 32], ~, Unknown], # 34
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 34, ~, true], # 35
  [Coerce, {from_repr: Scalar, to_repr: Str}, [35], ~, Str], # 36
  [PostfixDeref, {sigil: "@"}, [10], ~, Array, 34, ~, true], # 37
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [36, 37], ~, Str, 34, ~, true], # 38
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 39
  [Concat, ~, [38, 39], ~, Str], # 40
  [Print, ~, [40], 33, "Maybe[Boolean]"], # 41
  [Return, {implicit: true}, [1], 41, ~, 34], # 42
  [Count, ~, [10], ~, Int, 5, ~, true], # 43
  [Subscript, {kind: array}, [10, 13], ~, Scalar], # 44
  [Subscript, {kind: array}, [10, 13], ~, Str, 27, ~, true], # 45
  [Add, ~, [13, 8], ~, Int]]} # 46
main::d: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "x\n"}, ~, ~, Str], # 2
  [MemStart], # 3
  [Unwind, {file: "/tmp/a8EfE9GJC0/case.pl", line: 1}, [2], 0, ~, 3], # 4
  [Return, {implicit: true}, [1], 4, ~, 3]]} # 5
```

## final audit H: a method replaces its invocant through $_[0]

2026-11-24 final audit class H, probe f/o14.

```perl
package C; sub new { bless {}, shift } sub repl { $_[0] = "gone" } package main; my $o=C->new; $o->repl; print ref($o) ? "obj" : $o, "\n";
```

```behavior
parses: yes
```

```output
gone
```

```ir
C::new: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [HashLiteral, ~, ~, 0, HashRef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 1, Scalar, 3, true, true], # 4
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [1, 4], 4, Unknown, 4, true, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
C::repl: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: gone}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Assign, ~, [4, 1], 0, Str, 5, true], # 6
  [Return, {implicit: true}, [1], 6, ~, 6]]} # 7
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {place: true, sigil: $, symbol: o}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: C}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: new, package: main, param_names: [], want: scalar}, [3], 0, Object, 4, true], # 5
  [PadAccess, {sigil: $, symbol: o}, ~, ~, Unknown, 5, ~, true], # 6
  [Assign, ~, [6, 5], 5, Object, 5, true], # 7
  [Call, {dispatch_kind: method, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: repl, package: main, param_names: [], want: void}, [2], 7, Unknown, 7, true], # 8
  [PadAccess, {sigil: $, symbol: o}, ~, ~, Unknown, 8, ~, true], # 9
  [RefType, ~, [9], ~, Str, 8, ~, true], # 10
  [Constant, {const_type: string, value: obj}, ~, ~, Str], # 11
  [TernaryExpr, ~, [10, 11, 9], ~, Unknown], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [13, 14], 8, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 8], # 16
  [PadAccess, {sigil: $, symbol: o}, ~, ~, Unknown, 7, ~, true]]} # 17
```

## final audit I: $1 copied, then a match in a block

2026-11-24 final audit class I, probe f/b17.

```perl
my $s="abc"; $s=~/(b)/; my $x=$1; { "q"=~/(q)/; } print "$x$1\n";
```

```behavior
parses: yes
```

```output
bb
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 2
  [RegexMatch, {flags: "", pattern: "(b)"}, [2], 0, Boolean], # 3
  [RegexCapture, {"n": 1}, [3], ~, Str], # 4
  [Concat, ~, [4, 4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Constant, {const_type: string, value: q}, ~, ~, Str], # 8
  [RegexMatch, {flags: "", pattern: "(q)"}, [8], 3, Boolean], # 9
  [Print, ~, [7], 9, "Maybe[Boolean]"], # 10
  [MemStart], # 11
  [Return, {implicit: true}, [1], 10, ~, 11]]} # 12
```

## K1: a callee copies @_, then the caller's array is stored

2026-11-25 second final audit class K1, probe z/cp24.

```perl
my @a=(1,2); sub f { my @l=@_; $a[0]=9; "@l" } print f(@a), "\n";
```

```behavior
parses: yes
```

```output
1 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: a}, ~, ~, Array], # 2
  [MemStart], # 3
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: a}, ~, ~, Array, 3, ~, true], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [ArrayLiteral, {sigil: "@", symbol: a}, [5, 6], 0, Array], # 7
  [Assign, ~, [4, 7], 7, List, 3, true], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::f, package: main, param_names: [], want: list}, [2], 8, Str, 8, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [10, 11], 9, "Maybe[Boolean]"], # 12
  [Return, {implicit: true}, [1], 12, ~, 9]]} # 13
main::f: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: a}, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [ArrayLiteral, {sigil: "@", symbol: l}, [5], 0, Array], # 6
  [MemStart], # 7
  [Assign, ~, [3, 4], 6, Int, 7, true], # 8
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 8, ~, true], # 9
  [Coerce, {from_repr: Scalar, to_repr: Str}, [9], ~, Str], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [10, 6], ~, Str, 8, ~, true], # 11
  [Return, {implicit: true}, [11], 8, ~, 8]]} # 12
```

## K2: local of a variable $_[0] aliases

2026-11-25 second final audit class K2, probe z/qb01.

```perl
our $x=1; sub f { local $x=5; $_[0]=7; $x } my $r=f($x); print "$r$x\n";
```

```behavior
parses: yes
```

```output
57
```

```ir
main::f: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 4
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 5
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 6
  [MemStart], # 7
  [EntryWrite, ~, [5, 6], 0, Unknown, 7, true, true], # 8
  [Assign, ~, [3, 4], 8, Int, 8, true], # 9
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 9, ~, true], # 10
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar, 7, ~, true], # 11
  [EntryWrite, ~, [5, 11], 9, Unknown, 9, true, true], # 12
  [Return, {implicit: true}, [10], 12, ~, 12]]} # 13
refused: [
  "skipped main::__PROGRAM__: GAP: a variable handed to a sub as its $_[N] where that sub localizes it is not yet lowered -- perl's alias keeps the saved scalar, and the wire's place is the name's storage"]
```

## K3: a foreach iterator read after a call stores its element

2026-11-25 second final audit class K3, probe z/pa69.

```perl
my @a=(1,2); sub z { $a[0]=7 } for my $x (@a) { z(); print $x } print "\n";
```

```behavior
parses: yes
```

```output
72
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: a}, ~, ~, Array, 3, ~, true], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [ArrayLiteral, {sigil: "@", symbol: a}, [5, 6], 0, Array], # 7
  [Assign, ~, [4, 7], 7, List, 3, true], # 8
  [Loop, {bound: entry}, [8, 34]], # 9
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: a}, ~, ~, Array], # 10
  [Phi, {memory: true, region: 9}, [8, 29], ~, List], # 11
  [Count, ~, [10], ~, Int, 11, ~, true], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [Phi, {region: 9}, [13, 27], ~, Int], # 14
  [NumGt, ~, [12, 14], ~, Boolean], # 15
  [If, ~, [9, 15], 9], # 16
  [Proj, {index: 1}, [16]], # 17
  [Region, {head: 9}, [17]], # 18
  [Print, ~, [2], 18, "Maybe[Boolean]"], # 19
  [Phi, {memory: true, region: 18}, [11], ~, List], # 20
  [Return, {implicit: true}, [1], 19, ~, 20], # 21
  [Proj, {index: 0}, [16]], # 22
  [Exists, {kind: array}, [10, 14], 22, Boolean, 11, ~, true], # 23
  [Subscript, {kind: array}, [10, 14], ~, Scalar], # 24
  [Ref, ~, [24], ~, ScalarRef], # 25
  [TernaryExpr, ~, [23, 25, 1], 23, "Maybe[ScalarRef]"], # 26
  [Add, ~, [14, 5], ~, Int], # 27
  [Count, ~, [10], ~, Int, 8, ~, true], # 28
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::z, package: main, param_names: [], want: void}, ~, 26, Int, 11, true], # 29
  [PostfixDeref, {sigil: $}, [26], ~, Scalar, 29, ~, true], # 30
  [Subscript, {kind: array}, [10, 14], ~, Scalar, 29, ~, true], # 31
  [TernaryExpr, ~, [23, 30, 31], 29, Scalar], # 32
  [Coerce, {from_repr: Scalar, to_repr: Str}, [32], ~, Str], # 33
  [Print, ~, [33], 32, "Maybe[Boolean]"]]} # 34
main::z: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 1
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: a}, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Assign, ~, [4, 1], 0, Int, 5, true], # 6
  [Return, {implicit: true}, [1], 6, ~, 6]]} # 7
```

## K4: an assignment as the target of *=

2026-11-25 second final audit class K4, probe z/lv27.

```perl
my $x=3; ($x = $x + 1) *= $x; print "$x\n";
```

```behavior
parses: yes
```

```output
16
```

```ir
refused: [
  "skipped main::__PROGRAM__: GAP: an assignment used as the target of an op= is not yet lowered -- its store would be lost"]
```

## K5: two element op=s as operands of one +

2026-11-25 second final audit class K5, probe z/lv74.

```perl
my @a=(1,2,3); my $n = ($a[0] += 1) + ($a[0] += 1); print "$n @a\n";
```

```behavior
parses: yes
```

```output
6 3 2 3
```

```ir
refused: [
  "skipped main::__PROGRAM__: GAP: an assignment's element is read by alias and a later operand stores into its container -- not yet lowered"]
```

## K6: $g and $g++ handed to one call

2026-11-25 second final audit class K6, probe z/qd40.

```perl
our $g=1; sub f { "@_" } my $s=f($g, $g++); print "$s $g\n";
```

```behavior
parses: yes
```

```output
2 1 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [EntryWrite, ~, [2, 3], 0, Unknown, 4, true, true], # 5
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Int, 5, ~, true], # 6
  [Add, ~, [6, 3], ~, Int], # 7
  [EntryWrite, ~, [2, 7], 5, Unknown, 5, true, true], # 8
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Int, 8, ~, true], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/a8EfE9GJC0/case.pl", line: 1, name: main::f, package: main, param_names: [], want: scalar}, [9, 6], 8, Str, 8, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Int, 10, ~, true], # 14
  [Coerce, {from_repr: Int, to_repr: Str}, [14], ~, Str], # 15
  [Concat, ~, [13, 15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [Print, ~, [18], 10, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [1], 19, ~, 10]]} # 20
main::f: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 1, ~, true], # 2
  [Coerce, {from_repr: Scalar, to_repr: Str}, [2], ~, Str], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [3, 4], ~, Str, 1, ~, true], # 5
  [Return, {implicit: true}, [5], 0, ~, 1]]} # 6
```

## K7: an array in a list, then a later item stores its element

2026-11-25 second final audit class K7, probe z/fl01.

```perl
my @a=(1,2,3); my @b=(@a, $a[0]=9); print "@b\n";
```

```behavior
parses: yes
```

```output
9 2 3 9
```

```ir
refused: [
  "skipped main::__PROGRAM__: GAP: an aggregate flattened into a list is read by alias and a later item may store into its elements -- not yet lowered"]
```

## K8: a list assignment into a foreach iterator

2026-11-25 second final audit class K8, probe z/qf01.

```perl
my @a=(1,2); my $y=9; for my $x (@a) { ($x,$y)=($y,$x) } print "@a $y\n";
```

```behavior
parses: yes
```

```output
9 1 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [29], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Loop, {bound: entry}, [0, 36]], # 3
  [Phi, {memory: true, region: 3}, [2, 36], ~, Unknown], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [ArrayLiteral, {sigil: "@", symbol: a}, [5, 6], ~, Array], # 7
  [Count, ~, [7], ~, Int, 4, ~, true], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Phi, {region: 3}, [9, 37], ~, Int], # 10
  [NumGt, ~, [8, 10], ~, Boolean], # 11
  [If, ~, [3, 11], 3], # 12
  [Proj, {index: 1}, [12]], # 13
  [Region, {head: 3}, [13]], # 14
  [Phi, {memory: true, region: 14}, [4], ~, Unknown], # 15
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 15, ~, true], # 16
  [Coerce, {from_repr: Scalar, to_repr: Str}, [16], ~, Str], # 17
  [PostfixDeref, {sigil: "@"}, [7], ~, Array, 15, ~, true], # 18
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [17, 18], ~, Str, 15, ~, true], # 19
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 22
  [Phi, {region: 3}, [22, 34], ~, Int], # 23
  [Coerce, {from_repr: Int, to_repr: Str}, [23], ~, Str], # 24
  [Concat, ~, [21, 24], ~, Str], # 25
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 26
  [Concat, ~, [25, 26], ~, Str], # 27
  [Print, ~, [27], 14, "Maybe[Boolean]"], # 28
  [Return, {implicit: true}, [1], 28, ~, 15], # 29
  [Subscript, {kind: array}, [7, 10], ~, Scalar], # 30
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown], # 31
  [PadAccess, {sigil: $, symbol: "y"}, ~, ~, Unknown], # 32
  [Proj, {index: 0}, [12]], # 33
  [Subscript, {kind: array}, [7, 10], 33, Int, 4, ~, true], # 34
  [Assign, {targets: 2}, [31, 32, 23, 34], 34, List, 4, true], # 35
  [Assign, ~, [30, 23], 35, Int, 35, true], # 36
  [Add, ~, [10, 5], ~, Int], # 37
  [Count, ~, [7], ~, Int, 2, ~, true]]} # 38
```

## A loop body reads the array, then stores one of its elements

wire-v2 baseline section 20: a read early in a loop body sees the stores of earlier passes.

```perl
my @a=(1,2,3); my $s=""; for my $i (0..2) { $s .= "@a;"; $a[$i] = 0 } print "$s\n";
```

```behavior
parses: yes
```

```output
1 2 3;0 2 3;0 0 3;
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0, 24]], # 3
  [Phi, {region: 3}, [2, 32], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Phi, {region: 3}, [8, 25], ~, Int], # 9
  [NumGt, ~, [7, 9], ~, Boolean], # 10
  [If, ~, [3, 10], 3], # 11
  [Proj, {index: 1}, [11]], # 12
  [Region, {head: 3}, [12]], # 13
  [Print, ~, [6], 13, "Maybe[Boolean]"], # 14
  [MemStart], # 15
  [Phi, {memory: true, region: 3}, [15, 24], ~, Unknown], # 16
  [Phi, {memory: true, region: 13}, [16], ~, Unknown], # 17
  [Return, {implicit: true}, [1], 14, ~, 17], # 18
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 19
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 20
  [ArrayLiteral, {sigil: "@", symbol: a}, [19, 20, 7], ~, Array], # 21
  [Subscript, {kind: array}, [21, 9], ~, Scalar], # 22
  [Proj, {index: 0}, [11]], # 23
  [Assign, ~, [22, 8], 23, Int, 16, true], # 24
  [Add, ~, [9, 19], ~, Int], # 25
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 16, ~, true], # 26
  [Coerce, {from_repr: Scalar, to_repr: Str}, [26], ~, Str], # 27
  [PostfixDeref, {sigil: "@"}, [21], ~, Array, 16, ~, true], # 28
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [27, 28], ~, Str, 16, ~, true], # 29
  [Concat, ~, [4, 29], ~, Str], # 30
  [Constant, {const_type: string, value: ";"}, ~, ~, Str], # 31
  [Concat, ~, [30, 31], ~, Str]]} # 32
```

## A foreach alias write on a pass left by last

wire-v2 baseline section 20: the write is stored where it stands, not at the pass end.

```perl
my @a=(1,2); for my $x (@a) { $x .= "x"; last } print "@a\n";
```

```behavior
parses: yes
```

```output
1x 2
```

```ir
refused: [
  "skipped main::__PROGRAM__: GAP: loop control (last) inside a loop body not yet lowered"]
```

## A postfix foreach over a slice writes the elements

wire-v2 baseline section 26, probe l/lw25.

```perl
my @a=(1,2); my $b=join(",",@a); $_ .= "x" for @a[0,1]; print "$b ", join(",",@a), "\n";
```

```behavior
parses: yes
```

```output
1,2 1x,2x
```

```ir
main::__PROGRAM__: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 3, 4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 3, 4], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 10
  [MemStart], # 11
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar, 11, ~, true], # 12
  [Loop, {bound: entry}, [0, 36]], # 13
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 14
  [ArrayLiteral, {sigil: "@", symbol: a}, [3, 4], ~, Array], # 15
  [Slice, {kind: array}, [14, 3, 15], ~, List], # 16
  [ArrayLiteral, ~, [16], ~, Array], # 17
  [Phi, {memory: true, region: 13}, [11, 36], ~, Unknown], # 18
  [Count, ~, [17], ~, Int, 18, ~, true], # 19
  [Phi, {region: 13}, [14, 37], ~, Int], # 20
  [NumGt, ~, [19, 20], ~, Boolean], # 21
  [If, ~, [13, 21], 13], # 22
  [Proj, {index: 1}, [22]], # 23
  [Region, {head: 13}, [23]], # 24
  [Phi, {memory: true, region: 24}, [18], ~, Unknown], # 25
  [EntryWrite, ~, [10, 12], 24, Unknown, 25, true, true], # 26
  [Print, ~, [7, 8, 9], 26, "Maybe[Boolean]"], # 27
  [Return, {implicit: true}, [1], 27, ~, 26], # 28
  [Proj, {index: 0}, [22]], # 29
  [Subscript, {kind: array}, [17, 20], 29, Scalar, 18, ~, true], # 30
  [Coerce, {from_repr: Scalar, to_repr: Str}, [30], ~, Str], # 31
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 32
  [Concat, ~, [31, 32], ~, Str], # 33
  [Subscript, {kind: array}, [17, 20], ~, Scalar], # 34
  [Assign, ~, [34, 33], 30, Str, 18, true], # 35
  [EntryWrite, ~, [10, 33], 35, Unknown, 35, true, true], # 36
  [Add, ~, [20, 3], ~, Int], # 37
  [Count, ~, [17], ~, Int, 11, ~, true]]} # 38
```

## A loop Phi whose value turns from a number to a string

wire-v2 baseline section 26: a Phi keeps its init's stamp only while no pass changes it.

```perl
my $v = 0; for my $i (1..3) { $v = "s$i" if $i > 1 } print "$v\n";
```

```behavior
parses: yes
```

```output
s3
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Loop, {bound: entry}, [0, 22]], # 3
  [Phi, {region: 3}, [2, 26], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Phi, {region: 3}, [8, 27], ~, Int], # 9
  [NumGt, ~, [7, 9], ~, Boolean], # 10
  [If, ~, [3, 10], 3], # 11
  [Proj, {index: 1}, [11]], # 12
  [Region, {head: 3}, [12]], # 13
  [Print, ~, [6], 13, "Maybe[Boolean]"], # 14
  [MemStart], # 15
  [Return, {implicit: true}, [1], 14, ~, 15], # 16
  [Proj, {index: 0}, [11]], # 17
  [NumGt, ~, [9, 8], ~, Boolean], # 18
  [If, ~, [17, 18], 17], # 19
  [Proj, {index: 0}, [19]], # 20
  [Proj, {index: 1}, [19]], # 21
  [Region, {head: 19}, [20, 21]], # 22
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 23
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 24
  [Concat, ~, [23, 24], ~, Str], # 25
  [Phi, {predecessors: [20, 21], region: 22}, [25, 4], ~, Str], # 26
  [Add, ~, [9, 8], ~, Int]]} # 27
```
