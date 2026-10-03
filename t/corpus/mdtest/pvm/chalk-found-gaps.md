# Gaps chalk's own lib/ found

Programs reduced from subs in chalk's lib/ that B::SoN refused, and from
the wrong answers met while lowering them. Added here by B::SoN and sent to
pvm to place in its tiers; this file is replaced when the corpus is next
copied from pvm.

**Tier 07 subroutines.** Introduces nothing. Depends on 06_control.

## A die guarded inside a loop body

The guard runs on each element; the `die` leaves the loop and the sub on the element that fails it. A reader that steps past the `die` returns "ok" for both calls.

```perl
sub check {
    for my $x (@_) {
        die "too big: $x\n" if $x > 1;
    }
    return "ok";
}
print eval { check(1, 0) } // $@, "\n";
print eval { check(1, 9) } // $@;
```

```behavior
parses: yes
```

```output
ok
too big: 9
```

```ir
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Call, {dispatch_kind: direct, name: main::check, param_names: [], want: scalar}, [2, 4], 0, Str], # 5
  [Region, {eval_entry: 0}, [5]], # 6
  [Phi, {region: 6}, [5, 1], ~, Scalar], # 7
  [MemStart], # 8
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [8], ~, Scalar], # 9
  [DefinedOr, ~, [7, 9], ~, Scalar], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [11, 12], 6, Scalar], # 13
  [Call, {dispatch_kind: direct, name: main::check, param_names: [], want: scalar}, [2, 3], 13, Str], # 14
  [Region, {eval_entry: 13}, [14]], # 15
  [Phi, {region: 15}, [14, 1], ~, Scalar], # 16
  [DefinedOr, ~, [16, 9], ~, Scalar], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Print, ~, [18], 15, Scalar], # 19
  [Return, {implicit: true}, [1], 19]]} # 20
main::check: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ok}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Proj, {index: 1}, [2]], # 3
  [Region, {head: 2}, [3]], # 4
  [Return, ~, [1], 4], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [MemStart], # 7
  [Count, ~, [6, 7], ~, Int], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Phi, {region: 2}, [9, 18], ~, Int], # 10
  [NumGt, ~, [8, 10], 2, Boolean], # 11
  [Proj, {index: 0}, [2]], # 12
  [Subscript, {kind: array}, [6, 10, 7], ~, Scalar], # 13
  [Coerce, {from_repr: Scalar, to_repr: Num}, [13], ~, Num], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [NumGt, ~, [14, 15], ~, Boolean], # 16
  [If, ~, [12, 16], 12], # 17
  [Add, ~, [10, 15], ~, Int], # 18
  [Proj, {index: 0}, [17]], # 19
  [Proj, {index: 1}, [17]], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 21
  [Constant, {const_type: string, value: "too big: "}, ~, ~, Str], # 22
  [Concat, ~, [22, 21], ~, Str], # 23
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 24
  [Concat, ~, [23, 24], ~, Str], # 25
  [Unwind, ~, [25], 19], # 26
  [Region, {head: 17}, [26, 20]]]} # 27
```

## An iterator passed to a call, over read-only values

A foreach iterator aliases its element, and a callee given it may change the element through `$_[0]`. These elements are constants, which perl never writes: writing each one back after the body dies "Modification of a read-only value".

```perl
sub id { $_[0] }
sub keep {
    my $out = "";
    for my $x (@_) {
        next unless id($x) > 1;
        $out .= $x;
    }
    return $out;
}
print keep(1, 2, 3), "\n";
```

```behavior
parses: yes
```

```output
23
```

