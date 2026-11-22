# The `class` feature

`class`, `field`, `method` and `ADJUST`: four keywords that a reader
would call the subject of this tier and that produce, between them,
tier 05's `enterloop` and `leaveloop` plus `stub` and `methstart`.

**Tier 11 oo.** Introduces `anonhash`, `bless`, `emptyavhv`, `isa`,
`method`, `method_named`, `method_super`, `methstart`, `stub`,
`tie`, `tied`. Depends on 08_references.

This is the sharpest case in the corpus of a construct the optimiser
erases. Measured, neither `use feature 'class'` nor `no warnings
'experimental::class'` emits a runtime op, so the pragmas the syntax
requires cost this tier nothing and do not borrow tier 12's `use`. `use
v5.42;` is not enough on its own: it does not enable `feature 'class'`
in 5.42.0 and `class Foo` under it is a syntax error, so each case
names the feature. The constructor perl generates is XS code with no
Perl optree, so nothing this tier introduces can be measured through
it; `ref` on the result is what shows the class exists.

## An empty class body

`class Empty {}` is a complete, working class -- `Empty->new` returns
an object -- and it compiles to a bare block containing `stub`. There
is no `class` op:

    1  <0> enter v
    2  <;> nextstate(main 3 d.pl:3) v:%,{,fea=15
    3  <{> enterloop(next->5 last->5 redo->4) v
    4  <0> stub v
    5  <2> leaveloop vK/2

```perl
use feature 'class';
no warnings 'experimental::class';
class Empty {}
print ref(Empty->new), "\n";
```

```behavior
parses: yes
```

```output
Empty
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {class_name: Empty, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: new, package: main, param_names: [], want: scalar}, ~, 0, Object, 2, true], # 3
  [RefType, ~, [3], ~, Str, 3], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## `field` and `method` in a class body

`field` and `method` emit no op of their own. A class body holding both
compiles to a bare block of `nextstate`s and nothing else:

    3  <{> enterloop(next->5 last->5 redo->4) v
    4  <;> nextstate(Foo 7 a.pl:4) v:%,us,*,&,{,$,fea=15,0x10
    5  <2> leaveloop vK/2

`field $x = 5;` contributes one `nextstate` and NO store: the
initialiser is compiled into a field-init tree that is not reachable
from the main optree. The method body is likewise its own CV, so the
`methstart` that opens it is not in the main stream -- naming it takes
`-exec,Foo::m`:

    Foo::m:
    1  <+> methstart() v
    2  <;> nextstate(Foo 10 a.pl:4) v:%,us,*,&,$,fea=15,0x10
    3  <0> padsv[$x:FAKE:] s
    4  <1> leavesub[1 ref] K/REFC,1

That is the finding, not an omission: the op stream of a file using
`class` says almost nothing about the class. `methstart` has no classic
counterpart -- a `sub` doing the same job opens with `shift`. Two
spellings of one object system, two disjoint prefixes.

```perl
use feature 'class';
no warnings 'experimental::class';
class Foo {
    field $x = 5;
    method m { $x }
}
my $o = Foo->new;
print $o->m, "\n";
```

```behavior
parses: yes
```

```output
5
```

```ir
Foo::__DEFAULT_0: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
Foo::m: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 0, field_stash: Foo}, ~, ~, Int, 1], # 2
  [Return, {implicit: true}, [2], 0, ~, 1]]} # 3
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: Foo}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: Foo, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [Call, {class_name: Foo, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: m, package: main, param_names: [], want: list}, [5], 5, Int, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## `ADJUST` alone in a class body

`ADJUST` runs after construction and emits no op of its own. It becomes
an anonymous sub in the class stash with no CODE slot, so B::Concise
cannot name it and its body is unreachable from any dump; what the main
optree shows is a `nextstate` where the block was, and the whole class
body is three ops:

    3  <{> enterloop(next->5 last->5 redo->4) v
    4  <;> nextstate(Foo 5 f.pl:4) v:%,{,fea=15
    5  <2> leaveloop vK/2

ADJUST sits here BY ITSELF on purpose, and it parses under our parser.
The adjacency body is the same construct with a `method` after it, and
the pair is the whole demonstration: one construct per file goes green
over an adjacency bug by construction, because every construct in such
a corpus is measured alone.

```perl
use feature 'class';
no warnings 'experimental::class';
class Foo {
    field $x = 1;
    ADJUST { $x = 2 }
}
print ref(Foo->new), "\n";
```

```behavior
parses: yes
```

```output
Foo
```

```ir
Foo::__ADJUST_0: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [FieldAccess, {field_index: 0, field_stash: Foo}, ~, ~, Int], # 2
  [MemStart], # 3
  [Assign, ~, [2, 1], 0, Int, 3, true], # 4
  [Return, {implicit: true}, [1], 4, ~, 4]]} # 5
