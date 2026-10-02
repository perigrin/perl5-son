# Gaps chalk's own test suite found

Programs reduced from failures in chalk's test suite run against a lib/
that B::SoN had translated and emitted back. Each emission compiled, and
each gave a wrong answer: the corpus had no case for it. Added here by
B::SoN and sent to pvm to place in its tiers; this file is replaced when
the corpus is next copied from pvm.

**Tier 11 oo.** Introduces nothing. Depends on 11_oo.

## The seen-hash idiom

`$seen{$k}++` yields the element's value from before the store. A reader
that reads the element where the value is used -- after the store -- skips
every key. chalk's T2 type-narrowing pass is exactly this loop, and it
narrowed nothing.

```perl
my %seen;
my $out = "";
for my $k (qw(a a b a c)) {
    next if $seen{$k}++;
    $out .= $k;
}
print "$out\n";
```

```behavior
parses: yes
```

```output
abc
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 36], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Proj, {index: 1}, [3]], # 7
  [Region, {head: 3}, [7]], # 8
  [Print, ~, [6], 8, Scalar], # 9
  [Return, {implicit: true}, [1], 9], # 10
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 13
  [ArrayLiteral, ~, [11, 11, 12, 11, 13], ~, Array], # 14
  [MemStart], # 15
  [Count, ~, [14, 15], ~, Int], # 16
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 17
  [Phi, {region: 3}, [17, 26], ~, Int], # 18
  [NumGt, ~, [16, 18], 3, Boolean], # 19
  [Proj, {index: 0}, [3]], # 20
  [PadAccess, {sigil: "%", symbol: seen}, ~, ~, Unknown], # 21
  [Phi, {region: 3}, [15, 29], ~, Unknown], # 22
  [Subscript, {kind: array}, [14, 18, 22], ~, Str], # 23
  [Subscript, {kind: hash}, [21, 23, 22], 20, Scalar], # 24
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 25
  [Add, ~, [18, 25], ~, Int], # 26
  [Increment, ~, [24], ~, Scalar], # 27
  [Subscript, {kind: hash}, [21, 23], ~, Scalar], # 28
  [Assign, ~, [28, 27], 24, Scalar], # 29
  [DefinedOr, ~, [24, 17], ~, Scalar], # 30
  [Concat, ~, [4, 23], ~, Str], # 31
  [If, ~, [29, 30], 29], # 32
  [Proj, {index: 0}, [32]], # 33
  [Proj, {index: 1}, [32]], # 34
  [Region, {head: 32}, [33, 34]], # 35
  [Phi, {predecessors: [33, 34], region: 35}, [4, 31], ~, Str]]} # 36
```

## Pre- and post-increment of an element, used

The post form yields the old value and the pre form the new one, each
exactly once; the second `++$h{a}` sees the first's store.

```perl
my %h;
my $a1 = $h{a}++;
my $a2 = $h{a}++;
my $b1 = ++$h{b};
my $b2 = ++$h{b};
print "$a1 $a2 $h{a} $b1 $b2 $h{b}\n";
```

```behavior
parses: yes
```