```ir
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [Call, {dispatch_kind: direct, name: main::keep, param_names: [], want: list}, [2, 3, 4], 0, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, Scalar], # 8
  [Return, {implicit: true}, [1], 8]]} # 9
main::id: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Return, {implicit: true}, [4], 0]]} # 5
main::keep: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 28], ~, Str], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Return, ~, [3], 5], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [MemStart], # 8
  [Count, ~, [7, 8], ~, Int], # 9
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 10
  [Phi, {region: 2}, [10, 29], ~, Int], # 11
  [NumGt, ~, [9, 11], 2, Boolean], # 12
  [Proj, {index: 0}, [2]], # 13
  [PadAccess, {sigil: $, symbol: x}, [8], ~, Unknown], # 14
  [Subscript, {kind: array}, [7, 11, 8], ~, Scalar], # 15
  [Assign, ~, [14, 15], 13, Scalar], # 16
  [PadAccess, {sigil: $, symbol: x}, [16], ~, Str], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Concat, ~, [3, 18], ~, Str], # 19
  [Call, {dispatch_kind: direct, name: main::id, param_names: [], want: scalar}, [17], 16, Scalar], # 20
  [Coerce, {from_repr: Scalar, to_repr: Num}, [20], ~, Num], # 21
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 22
  [NumGt, ~, [21, 22], ~, Boolean], # 23
  [If, ~, [20, 23], 20], # 24
  [Proj, {index: 1}, [24]], # 25
  [Proj, {index: 0}, [24]], # 26
  [Region, {head: 24}, [25, 26]], # 27
  [Phi, {predecessors: [25, 26], region: 27}, [3, 19], ~, Str], # 28
  [Add, ~, [11, 22], ~, Int], # 29
  [Subscript, {kind: array}, [7, 11], ~, Scalar], # 30
  [Assign, {if_changed: true}, [30, 17], 27, Str]]} # 31
```

## A defined-or whose right side calls, in a loop body

The call runs only for the undefined elements: twice, not three times and not never.

```perl
my $calls = 0;
sub fallback { $calls++; return 7 }
my $out = "";
for my $x (undef, 2, undef) {
    my $v = $x // fallback();
    $out .= $v;
}
print "$out $calls\n";
```

```behavior
parses: yes
```

```output
727 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [31], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: $, symbol: calls}, [3], ~, Unknown], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [2, 38], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Proj, {index: 0}, [7]], # 11
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 12
  [ArrayLiteral, ~, [1, 12, 1], ~, Array], # 13
  [Phi, {region: 7}, [5, 36], ~, Int], # 14
  [Subscript, {kind: array}, [13, 14, 6], ~, Scalar], # 15
  [Defined, ~, [15], ~, Boolean], # 16
  [If, ~, [11, 16], 11], # 17
  [Proj, {index: 1}, [17]], # 18
  [Call, {dispatch_kind: direct, name: main::fallback, param_names: [], want: scalar}, ~, 18, Int], # 19
  [Proj, {index: 0}, [17]], # 20
  [Region, {head: 17}, [20, 19]], # 21
  [Phi, {predecessors: [20, 18], region: 21}, [6, 19], ~, Int], # 22
  [PadAccess, {shared: 1, sigil: $, symbol: calls}, [22], ~, Str], # 23
  [Coerce, {from_repr: Unknown, to_repr: Str}, [23], ~, Str], # 24
  [Concat, ~, [10, 24], ~, Str], # 25
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 26
  [Concat, ~, [25, 26], ~, Str], # 27
  [Proj, {index: 1}, [7]], # 28
  [Region, {head: 7}, [28]], # 29
  [Print, ~, [27], 29, Scalar], # 30
  [Return, {implicit: true}, [1], 30], # 31
  [Count, ~, [13, 6], ~, Int], # 32
  [NumGt, ~, [32, 14], 7, Boolean], # 33
  [Phi, {predecessors: [20, 18], region: 21}, [15, 19], ~, Scalar], # 34
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 35
  [Add, ~, [14, 35], ~, Int], # 36
  [Coerce, {from_repr: Unknown, to_repr: Str}, [34], ~, Str], # 37
  [Concat, ~, [8, 37], ~, Str]]} # 38
main::fallback: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 1
  [MemStart], # 2
  [PadAccess, {shared: 1, sigil: $, symbol: calls}, [2], ~, Unknown], # 3
  [Increment, ~, [3], ~, Scalar], # 4
  [Assign, ~, [3, 4], 0, Scalar], # 5
  [Return, ~, [1], 5]]} # 6
```

## A chain of ands with calls, guarding next

Each `id()` runs only when the operands to its left were true, so the calls are counted: 1 for the first element, 3 each for the others.

```perl
my $calls = 0;
sub id { $calls++; return $_[0] }
my $out = "";
for my $x (1, 2, 3, 9) {
    next unless id($x) && id($x) > 1 && id($x) < 9;
    $out .= $x;
}
print "$out $calls\n";
```

```behavior
parses: yes
```

```output
23 11
```