Foo::__DEFAULT_0: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: Foo}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: Foo, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [RefType, ~, [5], ~, Str, 5], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, "Maybe[Boolean]"], # 8
  [Return, {implicit: true}, [1], 8, ~, 5]]} # 9
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A `:param` field defaulting to a folded boolean

`!!0` and `!!1` fold at compile time to perl's shared immortals `sv_no`
and `sv_yes`, which B reports as `B::SPECIAL` rather than an IV, NV or
PV. A reader that knows only those three drops the default, and the
`:param` becomes required: `Flags->new` with no arguments then dies.
Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl, which compiled and gave a wrong answer.

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
Flags::__DEFAULT_0: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: boolean, value: ""}, ~, ~, Boolean], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
Flags::__DEFAULT_1: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: boolean, value: "1"}, ~, ~, Boolean], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
Flags::loud: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 1, field_stash: Flags}, ~, ~, Scalar], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
Flags::quiet: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Flags}, ~, ~, Scalar], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: Flags}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: Flags, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [Call, {class_name: Flags, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: quiet, package: main, param_names: [], want: scalar}, [5], 5, Scalar, 5, true], # 6
  [Constant, {const_type: string, value: q}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 8
  [TernaryExpr, ~, [6, 7, 8], ~, Str], # 9
  [Call, {class_name: Flags, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: loud, package: main, param_names: [], want: scalar}, [5], 6, Scalar, 6, true], # 10
  [Constant, {const_type: string, value: l}, ~, ~, Str], # 11
  [TernaryExpr, ~, [10, 11, 8], ~, Str], # 12
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 13
  [Call, {class_name: Flags, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: new, package: main, param_names: [quiet], want: scalar}, [13], 10, Object, 10, true], # 14
  [Call, {class_name: Flags, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: quiet, package: main, param_names: [], want: scalar}, [14], 14, Scalar, 14, true], # 15
  [Constant, {const_type: string, value: Q}, ~, ~, Str], # 16
  [TernaryExpr, ~, [15, 16, 8], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [9, 12, 17, 18], 15, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [1], 19, ~, 15]]} # 20
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A field post-increment whose value is used