```output
0 1 2 1 2 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [45], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {sigil: "%", symbol: h}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [MemStart], # 4
  [Subscript, {kind: hash}, [2, 3, 4], 0, Scalar], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 11
  [Increment, ~, [5], ~, Scalar], # 12
  [Assign, ~, [11, 12], 5, Scalar], # 13
  [Subscript, {kind: hash}, [2, 3, 13], 13, Scalar], # 14
  [DefinedOr, ~, [14, 6], ~, Scalar], # 15
  [Coerce, {from_repr: Scalar, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [10, 16], ~, Str], # 17
  [Concat, ~, [17, 9], ~, Str], # 18
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 19
  [Subscript, {kind: hash}, [2, 19], ~, Scalar], # 20
  [Increment, ~, [14], ~, Scalar], # 21
  [Assign, ~, [11, 21], 14, Scalar], # 22
  [Subscript, {kind: hash}, [2, 19, 22], 22, Scalar], # 23
  [Increment, ~, [23], ~, Scalar], # 24
  [Assign, ~, [20, 24], 23, Scalar], # 25
  [Subscript, {kind: hash}, [2, 19, 25], 25, Scalar], # 26
  [Increment, ~, [26], ~, Scalar], # 27
  [Assign, ~, [20, 27], 26, Scalar], # 28
  [Subscript, {kind: hash}, [2, 3, 28], ~, Scalar], # 29
  [Coerce, {from_repr: Unknown, to_repr: Str}, [29], ~, Str], # 30
  [Concat, ~, [18, 30], ~, Str], # 31
  [Concat, ~, [31, 9], ~, Str], # 32
  [Coerce, {from_repr: Scalar, to_repr: Str}, [24], ~, Str], # 33
  [Concat, ~, [32, 33], ~, Str], # 34
  [Concat, ~, [34, 9], ~, Str], # 35
  [Coerce, {from_repr: Scalar, to_repr: Str}, [27], ~, Str], # 36
  [Concat, ~, [35, 36], ~, Str], # 37
  [Concat, ~, [37, 9], ~, Str], # 38
  [Subscript, {kind: hash}, [2, 19, 28], ~, Scalar], # 39
  [Coerce, {from_repr: Unknown, to_repr: Str}, [39], ~, Str], # 40
  [Concat, ~, [38, 40], ~, Str], # 41
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 42
  [Concat, ~, [41, 42], ~, Str], # 43
  [Print, ~, [43], 28, Scalar], # 44
  [Return, {implicit: true}, [1], 44]]} # 45
```

## A post-increment of undef yields 0

`pp_postinc` sets its result to 0 when the old value is not defined. A
post-decrement does not, and a string comes back as it was.

```perl
my ($x, $y, %h);
my $p = $x++;
my $q = $y--;
my $r = $h{k}++;
my $s = "aa";
my $t = $s++;
print join(",", map { defined $_ ? "[$_]" : "undef" } $p, $q, $r, $t), "\n";
```

```behavior
parses: yes
```

```output
[0],undef,[0],[aa]
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [PadAccess, {sigil: "%", symbol: h}, ~, ~, Unknown], # 4
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 5
  [Subscript, {kind: hash}, [4, 5], ~, Scalar], # 6
  [MemStart], # 7
  [Subscript, {kind: hash}, [4, 5, 7], 0, Scalar], # 8
  [Increment, ~, [8], ~, Scalar], # 9
  [Assign, ~, [6, 9], 8, Scalar], # 10
  [Loop, {bound: entry}, [10], 10], # 11
  [Phi, {region: 11}, [3, 44], ~, Array], # 12
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Proj, {index: 1}, [11]], # 15
  [Region, {head: 11}, [15]], # 16
  [Print, ~, [13, 14], 16, Scalar], # 17
  [Return, {implicit: true}, [1], 17], # 18
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 19
  [DefinedOr, ~, [8, 19], ~, Scalar], # 20
  [Increment, ~, [1], ~, Scalar], # 21
  [DefinedOr, ~, [1, 19], ~, Scalar], # 22
  [Coerce, {from_repr: Undef, to_repr: Num}, [1], ~, Num], # 23
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 24
  [Subtract, ~, [23, 24], ~, Num], # 25
  [Constant, {const_type: string, value: aa}, ~, ~, Str], # 26
  [DefinedOr, ~, [26, 19], ~, Scalar], # 27
  [ArrayLiteral, ~, [22, 1, 20, 27], ~, List], # 28
  [Phi, {region: 11}, [19, 41], ~, Int], # 29
  [Subscript, {kind: array}, [28, 29, 10], ~, Scalar], # 30
  [Defined, ~, [30], ~, Boolean], # 31
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 32
  [Coerce, {from_repr: Scalar, to_repr: Str}, [30], ~, Str], # 33
  [Concat, ~, [32, 33], ~, Str], # 34
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 35
  [Concat, ~, [34, 35], ~, Str], # 36
  [TernaryExpr, ~, [31, 36, 1], ~, Scalar], # 37
  [Count, ~, [28, 10], ~, Int], # 38
  [NumGt, ~, [38, 29], 11, Boolean], # 39
  [Proj, {index: 0}, [11]], # 40
  [Add, ~, [29, 24], ~, Int], # 41
  [Constant, {const_type: string, value: undef}, ~, ~, Str], # 42
  [TernaryExpr, ~, [31, 36, 42], ~, Str], # 43
  [ListAppend, {collector: map}, [12, 43], ~, Array], # 44
  [Increment, ~, [26], ~, Scalar]]} # 45
```