```ir
main::__PROGRAM__: {start: 0, returns: [48], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: $, symbol: calls}, [3], ~, Unknown], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [2, 62], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [PadAccess, {sigil: $, symbol: x}, [6], ~, Unknown], # 11
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 12
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 13
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 14
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 15
  [ArrayLiteral, ~, [12, 13, 14, 15], ~, Array], # 16
  [Phi, {region: 7}, [5, 51], ~, Int], # 17
  [Subscript, {kind: array}, [16, 17, 6], ~, Int], # 18
  [Proj, {index: 0}, [7]], # 19
  [Assign, ~, [11, 18], 19, Int], # 20
  [PadAccess, {sigil: $, symbol: x}, [20], ~, Unknown], # 21
  [Call, {dispatch_kind: direct, name: main::id, param_names: [], want: scalar}, [21], 20, Scalar], # 22
  [PadAccess, {sigil: $, symbol: x}, [22], ~, Unknown], # 23
  [If, ~, [22, 22], 22], # 24
  [Proj, {index: 0}, [24]], # 25
  [Call, {dispatch_kind: direct, name: main::id, param_names: [], want: scalar}, [23], 25, Scalar], # 26
  [Proj, {index: 1}, [24]], # 27
  [Region, {head: 24}, [26, 27]], # 28
  [Phi, {predecessors: [25, 27], region: 28}, [26, 22], ~, Scalar], # 29
  [PadAccess, {sigil: $, symbol: x}, [29], ~, Unknown], # 30
  [Coerce, {from_repr: Scalar, to_repr: Num}, [26], ~, Num], # 31
  [NumGt, ~, [31, 12], ~, Boolean], # 32
  [Phi, {predecessors: [25, 27], region: 28}, [32, 22], ~, Scalar], # 33
  [If, ~, [28, 33], 28], # 34
  [Proj, {index: 0}, [34]], # 35
  [Call, {dispatch_kind: direct, name: main::id, param_names: [], want: scalar}, [30], 35, Scalar], # 36
  [Proj, {index: 1}, [34]], # 37
  [Region, {head: 34}, [36, 37]], # 38
  [Phi, {predecessors: [35, 37], region: 38}, [36, 29], ~, Scalar], # 39
  [PadAccess, {shared: 1, sigil: $, symbol: calls}, [39], ~, Str], # 40
  [Coerce, {from_repr: Unknown, to_repr: Str}, [40], ~, Str], # 41
  [Concat, ~, [10, 41], ~, Str], # 42
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 43
  [Concat, ~, [42, 43], ~, Str], # 44
  [Proj, {index: 1}, [7]], # 45
  [Region, {head: 7}, [45]], # 46
  [Print, ~, [44], 46, Scalar], # 47
  [Return, {implicit: true}, [1], 47], # 48
  [Count, ~, [16, 6], ~, Int], # 49
  [NumGt, ~, [49, 17], 7, Boolean], # 50
  [Add, ~, [17, 12], ~, Int], # 51
  [Coerce, {from_repr: Scalar, to_repr: Num}, [36], ~, Num], # 52
  [NumLt, ~, [52, 15], ~, Boolean], # 53
  [Phi, {predecessors: [35, 37], region: 38}, [53, 33], ~, Scalar], # 54
  [PadAccess, {sigil: $, symbol: x}, [39], ~, Str], # 55
  [Coerce, {from_repr: Unknown, to_repr: Str}, [55], ~, Str], # 56
  [Concat, ~, [8, 56], ~, Str], # 57
  [If, ~, [38, 54], 38], # 58
  [Proj, {index: 1}, [58]], # 59
  [Proj, {index: 0}, [58]], # 60
  [Region, {head: 58}, [59, 60]], # 61
  [Phi, {predecessors: [59, 60], region: 61}, [8, 57], ~, Str]]} # 62
main::id: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: $, symbol: calls}, [3], ~, Unknown], # 4
  [Increment, ~, [4], ~, Scalar], # 5
  [Assign, ~, [4, 5], 0, Scalar], # 6
  [Subscript, {kind: array}, [1, 2, 6], ~, Scalar], # 7
  [Return, ~, [7], 6]]} # 8
```

## A call under a statement modifier inside an if

The call runs only when both guards hold -- once in three calls of `f`.

```perl
my $calls = 0;
sub helper { $calls++ }
sub f {
    my ($x, $y) = @_;
    if ($x > 3) {
        helper() if $y > 3;
    }
}
f(5, 5); f(5, 1); f(1, 5);
print "$calls\n";
```