`$count++` on a field must store the incremented value AND yield the
old one, here after a guarded early return that leaves the field
untouched. An implementation that only stores, or only yields, numbers
the keys wrongly. Found the same way as the case above.

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
Index::__DEFAULT_1: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
Index::register: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Index}, ~, ~, Unknown], # 1
  [Parameter, {index: 0, name: $key, sigil: $}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [Subscript, {kind: hash}, [1, 2], ~, Scalar, 3], # 4
  [Exists, {kind: hash}, [1, 2], ~, Boolean, 3], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 1}, [6]], # 7
  [FieldAccess, {field_index: 1, field_stash: Index}, ~, 7, Int, 3], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [DefinedOr, ~, [8, 9], ~, Scalar], # 10
  [Proj, {index: 0}, [6]], # 11
  [Subscript, {kind: hash}, [1, 2], ~, Scalar], # 12
  [FieldAccess, {field_index: 1, field_stash: Index}, ~, ~, Int], # 13
  [Increment, ~, [8], ~, Scalar], # 14
  [Assign, ~, [13, 14], 8, Scalar, 3, true], # 15
  [Assign, ~, [12, 10], 15, Scalar, 15, true], # 16
  [Region, {head: 6}, [11, 16]], # 17
  [Phi, {predecessors: [11, 7], region: 17}, [4, 10], ~, Scalar], # 18
  [Phi, {exits: true, memory: true, predecessors: [11, 7], region: 17}, [3, 16], ~, Unknown], # 19
  [Return, ~, [18], 17, ~, 19]]} # 20
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [PackageMark, {package: Index}, ~, 0], # 3
  [PackageMark, {package: main}, ~, 3], # 4
  [MemStart], # 5
  [Call, {class_name: Index, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 13, name: new, package: main, param_names: [], want: scalar}, ~, 4, Object, 5, true], # 6
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 7
  [Call, {class_name: Index, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 14, name: register, package: main, param_names: [], want: list}, [6, 7], 6, Scalar, 6, true], # 8
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 9
  [Call, {class_name: Index, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 14, name: register, package: main, param_names: [], want: list}, [6, 9], 8, Scalar, 8, true], # 10
  [Call, {class_name: Index, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 14, name: register, package: main, param_names: [], want: list}, [6, 7], 10, Scalar, 10, true], # 11
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 12
  [Call, {class_name: Index, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 14, name: register, package: main, param_names: [], want: list}, [6, 12], 11, Scalar, 11, true], # 13
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 8, 10, 11, 13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [14, 15], 13, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 13]]} # 17
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A string built into a field

perl fuses the build and the store into one op: `$log .= "<$x>"` and
`$log = "[$log]"` are each a `multiconcat` writing the field's slot,
with no assignment op to see. A reader that takes the slot for a
lexical rebinds a name and never writes the field. Both forms, in a
method and in an ADJUST block. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl: a silent drop, wrong through perl5-son 63fa6fa.

```perl
use feature 'class';
no warnings 'experimental::class';
class Log {
    field $log = "";
    ADJUST { $log .= "start" }
    method add ($x) { $log .= "<$x>"; return $self }
    method close { $log = "[$log]"; return $log }
}
print Log->new->add("a")->add("b")->close, "\n";
```

```behavior
parses: yes
```

```output
[start<a><b>]
```

```ir
Log::__ADJUST_0: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 0, field_stash: Log}, ~, 0, Str, 1], # 2
  [Constant, {const_type: string, value: start}, ~, ~, Str], # 3
  [Concat, ~, [2, 3], ~, Str], # 4
  [FieldAccess, {field_index: 0, field_stash: Log}, ~, ~, Str], # 5
  [Assign, ~, [5, 4], 2, Str, 1, true], # 6
  [Return, {implicit: true}, [4], 6, ~, 6]]} # 7
Log::__DEFAULT_0: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
Log::add: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 1
  [FieldAccess, {field_index: 0, field_stash: Log}, ~, ~, Str], # 2
  [MemStart], # 3
  [FieldAccess, {field_index: 0, field_stash: Log}, ~, 0, Str, 3], # 4
  [Constant, {const_type: string, value: "<"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Concat, ~, [6, 8], ~, Str], # 9
  [Constant, {const_type: string, value: ">"}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Assign, ~, [2, 11], 4, Str, 3, true], # 12
  [Return, ~, [1], 12, ~, 12]]} # 13
Log::close: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Log}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [MemStart], # 3
  [FieldAccess, {field_index: 0, field_stash: Log}, ~, ~, Str, 3], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Concat, ~, [2, 5], ~, Str], # 6
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [Assign, ~, [1, 8], 0, Str, 3, true], # 9
  [FieldAccess, {field_index: 0, field_stash: Log}, ~, ~, Str, 9], # 10
  [Return, ~, [10], 9, ~, 9]]} # 11
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: Log}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: Log, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 6
  [Call, {class_name: Log, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: add, package: main, param_names: [], want: scalar}, [5, 6], 5, Unknown, 5, true], # 7
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 8
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: add, package: main, param_names: [], want: scalar}, [7, 8], 7, Unknown, 7, true], # 9
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: close, package: main, param_names: [], want: list}, [9], 9, Unknown, 9, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [11, 12], 10, "Maybe[Boolean]"], # 13
  [Return, {implicit: true}, [1], 13, ~, 10]]} # 14
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## `//=` into a field from a call