## Named scalars in a map, grep or foreach list

Each list element is aliased to `$_` or the loop variable, so perl flags
the operand as a modifiable lvalue. It is still read for its value.

```perl
my $p = 1 + time() * 0;
my $q = 2 + time() * 0;
my $o = "";
for my $v ($p, $q) { $o .= "[$v]" }
print join(",", map { "[$_]" } $p, $q), " ", join(",", grep { $_ > 1 } $p, $q), " $o\n";
```

```behavior
parses: yes
```

```output
[1],[2] 2 [1][2]
```

```ir
main::__PROGRAM__: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [Loop, {bound: entry}, [0], 0], # 4
  [Proj, {index: 1}, [4]], # 5
  [Region, {head: 4}, [5]], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [3, 51], ~, Array], # 8
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 8], ~, Str], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [ArrayLiteral, ~, ~, ~, Array], # 11
  [Proj, {index: 1}, [7]], # 12
  [Region, {head: 7}, [12]], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Phi, {region: 14}, [11, 57], ~, Array], # 15
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 15], ~, Str], # 16
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 17
  [Phi, {region: 4}, [17, 65], ~, Str], # 18
  [Concat, ~, [10, 18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [Proj, {index: 1}, [14]], # 22
  [Region, {head: 14}, [22]], # 23
  [Print, ~, [9, 10, 16, 21], 23, Scalar], # 24
  [Return, {implicit: true}, [1], 24], # 25
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 26
  [Call, {dispatch_kind: builtin, name: time, param_names: []}, ~, ~, Unknown], # 27
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 28
  [Multiply, ~, [27, 28], ~, Unknown], # 29
  [Add, ~, [26, 29], ~, Unknown], # 30
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 31
  [Call, {dispatch_kind: builtin, name: time, param_names: []}, ~, ~, Unknown], # 32
  [Multiply, ~, [32, 28], ~, Unknown], # 33
  [Add, ~, [31, 33], ~, Unknown], # 34
  [ArrayLiteral, ~, [30, 34], ~, Array], # 35
  [MemStart], # 36
  [Count, ~, [35, 36], ~, Int], # 37
  [Phi, {region: 4}, [28, 41], ~, Int], # 38
  [NumGt, ~, [37, 38], 4, Boolean], # 39
  [Proj, {index: 0}, [4]], # 40
  [Add, ~, [38, 26], ~, Int], # 41
  [Subscript, {kind: array}, [35, 38, 36], ~, Scalar], # 42
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 43
  [ArrayLiteral, ~, [30, 34], ~, List], # 44
  [Phi, {region: 7}, [28, 68], ~, Int], # 45
  [Subscript, {kind: array}, [44, 45, 36], ~, Scalar], # 46
  [Coerce, {from_repr: Unknown, to_repr: Str}, [46], ~, Str], # 47
  [Concat, ~, [43, 47], ~, Str], # 48
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 49
  [Concat, ~, [48, 49], ~, Str], # 50
  [ListAppend, {collector: map}, [8, 50], ~, Array], # 51
  [ArrayLiteral, ~, [30, 34], ~, List], # 52
  [Phi, {region: 14}, [28, 69], ~, Int], # 53
  [Subscript, {kind: array}, [52, 53, 36], ~, Scalar], # 54
  [Coerce, {from_repr: Scalar, to_repr: Num}, [54], ~, Num], # 55
  [NumGt, ~, [55, 26], ~, Boolean], # 56
  [ListAppend, {collector: grep}, [15, 54, 56], ~, Array], # 57
  [Count, ~, [44, 36], ~, Int], # 58
  [Count, ~, [52, 36], ~, Int], # 59
  [Coerce, {from_repr: Unknown, to_repr: Str}, [42], ~, Str], # 60
  [NumGt, ~, [58, 45], 7, Boolean], # 61
  [Proj, {index: 0}, [7]], # 62
  [Concat, ~, [18, 43], ~, Str], # 63
  [Concat, ~, [63, 60], ~, Str], # 64
  [Concat, ~, [64, 49], ~, Str], # 65
  [NumGt, ~, [59, 53], 14, Boolean], # 66
  [Proj, {index: 0}, [14]], # 67
  [Add, ~, [45, 26], ~, Int], # 68
  [Add, ~, [53, 26], ~, Int]]} # 69
```

