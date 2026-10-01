# Gaps chalk's own test suite found

Three programs reduced from failures in chalk's test suite run against a
lib/ that B::SoN had translated and emitted back. Each emission compiled,
and each gave a wrong answer: the corpus had no case for it. Added here by
B::SoN and sent to pvm to place in its tiers; this file is replaced when
the corpus is next copied from pvm.

**Tier 11 oo.** Introduces nothing. Depends on 11_oo.

## A `:param` field defaulting to a folded boolean

`!!0` and `!!1` fold to perl's shared false and true SVs, which a reader of
the constant sees as special values rather than as a number or a string.
Dropping that default makes the `:param` REQUIRED.

```perl
use feature 'class';
no warnings 'experimental::class';
class Flags { field $quiet :param :reader = !!0; field $loud :param :reader = !!1; }
my $f = Flags->new;
print $f->quiet ? "q" : "-", $f->loud ? "l" : "-", Flags->new(quiet => 1)->quiet ? "Q" : "-", "\n";
```

```behavior
parses: yes
```

```output
-lQ
```

```ir
Flags::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: boolean, value: ""}, ~, ~, Boolean], # 1
  [Return, ~, [1], 0]]} # 2
Flags::__DEFAULT_1: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: boolean, value: "1"}, ~, ~, Boolean], # 1
  [Return, ~, [1], 0]]} # 2
Flags::loud: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 1, field_stash: Flags}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
Flags::quiet: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Flags}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: Flags, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 2
  [Call, {class_name: Flags, dispatch_kind: method, name: quiet, param_names: []}, [2], 2, Scalar], # 3
  [Constant, {const_type: string, value: q}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 5
  [TernaryExpr, ~, [3, 4, 5], ~, Str], # 6
  [Call, {class_name: Flags, dispatch_kind: method, name: loud, param_names: []}, [2], 3, Scalar], # 7
  [Constant, {const_type: string, value: l}, ~, ~, Str], # 8
  [TernaryExpr, ~, [7, 8, 5], ~, Str], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Call, {class_name: Flags, dispatch_kind: method, name: new, param_names: [quiet]}, [10], 7, Object], # 11
  [Call, {class_name: Flags, dispatch_kind: method, name: quiet, param_names: []}, [11], 11, Scalar], # 12
  [Constant, {const_type: string, value: Q}, ~, ~, Str], # 13
  [TernaryExpr, ~, [12, 13, 5], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [6, 9, 14, 15], 12, Scalar], # 16
  [Return, ~, [1], 16]]} # 17
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## A field post-increment whose value is used

`my $id = $count++` stores the incremented field and yields the old value.
The guarded early return is the shape the failure came from.

```perl
use feature 'class';
no warnings 'experimental::class';
class Index {
    field %id_for;
    field $count = 0;
    method register ($key) {
        return $id_for{$key} if exists $id_for{$key};
        my $id = $count++;
        $id_for{$key} = $id;
        return $id;
    }
}
my $ix = Index->new;
print join(",", $ix->register("a"), $ix->register("b"), $ix->register("a"), $ix->register("c")), "\n";
```

```behavior
parses: yes
```

```output
0,1,0,2
```

```ir
Index::__DEFAULT_1: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Index::register: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Index}, ~, ~, Unknown], # 1
  [Parameter, {index: 0, name: $key, sigil: $}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [Subscript, {kind: hash}, [1, 2, 3], ~, Scalar], # 4
  [Exists, ~, [1, 2, 3], ~, Boolean], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 1}, [6]], # 7
  [FieldAccess, {field_index: 1, field_stash: Index}, ~, 7, Int], # 8
  [Proj, {index: 0}, [6]], # 9
  [Subscript, {kind: hash}, [1, 2], ~, Scalar], # 10
  [FieldAccess, {field_index: 1, field_stash: Index}, ~, ~, Int], # 11
  [Increment, ~, [8], ~, Scalar], # 12
  [Assign, ~, [11, 12], 8, Scalar], # 13
  [Assign, ~, [10, 8], 13, Int], # 14
  [Region, {head: 6}, [9, 14]], # 15
  [Phi, {predecessors: [9, 7], region: 15}, [4, 8], ~, Scalar], # 16
  [Return, ~, [16], 15]]} # 17
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [Call, {class_name: Index, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Call, {class_name: Index, dispatch_kind: method, name: register, param_names: []}, [3, 4], 3, Scalar], # 5
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 6
  [Call, {class_name: Index, dispatch_kind: method, name: register, param_names: []}, [3, 6], 5, Scalar], # 7
  [Call, {class_name: Index, dispatch_kind: method, name: register, param_names: []}, [3, 4], 7, Scalar], # 8
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 9
  [Call, {class_name: Index, dispatch_kind: method, name: register, param_names: []}, [3, 9], 8, Scalar], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 5, 7, 8, 10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [11, 12], 10, Scalar], # 13
  [Return, ~, [1], 13]]} # 14
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## A map topic passed to a sub

The topic is passed by alias, so perl marks it a potential lvalue; it is
still a read of the element.

```perl
sub shout { return uc $_[0] }
my @loud = map { shout($_) } qw(a b c);
print "@loud\n";
```

```behavior
parses: yes
```

```output
A B C
```

```ir
main::__PROGRAM__: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 4
  [ArrayLiteral, ~, [2, 3, 4], ~, List], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Loop, {bound: entry}, [0], 0], # 7
  [Phi, {region: 7}, [6, 27], ~, Int], # 8
  [MemStart], # 9
  [Subscript, {kind: array}, [5, 8, 9], ~, Str], # 10
  [Proj, {index: 0}, [7]], # 11
  [Call, {dispatch_kind: direct, name: main::shout, param_names: [], want: list}, [10], 11, Str], # 12
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [12], ~, Scalar], # 13
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 14
  [ArrayLiteral, ~, ~, ~, Array], # 15
  [Phi, {region: 7}, [15, 28], ~, Array], # 16
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [14, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Proj, {index: 1}, [7]], # 20
  [Region, {head: 7}, [20]], # 21
  [Print, ~, [19], 21, Scalar], # 22
  [Return, ~, [1], 22], # 23
  [Count, ~, [5, 9], ~, Int], # 24
  [NumGt, ~, [24, 8], 7, Boolean], # 25
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 26
  [Add, ~, [8, 26], ~, Int], # 27
  [ListAppend, {collector: map}, [16, 12], ~, Array]]} # 28
main::shout: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Call, {dispatch_kind: builtin, name: uc, param_names: []}, [4], ~, Str], # 5
  [Return, ~, [5], 0]]} # 6
```