The right side of `//=` runs only when the field is undefined, and the
store happens only then. Here it is a method call, so running it on the
other path shows in the call count. chalk's IR nodes default their
operands this way in ADJUST. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl: a silent drop, wrong through perl5-son 63fa6fa.

```perl
use feature 'class';
no warnings 'experimental::class';
class Node {
    field $inputs :param;
    field $left :param = undef;
    field $calls = 0;
    ADJUST { $left //= $self->first }
    method first { $calls++; return $inputs->[0] }
    method left { return $left }
    method calls { return $calls }
}
my $a = Node->new(inputs => [7, 8]);
my $b = Node->new(inputs => [7, 8], left => 1);
print join(",", $a->left, $a->calls, $b->left, $b->calls), "\n";
```

```behavior
parses: yes
```

```output
7,1,1,0
```

```ir
Node::__ADJUST_0: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 1, field_stash: Node}, ~, 0, Scalar, 1], # 2
  [Defined, ~, [2], ~, Boolean], # 3
  [If, ~, [2, 3], 2], # 4
  [Proj, {index: 0}, [4]], # 5
  [FieldAccess, {field_index: 1, field_stash: Node}, ~, ~, Scalar], # 6
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 7
  [Proj, {index: 1}, [4]], # 8
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: first, package: Node, param_names: [], want: scalar}, [7], 8, Scalar, 1, true], # 9
  [Assign, ~, [6, 9], 9, Scalar, 9, true], # 10
  [Region, {head: 4}, [5, 10]], # 11
  [Phi, {memory: true, predecessors: [5, 8], region: 11}, [1, 10], ~, Unknown], # 12
  [FieldAccess, {field_index: 1, field_stash: Node}, ~, 11, Scalar, 12], # 13
  [Return, {implicit: true}, [13], 13, ~, 12]]} # 14
Node::__DEFAULT_1: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
Node::__DEFAULT_2: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
Node::calls: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 2, field_stash: Node}, ~, ~, Int, 1], # 2
  [Return, ~, [2], 0, ~, 1]]} # 3
Node::first: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 2, field_stash: Node}, ~, ~, Int], # 1
  [MemStart], # 2
  [FieldAccess, {field_index: 2, field_stash: Node}, ~, 0, Int, 2], # 3
  [Increment, ~, [3], ~, Scalar], # 4
  [Assign, ~, [1, 4], 3, Scalar, 2, true], # 5
  [FieldAccess, {field_index: 0, field_stash: Node}, ~, ~, Unknown, 5], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [6, 7], 5, Scalar, 5, true], # 8
  [Return, ~, [8], 8, ~, 8]]} # 9
Node::left: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 1, field_stash: Node}, ~, ~, Scalar, 1], # 2
  [Return, ~, [2], 0, ~, 1]]} # 3
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "8"}, ~, ~, Int], # 4
  [PackageMark, {package: Node}, ~, 0], # 5
  [PackageMark, {package: main}, ~, 5], # 6
  [ArrayLiteral, ~, [3, 4], 6, ArrayRef], # 7
  [MemStart], # 8
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 12, name: new, package: main, param_names: [inputs], want: scalar}, [7], 7, Object, 8, true], # 9
  [ArrayLiteral, ~, [3, 4], 9, ArrayRef], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 13, name: new, package: main, param_names: [inputs, left], want: scalar}, [10, 11], 10, Object, 9, true], # 12
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 14, name: left, package: main, param_names: [], want: list}, [9], 12, Scalar, 12, true], # 13
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 14, name: calls, package: main, param_names: [], want: list}, [9], 13, Int, 13, true], # 14
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 14, name: left, package: main, param_names: [], want: list}, [12], 14, Scalar, 14, true], # 15
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 14, name: calls, package: main, param_names: [], want: list}, [12], 15, Int, 15, true], # 16
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 13, 14, 15, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [17, 18], 16, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [1], 19, ~, 16]]} # 20
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A subclass's ADJUST when its parent has one

Every ADJUST block of the class chain runs, the parent's first. A
reader that separates a class's own blocks from inherited ones by
counting the parent's must count them: the class's own block is the
one this case watches. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl: a silent drop, wrong through perl5-son 63fa6fa.

```perl
use feature 'class';
no warnings 'experimental::class';
class Base {
    field $trail = "";
    ADJUST { $trail .= "b" }
    method mark ($c) { $trail .= $c; return }
    method trail { return $trail }
}
class Derived :isa(Base) {
    ADJUST { $self->mark("d") }
}
print Derived->new->trail, "\n";
```

```behavior
parses: yes
```

```output
bd
```

```ir
Base::__ADJUST_0: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 0, field_stash: Base}, ~, 0, Str, 1], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Concat, ~, [2, 3], ~, Str], # 4
  [FieldAccess, {field_index: 0, field_stash: Base}, ~, ~, Str], # 5
  [Assign, ~, [5, 4], 2, Str, 1, true], # 6
  [Return, {implicit: true}, [4], 6, ~, 6]]} # 7