## A list builtin a sub returns takes the caller's context

`return values %h` is a list in list context and a count in scalar context;
its op records neither, because the caller decides. chalk's MOP lists its
classes this way.

```perl
use feature 'class';
no warnings 'experimental::class';
class Registry {
    field %classes;
    method add ($name) { $classes{$name} = 1; return $self }
    method classes { return values %classes }
}
my $r = Registry->new->add("A")->add("B");
my @all = $r->classes;
my $n = $r->classes;
print scalar(@all), " $n\n";
```

```behavior
parses: yes
```

```output
2 2
```

```ir
Registry::add: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 1
  [FieldAccess, {field_index: 0, field_stash: Registry}, ~, ~, Unknown], # 2
  [Parameter, {index: 0, name: $name, sigil: $}, ~, ~, Unknown], # 3
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int], # 6
  [Return, ~, [1], 6]]} # 7
Registry::classes: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Registry}, ~, ~, Unknown], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: values, param_names: []}, [1, 2], ~, Unknown], # 3
  [Return, ~, [3], 0]]} # 4
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: Registry, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 0, Object], # 2
  [Constant, {const_type: string, value: A}, ~, ~, Str], # 3
  [Call, {class_name: Registry, dispatch_kind: method, name: add, param_names: [], want: scalar}, [2, 3], 2, Unknown], # 4
  [Constant, {const_type: string, value: B}, ~, ~, Str], # 5
  [Call, {class_name: Registry, dispatch_kind: method, name: add, param_names: [], want: scalar}, [4, 5], 4, Unknown], # 6
  [Call, {class_name: Registry, dispatch_kind: method, name: classes, param_names: [], want: list}, [6], 6, Unknown], # 7
  [ArrayLiteral, {sigil: "@", symbol: all}, [7], ~, Array], # 8
  [MemStart], # 9
  [Count, ~, [8, 9], ~, Int], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 12
  [Call, {class_name: Registry, dispatch_kind: method, name: classes, param_names: [], want: scalar}, [6], 7, Unknown], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Concat, ~, [12, 14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Print, ~, [11, 17], 13, Scalar], # 18
  [Return, {implicit: true}, [1], 18]]} # 19
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
```

## A list assignment into a field aggregate

`%registry = $graphs->%*` stores into the object's field. Nothing in the
method reads it afterwards, so a reader that keeps only what the method
itself consumes drops the statement.

```perl
use feature 'class';
no warnings 'experimental::class';
class Holder {
    field %registry;
    field @order;
    method register ($graphs) { %registry = $graphs->%*; @order = sort keys %registry; return $self }
    method clear { @order = (); return $self }
    method summary { return scalar(keys %registry) . ":" . join(",", @order) }
}
my $h = Holder->new->register({ b => 2, a => 1 });
print $h->summary, " ", $h->clear->summary, "\n";
```

```behavior
parses: yes
```

```output
2:a,b 2:
```