```behavior
parses: yes
```

```output
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 3
  [MemStart], # 4
  [PadAccess, {shared: 1, sigil: $, symbol: calls}, [4], ~, Unknown], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Assign, ~, [5, 6], 0, Int], # 7
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: void}, [3, 3], 7, Scalar], # 8
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: void}, [3, 2], 8, Scalar], # 9
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: void}, [2, 3], 9, Scalar], # 10
  [PadAccess, {shared: 1, sigil: $, symbol: calls}, [10], ~, Str], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [Print, ~, [14], 10, Scalar], # 15
  [Return, {implicit: true}, [1], 15]]} # 16
main::f: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Num], # 1
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 2
  [NumGt, ~, [1, 2], ~, Boolean], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 0}, [4]], # 5
  [PadAccess, {sigil: $, symbol: "y"}, ~, ~, Num], # 6
  [NumGt, ~, [6, 2], ~, Boolean], # 7
  [If, ~, [5, 7], 5], # 8
  [Proj, {index: 0}, [8]], # 9
  [Call, {dispatch_kind: direct, name: main::helper, param_names: []}, ~, 9, Scalar], # 10
  [Proj, {index: 1}, [8]], # 11
  [Region, {head: 8}, [10, 11]], # 12
  [Phi, {predecessors: [9, 11], region: 12}, [10, 7], ~, Scalar], # 13
  [And, ~, [3, 13], ~, Scalar], # 14
  [Proj, {index: 1}, [4]], # 15
  [Region, {head: 4}, [15, 12]], # 16
  [Return, {implicit: true}, [14], 16], # 17
  [ArgsSource, ~, ~, ~, Array], # 18
  [Assign, ~, [1, 6, 18], ~, List]]} # 19
main::helper: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {shared: 1, sigil: $, symbol: calls}, [1], ~, Unknown], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Scalar], # 4
  [Increment, ~, [2], ~, Scalar], # 5
  [Assign, ~, [2, 5], 0, Scalar], # 6
  [Return, {implicit: true}, [4], 6]]} # 7
```

## A print under a modifier, ending a sub

The `if` is the sub's last statement, so it takes the caller's context: the inner modifier is neither void nor a plain value, and its print still runs only when both guards hold.

```perl
sub report {
    my ($x, $y) = @_;
    if ($x > 3) {
        print "both $x $y\n" if $y > 3;
    }
}
report(5, 5);
report(5, 1);
report(1, 5);
```

```behavior
parses: yes
```

```output
both 5 5
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 3
  [Call, {dispatch_kind: direct, name: main::report, param_names: [], want: void}, [3, 3], 0, Scalar], # 4
  [Call, {dispatch_kind: direct, name: main::report, param_names: [], want: void}, [3, 2], 4, Scalar], # 5
  [Call, {dispatch_kind: direct, name: main::report, param_names: [], want: void}, [2, 3], 5, Scalar], # 6
  [Return, {implicit: true}, [1], 6]]} # 7
main::report: {start: 0, returns: [26], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Num], # 1
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 2
  [NumGt, ~, [1, 2], ~, Boolean], # 3
  [Constant, {const_type: string, value: "both "}, ~, ~, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [PadAccess, {sigil: $, symbol: "y"}, ~, ~, Num], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Concat, ~, [8, 10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [If, ~, [0, 3], 0], # 14
  [Proj, {index: 0}, [14]], # 15
  [NumGt, ~, [9, 2], ~, Boolean], # 16
  [If, ~, [15, 16], 15], # 17
  [Proj, {index: 0}, [17]], # 18
  [Print, ~, [13], 18, Scalar], # 19
  [Proj, {index: 1}, [17]], # 20
  [Region, {head: 17}, [19, 20]], # 21
  [Phi, {predecessors: [18, 20], region: 21}, [19, 16], ~, Scalar], # 22
  [And, ~, [3, 22], ~, Scalar], # 23
  [Proj, {index: 1}, [14]], # 24
  [Region, {head: 14}, [24, 21]], # 25
  [Return, {implicit: true}, [23], 25], # 26
  [ArgsSource, ~, ~, ~, Array], # 27
  [Assign, ~, [1, 9, 27], ~, List]]} # 28
```