Base::__DEFAULT_0: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
Base::mark: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 2
  [FieldAccess, {field_index: 0, field_stash: Base}, ~, ~, Str], # 3
  [MemStart], # 4
  [FieldAccess, {field_index: 0, field_stash: Base}, ~, 0, Str, 4], # 5
  [Parameter, {index: 0, name: $c, sigil: $}, ~, ~, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Concat, ~, [5, 7], ~, Str], # 8
  [Assign, ~, [3, 8], 5, Str, 4, true], # 9
  [Return, ~, [1, 2], 9, ~, 9]]} # 10
Base::trail: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 0, field_stash: Base}, ~, ~, Str, 1], # 2
  [Return, ~, [2], 0, ~, 1]]} # 3
Derived::__ADJUST_0: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 1
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {class_name: Derived, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: mark, package: Derived, param_names: []}, [1, 2], 0, Unknown, 3, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: Base}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: Derived, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 12, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [Call, {class_name: Derived, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 12, name: trail, package: main, param_names: [], want: list}, [5], 5, Unknown, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A list builtin a sub returns takes the caller's context

`return values %h` is a list in list context and a count in scalar context; its op records neither, because the caller decides. chalk's MOP lists its classes this way. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl.

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
Registry::add: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 1
  [FieldAccess, {field_index: 0, field_stash: Registry}, ~, ~, Unknown], # 2
  [Parameter, {index: 0, name: $name, sigil: $}, ~, ~, Unknown], # 3
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Assign, ~, [4, 5], 0, Int, 6, true], # 7
  [Return, ~, [1], 7, ~, 7]]} # 8
Registry::classes: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Registry}, ~, ~, Unknown], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: values, param_names: []}, [1], ~, Unknown, 2], # 3
  [Return, ~, [3], 0, ~, 2]]} # 4
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: Registry}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: Registry, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [Constant, {const_type: string, value: A}, ~, ~, Str], # 6
  [Call, {class_name: Registry, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: add, package: main, param_names: [], want: scalar}, [5, 6], 5, Unknown, 5, true], # 7
  [Constant, {const_type: string, value: B}, ~, ~, Str], # 8
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: add, package: main, param_names: [], want: scalar}, [7, 8], 7, Unknown, 7, true], # 9
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: classes, package: main, param_names: [], want: list}, [9], 9, Unknown, 9, true], # 10
  [ArrayLiteral, {sigil: "@", symbol: all}, [10], ~, Array], # 11
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: classes, package: main, param_names: [], want: scalar}, [9], 10, Unknown, 10, true], # 12
  [Count, ~, [11], ~, Int, 12], # 13
  [Coerce, {from_repr: Int, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Print, ~, [14, 19], 12, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 12]]} # 21
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A list assignment into a field aggregate