```ir
Holder::clear: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 1
  [FieldAccess, {field_index: 1, field_stash: Holder}, ~, ~, Unknown], # 2
  [Assign, ~, [2], 0, Unknown], # 3
  [Return, ~, [1], 3]]} # 4
Holder::register: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 1
  [FieldAccess, {field_index: 1, field_stash: Holder}, ~, ~, Unknown], # 2
  [FieldAccess, {field_index: 0, field_stash: Holder}, ~, ~, Unknown], # 3
  [Parameter, {index: 0, name: $graphs, sigil: $}, ~, ~, Unknown], # 4
  [MemStart], # 5
  [PostfixDeref, {sigil: "%"}, [4, 5], ~, Hash], # 6
  [Assign, ~, [3, 6], 0, List], # 7
  [Call, {dispatch_kind: builtin, name: keys, param_names: []}, [3, 7], ~, List], # 8
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [8], ~, List], # 9
  [Assign, ~, [2, 9], 7, List], # 10
  [Return, ~, [1], 10]]} # 11
Holder::summary: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Holder}, ~, ~, Unknown], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: keys, param_names: []}, [1, 2], ~, Int], # 3
  [Coerce, {from_repr: Int, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: ":"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 7
  [FieldAccess, {field_index: 1, field_stash: Holder}, ~, ~, Unknown], # 8
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [7, 8], ~, Str], # 9
  [Concat, ~, [6, 9], ~, Str], # 10
  [Return, ~, [10], 0]]} # 11
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: Holder, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 0, Object], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [HashLiteral, ~, [3, 4, 5, 6], 2, HashRef], # 7
  [Call, {class_name: Holder, dispatch_kind: method, name: register, param_names: [], want: scalar}, [2, 7], 7, Unknown], # 8
  [Call, {class_name: Holder, dispatch_kind: method, name: summary, param_names: [], want: list}, [8], 8, Str], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [Call, {class_name: Holder, dispatch_kind: method, name: clear, param_names: [], want: scalar}, [8], 9, Unknown], # 12
  [Call, {class_name: Holder, dispatch_kind: method, name: summary, param_names: [], want: list}, [12], 12, Str], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [10, 11, 14, 15], 13, Scalar], # 16
  [Return, {implicit: true}, [1], 16]]} # 17
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
```

## A call in a ternary arm runs only on that arm

The method call is the arm's value, and the arm is taken only when the
element is defined. Run unconditionally, it calls a method on undef.

```perl
use v5.36;
use feature 'class';
no warnings 'experimental::class';
class Node { field $id :param; method id { return $id } }
sub ids ($in) { return join(",", map { defined($_) ? $_->id : "undef" } $in->@*) }
sub fib ($n) { return $n < 2 ? $n : fib($n - 1) + fib($n - 2) }
print ids([Node->new(id => 1), undef, Node->new(id => 3)]), " ", fib(10), "\n";
```

```behavior
parses: yes
```

```output
1,undef,3 55
```

```ir
Node::id: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Node}, ~, ~, Unknown], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [id], want: list}, [2], 0, Object], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [id], want: list}, [4], 3, Object], # 5
  [ArrayLiteral, ~, [3, 1, 5], 5, ArrayRef], # 6
  [Call, {dispatch_kind: direct, name: main::ids, param_names: [], want: list}, [6], 6, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 10
  [Call, {dispatch_kind: direct, name: main::fib, param_names: [], want: list}, [10], 7, Unknown], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [8, 9, 12, 13], 11, Scalar], # 14
  [Return, {implicit: true}, [1], 14]]} # 15
main::fib: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $n, sigil: $}, ~, ~, Num], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Subtract, ~, [1, 2], ~, Num], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [NumLt, ~, [1, 4], ~, Boolean], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 1}, [6]], # 7
  [Call, {dispatch_kind: direct, name: main::fib, param_names: [], want: scalar}, [3], 7, Unknown], # 8
  [Subtract, ~, [1, 4], ~, Num], # 9
  [Call, {dispatch_kind: direct, name: main::fib, param_names: [], want: scalar}, [9], 8, Unknown], # 10
  [Add, ~, [8, 10], ~, Unknown], # 11
  [Proj, {index: 0}, [6]], # 12
  [Region, {head: 6}, [12, 10]], # 13
  [Phi, {predecessors: [12, 7], region: 13}, [1, 11], ~, Unknown], # 14
  [Return, ~, [14], 13]]} # 15
main::ids: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 26], ~, Array], # 4
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 4], ~, Str], # 5
  [Proj, {index: 1}, [3]], # 6
  [Region, {head: 3}, [6]], # 7
  [Return, ~, [5], 7], # 8
  [Parameter, {index: 0, name: $in, sigil: $}, ~, ~, Unknown], # 9
  [MemStart], # 10
  [PostfixDeref, {sigil: "@"}, [9, 10], ~, Array], # 11
  [Count, ~, [11, 10], ~, Int], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [Phi, {region: 3}, [13, 28], ~, Int], # 14
  [NumGt, ~, [12, 14], 3, Boolean], # 15
  [Proj, {index: 0}, [3]], # 16
  [Subscript, {kind: array}, [11, 14, 10], ~, Scalar], # 17
  [Defined, ~, [17], ~, Boolean], # 18
  [If, ~, [16, 18], 16], # 19
  [Proj, {index: 0}, [19]], # 20
  [Call, {dispatch_kind: method, name: id, param_names: [], want: list}, [17], 20, Unknown], # 21
  [Constant, {const_type: string, value: undef}, ~, ~, Str], # 22
  [Proj, {index: 1}, [19]], # 23
  [Region, {head: 19}, [21, 23]], # 24
  [Phi, {predecessors: [20, 23], region: 24}, [21, 22], ~, Unknown], # 25
  [ListAppend, {collector: map}, [4, 25], ~, Array], # 26
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 27
  [Add, ~, [14, 27], ~, Int]]} # 28
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
```