`%registry = $graphs->%*` stores into the object's field. Nothing in the method reads it afterwards, so a reader that keeps only what the method itself consumes drops the statement. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl.

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
Holder::clear: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 1
  [FieldAccess, {field_index: 1, field_stash: Holder}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [Assign, {targets: 1}, [2], 0, Unknown, 3, true], # 4
  [Return, ~, [1], 4, ~, 4]]} # 5
Holder::register: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 1
  [FieldAccess, {field_index: 1, field_stash: Holder}, ~, ~, Unknown], # 2
  [FieldAccess, {field_index: 0, field_stash: Holder}, ~, ~, Unknown], # 3
  [Parameter, {index: 0, name: $graphs, sigil: $}, ~, ~, Unknown], # 4
  [MemStart], # 5
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 6, package: Holder, sigil: "%", strict: false}, [4], 0, Hash, 5, true], # 6
  [Assign, {targets: 1}, [3, 6], 6, List, 6, true], # 7
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [3], ~, List, 7], # 8
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [8], ~, List, 7], # 9
  [Assign, {targets: 1}, [2, 9], 7, List, 7, true], # 10
  [Return, ~, [1], 10, ~, 10]]} # 11
Holder::summary: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Holder}, ~, ~, Unknown], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: scalar}, [1], ~, Int, 2], # 3
  [Coerce, {from_repr: Int, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: ":"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 7
  [FieldAccess, {field_index: 1, field_stash: Holder}, ~, ~, Unknown], # 8
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [7, 8], ~, Str], # 9
  [Concat, ~, [6, 9], ~, Str], # 10
  [Return, ~, [10], 0, ~, 2]]} # 11
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: Holder}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: Holder, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 8
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 9
  [HashLiteral, ~, [6, 7, 8, 9], 5, HashRef], # 10
  [Call, {class_name: Holder, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: register, package: main, param_names: [], want: scalar}, [5, 10], 10, Unknown, 5, true], # 11
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 11, name: summary, package: main, param_names: [], want: list}, [11], 11, Unknown, 11, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 14
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 11, name: clear, package: main, param_names: [], want: scalar}, [11], 12, Unknown, 12, true], # 15
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 11, name: summary, package: main, param_names: [], want: list}, [15], 15, Unknown, 15, true], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [13, 14, 17, 18], 16, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [1], 19, ~, 16]]} # 20
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A call in a ternary arm runs only on that arm

The method call is the arm's value, and the arm is taken only when the element is defined. Run unconditionally, it calls a method on undef. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl.

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
Node::id: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 0, field_stash: Node}, ~, ~, Unknown, 1], # 2
  [Return, ~, [2], 0, ~, 1]]} # 3
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [PackageMark, {package: Node}, ~, 0], # 3
  [PackageMark, {package: main}, ~, 3], # 4
  [MemStart], # 5
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [id], want: list}, [2], 4, Object, 5, true], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [id], want: list}, [7], 6, Object, 6, true], # 8
  [ArrayLiteral, ~, [6, 1, 8], 8, ArrayRef], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::ids, package: main, param_names: [], want: list}, [9], 9, Str, 8, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 12
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::fib, package: main, param_names: [], want: list}, [13], 10, Unknown, 10, true], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Print, ~, [11, 12, 15, 16], 14, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [1], 17, ~, 14]]} # 18
main::fib: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $n, sigil: $}, ~, ~, Unknown], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Subtract, ~, [1, 2], ~, Unknown], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [NumLt, ~, [1, 4], ~, Boolean], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 1}, [6]], # 7
  [MemStart], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: main::fib, package: main, param_names: [], want: scalar}, [3], 7, Unknown, 8, true], # 9
  [Subtract, ~, [1, 4], ~, Unknown], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: main::fib, package: main, param_names: [], want: scalar}, [10], 9, Unknown, 9, true], # 11
  [Add, ~, [9, 11], ~, Unknown], # 12
  [Proj, {index: 0}, [6]], # 13
  [Region, {head: 6}, [13, 11]], # 14
  [Phi, {predecessors: [13, 7], region: 14}, [1, 12], ~, Unknown], # 15
  [Phi, {memory: true, predecessors: [13, 7], region: 14}, [8, 11], ~, Unknown], # 16
  [Return, ~, [15], 14, ~, 16]]} # 17
main::ids: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 34], ~, Array], # 4
  [MemStart], # 5
  [Phi, {memory: true, region: 3}, [5, 35], ~, Unknown], # 6
  [Proj, {index: 1}, [3]], # 7
  [Region, {head: 3}, [7]], # 8
  [Phi, {memory: true, region: 8}, [6], ~, Unknown], # 9
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 4], ~, Str, 9], # 10
  [Return, ~, [10], 8, ~, 9], # 11
  [Parameter, {index: 0, name: $in, sigil: $}, ~, ~, Unknown], # 12
  [PostfixDeref, {sigil: "@"}, [12], ~, Array, 5], # 13
  [Count, ~, [13], ~, Int, 6], # 14
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 15
  [Phi, {region: 3}, [15, 37], ~, Int], # 16
  [NumGt, ~, [14, 16], 3, Boolean], # 17
  [Proj, {index: 0}, [3]], # 18
  [Exists, {kind: array}, [13, 16], 18, Boolean, 6], # 19
  [Subscript, {kind: array}, [13, 16], ~, Scalar, 6], # 20
  [Subscript, {kind: array}, [13, 16], ~, Scalar], # 21
  [Ref, ~, [21], ~, ScalarRef], # 22
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 23
  [TernaryExpr, ~, [19, 22, 23], ~, "Maybe[ScalarRef]"], # 24
  [LocalAlias, {name: _}, [24], 19, Unknown, 6], # 25
  [Defined, ~, [20], ~, Boolean], # 26
  [If, ~, [25, 26], 25], # 27
  [Proj, {index: 0}, [27]], # 28
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: id, package: main, param_names: [], want: list}, [20], 28, Unknown, 6, true], # 29
  [Constant, {const_type: string, value: undef}, ~, ~, Str], # 30
  [Proj, {index: 1}, [27]], # 31
  [Region, {head: 27}, [29, 31]], # 32
  [Phi, {predecessors: [28, 31], region: 32}, [29, 30], ~, Unknown], # 33
  [ListAppend, {collector: map}, [4, 33], ~, Array], # 34
  [Phi, {memory: true, predecessors: [28, 31], region: 32}, [29, 6], ~, Unknown], # 35
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 36
  [Add, ~, [16, 36], ~, Int], # 37
  [Count, ~, [13], ~, Int, 5]]} # 38
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A method returning an array, called in list context

The method's `return @parts` is a list to a list-context caller and a count to a scalar one; the call site's context decides. chalk's IR nodes build their content hash as `join('|', $op, $self->_serialize_inputs())`. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl.

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
Node::count: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 1
  [MemStart], # 2
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: parts, package: Node, param_names: [], want: scalar}, [1], 0, Array, 2, true], # 3
  [Return, ~, [3], 3, ~, 3]]} # 4
Node::hash: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: op}, ~, ~, Str], # 2
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 3
  [MemStart], # 4
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: parts, package: Node, param_names: [], want: list}, [3], 0, Array, 4, true], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 2, 5], ~, Str], # 6
  [Return, ~, [6], 5, ~, 5]]} # 7
Node::parts: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [PadAccess, {sigil: "@", symbol: p}, ~, ~, Array], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [1, 2, 3], 0, Int, 4, true], # 5
  [Return, ~, [1], 5, ~, 5]]} # 6
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: new, package: main, param_names: [], want: scalar}, ~, 0, Object, 2, true], # 3
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: hash, package: main, param_names: [], want: list}, [3], 3, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: new, package: main, param_names: [], want: scalar}, ~, 4, Object, 4, true], # 7
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: count, package: main, param_names: [], want: list}, [7], 7, Array, 7, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [5, 6, 9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```