## A method returning an array, called in list context

The method's `return @parts` is a list to a list-context caller and a count
to a scalar one; the call site's context decides. chalk's IR nodes build
their content hash as `join('|', $op, $self->_serialize_inputs())`.

```perl
use feature 'class';
no warnings 'experimental::class';
class Node {
    method parts { my @p; push @p, "a", "b"; return @p }
    method hash  { return join("|", "op", $self->parts) }
    method count { my $c = $self->parts; return $c }
}
print Node->new->hash, " ", Node->new->count, "\n";
```

```behavior
parses: yes
```

```output
op|a|b 2
```

```ir
Node::count: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 1
  [Call, {class_name: Node, dispatch_kind: method, name: parts, param_names: [], want: scalar}, [1], 0, Unknown], # 2
  [Return, ~, [2], 2]]} # 3
Node::hash: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: op}, ~, ~, Str], # 2
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 3
  [Call, {class_name: Node, dispatch_kind: method, name: parts, param_names: [], want: list}, [3], 0, Unknown], # 4
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 2, 4], ~, Str], # 5
  [Return, ~, [5], 4]]} # 6
Node::parts: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {sigil: "@", symbol: p}, ~, ~, Unknown], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [1, 2, 3], 0, Unknown], # 4
  [Return, ~, [1], 4]]} # 5
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 0, Object], # 2
  [Call, {class_name: Node, dispatch_kind: method, name: hash, param_names: [], want: list}, [2], 2, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 3, Object], # 6
  [Call, {class_name: Node, dispatch_kind: method, name: count, param_names: [], want: list}, [6], 6, Unknown], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [4, 5, 8, 9], 7, Scalar], # 10
  [Return, {implicit: true}, [1], 10]]} # 11
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
```

## A signature's placeholder parameter keeps its place

`($, $phi)` takes two arguments and names the second: called as a class
method, the class name fills the placeholder.

```perl
use v5.36;
package Optimizer { sub collapse ($, $phi) { return "c$phi" } }
print Optimizer->collapse(7), " ", (eval { Optimizer->collapse(); 1 } ? "ran" : "too few"), "\n";
```

```behavior
parses: yes
```

```output
c7 too few
```

```ir
Optimizer::collapse: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 1
  [Parameter, {index: 1, name: $phi, sigil: $}, ~, ~, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Concat, ~, [1, 3], ~, Str], # 4
  [Return, ~, [4], 0]]} # 5
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: Optimizer}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 3
  [Call, {class_name: Optimizer, dispatch_kind: method, name: collapse, param_names: [], want: list}, [2, 3], 0, Unknown], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Call, {class_name: Optimizer, dispatch_kind: method, name: collapse, param_names: [], want: void}, [2], 4, Unknown], # 8
  [Region, {eval_entry: 4}, [8]], # 9
  [Phi, {region: 9}, [7, 1], ~, Scalar], # 10
  [Constant, {const_type: string, value: ran}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: "too few"}, ~, ~, Str], # 12
  [TernaryExpr, ~, [10, 11, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [5, 6, 13, 14], 9, Scalar], # 15
  [Return, {implicit: true}, [1], 15]]} # 16
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
```
