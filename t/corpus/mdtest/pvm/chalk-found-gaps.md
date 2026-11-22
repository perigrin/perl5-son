# Gaps chalk's own lib/ found

Programs reduced from modules in chalk's lib/ that B::SoN refused or
emitted wrongly once they began to translate. Added here by B::SoN and sent
to pvm to place in its tiers; this file is replaced when the corpus is next
copied from pvm.

**Tier 07 subroutines.** Introduces nothing. Depends on 06_control.

## An early return, an or-die, and a guarded return

Three ways out of one sub, and one way through. The value returned on the way through is computed after the `or die`; it must not be read before the variables it uses exist.

```perl
my %cache = (hb => "cached");
sub make {
    my ($op) = @_;
    if ($op eq "P") { return "phi" }
    my $key = $op or die "no op\n";
    return $cache{"h$key"} if exists $cache{"h$key"};
    return "new $key";
}
print make("P"), " ", make("a"), " ", make("b"), "\n";
```

```behavior
parses: yes
```

```output
phi new a cached
```

```ir
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: P}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: cache}, ~, ~, Hash, 3], # 4
  [Constant, {const_type: string, value: hb}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: cached}, ~, ~, Str], # 6
  [HashLiteral, {sigil: "%", symbol: cache}, [5, 6], 0, Hash], # 7
  [Assign, ~, [4, 7], 7, List, 3, true], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::make, package: main, param_names: [], want: list}, [2], 8, Scalar, 8, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::make, package: main, param_names: [], want: list}, [12], 9, Scalar, 9, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 15
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::make, package: main, param_names: [], want: list}, [15], 13, Scalar, 13, true], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [10, 11, 14, 11, 17, 18], 16, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [1], 19, ~, 16]]} # 20
main::make: {start: 0, returns: [30], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: phi}, ~, ~, Str], # 1
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: cache}, ~, ~, Hash], # 2
  [Constant, {const_type: string, value: h}, ~, ~, Str], # 3
  [PadAccess, {sigil: $, symbol: op}, ~, ~, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Concat, ~, [3, 5], ~, Str], # 6
  [MemStart], # 7
  [Subscript, {kind: hash}, [2, 6], ~, Scalar, 7], # 8
  [Constant, {const_type: string, value: "new "}, ~, ~, Str], # 9
  [Concat, ~, [9, 5], ~, Str], # 10
  [Constant, {const_type: string, value: P}, ~, ~, Str], # 11
  [StrEq, ~, [5, 11], ~, Boolean], # 12
  [If, ~, [0, 12], 0], # 13
  [Proj, {index: 1}, [13]], # 14
  [If, ~, [14, 4], 14], # 15
  [Proj, {index: 0}, [15]], # 16
  [Constant, {const_type: string, value: "no op\n"}, ~, ~, Str], # 17
  [Proj, {index: 1}, [15]], # 18
  [Unwind, {file: "/tmp/mvrHQew3rs/case.pl", line: 5}, [17], 18, ~, 7], # 19
  [Region, {head: 15}, [16, 19]], # 20
  [Exists, {kind: hash}, [2, 6], ~, Boolean, 7], # 21
  [If, ~, [20, 21], 20], # 22
  [Proj, {index: 0}, [22]], # 23
  [Proj, {index: 1}, [22]], # 24
  [Region, {head: 22}, [23, 24]], # 25
  [Phi, {predecessors: [23, 24], region: 25}, [8, 10], ~, Scalar], # 26
  [Proj, {index: 0}, [13]], # 27
  [Region, {head: 13}, [27, 25]], # 28
  [Phi, {predecessors: [27, 14], region: 28}, [1, 26], ~, Scalar], # 29
  [Return, ~, [29], 28, ~, 7], # 30
  [ArgsSource, ~, ~, ~, Array], # 31
  [Assign, {record: true, targets: 1}, [4, 31], ~, List]]} # 32
```

## A main:: sub and another package's sub, named from a class

Inside a class block a bare name is the class's own sub. `main::helper()` and `\&Other::helper` keep their packages.

```perl
use v5.42.0;
use experimental 'class';
sub helper { "main helper" }
package Other { sub helper { "other helper" } }
class Widget {
    method call_main  { main::helper() }
    method ref_other  { my $r = \&Other::helper; $r->() }
}
my $w = Widget->new;
print $w->call_main, "; ", $w->ref_other, "\n";
```

```behavior
parses: yes
```

```output
main helper; other helper
```

```ir
Other::helper: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "other helper"}, ~, ~, Str], # 1
  [MemStart], # 2
  [Return, {implicit: true}, [1], 0, ~, 2]]} # 3
Widget::call_main: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: main::helper, package: Widget, param_names: []}, ~, 0, Str, 1, true], # 2
  [Return, {implicit: true}, [2], 2, ~, 2]]} # 3
Widget::ref_other: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: code, value: Other::helper}, ~, ~, Code], # 1
  [Ref, ~, [1], ~, CodeRef], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: indirect, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: "", package: Widget, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {class_name: Widget, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: new, package: main, param_names: [], want: scalar}, ~, 0, Object, 2, true], # 3
  [Call, {class_name: Widget, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: call_main, package: main, param_names: [], want: list}, [3], 3, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "; "}, ~, ~, Str], # 6
  [Call, {class_name: Widget, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: ref_other, package: main, param_names: [], want: list}, [3], 4, Unknown, 4, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [5, 6, 8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7]]} # 11
main::helper: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "main helper"}, ~, ~, Str], # 1
  [MemStart], # 2
  [Return, {implicit: true}, [1], 0, ~, 2]]} # 3
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: experimental, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## Guards that call, then an if, in a loop body

Each `next unless` guard calls methods; the statements after the last guard run once per element that passes all three.

```perl
package Node { sub new { my ($c, %a) = @_; bless {%a}, $c } sub kind { $_[0]{kind} } sub owner { $_[0]{owner} } sub name { $_[0]{name} } }
sub matching {
    my ($loop, $nodes) = @_;
    my @found;
    for my $n (@$nodes) {
        next unless defined $n && $n->can('kind');
        next unless $n->kind eq 'Phi';
        my $owner = $n->owner;
        next unless defined $owner && $owner->name eq $loop->name;
        my $label = $n->name;
        if (defined $label) {
            push @found, $label;
        }
    }
    return join(",", @found);
}
my $loop = Node->new(name => 'L');
my @nodes = (Node->new(kind => 'Phi', owner => $loop, name => 'a'), undef,
             Node->new(kind => 'X'), Node->new(kind => 'Phi', owner => Node->new(name => 'M'), name => 'b'),
             Node->new(kind => 'Phi', owner => $loop));
print matching($loop, \@nodes), "\n";
```

```behavior
parses: yes
```

```output
a
```

```ir
Node::kind: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: kind}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
Node::name: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: name}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
Node::new: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [PadAccess, {sigil: "%", symbol: a}, ~, ~, Unknown], # 1
  [HashLiteral, ~, [1], 0, HashRef], # 2
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [2, 3], 2, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Assign, {record: true, targets: 2}, [3, 1, 7], ~, List]]} # 8
Node::owner: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: owner}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
main::__PROGRAM__: {start: 0, returns: [30], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: Node}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: kind}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: Phi}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: owner}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: name}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: M}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: X}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: L}, ~, ~, Str], # 9
  [MemStart], # 10
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 17, name: new, package: main, param_names: [], want: scalar}, [2, 6, 9], 0, Object, 10, true], # 11
  [PadAccess, {sigil: $, symbol: loop}, ~, ~, Unknown, 11], # 12
  [Assign, ~, [12, 11], 11, Object, 11, true], # 13
  [PadAccess, {sigil: $, symbol: loop}, ~, ~, Unknown, 13], # 14
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 15
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 18, name: new, package: main, param_names: [], want: list}, [2, 3, 4, 5, 14, 6, 15], 13, Object, 13, true], # 16
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 18, name: new, package: main, param_names: [], want: list}, [2, 3, 8], 16, Object, 16, true], # 17
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 18, name: new, package: main, param_names: [], want: list}, [2, 6, 7], 17, Object, 17, true], # 18
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 19
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 18, name: new, package: main, param_names: [], want: list}, [2, 3, 4, 5, 18, 6, 19], 18, Object, 18, true], # 20
  [PadAccess, {sigil: $, symbol: loop}, ~, ~, Unknown, 20], # 21
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 18, name: new, package: main, param_names: [], want: list}, [2, 3, 4, 5, 21], 20, Object, 20, true], # 22
  [PadAccess, {sigil: $, symbol: loop}, ~, ~, Unknown, 22], # 23
  [ArrayLiteral, {sigil: "@", symbol: nodes}, [16, 1, 17, 20, 22], ~, Array], # 24
  [Ref, ~, [24], ~, ArrayRef], # 25
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 21, name: main::matching, package: main, param_names: [], want: list}, [23, 25], 22, Str, 22, true], # 26
  [Coerce, {from_repr: Unknown, to_repr: Str}, [26], ~, Str], # 27
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 28
  [Print, ~, [27, 28], 26, "Maybe[Boolean]"], # 29
  [Return, {implicit: true}, [1], 29, ~, 26]]} # 30
main::matching: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: found}, ~, ~, Array], # 2
  [MemStart], # 3
  [Loop, {bound: entry}, [0], 0], # 4
  [Phi, {memory: true, region: 4}, [3, 87], ~, Unknown], # 5
  [Proj, {index: 1}, [4]], # 6
  [Region, {head: 4}, [6]], # 7
  [Phi, {memory: true, region: 7}, [5], ~, Unknown], # 8
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 2], ~, Str, 8], # 9
  [Return, ~, [9], 7, ~, 8], # 10
  [PadAccess, {sigil: $, symbol: nodes}, ~, ~, Unknown], # 11
  [PostfixDeref, {sigil: "@"}, [11], ~, Array, 3], # 12
  [Count, ~, [12], ~, Int, 5], # 13
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 14
  [Phi, {region: 4}, [14, 89], ~, Int], # 15
  [NumGt, ~, [13, 15], 4, Boolean], # 16
  [Proj, {index: 0}, [4]], # 17
  [Exists, {kind: array}, [12, 15], 17, Boolean, 5], # 18
  [Subscript, {kind: array}, [12, 15], ~, Scalar], # 19
  [Ref, ~, [19], ~, ScalarRef], # 20
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 21
  [TernaryExpr, ~, [18, 20, 21], 18, "Maybe[ScalarRef]"], # 22
  [PadAccess, {sigil: $, symbol: loop}, ~, ~, Unknown], # 23
  [PostfixDeref, {sigil: $}, [22], ~, Scalar, 5], # 24
  [Subscript, {kind: array}, [12, 15], ~, Scalar, 5], # 25
  [TernaryExpr, ~, [18, 24, 25], ~, Scalar], # 26
  [Constant, {const_type: string, value: kind}, ~, ~, Str], # 27
  [PostfixDeref, {sigil: $}, [22], ~, Scalar, 5], # 28
  [Subscript, {kind: array}, [12, 15], ~, Scalar, 5], # 29
  [TernaryExpr, ~, [18, 28, 29], 22, Scalar], # 30
  [Defined, ~, [30], ~, Boolean], # 31
  [If, ~, [30, 31], 30], # 32
  [Proj, {index: 0}, [32]], # 33
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: can, package: main, param_names: [], want: scalar}, [26, 27], 33, Unknown, 5, true], # 34
  [Proj, {index: 1}, [32]], # 35
  [Region, {head: 32}, [34, 35]], # 36
  [Phi, {memory: true, predecessors: [33, 35], region: 36}, [34, 5], ~, Unknown], # 37
  [PostfixDeref, {sigil: $}, [22], ~, Scalar, 37], # 38
  [Subscript, {kind: array}, [12, 15], ~, Scalar, 37], # 39
  [TernaryExpr, ~, [18, 38, 39], ~, Scalar], # 40
  [Phi, {predecessors: [33, 35], region: 36}, [34, 31], ~, Unknown], # 41
  [If, ~, [36, 41], 36], # 42
  [Proj, {index: 0}, [42]], # 43
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: kind, package: main, param_names: [], want: scalar}, [40], 43, Unknown, 37, true], # 44
  [PostfixDeref, {sigil: $}, [22], ~, Scalar, 44], # 45
  [Subscript, {kind: array}, [12, 15], ~, Scalar, 44], # 46
  [TernaryExpr, ~, [18, 45, 46], ~, Scalar], # 47
  [Coerce, {from_repr: Unknown, to_repr: Str}, [44], ~, Str], # 48
  [Constant, {const_type: string, value: Phi}, ~, ~, Str], # 49
  [StrEq, ~, [48, 49], ~, Boolean], # 50
  [If, ~, [44, 50], 44], # 51
  [Proj, {index: 0}, [51]], # 52
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: owner, package: main, param_names: [], want: scalar}, [47], 52, Unknown, 44, true], # 53
  [Defined, ~, [53], ~, Boolean], # 54
  [If, ~, [53, 54], 53], # 55
  [Proj, {index: 0}, [55]], # 56
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: name, package: main, param_names: [], want: scalar}, [53], 56, Unknown, 53, true], # 57
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: name, package: main, param_names: [], want: scalar}, [23], 57, Unknown, 57, true], # 58
  [Proj, {index: 1}, [55]], # 59
  [Region, {head: 55}, [58, 59]], # 60
  [Phi, {memory: true, predecessors: [56, 59], region: 60}, [58, 53], ~, Unknown], # 61
  [PostfixDeref, {sigil: $}, [22], ~, Scalar, 61], # 62
  [Subscript, {kind: array}, [12, 15], ~, Scalar, 61], # 63
  [TernaryExpr, ~, [18, 62, 63], ~, Scalar], # 64
  [Coerce, {from_repr: Unknown, to_repr: Str}, [57], ~, Str], # 65
  [Coerce, {from_repr: Unknown, to_repr: Str}, [58], ~, Str], # 66
  [StrEq, ~, [65, 66], ~, Boolean], # 67
  [Phi, {predecessors: [56, 59], region: 60}, [67, 54], ~, Boolean], # 68
  [If, ~, [60, 68], 60], # 69
  [Proj, {index: 0}, [69]], # 70
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: name, package: main, param_names: [], want: scalar}, [64], 70, Unknown, 61, true], # 71
  [Defined, ~, [71], ~, Boolean], # 72
  [If, ~, [71, 72], 71], # 73
  [Proj, {index: 0}, [73]], # 74
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 71], 74, Int, 71, true], # 75
  [Proj, {index: 1}, [73]], # 76
  [Region, {head: 73}, [76, 75]], # 77
  [Phi, {memory: true, predecessors: [76, 74], region: 77}, [71, 75], ~, Unknown], # 78
  [Proj, {index: 1}, [42]], # 79
  [Region, {head: 42}, [79, 77]], # 80
  [Phi, {memory: true, predecessors: [79, 43], region: 80}, [37, 78], ~, Unknown], # 81
  [Proj, {index: 1}, [51]], # 82
  [Region, {head: 4}, [80, 82]], # 83
  [Phi, {memory: true, predecessors: [17, 82], region: 83}, [81, 44], ~, Unknown], # 84
  [Proj, {index: 1}, [69]], # 85
  [Region, {head: 4}, [83, 85]], # 86
  [Phi, {memory: true, region: 86}, [84, 61], ~, Unknown], # 87
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 88
  [Add, ~, [15, 88], ~, Int], # 89
  [Count, ~, [12], ~, Int, 3], # 90
  [ArgsSource, ~, ~, ~, Array], # 91
  [Assign, {record: true, targets: 2}, [23, 11, 91], ~, List]]} # 92
```

## A guarded return inside an if, then a loop

One arm of the inner `if` leaves the sub; the other falls through to the loop after the outer `if`, which runs once.

```perl
sub walk {
    my ($op, $items) = @_;
    my @chain;
    if ($op eq "If" || $op eq "S") {
        push @chain, $op;
        return "stopped at @chain" if $op eq "If";
    }
    for my $item (@$items) { push @chain, $item }
    return "@chain";
}
print walk("If", [1]), " | ", walk("S", [2, 3]), " | ", walk("X", [4]), "\n";
```

```behavior
parses: yes
```

```output
stopped at If | S 2 3 | 4
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: If}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [3], 0, ArrayRef], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 11, name: main::walk, package: main, param_names: [], want: list}, [2, 4], 4, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: " | "}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: S}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [ArrayLiteral, ~, [10, 11], 6, ArrayRef], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 11, name: main::walk, package: main, param_names: [], want: list}, [9, 12], 12, Str, 6, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: X}, ~, ~, Str], # 15
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 16
  [ArrayLiteral, ~, [16], 13, ArrayRef], # 17
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 11, name: main::walk, package: main, param_names: [], want: list}, [15, 17], 17, Str, 13, true], # 18
  [Coerce, {from_repr: Unknown, to_repr: Str}, [18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Print, ~, [7, 8, 14, 8, 19, 20], 18, "Maybe[Boolean]"], # 21
  [Return, {implicit: true}, [1], 21, ~, 18]]} # 22
main::walk: {start: 0, returns: [35], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "stopped at "}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: chain}, ~, ~, Array], # 2
  [PadAccess, {sigil: $, symbol: op}, ~, ~, Unknown], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: If}, ~, ~, Str], # 5
  [StrEq, ~, [4, 5], ~, Boolean], # 6
  [Constant, {const_type: string, value: S}, ~, ~, Str], # 7
  [StrEq, ~, [4, 7], ~, Boolean], # 8
  [Or, ~, [6, 8], ~, Boolean], # 9
  [If, ~, [0, 9], 0], # 10
  [Proj, {index: 0}, [10]], # 11
  [MemStart], # 12
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 3], 11, Int, 12, true], # 13
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 13], # 14
  [Coerce, {from_repr: Scalar, to_repr: Str}, [14], ~, Str], # 15
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [15, 2], ~, Str, 13], # 16
  [Concat, ~, [1, 16], ~, Str], # 17
  [Proj, {index: 1}, [10]], # 18
  [If, ~, [13, 6], 13], # 19
  [Proj, {index: 1}, [19]], # 20
  [Region, {head: 10}, [18, 20]], # 21
  [Phi, {memory: true, predecessors: [18, 11], region: 21}, [12, 13], ~, Unknown], # 22
  [Loop, {bound: entry}, [21], 21], # 23
  [Phi, {memory: true, region: 23}, [22, 49], ~, Unknown], # 24
  [Proj, {index: 1}, [23]], # 25
  [Region, {head: 23}, [25]], # 26
  [Phi, {memory: true, region: 26}, [24], ~, Unknown], # 27
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 27], # 28
  [Coerce, {from_repr: Scalar, to_repr: Str}, [28], ~, Str], # 29
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [29, 2], ~, Str, 27], # 30
  [Proj, {index: 0}, [19]], # 31
  [Region, ~, [31, 26]], # 32
  [Phi, {predecessors: [31, 26], region: 32}, [17, 30], ~, Str], # 33
  [Phi, {exits: true, memory: true, predecessors: [31, 26], region: 32}, [13, 27], ~, Unknown], # 34
  [Return, ~, [33], 32, ~, 34], # 35
  [PadAccess, {sigil: $, symbol: items}, ~, ~, Unknown], # 36
  [PostfixDeref, {sigil: "@"}, [36], ~, Array, 22], # 37
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 38
  [Phi, {region: 23}, [38, 56], ~, Int], # 39
  [Proj, {index: 0}, [23]], # 40
  [Exists, {kind: array}, [37, 39], 40, Boolean, 24], # 41
  [Subscript, {kind: array}, [37, 39], ~, Scalar], # 42
  [Ref, ~, [42], ~, ScalarRef], # 43
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 44
  [TernaryExpr, ~, [41, 43, 44], 41, "Maybe[ScalarRef]"], # 45
  [PostfixDeref, {sigil: $}, [45], ~, Scalar, 24], # 46
  [Subscript, {kind: array}, [37, 39], ~, Scalar, 24], # 47
  [TernaryExpr, ~, [41, 46, 47], 45, Scalar], # 48
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 48], 48, Int, 24, true], # 49
  [ArgsSource, ~, ~, ~, Array], # 50
  [Assign, {record: true, targets: 2}, [3, 36, 50], ~, List], # 51
  [Count, ~, [37], ~, Int, 22], # 52
  [Count, ~, [37], ~, Int, 24], # 53
  [NumGt, ~, [53, 39], 23, Boolean], # 54
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 55
  [Add, ~, [39, 55], ~, Int]]} # 56
```

## A ternary passed to a sub, its arm reading a lexical

Perl passes arguments by alias and marks each one modifiable, the ternary's arms included; the arm still reads `$values`.

```perl
sub count_of { my ($label, $list) = @_; return "$label=" . scalar(@$list) }
sub build {
    my %args = @_;
    my $values = delete $args{values};
    return count_of("inputs", (defined $values ? $values : []));
}
print build(values => [1, 2, 3]), " ", build(), "\n";
```

```behavior
parses: yes
```

```output
inputs=3 inputs=0
```

```ir
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: values}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 5
  [ArrayLiteral, ~, [3, 4, 5], 0, ArrayRef], # 6
  [MemStart], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::build, package: main, param_names: [], want: list}, [2, 6], 6, Str, 7, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::build, package: main, param_names: [], want: list}, ~, 8, Str, 8, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [9, 10, 12, 13], 11, "Maybe[Boolean]"], # 14
  [Return, {implicit: true}, [1], 14, ~, 11]]} # 15
main::build: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: inputs}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [HashLiteral, {sigil: "%", symbol: args}, [2], ~, Hash], # 3
  [Constant, {const_type: string, value: values}, ~, ~, Str], # 4
  [MemStart], # 5
  [Delete, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [PadAccess, {sigil: $, symbol: values}, ~, ~, Unknown, 6], # 7
  [Assign, ~, [7, 6], 6, Scalar, 6, true], # 8
  [PadAccess, {sigil: $, symbol: values}, ~, ~, Unknown, 8], # 9
  [Defined, ~, [9], ~, Boolean], # 10
  [If, ~, [8, 10], 8], # 11
  [Proj, {index: 1}, [11]], # 12
  [ArrayLiteral, ~, ~, 12, ArrayRef], # 13
  [Proj, {index: 0}, [11]], # 14
  [Region, {head: 11}, [14, 13]], # 15
  [Phi, {predecessors: [14, 12], region: 15}, [9, 13], ~, Unknown], # 16
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::count_of, package: main, param_names: []}, [1, 16], 15, Str, 8, true], # 17
  [Return, ~, [17], 17, ~, 17]]} # 18
main::count_of: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: label}, ~, ~, Str], # 1
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 2
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 3
  [Concat, ~, [2, 3], ~, Str], # 4
  [PadAccess, {sigil: $, symbol: list}, ~, ~, Unknown], # 5
  [MemStart], # 6
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 1, package: main, sigil: "@", strict: false}, [5], 0, Array, 6, true], # 7
  [Count, ~, [7], ~, Int, 7], # 8
  [Concat, ~, [4, 8], ~, Str], # 9
  [Return, ~, [9], 7, ~, 7], # 10
  [ArgsSource, ~, ~, ~, Array], # 11
  [Assign, {record: true, targets: 2}, [1, 5, 11], ~, List]]} # 12
```

## A guarded return as the last statement

`return X if C` is `C and return X`. As the last statement it takes the caller's context, so when C fails the sub returns C: false for `if`, the value itself for `unless`.

```perl
sub big   { my ($k) = @_; return "big" if $k > 1 }
sub truthy { my ($k) = @_; return "none" unless $k }
print "[", scalar(big(0)), "] [", big(5), "] [", truthy("value"), "] [", truthy(0), "]\n";
```

```behavior
parses: yes
```

```output
[] [big] [value] [none]
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::big, package: main, param_names: [], want: scalar}, [3], 0, Scalar, 4, true], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "] ["}, ~, ~, Str], # 7
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::big, package: main, param_names: [], want: list}, [8], 5, Scalar, 5, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: value}, ~, ~, Str], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::truthy, package: main, param_names: [], want: list}, [11], 9, Unknown, 9, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::truthy, package: main, param_names: [], want: list}, [3], 12, Unknown, 12, true], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 16
  [Print, ~, [2, 6, 7, 10, 7, 13, 7, 15, 16], 14, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [1], 17, ~, 14]]} # 18
main::big: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: big}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: k}, ~, ~, Num], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [NumGt, ~, [2, 3], ~, Boolean], # 4
  [If, ~, [0, 4], 0], # 5
  [Proj, {index: 0}, [5]], # 6
  [Proj, {index: 1}, [5]], # 7
  [Region, {head: 5}, [6, 7]], # 8
  [Phi, {predecessors: [6, 7], region: 8}, [1, 4], ~, Scalar], # 9
  [MemStart], # 10
  [Return, ~, [9], 8, ~, 10], # 11
  [ArgsSource, ~, ~, ~, Array], # 12
  [Assign, {record: true, targets: 1}, [2, 12], ~, List]]} # 13
main::truthy: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: k}, ~, ~, Unknown], # 2
  [Not, ~, [2], ~, Boolean], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 0}, [4]], # 5
  [Proj, {index: 1}, [4]], # 6
  [Region, {head: 4}, [5, 6]], # 7
  [Phi, {predecessors: [5, 6], region: 7}, [1, 2], ~, Unknown], # 8
  [MemStart], # 9
  [Return, ~, [8], 7, ~, 9], # 10
  [ArgsSource, ~, ~, ~, Array], # 11
  [Assign, {record: true, targets: 1}, [2, 11], ~, List]]} # 12
```

## A guarded store into shared state after a next

After the `next unless` guard, each increment runs only when its own guard holds -- a file-scope lexical and a package scalar alike.

```perl
my $seen = 0;
our $total = 0;
sub tally {
    for my $x (@_) {
        next unless $x > 1;
        $seen++ if $x > 2;
        if ($x > 2) { $total += $x }
    }
    return "$seen $total";
}
print tally(1, 3, 0, 5, 2), "\n";
```

```behavior
parses: yes
```

```output
2 8
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [EntryDef, {package: main, sigil: $, symbol: total}, ~, ~, Scalar], # 7
  [MemStart], # 8
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: seen}, ~, ~, Unknown, 8], # 9
  [Assign, ~, [9, 4], 0, Int, 8, true], # 10
  [EntryWrite, ~, [7, 4], 10, Unknown, 10, true], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 11, name: main::tally, package: main, param_names: [], want: list}, [2, 3, 4, 5, 6], 11, Str, 11, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [13, 14], 12, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 12]]} # 16
main::tally: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {memory: true, region: 2}, [1, 49], ~, Unknown], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Phi, {memory: true, region: 5}, [3], ~, Unknown], # 6
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: seen}, ~, ~, Str, 6], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [EntryDef, {package: main, sigil: $, symbol: total}, ~, ~, Scalar, 6], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [10, 12], ~, Str], # 13
  [Return, ~, [13], 5, ~, 6], # 14
  [ArgsSource, ~, ~, ~, Array], # 15
  [Count, ~, [15], ~, Int, 3], # 16
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 17
  [Phi, {region: 2}, [17, 50], ~, Int], # 18
  [NumGt, ~, [16, 18], 2, Boolean], # 19
  [Proj, {index: 0}, [2]], # 20
  [Subscript, {kind: array}, [15, 18], ~, Scalar, 3], # 21
  [Coerce, {from_repr: Scalar, to_repr: Num}, [21], ~, Num], # 22
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 23
  [NumGt, ~, [22, 23], ~, Boolean], # 24
  [If, ~, [20, 24], 20], # 25
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: seen}, ~, ~, Unknown, 3], # 26
  [Increment, ~, [26], ~, Scalar], # 27
  [Proj, {index: 0}, [25]], # 28
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 29
  [NumGt, ~, [22, 29], ~, Boolean], # 30
  [If, ~, [28, 30], 28], # 31
  [Proj, {index: 0}, [31]], # 32
  [Assign, ~, [26, 27], 32, Scalar, 3, true], # 33
  [Proj, {index: 1}, [31]], # 34
  [Region, {head: 31}, [34, 33]], # 35
  [Phi, {memory: true, predecessors: [34, 32], region: 35}, [3, 33], ~, Unknown], # 36
  [EntryDef, {package: main, sigil: $, symbol: total}, ~, ~, Scalar], # 37
  [EntryDef, {package: main, sigil: $, symbol: total}, ~, ~, Scalar, 36], # 38
  [Coerce, {from_repr: Scalar, to_repr: Num}, [38], ~, Num], # 39
  [Add, ~, [39, 22], ~, Num], # 40
  [If, ~, [35, 30], 35], # 41
  [Proj, {index: 0}, [41]], # 42
  [EntryWrite, ~, [37, 40], 42, Unknown, 36, true], # 43
  [Proj, {index: 1}, [41]], # 44
  [Region, {head: 41}, [44, 43]], # 45
  [Phi, {memory: true, predecessors: [44, 42], region: 45}, [36, 43], ~, Unknown], # 46
  [Proj, {index: 1}, [25]], # 47
  [Region, {head: 25}, [47, 45]], # 48
  [Phi, {memory: true, predecessors: [47, 28], region: 48}, [3, 46], ~, Unknown], # 49
  [Add, ~, [18, 23], ~, Int], # 50
  [Count, ~, [15], ~, Int, 1]]} # 51
```

## A defined-ternary default and a defined-or default agree

For a plain lexical, `defined $v ? $v : []` and `$v // []` give the same value for every input -- undef, false values, a string, a reference -- and the default is a fresh array each time.

```perl
sub by_ternary { my ($v) = @_; my $r = defined $v ? $v : []; return ref $r ? "ref(" . scalar(@$r) . ")" : $r }
sub by_dor     { my ($v) = @_; my $r = $v // [];              return ref $r ? "ref(" . scalar(@$r) . ")" : $r }
for my $in (undef, 0, "", "x", [1, 2]) {
    print by_ternary($in) eq by_dor($in) ? "same " : "differ ", by_dor($in), "\n";
}
```

```behavior
parses: yes
```

```output
same ref(0)
same 0
same 
same x
same ref(2)
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [2, 3], 0, ArrayRef], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Proj, {index: 1}, [5]], # 6
  [Region, {head: 5}, [6]], # 7
  [MemStart], # 8
  [Phi, {memory: true, region: 5}, [8, 32], ~, Unknown], # 9
  [Phi, {memory: true, region: 7}, [9], ~, Unknown], # 10
  [Return, {implicit: true}, [1], 7, ~, 10], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 14
  [ArrayLiteral, ~, [1, 12, 13, 14, 4], ~, Array], # 15
  [Phi, {region: 5}, [12, 17], ~, Int], # 16
  [Add, ~, [16, 2], ~, Int], # 17
  [Count, ~, [15], ~, Int, 8], # 18
  [Count, ~, [15], ~, Int, 9], # 19
  [Subscript, {kind: array}, [15, 16], ~, Scalar], # 20
  [Subscript, {kind: array}, [15, 16], ~, Scalar, 9], # 21
  [Proj, {index: 0}, [5]], # 22
  [Ref, ~, [20], 22, ScalarRef, 9], # 23
  [PostfixDeref, {sigil: $}, [23], ~, Scalar, 9], # 24
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::by_ternary, package: main, param_names: [], want: scalar}, [24], 23, Unknown, 9, true], # 25
  [Subscript, {kind: array}, [15, 16], ~, Scalar, 25], # 26
  [PostfixDeref, {sigil: $}, [23], ~, Scalar, 25], # 27
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::by_dor, package: main, param_names: [], want: scalar}, [27], 25, Unknown, 25, true], # 28
  [Subscript, {kind: array}, [15, 16], ~, Scalar, 28], # 29
  [NumGt, ~, [19, 16], 5, Boolean], # 30
  [PostfixDeref, {sigil: $}, [23], ~, Scalar, 28], # 31
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::by_dor, package: main, param_names: [], want: list}, [31], 28, Unknown, 28, true], # 32
  [Coerce, {from_repr: Unknown, to_repr: Str}, [32], ~, Str], # 33
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 34
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 35
  [StrEq, ~, [34, 35], ~, Boolean], # 36
  [Constant, {const_type: string, value: "same "}, ~, ~, Str], # 37
  [Constant, {const_type: string, value: "differ "}, ~, ~, Str], # 38
  [TernaryExpr, ~, [36, 37, 38], ~, Str], # 39
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 40
  [Print, ~, [39, 33, 40], 32, "Maybe[Boolean]"]]} # 41
main::by_dor: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "ref("}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Unknown], # 2
  [Defined, ~, [2], ~, Boolean], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 1}, [4]], # 5
  [ArrayLiteral, ~, ~, 5, ArrayRef], # 6
  [DefinedOr, ~, [2, 6], ~, Unknown], # 7
  [Proj, {index: 0}, [4]], # 8
  [Region, {head: 4}, [8, 6]], # 9
  [MemStart], # 10
  [RefType, ~, [7], ~, Str, 10], # 11
  [If, ~, [9, 11], 9], # 12
  [Proj, {index: 0}, [12]], # 13
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: "@", strict: false}, [7], 13, Array, 10, true], # 14
  [Count, ~, [14], ~, Int, 14], # 15
  [Coerce, {from_repr: Int, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [1, 16], ~, Str], # 17
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Proj, {index: 1}, [12]], # 20
  [Region, {head: 12}, [14, 20]], # 21
  [Phi, {predecessors: [13, 20], region: 21}, [19, 7], ~, Unknown], # 22
  [Phi, {memory: true, predecessors: [13, 20], region: 21}, [14, 10], ~, Unknown], # 23
  [Return, ~, [22], 21, ~, 23], # 24
  [ArgsSource, ~, ~, ~, Array], # 25
  [Assign, {record: true, targets: 1}, [2, 25], ~, List]]} # 26
main::by_ternary: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "ref("}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Unknown], # 2
  [Defined, ~, [2], ~, Boolean], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 1}, [4]], # 5
  [ArrayLiteral, ~, ~, 5, ArrayRef], # 6
  [Proj, {index: 0}, [4]], # 7
  [Region, {head: 4}, [7, 6]], # 8
  [Phi, {predecessors: [7, 5], region: 8}, [2, 6], ~, Unknown], # 9
  [MemStart], # 10
  [RefType, ~, [9], ~, Str, 10], # 11
  [If, ~, [8, 11], 8], # 12
  [Proj, {index: 0}, [12]], # 13
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 1, package: main, sigil: "@", strict: false}, [9], 13, Array, 10, true], # 14
  [Count, ~, [14], ~, Int, 14], # 15
  [Coerce, {from_repr: Int, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [1, 16], ~, Str], # 17
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Proj, {index: 1}, [12]], # 20
  [Region, {head: 12}, [14, 20]], # 21
  [Phi, {predecessors: [13, 20], region: 21}, [19, 9], ~, Unknown], # 22
  [Phi, {memory: true, predecessors: [13, 20], region: 21}, [14, 10], ~, Unknown], # 23
  [Return, ~, [22], 21, ~, 23], # 24
  [ArgsSource, ~, ~, ~, Array], # 25
  [Assign, {record: true, targets: 1}, [2, 25], ~, List]]} # 26
```

## A defined-ternary evaluates its operand twice; defined-or once

The two spellings differ when the operand has an effect: the ternary runs it for the test and again for the value, so it sees the second result; `//` runs it once.

```perl
my $fetches = 0;
sub next_value { $fetches++; return $fetches > 1 ? "second" : "first" }
$fetches = 0; my $t = defined(next_value()) ? next_value() : "none"; print "ternary: $t after $fetches\n";
$fetches = 0; my $d = next_value() // "none";                      print "dor: $d after $fetches\n";
```

```behavior
parses: yes
```

```output
ternary: second after 2
dor: first after 1
```

```ir
main::__PROGRAM__: {start: 0, returns: [41], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "dor: "}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: fetches}, ~, ~, Unknown, 3], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int, 3, true], # 6
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: fetches}, ~, ~, Unknown, 6], # 7
  [Assign, ~, [7, 5], 6, Int, 6, true], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::next_value, package: main, param_names: [], want: scalar}, ~, 8, Str, 8, true], # 9
  [Defined, ~, [9], ~, Boolean], # 10
  [If, ~, [9, 10], 9], # 11
  [Proj, {index: 0}, [11]], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::next_value, package: main, param_names: [], want: scalar}, ~, 12, Str, 9, true], # 13
  [Proj, {index: 1}, [11]], # 14
  [Region, {head: 11}, [13, 14]], # 15
  [Phi, {memory: true, predecessors: [12, 14], region: 15}, [13, 9], ~, Str], # 16
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: fetches}, ~, ~, Str, 16], # 17
  [Constant, {const_type: string, value: "ternary: "}, ~, ~, Str], # 18
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 19
  [Phi, {predecessors: [12, 14], region: 15}, [13, 19], ~, Str], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Concat, ~, [18, 21], ~, Str], # 22
  [Constant, {const_type: string, value: " after "}, ~, ~, Str], # 23
  [Concat, ~, [22, 23], ~, Str], # 24
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 25
  [Concat, ~, [24, 25], ~, Str], # 26
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 27
  [Concat, ~, [26, 27], ~, Str], # 28
  [Print, ~, [28], 15, "Maybe[Boolean]"], # 29
  [Assign, ~, [17, 5], 29, Int, 16, true], # 30
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::next_value, package: main, param_names: [], want: scalar}, ~, 30, Str, 30, true], # 31
  [DefinedOr, ~, [31, 19], ~, Str], # 32
  [Coerce, {from_repr: Unknown, to_repr: Str}, [32], ~, Str], # 33
  [Concat, ~, [2, 33], ~, Str], # 34
  [Concat, ~, [34, 23], ~, Str], # 35
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: fetches}, ~, ~, Str, 31], # 36
  [Coerce, {from_repr: Unknown, to_repr: Str}, [36], ~, Str], # 37
  [Concat, ~, [35, 37], ~, Str], # 38
  [Concat, ~, [38, 27], ~, Str], # 39
  [Print, ~, [39], 31, "Maybe[Boolean]"], # 40
  [Return, {implicit: true}, [1], 40, ~, 31]]} # 41
main::next_value: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: fetches}, ~, ~, Unknown, 1], # 2
  [Increment, ~, [2], ~, Scalar], # 3
  [Assign, ~, [2, 3], 0, Scalar, 1, true], # 4
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: fetches}, ~, ~, Num, 4], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [NumGt, ~, [5, 6], ~, Boolean], # 7
  [Constant, {const_type: string, value: second}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: first}, ~, ~, Str], # 9
  [TernaryExpr, ~, [7, 8, 9], ~, Str], # 10
  [Return, ~, [10], 4, ~, 4]]} # 11
```

## An empty return is the empty list

A bare `return` and `return ()` give a list caller nothing and a scalar caller undef; beside a `return LIST` each caller still gets its own reading.

```perl
sub collect { my ($n) = @_; return () unless defined $n; my @c = map { "n$_" } 1 .. $n; return @c }
sub pair    { my ($n) = @_; return unless $n; return ($n, $n + 1) }
my @a = collect(2); my @b = collect(undef); my @p = pair(0); my $s = pair(3);
print scalar(@a), " ", scalar(@b), " ", scalar(@p), " $s\n";
```

```behavior
parses: yes
```

```output
2 0 0 4
```

```ir
main::__PROGRAM__: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::collect, package: main, param_names: [], want: list}, [2], 0, List, 3, true], # 4
  [ArrayLiteral, {sigil: "@", symbol: a}, [4], ~, Array], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::collect, package: main, param_names: [], want: list}, [1], 4, List, 4, true], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::pair, package: main, param_names: [], want: list}, [7], 8, List, 8, true], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::pair, package: main, param_names: [], want: scalar}, [6], 9, List, 9, true], # 10
  [Count, ~, [5], ~, Int, 10], # 11
  [Coerce, {from_repr: Int, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 13
  [ArrayLiteral, {sigil: "@", symbol: b}, [8], ~, Array], # 14
  [Count, ~, [14], ~, Int, 10], # 15
  [Coerce, {from_repr: Int, to_repr: Str}, [15], ~, Str], # 16
  [ArrayLiteral, {sigil: "@", symbol: p}, [9], ~, Array], # 17
  [Count, ~, [17], ~, Int, 10], # 18
  [Coerce, {from_repr: Int, to_repr: Str}, [18], ~, Str], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 20
  [Concat, ~, [13, 20], ~, Str], # 21
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 22
  [Concat, ~, [21, 22], ~, Str], # 23
  [Print, ~, [12, 13, 16, 13, 19, 23], 10, "Maybe[Boolean]"], # 24
  [Return, {implicit: true}, [1], 24, ~, 10]]} # 25
main::collect: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 3
  [Defined, ~, [3], ~, Boolean], # 4
  [Not, ~, [4], ~, Boolean], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 1}, [6]], # 7
  [Loop, {bound: entry}, [7], 7], # 8
  [Phi, {region: 8}, [2, 33], ~, Array], # 9
  [ArrayLiteral, ~, [9], ~, List], # 10
  [Proj, {index: 0}, [6]], # 11
  [Proj, {index: 1}, [8]], # 12
  [Region, {head: 8}, [12]], # 13
  [Region, {head: 6}, [11, 13]], # 14
  [Phi, {predecessors: [11, 7], region: 14}, [1, 10], ~, List], # 15
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 16
  [Count, ~, [9], ~, Int], # 17
  [Coerce, {from_repr: List, to_repr: Scalar}, [17], ~, Scalar], # 18
  [Phi, {predecessors: [11, 7], region: 14}, [16, 18], ~, Scalar], # 19
  [MemStart], # 20
  [Return, ~, [15, 19], 14, ~, 20], # 21
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 22
  [Range, ~, [22, 3], ~, List], # 23
  [Count, ~, [23], ~, Int, 20], # 24
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 25
  [Phi, {region: 8}, [25, 34], ~, Int], # 26
  [Subscript, {kind: array}, [23, 26], ~, Scalar, 20], # 27
  [NumGt, ~, [24, 26], 8, Boolean], # 28
  [Coerce, {from_repr: Unknown, to_repr: Str}, [27], ~, Str], # 29
  [Proj, {index: 0}, [8]], # 30
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 31
  [Concat, ~, [31, 29], ~, Str], # 32
  [ListAppend, {collector: map}, [9, 32], ~, Array], # 33
  [Add, ~, [26, 22], ~, Int], # 34
  [ArgsSource, ~, ~, ~, Array], # 35
  [Assign, {record: true, targets: 1}, [3, 35], ~, List]]} # 36
main::pair: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Add, ~, [2, 3], ~, Unknown], # 4
  [ArrayLiteral, ~, [2, 4], ~, List], # 5
  [Not, ~, [2], ~, Boolean], # 6
  [If, ~, [0, 6], 0], # 7
  [Proj, {index: 0}, [7]], # 8
  [Proj, {index: 1}, [7]], # 9
  [Region, {head: 7}, [8, 9]], # 10
  [Phi, {predecessors: [8, 9], region: 10}, [1, 5], ~, List], # 11
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 12
  [Coerce, {from_repr: List, to_repr: Scalar}, [4], ~, Scalar], # 13
  [Phi, {predecessors: [8, 9], region: 10}, [12, 13], ~, Scalar], # 14
  [MemStart], # 15
  [Return, ~, [11, 14], 10, ~, 15], # 16
  [ArgsSource, ~, ~, ~, Array], # 17
  [Assign, {record: true, targets: 1}, [2, 17], ~, List]]} # 18
```

## An array built from a parameter after a guard

The array is built after the early return, from the parameter the first statement binds.

```perl
sub range_of { my ($n) = @_; return 0 unless $n; my @c = (1 .. $n); return scalar(@c) }
print range_of(0), " ", range_of(4), "\n";
```

```behavior
parses: yes
```

```output
0 4
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::range_of, package: main, param_names: [], want: list}, [2], 0, Int, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::range_of, package: main, param_names: [], want: list}, [7], 4, Int, 4, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [5, 6, 9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
main::range_of: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Int], # 3
  [Range, ~, [2, 3], ~, List], # 4
  [ArrayLiteral, {sigil: "@", symbol: c}, [4], ~, Array], # 5
  [MemStart], # 6
  [Count, ~, [5], ~, Int, 6], # 7
  [Not, ~, [3], ~, Boolean], # 8
  [If, ~, [0, 8], 0], # 9
  [Proj, {index: 0}, [9]], # 10
  [Proj, {index: 1}, [9]], # 11
  [Region, {head: 9}, [10, 11]], # 12
  [Phi, {predecessors: [10, 11], region: 12}, [1, 7], ~, Int], # 13
  [Return, ~, [13], 12, ~, 6], # 14
  [ArgsSource, ~, ~, ~, Array], # 15
  [Assign, {record: true, targets: 1}, [3, 15], ~, List]]} # 16
```

## A list call or the empty list, chosen by a ternary

The empty arm `()` contributes no elements; the array holds the call's two or nothing.

```perl
sub two { return (1, 2) }
sub pick { my ($p) = @_; my @c = defined $p ? two() : (); return scalar(@c) }
print pick(1), " ", pick(undef), "\n";
```

```behavior
parses: yes
```

```output
2 0
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::pick, package: main, param_names: [], want: list}, [2], 0, Int, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::pick, package: main, param_names: [], want: list}, [1], 4, Int, 4, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [5, 6, 8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7]]} # 11
main::pick: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: p}, ~, ~, Unknown], # 1
  [Defined, ~, [1], ~, Boolean], # 2
  [If, ~, [0, 2], 0], # 3
  [Proj, {index: 0}, [3]], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::two, package: main, param_names: [], want: list}, ~, 4, List, 5, true], # 6
  [ArrayLiteral, ~, ~, ~, List], # 7
  [Proj, {index: 1}, [3]], # 8
  [Region, {head: 3}, [6, 8]], # 9
  [Phi, {predecessors: [4, 8], region: 9}, [6, 7], ~, List], # 10
  [ArrayLiteral, {sigil: "@", symbol: c}, [10], ~, Array], # 11
  [Phi, {memory: true, predecessors: [4, 8], region: 9}, [6, 5], ~, Unknown], # 12
  [Count, ~, [11], ~, Int, 12], # 13
  [Return, ~, [13], 9, ~, 12], # 14
  [ArgsSource, ~, ~, ~, Array], # 15
  [Assign, {record: true, targets: 1}, [1, 15], ~, List]]} # 16
main::two: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [ArrayLiteral, ~, [1, 2], ~, List], # 3
  [Coerce, {from_repr: List, to_repr: Scalar}, [2], ~, Scalar], # 4
  [MemStart], # 5
  [Return, ~, [3, 4], 0, ~, 5]]} # 6
```

## A copy changed through a reference

`%then` is a copy of `%pre`; changing it through `\%then` leaves `%pre` alone.

```perl
sub add_key { my ($h) = @_; $h->{added} = 1 }
sub branch { my ($src) = @_; my %pre = %$src; my %then = %pre; add_key(\%then);
             return join(",", sort keys %pre) . " | " . join(",", sort keys %then) }
print branch({ base => 1 }), "\n";
```

```behavior
parses: yes
```

```output
base | added,base
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: base}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [HashLiteral, ~, [2, 3], 0, HashRef], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::branch, package: main, param_names: [], want: list}, [4], 4, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
main::add_key: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [PadAccess, {sigil: $, symbol: h}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: added}, ~, ~, Str], # 3
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Assign, ~, [4, 1], 0, Int, 5, true], # 6
  [Return, {implicit: true}, [1], 6, ~, 6], # 7
  [ArgsSource, ~, ~, ~, Array], # 8
  [Assign, {record: true, targets: 1}, [2, 8], ~, List]]} # 9
main::branch: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: src}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: "%", strict: false}, [2], ~, Hash, 3], # 4
  [HashLiteral, {sigil: "%", symbol: then}, [4], ~, Hash], # 5
  [Ref, ~, [5], ~, HashRef], # 6
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: "%", strict: false}, [2], 0, Hash, 3, true], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::add_key, package: main, param_names: [], want: void}, [6], 7, Int, 7, true], # 8
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [4], ~, List, 8], # 9
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [9], ~, List, 8], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 10], ~, Str, 8], # 11
  [Constant, {const_type: string, value: " | "}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [5], ~, List, 8], # 14
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [14], ~, List, 8], # 15
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 15], ~, Str, 8], # 16
  [Concat, ~, [13, 16], ~, Str], # 17
  [Return, ~, [17], 8, ~, 8], # 18
  [ArgsSource, ~, ~, ~, Array], # 19
  [Assign, {record: true, targets: 1}, [2, 19], ~, List]]} # 20
```

## A lexical declared bare, set in a branch, passed to a sub

`my $found;` declares the variable before the `if`; the store inside the arm is not its declaration.

```perl
sub load { "loaded " . ($_[0] // "nothing") }
sub find { my ($want) = @_; my $found; if ($want) { $found = "it"; } return load($found) }
print find(1), "; ", find(0), "\n";
```

```behavior
parses: yes
```

```output
loaded it; loaded nothing
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::find, package: main, param_names: [], want: list}, [2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "; "}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::find, package: main, param_names: [], want: list}, [7], 4, Str, 4, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [5, 6, 9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
main::find: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: found}, ~, ~, Unknown, 1], # 2
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 3
  [Assign, ~, [2, 3], 0, Undef, 1, true], # 4
  [PadAccess, {sigil: $, symbol: found}, ~, ~, Unknown, 4], # 5
  [Constant, {const_type: string, value: it}, ~, ~, Str], # 6
  [PadAccess, {sigil: $, symbol: want}, ~, ~, Unknown], # 7
  [If, ~, [4, 7], 4], # 8
  [Proj, {index: 0}, [8]], # 9
  [Assign, ~, [5, 6], 9, Str, 4, true], # 10
  [Proj, {index: 1}, [8]], # 11
  [Region, {head: 8}, [11, 10]], # 12
  [Phi, {memory: true, predecessors: [11, 9], region: 12}, [4, 10], ~, "Maybe[Str]"], # 13
  [PadAccess, {sigil: $, symbol: found}, ~, ~, Unknown, 13], # 14
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::load, package: main, param_names: []}, [14], 12, Str, 13, true], # 15
  [Return, ~, [15], 15, ~, 15], # 16
  [ArgsSource, ~, ~, ~, Array], # 17
  [Assign, {record: true, targets: 1}, [7, 17], ~, List]]} # 18
main::load: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "loaded "}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Constant, {const_type: string, value: nothing}, ~, ~, Str], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Concat, ~, [1, 8], ~, Str], # 9
  [Return, {implicit: true}, [9], 0, ~, 4]]} # 10
```

## A store, then last, read after the loop

The store on the arm that leaves the loop is the value after it; when the loop runs out, the variable is still undef.

```perl
sub load { "loaded " . ($_[0] // "nothing") }
sub search { my $found; for my $c (@_) { if ($c eq "b") { $found = $c; last; } } return load($found) }
print search("a", "b", "c"), "; ", search("a"), "\n";
```

```behavior
parses: yes
```

```output
loaded b; loaded nothing
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::search, package: main, param_names: [], want: list}, [2, 3, 4], 0, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "; "}, ~, ~, Str], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::search, package: main, param_names: [], want: list}, [2], 6, Str, 6, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [7, 8, 10, 11], 9, "Maybe[Boolean]"], # 12
  [Return, {implicit: true}, [1], 12, ~, 9]]} # 13
main::load: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "loaded "}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Constant, {const_type: string, value: nothing}, ~, ~, Str], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Concat, ~, [1, 8], ~, Str], # 9
  [Return, {implicit: true}, [9], 0, ~, 4]]} # 10
main::search: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: found}, ~, ~, Unknown, 1], # 2
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 3
  [Assign, ~, [2, 3], 0, Undef, 1, true], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Phi, {memory: true, region: 5}, [4, 6], ~, Unknown], # 6
  [PadAccess, {sigil: $, symbol: found}, ~, ~, Unknown, 6], # 7
  [ArgsSource, ~, ~, ~, Array], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Phi, {region: 5}, [9, 29], ~, Int], # 10
  [Subscript, {kind: array}, [8, 10], ~, Scalar, 6], # 11
  [Proj, {index: 0}, [5]], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 13
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 14
  [StrEq, ~, [13, 14], ~, Boolean], # 15
  [If, ~, [12, 15], 12], # 16
  [Proj, {index: 0}, [16]], # 17
  [Assign, ~, [7, 11], 17, Scalar, 6, true], # 18
  [Proj, {index: 1}, [5]], # 19
  [Region, {head: 5}, [19, 18]], # 20
  [Phi, {memory: true, region: 20}, [6, 18], ~, Unknown], # 21
  [PadAccess, {sigil: $, symbol: found}, ~, ~, Unknown, 21], # 22
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::load, package: main, param_names: []}, [22], 20, Str, 21, true], # 23
  [Return, ~, [23], 23, ~, 23], # 24
  [Count, ~, [8], ~, Int, 4], # 25
  [Count, ~, [8], ~, Int, 6], # 26
  [NumGt, ~, [26, 10], 5, Boolean], # 27
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 28
  [Add, ~, [10, 28], ~, Int], # 29
  [Proj, {index: 1}, [16]]]} # 30
```

## A list repeated, and a string repeated

`(LIST) x N` makes N copies of the list's elements; `STR x N` makes one string.

```perl
my $n = 3;
my @dashes = ("-") x $n;
my @pairs  = (1, 2) x 2;
print scalar(@dashes), " [@pairs] ", "=" x $n, "\n";
```

```behavior
parses: yes
```

```output
3 [1 2 1 2] ===
```

```ir
main::__PROGRAM__: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 2
  [ArrayLiteral, ~, [2], ~, List], # 3
  [Coerce, {from_repr: List, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 5
  [Repeat, ~, [4, 5], ~, List], # 6
  [ArrayLiteral, {sigil: "@", symbol: dashes}, [6], ~, Array], # 7
  [MemStart], # 8
  [Count, ~, [7], ~, Int, 8], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " ["}, ~, ~, Str], # 11
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 8], # 12
  [Coerce, {from_repr: Scalar, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 14
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 15
  [ArrayLiteral, ~, [14, 15], ~, List], # 16
  [Coerce, {from_repr: List, to_repr: Str}, [16], ~, Str], # 17
  [Repeat, ~, [17, 15], ~, List], # 18
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [13, 18], ~, Str, 8], # 19
  [Concat, ~, [11, 19], ~, Str], # 20
  [Constant, {const_type: string, value: "] "}, ~, ~, Str], # 21
  [Concat, ~, [20, 21], ~, Str], # 22
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 23
  [Repeat, ~, [23, 5], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [Print, ~, [10, 22, 24, 25], 0, "Maybe[Boolean]"], # 26
  [Return, {implicit: true}, [1], 26, ~, 8], # 27
  [ArrayLiteral, {sigil: "@", symbol: pairs}, [18], ~, Array]]} # 28
```

## A postfix if and a postfix unless that rebind a lexical

Each modifier rebinds a lexical on one path; the value after it is the old one when the guard fails. pvm's corpus had no statement-modifier assignment.

```perl
sub describe {
    my ($value, $quantifier) = @_;
    my $str = ref $value ? "<ref>" : $value;
    $str .= $quantifier if defined $quantifier;
    my $sign = "+";
    $sign = "-" unless $value gt "m";
    return "$sign$str";
}
print describe("a", "*"), " ", describe("z"), " ", describe([1], "?"), "\n";
```

```behavior
parses: yes
```

```output
-a* +z -<ref>?
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "*"}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::describe, package: main, param_names: [], want: list}, [2, 3], 0, Str, 4, true], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::describe, package: main, param_names: [], want: list}, [8], 5, Str, 5, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [ArrayLiteral, ~, [11], 9, ArrayRef], # 12
  [Constant, {const_type: string, value: "?"}, ~, ~, Str], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::describe, package: main, param_names: [], want: list}, [12, 13], 12, Str, 9, true], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Print, ~, [6, 7, 10, 7, 15, 16], 14, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [1], 17, ~, 14]]} # 18
main::describe: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: value}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: m}, ~, ~, Str], # 2
  [StrGt, ~, [1, 2], ~, Boolean], # 3
  [Constant, {const_type: string, value: "+"}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 5
  [PadAccess, {sigil: $, symbol: quantifier}, ~, ~, Unknown], # 6
  [Defined, ~, [6], ~, Boolean], # 7
  [MemStart], # 8
  [RefType, ~, [1], ~, Str, 8], # 9
  [Constant, {const_type: string, value: "<ref>"}, ~, ~, Str], # 10
  [TernaryExpr, ~, [9, 10, 1], ~, Unknown], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [TernaryExpr, {rebind_arm: 1}, [7, 13, 11], 0, Unknown], # 14
  [TernaryExpr, {rebind_arm: 2}, [3, 4, 5], 14, Str], # 15
  [Concat, ~, [15, 14], ~, Str], # 16
  [Return, ~, [16], 15, ~, 8], # 17
  [ArgsSource, ~, ~, ~, Array], # 18
  [Assign, {record: true, targets: 2}, [1, 6, 18], ~, List]]} # 19
```


## An element store in a returned ternary

A ternary whose arm stores an element yields the stored value. Returned, it is in the caller's context, so the value must not be dropped as if it were void.

```perl
sub f { my @a = (0); return $_[0] ? ($a[0] = 7) : 8 }
print f(1), f(0), "\n";
```

```behavior
parses: yes
```

```output
78
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [2], 0, Int, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [6], 4, Int, 4, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [5, 8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7]]} # 11
main::f: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [ArrayLiteral, {sigil: "@", symbol: a}, [1], ~, Array], # 2
  [Subscript, {kind: array}, [2, 1], ~, Int], # 3
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [MemStart], # 6
  [Subscript, {kind: array}, [5, 1], ~, Scalar, 6], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [Assign, ~, [3, 4], 9, Int, 6, true], # 10
  [Subscript, {kind: array}, [2, 1, 10], ~, Int], # 11
  [Constant, {const_type: integer, value: "8"}, ~, ~, Int], # 12
  [Proj, {index: 1}, [8]], # 13
  [Region, {head: 8}, [10, 13]], # 14
  [Phi, {predecessors: [9, 13], region: 14}, [11, 12], ~, Int], # 15
  [Phi, {memory: true, predecessors: [9, 13], region: 14}, [10, 6], ~, Unknown], # 16
  [Return, ~, [15], 14, ~, 16]]} # 17
```

## A hash element chosen by a ternary inside a call's argument list

The element in the arm is a deferred lvalue (the callee could write it). It is not a store, so the ternary is an ordinary value select.

```perl
sub g { return join ",", @_ }
sub f { my %o = @_; return g(r => (exists $o{a} ? $o{a} : 'dflt')) }
print f(a => 1), " ", f(b => 2), "\n";
```

```behavior
parses: yes
```

```output
r,1 r,dflt
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2, 3], 0, Str, 4, true], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 8
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [8, 9], 5, Str, 5, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [6, 7, 11, 12], 10, "Maybe[Boolean]"], # 13
  [Return, {implicit: true}, [1], 13, ~, 10]]} # 14
main::f: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: r}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [HashLiteral, {sigil: "%", symbol: o}, [2], ~, Hash], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [MemStart], # 5
  [Exists, {kind: hash}, [3, 4], ~, Boolean, 5], # 6
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 7
  [Constant, {const_type: string, value: dflt}, ~, ~, Str], # 8
  [TernaryExpr, ~, [6, 7, 8], ~, Unknown], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: []}, [1, 9], 0, Str, 5, true], # 10
  [Return, ~, [10], 10, ~, 10]]} # 11
main::g: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 2], ~, Str, 3], # 4
  [Return, ~, [4], 0, ~, 3]]} # 5
```

## A sprintf of an element, then a call that writes it

A sprintf argument is flagged as a deferred lvalue, but sprintf only reads it. Its value must be the element before the callee writes through `$_[0]`.

```perl
sub g { $_[0] = 5 }
my %h = (a => 1);
my $c = 1;
my $x = sprintf("%s", $c ? $h{a} : 8);
g($h{a});
print "$x $h{a}\n";
```

```behavior
parses: yes
```

```output
1 5
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "%s"}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [HashLiteral, {sigil: "%", symbol: h}, [4, 3], ~, Hash], # 5
  [MemStart], # 6
  [Subscript, {kind: hash}, [5, 4], ~, Int, 6], # 7
  [Constant, {const_type: integer, value: "8"}, ~, ~, Int], # 8
  [TernaryExpr, ~, [3, 7, 8], ~, Unknown], # 9
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [2, 9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Subscript, {kind: hash}, [5, 4], ~, Int], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::g, package: main, param_names: [], want: void}, [13], 0, Int, 6, true], # 14
  [Subscript, {kind: hash}, [5, 4], ~, Scalar, 14], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [12, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Print, ~, [19], 14, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 14]]} # 21
main::g: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Assign, ~, [4, 1], 0, Int, 5, true], # 6
  [Return, {implicit: true}, [1], 6, ~, 6]]} # 7
```

## sprintf arguments read before a store

A `%s`-only sprintf becomes a multiconcat. Both forms read their element arguments where they stand.

```perl
my %h = (a => 1);
my @a = (2);
my $x = sprintf("%s %d", $h{a}, $a[0]);
$h{a} = 5;
$a[0] = 6;
print "$x $h{a} $a[0]\n";
```

```behavior
parses: yes
```

```output
1 2 5 6
```

```ir
main::__PROGRAM__: {start: 0, returns: [31], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "%s %d"}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [HashLiteral, {sigil: "%", symbol: h}, [3, 4], ~, Hash], # 5
  [MemStart], # 6
  [Subscript, {kind: hash}, [5, 3], ~, Int, 6], # 7
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 8
  [ArrayLiteral, {sigil: "@", symbol: a}, [8], ~, Array], # 9
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [9, 10], ~, Int, 6], # 11
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [2, 7, 11], ~, Str], # 12
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [Subscript, {kind: array}, [9, 10], ~, Int], # 15
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 16
  [Subscript, {kind: hash}, [5, 3], ~, Int], # 17
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 18
  [Assign, ~, [17, 18], 0, Int, 6, true], # 19
  [Assign, ~, [15, 16], 19, Int, 19, true], # 20
  [Subscript, {kind: hash}, [5, 3], ~, Scalar, 20], # 21
  [Coerce, {from_repr: Unknown, to_repr: Str}, [21], ~, Str], # 22
  [Concat, ~, [14, 22], ~, Str], # 23
  [Concat, ~, [23, 13], ~, Str], # 24
  [Subscript, {kind: array}, [9, 10], ~, Int, 20], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 26
  [Concat, ~, [24, 26], ~, Str], # 27
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 28
  [Concat, ~, [27, 28], ~, Str], # 29
  [Print, ~, [29], 20, "Maybe[Boolean]"], # 30
  [Return, {implicit: true}, [1], 30, ~, 20]]} # 31
```

## A block comparator that calls a method

A comparator block that calls a sub or declares a `my` gets a real scope, which perl's optimizer leaves as an ex-leave; it is still a block, not a comparator chosen at runtime.

```perl
package N { sub new { bless { n => $_[1] }, $_[0] } sub name { $_[0]{n} } }
my @ns = map { N->new($_) } qw(pear apple fig);
my @by = sort { $a->name cmp $b->name } @ns;
print join(" ", map { $_->name } @by), "\n";
my @len = sort { my $x = length $a->name; $x <=> length $b->name } @ns;
print join(" ", map { $_->name } @len), "\n";
```

```behavior
parses: yes
```

```output
apple fig pear
fig pear apple
```

```ir
N::name: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
N::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [HashLiteral, ~, [1, 5], 0, HashRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7], ~, Scalar, 4], # 8
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [6, 8], 6, Unknown, 4, true], # 9
  [Return, {implicit: true}, [9], 9, ~, 9]]} # 10
main::__PROGRAM__: {start: 0, returns: [32], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [ArrayLiteral, ~, ~, ~, Array], # 4
  [Loop, {bound: entry}, [0], 0], # 5
  [Phi, {region: 5}, [4, 63], ~, Array], # 6
  [ArrayLiteral, ~, ~, ~, Array], # 7
  [Proj, {index: 1}, [5]], # 8
  [Region, {head: 5}, [8]], # 9
  [MemStart], # 10
  [Phi, {memory: true, region: 5}, [10, 57], ~, Unknown], # 11
  [Phi, {memory: true, region: 9}, [11], ~, Unknown], # 12
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:1, sort_package: main, want: list}, [6], 9, List, 12, true], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Phi, {region: 14}, [7, 75], ~, Array], # 15
  [Phi, {memory: true, region: 14}, [13, 74], ~, Unknown], # 16
  [Proj, {index: 1}, [14]], # 17
  [Region, {head: 14}, [17]], # 18
  [Phi, {memory: true, region: 18}, [16], ~, Unknown], # 19
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 15], ~, Str, 19], # 20
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 21
  [Print, ~, [20, 21], 18, "Maybe[Boolean]"], # 22
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:2, sort_package: main, want: list}, [6], 22, List, 19, true], # 23
  [Loop, {bound: entry}, [23], 23], # 24
  [Phi, {region: 24}, [3, 58], ~, Array], # 25
  [Phi, {memory: true, region: 24}, [23, 51], ~, Unknown], # 26
  [Proj, {index: 1}, [24]], # 27
  [Region, {head: 24}, [27]], # 28
  [Phi, {memory: true, region: 28}, [26], ~, Unknown], # 29
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 25], ~, Str, 29], # 30
  [Print, ~, [30, 21], 28, "Maybe[Boolean]"], # 31
  [Return, {implicit: true}, [1], 31, ~, 29], # 32
  [Constant, {const_type: string, value: pear}, ~, ~, Str], # 33
  [Constant, {const_type: string, value: apple}, ~, ~, Str], # 34
  [Constant, {const_type: string, value: fig}, ~, ~, Str], # 35
  [ArrayLiteral, ~, [33, 34, 35], ~, List], # 36
  [Count, ~, [36], ~, Int, 11], # 37
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 38
  [Phi, {region: 5}, [38, 54], ~, Int], # 39
  [NumGt, ~, [37, 39], 5, Boolean], # 40
  [Proj, {index: 0}, [5]], # 41
  [Subscript, {kind: array}, [36, 39], ~, Scalar], # 42
  [Ref, ~, [42], ~, ScalarRef], # 43
  [LocalAlias, {name: _}, [43], 41, Unknown, 11], # 44
  [Phi, {region: 24}, [38, 68], ~, Int], # 45
  [Subscript, {kind: array}, [23, 45], ~, Scalar, 26], # 46
  [Subscript, {kind: array}, [23, 45], ~, Scalar], # 47
  [Ref, ~, [47], ~, ScalarRef], # 48
  [Proj, {index: 0}, [24]], # 49
  [LocalAlias, {name: _}, [48], 49, Unknown, 26], # 50
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: name, package: main, param_names: [], want: list}, [46], 50, Unknown, 26, true], # 51
  [Count, ~, [23], ~, Int, 26], # 52
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 53
  [Add, ~, [39, 53], ~, Int], # 54
  [Subscript, {kind: array}, [36, 39], ~, Str, 11], # 55
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 56
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: new, package: main, param_names: [], want: list}, [56, 55], 44, Object, 11, true], # 57
  [ListAppend, {collector: map}, [25, 51], ~, Array], # 58
  [Count, ~, [23], ~, Int, 23], # 59
  [NumGt, ~, [52, 45], 24, Boolean], # 60
  [Count, ~, [36], ~, Int, 10], # 61
  [Phi, {region: 14}, [38, 69], ~, Int], # 62
  [ListAppend, {collector: map}, [6, 57], ~, Array], # 63
  [Count, ~, [13], ~, Int, 13], # 64
  [Count, ~, [13], ~, Int, 16], # 65
  [Subscript, {kind: array}, [13, 62], ~, Scalar, 16], # 66
  [Subscript, {kind: array}, [13, 62], ~, Scalar], # 67
  [Add, ~, [45, 53], ~, Int], # 68
  [Add, ~, [62, 53], ~, Int], # 69
  [NumGt, ~, [65, 62], 14, Boolean], # 70
  [Proj, {index: 0}, [14]], # 71
  [Ref, ~, [67], ~, ScalarRef], # 72
  [LocalAlias, {name: _}, [72], 71, Unknown, 16], # 73
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: name, package: main, param_names: [], want: list}, [66], 73, Unknown, 16, true], # 74
  [ListAppend, {collector: map}, [15, 74], ~, Array]]} # 75
main::__PROGRAM__::__SORTCMP__:1: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: a}, ~, ~, Scalar, 1], # 2
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: name, package: main, param_names: [], want: scalar}, [2], 0, Unknown, 1, true], # 3
  [EntryDef, {package: main, sigil: $, symbol: b}, ~, ~, Scalar, 3], # 4
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: name, package: main, param_names: [], want: scalar}, [4], 3, Unknown, 3, true], # 5
  [StrCmp, ~, [3, 5], ~, Int], # 6
  [Return, {implicit: true}, [6], 5, ~, 5]]} # 7
main::__PROGRAM__::__SORTCMP__:2: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: a}, ~, ~, Scalar, 1], # 2
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: name, package: main, param_names: [], want: scalar}, [2], 0, Unknown, 1, true], # 3
  [Length, ~, [3], ~, Int], # 4
  [EntryDef, {package: main, sigil: $, symbol: b}, ~, ~, Scalar, 3], # 5
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: name, package: main, param_names: [], want: scalar}, [5], 3, Unknown, 3, true], # 6
  [Length, ~, [6], ~, Int], # 7
  [NumCmp, ~, [4, 7], ~, Int], # 8
  [Return, {implicit: true}, [8], 6, ~, 6]]} # 9
```

## An in-place sort in one arm

Perl folds `@a = sort ... @a` into the sort. Inside an `if` arm, the join must merge the array, not its count.

```perl
my @a = (3,1,2);
if (!@ARGV) { @a = sort { my $t=$a; $t <=> $b } @a }
print "@a\n";
```

```behavior
parses: yes
```

```output
1 2 3
```

```ir
main::__PROGRAM__: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [ArrayLiteral, {sigil: "@", symbol: a}, [3, 4, 5], ~, Array], # 6
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 7
  [Count, ~, [7], ~, Int, 2], # 8
  [If, ~, [0, 8], 0], # 9
  [Proj, {index: 1}, [9]], # 10
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:1, sort_package: main, want: list}, [6], 10, List, 2, true], # 11
  [Proj, {index: 0}, [9]], # 12
  [Region, {head: 9}, [12, 11]], # 13
  [Phi, {memory: true, predecessors: [12, 10], region: 13}, [2, 11], ~, Unknown], # 14
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 14], # 15
  [Coerce, {from_repr: Scalar, to_repr: Str}, [15], ~, Str], # 16
  [ArrayLiteral, {sigil: "@", symbol: a}, [11], ~, Array], # 17
  [Phi, {predecessors: [12, 10], region: 13}, [6, 17], ~, Array], # 18
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [16, 18], ~, Str, 14], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [Print, ~, [21], 13, "Maybe[Boolean]"], # 22
  [Return, {implicit: true}, [1], 22, ~, 14]]} # 23
main::__PROGRAM__::__SORTCMP__:1: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: a}, ~, ~, Scalar, 1], # 2
  [Coerce, {from_repr: Scalar, to_repr: Num}, [2], ~, Num], # 3
  [EntryDef, {package: main, sigil: $, symbol: b}, ~, ~, Scalar, 1], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [NumCmp, ~, [3, 5], ~, Int], # 6
  [Return, {implicit: true}, [6], 0, ~, 1]]} # 7
```

## A comparator sort on the right of an untaken &&

The sort is pinned in the &&'s arm. The binding of the && value must sit after the join, not inside the arm.

```perl
sub c { $a <=> $b }
my @r = @ARGV && sort c 3,1,2;
print scalar(@r), "\n";
```

```behavior
parses: yes
```

```output
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 2
  [MemStart], # 3
  [Count, ~, [2], ~, Int, 3], # 4
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [If, ~, [0, 4], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::c, sort_package: main, want: list}, [5, 6, 7], 9, List, 3, true], # 10
  [And, ~, [4, 10], ~, List], # 11
  [ArrayLiteral, {sigil: "@", symbol: r}, [11], ~, Array], # 12
  [Proj, {index: 1}, [8]], # 13
  [Region, {head: 8}, [13, 10]], # 14
  [Phi, {memory: true, predecessors: [13, 9], region: 14}, [3, 10], ~, Unknown], # 15
  [Count, ~, [12], ~, Int, 15], # 16
  [Coerce, {from_repr: Int, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [17, 18], 14, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [1], 19, ~, 15]]} # 20
main::c: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: a}, ~, ~, Scalar, 1], # 2
  [Coerce, {from_repr: Scalar, to_repr: Num}, [2], ~, Num], # 3
  [EntryDef, {package: main, sigil: $, symbol: b}, ~, ~, Scalar, 1], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [NumCmp, ~, [3, 5], ~, Int], # 6
  [Return, {implicit: true}, [6], 0, ~, 1]]} # 7
```

## Two targets from a ternary of a list call

The value merges two arms of unknown arity. Perl spreads it over the targets at runtime.

```perl
sub f {(1,2)}
my ($x,$y) = !@ARGV ? f() : ();
print "$x $y\n";
```

```behavior
parses: yes
```

```output
1 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [PadAccess, {sigil: $, symbol: "y"}, ~, ~, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Concat, ~, [5, 7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 11
  [MemStart], # 12
  [Count, ~, [11], ~, Int, 12], # 13
  [Not, ~, [13], ~, Boolean], # 14
  [If, ~, [0, 14], 0], # 15
  [Proj, {index: 0}, [15]], # 16
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, ~, 16, List, 12, true], # 17
  [ArrayLiteral, ~, ~, ~, List], # 18
  [Proj, {index: 1}, [15]], # 19
  [Region, {head: 15}, [17, 19]], # 20
  [Phi, {predecessors: [16, 19], region: 20}, [17, 18], ~, List], # 21
  [Phi, {memory: true, predecessors: [16, 19], region: 20}, [17, 12], ~, Unknown], # 22
  [Assign, {targets: 2}, [2, 6, 21], 20, List, 22, true], # 23
  [Print, ~, [10], 23, "Maybe[Boolean]"], # 24
  [Return, {implicit: true}, [1], 24, ~, 23]]} # 25
main::f: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [ArrayLiteral, ~, [1, 2], ~, List], # 3
  [Coerce, {from_repr: List, to_repr: Scalar}, [2], ~, Scalar], # 4
  [MemStart], # 5
  [Return, {implicit: true}, [3, 4], 0, ~, 5]]} # 6
```

## A returned eval that may die, called both ways

A list caller gets () when the body dies, and a scalar caller gets undef.

```perl
sub w { return eval { die "x\n" if $_[0]; 5 } }
my @r = w(1); my $s = w(1);
print scalar(@r), " ", defined $s ? "d" : "u", " ", w(0), "\n";
```

```behavior
parses: yes
```

```output
0 u 5
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::w, package: main, param_names: [], want: list}, [2], 0, "Maybe[Int]", 3, true], # 4
  [ArrayLiteral, {sigil: "@", symbol: r}, [4], ~, Array], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::w, package: main, param_names: [], want: scalar}, [2], 4, "Maybe[Int]", 4, true], # 6
  [Count, ~, [5], ~, Int, 6], # 7
  [Coerce, {from_repr: Int, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Defined, ~, [6], ~, Boolean], # 10
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 12
  [TernaryExpr, ~, [10, 11, 12], ~, Str], # 13
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 14
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::w, package: main, param_names: [], want: list}, [14], 6, "Maybe[Int]", 6, true], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [8, 9, 13, 9, 16, 17], 15, "Maybe[Boolean]"], # 18
  [Return, {implicit: true}, [1], 18, ~, 15]]} # 19
main::w: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 2
  [MemStart], # 3
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 3], # 4
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 5
  [EntryWrite, ~, [4, 5], 0, Unknown, 3, true], # 6
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 6], # 7
  [ArgsSource, ~, ~, ~, Array], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Subscript, {kind: array}, [8, 9], ~, Scalar, 6], # 10
  [If, ~, [6, 10], 6], # 11
  [Proj, {index: 1}, [11]], # 12
  [Constant, {const_type: string, value: "x\n"}, ~, ~, Str], # 13
  [Proj, {index: 0}, [11]], # 14
  [Unwind, {eval_id: 1, file: "/tmp/mvrHQew3rs/case.pl", line: 1}, [13], 14, ~, 6], # 15
  [Region, {head: 11}, [12, 15]], # 16
  [EntryWrite, ~, [7, 5], 16, Unknown, 6, true], # 17
  [Exc, ~, [15]], # 18
  [Region, {catch: true, eval_id: 1}, [18]], # 19
  [EntryWrite, ~, [7, 18], 19, Unknown, 6, true], # 20
  [Region, {eval_entry: 0, eval_id: 1, eval_want: runtime}, [17, 20]], # 21
  [Phi, {region: 21}, [1, 2], ~, "Maybe[Int]"], # 22
  [Phi, {memory: true, region: 21}, [17, 20], ~, Unknown], # 23
  [Return, ~, [22], 21, ~, 23]]} # 24
```

## A comparator block that calls a method

Every comparator in chalk's lib/ that refused calls a method on `$a` and `$b`. A block that calls a sub gets a real leave, which perl nulls, so the comparator slot holds an ex-leave rather than a scope. It is still an inline block, and it sorts by what it returns.

```perl
package Node { sub new { bless { id => $_[1] }, $_[0] } sub id { $_[0]{id} } }
my %member = map { $_ => Node->new($_) } qw(n3 n1 n2);
print join(",", map { $_->id } sort { $a->id cmp $b->id } values %member), "\n";
```

```ir
Node::id: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: id}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
Node::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: id}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [HashLiteral, ~, [1, 5], 0, HashRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7], ~, Scalar, 4], # 8
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [6, 8], 6, Unknown, 4, true], # 9
  [Return, {implicit: true}, [9], 9, ~, 9]]} # 10
main::__PROGRAM__: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [ArrayLiteral, ~, ~, ~, Array], # 4
  [Loop, {bound: entry}, [0], 0], # 5
  [Phi, {region: 5}, [4, 54], ~, Array], # 6
  [HashLiteral, {sigil: "%", symbol: member}, [6], ~, Hash], # 7
  [MemStart], # 8
  [Phi, {memory: true, region: 5}, [8, 49], ~, Unknown], # 9
  [Proj, {index: 1}, [5]], # 10
  [Region, {head: 5}, [10]], # 11
  [Phi, {memory: true, region: 11}, [9], ~, Unknown], # 12
  [Call, {dispatch_kind: builtin, name: values, param_names: [], want: list}, [7], ~, List, 12], # 13
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:1, sort_package: main, want: list}, [13], 11, List, 12, true], # 14
  [Loop, {bound: entry}, [14], 14], # 15
  [Phi, {region: 15}, [3, 50], ~, Array], # 16
  [Phi, {memory: true, region: 15}, [14, 43], ~, Unknown], # 17
  [Proj, {index: 1}, [15]], # 18
  [Region, {head: 15}, [18]], # 19
  [Phi, {memory: true, region: 19}, [17], ~, Unknown], # 20
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 16], ~, Str, 20], # 21
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 22
  [Print, ~, [21, 22], 19, "Maybe[Boolean]"], # 23
  [Return, {implicit: true}, [1], 23, ~, 20], # 24
  [Constant, {const_type: string, value: n3}, ~, ~, Str], # 25
  [Constant, {const_type: string, value: n1}, ~, ~, Str], # 26
  [Constant, {const_type: string, value: n2}, ~, ~, Str], # 27
  [ArrayLiteral, ~, [25, 26, 27], ~, List], # 28
  [Count, ~, [28], ~, Int, 9], # 29
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 30
  [Phi, {region: 5}, [30, 46], ~, Int], # 31
  [NumGt, ~, [29, 31], 5, Boolean], # 32
  [Proj, {index: 0}, [5]], # 33
  [Subscript, {kind: array}, [28, 31], ~, Scalar], # 34
  [Ref, ~, [34], ~, ScalarRef], # 35
  [LocalAlias, {name: _}, [35], 33, Unknown, 9], # 36
  [Phi, {region: 15}, [30, 55], ~, Int], # 37
  [Subscript, {kind: array}, [14, 37], ~, Scalar, 17], # 38
  [Subscript, {kind: array}, [14, 37], ~, Scalar], # 39
  [Ref, ~, [39], ~, ScalarRef], # 40
  [Proj, {index: 0}, [15]], # 41
  [LocalAlias, {name: _}, [40], 41, Unknown, 17], # 42
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: id, package: main, param_names: [], want: list}, [38], 42, Unknown, 17, true], # 43
  [Count, ~, [14], ~, Int, 17], # 44
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 45
  [Add, ~, [31, 45], ~, Int], # 46
  [Subscript, {kind: array}, [28, 31], ~, Str, 9], # 47
  [Constant, {const_type: string, value: Node}, ~, ~, Str], # 48
  [Call, {class_name: Node, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: new, package: main, param_names: [], want: list}, [48, 47], 36, Object, 9, true], # 49
  [ListAppend, {collector: map}, [16, 43], ~, Array], # 50
  [Count, ~, [14], ~, Int, 14], # 51
  [NumGt, ~, [44, 37], 15, Boolean], # 52
  [Count, ~, [28], ~, Int, 8], # 53
  [ListAppend, {collector: map}, [6, 47, 49], ~, Array], # 54
  [Add, ~, [37, 45], ~, Int]]} # 55
main::__PROGRAM__::__SORTCMP__:1: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: a}, ~, ~, Scalar, 1], # 2
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: id, package: main, param_names: [], want: scalar}, [2], 0, Unknown, 1, true], # 3
  [EntryDef, {package: main, sigil: $, symbol: b}, ~, ~, Scalar, 3], # 4
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: id, package: main, param_names: [], want: scalar}, [4], 3, Unknown, 3, true], # 5
  [StrCmp, ~, [3, 5], ~, Int], # 6
  [Return, {implicit: true}, [6], 5, ~, 5]]} # 7
```

## A sort inside a list-context eval

An eval's value in list context is a list. The sort runs in list context and the eval yields all of it. A die in the comparator is caught, leaves the list empty, and sets `$@`.

```perl
my @r = eval { sort { die "boom\n" if $a == 2; $a <=> $b } 3, 1, 2 };
print "[@r] $@";
```

```behavior
parses: yes
```

```output
[] boom
```

```ir
main::__PROGRAM__: {start: 0, returns: [29], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [MemStart], # 6
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 6], # 7
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 8
  [EntryWrite, ~, [7, 8], 0, Unknown, 6, true], # 9
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:1, sort_package: main, want: list}, [3, 4, 5], 9, List, 9, true], # 10
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 10], # 11
  [EntryWrite, ~, [11, 8], 10, Unknown, 10, true], # 12
  [Exc, ~, [10]], # 13
  [Region, {catch: true, eval_id: 1}, [13]], # 14
  [EntryWrite, ~, [11, 13], 14, Unknown, 10, true], # 15
  [Region, {eval_entry: 0, eval_id: 1, eval_want: list}, [12, 15]], # 16
  [Phi, {memory: true, region: 16}, [12, 15], ~, Unknown], # 17
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 17], # 18
  [Coerce, {from_repr: Scalar, to_repr: Str}, [18], ~, Str], # 19
  [Phi, {region: 16}, [10, 1], ~, List], # 20
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [19, 20], ~, Str, 17], # 21
  [Concat, ~, [2, 21], ~, Str], # 22
  [Constant, {const_type: string, value: "] "}, ~, ~, Str], # 23
  [Concat, ~, [22, 23], ~, Str], # 24
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 16, Scalar, 17], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 26
  [Concat, ~, [24, 26], ~, Str], # 27
  [Print, ~, [27], 25, "Maybe[Boolean]"], # 28
  [Return, {implicit: true}, [1], 28, ~, 17], # 29
  [ArrayLiteral, {sigil: "@", symbol: r}, [20], ~, Array]]} # 30
main::__PROGRAM__::__SORTCMP__:1: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: a}, ~, ~, Scalar, 1], # 2
  [Coerce, {from_repr: Scalar, to_repr: Num}, [2], ~, Num], # 3
  [EntryDef, {package: main, sigil: $, symbol: b}, ~, ~, Scalar, 1], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [NumCmp, ~, [3, 5], ~, Int], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [NumEq, ~, [3, 7], ~, Boolean], # 8
  [If, ~, [0, 8], 0], # 9
  [Proj, {index: 1}, [9]], # 10
  [Constant, {const_type: string, value: "boom\n"}, ~, ~, Str], # 11
  [Proj, {index: 0}, [9]], # 12
  [Unwind, {file: "/tmp/mvrHQew3rs/case.pl", line: 1}, [11], 12, ~, 1], # 13
  [Region, {head: 9}, [10, 13]], # 14
  [Return, {implicit: true}, [6], 14, ~, 1]]} # 15
```

## A defined-or that returns inside an if arm

Reduced from TypeLibrary::operand_repr_for_ir_op. The fallback leaves the sub; on the path that goes on, the value is the left side.

```perl
sub repr {
    my ($sig, $want) = @_;
    my $w;
    if ($want) {
        my $args = $sig->{args} // return "none";
        $w = $args + 1;
    } else {
        $w = 0;
    }
    return $w;
}
print repr({args => 2}, 1), " ", repr({}, 1), " ", repr({}, 0), "\n";
```

```behavior
parses: yes
```

```output
3 none 0
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: args}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [HashLiteral, ~, [2, 3], 0, HashRef], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 12, name: main::repr, package: main, param_names: [], want: list}, [4, 5], 4, Str, 6, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [HashLiteral, ~, ~, 7, HashRef], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 12, name: main::repr, package: main, param_names: [], want: list}, [10, 5], 10, Str, 7, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [HashLiteral, ~, ~, 11, HashRef], # 13
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 14
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 12, name: main::repr, package: main, param_names: [], want: list}, [13, 14], 13, Str, 11, true], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [8, 9, 12, 9, 16, 17], 15, "Maybe[Boolean]"], # 18
  [Return, {implicit: true}, [1], 18, ~, 15]]} # 19
main::repr: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: sig}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: args}, ~, ~, Str], # 3
  [PadAccess, {sigil: $, symbol: want}, ~, ~, Unknown], # 4
  [If, ~, [0, 4], 0], # 5
  [Proj, {index: 0}, [5]], # 6
  [MemStart], # 7
  [Subscript, {kind: hash}, [2, 3], 6, Scalar, 7, true], # 8
  [Coerce, {from_repr: Scalar, to_repr: Num}, [8], ~, Num], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Add, ~, [9, 10], ~, Num], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Defined, ~, [8], ~, Boolean], # 13
  [Not, ~, [13], ~, Boolean], # 14
  [If, ~, [8, 14], 8], # 15
  [Proj, {index: 1}, [15]], # 16
  [Proj, {index: 1}, [5]], # 17
  [Region, {head: 5}, [16, 17]], # 18
  [Phi, {predecessors: [6, 17], region: 18}, [11, 12], ~, Num], # 19
  [Proj, {index: 0}, [15]], # 20
  [Region, ~, [20, 18]], # 21
  [Phi, {predecessors: [20, 18], region: 21}, [1, 19], ~, Str], # 22
  [Phi, {memory: true, predecessors: [6, 17], region: 18}, [8, 7], ~, Unknown], # 23
  [Phi, {exits: true, memory: true, predecessors: [20, 18], region: 21}, [8, 23], ~, Unknown], # 24
  [Return, ~, [22], 21, ~, 24], # 25
  [ArgsSource, ~, ~, ~, Array], # 26
  [Assign, {record: true, targets: 2}, [2, 4, 26], ~, List]]} # 27
```

## A last guarded by a seen-hash increment in a foreach

Reduced from TypedInvariant::_arm_proj_of. The increment runs only when the left side lets it, and the and/or is a guard, not the loop condition.

```perl
sub count {
    my %seen;
    my $c = 0;
    for my $x (@_) {
        last if $x > 1 && $seen{$x}++;
        $c++;
    }
    return $c;
}
print count(1, 2, 3, 2, 5), "\n";
```

```behavior
parses: yes
```

```output
3
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: main::count, package: main, param_names: [], want: list}, [2, 3, 4, 3, 5], 0, Int, 6, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7]]} # 11
main::count: {start: 0, returns: [30], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 33], ~, Int], # 3
  [Proj, {index: 1}, [2]], # 4
  [PadAccess, {sigil: "%", symbol: seen}, ~, ~, Hash], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [Phi, {region: 2}, [1, 34], ~, Int], # 7
  [MemStart], # 8
  [Phi, {memory: true, region: 2}, [8, 28], ~, Unknown], # 9
  [Subscript, {kind: array}, [6, 7], ~, Scalar, 9], # 10
  [Subscript, {kind: hash}, [5, 10], ~, Scalar], # 11
  [Proj, {index: 0}, [2]], # 12
  [Coerce, {from_repr: Scalar, to_repr: Num}, [10], ~, Num], # 13
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 14
  [NumGt, ~, [13, 14], ~, Boolean], # 15
  [If, ~, [12, 15], 12], # 16
  [Proj, {index: 0}, [16]], # 17
  [Subscript, {kind: hash}, [5, 10], 17, Scalar, 9], # 18
  [Increment, ~, [18], ~, Scalar], # 19
  [Assign, ~, [11, 19], 18, Scalar, 9, true], # 20
  [Proj, {index: 1}, [16]], # 21
  [Region, {head: 16}, [20, 21]], # 22
  [DefinedOr, ~, [18, 1], ~, Scalar], # 23
  [Phi, {predecessors: [17, 21], region: 22}, [23, 15], ~, Scalar], # 24
  [If, ~, [22, 24], 22], # 25
  [Proj, {index: 0}, [25]], # 26
  [Region, {head: 2}, [4, 26]], # 27
  [Phi, {memory: true, predecessors: [17, 21], region: 22}, [20, 9], ~, Unknown], # 28
  [Phi, {memory: true, region: 27}, [9, 28], ~, Unknown], # 29
  [Return, ~, [3], 27, ~, 29], # 30
  [Count, ~, [6], ~, Int, 9], # 31
  [NumGt, ~, [31, 7], 2, Boolean], # 32
  [Add, ~, [3, 14], ~, Int], # 33
  [Add, ~, [7, 14], ~, Int], # 34
  [Proj, {index: 1}, [25]], # 35
  [Count, ~, [6], ~, Int, 8]]} # 36
```

## A defined-or that nexts, after a next unless

Reduced from TypeInference::_count_unknown. The rest of the body after the first guard holds a second one, whose fallback goes to the next iteration.

```perl
sub unknowns {
    my $n = 0;
    for my $x (@_) {
        next unless defined $x && length $x;
        my $r = $x // next;
        $n++ if $r eq "U";
    }
    return $n;
}
print unknowns("U", undef, "V", "", "U"), "\n";
```

```behavior
parses: yes
```

```output
2
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: U}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: V}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: main::unknowns, package: main, param_names: [], want: list}, [2, 1, 3, 4, 2], 0, Int, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
main::unknowns: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 34], ~, Int], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [MemStart], # 6
  [Return, ~, [3], 5, ~, 6], # 7
  [ArgsSource, ~, ~, ~, Array], # 8
  [Count, ~, [8], ~, Int, 6], # 9
  [Phi, {region: 2}, [1, 35], ~, Int], # 10
  [NumGt, ~, [9, 10], 2, Boolean], # 11
  [Proj, {index: 0}, [2]], # 12
  [Subscript, {kind: array}, [8, 10], ~, Scalar, 6], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: U}, ~, ~, Str], # 15
  [StrEq, ~, [14, 15], ~, Boolean], # 16
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 17
  [Add, ~, [3, 17], ~, Int], # 18
  [TernaryExpr, ~, [16, 18, 3], ~, Int], # 19
  [Defined, ~, [13], ~, Boolean], # 20
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 21
  [Length, ~, [21], ~, Int], # 22
  [And, ~, [20, 22], ~, Scalar], # 23
  [If, ~, [12, 23], 12], # 24
  [Proj, {index: 1}, [24]], # 25
  [Proj, {index: 0}, [24]], # 26
  [Not, ~, [20], ~, Boolean], # 27
  [If, ~, [26, 27], 26], # 28
  [Proj, {index: 1}, [28]], # 29
  [Region, {head: 24}, [25, 29]], # 30
  [Phi, {predecessors: [25, 26], region: 30}, [3, 19], ~, Int], # 31
  [Proj, {index: 0}, [28]], # 32
  [Region, {head: 2}, [30, 32]], # 33
  [Phi, {predecessors: [12, 32], region: 33}, [31, 3], ~, Int], # 34
  [Add, ~, [10, 17], ~, Int]]} # 35
```

## An or-last whose value is kept

In value context the guard yields its left side on the path that goes on.

```perl
sub upto_false {
    my $s = "";
    for my $x (@_) {
        my $r = $x || last;
        $s .= $r;
    }
    return $s;
}
print upto_false("a", "b", 0, "c"), "\n";
```

```behavior
parses: yes
```

```output
ab
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 5
  [MemStart], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::upto_false, package: main, param_names: [], want: list}, [2, 3, 4, 5], 0, Str, 6, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7]]} # 11
main::upto_false: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 18], ~, Str], # 3
  [Proj, {index: 1}, [2]], # 4
  [Proj, {index: 0}, [2]], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Phi, {region: 2}, [7, 20], ~, Int], # 8
  [MemStart], # 9
  [Subscript, {kind: array}, [6, 8], ~, Scalar, 9], # 10
  [If, ~, [5, 10], 5], # 11
  [Proj, {index: 1}, [11]], # 12
  [Region, {head: 2}, [4, 12]], # 13
  [Return, ~, [3], 13, ~, 9], # 14
  [Count, ~, [6], ~, Int, 9], # 15
  [NumGt, ~, [15, 8], 2, Boolean], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 17
  [Concat, ~, [3, 17], ~, Str], # 18
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 19
  [Add, ~, [8, 19], ~, Int], # 20
  [Proj, {index: 0}, [11]]]} # 21
```

## An if that moves the counter and nexts in a C-style for

Reduced from EmitHelpers::_emit_hash_ref_expr. The step is the loop's continue block, and the if is the first statement of the body, not its condition.

```perl
sub pairs {
    my @p = @_;
    my @o;
    for (my $i = 0; $i < @p; $i += 2) {
        my $k = $p[$i];
        if (defined $k && $k =~ /^%(\w+)$/) {
            push @o, "spread $1";
            $i--;
            next;
        }
        push @o, "$k=$p[$i + 1]";
    }
    return join ", ", @o;
}
print pairs("a", 1, "%x", "b", 2), "\n";
```

```behavior
parses: yes
```

```output
a=1, spread x, b=2
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: string, value: "%x"}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [MemStart], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 15, name: main::pairs, package: main, param_names: [], want: list}, [2, 3, 4, 5, 6], 0, Str, 7, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
main::pairs: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ", "}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: o}, ~, ~, Array], # 2
  [MemStart], # 3
  [Loop, {bound: each}, [0], 0], # 4
  [Phi, {memory: true, region: 4}, [3, 39], ~, Unknown], # 5
  [Proj, {index: 1}, [4]], # 6
  [Region, {head: 4}, [6]], # 7
  [Phi, {memory: true, region: 7}, [5], ~, Unknown], # 8
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 2], ~, Str, 8], # 9
  [Return, ~, [9], 7, ~, 8], # 10
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 11
  [Phi, {region: 4}, [11, 43], ~, Int], # 12
  [ArgsSource, ~, ~, ~, Array], # 13
  [Count, ~, [13], ~, Int, 5], # 14
  [NumLt, ~, [12, 14], 4, Boolean], # 15
  [Proj, {index: 0}, [4]], # 16
  [Subscript, {kind: array}, [13, 12], ~, Scalar, 5], # 17
  [Defined, ~, [17], ~, Boolean], # 18
  [Coerce, {from_repr: Scalar, to_repr: Str}, [17], ~, Str], # 19
  [RegexMatch, {flags: "", pattern: "^%(\\w+)$"}, [19], ~, Boolean], # 20
  [And, ~, [18, 20], ~, Boolean], # 21
  [If, ~, [16, 21], 16], # 22
  [Constant, {const_type: string, value: "spread "}, ~, ~, Str], # 23
  [RegexCapture, {"n": 1}, [20], ~, Str], # 24
  [Concat, ~, [23, 24], ~, Str], # 25
  [Proj, {index: 0}, [22]], # 26
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 25], 26, Int, 5, true], # 27
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 28
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 29
  [Concat, ~, [28, 29], ~, Str], # 30
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 31
  [Add, ~, [12, 31], ~, Int], # 32
  [Subscript, {kind: array}, [13, 32], ~, Scalar, 5], # 33
  [Coerce, {from_repr: Unknown, to_repr: Str}, [33], ~, Str], # 34
  [Concat, ~, [30, 34], ~, Str], # 35
  [Proj, {index: 1}, [22]], # 36
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 35], 36, Int, 5, true], # 37
  [Region, {head: 4}, [37, 27]], # 38
  [Phi, {memory: true, predecessors: [36, 26], region: 38}, [37, 27], ~, Int], # 39
  [Subtract, ~, [12, 31], ~, Int], # 40
  [Phi, {predecessors: [36, 26], region: 38}, [12, 40], ~, Int], # 41
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 42
  [Add, ~, [41, 42], ~, Int]]} # 43
```

## An exists guard on a hash reached through a reference

Reduced from Desugar::_create_helpers. The container is a scalar holding a reference, so only the op says it is a hash element and not an array element.

```perl
sub helpers {
    my ($h, $q) = @_;
    if ($q eq "+") {
        if (!exists $h->{plus}) { $h->{plus} = 1 }
        $h->{seen} = 2;
    }
    return 1;
}
my %h;
helpers(\%h, "+");
print join(",", sort keys %h), "\n";
```

```behavior
parses: yes
```

```output
plus,seen
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [PadAccess, {sigil: "%", symbol: h}, ~, ~, Hash], # 3
  [Ref, ~, [3], ~, HashRef], # 4
  [Constant, {const_type: string, value: "+"}, ~, ~, Str], # 5
  [MemStart], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: main::helpers, package: main, param_names: [], want: void}, [4, 5], 0, Int, 6, true], # 7
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [3], ~, List, 7], # 8
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [8], ~, List, 7], # 9
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 9], ~, Str, 7], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [10, 11], 7, "Maybe[Boolean]"], # 12
  [Return, {implicit: true}, [1], 12, ~, 7]]} # 13
main::helpers: {start: 0, returns: [26], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [PadAccess, {sigil: $, symbol: q}, ~, ~, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "+"}, ~, ~, Str], # 4
  [StrEq, ~, [3, 4], ~, Boolean], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 1}, [6]], # 7
  [PadAccess, {sigil: $, symbol: h}, ~, ~, Unknown], # 8
  [Constant, {const_type: string, value: seen}, ~, ~, Str], # 9
  [Subscript, {kind: hash}, [8, 9], ~, Scalar], # 10
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 11
  [Constant, {const_type: string, value: plus}, ~, ~, Str], # 12
  [Proj, {index: 0}, [6]], # 13
  [MemStart], # 14
  [Exists, {kind: hash}, [8, 12], 13, Boolean, 14, true], # 15
  [If, ~, [15, 15], 15], # 16
  [Proj, {index: 0}, [16]], # 17
  [Subscript, {kind: hash}, [8, 12], ~, Scalar], # 18
  [Proj, {index: 1}, [16]], # 19
  [Assign, ~, [18, 1], 19, Int, 15, true], # 20
  [Region, {head: 16}, [17, 20]], # 21
  [Phi, {memory: true, predecessors: [17, 19], region: 21}, [15, 20], ~, Scalar], # 22
  [Assign, ~, [10, 11], 21, Int, 22, true], # 23
  [Region, {head: 6}, [7, 23]], # 24
  [Phi, {memory: true, predecessors: [7, 13], region: 24}, [14, 23], ~, Unknown], # 25
  [Return, ~, [1], 24, ~, 25], # 26
  [ArgsSource, ~, ~, ~, Array], # 27
  [Assign, {record: true, targets: 2}, [8, 2, 27], ~, List]]} # 28
```

## Logical assigns into elements

A `//=`, `||=` or `&&=` into a hash or array element stores only when the test says so, and an array grows to the element it vivifies.

```perl
my %h; $h{a} //= 3; $h{b} ||= 4; $h{b} &&= 5; my @a; $a[1] //= 7; print join(",", map {"$_=$h{$_}"} sort keys %h), " ", scalar(@a), " $a[1]\n";
```

```behavior
parses: yes
```

```output
a=3,b=5 2 7
```

```ir
main::__PROGRAM__: {start: 0, returns: [77], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [PadAccess, {sigil: "@", symbol: a}, ~, ~, Array], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [PadAccess, {sigil: "%", symbol: h}, ~, ~, Hash], # 6
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 8
  [MemStart], # 9
  [Subscript, {kind: hash}, [6, 8], 0, Scalar, 9], # 10
  [Defined, ~, [10], ~, Boolean], # 11
  [If, ~, [10, 11], 10], # 12
  [Proj, {index: 0}, [12]], # 13
  [Subscript, {kind: hash}, [6, 8], ~, Scalar], # 14
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 15
  [Proj, {index: 1}, [12]], # 16
  [Assign, ~, [14, 1], 16, Undef, 9, true], # 17
  [Assign, ~, [14, 15], 17, Int, 17, true], # 18
  [Region, {head: 12}, [13, 18]], # 19
  [Phi, {memory: true, predecessors: [13, 16], region: 19}, [9, 18], ~, Unknown], # 20
  [Subscript, {kind: hash}, [6, 7], 19, Scalar, 20], # 21
  [Defined, ~, [21], ~, Boolean], # 22
  [If, ~, [21, 22], 21], # 23
  [Proj, {index: 0}, [23]], # 24
  [Subscript, {kind: hash}, [6, 7], ~, Scalar], # 25
  [Proj, {index: 1}, [23]], # 26
  [Assign, ~, [25, 1], 26, Undef, 20, true], # 27
  [Region, {head: 23}, [24, 27]], # 28
  [If, ~, [28, 21], 28], # 29
  [Proj, {index: 0}, [29]], # 30
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 31
  [Proj, {index: 1}, [29]], # 32
  [Phi, {memory: true, predecessors: [24, 26], region: 28}, [20, 27], ~, Unknown], # 33
  [Assign, ~, [25, 31], 32, Int, 33, true], # 34
  [Region, {head: 29}, [30, 34]], # 35
  [Phi, {memory: true, predecessors: [30, 32], region: 35}, [33, 34], ~, Unknown], # 36
  [Subscript, {kind: hash}, [6, 7], 35, Scalar, 36], # 37
  [Defined, ~, [37], ~, Boolean], # 38
  [If, ~, [37, 38], 37], # 39
  [Proj, {index: 0}, [39]], # 40
  [Proj, {index: 1}, [39]], # 41
  [Assign, ~, [25, 1], 41, Undef, 36, true], # 42
  [Region, {head: 39}, [40, 42]], # 43
  [If, ~, [43, 37], 43], # 44
  [Proj, {index: 1}, [44]], # 45
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 46
  [Proj, {index: 0}, [44]], # 47
  [Phi, {memory: true, predecessors: [40, 41], region: 43}, [36, 42], ~, Unknown], # 48
  [Assign, ~, [25, 46], 47, Int, 48, true], # 49
  [Region, {head: 44}, [45, 49]], # 50
  [Phi, {memory: true, predecessors: [45, 47], region: 50}, [48, 49], ~, Unknown], # 51
  [Subscript, {kind: array}, [4, 5], 50, Scalar, 51], # 52
  [Defined, ~, [52], ~, Boolean], # 53
  [If, ~, [52, 53], 52], # 54
  [Proj, {index: 0}, [54]], # 55
  [Subscript, {kind: array}, [4, 5], ~, Scalar], # 56
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 57
  [Proj, {index: 1}, [54]], # 58
  [Assign, ~, [56, 1], 58, Undef, 51, true], # 59
  [Assign, ~, [56, 57], 59, Int, 59, true], # 60
  [Region, {head: 54}, [55, 60]], # 61
  [Loop, {bound: entry}, [61], 61], # 62
  [Phi, {region: 62}, [3, 91], ~, Array], # 63
  [Phi, {memory: true, predecessors: [55, 58], region: 61}, [51, 60], ~, Unknown], # 64
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 63], ~, Str, 64], # 65
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 66
  [Count, ~, [4], ~, Int, 64], # 67
  [Coerce, {from_repr: Int, to_repr: Str}, [67], ~, Str], # 68
  [Subscript, {kind: array}, [4, 5], ~, Scalar, 64], # 69
  [Coerce, {from_repr: Unknown, to_repr: Str}, [69], ~, Str], # 70
  [Concat, ~, [66, 70], ~, Str], # 71
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 72
  [Concat, ~, [71, 72], ~, Str], # 73
  [Proj, {index: 1}, [62]], # 74
  [Region, {head: 62}, [74]], # 75
  [Print, ~, [65, 66, 68, 73], 75, "Maybe[Boolean]"], # 76
  [Return, {implicit: true}, [1], 76, ~, 64], # 77
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [6], ~, List, 64], # 78
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [78], ~, List, 64], # 79
  [Count, ~, [79], ~, Int, 64], # 80
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 81
  [Phi, {region: 62}, [81, 92], ~, Int], # 82
  [Subscript, {kind: array}, [79, 82], ~, Scalar, 64], # 83
  [Subscript, {kind: hash}, [6, 83], ~, Scalar, 64], # 84
  [NumGt, ~, [80, 82], 62, Boolean], # 85
  [Coerce, {from_repr: Unknown, to_repr: Str}, [83], ~, Str], # 86
  [Coerce, {from_repr: Unknown, to_repr: Str}, [84], ~, Str], # 87
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 88
  [Concat, ~, [86, 88], ~, Str], # 89
  [Concat, ~, [89, 87], ~, Str], # 90
  [ListAppend, {collector: map}, [63, 90], ~, Array], # 91
  [Add, ~, [82, 5], ~, Int], # 92
  [Proj, {index: 0}, [62]]]} # 93
```

## A return under a modifier in an if arm in a loop

The return leaves the sub from inside the loop; when it does not fire the loop runs out.

```perl
sub f { for my $i (1..3) { if ($i > 1) { return "E$i" if $i == $_[0] } } "L" } print f(2), f(9), "\n";
```

```behavior
parses: yes
```

```output
E2L
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f, package: main, param_names: [], want: list}, [2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f, package: main, param_names: [], want: list}, [6], 4, Str, 4, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [5, 8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7]]} # 11
main::f: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: E}, ~, ~, Str], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 27], ~, Int], # 4
  [Coerce, {from_repr: Int, to_repr: Str}, [4], ~, Str], # 5
  [Concat, ~, [1, 5], ~, Str], # 6
  [Constant, {const_type: string, value: L}, ~, ~, Str], # 7
  [Proj, {index: 0}, [3]], # 8
  [NumGt, ~, [4, 2], ~, Boolean], # 9
  [If, ~, [8, 9], 8], # 10
  [Proj, {index: 0}, [10]], # 11
  [ArgsSource, ~, ~, ~, Array], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [MemStart], # 14
  [Subscript, {kind: array}, [12, 13], ~, Scalar, 14], # 15
  [Coerce, {from_repr: Scalar, to_repr: Num}, [15], ~, Num], # 16
  [NumEq, ~, [4, 16], ~, Boolean], # 17
  [If, ~, [11, 17], 11], # 18
  [Proj, {index: 0}, [18]], # 19
  [Proj, {index: 1}, [3]], # 20
  [Region, {head: 3}, [20]], # 21
  [Region, ~, [19, 21]], # 22
  [Phi, {predecessors: [19, 21], region: 22}, [6, 7], ~, Str], # 23
  [Return, ~, [23], 22, ~, 14], # 24
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 25
  [NumGt, ~, [25, 4], 3, Boolean], # 26
  [Add, ~, [4, 2], ~, Int], # 27
  [Proj, {index: 1}, [10]], # 28
  [Proj, {index: 1}, [18]], # 29
  [Region, {head: 10}, [29, 28]]]} # 30
```

## A ternary with multi-element list arms

Each arm is its whole list: the array takes three values or none, and stays an array a push can grow.

```perl
my $c = 1; my @a = $c ? (1, 2, 3) : (); push @a, 4; my @b = $c ? () : (5, 6); print "@a|", scalar(@b), "\n";
```

```behavior
parses: yes
```

```output
1 2 3 4|0
```

```ir
main::__PROGRAM__: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [ArrayLiteral, ~, [2, 3, 4], ~, Array], # 5
  [ArrayLiteral, ~, ~, ~, Array], # 6
  [TernaryExpr, ~, [2, 5, 6], ~, Array], # 7
  [ArrayLiteral, {sigil: "@", symbol: a}, [7], ~, Array], # 8
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 9
  [MemStart], # 10
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [8, 9], 0, Int, 10, true], # 11
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 11], # 12
  [Coerce, {from_repr: Scalar, to_repr: Str}, [12], ~, Str], # 13
  [PostfixDeref, {sigil: "@"}, [8], ~, Array, 11], # 14
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [13, 14], ~, Str, 11], # 15
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [ArrayLiteral, ~, ~, ~, Array], # 18
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 19
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 20
  [ArrayLiteral, ~, [19, 20], ~, Array], # 21
  [TernaryExpr, ~, [2, 18, 21], ~, Array], # 22
  [Count, ~, [22], ~, Int, 11], # 23
  [Coerce, {from_repr: Int, to_repr: Str}, [23], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [Print, ~, [17, 24, 25], 11, "Maybe[Boolean]"], # 26
  [Return, {implicit: true}, [1], 26, ~, 11]]} # 27
```

## A signature default with an effect

The default runs only when the argument is absent, so the counter moves once.

```perl
use v5.36; our $c = 0; sub g { $c++; 5 } sub f ($x = g()) { $x + 1 } print f(), f(1), " c=$c\n";
```

```behavior
parses: yes
```

```output
62 c=1
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: $, symbol: c}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [EntryWrite, ~, [2, 3], 0, Unknown, 4, true], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f, package: main, param_names: [], want: list}, ~, 5, Unknown, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f, package: main, param_names: [], want: list}, [8], 6, Unknown, 6, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " c="}, ~, ~, Str], # 11
  [EntryDef, {package: main, sigil: $, symbol: c}, ~, ~, Int, 9], # 12
  [Coerce, {from_repr: Int, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [11, 13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [Print, ~, [7, 10, 16], 9, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [1], 17, ~, 9]]} # 18
main::f: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Unknown], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Count, {presence_test: true}, [2], ~, Int, 3], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [NumGt, ~, [4, 5], ~, Boolean], # 6
  [If, ~, [0, 6], 0], # 7
  [Proj, {index: 1}, [7]], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::g, package: main, param_names: [], want: scalar}, ~, 8, Int, 3, true], # 9
  [Proj, {index: 0}, [7]], # 10
  [Region, {head: 7}, [10, 9]], # 11
  [Phi, {predecessors: [10, 8], region: 11}, [1, 9], ~, Unknown], # 12
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 13
  [Add, ~, [12, 13], ~, Unknown], # 14
  [Phi, {memory: true, predecessors: [10, 8], region: 11}, [3, 9], ~, Unknown], # 15
  [Return, {implicit: true}, [14], 11, ~, 15]]} # 16
main::g: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [EntryDef, {package: main, sigil: $, symbol: c}, ~, ~, Scalar], # 2
  [MemStart], # 3
  [EntryDef, {package: main, sigil: $, symbol: c}, ~, ~, Scalar, 3], # 4
  [Increment, ~, [4], ~, Scalar], # 5
  [EntryWrite, ~, [2, 5], 0, Unknown, 3, true], # 6
  [Return, {implicit: true}, [1], 6, ~, 6]]} # 7
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## Lexical subs, one calling another

A `my sub` is called by its body; one lexical sub calls another, and a reference to one calls it too.

```perl
use v5.36; my sub a ($x) { $x + 1 } my sub b ($x) { a($x) * 2 } my $r = \&b; print b(1), " ", $r->(2), "\n";
```

```behavior
parses: yes
```

```output
4 6
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::__PROGRAM__::__ANON__:1:2, package: main, param_names: [], want: list}, [2], 0, Num, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::__PROGRAM__::__ANON__:1:2, package: main, param_names: [], want: list}, [7], 4, Num, 4, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [5, 6, 9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
main::__PROGRAM__::__ANON__:1:2: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 1], # 2
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Unknown], # 3
  [Assign, ~, [2, 3], 0, Unknown, 1, true], # 4
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 4], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::b::__ANON__:1:2, package: main, param_names: [], want: scalar}, [5], 4, Num, 4, true], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Multiply, ~, [6, 7], ~, Num], # 8
  [Return, {implicit: true}, [8], 6, ~, 6]]} # 9
main::b::__ANON__:1:2: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Num], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Add, ~, [1, 2], ~, Num], # 3
  [MemStart], # 4
  [Return, {implicit: true}, [3], 0, ~, 4]]} # 5
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## The count of a list call

The countof idiom counts what the call returns, at run time.

```perl
sub f { (1,2,3) } sub g { () } my $c = () = f(); my $d = () = g(); print "$c $d\n";
```

```behavior
parses: yes
```

```output
3 0
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f, package: main, param_names: [], want: list}, ~, 0, List, 2, true], # 3
  [ArrayLiteral, ~, [3], ~, Array], # 4
  [Count, ~, [4], ~, Int, 3], # 5
  [Coerce, {from_repr: Int, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::g, package: main, param_names: [], want: list}, ~, 3, Undef, 3, true], # 9
  [ArrayLiteral, ~, [9], ~, Array], # 10
  [Count, ~, [10], ~, Int, 9], # 11
  [Coerce, {from_repr: Int, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [8, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Print, ~, [15], 9, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 9]]} # 17
main::f: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, List], # 4
  [Coerce, {from_repr: List, to_repr: Scalar}, [3], ~, Scalar], # 5
  [MemStart], # 6
  [Return, {implicit: true}, [4, 5], 0, ~, 6]]} # 7
main::g: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Return, {implicit: true, valueless: true}, [1], 0, ~, 2]]} # 3
```

## An in-place reverse

perl compiles `@b = reverse @b` to a reverse with no list assign; the array still holds the reversed list.

```perl
my @b = (1, 2, 3); @b = reverse @b; print "@b\n";
```

```behavior
parses: yes
```

```output
3 2 1
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 2], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [ArrayLiteral, {sigil: "@", symbol: b}, [5, 6, 7], ~, Array], # 8
  [Call, {dispatch_kind: builtin, name: reverse, param_names: []}, [8], ~, List, 2], # 9
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 9], ~, Str, 2], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Print, ~, [12], 0, "Maybe[Boolean]"], # 13
  [Return, {implicit: true}, [1], 13, ~, 2], # 14
  [ArrayLiteral, {sigil: "@", symbol: b}, [9], ~, Array]]} # 15
```

## A loop Phi stamp decided by the scout

An undef init overwritten by each list element: the Phi's stamp is decided before the body walk, not unstamped after it.

```perl
sub f { my $s; for my $x (@_) { $s = $x } return $s } print f(3, 4, 5), "\n";
```

```behavior
parses: yes
```

```output
5
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f, package: main, param_names: [], want: list}, [2, 3, 4], 0, Scalar, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
main::f: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 14], ~, Scalar], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [MemStart], # 6
  [Return, ~, [3], 5, ~, 6], # 7
  [ArgsSource, ~, ~, ~, Array], # 8
  [Count, ~, [8], ~, Int, 6], # 9
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 10
  [Phi, {region: 2}, [10, 16], ~, Int], # 11
  [NumGt, ~, [9, 11], 2, Boolean], # 12
  [Proj, {index: 0}, [2]], # 13
  [Subscript, {kind: array}, [8, 11], ~, Scalar, 6], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Add, ~, [11, 15], ~, Int]]} # 16
```

## A foreach over a bare array with a hash store

A bare-declared array filled by push, iterated while the body stores a hash element read after the loop.

```perl
sub f { my %h = (a => 1); my @a; push @a, 1, 2; my $s = ""; for my $x (@a) { $h{a} = 9; $s .= $x } print "$s|$h{a}\n" } f();
```

```behavior
parses: yes
```

```output
12|9
```

```ir
main::__PROGRAM__: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f, package: main, param_names: [], want: void}, ~, 0, "Maybe[Boolean]", 2, true], # 3
  [Return, {implicit: true}, [1], 3, ~, 3]]} # 4
main::f: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: a}, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 3, 4], 0, Int, 5, true], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [1, 36], ~, Str], # 8
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 11
  [HashLiteral, {sigil: "%", symbol: h}, [11, 3], ~, Hash], # 12
  [Phi, {memory: true, region: 7}, [6, 34], ~, Int], # 13
  [Proj, {index: 1}, [7]], # 14
  [Region, {head: 7}, [14]], # 15
  [Phi, {memory: true, region: 15}, [13], ~, Int], # 16
  [Subscript, {kind: hash}, [12, 11], ~, Scalar, 16], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Concat, ~, [10, 18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [Print, ~, [21], 15, "Maybe[Boolean]"], # 22
  [Return, {implicit: true}, [22], 22, ~, 16], # 23
  [Count, ~, [2], ~, Int, 6], # 24
  [Count, ~, [2], ~, Int, 13], # 25
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 26
  [Phi, {region: 7}, [26, 29], ~, Int], # 27
  [Subscript, {kind: array}, [2, 27], ~, Scalar, 13], # 28
  [Add, ~, [27, 3], ~, Int], # 29
  [NumGt, ~, [25, 27], 7, Boolean], # 30
  [Proj, {index: 0}, [7]], # 31
  [Subscript, {kind: hash}, [12, 11], ~, Int], # 32
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 33
  [Assign, ~, [32, 33], 31, Int, 13, true], # 34
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 35
  [Concat, ~, [8, 35], ~, Str]]} # 36
```

## A file lexical read in scalar context from a lexical sub

A file-scope my sub sharing a file array by name; scalar @arr is its count, not its elements.

```perl
use v5.36; my @arr = (1, 2); my sub t { scalar @arr } print t(), "\n";
```

```behavior
parses: yes
```

```output
2
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: arr}, ~, ~, Array, 2], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [ArrayLiteral, {sigil: "@", symbol: arr}, [4, 5], 0, Array], # 6
  [Assign, ~, [3, 6], 6, List, 2, true], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::__PROGRAM__::__ANON__:1:3, package: main, param_names: [], want: list}, ~, 7, Int, 7, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
main::__PROGRAM__::__ANON__:1:3: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: arr}, ~, ~, Array], # 1
  [MemStart], # 2
  [Count, ~, [1], ~, Int, 2], # 3
  [Return, {implicit: true}, [3], 0, ~, 2]]} # 4
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## A while inside an if arm of a loop body

A nested while in a guarded arm is walked by the arm walk, so the rest of the arm is kept.

```perl
my $s = 0; my $o = ""; for my $i (1..4) { if ($i > 1) { my $k = 0; while ($k < $i) { $s += $k; $k++ } $o .= $s } } print "$o $s\n";
```

```behavior
parses: yes
```

```output
1410 10
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 41], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Phi, {region: 3}, [7, 38], ~, Int], # 8
  [Coerce, {from_repr: Int, to_repr: Str}, [8], ~, Str], # 9
  [Concat, ~, [6, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Proj, {index: 1}, [3]], # 13
  [Region, {head: 3}, [13]], # 14
  [Print, ~, [12], 14, "Maybe[Boolean]"], # 15
  [MemStart], # 16
  [Return, {implicit: true}, [1], 15, ~, 16], # 17
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 18
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 19
  [Phi, {region: 3}, [19, 25], ~, Int], # 20
  [NumGt, ~, [18, 20], 3, Boolean], # 21
  [Proj, {index: 0}, [3]], # 22
  [NumGt, ~, [20, 19], ~, Boolean], # 23
  [If, ~, [22, 23], 22], # 24
  [Add, ~, [20, 19], ~, Int], # 25
  [Proj, {index: 0}, [24]], # 26
  [Loop, {bound: each}, [26], 26], # 27
  [Phi, {region: 27}, [7, 31], ~, Int], # 28
  [NumLt, ~, [28, 20], 27, Boolean], # 29
  [Proj, {index: 1}, [24]], # 30
  [Add, ~, [28, 19], ~, Int], # 31
  [Proj, {index: 1}, [27]], # 32
  [Region, {head: 27}, [32]], # 33
  [Region, {head: 24}, [33, 30]], # 34
  [Phi, {region: 27}, [8, 36], ~, Int], # 35
  [Add, ~, [35, 28], ~, Int], # 36
  [Proj, {index: 0}, [27]], # 37
  [Phi, {predecessors: [26, 30], region: 34}, [35, 8], ~, Int], # 38
  [Coerce, {from_repr: Int, to_repr: Str}, [35], ~, Str], # 39
  [Concat, ~, [4, 39], ~, Str], # 40
  [Phi, {predecessors: [26, 30], region: 34}, [40, 4], ~, Str]]} # 41
```

## A bare block after a next if

The rest of a loop body after a next if reaches the latch through a bare block.

```perl
my @r; for my $i (1..4) { next if $i % 2; { push @r, $i * 3 } push @r, "x" } print "@r\n";
```

```behavior
parses: yes
```

```output
6 x 12 x
```

```ir
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {memory: true, region: 3}, [2, 32], ~, Unknown], # 4
  [Proj, {index: 1}, [3]], # 5
  [Region, {head: 3}, [5]], # 6
  [Phi, {memory: true, region: 6}, [4], ~, Unknown], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 7], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [PadAccess, {sigil: "@", symbol: r}, ~, ~, Array], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [9, 10], ~, Str, 7], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Print, ~, [13], 6, "Maybe[Boolean]"], # 14
  [Return, {implicit: true}, [1], 14, ~, 7], # 15
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 16
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 17
  [Phi, {region: 3}, [17, 33], ~, Int], # 18
  [NumGt, ~, [16, 18], 3, Boolean], # 19
  [Proj, {index: 0}, [3]], # 20
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 21
  [Modulo, ~, [18, 21], ~, Int], # 22
  [If, ~, [20, 22], 20], # 23
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 24
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 25
  [Multiply, ~, [18, 25], ~, Int], # 26
  [Proj, {index: 1}, [23]], # 27
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [10, 26], 27, Int, 4, true], # 28
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [10, 24], 28, Int, 28, true], # 29
  [Proj, {index: 0}, [23]], # 30
  [Region, {head: 23}, [30, 29]], # 31
  [Phi, {memory: true, predecessors: [30, 27], region: 31}, [4, 29], ~, Unknown], # 32
  [Add, ~, [18, 17], ~, Int]]} # 33
```

## A /ge replacement run once per match

The replacement of s///ge is a body run for each match, seeing that match's capture.

```perl
my $s = "a1b2c"; $s =~ s/(\d)/$1*10/ge; print "$s\n";
```

```behavior
parses: yes
```

```output
a10b20c
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 2], # 3
  [Constant, {const_type: string, value: a1b2c}, ~, ~, Str], # 4
  [Assign, ~, [3, 4], 0, Str, 2, true], # 5
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 5], # 6
  [RegexSubst, {flags: g, pattern: "(\\d)", replacement: "", replacement_body: main::__PROGRAM__::__SUBSTREPL__:1}, [6], 5, Str, 5, true], # 7
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Str, 7], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Print, ~, [11], 7, "Maybe[Boolean]"], # 12
  [Return, {implicit: true}, [1], 12, ~, 7]]} # 13
main::__PROGRAM__::__SUBSTREPL__:1: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [RegexMatch, {flags: g, pattern: "(\\d)"}, ~, ~, Boolean], # 1
  [RegexCapture, {"n": 1}, [1], ~, Str], # 2
  [Coerce, {from_repr: Str, to_repr: Num}, [2], ~, Num], # 3
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 4
  [Multiply, ~, [3, 4], ~, Num], # 5
  [MemStart], # 6
  [Return, {implicit: true}, [5], 0, ~, 6]]} # 7
```

## A lexical sub callee mapped over @_

A loop over @_ passing the alias to a my sub that only reads it translates; the callee is judged by its body.

```perl
use v5.36; my sub c ($s) { $s =~ s/1/9/; "[$s]" } sub e { join ",", map { c($_) } @_ } my @a = ("a1", "b1"); print e(@a), " @a\n";
```

```behavior
parses: yes
```

```output
[a9],[b9] a1 b1
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a1}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b1}, ~, ~, Str], # 3
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3], ~, Array], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::e, package: main, param_names: [], want: list}, [4], 0, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 8
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 6], # 9
  [Coerce, {from_repr: Scalar, to_repr: Str}, [9], ~, Str], # 10
  [PostfixDeref, {sigil: "@"}, [4], ~, Array, 6], # 11
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [10, 11], ~, Str, 6], # 12
  [Concat, ~, [8, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Print, ~, [7, 15], 6, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 6]]} # 17
main::e: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 23], ~, Array], # 4
  [MemStart], # 5
  [Phi, {memory: true, region: 3}, [5, 22], ~, Unknown], # 6
  [Proj, {index: 1}, [3]], # 7
  [Region, {head: 3}, [7]], # 8
  [Phi, {memory: true, region: 8}, [6], ~, Unknown], # 9
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 4], ~, Str, 9], # 10
  [Return, {implicit: true}, [10], 8, ~, 9], # 11
  [ArgsSource, ~, ~, ~, Array], # 12
  [Count, ~, [12], ~, Int, 6], # 13
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 14
  [Phi, {region: 3}, [14, 25], ~, Int], # 15
  [NumGt, ~, [13, 15], 3, Boolean], # 16
  [Proj, {index: 0}, [3]], # 17
  [Subscript, {kind: array}, [12, 15], ~, Scalar], # 18
  [Ref, ~, [18], ~, ScalarRef], # 19
  [LocalAlias, {name: _}, [19], 17, Unknown, 6], # 20
  [Subscript, {kind: array}, [12, 15], ~, Scalar, 6], # 21
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::e::__ANON__:1:1, package: main, param_names: [], want: list}, [21], 20, Str, 6, true], # 22
  [ListAppend, {collector: map}, [4, 22], ~, Array], # 23
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 24
  [Add, ~, [15, 24], ~, Int], # 25
  [Count, ~, [12], ~, Int, 5]]} # 26
main::e::__ANON__:1:1: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 2], # 3
  [Parameter, {index: 0, name: $s, sigil: $}, ~, ~, Unknown], # 4
  [Assign, ~, [3, 4], 0, Unknown, 2, true], # 5
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 5], # 6
  [RegexSubst, {flags: u, pattern: "1", replacement: "9"}, [6], 5, Str, 5, true], # 7
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Str, 7], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Concat, ~, [1, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Return, {implicit: true}, [12], 7, ~, 7]]} # 13
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## A while inside a block eval

A while loop in an eval body is walked like any loop; the eval's value is the block's last statement.

```perl
sub f { my $r = eval { my $i = 0; while ($i < 3) { $i++; print "$i\n" } 7 }; print "r=$r\n" } f();
```

```behavior
parses: yes
```

```output
1
2
3
r=7
```

```ir
main::__PROGRAM__: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f, package: main, param_names: [], want: void}, ~, 0, "Maybe[Boolean]", 2, true], # 3
  [Return, {implicit: true}, [1], 3, ~, 3]]} # 4
main::f: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "r="}, ~, ~, Str], # 1
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 2
  [MemStart], # 3
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 3], # 4
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 5
  [EntryWrite, ~, [4, 5], 0, Unknown, 3, true], # 6
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 6], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Assign, ~, [7, 8], 6, Int, 6, true], # 9
  [Loop, {bound: each}, [9], 9], # 10
  [Phi, {memory: true, region: 10}, [9, 30], ~, Scalar], # 11
  [Proj, {index: 1}, [10]], # 12
  [Region, {head: 10}, [12]], # 13
  [Phi, {memory: true, region: 13}, [11], ~, Scalar], # 14
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 14], # 15
  [EntryWrite, ~, [15, 5], 13, Unknown, 14, true], # 16
  [Region, {eval_entry: 0, eval_id: 1}, [16]], # 17
  [Phi, {region: 17}, [2], ~, "Maybe[Int]"], # 18
  [Coerce, {from_repr: "Maybe[Int]", to_repr: Str}, [18], ~, Str], # 19
  [Concat, ~, [1, 19], ~, Str], # 20
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 21
  [Concat, ~, [20, 21], ~, Str], # 22
  [Print, ~, [22], 17, "Maybe[Boolean]"], # 23
  [Return, {implicit: true}, [23], 23, ~, 16], # 24
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Num, 11], # 25
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 26
  [NumLt, ~, [25, 26], 10, Boolean], # 27
  [Proj, {index: 0}, [10]], # 28
  [Increment, ~, [25], ~, Scalar], # 29
  [Assign, ~, [25, 29], 28, Scalar, 11, true], # 30
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Str, 30], # 31
  [Coerce, {from_repr: Unknown, to_repr: Str}, [31], ~, Str], # 32
  [Concat, ~, [32, 21], ~, Str], # 33
  [Print, ~, [33], 30, "Maybe[Boolean]"]]} # 34
```

## A break in the rest after a next if

After a next if, the rest of the body holds a last if and a trailing next; the break leaves with the value the rest built.

```perl
my $s=''; for my $i (1..5) { next if $i == 1; $s .= $i; last if $i == 3; next } print "$s\n";
```

```behavior
parses: yes
```

```output
23
```

```ir
main::__PROGRAM__: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 31], ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Phi, {region: 3}, [5, 27], ~, Int], # 6
  [Coerce, {from_repr: Int, to_repr: Str}, [6], ~, Str], # 7
  [Concat, ~, [4, 7], ~, Str], # 8
  [Proj, {index: 1}, [3]], # 9
  [Proj, {index: 0}, [3]], # 10
  [NumEq, ~, [6, 5], ~, Boolean], # 11
  [If, ~, [10, 11], 10], # 12
  [Proj, {index: 1}, [12]], # 13
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 14
  [NumEq, ~, [6, 14], ~, Boolean], # 15
  [If, ~, [13, 15], 13], # 16
  [Proj, {index: 0}, [16]], # 17
  [Region, {head: 3}, [9, 17]], # 18
  [Phi, {region: 18}, [4, 8], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [Print, ~, [21], 18, "Maybe[Boolean]"], # 22
  [MemStart], # 23
  [Return, {implicit: true}, [1], 22, ~, 23], # 24
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 25
  [NumGt, ~, [25, 6], 3, Boolean], # 26
  [Add, ~, [6, 5], ~, Int], # 27
  [Proj, {index: 0}, [12]], # 28
  [Proj, {index: 1}, [16]], # 29
  [Region, {head: 3}, [28, 29]], # 30
  [Phi, {predecessors: [28, 29], region: 30}, [4, 8], ~, Str]]} # 31
```

## A labeled last in an if/else arm

last O in one arm and next in the other: the labeled last leaves the outer loop, not the inner one.

```perl
my $s=''; O: for my $i (1..3) { for my $j (1..3) { $s .= "$i$j "; if ($j == 2) { last O } else { next } } } print "$s\n";
```

```behavior
parses: yes
```

```output
11 12 
```

```ir
main::__PROGRAM__: {start: 0, returns: [29], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 7], ~, Str], # 4
  [Proj, {index: 0}, [3]], # 5
  [Loop, {bound: entry}, [5], 5], # 6
  [Phi, {region: 6}, [4, 16], ~, Str], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Phi, {region: 3}, [8, 33], ~, Int], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Concat, ~, [7, 10], ~, Str], # 11
  [Phi, {region: 6}, [8, 35], ~, Int], # 12
  [Coerce, {from_repr: Int, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [11, 13], ~, Str], # 14
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [Proj, {index: 1}, [3]], # 17
  [Proj, {index: 0}, [6]], # 18
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 19
  [NumEq, ~, [12, 19], ~, Boolean], # 20
  [If, ~, [18, 20], 18], # 21
  [Proj, {index: 0}, [21]], # 22
  [Region, {head: 3}, [17, 22]], # 23
  [Phi, {region: 23}, [4, 16], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [Concat, ~, [24, 25], ~, Str], # 26
  [Print, ~, [26], 23, "Maybe[Boolean]"], # 27
  [MemStart], # 28
  [Return, {implicit: true}, [1], 27, ~, 28], # 29
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 30
  [NumGt, ~, [30, 9], 3, Boolean], # 31
  [NumGt, ~, [30, 12], 6, Boolean], # 32
  [Add, ~, [9, 8], ~, Int], # 33
  [Proj, {index: 1}, [6]], # 34
  [Add, ~, [12, 8], ~, Int], # 35
  [Region, {head: 6}, [34]], # 36
  [Proj, {index: 1}, [21]]]} # 37
```

## Two next blocks before a fall-through

Each if block ending in next reaches the latch on its own edge; the fall-through reaches it on a third.

```perl
my $s=''; for my $i (1..6) { $s .= $i; if ($i == 2) { $s .= "a"; next } if ($i == 4) { $s .= "b"; next } $s .= "-" } print "$s\n";
```

```behavior
parses: yes
```

```output
1-2a3-4b5-6-
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 39], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Proj, {index: 1}, [3]], # 7
  [Region, {head: 3}, [7]], # 8
  [Print, ~, [6], 8, "Maybe[Boolean]"], # 9
  [MemStart], # 10
  [Return, {implicit: true}, [1], 9, ~, 10], # 11
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 12
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 13
  [Phi, {region: 3}, [13, 20], ~, Int], # 14
  [NumGt, ~, [12, 14], 3, Boolean], # 15
  [Proj, {index: 0}, [3]], # 16
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 17
  [NumEq, ~, [14, 17], ~, Boolean], # 18
  [If, ~, [16, 18], 16], # 19
  [Add, ~, [14, 13], ~, Int], # 20
  [Coerce, {from_repr: Int, to_repr: Str}, [14], ~, Str], # 21
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 22
  [NumEq, ~, [14, 22], ~, Boolean], # 23
  [Proj, {index: 0}, [19]], # 24
  [Proj, {index: 1}, [19]], # 25
  [Concat, ~, [4, 21], ~, Str], # 26
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 27
  [Concat, ~, [26, 27], ~, Str], # 28
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 29
  [Concat, ~, [26, 29], ~, Str], # 30
  [If, ~, [25, 23], 25], # 31
  [Proj, {index: 1}, [31]], # 32
  [Region, {head: 3}, [32, 24]], # 33
  [Phi, {predecessors: [32, 24], region: 33}, [28, 30], ~, Str], # 34
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 35
  [Concat, ~, [26, 35], ~, Str], # 36
  [Proj, {index: 0}, [31]], # 37
  [Region, {head: 3}, [33, 37]], # 38
  [Phi, {region: 38}, [34, 36], ~, Str]]} # 39
```

## Next blocks in a while loop carrying two values

A while loop whose next blocks carry different updates of two variables to the latch.

```perl
my ($s,$n)=('',0); my $i=0; while ($i < 6) { $i++; $n++; if ($i == 2) { $s .= "a"; next } if ($i == 4) { $n += 10; next } $s .= "-" } print "$s $n\n";
```

```behavior
parses: yes
```

```output
-a--- 16
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: each}, [0], 0], # 3
  [Phi, {region: 3}, [2, 48], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Phi, {region: 3}, [7, 42], ~, Int], # 8
  [Coerce, {from_repr: Int, to_repr: Str}, [8], ~, Str], # 9
  [Concat, ~, [6, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Proj, {index: 1}, [3]], # 13
  [Region, {head: 3}, [13]], # 14
  [Print, ~, [12], 14, "Maybe[Boolean]"], # 15
  [MemStart], # 16
  [Return, {implicit: true}, [1], 15, ~, 16], # 17
  [Phi, {region: 3}, [7, 23], ~, Int], # 18
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 19
  [NumLt, ~, [18, 19], 3, Boolean], # 20
  [Proj, {index: 0}, [3]], # 21
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 22
  [Add, ~, [18, 22], ~, Int], # 23
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 24
  [NumEq, ~, [23, 24], ~, Boolean], # 25
  [If, ~, [21, 25], 21], # 26
  [Proj, {index: 0}, [26]], # 27
  [Proj, {index: 1}, [26]], # 28
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown], # 29
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 30
  [Assign, {record: true, targets: 2}, [29, 30, 2, 7], ~, List], # 31
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 32
  [NumEq, ~, [23, 32], ~, Boolean], # 33
  [If, ~, [28, 33], 28], # 34
  [Proj, {index: 1}, [34]], # 35
  [Region, {head: 3}, [35, 27]], # 36
  [Add, ~, [8, 22], ~, Int], # 37
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 38
  [Add, ~, [37, 38], ~, Int], # 39
  [Proj, {index: 0}, [34]], # 40
  [Region, {head: 3}, [36, 40]], # 41
  [Phi, {region: 41}, [37, 39], ~, Int], # 42
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 43
  [Concat, ~, [4, 43], ~, Str], # 44
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 45
  [Concat, ~, [4, 45], ~, Str], # 46
  [Phi, {predecessors: [35, 27], region: 36}, [44, 46], ~, Str], # 47
  [Phi, {region: 41}, [47, 4], ~, Str]]} # 48
```


## A computed field default, made for each object

A `:param` field whose default is a constructor call. The default runs once for each object built without the argument, and not at all for one built with it.

```perl
use v5.42; use experimental 'class';
my $made = 0;
package Box { sub new ($c) { $made++; bless { n => $made }, $c } sub n ($s) { $s->{n} } }
class K { field $b :param :reader = Box->new; }
my $x = K->new;
my $y = K->new;
my $z = K->new(b => bless { n => 9 }, 'Box');
print $x->b->n, $y->b->n, $z->b->n, " $made\n";
```

```behavior
parses: yes
```

```output
129 2
```

```ir
Box::n: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $s, sigil: $}, ~, ~, Unknown], # 1
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 2
  [MemStart], # 3
  [Subscript, {kind: hash}, [1, 2], 0, Scalar, 3, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
Box::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: made}, ~, ~, Unknown, 2], # 3
  [Increment, ~, [3], ~, Scalar], # 4
  [Assign, ~, [3, 4], 0, Scalar, 2, true], # 5
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: made}, ~, ~, Unknown, 5], # 6
  [HashLiteral, ~, [1, 6], 5, HashRef], # 7
  [Parameter, {index: 0, name: $c, sigil: $}, ~, ~, Unknown], # 8
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [7, 8], 7, Unknown, 5, true], # 9
  [Return, {implicit: true}, [9], 9, ~, 9]]} # 10
K::__DEFAULT_0: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: Box}, ~, ~, Str], # 1
  [MemStart], # 2
  [Call, {class_name: Box, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: new, package: Box, param_names: [], want: scalar}, [1], 0, Object, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
K::b: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Scalar], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
main::__PROGRAM__: {start: 0, returns: [32], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: made}, ~, ~, Unknown, 2], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Assign, ~, [3, 4], 0, Int, 2, true], # 5
  [PackageMark, {package: K}, ~, 5], # 6
  [PackageMark, {package: main}, ~, 6], # 7
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: new, package: main, param_names: [], want: scalar}, ~, 7, Object, 5, true], # 8
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 10
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: new, package: main, param_names: [], want: scalar}, ~, 8, Object, 8, true], # 11
  [HashLiteral, ~, [9, 10], 11, HashRef], # 12
  [Constant, {const_type: string, value: Box}, ~, ~, Str], # 13
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [12, 13], 12, Unknown, 11, true], # 14
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [b], want: scalar}, [14], 14, Object, 14, true], # 15
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: b, package: main, param_names: [], want: scalar}, [8], 15, Scalar, 15, true], # 16
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: "n", package: main, param_names: [], want: list}, [16], 16, Unknown, 16, true], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: b, package: main, param_names: [], want: scalar}, [11], 17, Scalar, 17, true], # 19
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: "n", package: main, param_names: [], want: list}, [19], 19, Unknown, 19, true], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: b, package: main, param_names: [], want: scalar}, [15], 20, Scalar, 20, true], # 22
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: "n", package: main, param_names: [], want: list}, [22], 22, Unknown, 22, true], # 23
  [Coerce, {from_repr: Unknown, to_repr: Str}, [23], ~, Str], # 24
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 25
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: made}, ~, ~, Str, 23], # 26
  [Coerce, {from_repr: Unknown, to_repr: Str}, [26], ~, Str], # 27
  [Concat, ~, [25, 27], ~, Str], # 28
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 29
  [Concat, ~, [28, 29], ~, Str], # 30
  [Print, ~, [18, 21, 24, 30], 23, "Maybe[Boolean]"], # 31
  [Return, {implicit: true}, [1], 31, ~, 23]]} # 32
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: experimental, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A closure over a hash field

A method makes a closure that reads its class's hash field. Each call of the method closes over the object it runs on, so two objects answer for their own field.

```perl
use v5.42; use experimental 'class';
class C {
    field %m;
    method add ($k) { $m{$k} = 1 }
    method n { my $in = sub ($k) { exists $m{$k} ? 1 : 0 }; return $in->("a") . $in->("b") }
}
my $x = C->new; my $y = C->new;
$x->add("a"); $y->add("b");
print $x->n, $y->n, "\n";
```

```behavior
parses: yes
```

```output
1001
```

```ir
C::add: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [FieldAccess, {field_index: 0, field_stash: C}, ~, ~, Unknown], # 2
  [Parameter, {index: 0, name: $k, sigil: $}, ~, ~, Unknown], # 3
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Assign, ~, [4, 1], 0, Int, 5, true], # 6
  [Return, {implicit: true}, [1], 6, ~, 6]]} # 7
C::n: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: C::n::__ANON__:5:4, package: C, param_names: [], want: scalar}, [1], 0, Int, 2, true], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: C::n::__ANON__:5:4, package: C, param_names: [], want: scalar}, [4], 3, Int, 3, true], # 5
  [Concat, ~, [3, 5], ~, Str], # 6
  [Return, ~, [6], 5, ~, 5]]} # 7
C::n::__ANON__:5:4: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: C}, ~, ~, Unknown], # 1
  [Parameter, {index: 0, name: $k, sigil: $}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [Exists, {kind: hash}, [1, 2], ~, Boolean, 3], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [TernaryExpr, ~, [4, 5, 6], ~, Int], # 7
  [Return, {implicit: true}, [7], 0, ~, 3]]} # 8
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: C}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [], want: scalar}, ~, 5, Object, 5, true], # 6
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 8
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: add, package: main, param_names: [], want: void}, [5, 8], 6, Int, 6, true], # 9
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: add, package: main, param_names: [], want: void}, [6, 7], 9, Int, 9, true], # 10
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: "n", package: main, param_names: [], want: list}, [5], 10, Str, 10, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: "n", package: main, param_names: [], want: list}, [6], 11, Str, 11, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [12, 14, 15], 13, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 13]]} # 17
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: experimental, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A field read held across a store

A method keeps a field's value in a lexical, then stores to the field. The lexical holds the value from before the store, and a store's value is the value stored.

```perl
use v5.42; use experimental 'class';
class K {
    field $n = 1;
    method swap { my $old = $n; $n = 5; return "$old$n" }
    method bump { $n = $n + 1 }
}
my $k = K->new;
print $k->swap, " ", $k->bump, "\n";
```

```behavior
parses: yes
```

```output
15 6
```

```ir
K::__DEFAULT_0: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
K::bump: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Int, 1], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Add, ~, [2, 3], ~, Int], # 4
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Int], # 5
  [Assign, ~, [5, 4], 0, Int, 1, true], # 6
  [Return, {implicit: true}, [4], 6, ~, 6]]} # 7
K::swap: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Int, 1], # 2
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 4
  [Assign, ~, [3, 4], 0, Int, 1, true], # 5
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Int, 5], # 6
  [Concat, ~, [2, 6], ~, Str], # 7
  [Return, ~, [7], 5, ~, 5]]} # 8
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: K}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: swap, package: main, param_names: [], want: list}, [5], 5, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 8
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: bump, package: main, param_names: [], want: list}, [5], 6, Int, 6, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [7, 8, 10, 11], 9, "Maybe[Boolean]"], # 12
  [Return, {implicit: true}, [1], 12, ~, 9]]} # 13
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: experimental, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A hash element counted in a loop, read after it

A hash element is incremented in a foreach and in a while. The read after each loop sees every increment, not the value from the top of the last pass.

```perl
my @a = (1, 2, 3); my %h = (a => 0);
for my $x (@a) { $h{a}++ }
my $i = 0; my %w = (n => 0);
while ($i < 4) { $w{n}++; $i++ }
print "$h{a} $w{n}\n";
```

```behavior
parses: yes
```

```output
3 4
```

```ir
main::__PROGRAM__: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [HashLiteral, {sigil: "%", symbol: h}, [2, 3], ~, Hash], # 4
  [MemStart], # 5
  [Loop, {bound: entry}, [0], 0], # 6
  [Phi, {memory: true, region: 6}, [5, 46], ~, Unknown], # 7
  [Proj, {index: 1}, [6]], # 8
  [Region, {head: 6}, [8]], # 9
  [Phi, {memory: true, region: 9}, [7], ~, Unknown], # 10
  [Loop, {bound: each}, [9], 9], # 11
  [Phi, {memory: true, region: 11}, [10, 42], ~, Unknown], # 12
  [Proj, {index: 1}, [11]], # 13
  [Region, {head: 11}, [13]], # 14
  [Phi, {memory: true, region: 14}, [12], ~, Unknown], # 15
  [Subscript, {kind: hash}, [4, 2], ~, Scalar, 15], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 20
  [HashLiteral, {sigil: "%", symbol: w}, [20, 3], ~, Hash], # 21
  [Subscript, {kind: hash}, [21, 20], ~, Scalar, 15], # 22
  [Coerce, {from_repr: Unknown, to_repr: Str}, [22], ~, Str], # 23
  [Concat, ~, [19, 23], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [Concat, ~, [24, 25], ~, Str], # 26
  [Print, ~, [26], 14, "Maybe[Boolean]"], # 27
  [Return, {implicit: true}, [1], 27, ~, 15], # 28
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 29
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 30
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 31
  [ArrayLiteral, {sigil: "@", symbol: a}, [29, 30, 31], ~, Array], # 32
  [Count, ~, [32], ~, Int, 7], # 33
  [Phi, {region: 6}, [3, 43], ~, Int], # 34
  [NumGt, ~, [33, 34], 6, Boolean], # 35
  [Proj, {index: 0}, [6]], # 36
  [Subscript, {kind: hash}, [4, 2], 36, Scalar, 7], # 37
  [Subscript, {kind: hash}, [21, 20], ~, Int], # 38
  [Proj, {index: 0}, [11]], # 39
  [Subscript, {kind: hash}, [21, 20], 39, Scalar, 12], # 40
  [Increment, ~, [40], ~, Scalar], # 41
  [Assign, ~, [38, 41], 40, Scalar, 12, true], # 42
  [Add, ~, [34, 29], ~, Int], # 43
  [Increment, ~, [37], ~, Scalar], # 44
  [Subscript, {kind: hash}, [4, 2], ~, Int], # 45
  [Assign, ~, [45, 44], 37, Scalar, 7, true], # 46
  [Count, ~, [32], ~, Int, 5], # 47
  [Phi, {region: 11}, [3, 51], ~, Int], # 48
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 49
  [NumLt, ~, [48, 49], 11, Boolean], # 50
  [Add, ~, [48, 29], ~, Int]]} # 51
```

## A loop left by a last, then another loop

A `while (1)` left only by its `last`, a read of what it stored, then a second loop over the same package variable.

```perl
$x = 0;
while (1) { $x = $x + 1; last if $x == 3; }
print $x == 3 ? "ok 2\n" : "not ok 2\n";
$x = 0;
while ($x != 3) { $x = $x + 1; }
print "ok 3 $x\n";
```

```behavior
parses: yes
```

```output
ok 2
ok 3 3
```

```ir
main::__PROGRAM__: {start: 0, returns: [38], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "ok 3 "}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [EntryWrite, ~, [3, 4], 0, Unknown, 5, true], # 6
  [Loop, {bound: each}, [6], 6], # 7
  [Phi, {memory: true, region: 7}, [6, 12], ~, Unknown], # 8
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 8], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Add, ~, [9, 10], ~, Int], # 11
  [EntryWrite, ~, [3, 11], 7, Unknown, 8, true], # 12
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 12], # 13
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 14
  [NumEq, ~, [13, 14], ~, Boolean], # 15
  [If, ~, [12, 15], 12], # 16
  [Proj, {index: 0}, [16]], # 17
  [Region, {head: 7}, [17]], # 18
  [Phi, {memory: true, region: 18}, [12], ~, Unknown], # 19
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 19], # 20
  [NumEq, ~, [20, 14], ~, Boolean], # 21
  [Constant, {const_type: string, value: "ok 2\n"}, ~, ~, Str], # 22
  [Constant, {const_type: string, value: "not ok 2\n"}, ~, ~, Str], # 23
  [TernaryExpr, ~, [21, 22, 23], ~, Str], # 24
  [Print, ~, [24], 18, "Maybe[Boolean]"], # 25
  [EntryWrite, ~, [3, 4], 25, Unknown, 19, true], # 26
  [Loop, {bound: each}, [26], 26], # 27
  [Phi, {memory: true, region: 27}, [26, 42], ~, Unknown], # 28
  [Proj, {index: 1}, [27]], # 29
  [Region, {head: 27}, [29]], # 30
  [Phi, {memory: true, region: 30}, [28], ~, Unknown], # 31
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 31], # 32
  [Coerce, {from_repr: Int, to_repr: Str}, [32], ~, Str], # 33
  [Concat, ~, [2, 33], ~, Str], # 34
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 35
  [Concat, ~, [34, 35], ~, Str], # 36
  [Print, ~, [36], 30, "Maybe[Boolean]"], # 37
  [Return, {implicit: true}, [1], 37, ~, 31], # 38
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Int, 28], # 39
  [Add, ~, [39, 10], ~, Int], # 40
  [Proj, {index: 0}, [27]], # 41
  [EntryWrite, ~, [3, 40], 41, Unknown, 28, true], # 42
  [NumNe, ~, [39, 14], 27, Boolean], # 43
  [Proj, {index: 1}, [16]]]} # 44
```

## Method calls in a loop over an array filled by push

An array built by push is iterated while calling methods. No call can reach the array, so the loop sees each of its elements in turn.

```perl
package F {
    sub new { bless { n => { a => 1, b => 2, c => 3 } }, shift }
    sub get { $_[0]{n}{$_[1]} }
    sub drop { delete $_[0]{n}{$_[1]} }
}
my $f = F->new; my @dead;
for my $k (sort keys $f->{n}->%*) { push @dead, $k unless $k eq 'b' }
my @got;
for my $d (@dead) { push @got, $f->get($d); $f->drop($d) }
print "@got ", join(",", sort keys $f->{n}->%*), "\n";
```

```behavior
parses: yes
```

```output
1 3 b
```

```ir
F::drop: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 4
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [MemStart], # 7
  [Subscript, {kind: array}, [1, 6], ~, Scalar, 7], # 8
  [Delete, {kind: hash}, [5, 8], 0, Scalar, 7, true], # 9
  [Return, {implicit: true}, [9], 9, ~, 9]]} # 10
F::get: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 4
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [MemStart], # 7
  [Subscript, {kind: array}, [1, 6], ~, Scalar, 7], # 8
  [Subscript, {kind: hash}, [5, 8], 0, Scalar, 7, true], # 9
  [Return, {implicit: true}, [9], 9, ~, 9]]} # 10
F::new: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [HashLiteral, ~, [2, 3, 4, 5, 6, 7], 0, HashRef], # 8
  [HashLiteral, ~, [1, 8], 8, HashRef], # 9
  [ArgsSource, ~, ~, ~, Array], # 10
  [MemStart], # 11
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [10], 9, Scalar, 11, true], # 12
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [9, 12], 12, Unknown, 12, true], # 13
  [Return, {implicit: true}, [13], 13, ~, 13]]} # 14
main::__PROGRAM__: {start: 0, returns: [39], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: F}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {class_name: F, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: new, package: main, param_names: [], want: scalar}, [2], 0, Object, 3, true], # 4
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 5
  [Subscript, {kind: hash}, [4, 5], 4, Scalar, 4], # 6
  [HashLiteral, ~, ~, 6, HashRef], # 7
  [DefinedOr, ~, [6, 7], ~, Scalar], # 8
  [Subscript, {kind: hash}, [4, 5], ~, Scalar], # 9
  [Assign, ~, [9, 8], 7, Scalar, 4, true], # 10
  [PostfixDeref, {sigil: "%"}, [8], 10, Hash, 10, true], # 11
  [Loop, {bound: entry}, [11], 11], # 12
  [Phi, {memory: true, region: 12}, [11, 76], ~, Unknown], # 13
  [Proj, {index: 1}, [12]], # 14
  [Region, {head: 12}, [14]], # 15
  [Phi, {memory: true, region: 15}, [13], ~, Unknown], # 16
  [Loop, {bound: entry}, [15], 15], # 17
  [Phi, {memory: true, region: 17}, [16, 54], ~, Unknown], # 18
  [Proj, {index: 1}, [17]], # 19
  [Region, {head: 17}, [19]], # 20
  [Phi, {memory: true, region: 20}, [18], ~, Unknown], # 21
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 21], # 22
  [Coerce, {from_repr: Scalar, to_repr: Str}, [22], ~, Str], # 23
  [PadAccess, {sigil: "@", symbol: got}, ~, ~, Array], # 24
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [23, 24], ~, Str, 21], # 25
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 26
  [Concat, ~, [25, 26], ~, Str], # 27
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 28
  [Subscript, {kind: hash}, [4, 5], 20, Scalar, 21], # 29
  [HashLiteral, ~, ~, 29, HashRef], # 30
  [DefinedOr, ~, [29, 30], ~, Scalar], # 31
  [Assign, ~, [9, 31], 30, Scalar, 21, true], # 32
  [PostfixDeref, {sigil: "%"}, [31], 32, Hash, 32, true], # 33
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [33], ~, List, 33], # 34
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [34], ~, List, 33], # 35
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [28, 35], ~, Str, 33], # 36
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 37
  [Print, ~, [27, 36, 37], 33, "Maybe[Boolean]"], # 38
  [Return, {implicit: true}, [1], 38, ~, 33], # 39
  [PadAccess, {sigil: $, symbol: d}, ~, ~, Unknown, 18], # 40
  [PadAccess, {sigil: "@", symbol: dead}, ~, ~, Array], # 41
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 42
  [Phi, {region: 17}, [42, 81], ~, Int], # 43
  [Subscript, {kind: array}, [41, 43], ~, Scalar, 18], # 44
  [Proj, {index: 0}, [17]], # 45
  [Assign, ~, [40, 44], 45, Scalar, 18, true], # 46
  [PadAccess, {sigil: $, symbol: d}, ~, ~, Unknown, 46], # 47
  [Call, {class_name: F, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: get, package: main, param_names: [], want: list}, [4, 47], 46, Scalar, 46, true], # 48
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [24, 48], 48, Int, 48, true], # 49
  [PadAccess, {sigil: $, symbol: d}, ~, ~, Unknown, 49], # 50
  [Call, {class_name: F, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: drop, package: main, param_names: [], want: void}, [4, 50], 49, Scalar, 49, true], # 51
  [PadAccess, {sigil: $, symbol: d}, ~, ~, Unknown, 51], # 52
  [Subscript, {kind: array}, [41, 43], ~, Scalar], # 53
  [Assign, {if_changed: true}, [53, 52], 51, Unknown, 51, true], # 54
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [11], ~, List, 11], # 55
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [55], ~, List, 11], # 56
  [ArrayLiteral, ~, [56], ~, Array], # 57
  [Count, ~, [57], ~, Int, 11], # 58
  [Count, ~, [41], ~, Int, 18], # 59
  [Count, ~, [57], ~, Int, 13], # 60
  [Phi, {region: 12}, [42, 83], ~, Int], # 61
  [NumGt, ~, [60, 61], 12, Boolean], # 62
  [Proj, {index: 0}, [12]], # 63
  [Subscript, {kind: array}, [57, 61], ~, Scalar], # 64
  [Ref, ~, [64], 63, ScalarRef, 13], # 65
  [PostfixDeref, {sigil: $}, [65], ~, Scalar, 13], # 66
  [PostfixDeref, {sigil: $}, [65], 65, Scalar, 13], # 67
  [Coerce, {from_repr: Scalar, to_repr: Str}, [67], ~, Str], # 68
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 69
  [StrEq, ~, [68, 69], ~, Boolean], # 70
  [If, ~, [67, 70], 67], # 71
  [Proj, {index: 1}, [71]], # 72
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [41, 66], 72, Int, 13, true], # 73
  [Proj, {index: 0}, [71]], # 74
  [Region, {head: 71}, [74, 73]], # 75
  [Phi, {memory: true, predecessors: [74, 72], region: 75}, [13, 73], ~, Unknown], # 76
  [Subscript, {kind: array}, [57, 61], ~, Scalar, 13], # 77
  [Subscript, {kind: array}, [57, 61], ~, Scalar, 13], # 78
  [Count, ~, [41], ~, Int, 16], # 79
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 80
  [Add, ~, [43, 80], ~, Int], # 81
  [NumGt, ~, [59, 43], 17, Boolean], # 82
  [Add, ~, [61, 80], ~, Int]]} # 83
```

## Nested loops over other lists inside a pushed array

The outer list is filled by push; the inner loops walk the lists each element names.

```perl
my %in = (a => [[1, 2], 3], b => [4]); my @dead; push @dead, qw(a b);
my @seen;
for my $d (@dead) {
    for my $i ($in{$d}->@*) {
        if (ref $i) { for my $e ($i->@*) { push @seen, "$d$e" } }
        else { push @seen, "$d$i" }
    }
}
print "@seen\n";
```

```behavior
parses: yes
```

```output
a1 a2 a3 b4
```

```ir
main::__PROGRAM__: {start: 0, returns: [26], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {sigil: "@", symbol: dead}, ~, ~, Array], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [ArrayLiteral, ~, [6, 7], 0, ArrayRef], # 8
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 9
  [ArrayLiteral, ~, [8, 9], 8, ArrayRef], # 10
  [ArrayLiteral, ~, [5], 10, ArrayRef], # 11
  [MemStart], # 12
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 3, 4], 11, Int, 12, true], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Phi, {memory: true, region: 14}, [13, 73], ~, Unknown], # 15
  [Proj, {index: 1}, [14]], # 16
  [Region, {head: 14}, [16]], # 17
  [Phi, {memory: true, region: 17}, [15], ~, Unknown], # 18
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 18], # 19
  [Coerce, {from_repr: Scalar, to_repr: Str}, [19], ~, Str], # 20
  [PadAccess, {sigil: "@", symbol: seen}, ~, ~, Array], # 21
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [20, 21], ~, Str, 18], # 22
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 23
  [Concat, ~, [22, 23], ~, Str], # 24
  [Print, ~, [24], 17, "Maybe[Boolean]"], # 25
  [Return, {implicit: true}, [1], 25, ~, 18], # 26
  [HashLiteral, {sigil: "%", symbol: in}, [3, 10, 4, 11], ~, Hash], # 27
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 28
  [Phi, {region: 14}, [28, 66], ~, Int], # 29
  [Subscript, {kind: array}, [2, 29], ~, Scalar, 15], # 30
  [Proj, {index: 0}, [14]], # 31
  [Subscript, {kind: hash}, [27, 30], 31, Scalar, 15], # 32
  [ArrayLiteral, ~, ~, 32, ArrayRef], # 33
  [DefinedOr, ~, [32, 33], ~, Scalar], # 34
  [Subscript, {kind: hash}, [27, 30], ~, Scalar], # 35
  [Assign, ~, [35, 34], 33, Scalar, 15, true], # 36
  [PostfixDeref, {sigil: "@"}, [34], ~, Array, 36], # 37
  [Loop, {bound: entry}, [36], 36], # 38
  [Phi, {region: 38}, [28, 65], ~, Int], # 39
  [Proj, {index: 0}, [38]], # 40
  [Phi, {memory: true, region: 38}, [36, 96], ~, Unknown], # 41
  [Exists, {kind: array}, [37, 39], 40, Boolean, 41], # 42
  [Subscript, {kind: array}, [37, 39], ~, Scalar], # 43
  [Ref, ~, [43], ~, ScalarRef], # 44
  [TernaryExpr, ~, [42, 44, 1], 42, "Maybe[ScalarRef]"], # 45
  [PostfixDeref, {sigil: $}, [45], ~, Scalar, 41], # 46
  [Subscript, {kind: array}, [37, 39], ~, Scalar, 41], # 47
  [PostfixDeref, {sigil: $}, [45], ~, Scalar, 41], # 48
  [Subscript, {kind: array}, [37, 39], ~, Scalar, 41], # 49
  [TernaryExpr, ~, [42, 48, 49], 45, Scalar], # 50
  [RefType, ~, [50], ~, Str, 41], # 51
  [If, ~, [50, 51], 50], # 52
  [Proj, {index: 0}, [52]], # 53
  [TernaryExpr, ~, [42, 46, 47], 53, Scalar], # 54
  [PostfixDeref, {sigil: "@"}, [54], ~, Array, 41], # 55
  [Loop, {bound: entry}, [54], 54], # 56
  [Phi, {region: 56}, [28, 64], ~, Int], # 57
  [Proj, {index: 0}, [56]], # 58
  [Phi, {memory: true, region: 56}, [41, 80], ~, Unknown], # 59
  [Exists, {kind: array}, [55, 57], 58, Boolean, 59], # 60
  [Subscript, {kind: array}, [55, 57], ~, Scalar], # 61
  [Ref, ~, [61], ~, ScalarRef], # 62
  [TernaryExpr, ~, [60, 62, 1], 60, "Maybe[ScalarRef]"], # 63
  [Add, ~, [57, 6], ~, Int], # 64
  [Add, ~, [39, 6], ~, Int], # 65
  [Add, ~, [29, 6], ~, Int], # 66
  [PostfixDeref, {sigil: $}, [45], ~, Scalar, 41], # 67
  [PostfixDeref, {sigil: $}, [63], ~, Scalar, 59], # 68
  [Subscript, {kind: array}, [55, 57], ~, Scalar, 59], # 69
  [TernaryExpr, ~, [60, 68, 69], 63, Scalar], # 70
  [Proj, {index: 1}, [38]], # 71
  [Region, {head: 38}, [71]], # 72
  [Phi, {memory: true, region: 72}, [41], ~, Unknown], # 73
  [Count, ~, [2], ~, Int, 15], # 74
  [Subscript, {kind: array}, [37, 39], ~, Scalar, 41], # 75
  [TernaryExpr, ~, [42, 67, 75], ~, Scalar], # 76
  [Coerce, {from_repr: Scalar, to_repr: Str}, [30], ~, Str], # 77
  [Coerce, {from_repr: Scalar, to_repr: Str}, [70], ~, Str], # 78
  [Concat, ~, [77, 78], ~, Str], # 79
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [21, 79], 70, Int, 59, true], # 80
  [Count, ~, [2], ~, Int, 13], # 81
  [NumGt, ~, [74, 29], 14, Boolean], # 82
  [Coerce, {from_repr: Scalar, to_repr: Str}, [76], ~, Str], # 83
  [Concat, ~, [77, 83], ~, Str], # 84
  [Proj, {index: 1}, [52]], # 85
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [21, 84], 85, Int, 41, true], # 86
  [Count, ~, [55], ~, Int, 59], # 87
  [NumGt, ~, [87, 57], 56, Boolean], # 88
  [Count, ~, [37], ~, Int, 41], # 89
  [NumGt, ~, [89, 39], 38, Boolean], # 90
  [Count, ~, [37], ~, Int, 36], # 91
  [Proj, {index: 1}, [56]], # 92
  [Region, {head: 56}, [92]], # 93
  [Phi, {memory: true, region: 93}, [59], ~, Unknown], # 94
  [Region, {head: 52}, [93, 86]], # 95
  [Phi, {memory: true, predecessors: [53, 85], region: 95}, [94, 86], ~, Unknown], # 96
  [Count, ~, [55], ~, Int, 41]]} # 97
```

## A guarded defined-or store over an array filled by push

A hash element is filled from another hash, only where the key exists and the element is not yet defined.

```perl
my @k; push @k, qw(a b c);
my %ann = (a => 1, c => 3); my %s = (c => 9);
for my $k (@k) { $s{$k} //= $ann{$k} if exists $ann{$k} }
print join(",", map { "$_=$s{$_}" } sort keys %s), "\n";
```

```behavior
parses: yes
```

```output
a=1,c=9
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [PadAccess, {sigil: "@", symbol: k}, ~, ~, Array], # 4
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 7
  [MemStart], # 8
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [4, 5, 6, 7], 0, Int, 8, true], # 9
  [Loop, {bound: entry}, [9], 9], # 10
  [Proj, {index: 1}, [10]], # 11
  [Region, {head: 10}, [11]], # 12
  [Loop, {bound: entry}, [12], 12], # 13
  [Phi, {region: 13}, [3, 64], ~, Array], # 14
  [Phi, {memory: true, region: 10}, [9, 57], ~, Unknown], # 15
  [Phi, {memory: true, region: 12}, [15], ~, Unknown], # 16
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 14], ~, Str, 16], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Proj, {index: 1}, [13]], # 19
  [Region, {head: 13}, [19]], # 20
  [Print, ~, [17, 18], 20, "Maybe[Boolean]"], # 21
  [Return, {implicit: true}, [1], 21, ~, 16], # 22
  [Count, ~, [4], ~, Int, 9], # 23
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 24
  [HashLiteral, {sigil: "%", symbol: s}, [7, 24], ~, Hash], # 25
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 26
  [Phi, {region: 10}, [26, 66], ~, Int], # 27
  [Subscript, {kind: array}, [4, 27], ~, Scalar, 15], # 28
  [Subscript, {kind: hash}, [25, 28], ~, Scalar], # 29
  [Proj, {index: 0}, [10]], # 30
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 31
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 32
  [HashLiteral, {sigil: "%", symbol: ann}, [5, 31, 7, 32], ~, Hash], # 33
  [Exists, {kind: hash}, [33, 28], ~, Boolean, 15], # 34
  [If, ~, [30, 34], 30], # 35
  [Proj, {index: 0}, [35]], # 36
  [Subscript, {kind: hash}, [25, 28], 36, Scalar, 15], # 37
  [Defined, ~, [37], ~, Boolean], # 38
  [If, ~, [37, 38], 37], # 39
  [Proj, {index: 1}, [39]], # 40
  [Assign, ~, [29, 1], 40, Undef, 15, true], # 41
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [25], ~, List, 16], # 42
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [42], ~, List, 16], # 43
  [Count, ~, [43], ~, Int, 16], # 44
  [Phi, {region: 13}, [26, 65], ~, Int], # 45
  [Subscript, {kind: array}, [43, 45], ~, Scalar, 16], # 46
  [Subscript, {kind: hash}, [25, 46], ~, Scalar, 16], # 47
  [Count, ~, [4], ~, Int, 15], # 48
  [NumGt, ~, [48, 27], 10, Boolean], # 49
  [Subscript, {kind: hash}, [33, 28], ~, Scalar, 41], # 50
  [Assign, ~, [29, 50], 41, Scalar, 41, true], # 51
  [Proj, {index: 0}, [39]], # 52
  [Region, {head: 39}, [52, 51]], # 53
  [Phi, {memory: true, predecessors: [52, 40], region: 53}, [15, 51], ~, Unknown], # 54
  [Proj, {index: 1}, [35]], # 55
  [Region, {head: 35}, [53, 55]], # 56
  [Phi, {memory: true, predecessors: [36, 55], region: 56}, [54, 15], ~, Unknown], # 57
  [NumGt, ~, [44, 45], 13, Boolean], # 58
  [Coerce, {from_repr: Unknown, to_repr: Str}, [46], ~, Str], # 59
  [Coerce, {from_repr: Unknown, to_repr: Str}, [47], ~, Str], # 60
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 61
  [Concat, ~, [59, 61], ~, Str], # 62
  [Concat, ~, [62, 60], ~, Str], # 63
  [ListAppend, {collector: map}, [14, 63], ~, Array], # 64
  [Add, ~, [45, 31], ~, Int], # 65
  [Add, ~, [27, 31], ~, Int], # 66
  [Proj, {index: 0}, [13]]]} # 67
```

## A method call returned last, in the caller's context

A method returns another method's list. A list caller gets the list and a scalar caller what the inner method gives in scalar context, here its count.

```perl
use v5.42; use experimental 'class';
class C {
    field $kids :param = [];
    method children { $kids }
    method walk_all ($cb) {
        my @results; my @stack = ($self);
        while (@stack) { my $node = pop @stack; push @results, $cb->($node); push @stack, $node->children()->@*; }
        return @results;
    }
    method leaves { return $self->walk_all(sub ($n) { return $n }) }
}
my $c = C->new(kids => [C->new, C->new]);
my @l = $c->leaves; my $n = $c->leaves;
print scalar(@l), " $n\n";
```

```behavior
parses: yes
```

```output
3 3
```

```ir
C::__DEFAULT_0: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, ArrayRef], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
C::children: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 0, field_stash: C}, ~, ~, Scalar, 1], # 2
  [Return, {implicit: true}, [2], 0, ~, 1]]} # 3
C::leaves: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 1
  [AnonSub, {name: C::leaves::__ANON__:10:2}, ~, ~, CodeRef], # 2
  [MemStart], # 3
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: walk_all, package: C, param_names: []}, [1, 2], 0, Array, 3, true], # 4
  [Return, ~, [4], 4, ~, 4]]} # 5
C::leaves::__ANON__:10:2: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $n, sigil: $}, ~, ~, Unknown], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
C::walk_all: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [PadAccess, {sigil: "@", symbol: results}, ~, ~, Array], # 1
  [Loop, {bound: each}, [0], 0], # 2
  [Proj, {index: 1}, [2]], # 3
  [Region, {head: 2}, [3]], # 4
  [MemStart], # 5
  [Phi, {memory: true, region: 2}, [5, 25], ~, Unknown], # 6
  [Phi, {memory: true, region: 4}, [6], ~, Unknown], # 7
  [Return, ~, [1], 4, ~, 7], # 8
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 9
  [ArrayLiteral, {sigil: "@", symbol: stack}, [9], ~, Array], # 10
  [Count, ~, [10], ~, Int, 6], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [NumNe, ~, [11, 12], 2, Boolean], # 13
  [Proj, {index: 0}, [2]], # 14
  [Parameter, {index: 0, name: $cb, sigil: $}, ~, ~, Unknown], # 15
  [Call, {dispatch_kind: builtin, name: pop, param_names: []}, [10], 14, Scalar, 6, true], # 16
  [PadAccess, {sigil: $, symbol: node}, ~, ~, Unknown, 16], # 17
  [Assign, ~, [17, 16], 16, Scalar, 16, true], # 18
  [PadAccess, {sigil: $, symbol: node}, ~, ~, Unknown, 18], # 19
  [Call, {dispatch_kind: indirect, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: "", package: C, param_names: [], want: list}, [15, 19], 18, Unknown, 18, true], # 20
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [1, 20], 20, Int, 20, true], # 21
  [PadAccess, {sigil: $, symbol: node}, ~, ~, Unknown, 21], # 22
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: children, package: C, param_names: [], want: scalar}, [22], 21, Unknown, 21, true], # 23
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 7, package: C, sigil: "@", strict: true}, [23], 23, Array, 23, true], # 24
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [10, 24], 24, Int, 24, true]]} # 25
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: C}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 12, name: new, package: main, param_names: [], want: list}, ~, 3, Object, 4, true], # 5
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 12, name: new, package: main, param_names: [], want: list}, ~, 5, Object, 5, true], # 6
  [ArrayLiteral, ~, [5, 6], 6, ArrayRef], # 7
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 12, name: new, package: main, param_names: [kids], want: scalar}, [7], 7, Object, 6, true], # 8
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 13, name: leaves, package: main, param_names: [], want: list}, [8], 8, Array, 8, true], # 9
  [ArrayLiteral, {sigil: "@", symbol: l}, [9], ~, Array], # 10
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 13, name: leaves, package: main, param_names: [], want: scalar}, [8], 9, Array, 9, true], # 11
  [Count, ~, [10], ~, Int, 11], # 12
  [Coerce, {from_repr: Int, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [Print, ~, [13, 18], 11, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [1], 19, ~, 11]]} # 20
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: experimental, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## The count of an array passed as an argument

`scalar(@a)` among a call's arguments is one value, the count, for an array assigned a list and one filled by push.

```perl
sub new { my ($c, %o) = @_; return $o{ix} }
my @a = (1, 2, 3); my @b; push @b, 4, 5;
print main->new(ix => scalar(@a)), main->new(ix => scalar(@b)), "\n";
```

```behavior
parses: yes
```

```output
32
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: main}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: ix}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [ArrayLiteral, {sigil: "@", symbol: a}, [4, 5, 6], ~, Array], # 7
  [PadAccess, {sigil: "@", symbol: b}, ~, ~, Array], # 8
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 9
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 10
  [MemStart], # 11
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [8, 9, 10], 0, Int, 11, true], # 12
  [Count, ~, [7], ~, Int, 12], # 13
  [Call, {class_name: main, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: new, package: main, param_names: [], want: list}, [2, 3, 13], 12, Object, 12, true], # 14
  [Coerce, {from_repr: Object, to_repr: Str}, [14], ~, Str], # 15
  [Count, ~, [8], ~, Int, 14], # 16
  [Call, {class_name: main, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: new, package: main, param_names: [], want: list}, [2, 3, 16], 14, Object, 14, true], # 17
  [Coerce, {from_repr: Object, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Print, ~, [15, 18, 19], 17, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 17]]} # 21
main::new: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {sigil: "%", symbol: o}, ~, ~, Hash], # 1
  [Constant, {const_type: string, value: ix}, ~, ~, Str], # 2
  [MemStart], # 3
  [Subscript, {kind: hash}, [1, 2], ~, Scalar, 3], # 4
  [Return, ~, [4], 0, ~, 3], # 5
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Assign, {record: true, targets: 2}, [6, 1, 7], ~, List]]} # 8
```

## A closure over its sub's own parameter

A sub hands another a closure that reads the first sub's signature parameter. Each call closes over its own.

```perl
use v5.42;
sub walk ($cb) { join ",", grep { defined } map { $cb->($_) } (1, 2, 3) }
sub only ($want) { walk(sub ($n) { $n == $want ? $n : undef }) }
print only(2), only(3), "\n";
```

```behavior
parses: yes
```

```output
23
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::only, package: main, param_names: [], want: list}, [2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::only, package: main, param_names: [], want: list}, [6], 4, Str, 4, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [5, 8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7]]} # 11
main::only: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: want}, ~, ~, Unknown, 2], # 3
  [Parameter, {index: 0, name: $want, sigil: $}, ~, ~, Unknown], # 4
  [Assign, ~, [3, 4], 0, Unknown, 2, true], # 5
  [MakeCell, {captured_written: false, cell_name: $want}, [1], 5, Ref, 5, true], # 6
  [AnonSub, {captures: [$want], name: main::only::__ANON__:3:4}, [6], ~, CodeRef], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::walk, package: main, param_names: []}, [7], 6, Str, 6, true], # 8
  [Return, {implicit: true}, [8], 8, ~, 8]]} # 9
main::only::__ANON__:3:4: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $n, sigil: $}, ~, ~, Num], # 1
  [CellParam, {index: 0, name: $want}, ~, ~, Ref], # 2
  [MemStart], # 3
  [CellRead, ~, [2], ~, Unknown, 3], # 4
  [NumEq, ~, [1, 4], ~, Boolean], # 5
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 6
  [TernaryExpr, ~, [5, 1, 6], ~, Unknown], # 7
  [Return, {implicit: true}, [7], 0, ~, 3]]} # 8
main::walk: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [Region, {head: 3}, [4]], # 5
  [Loop, {bound: entry}, [5], 5], # 6
  [Phi, {region: 6}, [2, 35], ~, Array], # 7
  [MemStart], # 8
  [Phi, {memory: true, region: 3}, [8, 38], ~, Unknown], # 9
  [Phi, {memory: true, region: 5}, [9], ~, Unknown], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 7], ~, Str, 10], # 11
  [Proj, {index: 1}, [6]], # 12
  [Region, {head: 6}, [12]], # 13
  [Return, {implicit: true}, [11], 13, ~, 10], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 16
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 17
  [ArrayLiteral, ~, [15, 16, 17], ~, List], # 18
  [Count, ~, [18], ~, Int, 9], # 19
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 20
  [Phi, {region: 3}, [20, 45], ~, Int], # 21
  [NumGt, ~, [19, 21], 3, Boolean], # 22
  [Proj, {index: 0}, [3]], # 23
  [ArrayLiteral, ~, ~, ~, Array], # 24
  [Phi, {region: 3}, [24, 47], ~, Array], # 25
  [Count, ~, [25], ~, Int, 10], # 26
  [Phi, {region: 6}, [20, 48], ~, Int], # 27
  [Subscript, {kind: array}, [25, 27], ~, Scalar, 10], # 28
  [Proj, {index: 0}, [6]], # 29
  [Exists, {kind: array}, [25, 27], 29, Boolean, 10], # 30
  [Subscript, {kind: array}, [18, 21], ~, Scalar], # 31
  [Ref, ~, [31], ~, ScalarRef], # 32
  [LocalAlias, {name: _}, [32], 23, Unknown, 9], # 33
  [Defined, ~, [28], ~, Boolean], # 34
  [ListAppend, {collector: grep}, [7, 28, 34], ~, Array], # 35
  [Parameter, {index: 0, name: $cb, sigil: $}, ~, ~, Unknown], # 36
  [Subscript, {kind: array}, [18, 21], ~, Int, 9], # 37
  [Call, {dispatch_kind: indirect, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: "", package: main, param_names: [], want: list}, [36, 37], 33, Unknown, 9, true], # 38
  [NumGt, ~, [26, 27], 6, Boolean], # 39
  [Subscript, {kind: array}, [25, 27], ~, Scalar], # 40
  [Ref, ~, [40], ~, ScalarRef], # 41
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 42
  [TernaryExpr, ~, [30, 41, 42], ~, "Maybe[ScalarRef]"], # 43
  [LocalAlias, {name: _}, [43], 30, Unknown, 10], # 44
  [Add, ~, [21, 15], ~, Int], # 45
  [Count, ~, [18], ~, Int, 8], # 46
  [ListAppend, {collector: map}, [25, 38], ~, Array], # 47
  [Add, ~, [27, 15], ~, Int]]} # 48
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## A call returned in one arm, a constant in the other

One path returns a call's list, the other a constant. The call runs in the caller's context: a list caller gets the list, a scalar caller the call's scalar value.

```perl
sub g { return (4, 5, 6) }
sub f { my ($x) = @_; if ($x) { return g(); } return 7; }
my @a = f(1); my $s = f(1); my $t = f(0);
print scalar(@a), $s, $t, "\n";
```

```behavior
parses: yes
```

```output
367
```

```ir
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2], 0, List, 3, true], # 4
  [ArrayLiteral, {sigil: "@", symbol: a}, [4], ~, Array], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: scalar}, [2], 4, List, 4, true], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: scalar}, [6], 7, List, 7, true], # 8
  [Count, ~, [5], ~, Int, 8], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [10, 11, 12, 13], 8, "Maybe[Boolean]"], # 14
  [Return, {implicit: true}, [1], 14, ~, 8]]} # 15
main::f: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown], # 1
  [If, ~, [0, 1], 0], # 2
  [Proj, {index: 0}, [2]], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: []}, ~, 3, List, 4, true], # 5
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 6
  [Proj, {index: 1}, [2]], # 7
  [Region, {head: 2}, [5, 7]], # 8
  [Phi, {predecessors: [3, 7], region: 8}, [5, 6], ~, List], # 9
  [Phi, {exits: true, memory: true, predecessors: [3, 7], region: 8}, [5, 4], ~, Unknown], # 10
  [Return, ~, [9], 8, ~, 10], # 11
  [ArgsSource, ~, ~, ~, Array], # 12
  [Assign, {record: true, targets: 1}, [1, 12], ~, List]]} # 13
main::g: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, List], # 4
  [Coerce, {from_repr: List, to_repr: Scalar}, [3], ~, Scalar], # 5
  [MemStart], # 6
  [Return, ~, [4, 5], 0, ~, 6]]} # 7
```

## A closure fills a list its sub drains in a loop

A callback pushes onto a list its sub declares; each pass of an outer loop drains the list with nested loops and calls, then clears it. The list is private apart from that closure, which only pushes, and it is the same array in both.

```perl
sub f { my @pending; my $commit = sub { push @pending, $_[0] }; my $out = "";
  for my $pos (1 .. 3) { $commit->($pos); $commit->($pos * 10) if $pos == 2;
    if (@pending) { for my $s (@pending) { for my $k (1 .. 2) { $out .= length($s) } $out .= $s } @pending = () } $out .= "|" }
  return $out }
print f(), "\n";
```

```behavior
parses: yes
```

```output
111|1122220|113|
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {shared: 1, sigil: "@", symbol: pending}, ~, ~, Array], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: "@", symbol: pending}, ~, ~, Array, 3], # 4
  [ArrayLiteral, ~, ~, ~, Array], # 5
  [Assign, ~, [4, 5], 0, List, 3, true], # 6
  [MakeCell, {captured_written: false, cell_name: "@pending"}, [2], 6, Ref, 6, true], # 7
  [Loop, {bound: entry}, [7], 7], # 8
  [Phi, {region: 8}, [1, 47], ~, Str], # 9
  [Proj, {index: 1}, [8]], # 10
  [Region, {head: 8}, [10]], # 11
  [Phi, {memory: true, region: 8}, [7, 57], ~, List], # 12
  [Phi, {memory: true, region: 11}, [12], ~, List], # 13
  [Return, ~, [9], 11, ~, 13], # 14
  [PadAccess, {sigil: $, symbol: pos}, ~, ~, Unknown, 12], # 15
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 16
  [Phi, {region: 8}, [16, 66], ~, Int], # 17
  [Proj, {index: 0}, [8]], # 18
  [Assign, ~, [15, 17], 18, Int, 12, true], # 19
  [PadAccess, {sigil: $, symbol: pos}, ~, ~, Unknown, 19], # 20
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f::__ANON__:1:3, package: main, param_names: [], want: void}, [20], 19, Int, 19, true], # 21
  [PadAccess, {sigil: $, symbol: pos}, ~, ~, Num, 21], # 22
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 23
  [Multiply, ~, [22, 23], ~, Num], # 24
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 25
  [NumEq, ~, [22, 25], ~, Boolean], # 26
  [If, ~, [21, 26], 21], # 27
  [Proj, {index: 0}, [27]], # 28
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f::__ANON__:1:3, package: main, param_names: [], want: void}, [24], 28, Int, 21, true], # 29
  [Proj, {index: 1}, [27]], # 30
  [Region, {head: 27}, [29, 30]], # 31
  [Phi, {memory: true, predecessors: [28, 30], region: 31}, [29, 21], ~, Int], # 32
  [Count, ~, [2], ~, Int, 32], # 33
  [If, ~, [31, 33], 31], # 34
  [Proj, {index: 0}, [34]], # 35
  [Loop, {bound: entry}, [35], 35], # 36
  [Phi, {region: 36}, [9, 56], ~, Str], # 37
  [PadAccess, {shared: 1, sigil: "@", symbol: pending}, ~, ~, Array, 32], # 38
  [Proj, {index: 1}, [36]], # 39
  [Region, {head: 36}, [39]], # 40
  [ArrayLiteral, {sigil: "@", symbol: pending}, ~, 40, Array], # 41
  [Assign, ~, [38, 41], 41, List, 32, true], # 42
  [Proj, {index: 1}, [34]], # 43
  [Region, {head: 34}, [42, 43]], # 44
  [Phi, {predecessors: [35, 43], region: 44}, [37, 9], ~, Str], # 45
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 46
  [Concat, ~, [45, 46], ~, Str], # 47
  [AnonSub, {captures: ["@pending"], name: main::f::__ANON__:1:3}, [7], ~, CodeRef], # 48
  [Proj, {index: 0}, [36]], # 49
  [Loop, {bound: entry}, [49], 49], # 50
  [Phi, {region: 50}, [37, 63], ~, Str], # 51
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 52
  [Phi, {region: 36}, [52, 65], ~, Int], # 53
  [Subscript, {kind: array}, [2, 53], ~, Scalar, 32], # 54
  [Coerce, {from_repr: Unknown, to_repr: Str}, [54], ~, Str], # 55
  [Concat, ~, [51, 55], ~, Str], # 56
  [Phi, {memory: true, predecessors: [35, 43], region: 44}, [42, 32], ~, List], # 57
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 58
  [NumGt, ~, [58, 17], 8, Boolean], # 59
  [Coerce, {from_repr: Scalar, to_repr: Str}, [54], ~, Str], # 60
  [Length, ~, [60], ~, Int], # 61
  [Coerce, {from_repr: Int, to_repr: Str}, [61], ~, Str], # 62
  [Concat, ~, [51, 62], ~, Str], # 63
  [NumGt, ~, [33, 53], 36, Boolean], # 64
  [Add, ~, [53, 16], ~, Int], # 65
  [Add, ~, [17, 16], ~, Int], # 66
  [Phi, {region: 50}, [16, 68], ~, Int], # 67
  [Add, ~, [67, 16], ~, Int], # 68
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 69
  [NumGt, ~, [69, 67], 50, Boolean], # 70
  [Proj, {index: 0}, [50]], # 71
  [Proj, {index: 1}, [50]], # 72
  [Region, {head: 50}, [72]]]} # 73
main::f::__ANON__:1:3: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: pending}, ~, ~, Array], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [1, 5], 0, Int, 4, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A closure pushes onto its sub's array

The sub reads the array after the closure's calls, and clears it before them. The closure and the sub share one array.

```perl
sub f { my @p = (5); my $c = sub { push @p, $_[0] }; $c->(1); $c->(2); my $a = "@p"; @p = (); $c->(3); return "$a/@p" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
5 1 2/3
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array], # 3
  [MemStart], # 4
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array, 4], # 5
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 6
  [ArrayLiteral, {sigil: "@", symbol: p}, [6], 0, Array], # 7
  [Assign, ~, [5, 7], 7, List, 4, true], # 8
  [MakeCell, {captured_written: false, cell_name: "@p"}, [3], 8, Ref, 8, true], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f::__ANON__:1:4, package: main, param_names: [], want: void}, [2], 9, Int, 9, true], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f::__ANON__:1:4, package: main, param_names: [], want: void}, [1], 10, Int, 10, true], # 11
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 11], # 12
  [Coerce, {from_repr: Scalar, to_repr: Str}, [12], ~, Str], # 13
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array, 11], # 14
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [13, 14], ~, Str, 11], # 15
  [Constant, {const_type: string, value: "/"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 18
  [ArrayLiteral, {sigil: "@", symbol: p}, ~, 11, Array], # 19
  [Assign, ~, [14, 19], 19, List, 11, true], # 20
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f::__ANON__:1:4, package: main, param_names: [], want: void}, [18], 20, Int, 20, true], # 21
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array, 21], # 22
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [13, 22], ~, Str, 21], # 23
  [Concat, ~, [17, 23], ~, Str], # 24
  [Return, ~, [24], 21, ~, 21], # 25
  [AnonSub, {captures: ["@p"], name: main::f::__ANON__:1:4}, [9], ~, CodeRef]]} # 26
main::f::__ANON__:1:4: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [1, 5], 0, Int, 4, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A closure grows the list its sub iterates

A closure called from a foreach body pushes onto the array being iterated. Perl reads the length on every pass, so the new elements get passes too.

```perl
sub f { my @p = (1); my $add = sub { push @p, $_[0] + 1 if $_[0] < 4 }; my $out = ""; for my $x (@p) { $add->($x); $out .= $x } return $out }
print f(), "\n";
```

```behavior
parses: yes
```

```output
1234
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array, 3], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [ArrayLiteral, {sigil: "@", symbol: p}, [5], 0, Array], # 6
  [Assign, ~, [4, 6], 6, List, 3, true], # 7
  [MakeCell, {captured_written: false, cell_name: "@p"}, [2], 7, Ref, 7, true], # 8
  [Loop, {bound: entry}, [8], 8], # 9
  [Phi, {region: 9}, [1, 26], ~, Str], # 10
  [Proj, {index: 1}, [9]], # 11
  [Region, {head: 9}, [11]], # 12
  [Phi, {memory: true, region: 9}, [8, 29], ~, Scalar], # 13
  [Phi, {memory: true, region: 12}, [13], ~, Scalar], # 14
  [Return, ~, [10], 12, ~, 14], # 15
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 13], # 16
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 17
  [Phi, {region: 9}, [17, 27], ~, Int], # 18
  [Subscript, {kind: array}, [2, 18], ~, Scalar, 13], # 19
  [Proj, {index: 0}, [9]], # 20
  [Assign, ~, [16, 19], 20, Scalar, 13, true], # 21
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 21], # 22
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f::__ANON__:1:4, package: main, param_names: [], want: void}, [22], 21, Scalar, 21, true], # 23
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Str, 23], # 24
  [Coerce, {from_repr: Unknown, to_repr: Str}, [24], ~, Str], # 25
  [Concat, ~, [10, 25], ~, Str], # 26
  [Add, ~, [18, 5], ~, Int], # 27
  [Subscript, {kind: array}, [2, 18], ~, Scalar], # 28
  [Assign, {if_changed: true}, [28, 24], 23, Str, 23, true], # 29
  [Count, ~, [2], ~, Int, 13], # 30
  [AnonSub, {captures: ["@p"], name: main::f::__ANON__:1:4}, [8], ~, CodeRef], # 31
  [Count, ~, [2], ~, Int, 8], # 32
  [NumGt, ~, [30, 18], 9, Boolean]]} # 33
main::f::__ANON__:1:4: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 6
  [NumLt, ~, [5, 6], ~, Boolean], # 7
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array], # 8
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 9
  [Add, ~, [5, 9], ~, Num], # 10
  [If, ~, [0, 7], 0], # 11
  [Proj, {index: 0}, [11]], # 12
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [8, 10], 12, Int, 3, true], # 13
  [And, ~, [7, 13], ~, Scalar], # 14
  [Proj, {index: 1}, [11]], # 15
  [Region, {head: 11}, [15, 13]], # 16
  [Phi, {memory: true, predecessors: [15, 12], region: 16}, [3, 13], ~, Unknown], # 17
  [Return, {implicit: true}, [14], 16, ~, 17]]} # 18
```

## A //= into a hash a closure captures

The closure defaults an element of a hash its sub declares. Its second call finds the first call's value.

```perl
sub g { my %h; my $f = sub { $h{$_[0]} //= $_[1] }; return join " ", $f->("a", 1), $f->("a", 2), $f->("b", 3) }
print g(), "\n";
```

```behavior
parses: yes
```

```output
1 1 3
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::g: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Hash], # 4
  [MemStart], # 5
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Hash, 5], # 6
  [HashLiteral, ~, ~, ~, Hash], # 7
  [Assign, ~, [6, 7], 0, List, 5, true], # 8
  [MakeCell, {captured_written: false, cell_name: "%h"}, [4], 8, Ref, 8, true], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::g::__ANON__:1:3, package: main, param_names: [], want: list}, [2, 3], 9, Scalar, 9, true], # 10
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::g::__ANON__:1:3, package: main, param_names: [], want: list}, [2, 11], 10, Scalar, 10, true], # 12
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 13
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 14
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::g::__ANON__:1:3, package: main, param_names: [], want: list}, [13, 14], 12, Scalar, 12, true], # 15
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 10, 12, 15], ~, Str], # 16
  [Return, ~, [16], 15, ~, 15], # 17
  [AnonSub, {captures: ["%h"], name: main::g::__ANON__:1:3}, [9], ~, CodeRef]]} # 18
main::g::__ANON__:1:3: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Hash], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Subscript, {kind: hash}, [1, 5], 0, Scalar, 4], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Subscript, {kind: hash}, [1, 5], ~, Scalar], # 8
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 9
  [Defined, ~, [6], ~, Boolean], # 10
  [If, ~, [6, 10], 6], # 11
  [Proj, {index: 1}, [11]], # 12
  [Assign, ~, [8, 9], 12, Undef, 4, true], # 13
  [Subscript, {kind: array}, [2, 7], ~, Scalar, 13], # 14
  [Proj, {index: 0}, [11]], # 15
  [Assign, ~, [8, 14], 13, Scalar, 13, true], # 16
  [Region, {head: 11}, [15, 16]], # 17
  [Phi, {predecessors: [15, 12], region: 17}, [6, 14], ~, Scalar], # 18
  [Phi, {memory: true, predecessors: [15, 12], region: 17}, [4, 16], ~, Unknown], # 19
  [Return, {implicit: true}, [18], 17, ~, 19]]} # 20
```

## A recursive closure stored after it is made

The variable is declared, then assigned the closure that calls itself through it.

```perl
sub f { my $w; $w = sub { my $n = shift; return $n <= 0 ? 0 : $n + $w->($n - 1) }; return $w->(3) }
print f(), "\n";
```

```behavior
parses: yes
```

```output
6
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, ~, 0, Unknown, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: w}, ~, ~, Unknown, 2], # 3
  [Assign, ~, [3, 1], 0, Undef, 2, true], # 4
  [MakeCell, {captured_written: false, cell_name: $w}, [1], 4, Ref, 4, true], # 5
  [AnonSub, {captures: [$w], name: main::f::__ANON__:1:2}, [5], ~, CodeRef], # 6
  [CellWrite, ~, [5, 6], 5, Scalar, 5, true], # 7
  [CellRead, ~, [5], ~, Unknown, 7], # 8
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 9
  [Call, {dispatch_kind: indirect, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: "", package: main, param_names: []}, [8, 9], 7, Unknown, 7, true], # 10
  [Return, ~, [10], 10, ~, 10]]} # 11
main::f::__ANON__:1:2: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 0, Scalar, 3, true], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [CellParam, {index: 0, name: $w}, ~, ~, Ref], # 6
  [CellRead, ~, [6], ~, Unknown, 4], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Subtract, ~, [5, 8], ~, Num], # 9
  [NumLe, ~, [5, 1], ~, Boolean], # 10
  [If, ~, [4, 10], 4], # 11
  [Proj, {index: 1}, [11]], # 12
  [Call, {dispatch_kind: indirect, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: "", package: main, param_names: [], want: scalar}, [7, 9], 12, Unknown, 4, true], # 13
  [Add, ~, [5, 13], ~, Unknown], # 14
  [Proj, {index: 0}, [11]], # 15
  [Region, {head: 11}, [15, 13]], # 16
  [Phi, {predecessors: [15, 12], region: 16}, [1, 14], ~, Unknown], # 17
  [Phi, {memory: true, predecessors: [15, 12], region: 16}, [4, 13], ~, Unknown], # 18
  [Return, ~, [17], 16, ~, 18]]} # 19
```

## A //= through a captured reference in a recursive closure

The element belongs to the referent, which the closure and its maker share.

```perl
use v5.38; sub collect ($tree, $dv) { my $walk; $walk = sub ($node) { return unless ref $node; $dv->{$node->{name}} //= 1 if exists $node->{name}; for my $k ($node->{kids}->@*) { $walk->($k) } }; $walk->($tree); return join ",", sort keys %$dv }
print collect({ kids => [{ name => 'a', kids => [] }, { name => 'b', kids => [{ name => 'a', kids => [] }] }] }, { z => 0 }), "\n";
```

```behavior
parses: yes
```

```output
a,b,z
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: kids}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: name}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [ArrayLiteral, ~, ~, 0, ArrayRef], # 5
  [HashLiteral, ~, [3, 4, 2, 5], 5, HashRef], # 6
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 7
  [ArrayLiteral, ~, ~, 6, ArrayRef], # 8
  [HashLiteral, ~, [3, 4, 2, 8], 8, HashRef], # 9
  [ArrayLiteral, ~, [9], 9, ArrayRef], # 10
  [HashLiteral, ~, [3, 7, 2, 10], 10, HashRef], # 11
  [ArrayLiteral, ~, [6, 11], 11, ArrayRef], # 12
  [HashLiteral, ~, [2, 12], 12, HashRef], # 13
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 14
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 15
  [HashLiteral, ~, [14, 15], 13, HashRef], # 16
  [MemStart], # 17
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::collect, package: main, param_names: [], want: list}, [13, 16], 16, Str, 17, true], # 18
  [Coerce, {from_repr: Unknown, to_repr: Str}, [18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Print, ~, [19, 20], 18, "Maybe[Boolean]"], # 21
  [Return, {implicit: true}, [1], 21, ~, 18]]} # 22
main::collect: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: tree}, ~, ~, Unknown, 3], # 4
  [Parameter, {index: 0, name: $tree, sigil: $}, ~, ~, Unknown], # 5
  [Assign, ~, [4, 5], 0, Unknown, 3, true], # 6
  [PadAccess, {sigil: $, symbol: dv}, ~, ~, Unknown, 6], # 7
  [Parameter, {index: 1, name: $dv, sigil: $}, ~, ~, Unknown], # 8
  [Assign, ~, [7, 8], 6, Unknown, 6, true], # 9
  [PadAccess, {sigil: $, symbol: walk}, ~, ~, Unknown, 9], # 10
  [Assign, ~, [10, 2], 9, Undef, 9, true], # 11
  [MakeCell, {captured_written: true, cell_name: $dv}, [2], 11, Ref, 11, true], # 12
  [MakeCell, {captured_written: false, cell_name: $walk}, [2], 12, Ref, 12, true], # 13
  [AnonSub, {captures: [$dv, $walk], name: main::collect::__ANON__:1:4}, [12, 13], ~, CodeRef], # 14
  [CellWrite, ~, [13, 14], 13, Scalar, 13, true], # 15
  [CellRead, ~, [13], ~, Unknown, 15], # 16
  [PadAccess, {sigil: $, symbol: tree}, ~, ~, Unknown, 15], # 17
  [Call, {dispatch_kind: indirect, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: "", package: main, param_names: [], want: void}, [16, 17], 15, Unknown, 15, true], # 18
  [CellRead, ~, [12], ~, Unknown, 18], # 19
  [PostfixDeref, {sigil: "%"}, [19], 18, Hash, 18, true], # 20
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [20], ~, List, 20], # 21
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [21], ~, List, 20], # 22
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 22], ~, Str, 20], # 23
  [Return, ~, [23], 20, ~, 20]]} # 24
main::collect::__ANON__:1:4: {start: 0, returns: [47], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [Constant, {const_type: boolean, value: ""}, ~, ~, Boolean], # 2
  [Parameter, {index: 0, name: $node, sigil: $}, ~, ~, Unknown], # 3
  [MemStart], # 4
  [RefType, ~, [3], ~, Str, 4], # 5
  [Not, ~, [5], ~, Boolean], # 6
  [If, ~, [0, 6], 0], # 7
  [Proj, {index: 0}, [7]], # 8
  [Constant, {const_type: string, value: kids}, ~, ~, Str], # 9
  [Subscript, {kind: hash}, [3, 9], ~, Scalar], # 10
  [Constant, {const_type: string, value: name}, ~, ~, Str], # 11
  [Proj, {index: 1}, [7]], # 12
  [Exists, {kind: hash}, [3, 11], 12, Boolean, 4, true], # 13
  [If, ~, [13, 13], 13], # 14
  [Proj, {index: 1}, [14]], # 15
  [CellParam, {index: 0, name: $dv}, ~, ~, Ref], # 16
  [CellRead, ~, [16], ~, Unknown, 13], # 17
  [Proj, {index: 0}, [14]], # 18
  [Subscript, {kind: hash}, [3, 11], 18, Scalar, 13, true], # 19
  [Subscript, {kind: hash}, [17, 19], 19, Scalar, 19], # 20
  [Defined, ~, [20], ~, Boolean], # 21
  [If, ~, [20, 21], 20], # 22
  [Proj, {index: 0}, [22]], # 23
  [Subscript, {kind: hash}, [17, 19], ~, Scalar], # 24
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 25
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 26
  [Proj, {index: 1}, [22]], # 27
  [Assign, ~, [24, 26], 27, Undef, 19, true], # 28
  [Assign, ~, [24, 25], 28, Int, 28, true], # 29
  [Region, {head: 22}, [23, 29]], # 30
  [Region, {head: 14}, [15, 30]], # 31
  [Phi, {memory: true, predecessors: [23, 27], region: 30}, [19, 29], ~, Scalar], # 32
  [Phi, {memory: true, predecessors: [15, 18], region: 31}, [13, 32], ~, Scalar], # 33
  [Subscript, {kind: hash}, [3, 9], 31, Scalar, 33], # 34
  [ArrayLiteral, ~, ~, 34, ArrayRef], # 35
  [DefinedOr, ~, [34, 35], ~, Scalar], # 36
  [Assign, ~, [10, 36], 35, Scalar, 33, true], # 37
  [Loop, {bound: entry}, [37], 37], # 38
  [Proj, {index: 1}, [38]], # 39
  [Region, {head: 38}, [39]], # 40
  [Region, {head: 7}, [8, 40]], # 41
  [Phi, {predecessors: [8, 12], region: 41}, [1, 2], ~, List], # 42
  [Phi, {predecessors: [8, 12], region: 41}, [26, 2], ~, "Maybe[Boolean]"], # 43
  [Phi, {memory: true, region: 38}, [37, 61], ~, Unknown], # 44
  [Phi, {memory: true, region: 40}, [44], ~, Unknown], # 45
  [Phi, {exits: true, memory: true, predecessors: [8, 12], region: 41}, [4, 45], ~, Unknown], # 46
  [Return, ~, [42, 43], 41, ~, 46], # 47
  [PostfixDeref, {sigil: "@"}, [36], ~, Array, 37], # 48
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 49
  [Phi, {region: 38}, [49, 65], ~, Int], # 50
  [Proj, {index: 0}, [38]], # 51
  [Exists, {kind: array}, [48, 50], 51, Boolean, 44], # 52
  [Subscript, {kind: array}, [48, 50], ~, Scalar], # 53
  [Ref, ~, [53], ~, ScalarRef], # 54
  [TernaryExpr, ~, [52, 54, 26], 52, "Maybe[ScalarRef]"], # 55
  [PostfixDeref, {sigil: $}, [55], ~, Scalar, 44], # 56
  [CellParam, {index: 1, name: $walk}, ~, ~, Ref], # 57
  [CellRead, ~, [57], ~, Unknown, 44], # 58
  [Subscript, {kind: array}, [48, 50], ~, Scalar, 44], # 59
  [TernaryExpr, ~, [52, 56, 59], ~, Scalar], # 60
  [Call, {dispatch_kind: indirect, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: "", package: main, param_names: [], want: void}, [58, 60], 55, Unknown, 44, true], # 61
  [Count, ~, [48], ~, Int, 44], # 62
  [NumGt, ~, [62, 50], 38, Boolean], # 63
  [Count, ~, [48], ~, Int, 37], # 64
  [Add, ~, [50, 25], ~, Int]]} # 65
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.038"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## A try whose catch rethrows, inside an if arm

The body merges two values through a method that may die; the catch rethrows with context.

```perl
use v5.42; no warnings;
package S { sub new { bless {}, shift } sub add { my ($s, $a, $b) = @_; die "clash\n" if $a eq $b; return "$a$b" } }
sub merge ($s, $x, $y) {
    my $out = "none";
    if (defined $x) {
        my $merged;
        try { $merged = $s->add($x, $y); } catch ($e) { die "Ambiguity for '$x': $e"; }
        $out = $merged;
    }
    return $out;
}
my $s = S->new;
print merge($s, "a", "b"), " ", merge($s, undef, "b"), " ", (eval { merge($s, "a", "a") } // "died: $@");
```

```behavior
parses: yes
```

```output
ab none died: Ambiguity for 'a': clash
```

```ir
S::add: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: a}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Str], # 2
  [Concat, ~, [1, 2], ~, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 5
  [StrEq, ~, [4, 5], ~, Boolean], # 6
  [If, ~, [0, 6], 0], # 7
  [Proj, {index: 1}, [7]], # 8
  [Constant, {const_type: string, value: "clash\n"}, ~, ~, Str], # 9
  [Proj, {index: 0}, [7]], # 10
  [MemStart], # 11
  [Unwind, {file: "/tmp/mvrHQew3rs/case.pl", line: 2}, [9], 10, ~, 11], # 12
  [Region, {head: 7}, [8, 12]], # 13
  [Return, ~, [3], 13, ~, 11], # 14
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown], # 15
  [ArgsSource, ~, ~, ~, Array], # 16
  [Assign, {record: true, targets: 3}, [15, 1, 2, 16], ~, List]]} # 17
S::new: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [HashLiteral, ~, ~, 0, HashRef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 1, Scalar, 3, true], # 4
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [1, 4], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
main::__PROGRAM__: {start: 0, returns: [36], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: S}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {class_name: S, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 12, name: new, package: main, param_names: [], want: scalar}, [2], 0, Object, 3, true], # 4
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 4], # 5
  [Assign, ~, [5, 4], 4, Object, 4, true], # 6
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 6], # 7
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 13, name: main::merge, package: main, param_names: [], want: list}, [7, 8, 9], 6, Unknown, 6, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 12
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 10], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 13, name: main::merge, package: main, param_names: [], want: list}, [13, 1, 9], 10, Unknown, 10, true], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 14], # 16
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 17
  [EntryWrite, ~, [16, 17], 14, Unknown, 14, true], # 18
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 18], # 19
  [Call, {dispatch_kind: direct, eval_id: 2, file: "/tmp/mvrHQew3rs/case.pl", line: 13, name: main::merge, package: main, param_names: [], want: scalar}, [19, 8, 8], 18, Unknown, 18, true], # 20
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 20], # 21
  [EntryWrite, ~, [21, 17], 20, Unknown, 20, true], # 22
  [Exc, ~, [20]], # 23
  [Region, {catch: true, eval_id: 2}, [23]], # 24
  [EntryWrite, ~, [21, 23], 24, Unknown, 20, true], # 25
  [Region, {eval_entry: 14, eval_id: 2}, [22, 25]], # 26
  [Phi, {region: 26}, [20, 1], ~, Unknown], # 27
  [Constant, {const_type: string, value: "died: "}, ~, ~, Str], # 28
  [Phi, {memory: true, region: 26}, [22, 25], ~, Unknown], # 29
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 29], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [30], ~, Str], # 31
  [Concat, ~, [28, 31], ~, Str], # 32
  [DefinedOr, ~, [27, 32], ~, Unknown], # 33
  [Coerce, {from_repr: Unknown, to_repr: Str}, [33], ~, Str], # 34
  [Print, ~, [11, 12, 15, 12, 34], 26, "Maybe[Boolean]"], # 35
  [Return, {implicit: true}, [1], 35, ~, 29], # 36
  [Defined, ~, [27], ~, Boolean], # 37
  [TernaryExpr, ~, [37, 1, 32], ~, "Maybe[Str]"]]} # 38
main::merge: {start: 0, returns: [47], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 1
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 3], # 4
  [Parameter, {index: 0, name: $s, sigil: $}, ~, ~, Unknown], # 5
  [Assign, ~, [4, 5], 0, Unknown, 3, true], # 6
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 6], # 7
  [Parameter, {index: 1, name: $x, sigil: $}, ~, ~, Unknown], # 8
  [Assign, ~, [7, 8], 6, Unknown, 6, true], # 9
  [PadAccess, {sigil: $, symbol: "y"}, ~, ~, Unknown, 9], # 10
  [Parameter, {index: 2, name: $y, sigil: $}, ~, ~, Unknown], # 11
  [Assign, ~, [10, 11], 9, Unknown, 9, true], # 12
  [PadAccess, {sigil: $, symbol: merged}, ~, ~, Unknown, 12], # 13
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 14
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 12], # 15
  [Defined, ~, [15], ~, Boolean], # 16
  [If, ~, [12, 16], 12], # 17
  [Proj, {index: 0}, [17]], # 18
  [Assign, ~, [13, 14], 18, Undef, 12, true], # 19
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 19], # 20
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 19], # 21
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 19], # 22
  [PadAccess, {sigil: $, symbol: "y"}, ~, ~, Unknown, 19], # 23
  [Call, {dispatch_kind: method, eval_id: 1, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: add, package: main, param_names: [], want: scalar}, [21, 22, 23], 19, Unknown, 19, true], # 24
  [PadAccess, {sigil: $, symbol: merged}, ~, ~, Unknown, 24], # 25
  [Assign, ~, [25, 24], 24, Unknown, 24, true], # 26
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 26], # 27
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 28
  [EntryWrite, ~, [27, 28], 26, Unknown, 26, true], # 29
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 24], # 30
  [Exc, ~, [24]], # 31
  [Region, {catch: true, eval_id: 1}, [31]], # 32
  [EntryWrite, ~, [30, 31], 32, Unknown, 24, true], # 33
  [Region, {eval_entry: 19, eval_id: 1}, [29, 33]], # 34
  [Phi, {memory: true, region: 34}, [29, 33], ~, Unknown], # 35
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 34, Scalar, 35], # 36
  [EntryWrite, ~, [2, 20], 36, Unknown, 35, true], # 37
  [PadAccess, {sigil: $, symbol: merged}, ~, ~, Unknown, 37], # 38
  [Proj, {index: 1}, [17]], # 39
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 40
  [Phi, {region: 34}, [40, 14], ~, "Maybe[Int]"], # 41
  [If, ~, [37, 41], 37], # 42
  [Proj, {index: 0}, [42]], # 43
  [Region, {head: 17}, [39, 43]], # 44
  [Phi, {predecessors: [39, 43], region: 44}, [1, 38], ~, Unknown], # 45
  [Phi, {memory: true, predecessors: [39, 43], region: 44}, [12, 37], ~, Unknown], # 46
  [Return, ~, [45], 44, ~, 46], # 47
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Str, 37], # 48
  [Proj, {index: 1}, [42]], # 49
  [Coerce, {from_repr: Unknown, to_repr: Str}, [48], ~, Str], # 50
  [Coerce, {from_repr: Unknown, to_repr: Str}, [36], ~, Str], # 51
  [Constant, {const_type: string, value: "Ambiguity for '"}, ~, ~, Str], # 52
  [Concat, ~, [52, 50], ~, Str], # 53
  [Constant, {const_type: string, value: "': "}, ~, ~, Str], # 54
  [Concat, ~, [53, 54], ~, Str], # 55
  [Concat, ~, [55, 51], ~, Str], # 56
  [Unwind, {file: "/tmp/mvrHQew3rs/case.pl", line: 7}, [56], 49, ~, 37]]} # 57
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: unimport, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
```

## A try whose catch handles, leaving $@ alone

try/catch does not touch $@ outside it.

```perl
use v5.42; no warnings;
sub g ($x) { die "bad $x\n" if $x > 1; return $x }
sub h ($x) { my $r = "n"; try { g($x); } catch ($e) { chomp $e; $r = "c:$e"; } return $r }
$@ = "before";
print h(1), " ", h(2), " [$@]\n";
```

```behavior
parses: yes
```

```output
n c:bad 2 [before]
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 3
  [Constant, {const_type: string, value: before}, ~, ~, Str], # 4
  [MemStart], # 5
  [EntryWrite, ~, [3, 4], 0, Unknown, 5, true], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::h, package: main, param_names: [], want: list}, [2], 6, Str, 6, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::h, package: main, param_names: [], want: list}, [10], 7, Str, 7, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: " ["}, ~, ~, Str], # 13
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 11, Str, 11], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Print, ~, [8, 9, 12, 17], 14, "Maybe[Boolean]"], # 18
  [Return, {implicit: true}, [1], 18, ~, 11]]} # 19
main::g: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Unknown], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [NumGt, ~, [1, 2], ~, Boolean], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 1}, [4]], # 5
  [Constant, {const_type: string, value: "bad "}, ~, ~, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Proj, {index: 0}, [4]], # 11
  [MemStart], # 12
  [Unwind, {file: "/tmp/mvrHQew3rs/case.pl", line: 2}, [10], 11, ~, 12], # 13
  [Region, {head: 4}, [5, 13]], # 14
  [Return, ~, [1], 14, ~, 12]]} # 15
main::h: {start: 0, returns: [31], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: "c:"}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 3], # 4
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Unknown], # 5
  [Assign, ~, [4, 5], 0, Unknown, 3, true], # 6
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 6], # 7
  [Call, {dispatch_kind: direct, eval_id: 1, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::g, package: main, param_names: []}, [7], 6, Unknown, 6, true], # 8
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 8], # 9
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 10
  [EntryWrite, ~, [9, 10], 8, Unknown, 8, true], # 11
  [Exc, ~, [8]], # 12
  [Region, {catch: true, eval_id: 1}, [12]], # 13
  [EntryWrite, ~, [9, 12], 13, Unknown, 8, true], # 14
  [Region, {eval_entry: 6, eval_id: 1}, [11, 14]], # 15
  [Phi, {memory: true, region: 15}, [11, 14], ~, Unknown], # 16
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 15, Scalar, 16], # 17
  [Chomp, {kind: chomp}, [17], ~, Str], # 18
  [Concat, ~, [2, 18], ~, Str], # 19
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 20
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 6], # 21
  [EntryWrite, ~, [20, 21], 17, Unknown, 16, true], # 22
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 23
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 24
  [Phi, {region: 15}, [23, 24], ~, "Maybe[Int]"], # 25
  [If, ~, [22, 25], 22], # 26
  [Proj, {index: 0}, [26]], # 27
  [Proj, {index: 1}, [26]], # 28
  [Region, {head: 26}, [27, 28]], # 29
  [Phi, {predecessors: [27, 28], region: 29}, [1, 19], ~, Str], # 30
  [Return, ~, [30], 29, ~, 22], # 31
  [Phi, {predecessors: [27, 28], region: 29}, [8, 19], ~, Unknown], # 32
  [ChompValue, {kind: chomp}, [17], ~, Int]]} # 33
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: unimport, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
```

## A return after a next in a while body

One arm moves on with next, another returns. The arm that goes round must not be taken for the exit.

```perl
use v5.42;
sub find ($n) {
    my $cur = $n;
    while (defined $cur) {
        if (ref $cur eq 'ARRAY') { return $cur->[0] eq 'x' ? 'found' : 'other' }
        if (ref $cur eq 'HASH') { $cur = $cur->{next}; next; }
        return 'stop';
    }
    return 'end';
}
print find({ next => { next => ['x'] } }), " ", find({ next => \1 }), " ", find({ next => undef }), "\n";
```

```behavior
parses: yes
```

```output
found stop end
```

```ir
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: next}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 3
  [ArrayLiteral, ~, [3], 0, ArrayRef], # 4
  [HashLiteral, ~, [2, 4], 4, HashRef], # 5
  [HashLiteral, ~, [2, 5], 5, HashRef], # 6
  [MemStart], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 11, name: main::find, package: main, param_names: [], want: list}, [6], 6, Str, 7, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [Constant, {const_type: ref, value: "1"}, ~, ~, ScalarRef], # 11
  [HashLiteral, ~, [2, 11], 8, HashRef], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 11, name: main::find, package: main, param_names: [], want: list}, [12], 12, Str, 8, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [HashLiteral, ~, [2, 1], 13, HashRef], # 15
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 11, name: main::find, package: main, param_names: [], want: list}, [15], 15, Str, 13, true], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [9, 10, 14, 10, 17, 18], 16, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [1], 19, ~, 16]]} # 20
main::find: {start: 0, returns: [33], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $n, sigil: $}, ~, ~, Unknown], # 1
  [Loop, {bound: each}, [0], 0], # 2
  [Phi, {region: 2}, [1, 37], ~, Unknown], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Phi, {memory: true, region: 2}, [5, 37], ~, Unknown], # 6
  [Subscript, {kind: array}, [3, 4], ~, Scalar, 6], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 9
  [StrEq, ~, [8, 9], ~, Boolean], # 10
  [Constant, {const_type: string, value: found}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: other}, ~, ~, Str], # 12
  [TernaryExpr, ~, [10, 11, 12], ~, Str], # 13
  [Constant, {const_type: string, value: stop}, ~, ~, Str], # 14
  [Constant, {const_type: string, value: end}, ~, ~, Str], # 15
  [Proj, {index: 0}, [2]], # 16
  [RefType, ~, [3], ~, Str, 6], # 17
  [Constant, {const_type: string, value: ARRAY}, ~, ~, Str], # 18
  [StrEq, ~, [17, 18], ~, Boolean], # 19
  [If, ~, [16, 19], 16], # 20
  [Proj, {index: 0}, [20]], # 21
  [Proj, {index: 1}, [20]], # 22
  [Constant, {const_type: string, value: HASH}, ~, ~, Str], # 23
  [StrEq, ~, [17, 23], ~, Boolean], # 24
  [If, ~, [22, 24], 22], # 25
  [Proj, {index: 1}, [25]], # 26
  [Proj, {index: 1}, [2]], # 27
  [Region, {head: 2}, [27]], # 28
  [Region, ~, [21, 26, 28]], # 29
  [Phi, {predecessors: [21, 26, 28], region: 29}, [13, 14, 15], ~, Str], # 30
  [Phi, {memory: true, region: 28}, [6], ~, Unknown], # 31
  [Phi, {exits: true, memory: true, predecessors: [21, 26, 28], region: 29}, [6, 6, 31], ~, Unknown], # 32
  [Return, ~, [30], 29, ~, 32], # 33
  [Defined, ~, [3], 2, Boolean], # 34
  [Constant, {const_type: string, value: next}, ~, ~, Str], # 35
  [Proj, {index: 0}, [25]], # 36
  [Subscript, {kind: hash}, [3, 35], 36, Scalar, 6, true]]} # 37
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## A guarded return in a while that declares its variable

The condition declares `my $next`, which wraps the body in a block of its own.

```perl
my %PARENT = (a => 'b', b => 'c', c => 'd'); my %cache;
sub is_sub { my ($child, $parent) = @_; my $current = $child;
  while (my $next = $PARENT{$current}) { if ($next eq $parent) { $cache{"$child$parent"} = 1; return 1 } $current = $next }
  $cache{"$child$parent"} = 0; return 0 }
print is_sub('a', 'c'), is_sub('a', 'x'), is_sub('c', 'd'), " ", join(",", map { "$_=$cache{$_}" } sort keys %cache), "\n";
```

```behavior
parses: yes
```

```output
101 ac=1,ax=0,cd=1
```

```ir
main::__PROGRAM__: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 3
  [MemStart], # 4
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: PARENT}, ~, ~, Hash, 4], # 5
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 7
  [HashLiteral, {sigil: "%", symbol: PARENT}, [2, 6, 6, 3, 3, 7], 0, Hash], # 8
  [Assign, ~, [5, 8], 8, List, 4, true], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::is_sub, package: main, param_names: [], want: list}, [2, 3], 9, Int, 9, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::is_sub, package: main, param_names: [], want: list}, [2, 12], 10, Int, 10, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::is_sub, package: main, param_names: [], want: list}, [3, 7], 13, Int, 13, true], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 17
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 18
  [ArrayLiteral, ~, ~, ~, Array], # 19
  [Loop, {bound: entry}, [15], 15], # 20
  [Phi, {region: 20}, [19, 44], ~, Array], # 21
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [18, 21], ~, Str, 15], # 22
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 23
  [Proj, {index: 1}, [20]], # 24
  [Region, {head: 20}, [24]], # 25
  [Print, ~, [11, 14, 16, 17, 22, 23], 25, "Maybe[Boolean]"], # 26
  [Return, {implicit: true}, [1], 26, ~, 15], # 27
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: cache}, ~, ~, Hash, 15], # 28
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [28], ~, List, 15], # 29
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [29], ~, List, 15], # 30
  [Count, ~, [30], ~, Int, 15], # 31
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 32
  [Phi, {region: 20}, [32, 46], ~, Int], # 33
  [Subscript, {kind: array}, [30, 33], ~, Scalar, 15], # 34
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: cache}, ~, ~, Hash], # 35
  [Subscript, {kind: hash}, [35, 34], ~, Scalar, 15], # 36
  [NumGt, ~, [31, 33], 20, Boolean], # 37
  [Proj, {index: 0}, [20]], # 38
  [Coerce, {from_repr: Unknown, to_repr: Str}, [34], ~, Str], # 39
  [Coerce, {from_repr: Unknown, to_repr: Str}, [36], ~, Str], # 40
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 41
  [Concat, ~, [39, 41], ~, Str], # 42
  [Concat, ~, [42, 40], ~, Str], # 43
  [ListAppend, {collector: map}, [21, 43], ~, Array], # 44
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 45
  [Add, ~, [33, 45], ~, Int]]} # 46
main::is_sub: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: cache}, ~, ~, Hash], # 3
  [PadAccess, {sigil: $, symbol: child}, ~, ~, Unknown], # 4
  [PadAccess, {sigil: $, symbol: parent}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Subscript, {kind: hash}, [3, 6], ~, Scalar], # 7
  [Loop, {bound: each}, [0], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: PARENT}, ~, ~, Hash], # 10
  [Phi, {region: 8}, [4, 14], ~, Unknown], # 11
  [MemStart], # 12
  [Phi, {memory: true, region: 8}, [12, 13], ~, Unknown], # 13
  [Subscript, {kind: hash}, [10, 11], ~, Scalar, 13], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 16
  [StrEq, ~, [15, 16], ~, Boolean], # 17
  [If, ~, [9, 17], 9], # 18
  [Proj, {index: 0}, [18]], # 19
  [Assign, ~, [7, 1], 19, Int, 13, true], # 20
  [Proj, {index: 1}, [8]], # 21
  [Region, {head: 8}, [21]], # 22
  [Phi, {memory: true, region: 22}, [13], ~, Unknown], # 23
  [Assign, ~, [7, 2], 22, Int, 23, true], # 24
  [Region, ~, [20, 24]], # 25
  [Phi, {predecessors: [19, 24], region: 25}, [1, 2], ~, Int], # 26
  [Phi, {exits: true, memory: true, predecessors: [19, 24], region: 25}, [20, 24], ~, Int], # 27
  [Return, ~, [26], 25, ~, 27], # 28
  [Not, ~, [14], ~, Boolean], # 29
  [Not, ~, [29], 8, Boolean], # 30
  [Proj, {index: 1}, [18]], # 31
  [ArgsSource, ~, ~, ~, Array], # 32
  [Assign, {record: true, targets: 2}, [4, 5, 32], ~, List]]} # 33
```

## A pushed array drained and cleared in an arm of a loop

The array is carried by the loop, and a foreach over it runs inside an arm that then clears it.

```perl
sub f { my @p; my $out = ""; for my $pos (0 .. 5) { push @p, $pos if $pos % 2; if (@p > 1) { for my $s (@p) { $out .= $s } $out .= "|"; @p = (); } } return "$out @p" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
13| 5
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 46], ~, Str], # 3
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [MemStart], # 6
  [Phi, {memory: true, region: 2}, [6, 31], ~, Unknown], # 7
  [Proj, {index: 1}, [2]], # 8
  [Region, {head: 2}, [8]], # 9
  [Phi, {memory: true, region: 9}, [7], ~, Unknown], # 10
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 10], # 11
  [Coerce, {from_repr: Scalar, to_repr: Str}, [11], ~, Str], # 12
  [PadAccess, {sigil: "@", symbol: p}, ~, ~, Array], # 13
  [Phi, {region: 2}, [13, 50], ~, Array], # 14
  [PostfixDeref, {sigil: "@"}, [14], ~, Array, 10], # 15
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 15], ~, Str, 10], # 16
  [Concat, ~, [5, 16], ~, Str], # 17
  [Return, ~, [17], 9, ~, 10], # 18
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 19
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 20
  [Phi, {region: 2}, [20, 33], ~, Int], # 21
  [NumGt, ~, [19, 21], 2, Boolean], # 22
  [Proj, {index: 0}, [2]], # 23
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 24
  [Modulo, ~, [21, 24], ~, Int], # 25
  [If, ~, [23, 25], 23], # 26
  [Proj, {index: 0}, [26]], # 27
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [14, 21], 27, Int, 7, true], # 28
  [Proj, {index: 1}, [26]], # 29
  [Region, {head: 26}, [28, 29]], # 30
  [Phi, {memory: true, predecessors: [27, 29], region: 30}, [28, 7], ~, Unknown], # 31
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 32
  [Add, ~, [21, 32], ~, Int], # 33
  [Count, ~, [14], ~, Int, 31], # 34
  [NumGt, ~, [34, 32], ~, Boolean], # 35
  [If, ~, [30, 35], 30], # 36
  [Proj, {index: 0}, [36]], # 37
  [Loop, {bound: entry}, [37], 37], # 38
  [Phi, {region: 38}, [3, 52], ~, Str], # 39
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 40
  [Concat, ~, [39, 40], ~, Str], # 41
  [Proj, {index: 1}, [38]], # 42
  [Region, {head: 38}, [42]], # 43
  [Proj, {index: 1}, [36]], # 44
  [Region, {head: 36}, [43, 44]], # 45
  [Phi, {predecessors: [37, 44], region: 45}, [41, 3], ~, Str], # 46
  [Phi, {region: 38}, [20, 54], ~, Int], # 47
  [Subscript, {kind: array}, [14, 47], ~, Scalar, 31], # 48
  [ArrayLiteral, {sigil: "@", symbol: p}, ~, ~, Array], # 49
  [Phi, {predecessors: [37, 44], region: 45}, [49, 14], ~, Array], # 50
  [Coerce, {from_repr: Unknown, to_repr: Str}, [48], ~, Str], # 51
  [Concat, ~, [39, 51], ~, Str], # 52
  [NumGt, ~, [34, 47], 38, Boolean], # 53
  [Add, ~, [47, 32], ~, Int], # 54
  [Proj, {index: 0}, [38]]]} # 55
```

## A method that ends by clearing its field aggregates

The value of the clearing assignment is the method's return value.

```perl
use v5.42; use experimental 'class';
class K { field %h = (a => 1, b => 2); field @l = (1, 2, 3);
  method reset_h { %h = () } method reset_l { @l = (9) } method n { scalar(keys %h) . scalar(@l) } }
my $k = K->new; my $a = $k->reset_h; my @b = $k->reset_l; print $a, scalar(@b), $k->n, "\n";
```

```behavior
parses: yes
```

```output
0101
```

```ir
K::__DEFAULT_0: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [HashLiteral, ~, [1, 2, 3, 4], ~, Hash], # 5
  [MemStart], # 6
  [Return, ~, [5], 0, ~, 6], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [ArrayLiteral, ~, [2, 4, 8], ~, Array], # 9
  [Start], # 10
  [Return, ~, [9], 10, ~, 6]]} # 11
K::__DEFAULT_1: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, Array], # 4
  [MemStart], # 5
  [Return, ~, [4], 0, ~, 5], # 6
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 8
  [HashLiteral, ~, [7, 1, 8, 2], ~, Hash], # 9
  [Start], # 10
  [Return, ~, [9], 10, ~, 5]]} # 11
K::n: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Hash], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: scalar}, [1], ~, Int, 2], # 3
  [FieldAccess, {field_index: 1, field_stash: K}, ~, ~, Array], # 4
  [Count, ~, [4], ~, Int, 2], # 5
  [Concat, ~, [3, 5], ~, Str], # 6
  [Return, {implicit: true}, [6], 0, ~, 2]]} # 7
K::reset_h: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Hash], # 1
  [MemStart], # 2
  [Assign, {targets: 1}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
K::reset_l: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 1, field_stash: K}, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Assign, {targets: 1}, [1, 2], 0, Int, 3, true], # 4
  [Return, {implicit: true}, [4], 4, ~, 4]]} # 5
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: K}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: reset_h, package: main, param_names: [], want: scalar}, [5], 5, Unknown, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: reset_l, package: main, param_names: [], want: list}, [5], 6, Int, 6, true], # 8
  [ArrayLiteral, {sigil: "@", symbol: b}, [8], ~, Array], # 9
  [Count, ~, [9], ~, Int, 8], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: "n", package: main, param_names: [], want: list}, [5], 8, Str, 8, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [7, 11, 13, 14], 12, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 12]]} # 16
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: experimental, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## An if/else ending a sub, an arm storing then yielding a constant

The sub has a signature, and its last statement is an if/else whose arm stores a hash element and then yields a constant. Each call returns its arm's constant.

```perl
use v5.42; no warnings;
my %h;
sub g ($k, $x) { if ($k) { 1 } else { $h{$k} = 3; 2 } }
print g(1, "X"), g(0, "Y"), " $h{0}\n";
```

```behavior
parses: yes
```

```output
12 3
```

```ir
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: string, value: X}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::g, package: main, param_names: [], want: list}, [2, 3], 0, Int, 4, true], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Constant, {const_type: string, value: "Y"}, ~, ~, Str], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::g, package: main, param_names: [], want: list}, [7, 8], 5, Int, 5, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: h}, ~, ~, Hash], # 12
  [Constant, {const_type: string, value: "0"}, ~, ~, Str], # 13
  [Subscript, {kind: hash}, [12, 13], ~, Scalar, 9], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Concat, ~, [11, 15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [Print, ~, [6, 10, 18], 9, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [1], 19, ~, 9]]} # 20
main::g: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Parameter, {index: 0, name: $k, sigil: $}, ~, ~, Unknown], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 0}, [4]], # 5
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: h}, ~, ~, Hash], # 6
  [Subscript, {kind: hash}, [6, 3], ~, Scalar], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [Proj, {index: 1}, [4]], # 9
  [MemStart], # 10
  [Assign, ~, [7, 8], 9, Int, 10, true], # 11
  [Region, {head: 4}, [5, 11]], # 12
  [Phi, {predecessors: [5, 9], region: 12}, [1, 2], ~, Int], # 13
  [Phi, {memory: true, predecessors: [5, 9], region: 12}, [10, 11], ~, Unknown], # 14
  [Return, {implicit: true}, [13], 12, ~, 14]]} # 15
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: unimport, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
```

## An if/else ending a sub, each arm ending in an if

Each arm stores into a hash and then runs an `if` without an else. The sub yields the inner if's value: the push count, or the false condition.

```perl
use v5.42; no warnings;
my %c;
sub g ($k, $v, $e, $p, $ag) {
    if (exists $c{$k}) { $c{$k} .= $v; if ($e == $p && $ag) { push $ag->@*, 1 } }
    else { $c{$k} = $v; if ($e == $p && $ag) { push $ag->@*, 2 } }
}
my @ag;
print join("|", map { $_ // "u" } scalar(g("a", "x", 1, 1, \@ag)), scalar(g("a", "y", 1, 2, \@ag)), scalar(g("c", "w", 2, 2, \@ag))), " $c{a}\n";
```

```behavior
parses: yes
```

```output
1||2 xy
```

```ir
main::__PROGRAM__: {start: 0, returns: [30], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: w}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [PadAccess, {sigil: "@", symbol: ag}, ~, ~, Array], # 7
  [Ref, ~, [7], ~, ArrayRef], # 8
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 12
  [MemStart], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: main::g, package: main, param_names: [], want: scalar}, [9, 12, 11, 11, 8], 0, Unknown, 13, true], # 14
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: main::g, package: main, param_names: [], want: scalar}, [9, 10, 11, 6, 8], 14, Unknown, 14, true], # 15
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: main::g, package: main, param_names: [], want: scalar}, [4, 5, 6, 6, 8], 15, Unknown, 15, true], # 16
  [Loop, {bound: entry}, [16], 16], # 17
  [Phi, {region: 17}, [3, 43], ~, Array], # 18
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 18], ~, Str, 16], # 19
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 20
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: c}, ~, ~, Hash], # 21
  [Subscript, {kind: hash}, [21, 9], ~, Scalar, 16], # 22
  [Coerce, {from_repr: Unknown, to_repr: Str}, [22], ~, Str], # 23
  [Concat, ~, [20, 23], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [Concat, ~, [24, 25], ~, Str], # 26
  [Proj, {index: 1}, [17]], # 27
  [Region, {head: 17}, [27]], # 28
  [Print, ~, [19, 26], 28, "Maybe[Boolean]"], # 29
  [Return, {implicit: true}, [1], 29, ~, 16], # 30
  [ArrayLiteral, ~, [14, 15, 16], ~, List], # 31
  [Count, ~, [31], ~, Int, 16], # 32
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 33
  [Phi, {region: 17}, [33, 36], ~, Int], # 34
  [Subscript, {kind: array}, [31, 34], ~, Scalar, 16], # 35
  [Add, ~, [34, 11], ~, Int], # 36
  [Subscript, {kind: array}, [31, 34], ~, Scalar], # 37
  [NumGt, ~, [32, 34], 17, Boolean], # 38
  [Proj, {index: 0}, [17]], # 39
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 40
  [DefinedOr, ~, [35, 40], ~, Scalar], # 41
  [Ref, ~, [37], ~, ScalarRef], # 42
  [ListAppend, {collector: map}, [18, 41], ~, Array], # 43
  [LocalAlias, {name: _}, [42], 39, Unknown, 16]]} # 44
main::g: {start: 0, returns: [41], nodes: [
  [Start], # 0
  [Parameter, {index: 4, name: $ag, sigil: $}, ~, ~, Unknown], # 1
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: c}, ~, ~, Hash], # 2
  [Parameter, {index: 0, name: $k, sigil: $}, ~, ~, Unknown], # 3
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [2, 3], ~, Scalar, 5], # 6
  [Coerce, {from_repr: Scalar, to_repr: Str}, [6], ~, Str], # 7
  [Parameter, {index: 1, name: $v, sigil: $}, ~, ~, Unknown], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Exists, {kind: hash}, [2, 3], ~, Boolean, 5], # 10
  [If, ~, [0, 10], 0], # 11
  [Proj, {index: 0}, [11]], # 12
  [Assign, ~, [4, 9], 12, Str, 5, true], # 13
  [PostfixDeref, {sigil: "@"}, [1], ~, Array, 13], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Parameter, {index: 2, name: $e, sigil: $}, ~, ~, Num], # 16
  [Parameter, {index: 3, name: $p, sigil: $}, ~, ~, Num], # 17
  [NumEq, ~, [16, 17], ~, Boolean], # 18
  [And, ~, [18, 1], ~, Unknown], # 19
  [If, ~, [13, 19], 13], # 20
  [Proj, {index: 0}, [20]], # 21
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [14, 15], 21, Int, 13, true], # 22
  [Proj, {index: 1}, [20]], # 23
  [Region, {head: 20}, [22, 23]], # 24
  [Phi, {predecessors: [21, 23], region: 24}, [22, 19], ~, Unknown], # 25
  [Proj, {index: 1}, [11]], # 26
  [Assign, ~, [4, 8], 26, Unknown, 5, true], # 27
  [PostfixDeref, {sigil: "@"}, [1], ~, Array, 27], # 28
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 29
  [If, ~, [27, 19], 27], # 30
  [Proj, {index: 0}, [30]], # 31
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [28, 29], 31, Int, 27, true], # 32
  [Proj, {index: 1}, [30]], # 33
  [Region, {head: 30}, [32, 33]], # 34
  [Phi, {predecessors: [31, 33], region: 34}, [32, 19], ~, Unknown], # 35
  [Region, {head: 11}, [24, 34]], # 36
  [Phi, {predecessors: [12, 26], region: 36}, [25, 35], ~, Unknown], # 37
  [Phi, {memory: true, predecessors: [21, 23], region: 24}, [22, 13], ~, Str], # 38
  [Phi, {memory: true, predecessors: [31, 33], region: 34}, [32, 27], ~, Unknown], # 39
  [Phi, {memory: true, predecessors: [12, 26], region: 36}, [38, 39], ~, Unknown], # 40
  [Return, {implicit: true}, [37], 36, ~, 40]]} # 41
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: unimport, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
```

## A try in an if/else arm, after an early return

The catch dies, so the try has no join of its own; the arm goes on to the if/else's join, whose value the sub returns.

```perl
use v5.42; no warnings;
my %c; $c{a} = 1;
sub f { 1 }
sub g ($k) { return if $k eq "z"; if (exists $c{$k}) { try { f() } catch ($x) { die "A: $x" } 1 } else { 2 } }
print g("a"), g("b"), "[", scalar(g("z")) // "u", "]\n";
```

```behavior
parses: yes
```

```output
12[u]
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: c}, ~, ~, Hash], # 3
  [Subscript, {kind: hash}, [3, 2], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Assign, ~, [4, 5], 0, Int, 6, true], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::g, package: main, param_names: [], want: list}, [2], 7, List, 7, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::g, package: main, param_names: [], want: list}, [10], 8, List, 8, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 14
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::g, package: main, param_names: [], want: scalar}, [14], 11, List, 11, true], # 15
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 16
  [DefinedOr, ~, [15, 16], ~, List], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 19
  [Print, ~, [9, 12, 13, 18, 19], 15, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 15]]} # 21
main::f: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [MemStart], # 2
  [Return, {implicit: true}, [1], 0, ~, 2]]} # 3
main::g: {start: 0, returns: [41], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 4
  [MemStart], # 5
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 5], # 6
  [Parameter, {index: 0, name: $k, sigil: $}, ~, ~, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 9
  [StrEq, ~, [8, 9], ~, Boolean], # 10
  [If, ~, [0, 10], 0], # 11
  [Proj, {index: 1}, [11]], # 12
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: c}, ~, ~, Hash], # 13
  [Exists, {kind: hash}, [13, 7], ~, Boolean, 5], # 14
  [If, ~, [12, 14], 12], # 15
  [Proj, {index: 0}, [15]], # 16
  [Call, {dispatch_kind: direct, eval_id: 1, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: []}, ~, 16, Int, 5, true], # 17
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 17], # 18
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 19
  [EntryWrite, ~, [18, 19], 17, Unknown, 17, true], # 20
  [Exc, ~, [17]], # 21
  [Region, {catch: true, eval_id: 1}, [21]], # 22
  [EntryWrite, ~, [18, 21], 22, Unknown, 17, true], # 23
  [Region, {eval_entry: 16, eval_id: 1}, [20, 23]], # 24
  [Phi, {memory: true, region: 24}, [20, 23], ~, Unknown], # 25
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 24, Scalar, 25], # 26
  [EntryWrite, ~, [4, 6], 26, Unknown, 25, true], # 27
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 28
  [Phi, {region: 24}, [2, 28], ~, "Maybe[Int]"], # 29
  [If, ~, [27, 29], 27], # 30
  [Proj, {index: 0}, [30]], # 31
  [Proj, {index: 1}, [15]], # 32
  [Region, {head: 15}, [31, 32]], # 33
  [Phi, {predecessors: [31, 32], region: 33}, [2, 3], ~, Int], # 34
  [Proj, {index: 0}, [11]], # 35
  [Region, {head: 11}, [35, 33]], # 36
  [Phi, {predecessors: [35, 12], region: 36}, [1, 34], ~, List], # 37
  [Phi, {predecessors: [35, 12], region: 36}, [28, 34], ~, "Maybe[Int]"], # 38
  [Phi, {memory: true, predecessors: [31, 32], region: 33}, [27, 5], ~, Unknown], # 39
  [Phi, {exits: true, memory: true, predecessors: [35, 12], region: 36}, [5, 39], ~, Unknown], # 40
  [Return, ~, [37, 38], 36, ~, 40], # 41
  [Proj, {index: 1}, [30]], # 42
  [Coerce, {from_repr: Unknown, to_repr: Str}, [26], ~, Str], # 43
  [Constant, {const_type: string, value: "A: "}, ~, ~, Str], # 44
  [Concat, ~, [44, 43], ~, Str], # 45
  [Unwind, {file: "/tmp/mvrHQew3rs/case.pl", line: 4}, [45], 42, ~, 27]]} # 46
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: unimport, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
```

## A ternary argument passes its variables by alias

The callee writes `$_[1]`, which is the second variable of the arm the ternary chose.

```perl
sub g { $_[1] = 42 }
my $c = 1; my $s = 5; my $t = 6;
g($c ? ($s, $t) : ());
print "$s $t\n";
```

```behavior
parses: yes
```

```output
5 42
```

```ir
main::__PROGRAM__: {start: 0, returns: [26], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 3], # 4
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int, 3, true], # 6
  [PadAccess, {sigil: $, symbol: t}, ~, ~, Unknown, 6], # 7
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 8
  [Assign, ~, [7, 8], 6, Int, 6, true], # 9
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 9], # 10
  [PadAccess, {sigil: $, symbol: t}, ~, ~, Unknown, 9], # 11
  [ArrayLiteral, ~, [10, 11], ~, Array], # 12
  [ArrayLiteral, ~, ~, ~, Array], # 13
  [TernaryExpr, ~, [2, 12, 13], ~, Array], # 14
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::g, package: main, param_names: [], want: void}, [14], 9, Int, 9, true], # 15
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Str, 15], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [PadAccess, {sigil: $, symbol: t}, ~, ~, Str, 15], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Concat, ~, [19, 21], ~, Str], # 22
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 23
  [Concat, ~, [22, 23], ~, Str], # 24
  [Print, ~, [24], 15, "Maybe[Boolean]"], # 25
  [Return, {implicit: true}, [1], 25, ~, 15]]} # 26
main::g: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "42"}, ~, ~, Int], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Assign, ~, [4, 1], 0, Int, 5, true], # 6
  [Return, {implicit: true}, [1], 6, ~, 6]]} # 7
```

## A method call's argument is an alias

The method writes `$_[1]`, its first argument after the invocant, and the caller's variable changes.

```perl
package O { sub new { bless {}, shift } sub m { $_[1] = 9 } }
sub f { my $o = O->new; my $x = 1; $o->m($x); return $x }
print f(), "\n";
```

```behavior
parses: yes
```

```output
9
```

```ir
O::m: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Assign, ~, [4, 1], 0, Int, 5, true], # 6
  [Return, {implicit: true}, [1], 6, ~, 6]]} # 7
O::new: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [HashLiteral, ~, ~, 0, HashRef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 1, Scalar, 3, true], # 4
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [1, 4], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Unknown, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: O}, ~, ~, Str], # 1
  [MemStart], # 2
  [Call, {class_name: O, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: new, package: main, param_names: [], want: scalar}, [1], 0, Object, 2, true], # 3
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 3], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 3, Int, 3, true], # 6
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 6], # 7
  [Call, {class_name: O, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: m, package: main, param_names: [], want: void}, [3, 7], 6, Int, 6, true], # 8
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 8], # 9
  [Return, ~, [9], 8, ~, 8]]} # 10
```

## Optional pairs as a method call's arguments

Each pair is passed only when its value is defined.

```perl
package K { sub new { shift; bless {@_}, "K" } }
sub f { my ($s, $p) = @_; my $o = K->new(name => "n", (defined $s ? (superclass => $s) : ()), (defined $p ? (parent => $p) : ())); return join ",", map { "$_=$o->{$_}" } sort keys %$o }
print f("S", undef), " ", f(undef, "P"), "\n";
```

```behavior
parses: yes
```

```output
name=n,superclass=S name=n,parent=P
```

```ir
K::new: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1], 0, Scalar, 2, true], # 3
  [HashLiteral, ~, [1], 3, HashRef], # 4
  [Constant, {const_type: string, value: K}, ~, ~, Str], # 5
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [4, 5], 4, Unknown, 3, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: S}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2, 1], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: P}, ~, ~, Str], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [1, 7], 4, Str, 4, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [5, 6, 9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
main::f: {start: 0, returns: [32], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Constant, {const_type: string, value: K}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: name}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 5
  [MemStart], # 6
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 6], # 7
  [PadAccess, {sigil: $, symbol: p}, ~, ~, Unknown, 6], # 8
  [ArgsSource, ~, ~, ~, Array], # 9
  [Assign, {targets: 2}, [7, 8, 9], 0, List, 6, true], # 10
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 10], # 11
  [Defined, ~, [11], ~, Boolean], # 12
  [Constant, {const_type: string, value: superclass}, ~, ~, Str], # 13
  [ArrayLiteral, ~, [13, 11], ~, Array], # 14
  [ArrayLiteral, ~, ~, ~, Array], # 15
  [TernaryExpr, ~, [12, 14, 15], ~, Array], # 16
  [PadAccess, {sigil: $, symbol: p}, ~, ~, Unknown, 10], # 17
  [Defined, ~, [17], ~, Boolean], # 18
  [Constant, {const_type: string, value: parent}, ~, ~, Str], # 19
  [ArrayLiteral, ~, [19, 17], ~, Array], # 20
  [ArrayLiteral, ~, ~, ~, Array], # 21
  [TernaryExpr, ~, [18, 20, 21], ~, Array], # 22
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: new, package: main, param_names: [], want: scalar}, [3, 4, 5, 16, 22], 10, Object, 10, true], # 23
  [PostfixDeref, {sigil: "%"}, [23], 23, Hash, 23, true], # 24
  [Loop, {bound: entry}, [24], 24], # 25
  [Phi, {region: 25}, [2, 45], ~, Array], # 26
  [Phi, {memory: true, region: 25}, [24, 39], ~, List], # 27
  [Proj, {index: 1}, [25]], # 28
  [Region, {head: 25}, [28]], # 29
  [Phi, {memory: true, region: 29}, [27], ~, List], # 30
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 26], ~, Str, 30], # 31
  [Return, ~, [31], 29, ~, 30], # 32
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [24], ~, List, 24], # 33
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [33], ~, List, 24], # 34
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 35
  [Phi, {region: 25}, [35, 50], ~, Int], # 36
  [Subscript, {kind: array}, [34, 36], ~, Scalar, 27], # 37
  [Proj, {index: 0}, [25]], # 38
  [Subscript, {kind: hash}, [23, 37], 38, Scalar, 27, true], # 39
  [Coerce, {from_repr: Unknown, to_repr: Str}, [37], ~, Str], # 40
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 41
  [Concat, ~, [40, 41], ~, Str], # 42
  [Coerce, {from_repr: Unknown, to_repr: Str}, [39], ~, Str], # 43
  [Concat, ~, [42, 43], ~, Str], # 44
  [ListAppend, {collector: map}, [26, 44], ~, Array], # 45
  [Count, ~, [34], ~, Int, 27], # 46
  [Count, ~, [34], ~, Int, 24], # 47
  [NumGt, ~, [46, 36], 25, Boolean], # 48
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 49
  [Add, ~, [36, 49], ~, Int]]} # 50
```

## A sub reads, clears and refills an array its closure pushes onto

The read keeps the array as it stood; the clear lands between the calls.

```perl
sub f { my @p = (5); my $c = sub { push @p, $_[0] }; $c->(1); $c->(2); my $a = "@p"; @p = (); $c->(3); return "$a/@p" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
5 1 2/3
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array], # 3
  [MemStart], # 4
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array, 4], # 5
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 6
  [ArrayLiteral, {sigil: "@", symbol: p}, [6], 0, Array], # 7
  [Assign, ~, [5, 7], 7, List, 4, true], # 8
  [MakeCell, {captured_written: false, cell_name: "@p"}, [3], 8, Ref, 8, true], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f::__ANON__:1:4, package: main, param_names: [], want: void}, [2], 9, Int, 9, true], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f::__ANON__:1:4, package: main, param_names: [], want: void}, [1], 10, Int, 10, true], # 11
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 11], # 12
  [Coerce, {from_repr: Scalar, to_repr: Str}, [12], ~, Str], # 13
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array, 11], # 14
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [13, 14], ~, Str, 11], # 15
  [Constant, {const_type: string, value: "/"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 18
  [ArrayLiteral, {sigil: "@", symbol: p}, ~, 11, Array], # 19
  [Assign, ~, [14, 19], 19, List, 11, true], # 20
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f::__ANON__:1:4, package: main, param_names: [], want: void}, [18], 20, Int, 20, true], # 21
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array, 21], # 22
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [13, 22], ~, Str, 21], # 23
  [Concat, ~, [17, 23], ~, Str], # 24
  [Return, ~, [24], 21, ~, 21], # 25
  [AnonSub, {captures: ["@p"], name: main::f::__ANON__:1:4}, [9], ~, CodeRef]]} # 26
main::f::__ANON__:1:4: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [1, 5], 0, Int, 4, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A sub reads a hash between its closure's stores

Each `keys` sees the hash as it stood at that point.

```perl
sub f { my %h = (a => 1); my $c = sub { $h{$_[0]} = 1 }; my @k = sort keys %h; $c->("b"); my @l = sort keys %h; %h = (); $c->("c"); return join ",", @k, "|", @l, "|", sort keys %h }
print f(), "\n";
```

```behavior
parses: yes
```

```output
a,|,a,b,|,c
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Hash], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Hash, 3], # 4
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [HashLiteral, {sigil: "%", symbol: h}, [5, 6], 0, Hash], # 7
  [Assign, ~, [4, 7], 7, List, 3, true], # 8
  [MakeCell, {captured_written: false, cell_name: "%h"}, [2], 8, Ref, 8, true], # 9
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Hash, 9], # 10
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [10], ~, List, 9], # 11
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [11], ~, List, 9], # 12
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 14
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f::__ANON__:1:4, package: main, param_names: [], want: void}, [14], 9, Int, 9, true], # 15
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Hash, 15], # 16
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [16], ~, List, 15], # 17
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [17], ~, List, 15], # 18
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 19
  [HashLiteral, {sigil: "%", symbol: h}, ~, 15, Hash], # 20
  [Assign, ~, [16, 20], 20, List, 15, true], # 21
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f::__ANON__:1:4, package: main, param_names: [], want: void}, [19], 21, Int, 21, true], # 22
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Hash, 22], # 23
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [23], ~, List, 22], # 24
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [24], ~, List, 22], # 25
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 12, 13, 18, 13, 25], ~, Str, 22], # 26
  [Return, ~, [26], 22, ~, 22], # 27
  [AnonSub, {captures: ["%h"], name: main::f::__ANON__:1:4}, [9], ~, CodeRef]]} # 28
main::f::__ANON__:1:4: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Hash], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [3, 4], ~, Scalar, 5], # 6
  [Subscript, {kind: hash}, [2, 6], ~, Scalar], # 7
  [Assign, ~, [7, 1], 0, Int, 5, true], # 8
  [Return, {implicit: true}, [1], 8, ~, 8]]} # 9
```

## A closure bound once, called on a foreach iterator

The closure's value is kept. Its body holds no alias to the iterator, so the loop lowers.

```perl
use v5.42;
my @a = (1, 2);
my $g = sub ($x, $y) { $x + $y };
my @r;
for my $i (@a) { my $v = $g->($i, 1); push @r, $v }
print "@a @r\n";
```

```behavior
parses: yes
```

```output
1 2 2 3
```

```ir
main::__PROGRAM__: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {memory: true, region: 3}, [2, 37], ~, Unknown], # 4
  [Proj, {index: 1}, [3]], # 5
  [Region, {head: 3}, [5]], # 6
  [Phi, {memory: true, region: 6}, [4], ~, Unknown], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 7], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 11
  [ArrayLiteral, {sigil: "@", symbol: a}, [10, 11], ~, Array], # 12
  [PostfixDeref, {sigil: "@"}, [12], ~, Array, 7], # 13
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [9, 13], ~, Str, 7], # 14
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [PadAccess, {sigil: "@", symbol: r}, ~, ~, Array], # 17
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [9, 17], ~, Str, 7], # 18
  [Concat, ~, [16, 18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [Print, ~, [21], 6, "Maybe[Boolean]"], # 22
  [Return, {implicit: true}, [1], 22, ~, 7], # 23
  [Count, ~, [12], ~, Int, 4], # 24
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 25
  [Phi, {region: 3}, [25, 38], ~, Int], # 26
  [NumGt, ~, [24, 26], 3, Boolean], # 27
  [Proj, {index: 0}, [3]], # 28
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 4], # 29
  [Subscript, {kind: array}, [12, 26], ~, Int, 4], # 30
  [Assign, ~, [29, 30], 28, Int, 4, true], # 31
  [Subscript, {kind: array}, [12, 26], ~, Scalar], # 32
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 31], # 33
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::__PROGRAM__::__ANON__:3:17, package: main, param_names: [], want: scalar}, [33, 10], 31, Num, 31, true], # 34
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [17, 34], 34, Int, 34, true], # 35
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Unknown, 35], # 36
  [Assign, {if_changed: true}, [32, 36], 35, Unknown, 35, true], # 37
  [Add, ~, [26, 10], ~, Int], # 38
  [Count, ~, [12], ~, Int, 2]]} # 39
main::__PROGRAM__::__ANON__:3:17: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Num], # 1
  [Parameter, {index: 1, name: $y, sigil: $}, ~, ~, Num], # 2
  [Add, ~, [1, 2], ~, Num], # 3
  [MemStart], # 4
  [Return, {implicit: true}, [3], 0, ~, 4]]} # 5
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## A variable declared in a while condition, passed to a call

The condition declares `my $n = shift @w` and the body passes `$n` to a sub. Each pass stores the new value before the body reads it.

```perl
sub g { "<$_[0]>" }
sub f { my @w = (1, 2); my $s = ""; while (my $n = shift @w) { $s .= g($n) } $s }
print f(), "\n";
```

```behavior
parses: yes
```

```output
<1><2>
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: each}, [0], 0], # 2
  [Phi, {region: 2}, [1, 22], ~, Str], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [MemStart], # 6
  [Phi, {memory: true, region: 2}, [6, 20], ~, Unknown], # 7
  [Phi, {memory: true, region: 5}, [7], ~, Unknown], # 8
  [Return, {implicit: true}, [3], 5, ~, 8], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 11
  [ArrayLiteral, {sigil: "@", symbol: w}, [10, 11], ~, Array], # 12
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [12], 2, Int, 7, true], # 13
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 14
  [NumNe, ~, [13, 14], 2, Boolean], # 15
  [Proj, {index: 0}, [2]], # 16
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown, 13], # 17
  [Assign, ~, [17, 13], 13, Int, 13, true], # 18
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown, 18], # 19
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: scalar}, [19], 16, Str, 18, true], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Concat, ~, [3, 21], ~, Str]]} # 22
main::g: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "<"}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Constant, {const_type: string, value: ">"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Return, {implicit: true}, [9], 0, ~, 4]]} # 10
```

## A my declared on the right of &&

The variable declared in the condition is undef where the left side was false.

```perl
my %h = (a => { v => 5 });
sub f { my ($k, $on) = @_; my $r = "none"; if ($on && (my $x = $h{$k})) { $r = $x->{v} } return $r }
print f("a", 1), f("b", 1), f("a", 0), "\n";
```

```behavior
parses: yes
```

```output
5nonenone
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: h}, ~, ~, Hash, 4], # 5
  [Constant, {const_type: string, value: v}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 7
  [HashLiteral, ~, [6, 7], 0, HashRef], # 8
  [HashLiteral, {sigil: "%", symbol: h}, [2, 8], 8, Hash], # 9
  [Assign, ~, [5, 9], 9, List, 4, true], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2, 3], 10, Scalar, 10, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [13, 3], 11, Scalar, 11, true], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2, 16], 14, Scalar, 14, true], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Print, ~, [12, 15, 18, 19], 17, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 17]]} # 21
main::f: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: "on"}, ~, ~, Unknown], # 2
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: h}, ~, ~, Hash], # 3
  [PadAccess, {sigil: $, symbol: k}, ~, ~, Unknown], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], ~, Scalar, 5], # 6
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 7
  [TernaryExpr, ~, [2, 6, 7], ~, Unknown], # 8
  [Constant, {const_type: string, value: v}, ~, ~, Str], # 9
  [And, ~, [2, 6], ~, Unknown], # 10
  [If, ~, [0, 10], 0], # 11
  [Proj, {index: 0}, [11]], # 12
  [Subscript, {kind: hash}, [8, 9], 12, Scalar, 5, true], # 13
  [Proj, {index: 1}, [11]], # 14
  [Region, {head: 11}, [14, 13]], # 15
  [Phi, {predecessors: [14, 12], region: 15}, [1, 13], ~, Scalar], # 16
  [Phi, {memory: true, predecessors: [14, 12], region: 15}, [5, 13], ~, Unknown], # 17
  [Return, ~, [16], 15, ~, 17], # 18
  [ArgsSource, ~, ~, ~, Array], # 19
  [Assign, {record: true, targets: 2}, [4, 2, 19], ~, List], # 20
  [TernaryExpr, ~, [2, 3, 7], ~, Unknown]]} # 21
```

## An aggregate field whose default holds references

The default is the whole list, not its last item.

```perl
use v5.42; use experimental 'class';
class K { field %items = (r => { 7 => "V" }, s => [1, 2]); method g { $items{r}{7} . scalar($items{s}->@*) . join(",", sort keys %items) } }
print K->new->g, "\n";
```

```behavior
parses: yes
```

```output
V2r,s
```

```ir
K::__DEFAULT_0: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: r}, ~, ~, Str], # 1
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 2
  [Constant, {const_type: string, value: V}, ~, ~, Str], # 3
  [HashLiteral, ~, [2, 3], 0, HashRef], # 4
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [ArrayLiteral, ~, [6, 7], 4, ArrayRef], # 8
  [ArrayLiteral, ~, [1, 4, 5, 8], ~, List], # 9
  [MemStart], # 10
  [Return, {implicit: true}, [9], 8, ~, 10]]} # 11
K::g: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Hash], # 1
  [Constant, {const_type: string, value: r}, ~, ~, Str], # 2
  [Subscript, {kind: hash}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: "7"}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 8
  [Subscript, {kind: hash}, [1, 8], ~, Scalar, 6], # 9
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: K, sigil: "@", strict: true}, [9], 6, Array, 6, true], # 10
  [Count, ~, [10], ~, Int, 10], # 11
  [Coerce, {from_repr: Int, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [7, 12], ~, Str], # 13
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 14
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [1], ~, List, 10], # 15
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [15], ~, List, 10], # 16
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [14, 16], ~, Str, 10], # 17
  [Concat, ~, [13, 17], ~, Str], # 18
  [Return, {implicit: true}, [18], 10, ~, 10]]} # 19
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: K}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: g, package: main, param_names: [], want: list}, [5], 5, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: experimental, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A read at the top of a pass, stored later in it

The character is read before the position moves, and the position is passed to a call.

```perl
sub g { $_[1] + 2 }
sub run { my ($in) = @_; my $pos = 0; my $out = ""; while ($pos < length $in) { my $c = substr($in, $pos, 1); if ($c eq "@") { $pos = g($in, $pos); next } $out .= $c; $pos++ } return $out }
print run("ab\@xcd"), "\n";
```

```behavior
parses: yes
```

```output
abcd
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "ab@xcd"}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::run, package: main, param_names: [], want: list}, [2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, "Maybe[Boolean]"], # 7
  [Return, {implicit: true}, [1], 7, ~, 4]]} # 8
main::g: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Add, ~, [5, 6], ~, Num], # 7
  [Return, {implicit: true}, [7], 0, ~, 3]]} # 8
main::run: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: in}, ~, ~, Unknown, 2], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Assign, {targets: 1}, [3, 4], 0, List, 2, true], # 5
  [PadAccess, {sigil: $, symbol: pos}, ~, ~, Unknown, 5], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Assign, ~, [6, 7], 5, Int, 5, true], # 8
  [Loop, {bound: each}, [8], 8], # 9
  [Phi, {region: 9}, [1, 33], ~, Str], # 10
  [Proj, {index: 1}, [9]], # 11
  [Region, {head: 9}, [11]], # 12
  [Phi, {memory: true, region: 9}, [8, 34], ~, Scalar], # 13
  [Phi, {memory: true, region: 12}, [13], ~, Scalar], # 14
  [Return, ~, [10], 12, ~, 14], # 15
  [PadAccess, {sigil: $, symbol: in}, ~, ~, Unknown, 13], # 16
  [PadAccess, {sigil: $, symbol: pos}, ~, ~, Num, 13], # 17
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 18
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [16, 17, 18], ~, Str], # 19
  [Concat, ~, [10, 19], ~, Str], # 20
  [Increment, ~, [17], ~, Scalar], # 21
  [Proj, {index: 0}, [9]], # 22
  [Constant, {const_type: string, value: "@"}, ~, ~, Str], # 23
  [StrEq, ~, [19, 23], ~, Boolean], # 24
  [If, ~, [22, 24], 22], # 25
  [Proj, {index: 1}, [25]], # 26
  [Assign, ~, [17, 21], 26, Scalar, 13, true], # 27
  [Proj, {index: 0}, [25]], # 28
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: scalar}, [16, 17], 28, Num, 13, true], # 29
  [PadAccess, {sigil: $, symbol: pos}, ~, ~, Unknown, 29], # 30
  [Assign, ~, [30, 29], 29, Num, 29, true], # 31
  [Region, {head: 9}, [27, 31]], # 32
  [Phi, {predecessors: [26, 28], region: 32}, [20, 10], ~, Str], # 33
  [Phi, {memory: true, predecessors: [26, 28], region: 32}, [27, 31], ~, Scalar], # 34
  [Length, ~, [16], ~, Int], # 35
  [NumLt, ~, [17, 35], 9, Boolean]]} # 36
```

## An arm that loops before it nexts, beside a last

The arm runs an inner loop and then continues the outer one; the arm beside it leaves.

```perl
sub run { my ($in) = @_; my $pos = 0; my @err; my $out = "";
  while ($pos < length $in) {
    my $c = substr($in, $pos, 1);
    if ($c eq "@") {
      if (@err < 5) { push @err, $pos; my $s = $pos + 2; if ($s < length $in) { for my $k (1 .. 2) { $out .= "<$k>" } $pos = $s; next } }
      last;
    }
    $out .= $c; $pos++;
  }
  return "$out|@err" }
print run("ab\@xcd\@yz"), " ", run("ab\@x"), "\n";
```

```behavior
parses: yes
```

```output
ab<1><2>cd<1><2>z|2 6 ab|2
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "ab@xcd@yz"}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 11, name: main::run, package: main, param_names: [], want: list}, [2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: "ab@x"}, ~, ~, Str], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 11, name: main::run, package: main, param_names: [], want: list}, [7], 4, Str, 4, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [5, 6, 9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
main::run: {start: 0, returns: [41], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: each}, [0], 0], # 2
  [Phi, {region: 2}, [1, 54], ~, Str], # 3
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [MemStart], # 6
  [Phi, {memory: true, region: 2}, [6, 49], ~, Unknown], # 7
  [PadAccess, {sigil: "@", symbol: err}, ~, ~, Array], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Phi, {region: 2}, [9, 51], ~, Int], # 10
  [Proj, {index: 0}, [2]], # 11
  [PadAccess, {sigil: $, symbol: in}, ~, ~, Str], # 12
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 13
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [12, 10, 13], ~, Str], # 14
  [Constant, {const_type: string, value: "@"}, ~, ~, Str], # 15
  [StrEq, ~, [14, 15], ~, Boolean], # 16
  [If, ~, [11, 16], 11], # 17
  [Proj, {index: 0}, [17]], # 18
  [Count, ~, [8], ~, Int, 7], # 19
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 20
  [NumLt, ~, [19, 20], ~, Boolean], # 21
  [If, ~, [18, 21], 18], # 22
  [Proj, {index: 0}, [22]], # 23
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [8, 10], 23, Int, 7, true], # 24
  [Proj, {index: 1}, [22]], # 25
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 26
  [Add, ~, [10, 26], ~, Int], # 27
  [Length, ~, [12], ~, Int], # 28
  [NumLt, ~, [27, 28], ~, Boolean], # 29
  [If, ~, [24, 29], 24], # 30
  [Proj, {index: 1}, [30]], # 31
  [Region, {head: 22}, [25, 31]], # 32
  [Phi, {memory: true, predecessors: [25, 23], region: 32}, [7, 24], ~, Unknown], # 33
  [Proj, {index: 1}, [2]], # 34
  [Region, {head: 2}, [34, 32]], # 35
  [Phi, {memory: true, region: 35}, [7, 33], ~, Unknown], # 36
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 36], # 37
  [Coerce, {from_repr: Scalar, to_repr: Str}, [37], ~, Str], # 38
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [38, 8], ~, Str, 36], # 39
  [Concat, ~, [5, 39], ~, Str], # 40
  [Return, ~, [40], 35, ~, 36], # 41
  [NumLt, ~, [10, 28], 2, Boolean], # 42
  [Proj, {index: 1}, [17]], # 43
  [Proj, {index: 0}, [30]], # 44
  [Loop, {bound: entry}, [44], 44], # 45
  [Proj, {index: 1}, [45]], # 46
  [Region, {head: 45}, [46]], # 47
  [Region, {head: 2}, [43, 47]], # 48
  [Phi, {memory: true, predecessors: [43, 44], region: 48}, [7, 24], ~, Unknown], # 49
  [Add, ~, [10, 13], ~, Int], # 50
  [Phi, {predecessors: [43, 44], region: 48}, [50, 27], ~, Int], # 51
  [Concat, ~, [3, 14], ~, Str], # 52
  [Phi, {region: 45}, [3, 63], ~, Str], # 53
  [Phi, {predecessors: [43, 44], region: 48}, [52, 53], ~, Str], # 54
  [ArgsSource, ~, ~, ~, Array], # 55
  [Assign, {record: true, targets: 1}, [12, 55], ~, List], # 56
  [Constant, {const_type: string, value: "<"}, ~, ~, Str], # 57
  [Concat, ~, [53, 57], ~, Str], # 58
  [Phi, {region: 45}, [13, 64], ~, Int], # 59
  [Coerce, {from_repr: Int, to_repr: Str}, [59], ~, Str], # 60
  [Concat, ~, [58, 60], ~, Str], # 61
  [Constant, {const_type: string, value: ">"}, ~, ~, Str], # 62
  [Concat, ~, [61, 62], ~, Str], # 63
  [Add, ~, [59, 13], ~, Int], # 64
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 65
  [NumGt, ~, [65, 59], 45, Boolean], # 66
  [Proj, {index: 0}, [45]]]} # 67
```

## An eval body that writes an outer lexical, then dies

The store made before the die survives it.

```perl
sub f { my $n = 0; eval { for my $x (@_) { $n = $x; die "d\n" if $x eq "b" } }; return $n }
print f("a", "b", "c"), "\n";
```

```behavior
parses: yes
```

```output
b
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [2, 3, 4], 0, Unknown, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
main::f: {start: 0, returns: [35], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown, 1], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Assign, ~, [2, 3], 0, Int, 1, true], # 4
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 4], # 5
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 6
  [EntryWrite, ~, [5, 6], 4, Unknown, 4, true], # 7
  [Loop, {bound: entry}, [7], 7], # 8
  [Phi, {memory: true, region: 8}, [7, 20], ~, Unknown], # 9
  [Proj, {index: 1}, [8]], # 10
  [Region, {head: 8}, [10]], # 11
  [Phi, {memory: true, region: 11}, [9], ~, Unknown], # 12
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 12], # 13
  [EntryWrite, ~, [13, 6], 11, Unknown, 12, true], # 14
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown, 9], # 15
  [ArgsSource, ~, ~, ~, Array], # 16
  [Phi, {region: 8}, [3, 38], ~, Int], # 17
  [Subscript, {kind: array}, [16, 17], ~, Scalar, 9], # 18
  [Proj, {index: 0}, [8]], # 19
  [Assign, ~, [15, 18], 19, Scalar, 9, true], # 20
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 20], # 21
  [Constant, {const_type: string, value: "d\n"}, ~, ~, Str], # 22
  [Coerce, {from_repr: Unknown, to_repr: Str}, [18], ~, Str], # 23
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 24
  [StrEq, ~, [23, 24], ~, Boolean], # 25
  [If, ~, [20, 25], 20], # 26
  [Proj, {index: 0}, [26]], # 27
  [Unwind, {eval_id: 1, file: "/tmp/mvrHQew3rs/case.pl", line: 1}, [22], 27, ~, 20], # 28
  [Exc, ~, [28]], # 29
  [Region, {catch: true, eval_id: 1}, [29]], # 30
  [EntryWrite, ~, [21, 29], 30, Unknown, 20, true], # 31
  [Region, {eval_entry: 4, eval_id: 1}, [14, 31]], # 32
  [Phi, {memory: true, region: 32}, [14, 31], ~, Unknown], # 33
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown, 33], # 34
  [Return, ~, [34], 32, ~, 33], # 35
  [Count, ~, [16], ~, Int, 7], # 36
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 37
  [Add, ~, [17, 37], ~, Int], # 38
  [Count, ~, [16], ~, Int, 9], # 39
  [NumGt, ~, [39, 17], 8, Boolean], # 40
  [Proj, {index: 1}, [26]], # 41
  [Region, {head: 26}, [28, 41]]]} # 42
```

## A try body that writes an outer lexical beside a catch that goes on

After the die the variable holds what the body stored by then.

```perl
use v5.42; no warnings;
sub f ($d) { my $x = 0; try { $x = 1; die "no\n" if $d; $x = 3 } catch ($e) { print "c" } return $x }
print f(0), f(1), "\n";
```

```behavior
parses: yes
```

```output
c31
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2], 0, Unknown, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [6], 4, Unknown, 4, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [5, 8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7]]} # 11
main::f: {start: 0, returns: [40], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 2], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Assign, ~, [3, 4], 0, Int, 2, true], # 5
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 5], # 6
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 5], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Assign, ~, [7, 8], 5, Int, 5, true], # 9
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 9], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [Parameter, {index: 0, name: $d, sigil: $}, ~, ~, Unknown], # 12
  [If, ~, [9, 12], 9], # 13
  [Proj, {index: 1}, [13]], # 14
  [Constant, {const_type: string, value: "no\n"}, ~, ~, Str], # 15
  [Proj, {index: 0}, [13]], # 16
  [Unwind, {eval_id: 1, file: "/tmp/mvrHQew3rs/case.pl", line: 2}, [15], 16, ~, 9], # 17
  [Region, {head: 13}, [14, 17]], # 18
  [Assign, ~, [10, 11], 18, Int, 9, true], # 19
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 19], # 20
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 21
  [EntryWrite, ~, [20, 21], 19, Unknown, 19, true], # 22
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 9], # 23
  [Exc, ~, [17]], # 24
  [Region, {catch: true, eval_id: 1}, [24]], # 25
  [EntryWrite, ~, [23, 24], 25, Unknown, 9, true], # 26
  [Region, {eval_entry: 5, eval_id: 1}, [22, 26]], # 27
  [Phi, {memory: true, region: 27}, [22, 26], ~, Unknown], # 28
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 27, Scalar, 28], # 29
  [EntryWrite, ~, [1, 6], 29, Unknown, 28, true], # 30
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 30], # 31
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 32
  [Phi, {region: 27}, [8, 32], ~, "Maybe[Int]"], # 33
  [If, ~, [30, 33], 30], # 34
  [Proj, {index: 0}, [34]], # 35
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 36
  [Proj, {index: 1}, [34]], # 37
  [Print, ~, [36], 37, "Maybe[Boolean]"], # 38
  [Region, {head: 34}, [35, 38]], # 39
  [Return, ~, [31], 39, ~, 30], # 40
  [Phi, {predecessors: [35, 37], region: 39}, [11, 38], ~, Scalar]]} # 41
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: unimport, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
```

## A sorted array whose iterator a method writes

The method writes `$_[1]`, which is the element the foreach aliases.

```perl
package O { sub m { $_[1] = uc $_[1] if $_[1] eq "b" } }
my @n = sort qw(c b a); for my $x (@n) { O->m($x) } print "@n\n";
```

```behavior
parses: yes
```

```output
a B c
```

```ir
O::m: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 6
  [StrEq, ~, [5, 6], ~, Boolean], # 7
  [Call, {dispatch_kind: builtin, name: uc, param_names: []}, [4], ~, Str], # 8
  [And, ~, [7, 8], ~, Scalar], # 9
  [If, ~, [0, 7], 0], # 10
  [Proj, {index: 1}, [10]], # 11
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 12
  [Proj, {index: 0}, [10]], # 13
  [Assign, ~, [12, 8], 13, Str, 3, true], # 14
  [Region, {head: 10}, [11, 14]], # 15
  [Phi, {memory: true, predecessors: [11, 13], region: 15}, [3, 14], ~, Unknown], # 16
  [Return, {implicit: true}, [9], 15, ~, 16]]} # 17
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {memory: true, region: 3}, [2, 34], ~, Unknown], # 4
  [Proj, {index: 1}, [3]], # 5
  [Region, {head: 3}, [5]], # 6
  [Phi, {memory: true, region: 6}, [4], ~, Unknown], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 7], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 12
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [10, 11, 12], ~, List], # 13
  [ArrayLiteral, {sigil: "@", symbol: "n"}, [13], ~, Array], # 14
  [PostfixDeref, {sigil: "@"}, [14], ~, Array, 7], # 15
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [9, 15], ~, Str, 7], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [Print, ~, [18], 6, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [1], 19, ~, 7], # 20
  [Count, ~, [14], ~, Int, 4], # 21
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 22
  [Phi, {region: 3}, [22, 36], ~, Int], # 23
  [NumGt, ~, [21, 23], 3, Boolean], # 24
  [Proj, {index: 0}, [3]], # 25
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 4], # 26
  [Subscript, {kind: array}, [14, 23], ~, Scalar, 4], # 27
  [Assign, ~, [26, 27], 25, Scalar, 4, true], # 28
  [Subscript, {kind: array}, [14, 23], ~, Scalar], # 29
  [Constant, {const_type: string, value: O}, ~, ~, Str], # 30
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 28], # 31
  [Call, {class_name: O, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: m, package: main, param_names: [], want: void}, [30, 31], 28, Scalar, 28, true], # 32
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 32], # 33
  [Assign, {if_changed: true}, [29, 33], 32, Unknown, 32, true], # 34
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 35
  [Add, ~, [23, 35], ~, Int], # 36
  [Count, ~, [14], ~, Int, 2]]} # 37
```

## A slice of an array made in a loop body

The array is fresh each pass and reaches the slice through a merge.

```perl
sub f { my %idom = (a => 1, b => 2, c => 3); my $out = "";
  for my $k (qw(x y)) { my @p = grep { exists $idom{$_} } qw(a b c); next unless @p; my $n = $p[0]; for my $q (@p[1 .. $#p]) { $n .= $q } $out .= "$k$n " }
  $out }
print f(), "\n";
```

```behavior
parses: yes
```

```output
xabc yabc 
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 37], ~, Str], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [MemStart], # 6
  [Return, {implicit: true}, [3], 5, ~, 6], # 7
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 9
  [ArrayLiteral, ~, [8, 9], ~, Array], # 10
  [Count, ~, [10], ~, Int, 6], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Phi, {region: 2}, [12, 61], ~, Int], # 13
  [NumGt, ~, [11, 13], 2, Boolean], # 14
  [Proj, {index: 0}, [2]], # 15
  [Subscript, {kind: array}, [10, 13], ~, Str, 6], # 16
  [Concat, ~, [3, 16], ~, Str], # 17
  [ArrayLiteral, ~, ~, ~, Array], # 18
  [Loop, {bound: entry}, [15], 15], # 19
  [Phi, {region: 19}, [18, 58], ~, Array], # 20
  [Subscript, {kind: array}, [20, 12], ~, Scalar, 6], # 21
  [Proj, {index: 1}, [19]], # 22
  [Region, {head: 19}, [22]], # 23
  [Count, ~, [20], ~, Int, 6], # 24
  [If, ~, [23, 24], 23], # 25
  [Proj, {index: 0}, [25]], # 26
  [Loop, {bound: entry}, [26], 26], # 27
  [Phi, {region: 27}, [21, 65], ~, Scalar], # 28
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 29
  [Concat, ~, [17, 29], ~, Str], # 30
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 31
  [Concat, ~, [30, 31], ~, Str], # 32
  [Proj, {index: 1}, [25]], # 33
  [Proj, {index: 1}, [27]], # 34
  [Region, {head: 27}, [34]], # 35
  [Region, {head: 25}, [33, 35]], # 36
  [Phi, {predecessors: [33, 26], region: 36}, [3, 32], ~, Str], # 37
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 38
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 39
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 40
  [ArrayLiteral, ~, [38, 39, 40], ~, List], # 41
  [Count, ~, [41], ~, Int, 6], # 42
  [Phi, {region: 19}, [12, 63], ~, Int], # 43
  [Subscript, {kind: array}, [41, 43], ~, Str, 6], # 44
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 45
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 46
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 47
  [HashLiteral, {sigil: "%", symbol: idom}, [38, 45, 39, 46, 40, 47], ~, Hash], # 48
  [Exists, {kind: hash}, [48, 44], ~, Boolean, 6], # 49
  [Subtract, ~, [24, 45], ~, Int], # 50
  [Range, ~, [45, 50], ~, List], # 51
  [Slice, {kind: array}, [51, 20], ~, List], # 52
  [ArrayLiteral, ~, [52], ~, Array], # 53
  [Count, ~, [53], ~, Int, 6], # 54
  [Phi, {region: 27}, [12, 66], ~, Int], # 55
  [Subscript, {kind: array}, [53, 55], ~, Scalar, 6], # 56
  [NumGt, ~, [42, 43], 19, Boolean], # 57
  [ListAppend, {collector: grep}, [20, 44, 49], ~, Array], # 58
  [NumGt, ~, [54, 55], 27, Boolean], # 59
  [Coerce, {from_repr: Unknown, to_repr: Str}, [56], ~, Str], # 60
  [Add, ~, [13, 45], ~, Int], # 61
  [Proj, {index: 0}, [19]], # 62
  [Add, ~, [43, 45], ~, Int], # 63
  [Coerce, {from_repr: Scalar, to_repr: Str}, [28], ~, Str], # 64
  [Concat, ~, [64, 60], ~, Str], # 65
  [Add, ~, [55, 45], ~, Int], # 66
  [Proj, {index: 0}, [27]]]} # 67
```

## A slice of a dereferenced array and hash

A slice through a reference keeps its brackets: `$r->@[...]` and `$h->@{...}`.

```perl
use v5.42;
sub f ($r, $h) { my @a = $r->@[1, 2]; my @b = $h->@{qw(x y)}; return "@a|@b" }
print f([5, 6, 7], { x => 1, y => 2 }), "\n";
```

```behavior
parses: yes
```

```output
6 7|1 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 4
  [ArrayLiteral, ~, [2, 3, 4], 0, ArrayRef], # 5
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 8
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 9
  [HashLiteral, ~, [6, 7, 8, 9], 5, HashRef], # 10
  [MemStart], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [5, 10], 10, Str, 11, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [13, 14], 12, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 12]]} # 16
main::f: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 1], # 2
  [Coerce, {from_repr: Scalar, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Parameter, {index: 0, name: $r, sigil: $}, ~, ~, Unknown], # 6
  [Slice, {kind: array}, [4, 5, 6], ~, List], # 7
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [3, 7], ~, Str, 1], # 8
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 12
  [Parameter, {index: 1, name: $h, sigil: $}, ~, ~, Unknown], # 13
  [Slice, {kind: hash}, [11, 12, 13], ~, List], # 14
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [3, 14], ~, Str, 1], # 15
  [Concat, ~, [10, 15], ~, Str], # 16
  [Return, ~, [16], 0, ~, 1], # 17
  [ArrayLiteral, {sigil: "@", symbol: b}, [14], ~, Array], # 18
  [ArrayLiteral, {sigil: "@", symbol: a}, [7], ~, Array]]} # 19
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## A slice of an array field

A method slices its own array field.

```perl
use v5.42; use experimental 'class';
class K { field @f = (4, 5, 6); method s { my @x = @f[0, 2]; "@x" } }
print K->new->s, "\n";
```

```behavior
parses: yes
```

```output
4 6
```

```ir
K::__DEFAULT_0: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, Array], # 4
  [MemStart], # 5
  [Return, ~, [4], 0, ~, 5]]} # 6
K::s: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 1], # 2
  [Coerce, {from_repr: Scalar, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Array], # 6
  [Slice, {kind: array}, [4, 5, 6], ~, List], # 7
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [3, 7], ~, Str, 1], # 8
  [Return, {implicit: true}, [8], 0, ~, 1], # 9
  [ArrayLiteral, {sigil: "@", symbol: x}, [7], ~, Array]]} # 10
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: K}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: s, package: main, param_names: [], want: list}, [5], 5, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: experimental, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A sort block reading a hash of its sub

The comparator reads an aggregate its enclosing sub filled.

```perl
sub order { my @blocks = @_; my %rpo; my $i = 0; $rpo{$_} = $i++ for reverse @blocks; return join ",", sort { $rpo{$a} <=> $rpo{$b} } @blocks }
print order(qw(x y z)), " ", order(qw(p q)), "\n";
```

```behavior
parses: yes
```

```output
z,y,x q,p
```

```ir
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::order, package: main, param_names: [], want: list}, [2, 3, 4], 0, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: p}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: q}, ~, ~, Str], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::order, package: main, param_names: [], want: list}, [9, 10], 6, Str, 6, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [7, 8, 12, 13], 11, "Maybe[Boolean]"], # 14
  [Return, {implicit: true}, [1], 14, ~, 11]]} # 15
main::order: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: "%", symbol: rpo}, ~, ~, Hash, 3], # 4
  [HashLiteral, ~, ~, ~, Hash], # 5
  [Assign, ~, [4, 5], 0, List, 3, true], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Proj, {index: 1}, [7]], # 8
  [Region, {head: 7}, [8]], # 9
  [Phi, {memory: true, region: 7}, [6, 27], ~, List], # 10
  [Phi, {memory: true, region: 9}, [10], ~, List], # 11
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::order::__SORTCMP__:1, sort_package: main, want: list}, [2], 9, List, 11, true], # 12
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 12], ~, Str, 12], # 13
  [Return, ~, [13], 12, ~, 12], # 14
  [Call, {dispatch_kind: builtin, name: reverse, param_names: []}, [2], ~, List, 6], # 15
  [ArrayLiteral, ~, [15], ~, Array], # 16
  [Count, ~, [16], ~, Int, 6], # 17
  [Count, ~, [16], ~, Int, 10], # 18
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 19
  [Phi, {region: 7}, [19, 29], ~, Int], # 20
  [NumGt, ~, [18, 20], 7, Boolean], # 21
  [Proj, {index: 0}, [7]], # 22
  [PadAccess, {shared: 1, sigil: "%", symbol: rpo}, ~, ~, Hash], # 23
  [Subscript, {kind: array}, [16, 20], ~, Scalar, 10], # 24
  [Subscript, {kind: hash}, [23, 24], ~, Scalar], # 25
  [Phi, {region: 7}, [19, 30], ~, Int], # 26
  [Assign, ~, [25, 26], 22, Int, 10, true], # 27
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 28
  [Add, ~, [20, 28], ~, Int], # 29
  [Add, ~, [26, 28], ~, Int]]} # 30
main::order::__SORTCMP__:1: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "%", symbol: rpo}, ~, ~, Hash], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: a}, ~, ~, Scalar, 2], # 3
  [Subscript, {kind: hash}, [1, 3], ~, Scalar, 2], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [EntryDef, {package: main, sigil: $, symbol: b}, ~, ~, Scalar, 2], # 6
  [Subscript, {kind: hash}, [1, 6], ~, Scalar, 2], # 7
  [Coerce, {from_repr: Scalar, to_repr: Num}, [7], ~, Num], # 8
  [NumCmp, ~, [5, 8], ~, Int], # 9
  [Return, {implicit: true}, [9], 0, ~, 2]]} # 10
```

## An anonymous sub with a slurpy parameter

The anon sub takes a leading scalar and the rest of its arguments as an array.

```perl
use v5.42;
sub f { my @seen; my $mk = sub ($id, @rest) { push @seen, "$id:@rest"; return scalar @rest }; my $n = $mk->(1, 2, 3) + $mk->(4); return "$n @seen" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
2 1:2 3 4:
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [PadAccess, {shared: 1, sigil: "@", symbol: seen}, ~, ~, Array], # 4
  [MemStart], # 5
  [PadAccess, {shared: 1, sigil: "@", symbol: seen}, ~, ~, Array, 5], # 6
  [ArrayLiteral, ~, ~, ~, Array], # 7
  [Assign, ~, [6, 7], 0, List, 5, true], # 8
  [MakeCell, {captured_written: false, cell_name: "@seen"}, [4], 8, Ref, 8, true], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f::__ANON__:2:3, package: main, param_names: [], want: scalar}, [1, 2, 3], 9, Int, 9, true], # 10
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f::__ANON__:2:3, package: main, param_names: [], want: scalar}, [11], 10, Int, 10, true], # 12
  [Add, ~, [10, 12], ~, Int], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 12], # 17
  [Coerce, {from_repr: Scalar, to_repr: Str}, [17], ~, Str], # 18
  [PadAccess, {shared: 1, sigil: "@", symbol: seen}, ~, ~, Array, 12], # 19
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [18, 19], ~, Str, 12], # 20
  [Concat, ~, [16, 20], ~, Str], # 21
  [Return, ~, [21], 12, ~, 12], # 22
  [AnonSub, {captures: ["@seen"], name: main::f::__ANON__:2:3}, [9], ~, CodeRef]]} # 23
main::f::__ANON__:2:3: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Parameter, {index: 1, name: "@rest", sigil: "@"}, ~, ~, Array], # 1
  [PadAccess, {shared: 1, sigil: "@", symbol: seen}, ~, ~, Array], # 2
  [Parameter, {index: 0, name: $id, sigil: $}, ~, ~, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: ":"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [MemStart], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 7], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [9, 1], ~, Str, 7], # 10
  [Concat, ~, [6, 10], ~, Str], # 11
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 11], 0, Int, 7, true], # 12
  [Count, ~, [1], ~, Int, 12], # 13
  [Return, ~, [13], 12, ~, 12]]} # 14
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## A slice of a referenced field, grepped

grep aliases its list, so perl flags the slice modifiable; it is still a postfix slice.

```perl
use v5.42; use experimental 'class';
class K { field $r = [3, 4, 5, 6]; method s { my @x = grep { $_ > 3 } $r->@[0 .. $#{ $r } - 1]; "@x" } }
print K->new->s, "\n";
```

```behavior
parses: yes
```

```output
4 5
```

```ir
K::__DEFAULT_0: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 4
  [ArrayLiteral, ~, [1, 2, 3, 4], ~, ArrayRef], # 5
  [MemStart], # 6
  [Return, ~, [5], 0, ~, 6]]} # 7
K::s: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 1], # 2
  [Coerce, {from_repr: Scalar, to_repr: Str}, [2], ~, Str], # 3
  [ArrayLiteral, ~, ~, ~, Array], # 4
  [Loop, {bound: entry}, [0], 0], # 5
  [Phi, {region: 5}, [4, 28], ~, Array], # 6
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [3, 6], ~, Str, 1], # 7
  [Proj, {index: 1}, [5]], # 8
  [Region, {head: 5}, [8]], # 9
  [Return, {implicit: true}, [7], 9, ~, 1], # 10
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 11
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, ArrayRef, 1], # 12
  [PostfixDeref, {sigil: "@"}, [12], ~, Array, 1], # 13
  [Count, ~, [13], ~, Int, 1], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Subtract, ~, [14, 15], ~, Int], # 16
  [Subtract, ~, [16, 15], ~, Int], # 17
  [Range, ~, [11, 17], ~, List], # 18
  [Slice, {kind: array}, [18, 12], ~, List], # 19
  [Count, ~, [19], ~, Int, 1], # 20
  [Phi, {region: 5}, [11, 29], ~, Int], # 21
  [NumGt, ~, [20, 21], 5, Boolean], # 22
  [Proj, {index: 0}, [5]], # 23
  [Subscript, {kind: array}, [19, 21], ~, Scalar, 1], # 24
  [Coerce, {from_repr: Scalar, to_repr: Num}, [24], ~, Num], # 25
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 26
  [NumGt, ~, [25, 26], ~, Boolean], # 27
  [ListAppend, {collector: grep}, [6, 24, 27], ~, Array], # 28
  [Add, ~, [21, 15], ~, Int]]} # 29
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: K}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: s, package: main, param_names: [], want: list}, [5], 5, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: experimental, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A list assign of parameters a call also takes

Parameters passed to a call live in memory; so do targets passed on to one.

```perl
use v5.42; package O { sub m { $_[1] } }
sub f ($l, $r, $v) { O->m($l); O->m($r); my ($c, $j); if ($v) { ($c, $j) = ($l, $r) } else { ($c, $j) = ($r, $l) } O->m($c, $j); return "$c>$j" }
print f(1, 2, 1), f(1, 2, 0), "\n";
```

```behavior
parses: yes
```

```output
1>22>1
```

```ir
O::m: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Return, {implicit: true}, [4], 0, ~, 3]]} # 5
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2, 3, 2], 0, Str, 4, true], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2, 3, 7], 5, Str, 5, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [6, 9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
main::f: {start: 0, returns: [40], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: O}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: l}, ~, ~, Unknown, 2], # 3
  [Parameter, {index: 0, name: $l, sigil: $}, ~, ~, Unknown], # 4
  [Assign, ~, [3, 4], 0, Unknown, 2, true], # 5
  [PadAccess, {sigil: $, symbol: r}, ~, ~, Unknown, 5], # 6
  [Parameter, {index: 1, name: $r, sigil: $}, ~, ~, Unknown], # 7
  [Assign, ~, [6, 7], 5, Unknown, 5, true], # 8
  [PadAccess, {sigil: $, symbol: l}, ~, ~, Unknown, 8], # 9
  [Call, {class_name: O, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: m, package: main, param_names: [], want: void}, [1, 9], 8, Scalar, 8, true], # 10
  [PadAccess, {sigil: $, symbol: r}, ~, ~, Unknown, 10], # 11
  [Call, {class_name: O, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: m, package: main, param_names: [], want: void}, [1, 11], 10, Scalar, 10, true], # 12
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 12], # 13
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 14
  [Assign, ~, [13, 14], 12, Undef, 12, true], # 15
  [PadAccess, {sigil: $, symbol: j}, ~, ~, Unknown, 15], # 16
  [Assign, ~, [16, 14], 15, Undef, 15, true], # 17
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 17], # 18
  [PadAccess, {sigil: $, symbol: j}, ~, ~, Unknown, 17], # 19
  [PadAccess, {sigil: $, symbol: l}, ~, ~, Unknown, 17], # 20
  [PadAccess, {sigil: $, symbol: r}, ~, ~, Unknown, 17], # 21
  [Parameter, {index: 2, name: $v, sigil: $}, ~, ~, Unknown], # 22
  [If, ~, [17, 22], 17], # 23
  [Proj, {index: 0}, [23]], # 24
  [Assign, {targets: 2}, [18, 19, 20, 21], 24, List, 17, true], # 25
  [Proj, {index: 1}, [23]], # 26
  [Assign, {targets: 2}, [18, 19, 21, 20], 26, List, 17, true], # 27
  [Region, {head: 23}, [25, 27]], # 28
  [Phi, {memory: true, predecessors: [24, 26], region: 28}, [25, 27], ~, List], # 29
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 29], # 30
  [PadAccess, {sigil: $, symbol: j}, ~, ~, Unknown, 29], # 31
  [Call, {class_name: O, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: m, package: main, param_names: [], want: void}, [1, 30, 31], 28, Scalar, 29, true], # 32
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Str, 32], # 33
  [Coerce, {from_repr: Unknown, to_repr: Str}, [33], ~, Str], # 34
  [Constant, {const_type: string, value: ">"}, ~, ~, Str], # 35
  [Concat, ~, [34, 35], ~, Str], # 36
  [PadAccess, {sigil: $, symbol: j}, ~, ~, Str, 32], # 37
  [Coerce, {from_repr: Unknown, to_repr: Str}, [37], ~, Str], # 38
  [Concat, ~, [36, 38], ~, Str], # 39
  [Return, ~, [39], 32, ~, 32], # 40
  [Phi, {predecessors: [24, 26], region: 28}, [20, 21], ~, Unknown], # 41
  [Phi, {predecessors: [24, 26], region: 28}, [21, 20], ~, Unknown]]} # 42
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## A list assign of element reads, the container written after

The targets keep the values read at the assign.

```perl
sub f { my $r = [[1, 2]]; my ($lv, $val) = ($r->[0][0], $r->[0][1]); $r->[0][0] = 9; return "$lv $val $r->[0][0]" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
1 2 9
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [26], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [ArrayLiteral, ~, [1, 2], 0, ArrayRef], # 3
  [ArrayLiteral, ~, [3], 3, ArrayRef], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [4, 5], ~, ArrayRef], # 6
  [MemStart], # 7
  [Subscript, {kind: array}, [6, 5], 4, Scalar, 7, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Subscript, {kind: array}, [6, 1], 8, Scalar, 8, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [11, 13], ~, Str], # 14
  [Concat, ~, [14, 10], ~, Str], # 15
  [Subscript, {kind: array}, [4, 5], 12, ArrayRef, 12], # 16
  [ArrayLiteral, ~, ~, 16, ArrayRef], # 17
  [DefinedOr, ~, [16, 17], ~, ArrayRef], # 18
  [Subscript, {kind: array}, [18, 5], ~, Scalar], # 19
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 20
  [Assign, ~, [6, 18], 17, ArrayRef, 12, true], # 21
  [Assign, ~, [19, 20], 21, Int, 21, true], # 22
  [Subscript, {kind: array}, [6, 5], 22, Scalar, 22, true], # 23
  [Coerce, {from_repr: Unknown, to_repr: Str}, [23], ~, Str], # 24
  [Concat, ~, [15, 24], ~, Str], # 25
  [Return, ~, [25], 23, ~, 23], # 26
  [PadAccess, {sigil: $, symbol: lv}, ~, ~, Unknown], # 27
  [PadAccess, {sigil: $, symbol: val}, ~, ~, Unknown], # 28
  [Assign, {record: true, targets: 2}, [27, 28, 8, 12], ~, List]]} # 29
```

## A list assign from a call into declared scalars

The call has no positions, but the targets hold what it returned.

```perl
sub g { (5, 2) }
sub f { my ($lo, $used); ($lo, $used) = g(); $used += 1; "$lo $used" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
5 3
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: lo}, ~, ~, Str], # 1
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 2
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 3
  [Concat, ~, [2, 3], ~, Str], # 4
  [PadAccess, {sigil: $, symbol: used}, ~, ~, Num], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [Add, ~, [5, 6], ~, Num], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Concat, ~, [4, 8], ~, Str], # 9
  [MemStart], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: list}, ~, 0, List, 10, true], # 11
  [Assign, {targets: 2}, [1, 5, 11], 11, List, 11, true], # 12
  [Return, {implicit: true}, [9], 12, ~, 12]]} # 13
main::g: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [ArrayLiteral, ~, [1, 2], ~, List], # 3
  [Coerce, {from_repr: List, to_repr: Scalar}, [2], ~, Scalar], # 4
  [MemStart], # 5
  [Return, {implicit: true}, [3, 4], 0, ~, 5]]} # 6
```

## One declared scalar from a call, in an arm

`($lo) = g()` takes the first element, not the list.

```perl
sub g { (5, 2) }
sub f { my $lo = 0; if ($_[0]) { ($lo) = g(); } "$lo" }
print f(1), f(0), "\n";
```

```behavior
parses: yes
```

```output
50
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [6], 4, Str, 4, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [5, 8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7]]} # 11
main::f: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [PadAccess, {sigil: $, symbol: lo}, ~, ~, Unknown], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [3, 1], ~, Scalar, 4], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 1}, [6]], # 7
  [Proj, {index: 0}, [6]], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: list}, ~, 8, List, 4, true], # 9
  [Assign, {targets: 1}, [2, 9], 9, List, 9, true], # 10
  [Region, {head: 6}, [7, 10]], # 11
  [Phi, {predecessors: [7, 8], region: 11}, [1, 2], ~, Unknown], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Phi, {memory: true, predecessors: [7, 8], region: 11}, [4, 10], ~, Unknown], # 14
  [Return, {implicit: true}, [13], 11, ~, 14]]} # 15
main::g: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [ArrayLiteral, ~, [1, 2], ~, List], # 3
  [Coerce, {from_repr: List, to_repr: Scalar}, [2], ~, Scalar], # 4
  [MemStart], # 5
  [Return, {implicit: true}, [3, 4], 0, ~, 5]]} # 6
```

## A list assign from a call in one arm, a list in the other, inside a loop

Both arms assign the pair the loop then reads.

```perl
sub esc { return (ord($_[0][$_[1]]) + 100, 1) }
sub f {
    my @chars = split //, $_[0];
    my @ranges; my $j = 0;
    while ($j <= $#chars) {
        my $cc = $chars[$j];
        last if $cc eq ']';
        my ($lo, $lo_used);
        if ($cc eq '\\') { ($lo, $lo_used) = esc(\@chars, $j + 1); $lo_used += 1 }
        else { ($lo, $lo_used) = (ord($cc), 1) }
        my $k = $j + $lo_used;
        if (($chars[$k] // '') eq '-') { push @ranges, "$lo-" . ord($chars[$k + 1]); $j = $k + 2; next }
        push @ranges, $lo;
        $j = $k;
    }
    return "@ranges";
}
print f('a\\nb-d]'), "\n";
```

```behavior
parses: yes
```

```output
97 210 98-100
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "a\\nb-d]"}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 18, name: main::f, package: main, param_names: [], want: list}, [2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, "Maybe[Boolean]"], # 7
  [Return, {implicit: true}, [1], 7, ~, 4]]} # 8
main::esc: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [1, 4], ~, Scalar, 5], # 6
  [Subscript, {kind: array}, [3, 6], 0, Scalar, 5, true], # 7
  [Call, {dispatch_kind: builtin, name: ord, param_names: []}, [7], ~, Int], # 8
  [Constant, {const_type: integer, value: "100"}, ~, ~, Int], # 9
  [Add, ~, [8, 9], ~, Int], # 10
  [ArrayLiteral, ~, [10, 4], ~, List], # 11
  [Coerce, {from_repr: List, to_repr: Scalar}, [4], ~, Scalar], # 12
  [Return, ~, [11, 12], 7, ~, 7]]} # 13
main::f: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Constant, {const_type: regex, value: ""}, ~, ~, Regex], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Subscript, {kind: array}, [3, 4], ~, Scalar, 1], # 5
  [Call, {dispatch_kind: builtin, name: split, param_names: []}, [2, 5, 4], ~, List], # 6
  [ArrayLiteral, {sigil: "@", symbol: chars}, [6], 0, Array], # 7
  [Loop, {bound: each}, [7], 7], # 8
  [Phi, {memory: true, region: 8}, [1, 67], ~, Unknown], # 9
  [Proj, {index: 1}, [8]], # 10
  [Proj, {index: 0}, [8]], # 11
  [Phi, {region: 8}, [4, 70], ~, Unknown], # 12
  [Subscript, {kind: array}, [7, 12], ~, Scalar, 9], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 15
  [StrEq, ~, [14, 15], ~, Boolean], # 16
  [If, ~, [11, 16], 11], # 17
  [Proj, {index: 0}, [17]], # 18
  [Region, {head: 8}, [10, 18]], # 19
  [Phi, {memory: true, region: 19}, [9, 9], ~, Unknown], # 20
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 20], # 21
  [Coerce, {from_repr: Scalar, to_repr: Str}, [21], ~, Str], # 22
  [PadAccess, {sigil: "@", symbol: ranges}, ~, ~, Array], # 23
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [22, 23], ~, Str, 20], # 24
  [Return, ~, [24], 19, ~, 20], # 25
  [Count, ~, [7], ~, Int, 9], # 26
  [Ref, ~, [7], ~, ArrayRef], # 27
  [PadAccess, {sigil: $, symbol: lo_used}, ~, ~, Num], # 28
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 29
  [Add, ~, [28, 29], ~, Num], # 30
  [PadAccess, {sigil: $, symbol: lo}, ~, ~, Str], # 31
  [Add, ~, [12, 29], ~, Unknown], # 32
  [Proj, {index: 1}, [17]], # 33
  [Constant, {const_type: string, value: "\\"}, ~, ~, Str], # 34
  [StrEq, ~, [14, 34], ~, Boolean], # 35
  [If, ~, [33, 35], 33], # 36
  [Proj, {index: 0}, [36]], # 37
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::esc, package: main, param_names: [], want: list}, [27, 32], 37, List, 9, true], # 38
  [Assign, {targets: 2}, [31, 28, 38], 38, List, 38, true], # 39
  [Call, {dispatch_kind: builtin, name: ord, param_names: []}, [13], ~, Int], # 40
  [Proj, {index: 1}, [36]], # 41
  [Assign, {targets: 2}, [31, 28, 40, 29], 41, List, 9, true], # 42
  [Region, {head: 36}, [39, 42]], # 43
  [Phi, {predecessors: [37, 41], region: 43}, [30, 28], ~, Num], # 44
  [Add, ~, [12, 44], ~, Unknown], # 45
  [Phi, {memory: true, predecessors: [37, 41], region: 43}, [39, 42], ~, List], # 46
  [Subscript, {kind: array}, [7, 45], ~, Scalar, 46], # 47
  [Add, ~, [45, 29], ~, Unknown], # 48
  [Subscript, {kind: array}, [7, 48], ~, Scalar, 46], # 49
  [Subtract, ~, [26, 29], ~, Int], # 50
  [NumLe, ~, [12, 50], 8, Boolean], # 51
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 52
  [DefinedOr, ~, [47, 52], ~, Scalar], # 53
  [Call, {dispatch_kind: builtin, name: ord, param_names: []}, [49], ~, Int], # 54
  [Coerce, {from_repr: Unknown, to_repr: Str}, [31], ~, Str], # 55
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 56
  [Concat, ~, [55, 56], ~, Str], # 57
  [Concat, ~, [57, 54], ~, Str], # 58
  [Coerce, {from_repr: Unknown, to_repr: Str}, [53], ~, Str], # 59
  [StrEq, ~, [59, 56], ~, Boolean], # 60
  [If, ~, [43, 60], 43], # 61
  [Proj, {index: 0}, [61]], # 62
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [23, 58], 62, Int, 46, true], # 63
  [Proj, {index: 1}, [61]], # 64
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [23, 31], 64, Int, 46, true], # 65
  [Region, {head: 8}, [65, 63]], # 66
  [Phi, {memory: true, predecessors: [64, 62], region: 66}, [65, 63], ~, Int], # 67
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 68
  [Add, ~, [45, 68], ~, Unknown], # 69
  [Phi, {predecessors: [64, 62], region: 66}, [45, 69], ~, Unknown]]} # 70
```

## A split array passed by reference and pushed

The array a split fills is a container its reference and push both reach.

```perl
sub g { scalar @{$_[0]} }
sub f { my @c = split /,/, $_[0]; push @c, "z"; my $n = g(\@c); "$n @c" }
print f("a,b"), "\n";
```

```behavior
parses: yes
```

```output
3 a b z
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "a,b"}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, "Maybe[Boolean]"], # 7
  [Return, {implicit: true}, [1], 7, ~, 4]]} # 8
main::f: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: regex, value: ","}, ~, ~, Regex], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Call, {dispatch_kind: builtin, name: split, param_names: []}, [1, 5, 3], ~, List], # 6
  [ArrayLiteral, {sigil: "@", symbol: c}, [6], 0, Array], # 7
  [Ref, ~, [7], ~, ArrayRef], # 8
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 9
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [7, 9], 7, Int, 4, true], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: scalar}, [8], 10, Int, 10, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 11], # 15
  [Coerce, {from_repr: Scalar, to_repr: Str}, [15], ~, Str], # 16
  [PostfixDeref, {sigil: "@"}, [7], ~, Array, 11], # 17
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [16, 17], ~, Str, 11], # 18
  [Concat, ~, [14, 18], ~, Str], # 19
  [Return, {implicit: true}, [19], 11, ~, 11]]} # 20
main::g: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 1, package: main, sigil: "@", strict: false}, [4], 0, Array, 3, true], # 5
  [Count, ~, [5], ~, Int, 5], # 6
  [Return, {implicit: true}, [6], 5, ~, 5]]} # 7
```

## A catch that leaves the loop

A `last` in the catch block leaves the loop the try sits in.

```perl
use v5.42; no warnings;
sub g { die "no\n" if $_[0] == 3; return $_[0] * 2 }
sub f { my @out; my $ok = 1; for my $s (@_) { my $c; try { $c = g($s) } catch ($e) { $ok = 0; last } push @out, $c } return "$ok:@out" }
print f(1, 2, 3, 4), " ", f(1, 2), "\n";
```

```behavior
parses: yes
```

```output
0:2 4 1:2 4
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [2, 3, 4, 5], 0, Str, 6, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [2, 3], 7, Str, 7, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [8, 9, 11, 12], 10, "Maybe[Boolean]"], # 13
  [Return, {implicit: true}, [1], 13, ~, 10]]} # 14
main::f: {start: 0, returns: [50], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 5
  [MemStart], # 6
  [Phi, {memory: true, region: 3}, [6, 55], ~, Unknown], # 7
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 7], # 8
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 9
  [ArgsSource, ~, ~, ~, Array], # 10
  [Phi, {region: 3}, [2, 56], ~, Int], # 11
  [Proj, {index: 0}, [3]], # 12
  [Exists, {kind: array}, [10, 11], 12, Boolean, 7], # 13
  [Subscript, {kind: array}, [10, 11], ~, Scalar], # 14
  [Ref, ~, [14], ~, ScalarRef], # 15
  [TernaryExpr, ~, [13, 15, 9], 13, "Maybe[ScalarRef]"], # 16
  [Assign, ~, [8, 9], 16, Undef, 7, true], # 17
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 17], # 18
  [PostfixDeref, {sigil: $}, [16], ~, Scalar, 17], # 19
  [Subscript, {kind: array}, [10, 11], ~, Scalar, 17], # 20
  [TernaryExpr, ~, [13, 19, 20], ~, Scalar], # 21
  [Call, {dispatch_kind: direct, eval_id: 3, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::g, package: main, param_names: [], want: scalar}, [21], 17, Num, 17, true], # 22
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 22], # 23
  [Assign, ~, [23, 22], 22, Num, 22, true], # 24
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 24], # 25
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 26
  [EntryWrite, ~, [25, 26], 24, Unknown, 24, true], # 27
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 22], # 28
  [Exc, ~, [22]], # 29
  [Region, {catch: true, eval_id: 3}, [29]], # 30
  [EntryWrite, ~, [28, 29], 30, Unknown, 22, true], # 31
  [Region, {eval_entry: 17, eval_id: 3}, [27, 31]], # 32
  [Phi, {memory: true, region: 32}, [27, 31], ~, Unknown], # 33
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 32, Scalar, 33], # 34
  [EntryWrite, ~, [5, 18], 34, Unknown, 33, true], # 35
  [Phi, {region: 32}, [1, 9], ~, "Maybe[Int]"], # 36
  [If, ~, [35, 36], 35], # 37
  [Proj, {index: 1}, [37]], # 38
  [Region, {head: 3}, [4, 38]], # 39
  [Phi, {region: 39}, [1, 2], ~, Int], # 40
  [Coerce, {from_repr: Int, to_repr: Str}, [40], ~, Str], # 41
  [Constant, {const_type: string, value: ":"}, ~, ~, Str], # 42
  [Concat, ~, [41, 42], ~, Str], # 43
  [Phi, {memory: true, region: 39}, [7, 35], ~, Unknown], # 44
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 44], # 45
  [Coerce, {from_repr: Scalar, to_repr: Str}, [45], ~, Str], # 46
  [PadAccess, {sigil: "@", symbol: out}, ~, ~, Array], # 47
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [46, 47], ~, Str, 44], # 48
  [Concat, ~, [43, 48], ~, Str], # 49
  [Return, ~, [49], 39, ~, 44], # 50
  [Count, ~, [10], ~, Int, 7], # 51
  [NumGt, ~, [51, 11], 3, Boolean], # 52
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 35], # 53
  [Proj, {index: 0}, [37]], # 54
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [47, 53], 54, Int, 35, true], # 55
  [Add, ~, [11, 1], ~, Int], # 56
  [Count, ~, [10], ~, Int, 6]]} # 57
main::g: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [NumEq, ~, [5, 8], ~, Boolean], # 9
  [If, ~, [0, 9], 0], # 10
  [Proj, {index: 1}, [10]], # 11
  [Constant, {const_type: string, value: "no\n"}, ~, ~, Str], # 12
  [Proj, {index: 0}, [10]], # 13
  [Unwind, {file: "/tmp/mvrHQew3rs/case.pl", line: 2}, [12], 13, ~, 3], # 14
  [Region, {head: 10}, [11, 14]], # 15
  [Return, ~, [7], 15, ~, 3]]} # 16
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: unimport, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
```

## A catch that goes round the loop again

A `next` in the catch block skips the rest of the pass.

```perl
use v5.42; no warnings;
sub g { die "no\n" if $_[0] == 3; return $_[0] * 2 }
sub f { my @out; my $bad = 0; for my $s (@_) { my $c; try { $c = g($s) } catch ($e) { $bad++; next } push @out, $c } return "$bad:@out" }
print f(1, 2, 3, 4), "\n";
```

```behavior
parses: yes
```

```output
1:2 4 8
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [2, 3, 4, 5], 0, Str, 6, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7]]} # 11
main::f: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 61], ~, Int], # 3
  [Coerce, {from_repr: Int, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: ":"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [MemStart], # 7
  [Phi, {memory: true, region: 2}, [7, 57], ~, Unknown], # 8
  [Proj, {index: 1}, [2]], # 9
  [Region, {head: 2}, [9]], # 10
  [Phi, {memory: true, region: 10}, [8], ~, Unknown], # 11
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 11], # 12
  [Coerce, {from_repr: Scalar, to_repr: Str}, [12], ~, Str], # 13
  [PadAccess, {sigil: "@", symbol: out}, ~, ~, Array], # 14
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [13, 14], ~, Str, 11], # 15
  [Concat, ~, [6, 15], ~, Str], # 16
  [Return, ~, [16], 10, ~, 11], # 17
  [ArgsSource, ~, ~, ~, Array], # 18
  [Count, ~, [18], ~, Int, 8], # 19
  [Phi, {region: 2}, [1, 58], ~, Int], # 20
  [NumGt, ~, [19, 20], 2, Boolean], # 21
  [Proj, {index: 0}, [2]], # 22
  [Exists, {kind: array}, [18, 20], 22, Boolean, 8], # 23
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 24
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 8], # 25
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 26
  [Subscript, {kind: array}, [18, 20], ~, Scalar], # 27
  [Ref, ~, [27], ~, ScalarRef], # 28
  [TernaryExpr, ~, [23, 28, 26], 23, "Maybe[ScalarRef]"], # 29
  [Assign, ~, [25, 26], 29, Undef, 8, true], # 30
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 30], # 31
  [PostfixDeref, {sigil: $}, [29], ~, Scalar, 30], # 32
  [Subscript, {kind: array}, [18, 20], ~, Scalar, 30], # 33
  [TernaryExpr, ~, [23, 32, 33], ~, Scalar], # 34
  [Call, {dispatch_kind: direct, eval_id: 3, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::g, package: main, param_names: [], want: scalar}, [34], 30, Num, 30, true], # 35
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 35], # 36
  [Assign, ~, [36, 35], 35, Num, 35, true], # 37
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 37], # 38
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 39
  [EntryWrite, ~, [38, 39], 37, Unknown, 37, true], # 40
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 35], # 41
  [Exc, ~, [35]], # 42
  [Region, {catch: true, eval_id: 3}, [42]], # 43
  [EntryWrite, ~, [41, 42], 43, Unknown, 35, true], # 44
  [Region, {eval_entry: 30, eval_id: 3}, [40, 44]], # 45
  [Phi, {memory: true, region: 45}, [40, 44], ~, Unknown], # 46
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 45, Scalar, 46], # 47
  [EntryWrite, ~, [24, 31], 47, Unknown, 46, true], # 48
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 48], # 49
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 50
  [Phi, {region: 45}, [50, 26], ~, "Maybe[Int]"], # 51
  [If, ~, [48, 51], 48], # 52
  [Proj, {index: 0}, [52]], # 53
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [14, 49], 53, Int, 48, true], # 54
  [Proj, {index: 1}, [52]], # 55
  [Region, {head: 2}, [54, 55]], # 56
  [Phi, {memory: true, predecessors: [53, 55], region: 56}, [54, 48], ~, Unknown], # 57
  [Add, ~, [20, 50], ~, Int], # 58
  [Count, ~, [18], ~, Int, 7], # 59
  [Add, ~, [3, 50], ~, Int], # 60
  [Phi, {predecessors: [53, 55], region: 56}, [3, 60], ~, Int]]} # 61
main::g: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [NumEq, ~, [5, 8], ~, Boolean], # 9
  [If, ~, [0, 9], 0], # 10
  [Proj, {index: 1}, [10]], # 11
  [Constant, {const_type: string, value: "no\n"}, ~, ~, Str], # 12
  [Proj, {index: 0}, [10]], # 13
  [Unwind, {file: "/tmp/mvrHQew3rs/case.pl", line: 2}, [12], 13, ~, 3], # 14
  [Region, {head: 10}, [11, 14]], # 15
  [Return, ~, [7], 15, ~, 3]]} # 16
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: unimport, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
```

## A catch that returns from inside a loop

The catch names no error; the `$@` read where the eval ends has no reader.

```perl
use v5.42; no warnings;
sub g { die "no\n" if $_[0] == 3; return $_[0] * 2 }
sub f { my @out; for my $s (@_) { my $c; try { $c = g($s) } catch ($e) { return "R@out" } push @out, $c } return "@out" }
print f(1, 2, 3, 4), " ", f(1, 2), "\n";
```

```behavior
parses: yes
```

```output
R2 4 2 4
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [2, 3, 4, 5], 0, Str, 6, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [2, 3], 7, Str, 7, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [8, 9, 11, 12], 10, "Maybe[Boolean]"], # 13
  [Return, {implicit: true}, [1], 13, ~, 10]]} # 14
main::f: {start: 0, returns: [53], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: R}, ~, ~, Str], # 1
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 2
  [MemStart], # 3
  [Loop, {bound: entry}, [0], 0], # 4
  [Phi, {memory: true, region: 4}, [3, 58], ~, Unknown], # 5
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 5], # 6
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 7
  [ArgsSource, ~, ~, ~, Array], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Phi, {region: 4}, [9, 59], ~, Int], # 10
  [Proj, {index: 0}, [4]], # 11
  [Exists, {kind: array}, [8, 10], 11, Boolean, 5], # 12
  [Subscript, {kind: array}, [8, 10], ~, Scalar], # 13
  [Ref, ~, [13], ~, ScalarRef], # 14
  [TernaryExpr, ~, [12, 14, 7], 12, "Maybe[ScalarRef]"], # 15
  [Assign, ~, [6, 7], 15, Undef, 5, true], # 16
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 16], # 17
  [PostfixDeref, {sigil: $}, [15], ~, Scalar, 16], # 18
  [Subscript, {kind: array}, [8, 10], ~, Scalar, 16], # 19
  [TernaryExpr, ~, [12, 18, 19], ~, Scalar], # 20
  [Call, {dispatch_kind: direct, eval_id: 3, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::g, package: main, param_names: [], want: scalar}, [20], 16, Num, 16, true], # 21
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 21], # 22
  [Assign, ~, [22, 21], 21, Num, 21, true], # 23
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 23], # 24
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 25
  [EntryWrite, ~, [24, 25], 23, Unknown, 23, true], # 26
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 21], # 27
  [Exc, ~, [21]], # 28
  [Region, {catch: true, eval_id: 3}, [28]], # 29
  [EntryWrite, ~, [27, 28], 29, Unknown, 21, true], # 30
  [Region, {eval_entry: 16, eval_id: 3}, [26, 30]], # 31
  [Phi, {memory: true, region: 31}, [26, 30], ~, Unknown], # 32
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, 31, Scalar, 32], # 33
  [EntryWrite, ~, [2, 17], 33, Unknown, 32, true], # 34
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 34], # 35
  [Coerce, {from_repr: Scalar, to_repr: Str}, [35], ~, Str], # 36
  [PadAccess, {sigil: "@", symbol: out}, ~, ~, Array], # 37
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [36, 37], ~, Str, 34], # 38
  [Concat, ~, [1, 38], ~, Str], # 39
  [Proj, {index: 1}, [4]], # 40
  [Region, {head: 4}, [40]], # 41
  [Phi, {memory: true, region: 41}, [5], ~, Unknown], # 42
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 42], # 43
  [Coerce, {from_repr: Scalar, to_repr: Str}, [43], ~, Str], # 44
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [44, 37], ~, Str, 42], # 45
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 46
  [Phi, {region: 31}, [46, 7], ~, "Maybe[Int]"], # 47
  [If, ~, [34, 47], 34], # 48
  [Proj, {index: 1}, [48]], # 49
  [Region, ~, [49, 41]], # 50
  [Phi, {predecessors: [49, 41], region: 50}, [39, 45], ~, Str], # 51
  [Phi, {exits: true, memory: true, predecessors: [49, 41], region: 50}, [34, 42], ~, Unknown], # 52
  [Return, ~, [51], 50, ~, 52], # 53
  [Count, ~, [8], ~, Int, 5], # 54
  [NumGt, ~, [54, 10], 4, Boolean], # 55
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 34], # 56
  [Proj, {index: 0}, [48]], # 57
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [37, 56], 57, Int, 34, true], # 58
  [Add, ~, [10, 46], ~, Int], # 59
  [Count, ~, [8], ~, Int, 3]]} # 60
main::g: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [NumEq, ~, [5, 8], ~, Boolean], # 9
  [If, ~, [0, 9], 0], # 10
  [Proj, {index: 1}, [10]], # 11
  [Constant, {const_type: string, value: "no\n"}, ~, ~, Str], # 12
  [Proj, {index: 0}, [10]], # 13
  [Unwind, {file: "/tmp/mvrHQew3rs/case.pl", line: 2}, [12], 13, ~, 3], # 14
  [Region, {head: 10}, [11, 14]], # 15
  [Return, ~, [7], 15, ~, 3]]} # 16
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: unimport, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
```

## An if without else that stores and returns, ending a sub

The nested if is a short-circuit whose arm returns; the path that skipped it yields the condition.

```perl
my %t;
sub f { my ($c, $a, $b) = @_; if ($c) { if ($a && $b) { $t{$b} = $a; return } } }
my @r = map { scalar(f(@$_)) // "u" } [1,"P",3],[1,"P",0],[1,"",4],[0,1,1];
my @l = f(1,"Q",0);
print "@r|", scalar(@l), "|", join(",", map {"$_=$t{$_}"} sort keys %t), "\n";
```

```behavior
parses: yes
```

```output
u 0  0|1|3=P
```

```ir
main::__PROGRAM__: {start: 0, returns: [39], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: string, value: Q}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 6
  [Constant, {const_type: string, value: P}, ~, ~, Str], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [ArrayLiteral, ~, [2, 7, 8], 0, ArrayRef], # 9
  [ArrayLiteral, ~, [2, 7, 4], 9, ArrayRef], # 10
  [ArrayLiteral, ~, [2, 5, 6], 10, ArrayRef], # 11
  [ArrayLiteral, ~, [4, 2, 2], 11, ArrayRef], # 12
  [Loop, {bound: entry}, [12], 12], # 13
  [Proj, {index: 1}, [13]], # 14
  [Region, {head: 13}, [14]], # 15
  [MemStart], # 16
  [Phi, {memory: true, region: 13}, [16, 69], ~, Unknown], # 17
  [Phi, {memory: true, region: 15}, [17], ~, Unknown], # 18
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [2, 3, 4], 15, Unknown, 18, true], # 19
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 19], # 20
  [Coerce, {from_repr: Scalar, to_repr: Str}, [20], ~, Str], # 21
  [ArrayLiteral, ~, ~, ~, Array], # 22
  [Phi, {region: 13}, [22, 72], ~, Array], # 23
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [21, 23], ~, Str, 19], # 24
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 25
  [Concat, ~, [24, 25], ~, Str], # 26
  [ArrayLiteral, {sigil: "@", symbol: l}, [19], ~, Array], # 27
  [Count, ~, [27], ~, Int, 19], # 28
  [Coerce, {from_repr: Int, to_repr: Str}, [28], ~, Str], # 29
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 30
  [ArrayLiteral, ~, ~, ~, Array], # 31
  [Loop, {bound: entry}, [19], 19], # 32
  [Phi, {region: 32}, [31, 66], ~, Array], # 33
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [30, 33], ~, Str, 19], # 34
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 35
  [Proj, {index: 1}, [32]], # 36
  [Region, {head: 32}, [36]], # 37
  [Print, ~, [26, 29, 25, 34, 35], 37, "Maybe[Boolean]"], # 38
  [Return, {implicit: true}, [1], 38, ~, 19], # 39
  [ArrayLiteral, ~, [9, 10, 11, 12], ~, List], # 40
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: t}, ~, ~, Hash, 19], # 41
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [41], ~, List, 19], # 42
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [42], ~, List, 19], # 43
  [Count, ~, [43], ~, Int, 19], # 44
  [Phi, {region: 32}, [4, 51], ~, Int], # 45
  [Subscript, {kind: array}, [43, 45], ~, Scalar, 19], # 46
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: t}, ~, ~, Hash], # 47
  [Subscript, {kind: hash}, [47, 46], ~, Scalar, 19], # 48
  [Phi, {region: 13}, [4, 50], ~, Int], # 49
  [Add, ~, [49, 2], ~, Int], # 50
  [Add, ~, [45, 2], ~, Int], # 51
  [Count, ~, [40], ~, Int, 16], # 52
  [Count, ~, [40], ~, Int, 17], # 53
  [Subscript, {kind: array}, [40, 49], ~, ArrayRef, 17], # 54
  [Subscript, {kind: array}, [40, 49], ~, Scalar], # 55
  [NumGt, ~, [44, 45], 32, Boolean], # 56
  [Proj, {index: 0}, [32]], # 57
  [Coerce, {from_repr: Unknown, to_repr: Str}, [46], ~, Str], # 58
  [Coerce, {from_repr: Unknown, to_repr: Str}, [48], ~, Str], # 59
  [NumGt, ~, [53, 49], 13, Boolean], # 60
  [PostfixDeref, {sigil: "@"}, [54], ~, Array, 17], # 61
  [Ref, ~, [55], ~, ScalarRef], # 62
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 63
  [Concat, ~, [58, 63], ~, Str], # 64
  [Concat, ~, [64, 59], ~, Str], # 65
  [ListAppend, {collector: map}, [33, 65], ~, Array], # 66
  [Proj, {index: 0}, [13]], # 67
  [LocalAlias, {name: _}, [62], 67, Unknown, 17], # 68
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: scalar}, [61], 68, Unknown, 17, true], # 69
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 70
  [DefinedOr, ~, [69, 70], ~, Unknown], # 71
  [ListAppend, {collector: map}, [23, 71], ~, Array]]} # 72
main::f: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 2
  [PadAccess, {sigil: $, symbol: a}, ~, ~, Unknown], # 3
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Unknown], # 4
  [And, ~, [3, 4], ~, Unknown], # 5
  [And, ~, [2, 5], ~, Unknown], # 6
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: t}, ~, ~, Hash], # 7
  [Subscript, {kind: hash}, [7, 4], ~, Scalar], # 8
  [If, ~, [0, 2], 0], # 9
  [Proj, {index: 0}, [9]], # 10
  [If, ~, [10, 5], 10], # 11
  [Proj, {index: 0}, [11]], # 12
  [MemStart], # 13
  [Assign, ~, [8, 3], 12, Unknown, 13, true], # 14
  [Proj, {index: 1}, [9]], # 15
  [Proj, {index: 1}, [11]], # 16
  [Region, {head: 9}, [15, 16]], # 17
  [Region, ~, [14, 17]], # 18
  [Phi, {predecessors: [12, 17], region: 18}, [1, 6], ~, Unknown], # 19
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 20
  [Phi, {predecessors: [12, 17], region: 18}, [20, 6], ~, Unknown], # 21
  [Phi, {exits: true, memory: true, predecessors: [12, 17], region: 18}, [14, 13], ~, Unknown], # 22
  [Return, ~, [19, 21], 18, ~, 22], # 23
  [ArgsSource, ~, ~, ~, Array], # 24
  [Assign, {record: true, targets: 3}, [2, 3, 4, 24], ~, List]]} # 25
```

## A phi var-table update, guarded by returns

Early returns guard a method-call chain; the last if stores into nested hashes and returns.

```perl
package N { sub new { bless { o => $_[1], i => $_[2], id => $_[3] }, $_[0] } sub operation { $_[0]{o} } sub inputs { $_[0]{i} } sub id { $_[0]{id} } }
sub upd { my ($self, $phi, $ref) = @_; my $inputs = $phi->inputs; return unless defined $inputs && @$inputs; my $init = $inputs->[0]; return unless defined $init;
  if ($init->operation eq 'PadAccess') { my $vd = $init->inputs->[0]; if (defined $vd && $vd->operation eq 'VarDecl') { $self->{t}{ $vd->id } = $ref; $self->{p}{ $phi->id } = $vd->id; return } } }
my $s = {}; upd($s, N->new("Phi", [N->new("PadAccess", [N->new("VarDecl", [], 5)])], 9), "R"); upd($s, N->new("Phi", [N->new("PadAccess", [undef])], 3), "Q"); upd($s, N->new("Phi", [], 4), "Z");
print join(",", map { "$_=$s->{t}{$_}" } sort keys %{$s->{t}}), " ", join(",", %{$s->{p}}), "\n";
```

```behavior
parses: yes
```

```output
5=R 9,5
```

```ir
N::id: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: id}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
N::inputs: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: i}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
N::new: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: o}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Constant, {const_type: string, value: i}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7], ~, Scalar, 4], # 8
  [Constant, {const_type: string, value: id}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [2, 10], ~, Scalar, 4], # 11
  [HashLiteral, ~, [1, 5, 6, 8, 9, 11], 0, HashRef], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [Subscript, {kind: array}, [2, 13], ~, Scalar, 4], # 14
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [12, 14], 12, Unknown, 4, true], # 15
  [Return, {implicit: true}, [15], 15, ~, 15]]} # 16
N::operation: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: o}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
main::__PROGRAM__: {start: 0, returns: [60], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [MemStart], # 4
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 4], # 5
  [HashLiteral, ~, ~, 0, HashRef], # 6
  [Assign, ~, [5, 6], 6, HashRef, 4, true], # 7
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 7], # 8
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: Phi}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: PadAccess}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: VarDecl}, ~, ~, Str], # 12
  [ArrayLiteral, ~, ~, 7, ArrayRef], # 13
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 14
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: new, package: main, param_names: [], want: list}, [9, 12, 13, 14], 13, Object, 7, true], # 15
  [ArrayLiteral, ~, [15], 15, ArrayRef], # 16
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: new, package: main, param_names: [], want: list}, [9, 11, 16], 16, Object, 15, true], # 17
  [ArrayLiteral, ~, [17], 17, ArrayRef], # 18
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 19
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: new, package: main, param_names: [], want: list}, [9, 10, 18, 19], 18, Object, 17, true], # 20
  [Constant, {const_type: string, value: R}, ~, ~, Str], # 21
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::upd, package: main, param_names: [], want: void}, [8, 20, 21], 20, List, 20, true], # 22
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 22], # 23
  [ArrayLiteral, ~, [1], 22, ArrayRef], # 24
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: new, package: main, param_names: [], want: list}, [9, 11, 24], 24, Object, 22, true], # 25
  [ArrayLiteral, ~, [25], 25, ArrayRef], # 26
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 27
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: new, package: main, param_names: [], want: list}, [9, 10, 26, 27], 26, Object, 25, true], # 28
  [Constant, {const_type: string, value: Q}, ~, ~, Str], # 29
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::upd, package: main, param_names: [], want: void}, [23, 28, 29], 28, List, 28, true], # 30
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 30], # 31
  [ArrayLiteral, ~, ~, 30, ArrayRef], # 32
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 33
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: new, package: main, param_names: [], want: list}, [9, 10, 32, 33], 32, Object, 30, true], # 34
  [Constant, {const_type: string, value: Z}, ~, ~, Str], # 35
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::upd, package: main, param_names: [], want: void}, [31, 34, 35], 34, List, 34, true], # 36
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 36], # 37
  [Constant, {const_type: string, value: t}, ~, ~, Str], # 38
  [Subscript, {kind: hash}, [37, 38], 36, Scalar, 36], # 39
  [HashLiteral, ~, ~, 39, HashRef], # 40
  [DefinedOr, ~, [39, 40], ~, Scalar], # 41
  [Subscript, {kind: hash}, [37, 38], ~, Scalar], # 42
  [Assign, ~, [42, 41], 40, Scalar, 36, true], # 43
  [PostfixDeref, {sigil: "%"}, [41], 43, Hash, 43, true], # 44
  [Loop, {bound: entry}, [44], 44], # 45
  [Phi, {region: 45}, [3, 75], ~, Array], # 46
  [Phi, {memory: true, region: 45}, [44, 72], ~, List], # 47
  [Proj, {index: 1}, [45]], # 48
  [Region, {head: 45}, [48]], # 49
  [Phi, {memory: true, region: 49}, [47], ~, List], # 50
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 46], ~, Str, 50], # 51
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 52
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 50], # 53
  [Constant, {const_type: string, value: p}, ~, ~, Str], # 54
  [Subscript, {kind: hash}, [53, 54], 49, Scalar, 50, true], # 55
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 5, package: main, sigil: "%", strict: false}, [55], 55, Hash, 55, true], # 56
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 56], ~, Str, 56], # 57
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 58
  [Print, ~, [51, 52, 57, 58], 56, "Maybe[Boolean]"], # 59
  [Return, {implicit: true}, [1], 59, ~, 56], # 60
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [44], ~, List, 44], # 61
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [61], ~, List, 44], # 62
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 63
  [Phi, {region: 45}, [63, 80], ~, Int], # 64
  [Subscript, {kind: array}, [62, 64], ~, Scalar, 47], # 65
  [Coerce, {from_repr: Unknown, to_repr: Str}, [65], ~, Str], # 66
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 67
  [Concat, ~, [66, 67], ~, Str], # 68
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 47], # 69
  [Subscript, {kind: hash}, [69, 38], ~, Scalar], # 70
  [Proj, {index: 0}, [45]], # 71
  [Subscript, {kind: hash}, [70, 65], 71, Scalar, 47, true], # 72
  [Coerce, {from_repr: Unknown, to_repr: Str}, [72], ~, Str], # 73
  [Concat, ~, [68, 73], ~, Str], # 74
  [ListAppend, {collector: map}, [46, 74], ~, Array], # 75
  [Count, ~, [62], ~, Int, 47], # 76
  [Count, ~, [62], ~, Int, 44], # 77
  [NumGt, ~, [76, 64], 45, Boolean], # 78
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 79
  [Add, ~, [64, 79], ~, Int]]} # 80
main::upd: {start: 0, returns: [87], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [ArrayLiteral, ~, ~, ~, List], # 2
  [PadAccess, {sigil: $, symbol: phi}, ~, ~, Unknown], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: inputs, package: main, param_names: [], want: scalar}, [3], 0, Unknown, 4, true], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Defined, ~, [5], ~, Boolean], # 7
  [If, ~, [5, 7], 5], # 8
  [Proj, {index: 1}, [8]], # 9
  [Proj, {index: 0}, [8]], # 10
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: "@", strict: false}, [5], 10, Array, 5, true], # 11
  [Region, {head: 8}, [9, 11]], # 12
  [Count, ~, [11], ~, Int, 11], # 13
  [Phi, {predecessors: [9, 10], region: 12}, [7, 13], ~, Scalar], # 14
  [Not, ~, [14], ~, Boolean], # 15
  [If, ~, [12, 15], 12], # 16
  [Proj, {index: 1}, [16]], # 17
  [Phi, {memory: true, predecessors: [9, 10], region: 12}, [5, 11], ~, Unknown], # 18
  [Subscript, {kind: array}, [5, 6], 17, Scalar, 18, true], # 19
  [Defined, ~, [19], ~, Boolean], # 20
  [Not, ~, [20], ~, Boolean], # 21
  [If, ~, [19, 21], 19], # 22
  [Proj, {index: 1}, [22]], # 23
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: operation, package: main, param_names: [], want: scalar}, [19], 23, Unknown, 19, true], # 24
  [Coerce, {from_repr: Unknown, to_repr: Str}, [24], ~, Str], # 25
  [Constant, {const_type: string, value: PadAccess}, ~, ~, Str], # 26
  [StrEq, ~, [25, 26], ~, Boolean], # 27
  [If, ~, [24, 27], 24], # 28
  [Proj, {index: 0}, [28]], # 29
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: inputs, package: main, param_names: [], want: scalar}, [19], 29, Unknown, 24, true], # 30
  [Subscript, {kind: array}, [30, 6], 30, Scalar, 30, true], # 31
  [Defined, ~, [31], ~, Boolean], # 32
  [If, ~, [31, 32], 31], # 33
  [Proj, {index: 0}, [33]], # 34
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: operation, package: main, param_names: [], want: scalar}, [31], 34, Unknown, 31, true], # 35
  [Coerce, {from_repr: Unknown, to_repr: Str}, [35], ~, Str], # 36
  [Constant, {const_type: string, value: VarDecl}, ~, ~, Str], # 37
  [StrEq, ~, [36, 37], ~, Boolean], # 38
  [Proj, {index: 1}, [33]], # 39
  [Region, {head: 33}, [35, 39]], # 40
  [Phi, {predecessors: [34, 39], region: 40}, [38, 32], ~, Boolean], # 41
  [Proj, {index: 1}, [28]], # 42
  [If, ~, [40, 41], 40], # 43
  [Proj, {index: 1}, [43]], # 44
  [Region, {head: 28}, [42, 44]], # 45
  [Phi, {predecessors: [42, 29], region: 45}, [27, 41], ~, Boolean], # 46
  [Proj, {index: 0}, [22]], # 47
  [Region, {head: 22}, [47, 45]], # 48
  [Phi, {predecessors: [47, 23], region: 48}, [2, 46], ~, List], # 49
  [Proj, {index: 0}, [16]], # 50
  [Region, {head: 16}, [50, 48]], # 51
  [Phi, {predecessors: [50, 17], region: 51}, [1, 49], ~, List], # 52
  [ArrayLiteral, ~, ~, ~, List], # 53
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 54
  [Constant, {const_type: string, value: p}, ~, ~, Str], # 55
  [Constant, {const_type: string, value: t}, ~, ~, Str], # 56
  [Proj, {index: 0}, [43]], # 57
  [Phi, {memory: true, predecessors: [34, 39], region: 40}, [35, 31], ~, Unknown], # 58
  [Subscript, {kind: hash}, [54, 56], 57, Scalar, 58], # 59
  [HashLiteral, ~, ~, 59, HashRef], # 60
  [DefinedOr, ~, [59, 60], ~, Scalar], # 61
  [Subscript, {kind: hash}, [54, 56], ~, Scalar], # 62
  [Assign, ~, [62, 61], 60, Scalar, 58, true], # 63
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: id, package: main, param_names: [], want: scalar}, [31], 63, Unknown, 63, true], # 64
  [Subscript, {kind: hash}, [61, 64], ~, Scalar], # 65
  [PadAccess, {sigil: $, symbol: ref}, ~, ~, Unknown], # 66
  [Assign, ~, [65, 66], 64, Unknown, 64, true], # 67
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: id, package: main, param_names: [], want: scalar}, [31], 67, Unknown, 67, true], # 68
  [Subscript, {kind: hash}, [54, 55], 68, Scalar, 68], # 69
  [HashLiteral, ~, ~, 69, HashRef], # 70
  [DefinedOr, ~, [69, 70], ~, Scalar], # 71
  [Subscript, {kind: hash}, [54, 55], ~, Scalar], # 72
  [Assign, ~, [72, 71], 70, Scalar, 68, true], # 73
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: id, package: main, param_names: [], want: scalar}, [3], 73, Unknown, 73, true], # 74
  [Subscript, {kind: hash}, [71, 74], ~, Scalar], # 75
  [Assign, ~, [75, 68], 74, Unknown, 74, true], # 76
  [Region, ~, [51, 76]], # 77
  [Phi, {predecessors: [51, 57], region: 77}, [52, 53], ~, List], # 78
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 79
  [Phi, {predecessors: [47, 23], region: 48}, [79, 46], ~, "Maybe[Boolean]"], # 80
  [Phi, {predecessors: [50, 17], region: 51}, [79, 80], ~, "Maybe[Boolean]"], # 81
  [Phi, {predecessors: [51, 57], region: 77}, [81, 79], ~, "Maybe[Boolean]"], # 82
  [Phi, {memory: true, predecessors: [42, 29], region: 45}, [24, 58], ~, Unknown], # 83
  [Phi, {exits: true, memory: true, predecessors: [47, 23], region: 48}, [19, 83], ~, Unknown], # 84
  [Phi, {exits: true, memory: true, predecessors: [50, 17], region: 51}, [18, 84], ~, Unknown], # 85
  [Phi, {exits: true, memory: true, predecessors: [51, 57], region: 77}, [85, 76], ~, Unknown], # 86
  [Return, ~, [78, 82], 77, ~, 86], # 87
  [ArgsSource, ~, ~, ~, Array], # 88
  [Assign, {record: true, targets: 3}, [54, 3, 66, 88], ~, List], # 89
  [Phi, {predecessors: [42, 29], region: 45}, [79, 31], ~, Scalar]]} # 90
```

## A local hash element for the rest of a sub

A recursion guard: the element is set for the callee and gone once the sub returns.

```perl
sub h { my $s = shift; join ",", map { "$_=" . (ref $s->{$_} ? "{" . join("", sort keys %{$s->{$_}}) . "}" : $s->{$_} // "u") } sort keys %$s }
sub f { my ($self, $n) = @_; local $self->{c} = { ($self->{c} // {})->%*, $n => 1 }; return h($self) }
my $s = { a => 1 }; print f($s, "x"), " | ", h($s), "\n";
```

```behavior
parses: yes
```

```output
a=1,c={x} | a=1
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 2], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [HashLiteral, ~, [4, 5], 0, HashRef], # 6
  [Assign, ~, [3, 6], 6, HashRef, 2, true], # 7
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 7], # 8
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [8, 9], 7, Str, 7, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: " | "}, ~, ~, Str], # 12
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 10], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::h, package: main, param_names: [], want: list}, [13], 10, Str, 10, true], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Print, ~, [11, 12, 15, 16], 14, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [1], 17, ~, 14]]} # 18
main::f: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown, 1], # 2
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Assign, {targets: 2}, [2, 3, 4], 0, List, 1, true], # 5
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown, 5], # 6
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 7
  [Subscript, {kind: hash}, [6, 7], 5, Scalar, 5, true], # 8
  [Defined, ~, [8], ~, Boolean], # 9
  [If, ~, [8, 9], 8], # 10
  [Proj, {index: 1}, [10]], # 11
  [HashLiteral, ~, ~, 11, HashRef], # 12
  [DefinedOr, ~, [8, 12], ~, Scalar], # 13
  [Proj, {index: 0}, [10]], # 14
  [Region, {head: 10}, [14, 12]], # 15
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: "%", strict: false}, [13], 15, Hash, 8, true], # 16
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown, 16], # 17
  [Subscript, {kind: hash}, [17, 7], ~, Scalar], # 18
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 19
  [HashLiteral, ~, [16, 3, 19], 16, HashRef], # 20
  [Assign, {local: true}, [18, 20], 20, HashRef, 16, true], # 21
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown, 21], # 22
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::h, package: main, param_names: []}, [22], 21, Str, 21, true], # 23
  [Subscript, {kind: hash}, [17, 7], ~, Scalar, 16], # 24
  [Exists, {kind: hash}, [17, 7], ~, Boolean, 16], # 25
  [ElemRestore, {at_return: 1, kind: hash}, [17, 7, 24, 25], 23, Unknown, 23, true], # 26
  [Return, ~, [23], 26, ~, 26]]} # 27
main::h: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [3], 0, Scalar, 4, true], # 5
  [PostfixDeref, {sigil: "%"}, [5], 5, Hash, 5, true], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [2, 52], ~, Array], # 8
  [Phi, {memory: true, region: 7}, [6, 37], ~, List], # 9
  [Proj, {index: 1}, [7]], # 10
  [Region, {head: 7}, [10]], # 11
  [Phi, {memory: true, region: 11}, [9], ~, List], # 12
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 8], ~, Str, 12], # 13
  [Return, {implicit: true}, [13], 11, ~, 12], # 14
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [6], ~, List, 6], # 15
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [15], ~, List, 6], # 16
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 17
  [Phi, {region: 7}, [17, 56], ~, Int], # 18
  [Subscript, {kind: array}, [16, 18], ~, Scalar, 9], # 19
  [Proj, {index: 0}, [7]], # 20
  [Subscript, {kind: hash}, [5, 19], 20, Scalar, 9, true], # 21
  [RefType, ~, [21], ~, Str, 21], # 22
  [If, ~, [21, 22], 21], # 23
  [Proj, {index: 1}, [23]], # 24
  [Subscript, {kind: hash}, [5, 19], 24, Scalar, 21, true], # 25
  [Subscript, {kind: hash}, [5, 19], ~, Scalar], # 26
  [Proj, {index: 0}, [23]], # 27
  [Subscript, {kind: hash}, [5, 19], 27, Scalar, 21], # 28
  [Count, ~, [16], ~, Int, 6], # 29
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 30
  [DefinedOr, ~, [25, 30], ~, Scalar], # 31
  [HashLiteral, ~, ~, 28, HashRef], # 32
  [DefinedOr, ~, [28, 32], ~, Scalar], # 33
  [Assign, ~, [26, 33], 32, Scalar, 21, true], # 34
  [PostfixDeref, {sigil: "%"}, [33], 34, Hash, 34, true], # 35
  [Region, {head: 23}, [35, 25]], # 36
  [Phi, {memory: true, predecessors: [27, 24], region: 36}, [35, 25], ~, List], # 37
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 38
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 39
  [Concat, ~, [38, 39], ~, Str], # 40
  [Constant, {const_type: string, value: "{"}, ~, ~, Str], # 41
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 42
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [35], ~, List, 35], # 43
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [43], ~, List, 35], # 44
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [42, 44], ~, Str, 35], # 45
  [Concat, ~, [41, 45], ~, Str], # 46
  [Constant, {const_type: string, value: "}"}, ~, ~, Str], # 47
  [Concat, ~, [46, 47], ~, Str], # 48
  [Phi, {predecessors: [27, 24], region: 36}, [48, 31], ~, Scalar], # 49
  [Coerce, {from_repr: Scalar, to_repr: Str}, [49], ~, Str], # 50
  [Concat, ~, [40, 50], ~, Str], # 51
  [ListAppend, {collector: map}, [8, 51], ~, Array], # 52
  [Count, ~, [16], ~, Int, 9], # 53
  [NumGt, ~, [53, 18], 7, Boolean], # 54
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 55
  [Add, ~, [18, 55], ~, Int]]} # 56
```

## A local hash element in an if block

Restored at the end of the block, so a read after it sees the old value.

```perl
sub h { my $s = shift; join ",", map { "$_=" . ($s->{$_} // "u") } sort keys %$s }
sub f { my ($self, $n) = @_; my $r = ""; if ($n) { local $self->{c} = $n; $r = h($self) } return "$r / " . h($self) }
my $s = { a => 1, c => 0 }; print f($s, "x"), " | ", f($s, ""), " | ", h($s), "\n";
```

```behavior
parses: yes
```

```output
a=1,c=x / a=1,c=0 |  / a=1,c=0 | a=1,c=0
```

```ir
main::__PROGRAM__: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 2], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [HashLiteral, ~, [4, 5, 6, 7], 0, HashRef], # 8
  [Assign, ~, [3, 8], 8, HashRef, 2, true], # 9
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 9], # 10
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [10, 11], 9, Str, 9, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: " | "}, ~, ~, Str], # 14
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 12], # 15
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 16
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [15, 16], 12, Str, 12, true], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 17], # 19
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::h, package: main, param_names: [], want: list}, [19], 17, Str, 17, true], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 22
  [Print, ~, [13, 14, 18, 14, 21, 22], 20, "Maybe[Boolean]"], # 23
  [Return, {implicit: true}, [1], 23, ~, 20]]} # 24
main::f: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown, 2], # 3
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Assign, {targets: 2}, [3, 4, 5], 0, List, 2, true], # 6
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown, 6], # 7
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 8
  [Subscript, {kind: hash}, [7, 8], ~, Scalar], # 9
  [If, ~, [6, 4], 6], # 10
  [Proj, {index: 0}, [10]], # 11
  [Assign, {local: true}, [9, 4], 11, Unknown, 6, true], # 12
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown, 12], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::h, package: main, param_names: [], want: scalar}, [13], 12, Str, 12, true], # 14
  [Proj, {index: 1}, [10]], # 15
  [Subscript, {kind: hash}, [7, 8], ~, Scalar, 6], # 16
  [Exists, {kind: hash}, [7, 8], ~, Boolean, 6], # 17
  [ElemRestore, {kind: hash}, [7, 8, 16, 17], 14, Unknown, 14, true], # 18
  [Region, {head: 10}, [15, 18]], # 19
  [Phi, {predecessors: [15, 11], region: 19}, [1, 14], ~, Str], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Constant, {const_type: string, value: " / "}, ~, ~, Str], # 22
  [Concat, ~, [21, 22], ~, Str], # 23
  [Phi, {memory: true, predecessors: [15, 11], region: 19}, [6, 18], ~, Unknown], # 24
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown, 24], # 25
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::h, package: main, param_names: [], want: scalar}, [25], 19, Str, 24, true], # 26
  [Concat, ~, [23, 26], ~, Str], # 27
  [Return, ~, [27], 26, ~, 26]]} # 28
main::h: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [3], 0, Scalar, 4, true], # 5
  [PostfixDeref, {sigil: "%"}, [5], 5, Hash, 5, true], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [2, 30], ~, Array], # 8
  [Phi, {memory: true, region: 7}, [6, 21], ~, List], # 9
  [Proj, {index: 1}, [7]], # 10
  [Region, {head: 7}, [10]], # 11
  [Phi, {memory: true, region: 11}, [9], ~, List], # 12
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 8], ~, Str, 12], # 13
  [Return, {implicit: true}, [13], 11, ~, 12], # 14
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [6], ~, List, 6], # 15
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [15], ~, List, 6], # 16
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 17
  [Phi, {region: 7}, [17, 34], ~, Int], # 18
  [Subscript, {kind: array}, [16, 18], ~, Scalar, 9], # 19
  [Proj, {index: 0}, [7]], # 20
  [Subscript, {kind: hash}, [5, 19], 20, Scalar, 9, true], # 21
  [Count, ~, [16], ~, Int, 6], # 22
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 23
  [DefinedOr, ~, [21, 23], ~, Scalar], # 24
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 25
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 26
  [Concat, ~, [25, 26], ~, Str], # 27
  [Coerce, {from_repr: Scalar, to_repr: Str}, [24], ~, Str], # 28
  [Concat, ~, [27, 28], ~, Str], # 29
  [ListAppend, {collector: map}, [8, 29], ~, Array], # 30
  [Count, ~, [16], ~, Int, 9], # 31
  [NumGt, ~, [31, 18], 7, Boolean], # 32
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 33
  [Add, ~, [18, 33], ~, Int]]} # 34
```

## A local on a key that did not exist

The restore deletes the key again.

```perl
sub f { my ($self) = @_; my $r = ""; { local $self->{k} = 5; $r = join ",", sort keys %$self } return "$r / " . join(",", sort keys %$self) }
print f({ a => 1 }), "\n";
```

```behavior
parses: yes
```

```output
a,k / a
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [HashLiteral, ~, [2, 3], 0, HashRef], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [4], 4, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
main::f: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 3
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Assign, {local: true}, [4, 5], 0, Int, 6, true], # 7
  [PostfixDeref, {sigil: "%"}, [2], 7, Hash, 7, true], # 8
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [8], ~, List, 8], # 9
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [9], ~, List, 8], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 10], ~, Str, 8], # 11
  [Constant, {const_type: string, value: " / "}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Subscript, {kind: hash}, [2, 3], ~, Scalar, 6], # 14
  [Exists, {kind: hash}, [2, 3], ~, Boolean, 6], # 15
  [ElemRestore, {kind: hash}, [2, 3, 14, 15], 8, Unknown, 8, true], # 16
  [PostfixDeref, {sigil: "%"}, [2], 16, Hash, 16, true], # 17
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [17], ~, List, 17], # 18
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [18], ~, List, 17], # 19
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 19], ~, Str, 17], # 20
  [Concat, ~, [13, 20], ~, Str], # 21
  [Return, ~, [21], 17, ~, 17], # 22
  [ArgsSource, ~, ~, ~, Array], # 23
  [Assign, {record: true, targets: 1}, [2, 23], ~, List]]} # 24
```

## A package local in an if arm

The arm restores the package variable at its end, before the call after the if.

```perl
our $g = 1; sub g { "g=$g" }
sub f { my $r = ""; if ($_[0]) { local $g = 2; $r = g() } return "$r " . g() }
print f(1), " | ", f(0), " | $g\n";
```

```behavior
parses: yes
```

```output
g=2 g=1 |  g=1 | 1
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar], # 3
  [MemStart], # 4
  [EntryWrite, ~, [3, 2], 0, Unknown, 4, true], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2], 5, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: " | "}, ~, ~, Str], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [9], 6, Str, 6, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Int, 10], # 12
  [Coerce, {from_repr: Int, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [8, 13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [Print, ~, [7, 8, 11, 16], 10, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [1], 17, ~, 10]]} # 18
main::f: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Subscript, {kind: array}, [4, 5], ~, Scalar, 6], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [EntryWrite, ~, [2, 3], 9, Unknown, 6, true], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: scalar}, ~, 10, Str, 10, true], # 11
  [Proj, {index: 1}, [8]], # 12
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar, 6], # 13
  [EntryWrite, ~, [2, 13], 11, Unknown, 11, true], # 14
  [Region, {head: 8}, [12, 14]], # 15
  [Phi, {predecessors: [12, 9], region: 15}, [1, 11], ~, Str], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Phi, {memory: true, predecessors: [12, 9], region: 15}, [6, 14], ~, Unknown], # 20
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: scalar}, ~, 15, Str, 20, true], # 21
  [Concat, ~, [19, 21], ~, Str], # 22
  [Return, ~, [22], 21, ~, 21]]} # 23
main::g: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "g="}, ~, ~, Str], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar, 2], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Concat, ~, [1, 4], ~, Str], # 5
  [Return, {implicit: true}, [5], 0, ~, 2]]} # 6
```

## A builtin of the topic in a grep

The `$_` handed to `blessed` is marked modifiable, but the builtin only reads the element.

```perl
use Scalar::Util qw(blessed);
package K { sub new { bless {}, shift } sub ok { 1 } }
my @a = (K->new, 3, K->new);
my @g = grep { blessed($_) && $_->ok } @a;
print scalar(@g), "\n";
```

```behavior
parses: yes
```

```output
2
```

```ir
K::new: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [HashLiteral, ~, ~, 0, HashRef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 1, Scalar, 3, true], # 4
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [1, 4], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
K::ok: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [MemStart], # 2
  [Return, {implicit: true}, [1], 0, ~, 2]]} # 3
Scalar::Util::export_fail: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Proj, {index: 1}, [2]], # 3
  [Region, {head: 2}, [3]], # 4
  [ArrayLiteral, ~, ~, ~, Array], # 5
  [Phi, {region: 2}, [5, 27], ~, Array], # 6
  [Count, ~, [6], ~, Int], # 7
  [If, ~, [4, 7], 4], # 8
  [Proj, {index: 1}, [8]], # 9
  [Constant, {const_type: string, value: "Vstrings are not implemented in this version of perl"}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: Carp.pm}, ~, ~, Str], # 11
  [Proj, {index: 0}, [8]], # 12
  [MemStart], # 13
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [11], 12, Unknown, 13, true], # 14
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/Scalar/Util.pm", line: 43, name: Carp::croak, package: Scalar::Util, param_names: [], want: void}, [10], 14, Unknown, 14, true], # 15
  [Region, {head: 8}, [9, 15]], # 16
  [Phi, {memory: true, predecessors: [9, 12], region: 16}, [13, 15], ~, Unknown], # 17
  [Return, {implicit: true}, [1], 16, ~, 17], # 18
  [Count, ~, [1], ~, Int, 13], # 19
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 20
  [Phi, {region: 2}, [20, 29], ~, Int], # 21
  [NumGt, ~, [19, 21], 2, Boolean], # 22
  [Proj, {index: 0}, [2]], # 23
  [Subscript, {kind: array}, [1, 21], ~, Scalar, 13], # 24
  [Coerce, {from_repr: Scalar, to_repr: Str}, [24], ~, Str], # 25
  [RegexMatch, {flags: "", pattern: "^isvstring$"}, [25], ~, Boolean], # 26
  [ListAppend, {collector: grep}, [6, 24, 26], ~, Array], # 27
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 28
  [Add, ~, [21, 28], ~, Int]]} # 29
Scalar::Util::set_prototype: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: code}, ~, ~, Unknown, 1], # 2
  [PadAccess, {sigil: $, symbol: proto}, ~, ~, Unknown, 1], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Assign, {targets: 2}, [2, 3, 4], 0, List, 1, true], # 5
  [PadAccess, {sigil: $, symbol: proto}, ~, ~, Unknown, 5], # 6
  [PadAccess, {sigil: $, symbol: code}, ~, ~, Unknown, 5], # 7
  [Call, {dispatch_kind: direct, external: true, file: "/home/runner/.local/share/pvm/versions/5.42.0/lib/perl5/5.42.0/x86_64-linux-thread-multi/Scalar/Util.pm", line: 53, name: Sub::Util::set_prototype, package: Scalar::Util, param_names: [], xs: true}, [6, 7], 5, Unknown, 5, true], # 8
  [Return, ~, [8], 8, ~, 8]]} # 9
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Constant, {const_type: string, value: K}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: new, package: main, param_names: [], want: list}, [3], 0, Object, 4, true], # 5
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: new, package: main, param_names: [], want: list}, [3], 5, Object, 5, true], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [2, 40], ~, Array], # 8
  [Phi, {memory: true, region: 7}, [6, 37], ~, Unknown], # 9
  [Proj, {index: 1}, [7]], # 10
  [Region, {head: 7}, [10]], # 11
  [Phi, {memory: true, region: 11}, [9], ~, Unknown], # 12
  [Count, ~, [8], ~, Int, 12], # 13
  [Coerce, {from_repr: Int, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [14, 15], 11, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 12], # 17
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 18
  [ArrayLiteral, {sigil: "@", symbol: a}, [5, 18, 6], ~, Array], # 19
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 20
  [Phi, {region: 7}, [20, 42], ~, Int], # 21
  [Proj, {index: 0}, [7]], # 22
  [Exists, {kind: array}, [19, 21], 22, Boolean, 9], # 23
  [Subscript, {kind: array}, [19, 21], ~, Scalar], # 24
  [Ref, ~, [24], ~, ScalarRef], # 25
  [TernaryExpr, ~, [23, 25, 1], ~, "Maybe[ScalarRef]"], # 26
  [Count, ~, [19], ~, Int, 6], # 27
  [Count, ~, [19], ~, Int, 9], # 28
  [Subscript, {kind: array}, [19, 21], ~, Scalar, 9], # 29
  [LocalAlias, {name: _}, [26], 23, Unknown, 9], # 30
  [Call, {dispatch_kind: builtin, name: blessed, param_names: []}, [29], ~, Scalar, 9], # 31
  [If, ~, [30, 31], 30], # 32
  [Proj, {index: 0}, [32]], # 33
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: ok, package: main, param_names: [], want: scalar}, [29], 33, Unknown, 9, true], # 34
  [Proj, {index: 1}, [32]], # 35
  [Region, {head: 32}, [34, 35]], # 36
  [Phi, {memory: true, predecessors: [33, 35], region: 36}, [34, 9], ~, Unknown], # 37
  [NumGt, ~, [28, 21], 7, Boolean], # 38
  [Phi, {predecessors: [33, 35], region: 36}, [34, 31], ~, Unknown], # 39
  [ListAppend, {collector: grep}, [8, 29, 39], ~, Array], # 40
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 41
  [Add, ~, [21, 41], ~, Int]]} # 42
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: Scalar::Util}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: blessed}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "Scalar/Util.pm"}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: Scalar::Util, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## An array rewritten in two ifs, then iterated

Each if may replace the array with a rewritten copy; the merges are arrays, and the copies read the arm-local array where they stand.

```perl
sub f { my @lines; push @lines, "a", "b";
  if ($_[0]) { my @n; for my $l (@lines) { push @n, uc $l } @lines = @n }
  if ($_[1]) { my @n; for my $l (@lines) { push @n, "$l$l" } @lines = @n }
  my $s = ""; for my $l (@lines) { $s .= $l } return $s }
print f(1, 0), f(0, 1), f(1, 1), f(0, 0), "\n";
```

```behavior
parses: yes
```

```output
ABaabbAABBab
```

```ir
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::f, package: main, param_names: [], want: list}, [2, 3], 0, Str, 4, true], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::f, package: main, param_names: [], want: list}, [3, 2], 5, Str, 5, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::f, package: main, param_names: [], want: list}, [2, 2], 7, Str, 7, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::f, package: main, param_names: [], want: list}, [3, 3], 9, Str, 9, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [6, 8, 10, 12, 13], 11, "Maybe[Boolean]"], # 14
  [Return, {implicit: true}, [1], 14, ~, 11]]} # 15
main::f: {start: 0, returns: [40], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: lines}, ~, ~, Array], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 3, 4], 0, Int, 5, true], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Subscript, {kind: array}, [7, 8], ~, Scalar, 6], # 9
  [If, ~, [6, 9], 6], # 10
  [Proj, {index: 1}, [10]], # 11
  [PadAccess, {sigil: "@", symbol: "n"}, ~, ~, Array], # 12
  [Proj, {index: 0}, [10]], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Proj, {index: 1}, [14]], # 15
  [Region, {head: 14}, [15]], # 16
  [ArrayLiteral, {rebinds: true, sigil: "@", symbol: lines}, [12], 16, Array], # 17
  [Region, {head: 10}, [11, 17]], # 18
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 19
  [Phi, {memory: true, region: 14}, [6, 54], ~, Int], # 20
  [Phi, {memory: true, region: 16}, [20], ~, Int], # 21
  [Phi, {memory: true, predecessors: [11, 13], region: 18}, [6, 21], ~, Int], # 22
  [Subscript, {kind: array}, [7, 19], ~, Scalar, 22], # 23
  [If, ~, [18, 23], 18], # 24
  [Proj, {index: 1}, [24]], # 25
  [PadAccess, {sigil: "@", symbol: n__2}, ~, ~, Array], # 26
  [Proj, {index: 0}, [24]], # 27
  [Loop, {bound: entry}, [27], 27], # 28
  [Proj, {index: 1}, [28]], # 29
  [Region, {head: 28}, [29]], # 30
  [ArrayLiteral, {rebinds: true, sigil: "@", symbol: lines}, [26], 30, Array], # 31
  [Region, {head: 24}, [25, 31]], # 32
  [Loop, {bound: entry}, [32], 32], # 33
  [Phi, {region: 33}, [1, 47], ~, Str], # 34
  [Proj, {index: 1}, [33]], # 35
  [Region, {head: 33}, [35]], # 36
  [Phi, {memory: true, region: 28}, [22, 64], ~, Int], # 37
  [Phi, {memory: true, region: 30}, [37], ~, Int], # 38
  [Phi, {memory: true, predecessors: [25, 27], region: 32}, [22, 38], ~, Int], # 39
  [Return, ~, [34], 36, ~, 39], # 40
  [Count, ~, [2], ~, Int, 6], # 41
  [Phi, {predecessors: [11, 13], region: 18}, [2, 17], ~, Array], # 42
  [Phi, {predecessors: [25, 27], region: 32}, [42, 31], ~, Array], # 43
  [Phi, {region: 33}, [8, 66], ~, Int], # 44
  [Subscript, {kind: array}, [43, 44], ~, Scalar, 39], # 45
  [Coerce, {from_repr: Unknown, to_repr: Str}, [45], ~, Str], # 46
  [Concat, ~, [34, 46], ~, Str], # 47
  [Count, ~, [43], ~, Int, 39], # 48
  [Count, ~, [2], ~, Int, 20], # 49
  [Phi, {region: 14}, [8, 67], ~, Int], # 50
  [Subscript, {kind: array}, [2, 50], ~, Scalar, 20], # 51
  [Call, {dispatch_kind: builtin, name: uc, param_names: []}, [51], ~, Str], # 52
  [Proj, {index: 0}, [14]], # 53
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [12, 52], 53, Int, 20, true], # 54
  [Count, ~, [42], ~, Int, 22], # 55
  [NumGt, ~, [48, 44], 33, Boolean], # 56
  [NumGt, ~, [49, 50], 14, Boolean], # 57
  [Count, ~, [42], ~, Int, 37], # 58
  [Phi, {region: 28}, [8, 69], ~, Int], # 59
  [Subscript, {kind: array}, [42, 59], ~, Scalar, 37], # 60
  [Coerce, {from_repr: Scalar, to_repr: Str}, [60], ~, Str], # 61
  [Concat, ~, [61, 61], ~, Str], # 62
  [Proj, {index: 0}, [28]], # 63
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [26, 62], 63, Int, 37, true], # 64
  [Proj, {index: 0}, [33]], # 65
  [Add, ~, [44, 19], ~, Int], # 66
  [Add, ~, [50, 19], ~, Int], # 67
  [NumGt, ~, [58, 59], 28, Boolean], # 68
  [Add, ~, [59, 19], ~, Int]]} # 69
```

## Two sibling arrays of one name

A `my @n` in each of two ifs: two arrays.

```perl
sub f { my $s = ""; if ($_[0]) { my @n; push @n, 1; $s .= "@n;" } if ($_[1]) { my @n; push @n, 2; $s .= "@n;" } $s }
print f(1, 1), f(0, 1), "\n";
```

```behavior
parses: yes
```

```output
1;2;2;
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [2, 2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [6, 2], 4, Str, 4, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [5, 8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7]]} # 11
main::f: {start: 0, returns: [36], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: "n"}, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Subscript, {kind: array}, [4, 5], ~, Scalar, 6], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 3], 9, Int, 6, true], # 10
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 10], # 11
  [Coerce, {from_repr: Scalar, to_repr: Str}, [11], ~, Str], # 12
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 2], ~, Str, 10], # 13
  [Concat, ~, [1, 13], ~, Str], # 14
  [Constant, {const_type: string, value: ";"}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [Proj, {index: 1}, [8]], # 17
  [Region, {head: 8}, [17, 10]], # 18
  [Phi, {predecessors: [17, 9], region: 18}, [1, 16], ~, Str], # 19
  [PadAccess, {sigil: "@", symbol: n__2}, ~, ~, Array], # 20
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 21
  [Phi, {memory: true, predecessors: [17, 9], region: 18}, [6, 10], ~, Unknown], # 22
  [Subscript, {kind: array}, [4, 3], ~, Scalar, 22], # 23
  [If, ~, [18, 23], 18], # 24
  [Proj, {index: 0}, [24]], # 25
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [20, 21], 25, Int, 22, true], # 26
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 26], # 27
  [Coerce, {from_repr: Scalar, to_repr: Str}, [27], ~, Str], # 28
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [28, 20], ~, Str, 26], # 29
  [Concat, ~, [19, 29], ~, Str], # 30
  [Concat, ~, [30, 15], ~, Str], # 31
  [Proj, {index: 1}, [24]], # 32
  [Region, {head: 24}, [32, 26]], # 33
  [Phi, {predecessors: [32, 25], region: 33}, [19, 31], ~, Str], # 34
  [Phi, {memory: true, predecessors: [32, 25], region: 33}, [22, 26], ~, Unknown], # 35
  [Return, {implicit: true}, [34], 33, ~, 35]]} # 36
```

## A closure array fresh on each call of its sub

The sub declares the array its closure pushes onto; each call starts empty.

```perl
sub mk { my @p; my $c = sub { push @p, $_[0] }; $c->(1); $c->(2); return "@p" }
print mk(), "|", mk(), "\n";
```

```behavior
parses: yes
```

```output
1 2|1 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::mk, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::mk, package: main, param_names: [], want: list}, ~, 3, Str, 3, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [4, 5, 7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
main::mk: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array], # 3
  [MemStart], # 4
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array, 4], # 5
  [ArrayLiteral, ~, ~, ~, Array], # 6
  [Assign, ~, [5, 6], 0, List, 4, true], # 7
  [MakeCell, {captured_written: false, cell_name: "@p"}, [3], 7, Ref, 7, true], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::mk::__ANON__:1:3, package: main, param_names: [], want: void}, [2], 8, Int, 8, true], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::mk::__ANON__:1:3, package: main, param_names: [], want: void}, [1], 9, Int, 9, true], # 10
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 10], # 11
  [Coerce, {from_repr: Scalar, to_repr: Str}, [11], ~, Str], # 12
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array, 10], # 13
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 13], ~, Str, 10], # 14
  [Return, ~, [14], 10, ~, 10], # 15
  [AnonSub, {captures: ["@p"], name: main::mk::__ANON__:1:3}, [8], ~, CodeRef]]} # 16
main::mk::__ANON__:1:3: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Array], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [1, 5], 0, Int, 4, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A callee changes the iterated element in place

The iterator is an alias: a read after the call sees the changed element.

```perl
sub g { $_[0][$_[1]] = $_[0][$_[1]] . "!" }
sub f { my $l = [qw(a b c)]; my $s = ""; my $i = 0; for my $x (@$l) { g($l, $i++); $s .= $x } "$s|@$l" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
a!b!c!|a! b! c!
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: l}, ~, ~, Unknown, 2], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 6
  [ArrayLiteral, ~, [4, 5, 6], 0, ArrayRef], # 7
  [Assign, ~, [3, 7], 7, ArrayRef, 2, true], # 8
  [Loop, {bound: entry}, [8], 8], # 9
  [Phi, {region: 9}, [1, 44], ~, Str], # 10
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Phi, {memory: true, region: 9}, [8, 38], ~, Scalar], # 13
  [Proj, {index: 1}, [9]], # 14
  [Region, {head: 9}, [14]], # 15
  [Phi, {memory: true, region: 15}, [13], ~, Scalar], # 16
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 16], # 17
  [Coerce, {from_repr: Scalar, to_repr: Str}, [17], ~, Str], # 18
  [PadAccess, {sigil: $, symbol: l}, ~, ~, Unknown, 16], # 19
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: "@", strict: false}, [19], 15, Array, 16, true], # 20
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [18, 20], ~, Str, 20], # 21
  [Concat, ~, [12, 21], ~, Str], # 22
  [Return, {implicit: true}, [22], 20, ~, 20], # 23
  [PadAccess, {sigil: $, symbol: l}, ~, ~, Unknown, 8], # 24
  [PostfixDeref, {sigil: "@"}, [24], ~, Array, 8], # 25
  [Count, ~, [25], ~, Int, 8], # 26
  [Count, ~, [25], ~, Int, 13], # 27
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 28
  [Phi, {region: 9}, [28, 46], ~, Int], # 29
  [Proj, {index: 0}, [9]], # 30
  [Exists, {kind: array}, [25, 29], 30, Boolean, 13], # 31
  [Subscript, {kind: array}, [25, 29], ~, Scalar], # 32
  [PadAccess, {sigil: $, symbol: l}, ~, ~, Unknown, 13], # 33
  [Phi, {region: 9}, [28, 47], ~, Int], # 34
  [Ref, ~, [32], ~, ScalarRef], # 35
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 36
  [TernaryExpr, ~, [31, 35, 36], 31, "Maybe[ScalarRef]"], # 37
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: void}, [33, 34], 37, Str, 13, true], # 38
  [Subscript, {kind: array}, [25, 29], ~, Scalar, 38], # 39
  [NumGt, ~, [27, 29], 9, Boolean], # 40
  [PostfixDeref, {sigil: $}, [37], ~, Scalar, 38], # 41
  [TernaryExpr, ~, [31, 41, 39], 38, Scalar], # 42
  [Coerce, {from_repr: Scalar, to_repr: Str}, [42], ~, Str], # 43
  [Concat, ~, [10, 43], ~, Str], # 44
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 45
  [Add, ~, [29, 45], ~, Int], # 46
  [Add, ~, [34, 45], ~, Int]]} # 47
main::g: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [1, 4], ~, Scalar, 5], # 6
  [Subscript, {kind: array}, [3, 6], 0, Scalar, 5, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "!"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Subscript, {kind: array}, [1, 4], ~, Scalar, 7], # 11
  [Subscript, {kind: array}, [3, 11], ~, Scalar], # 12
  [Assign, ~, [12, 10], 7, Str, 7, true], # 13
  [Return, {implicit: true}, [10], 13, ~, 13]]} # 14
```

## A callee shifts the list under the iterator

The alias stays on its element when the elements move.

```perl
sub g { shift @{$_[0]} }
sub f { my $l = [qw(a b c d)]; my $s = ""; for my $x (@$l) { $s .= $x; g($l); $s .= $x . ";" } "$s|@$l" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
aa;cc;|c d
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: l}, ~, ~, Unknown, 2], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 7
  [ArrayLiteral, ~, [4, 5, 6, 7], 0, ArrayRef], # 8
  [Assign, ~, [3, 8], 8, ArrayRef, 2, true], # 9
  [Loop, {bound: entry}, [9], 9], # 10
  [Phi, {region: 10}, [1, 51], ~, Str], # 11
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Phi, {memory: true, region: 10}, [9, 41], ~, Scalar], # 14
  [Proj, {index: 1}, [10]], # 15
  [Region, {head: 10}, [15]], # 16
  [Phi, {memory: true, region: 16}, [14], ~, Scalar], # 17
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 17], # 18
  [Coerce, {from_repr: Scalar, to_repr: Str}, [18], ~, Str], # 19
  [PadAccess, {sigil: $, symbol: l}, ~, ~, Unknown, 17], # 20
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: "@", strict: false}, [20], 16, Array, 17, true], # 21
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [19, 21], ~, Str, 21], # 22
  [Concat, ~, [13, 22], ~, Str], # 23
  [Return, {implicit: true}, [23], 21, ~, 21], # 24
  [PadAccess, {sigil: $, symbol: l}, ~, ~, Unknown, 9], # 25
  [PostfixDeref, {sigil: "@"}, [25], ~, Array, 9], # 26
  [Count, ~, [26], ~, Int, 9], # 27
  [Count, ~, [26], ~, Int, 14], # 28
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 29
  [Phi, {region: 10}, [29, 53], ~, Int], # 30
  [Proj, {index: 0}, [10]], # 31
  [Exists, {kind: array}, [26, 30], 31, Boolean, 14], # 32
  [Subscript, {kind: array}, [26, 30], ~, Scalar], # 33
  [Subscript, {kind: array}, [26, 30], ~, Scalar, 14], # 34
  [PadAccess, {sigil: $, symbol: l}, ~, ~, Unknown, 14], # 35
  [Ref, ~, [33], ~, ScalarRef], # 36
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 37
  [TernaryExpr, ~, [32, 36, 37], 32, "Maybe[ScalarRef]"], # 38
  [PostfixDeref, {sigil: $}, [38], ~, Scalar, 14], # 39
  [TernaryExpr, ~, [32, 39, 34], 38, Scalar], # 40
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: void}, [35], 40, Scalar, 14, true], # 41
  [Subscript, {kind: array}, [26, 30], ~, Scalar, 41], # 42
  [NumGt, ~, [28, 30], 10, Boolean], # 43
  [Coerce, {from_repr: Scalar, to_repr: Str}, [40], ~, Str], # 44
  [Concat, ~, [11, 44], ~, Str], # 45
  [PostfixDeref, {sigil: $}, [38], ~, Scalar, 41], # 46
  [TernaryExpr, ~, [32, 46, 42], 41, Scalar], # 47
  [Coerce, {from_repr: Scalar, to_repr: Str}, [47], ~, Str], # 48
  [Concat, ~, [45, 48], ~, Str], # 49
  [Constant, {const_type: string, value: ";"}, ~, ~, Str], # 50
  [Concat, ~, [49, 50], ~, Str], # 51
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 52
  [Add, ~, [30, 52], ~, Int]]} # 53
main::g: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [PostfixDeref, {sigil: "@"}, [3], ~, Array, 4], # 5
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [5], 0, Scalar, 4, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A callee writes the iterator through @_

Passed on, the iterator is the element itself.

```perl
sub g { $_[0] = uc $_[0] }
sub f { my $l = [qw(a b)]; my $s = ""; for my $x (@$l) { g($x); $s .= $x } "$s|@$l" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
AB|A B
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [ArrayLiteral, ~, [2, 3], 0, ArrayRef], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Phi, {region: 5}, [1, 41], ~, Str], # 6
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [MemStart], # 9
  [Phi, {memory: true, region: 5}, [9, 33], ~, Unknown], # 10
  [Proj, {index: 1}, [5]], # 11
  [Region, {head: 5}, [11]], # 12
  [Phi, {memory: true, region: 12}, [10], ~, Unknown], # 13
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 13], # 14
  [Coerce, {from_repr: Scalar, to_repr: Str}, [14], ~, Str], # 15
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: "@", strict: false}, [4], ~, Array, 13], # 16
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [15, 16], ~, Str, 13], # 17
  [Concat, ~, [8, 17], ~, Str], # 18
  [Return, {implicit: true}, [18], 12, ~, 13], # 19
  [Count, ~, [4], ~, Int, 9], # 20
  [Count, ~, [4], ~, Int, 10], # 21
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 22
  [Phi, {region: 5}, [22, 39], ~, Int], # 23
  [Proj, {index: 0}, [5]], # 24
  [Exists, {kind: array}, [4, 23], 24, Boolean, 10], # 25
  [Subscript, {kind: array}, [4, 23], ~, Scalar], # 26
  [Subscript, {kind: array}, [4, 23], ~, Scalar, 10], # 27
  [Ref, ~, [26], ~, ScalarRef], # 28
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 29
  [TernaryExpr, ~, [25, 28, 29], 25, "Maybe[ScalarRef]"], # 30
  [PostfixDeref, {sigil: $}, [30], ~, Scalar, 10], # 31
  [TernaryExpr, ~, [25, 31, 27], ~, Scalar], # 32
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: void}, [32], 30, Str, 10, true], # 33
  [Subscript, {kind: array}, [4, 23], ~, Scalar, 33], # 34
  [NumGt, ~, [21, 23], 5, Boolean], # 35
  [PostfixDeref, {sigil: $}, [30], ~, Scalar, 33], # 36
  [TernaryExpr, ~, [25, 36, 34], 33, Scalar], # 37
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 38
  [Add, ~, [23, 38], ~, Int], # 39
  [Coerce, {from_repr: Scalar, to_repr: Str}, [37], ~, Str], # 40
  [Concat, ~, [6, 40], ~, Str]]} # 41
main::g: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Call, {dispatch_kind: builtin, name: uc, param_names: []}, [4], ~, Str], # 5
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 6
  [Assign, ~, [6, 5], 0, Str, 3, true], # 7
  [Return, {implicit: true}, [5], 7, ~, 7]]} # 8
```

## A hole the body fills is seen through the alias

The alias of a missing element reads it lazily; nothing is created by iterating.

```perl
sub f { my @a; $a[1] = 1; my $s = ""; for my $x (@a) { $a[0] = 5; $s .= $x // "u" } print $s, (exists $a[0] ? "e" : "n"), "\n" }
f();
```

```behavior
parses: yes
```

```output
51e
```

```ir
main::__PROGRAM__: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: void}, ~, 0, "Maybe[Boolean]", 2, true], # 3
  [Return, {implicit: true}, [1], 3, ~, 3]]} # 4
main::f: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: a}, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Assign, ~, [4, 3], 0, Int, 5, true], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [1, 41], ~, Str], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Phi, {memory: true, region: 7}, [6, 34], ~, Int], # 10
  [Proj, {index: 1}, [7]], # 11
  [Region, {head: 7}, [11]], # 12
  [Phi, {memory: true, region: 12}, [10], ~, Int], # 13
  [Exists, {kind: array}, [2, 9], ~, Boolean, 13], # 14
  [Constant, {const_type: string, value: e}, ~, ~, Str], # 15
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 16
  [TernaryExpr, ~, [14, 15, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [8, 17, 18], 12, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [19], 19, ~, 13], # 20
  [Count, ~, [2], ~, Int, 6], # 21
  [Phi, {region: 7}, [9, 23], ~, Int], # 22
  [Add, ~, [22, 3], ~, Int], # 23
  [Count, ~, [2], ~, Int, 10], # 24
  [NumGt, ~, [24, 22], 7, Boolean], # 25
  [Proj, {index: 0}, [7]], # 26
  [Subscript, {kind: array}, [2, 9], ~, Scalar], # 27
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 28
  [Exists, {kind: array}, [2, 22], 26, Boolean, 10], # 29
  [Subscript, {kind: array}, [2, 22], ~, Scalar], # 30
  [Ref, ~, [30], ~, ScalarRef], # 31
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 32
  [TernaryExpr, ~, [29, 31, 32], 29, "Maybe[ScalarRef]"], # 33
  [Assign, ~, [27, 28], 33, Int, 10, true], # 34
  [PostfixDeref, {sigil: $}, [33], ~, Scalar, 34], # 35
  [Subscript, {kind: array}, [2, 22], ~, Scalar, 34], # 36
  [TernaryExpr, ~, [29, 35, 36], 34, Scalar], # 37
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 38
  [DefinedOr, ~, [37, 38], ~, Scalar], # 39
  [Coerce, {from_repr: Scalar, to_repr: Str}, [39], ~, Str], # 40
  [Concat, ~, [8, 40], ~, Str]]} # 41
```

## A callee returning a reference to the iterator over a list a call made

The reference the callee hands back is to the element the iterator aliases.

```perl
package S { sub new { bless { n => $_[1] }, $_[0] } sub name { $_[0]{n} } }
package C { sub new { bless {}, shift } sub subs { (S->new("a"), S->new("b"), S->new("a")) } }
sub root { my ($s) = @_; return \$_[0] }
sub f { my ($cls) = @_; my $reg = { subs => [] };
  for my $s ($cls->subs) { my $sname = $s->name; next if grep { ($_->{name} // '') eq $sname } @{ $reg->{subs} }; my $b = root($s); push @{ $reg->{subs} }, { name => $sname, same => ($$b == $s ? 1 : 0) } }
  join ",", map { "$_->{name}:$_->{same}" } @{ $reg->{subs} } }
print f(C->new), "\n";
```

```behavior
parses: yes
```

```output
a:1,b:1
```

```ir
C::new: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [HashLiteral, ~, ~, 0, HashRef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 1, Scalar, 3, true], # 4
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [1, 4], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
C::subs: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: S}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {class_name: S, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: new, package: C, param_names: []}, [1, 2], 0, Object, 3, true], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [Call, {class_name: S, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: new, package: C, param_names: []}, [1, 5], 4, Object, 4, true], # 6
  [Call, {class_name: S, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: new, package: C, param_names: []}, [1, 2], 6, Object, 6, true], # 7
  [ArrayLiteral, ~, [4, 6, 7], ~, List], # 8
  [Coerce, {from_repr: List, to_repr: Scalar}, [7], ~, Scalar], # 9
  [Return, {implicit: true}, [8, 9], 7, ~, 7]]} # 10
S::name: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
S::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [HashLiteral, ~, [1, 5], 0, HashRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7], ~, Scalar, 4], # 8
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [6, 8], 6, Unknown, 4, true], # 9
  [Return, {implicit: true}, [9], 9, ~, 9]]} # 10
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: C}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [], want: list}, [2], 0, Object, 3, true], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::f, package: main, param_names: [], want: list}, [4], 4, Str, 4, true], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, "Maybe[Boolean]"], # 8
  [Return, {implicit: true}, [1], 8, ~, 5]]} # 9
main::f: {start: 0, returns: [26], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Constant, {const_type: string, value: subs}, ~, ~, Str], # 3
  [ArrayLiteral, ~, ~, 0, ArrayRef], # 4
  [HashLiteral, ~, [3, 4], 4, HashRef], # 5
  [Subscript, {kind: hash}, [5, 3], ~, ArrayRef], # 6
  [PadAccess, {sigil: $, symbol: cls}, ~, ~, Unknown], # 7
  [MemStart], # 8
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: subs, package: main, param_names: [], want: list}, [7], 5, Unknown, 8, true], # 9
  [Loop, {bound: entry}, [9], 9], # 10
  [Proj, {index: 1}, [10]], # 11
  [Region, {head: 10}, [11]], # 12
  [Phi, {memory: true, region: 10}, [9, 92], ~, Unknown], # 13
  [Phi, {memory: true, region: 12}, [13], ~, Unknown], # 14
  [Subscript, {kind: hash}, [5, 3], 12, Scalar, 14], # 15
  [ArrayLiteral, ~, ~, 15, ArrayRef], # 16
  [DefinedOr, ~, [15, 16], ~, Scalar], # 17
  [Assign, ~, [6, 17], 16, Scalar, 14, true], # 18
  [Loop, {bound: entry}, [18], 18], # 19
  [Phi, {region: 19}, [2, 65], ~, Array], # 20
  [Phi, {memory: true, region: 19}, [18, 62], ~, Scalar], # 21
  [Proj, {index: 1}, [19]], # 22
  [Region, {head: 19}, [22]], # 23
  [Phi, {memory: true, region: 23}, [21], ~, Scalar], # 24
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 20], ~, Str, 24], # 25
  [Return, {implicit: true}, [25], 23, ~, 24], # 26
  [ArrayLiteral, ~, [9], ~, Array], # 27
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 28
  [Phi, {region: 10}, [28, 107], ~, Int], # 29
  [Subscript, {kind: array}, [27, 29], ~, Scalar], # 30
  [Proj, {index: 0}, [10]], # 31
  [Ref, ~, [30], 31, ScalarRef, 13], # 32
  [PostfixDeref, {sigil: $}, [32], ~, Scalar, 13], # 33
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: name, package: main, param_names: [], want: scalar}, [33], 32, Unknown, 13, true], # 34
  [Subscript, {kind: hash}, [5, 3], 34, Scalar, 34], # 35
  [ArrayLiteral, ~, ~, 35, ArrayRef], # 36
  [DefinedOr, ~, [35, 36], ~, Scalar], # 37
  [Assign, ~, [6, 37], 36, Scalar, 34, true], # 38
  [Loop, {bound: entry}, [38], 38], # 39
  [Phi, {memory: true, region: 39}, [38, 100], ~, Scalar], # 40
  [Proj, {index: 1}, [39]], # 41
  [Region, {head: 39}, [41]], # 42
  [Phi, {memory: true, region: 42}, [40], ~, Scalar], # 43
  [PostfixDeref, {sigil: $}, [32], ~, Scalar, 43], # 44
  [ArrayLiteral, ~, ~, ~, Array], # 45
  [Phi, {region: 39}, [45, 108], ~, Array], # 46
  [Count, ~, [46], ~, Int], # 47
  [If, ~, [42, 47], 42], # 48
  [Proj, {index: 1}, [48]], # 49
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::root, package: main, param_names: [], want: scalar}, [44], 49, ScalarRef, 43, true], # 50
  [Subscript, {kind: hash}, [5, 3], 50, Scalar, 50], # 51
  [PostfixDeref, {sigil: "@"}, [17], ~, Array, 18], # 52
  [Phi, {region: 19}, [28, 96], ~, Int], # 53
  [Subscript, {kind: array}, [52, 53], ~, Scalar, 21], # 54
  [Constant, {const_type: string, value: name}, ~, ~, Str], # 55
  [Proj, {index: 0}, [19]], # 56
  [Subscript, {kind: hash}, [54, 55], 56, Scalar, 21, true], # 57
  [Coerce, {from_repr: Unknown, to_repr: Str}, [57], ~, Str], # 58
  [Constant, {const_type: string, value: ":"}, ~, ~, Str], # 59
  [Concat, ~, [58, 59], ~, Str], # 60
  [Constant, {const_type: string, value: same}, ~, ~, Str], # 61
  [Subscript, {kind: hash}, [54, 61], 57, Scalar, 57, true], # 62
  [Coerce, {from_repr: Unknown, to_repr: Str}, [62], ~, Str], # 63
  [Concat, ~, [60, 63], ~, Str], # 64
  [ListAppend, {collector: map}, [20, 64], ~, Array], # 65
  [Count, ~, [52], ~, Int, 21], # 66
  [Count, ~, [27], ~, Int, 9], # 67
  [ArrayLiteral, ~, ~, 51, ArrayRef], # 68
  [DefinedOr, ~, [51, 68], ~, Scalar], # 69
  [Assign, ~, [6, 69], 68, Scalar, 50, true], # 70
  [NumGt, ~, [66, 53], 19, Boolean], # 71
  [Count, ~, [52], ~, Int, 18], # 72
  [ArgsSource, ~, ~, ~, Array], # 73
  [Assign, {record: true, targets: 1}, [7, 73], ~, List], # 74
  [Count, ~, [27], ~, Int, 13], # 75
  [Subscript, {kind: array}, [27, 29], ~, Scalar, 13], # 76
  [Subscript, {kind: array}, [27, 29], ~, Scalar, 43], # 77
  [Subscript, {kind: array}, [27, 29], ~, Scalar, 70], # 78
  [NumGt, ~, [75, 29], 10, Boolean], # 79
  [PostfixDeref, {sigil: "@"}, [69], ~, Array, 70], # 80
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 5, package: main, sigil: $, strict: false}, [50], ~, Scalar, 70], # 81
  [Coerce, {from_repr: Scalar, to_repr: Num}, [81], ~, Num], # 82
  [PostfixDeref, {sigil: $}, [32], 70, Scalar, 70], # 83
  [Coerce, {from_repr: Scalar, to_repr: Num}, [83], ~, Num], # 84
  [NumEq, ~, [82, 84], ~, Boolean], # 85
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 86
  [TernaryExpr, ~, [85, 86, 28], ~, Int], # 87
  [HashLiteral, ~, [55, 34, 61, 87], 83, HashRef], # 88
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [80, 88], 88, Int, 70, true], # 89
  [Proj, {index: 0}, [48]], # 90
  [Region, {head: 48}, [90, 89]], # 91
  [Phi, {memory: true, predecessors: [90, 49], region: 91}, [43, 89], ~, Scalar], # 92
  [PostfixDeref, {sigil: "@"}, [37], ~, Array, 38], # 93
  [Count, ~, [93], ~, Int, 38], # 94
  [Coerce, {from_repr: Unknown, to_repr: Str}, [34], ~, Str], # 95
  [Add, ~, [53, 86], ~, Int], # 96
  [Phi, {region: 39}, [28, 109], ~, Int], # 97
  [Subscript, {kind: array}, [93, 97], ~, Scalar, 40], # 98
  [Proj, {index: 0}, [39]], # 99
  [Subscript, {kind: hash}, [98, 55], 99, Scalar, 40, true], # 100
  [Count, ~, [93], ~, Int, 40], # 101
  [NumGt, ~, [101, 97], 39, Boolean], # 102
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 103
  [DefinedOr, ~, [100, 103], ~, Scalar], # 104
  [Coerce, {from_repr: Unknown, to_repr: Str}, [104], ~, Str], # 105
  [StrEq, ~, [105, 95], ~, Boolean], # 106
  [Add, ~, [29, 86], ~, Int], # 107
  [ListAppend, {collector: grep}, [46, 98, 106], ~, Array], # 108
  [Add, ~, [97, 86], ~, Int]]} # 109
main::root: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Ref, ~, [3], 0, ScalarRef, 4, true], # 5
  [Return, ~, [5], 5, ~, 5], # 6
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown], # 7
  [Assign, {record: true, targets: 1}, [7, 1], ~, List]]} # 8
```

## The keys of a referenced hash read before a store

The keys are a copy taken where they are read.

```perl
sub f { my $h = {a=>1}; my $k = join ",", sort keys %$h; $h->{b} = 2; return $k }
print f(), "\n";
```

```behavior
parses: yes
```

```output
a
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [HashLiteral, ~, [2, 3], 0, HashRef], # 4
  [MemStart], # 5
  [PostfixDeref, {sigil: "%"}, [4], ~, Hash, 5], # 6
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [6], ~, List, 5], # 7
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [7], ~, List, 5], # 8
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 8], ~, Str, 5], # 9
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 10
  [Subscript, {kind: hash}, [4, 10], ~, Undef], # 11
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 12
  [Assign, ~, [11, 12], 4, Int, 5, true], # 13
  [Return, ~, [9], 13, ~, 13]]} # 14
```

## A nested loop that writes the list the outer loop walks

The outer iterator reads each element where the body reads it, after the inner loop wrote the earlier ones.

```perl
sub f { my @a; push @a, 1, 2; my $s = "";
  for my $x (@a) { $s .= $x; $_ = 0 for @a }
  return "$s|@a" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
10|0 0
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: a}, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 3, 4], 0, Int, 5, true], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [1, 52], ~, Str], # 8
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Phi, {memory: true, region: 7}, [6, 46], ~, Unknown], # 11
  [Proj, {index: 1}, [7]], # 12
  [Region, {head: 7}, [12]], # 13
  [Phi, {memory: true, region: 13}, [11], ~, Unknown], # 14
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 14], # 15
  [Coerce, {from_repr: Scalar, to_repr: Str}, [15], ~, Str], # 16
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [16, 2], ~, Str, 14], # 17
  [Concat, ~, [10, 17], ~, Str], # 18
  [Return, ~, [18], 13, ~, 14], # 19
  [Count, ~, [2], ~, Int, 6], # 20
  [Count, ~, [2], ~, Int, 11], # 21
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 22
  [Phi, {region: 7}, [22, 40], ~, Int], # 23
  [Proj, {index: 0}, [7]], # 24
  [Exists, {kind: array}, [2, 23], 24, Boolean, 11], # 25
  [Subscript, {kind: array}, [2, 23], ~, Scalar], # 26
  [Subscript, {kind: array}, [2, 23], ~, Scalar, 11], # 27
  [Ref, ~, [26], ~, ScalarRef], # 28
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 29
  [TernaryExpr, ~, [25, 28, 29], 25, "Maybe[ScalarRef]"], # 30
  [PostfixDeref, {sigil: $}, [30], ~, Scalar, 11], # 31
  [TernaryExpr, ~, [25, 31, 27], 30, Scalar], # 32
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, 32, Scalar, 11], # 33
  [Loop, {bound: entry}, [33], 33], # 34
  [Phi, {memory: true, region: 34}, [11, 50], ~, Unknown], # 35
  [Count, ~, [2], ~, Int, 35], # 36
  [Phi, {region: 34}, [22, 39], ~, Int], # 37
  [Subscript, {kind: array}, [2, 37], ~, Scalar], # 38
  [Add, ~, [37, 3], ~, Int], # 39
  [Add, ~, [23, 3], ~, Int], # 40
  [NumGt, ~, [21, 23], 7, Boolean], # 41
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 42
  [Proj, {index: 1}, [34]], # 43
  [Region, {head: 34}, [43]], # 44
  [Phi, {memory: true, region: 44}, [35], ~, Unknown], # 45
  [EntryWrite, ~, [42, 33], 44, Unknown, 45, true], # 46
  [NumGt, ~, [36, 37], 34, Boolean], # 47
  [Proj, {index: 0}, [34]], # 48
  [EntryWrite, ~, [42, 22], 48, Unknown, 35, true], # 49
  [Assign, ~, [38, 22], 49, Int, 49, true], # 50
  [Coerce, {from_repr: Scalar, to_repr: Str}, [32], ~, Str], # 51
  [Concat, ~, [8, 51], ~, Str]]} # 52
```

## A carried read between two stores through a reference

The store through the reference is seen by the iterator read between the two stores.

```perl
sub f { my @a = (1,2); my $r = \@a; my $s = "";
  for my $x (@a) { $r->[0] = 7; $s .= $x; $r->[0] = 8 }
  return "$s|@a" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
72|8 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 41], ~, Str], # 3
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [MemStart], # 6
  [Phi, {memory: true, region: 2}, [6, 38], ~, Unknown], # 7
  [Proj, {index: 1}, [2]], # 8
  [Region, {head: 2}, [8]], # 9
  [Phi, {memory: true, region: 9}, [7], ~, Unknown], # 10
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 10], # 11
  [Coerce, {from_repr: Scalar, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 13
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 14
  [ArrayLiteral, {sigil: "@", symbol: a}, [13, 14], ~, Array], # 15
  [PostfixDeref, {sigil: "@"}, [15], ~, Array, 10], # 16
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 16], ~, Str, 10], # 17
  [Concat, ~, [5, 17], ~, Str], # 18
  [Return, ~, [18], 9, ~, 10], # 19
  [Count, ~, [15], ~, Int, 7], # 20
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 21
  [Phi, {region: 2}, [21, 39], ~, Int], # 22
  [NumGt, ~, [20, 22], 2, Boolean], # 23
  [Proj, {index: 0}, [2]], # 24
  [Exists, {kind: array}, [15, 22], 24, Boolean, 7], # 25
  [Ref, ~, [15], ~, ArrayRef], # 26
  [Subscript, {kind: array}, [26, 21], ~, Scalar], # 27
  [Constant, {const_type: integer, value: "8"}, ~, ~, Int], # 28
  [Subscript, {kind: array}, [15, 22], ~, Scalar], # 29
  [Ref, ~, [29], ~, ScalarRef], # 30
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 31
  [TernaryExpr, ~, [25, 30, 31], 25, "Maybe[ScalarRef]"], # 32
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 33
  [Assign, ~, [27, 33], 32, Int, 7, true], # 34
  [PostfixDeref, {sigil: $}, [32], ~, Scalar, 34], # 35
  [Subscript, {kind: array}, [15, 22], ~, Scalar, 34], # 36
  [TernaryExpr, ~, [25, 35, 36], 34, Scalar], # 37
  [Assign, ~, [27, 28], 37, Int, 34, true], # 38
  [Add, ~, [22, 13], ~, Int], # 39
  [Coerce, {from_repr: Scalar, to_repr: Str}, [37], ~, Str], # 40
  [Concat, ~, [3, 40], ~, Str], # 41
  [Count, ~, [15], ~, Int, 6]]} # 42
```

## An array element passed to a callee that writes it

Arguments are passed by alias: the callee writes the element, and a later read of the whole array sees it.

```perl
sub g { $_[0] = 5 }
sub f { my @n = (1, 2); my $s = "@n"; g($n[0]); g($_) for @n[1 .. 1]; return "$s|@n" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
1 2|5 5
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 1], # 2
  [Coerce, {from_repr: Scalar, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [3, 4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [ArrayLiteral, {sigil: "@", symbol: "n"}, [4, 5], ~, Array], # 9
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [9, 10], ~, Int], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: void}, [11], 0, Int, 1, true], # 12
  [Loop, {bound: entry}, [12], 12], # 13
  [Phi, {memory: true, region: 13}, [12, 35], ~, Int], # 14
  [Proj, {index: 1}, [13]], # 15
  [Region, {head: 13}, [15]], # 16
  [Phi, {memory: true, region: 16}, [14], ~, Int], # 17
  [PostfixDeref, {sigil: "@"}, [9], ~, Array, 17], # 18
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [3, 18], ~, Str, 17], # 19
  [Concat, ~, [8, 19], ~, Str], # 20
  [Return, ~, [20], 16, ~, 17], # 21
  [ArrayLiteral, ~, [4], ~, Array], # 22
  [PostfixDeref, {sigil: "@"}, [22], ~, Array, 12], # 23
  [Slice, {kind: array}, [23, 9], ~, List], # 24
  [ArrayLiteral, ~, [24], ~, Array], # 25
  [Count, ~, [25], ~, Int, 12], # 26
  [Count, ~, [25], ~, Int, 14], # 27
  [Phi, {region: 13}, [10, 36], ~, Int], # 28
  [NumGt, ~, [27, 28], 13, Boolean], # 29
  [Proj, {index: 0}, [13]], # 30
  [Subscript, {kind: array}, [25, 28], ~, Scalar, 14], # 31
  [Subscript, {kind: array}, [25, 28], ~, Scalar], # 32
  [Ref, ~, [32], ~, ScalarRef], # 33
  [LocalAlias, {name: _}, [33], 30, Unknown, 14], # 34
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: void}, [31], 34, Int, 14, true], # 35
  [Add, ~, [28, 4], ~, Int]]} # 36
main::g: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Assign, ~, [4, 1], 0, Int, 5, true], # 6
  [Return, {implicit: true}, [1], 6, ~, 6]]} # 7
```

## The implicit $_ over an array, passed to a callee that writes it

The topic is the element itself, so the callee writes into the array.

```perl
sub g { $_[0] = $_[0] * 10 }
sub f { my @n = (1, 2); g($_) for @n; return "@n" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
10 20
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {memory: true, region: 2}, [1, 27], ~, Unknown], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Phi, {memory: true, region: 5}, [3], ~, Unknown], # 6
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 6], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 9
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 10
  [ArrayLiteral, {sigil: "@", symbol: "n"}, [9, 10], ~, Array], # 11
  [PostfixDeref, {sigil: "@"}, [11], ~, Array, 6], # 12
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [8, 12], ~, Str, 6], # 13
  [Return, ~, [13], 5, ~, 6], # 14
  [Count, ~, [11], ~, Int, 3], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Phi, {region: 2}, [16, 28], ~, Int], # 17
  [NumGt, ~, [15, 17], 2, Boolean], # 18
  [Proj, {index: 0}, [2]], # 19
  [Exists, {kind: array}, [11, 17], 19, Boolean, 3], # 20
  [Subscript, {kind: array}, [11, 17], ~, Int, 3], # 21
  [Subscript, {kind: array}, [11, 17], ~, Scalar], # 22
  [Ref, ~, [22], ~, ScalarRef], # 23
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 24
  [TernaryExpr, ~, [20, 23, 24], ~, "Maybe[ScalarRef]"], # 25
  [LocalAlias, {name: _}, [25], 20, Unknown, 3], # 26
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: void}, [21], 26, Num, 3, true], # 27
  [Add, ~, [17, 9], ~, Int], # 28
  [Count, ~, [11], ~, Int, 1]]} # 29
main::g: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 8
  [Assign, ~, [8, 7], 0, Num, 3, true], # 9
  [Return, {implicit: true}, [7], 9, ~, 9]]} # 10
```

## An inner loop over an element of a referenced array that never reads its iterator

The pass binds nothing the body reads; the loop still counts the elements.

```perl
sub set { my ($c, $p) = @_; push $c->[$p]->@*, [1, undef, 2] }
sub f { my @chart = map { [] } 0 .. 2; my $n = 0;
  for my $pos (0 .. 2) { set(\@chart, $pos);
    if ($ENV{P} // 1) { for my $oh ($chart[$pos]->@*) { $n++ } }
    $chart[$pos - 1] = [] if $pos > 1 }
  return $n }
print f(), "\n";
```

```behavior
parses: yes
```

```output
3
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::f, package: main, param_names: [], want: list}, ~, 0, Int, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Proj, {index: 1}, [2]], # 3
  [Region, {head: 2}, [3]], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Phi, {region: 5}, [1, 48], ~, Int], # 6
  [Proj, {index: 1}, [5]], # 7
  [Region, {head: 5}, [7]], # 8
  [MemStart], # 9
  [Phi, {memory: true, region: 2}, [9, 10], ~, Unknown], # 10
  [Phi, {memory: true, region: 4}, [10], ~, Unknown], # 11
  [Phi, {memory: true, region: 5}, [11, 63], ~, Unknown], # 12
  [Phi, {memory: true, region: 8}, [12], ~, Unknown], # 13
  [Return, ~, [6], 8, ~, 13], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 16
  [ArrayLiteral, ~, [1, 15, 16], ~, Array], # 17
  [PostfixDeref, {sigil: "@"}, [17], ~, Array, 9], # 18
  [Count, ~, [18], ~, Int, 10], # 19
  [Phi, {region: 2}, [1, 64], ~, Int], # 20
  [NumGt, ~, [19, 20], 2, Boolean], # 21
  [Proj, {index: 0}, [2]], # 22
  [ArrayLiteral, ~, ~, ~, Array], # 23
  [Phi, {region: 2}, [23, 66], ~, Array], # 24
  [Ref, ~, [24], ~, ArrayRef], # 25
  [PadAccess, {sigil: $, symbol: pos}, ~, ~, Unknown, 12], # 26
  [Phi, {region: 5}, [1, 67], ~, Int], # 27
  [Proj, {index: 0}, [5]], # 28
  [Assign, ~, [26, 27], 28, Int, 12, true], # 29
  [PadAccess, {sigil: $, symbol: pos}, ~, ~, Unknown, 29], # 30
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::set, package: main, param_names: [], want: void}, [25, 30], 29, Int, 29, true], # 31
  [PadAccess, {sigil: $, symbol: pos}, ~, ~, Unknown, 31], # 32
  [Subscript, {kind: array}, [24, 32], ~, Scalar], # 33
  [EnvRead, {key: P}, ~, ~, Str], # 34
  [DefinedOr, ~, [34, 15], ~, Str], # 35
  [If, ~, [31, 35], 31], # 36
  [Proj, {index: 0}, [36]], # 37
  [Subscript, {kind: array}, [24, 32], 37, Scalar, 31], # 38
  [ArrayLiteral, ~, ~, 38, ArrayRef], # 39
  [DefinedOr, ~, [38, 39], ~, Scalar], # 40
  [Assign, ~, [33, 40], 39, Scalar, 31, true], # 41
  [Loop, {bound: entry}, [41], 41], # 42
  [Phi, {region: 42}, [6, 51], ~, Int], # 43
  [Proj, {index: 1}, [42]], # 44
  [Region, {head: 42}, [44]], # 45
  [Proj, {index: 1}, [36]], # 46
  [Region, {head: 36}, [45, 46]], # 47
  [Phi, {predecessors: [37, 46], region: 47}, [43, 6], ~, Int], # 48
  [ArrayLiteral, ~, ~, 22, ArrayRef], # 49
  [Phi, {region: 42}, [1, 70], ~, Int], # 50
  [Add, ~, [43, 15], ~, Int], # 51
  [Phi, {memory: true, predecessors: [37, 46], region: 47}, [41, 31], ~, Scalar], # 52
  [PadAccess, {sigil: $, symbol: pos}, ~, ~, Num, 52], # 53
  [Subtract, ~, [53, 15], ~, Num], # 54
  [Subscript, {kind: array}, [24, 54], ~, Scalar], # 55
  [NumGt, ~, [53, 15], ~, Boolean], # 56
  [If, ~, [47, 56], 47], # 57
  [Proj, {index: 0}, [57]], # 58
  [ArrayLiteral, ~, ~, 58, ArrayRef], # 59
  [Assign, ~, [55, 59], 59, ArrayRef, 52, true], # 60
  [Proj, {index: 1}, [57]], # 61
  [Region, {head: 57}, [60, 61]], # 62
  [Phi, {memory: true, predecessors: [58, 61], region: 62}, [60, 52], ~, Scalar], # 63
  [Add, ~, [20, 15], ~, Int], # 64
  [Subscript, {kind: array}, [18, 20], ~, Scalar, 10], # 65
  [ListAppend, {collector: map}, [24, 49], ~, Array], # 66
  [Add, ~, [27, 15], ~, Int], # 67
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 68
  [NumGt, ~, [68, 27], 5, Boolean], # 69
  [Add, ~, [50, 15], ~, Int], # 70
  [PostfixDeref, {sigil: "@"}, [40], ~, Array, 41], # 71
  [Count, ~, [71], ~, Int, 41], # 72
  [NumGt, ~, [72, 50], 42, Boolean], # 73
  [Count, ~, [18], ~, Int, 9], # 74
  [Proj, {index: 0}, [42]]]} # 75
main::set: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 1
  [PadAccess, {sigil: $, symbol: p}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], 0, Scalar, 3], # 4
  [ArrayLiteral, ~, ~, 4, ArrayRef], # 5
  [DefinedOr, ~, [4, 5], ~, Scalar], # 6
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 7
  [Assign, ~, [7, 6], 5, Scalar, 3, true], # 8
  [PostfixDeref, {sigil: "@"}, [6], ~, Array, 8], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 11
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 12
  [ArrayLiteral, ~, [10, 11, 12], 8, ArrayRef], # 13
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [9, 13], 13, Int, 8, true], # 14
  [Return, {implicit: true}, [14], 14, ~, 14], # 15
  [ArgsSource, ~, ~, ~, Array], # 16
  [Assign, {record: true, targets: 2}, [1, 2, 16], ~, List]]} # 17
```

## A list built after a loop from a scalar passed to a call

The read after the loop sees the memory the loop leaves with, so the list is declared after the loop.

```perl
package N { sub new { my ($c, $n, @k) = @_; bless { n => $n, k => [@k] }, $c } sub kids { $_[0]{k} } sub n { $_[0]{n} } }
sub vals { ({ a => 1 }, [2], { b => 1 }) }
sub f { my ($ctx) = @_; my @stmts;
  for my $val (vals($ctx)) {
    if (ref($val) eq 'ARRAY') { } elsif (ref($val) eq 'HASH' && exists $val->{a}) { push @stmts, $val } }
  my @walk = ($ctx); my $s = "";
  while (my $node = pop @walk) { $s .= $node->n; push @walk, $node->kids->@* }
  return $s . scalar(@stmts) }
print f(N->new("a", N->new("b"))), "\n";
```

```behavior
parses: yes
```

```output
ab1
```

```ir
N::kids: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
N::n: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
N::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 3
  [PadAccess, {sigil: "@", symbol: k}, ~, ~, Unknown], # 4
  [ArrayLiteral, ~, [4], 0, ArrayRef], # 5
  [HashLiteral, ~, [1, 2, 3, 5], 5, HashRef], # 6
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 7
  [MemStart], # 8
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [6, 7], 6, Unknown, 8, true], # 9
  [Return, {implicit: true}, [9], 9, ~, 9], # 10
  [ArgsSource, ~, ~, ~, Array], # 11
  [Assign, {record: true, targets: 3}, [7, 2, 4, 11], ~, List]]} # 12
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: new, package: main, param_names: [], want: list}, [2, 4], 0, Object, 5, true], # 6
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: new, package: main, param_names: [], want: list}, [2, 3, 6], 6, Object, 6, true], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::f, package: main, param_names: [], want: list}, [7], 7, Str, 7, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
main::f: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: ctx}, ~, ~, Unknown, 2], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Assign, {targets: 1}, [3, 4], 0, List, 2, true], # 5
  [PadAccess, {sigil: $, symbol: ctx}, ~, ~, Unknown, 5], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::vals, package: main, param_names: [], want: list}, [6], 5, List, 5, true], # 7
  [Loop, {bound: entry}, [7], 7], # 8
  [Proj, {index: 1}, [8]], # 9
  [Region, {head: 8}, [9]], # 10
  [Loop, {bound: each}, [10], 10], # 11
  [Phi, {region: 11}, [1, 31], ~, Str], # 12
  [PadAccess, {sigil: "@", symbol: stmts}, ~, ~, Array], # 13
  [Phi, {memory: true, region: 8}, [7, 74], ~, Unknown], # 14
  [Phi, {memory: true, region: 10}, [14], ~, Unknown], # 15
  [Phi, {memory: true, region: 11}, [15, 34], ~, Unknown], # 16
  [Proj, {index: 1}, [11]], # 17
  [Region, {head: 11}, [17]], # 18
  [Phi, {memory: true, region: 18}, [16], ~, Unknown], # 19
  [Count, ~, [13], ~, Int, 19], # 20
  [Concat, ~, [12, 20], ~, Str], # 21
  [Return, ~, [21], 18, ~, 19], # 22
  [ArrayLiteral, ~, [7], ~, Array], # 23
  [Count, ~, [23], ~, Int, 7], # 24
  [PadAccess, {sigil: $, symbol: ctx}, ~, ~, Unknown, 15], # 25
  [ArrayLiteral, {sigil: "@", symbol: walk}, [25], ~, Array], # 26
  [Call, {dispatch_kind: builtin, name: pop, param_names: []}, [26], 11, Scalar, 16, true], # 27
  [Proj, {index: 0}, [11]], # 28
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: "n", package: main, param_names: [], want: scalar}, [27], 28, Unknown, 27, true], # 29
  [Coerce, {from_repr: Unknown, to_repr: Str}, [29], ~, Str], # 30
  [Concat, ~, [12, 30], ~, Str], # 31
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: kids, package: main, param_names: [], want: scalar}, [27], 29, Unknown, 29, true], # 32
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 7, package: main, sigil: "@", strict: false}, [32], 32, Array, 32, true], # 33
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [26, 33], 33, Int, 33, true], # 34
  [Count, ~, [23], ~, Int, 14], # 35
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 36
  [Phi, {region: 8}, [36, 78], ~, Int], # 37
  [Subscript, {kind: array}, [23, 37], ~, Scalar], # 38
  [Subscript, {kind: array}, [23, 37], ~, Scalar, 14], # 39
  [Subscript, {kind: array}, [23, 37], ~, Scalar, 14], # 40
  [Subscript, {kind: array}, [23, 37], ~, Scalar, 14], # 41
  [Proj, {index: 0}, [8]], # 42
  [Ref, ~, [38], 42, ScalarRef, 14], # 43
  [PostfixDeref, {sigil: $}, [43], ~, Scalar, 14], # 44
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 45
  [PostfixDeref, {sigil: $}, [43], 43, Scalar, 14], # 46
  [RefType, ~, [46], ~, Str, 14], # 47
  [Constant, {const_type: string, value: ARRAY}, ~, ~, Str], # 48
  [StrEq, ~, [47, 48], ~, Boolean], # 49
  [If, ~, [46, 49], 46], # 50
  [Proj, {index: 1}, [50]], # 51
  [PostfixDeref, {sigil: $}, [43], ~, Scalar, 14], # 52
  [RefType, ~, [52], ~, Str, 14], # 53
  [Constant, {const_type: string, value: HASH}, ~, ~, Str], # 54
  [StrEq, ~, [53, 54], ~, Boolean], # 55
  [If, ~, [51, 55], 51], # 56
  [Proj, {index: 0}, [56]], # 57
  [Exists, {kind: hash}, [44, 45], 57, Boolean, 14, true], # 58
  [Proj, {index: 1}, [56]], # 59
  [Region, {head: 56}, [58, 59]], # 60
  [Phi, {memory: true, predecessors: [57, 59], region: 60}, [58, 14], ~, Unknown], # 61
  [Subscript, {kind: array}, [23, 37], ~, Scalar, 61], # 62
  [NumGt, ~, [35, 37], 8, Boolean], # 63
  [PostfixDeref, {sigil: $}, [43], ~, Scalar, 61], # 64
  [Phi, {predecessors: [57, 59], region: 60}, [58, 55], ~, Boolean], # 65
  [If, ~, [60, 65], 60], # 66
  [Proj, {index: 0}, [66]], # 67
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [13, 64], 67, Int, 61, true], # 68
  [Proj, {index: 1}, [66]], # 69
  [Region, {head: 66}, [69, 68]], # 70
  [Phi, {memory: true, predecessors: [69, 67], region: 70}, [61, 68], ~, Unknown], # 71
  [Proj, {index: 0}, [50]], # 72
  [Region, {head: 50}, [72, 70]], # 73
  [Phi, {memory: true, predecessors: [72, 51], region: 73}, [14, 71], ~, Unknown], # 74
  [Not, ~, [27], ~, Boolean], # 75
  [Not, ~, [75], 11, Boolean], # 76
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 77
  [Add, ~, [37, 77], ~, Int]]} # 78
main::vals: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [HashLiteral, ~, [1, 2], 0, HashRef], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [ArrayLiteral, ~, [4], 3, ArrayRef], # 5
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 6
  [HashLiteral, ~, [6, 2], 5, HashRef], # 7
  [ArrayLiteral, ~, [3, 5, 7], ~, List], # 8
  [Coerce, {from_repr: List, to_repr: Scalar}, [7], ~, Scalar], # 9
  [MemStart], # 10
  [Return, {implicit: true}, [8, 9], 7, ~, 10]]} # 11
```

## A callee reads the topic of a foreach, a grep and a range by name

Each pass aliases `$_` to its element (a fresh value for a range), so a callee that matches against it sees the element.

```perl
sub is_x { /x/ } sub show { print $_ }
sub f { my @a = qw(ax b xc); my @g = grep { is_x() } @a; show() for @a; show() for 1 .. 2; return " @g" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
axbxc12 ax xc
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 1
  [MemStart], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {memory: true, region: 3}, [2, 47], ~, Unknown], # 4
  [Proj, {index: 1}, [3]], # 5
  [Region, {head: 3}, [5]], # 6
  [Phi, {memory: true, region: 6}, [4], ~, Unknown], # 7
  [Loop, {bound: entry}, [6], 6], # 8
  [Phi, {memory: true, region: 8}, [7, 62], ~, Unknown], # 9
  [Proj, {index: 1}, [8]], # 10
  [Region, {head: 8}, [10]], # 11
  [Phi, {memory: true, region: 11}, [9], ~, Unknown], # 12
  [Loop, {bound: entry}, [11], 11], # 13
  [Phi, {memory: true, region: 13}, [12, 39], ~, Unknown], # 14
  [Proj, {index: 1}, [13]], # 15
  [Region, {head: 13}, [15]], # 16
  [Phi, {memory: true, region: 16}, [14], ~, Unknown], # 17
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 17], # 18
  [Coerce, {from_repr: Scalar, to_repr: Str}, [18], ~, Str], # 19
  [ArrayLiteral, ~, ~, ~, Array], # 20
  [Phi, {region: 3}, [20, 48], ~, Array], # 21
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [19, 21], ~, Str, 17], # 22
  [Concat, ~, [1, 22], ~, Str], # 23
  [Return, ~, [23], 16, ~, 17], # 24
  [Constant, {const_type: string, value: ax}, ~, ~, Str], # 25
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 26
  [Constant, {const_type: string, value: xc}, ~, ~, Str], # 27
  [ArrayLiteral, {sigil: "@", symbol: a}, [25, 26, 27], ~, Array], # 28
  [Count, ~, [28], ~, Int, 4], # 29
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 30
  [Phi, {region: 3}, [30, 40], ~, Int], # 31
  [NumGt, ~, [29, 31], 3, Boolean], # 32
  [Proj, {index: 0}, [3]], # 33
  [Exists, {kind: array}, [28, 31], 33, Boolean, 4], # 34
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 35
  [Phi, {region: 13}, [35, 64], ~, Int], # 36
  [Proj, {index: 0}, [13]], # 37
  [LocalAlias, {name: _}, [36], 37, Unknown, 14], # 38
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::show, package: main, param_names: [], want: void}, ~, 38, "Maybe[Boolean]", 14, true], # 39
  [Add, ~, [31, 35], ~, Int], # 40
  [Subscript, {kind: array}, [28, 31], ~, Str, 4], # 41
  [Subscript, {kind: array}, [28, 31], ~, Scalar], # 42
  [Ref, ~, [42], ~, ScalarRef], # 43
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 44
  [TernaryExpr, ~, [34, 43, 44], ~, "Maybe[ScalarRef]"], # 45
  [LocalAlias, {name: _}, [45], 34, Unknown, 4], # 46
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::is_x, package: main, param_names: [], want: scalar}, ~, 46, Boolean, 4, true], # 47
  [ListAppend, {collector: grep}, [21, 41, 47], ~, Array], # 48
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 49
  [NumGt, ~, [49, 36], 13, Boolean], # 50
  [Count, ~, [28], ~, Int, 2], # 51
  [Count, ~, [28], ~, Int, 7], # 52
  [Count, ~, [28], ~, Int, 9], # 53
  [Phi, {region: 8}, [30, 63], ~, Int], # 54
  [Proj, {index: 0}, [8]], # 55
  [Exists, {kind: array}, [28, 54], 55, Boolean, 9], # 56
  [Subscript, {kind: array}, [28, 54], ~, Scalar], # 57
  [NumGt, ~, [53, 54], 8, Boolean], # 58
  [Ref, ~, [57], ~, ScalarRef], # 59
  [TernaryExpr, ~, [56, 59, 44], ~, "Maybe[ScalarRef]"], # 60
  [LocalAlias, {name: _}, [60], 56, Unknown, 9], # 61
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::show, package: main, param_names: [], want: void}, ~, 61, "Maybe[Boolean]", 9, true], # 62
  [Add, ~, [54, 35], ~, Int], # 63
  [Add, ~, [36, 35], ~, Int]]} # 64
main::is_x: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 1
  [Coerce, {from_repr: Scalar, to_repr: Str}, [1], ~, Str], # 2
  [RegexMatch, {flags: "", pattern: x}, [2], ~, Boolean], # 3
  [MemStart], # 4
  [Return, {implicit: true}, [3], 0, ~, 4]]} # 5
main::show: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar, 1], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Print, ~, [3], 0, "Maybe[Boolean]"], # 4
  [Return, {implicit: true}, [4], 4, ~, 1]]} # 5
```

## A callee writes the topic of a foreach by name

The write lands in the element the topic aliases, and the topic is restored after the loop.

```perl
sub bump { $_ .= "!" }
sub f { my @a = (1, 2); $_ = "top"; bump() for @a; return "$_|@a" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
top|1! 2!
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::bump: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar, 1], # 2
  [Coerce, {from_repr: Scalar, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "!"}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 6
  [EntryWrite, ~, [6, 5], 0, Unknown, 1, true], # 7
  [Return, {implicit: true}, [5], 7, ~, 7]]} # 8
main::f: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 1
  [Constant, {const_type: string, value: top}, ~, ~, Str], # 2
  [MemStart], # 3
  [EntryWrite, ~, [1, 2], 0, Unknown, 3, true], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Phi, {memory: true, region: 5}, [4, 34], ~, Unknown], # 6
  [Proj, {index: 1}, [5]], # 7
  [Region, {head: 5}, [7]], # 8
  [Phi, {memory: true, region: 8}, [6], ~, Unknown], # 9
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Str, 9], # 10
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 9], # 13
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 16
  [ArrayLiteral, {sigil: "@", symbol: a}, [15, 16], ~, Array], # 17
  [PostfixDeref, {sigil: "@"}, [17], ~, Array, 9], # 18
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [14, 18], ~, Str, 9], # 19
  [Concat, ~, [12, 19], ~, Str], # 20
  [Return, ~, [20], 8, ~, 9], # 21
  [Count, ~, [17], ~, Int, 4], # 22
  [Count, ~, [17], ~, Int, 6], # 23
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 24
  [Phi, {region: 5}, [24, 35], ~, Int], # 25
  [NumGt, ~, [23, 25], 5, Boolean], # 26
  [Proj, {index: 0}, [5]], # 27
  [Exists, {kind: array}, [17, 25], 27, Boolean, 6], # 28
  [Subscript, {kind: array}, [17, 25], ~, Scalar], # 29
  [Ref, ~, [29], ~, ScalarRef], # 30
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 31
  [TernaryExpr, ~, [28, 30, 31], ~, "Maybe[ScalarRef]"], # 32
  [LocalAlias, {name: _}, [32], 28, Unknown, 6], # 33
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::bump, package: main, param_names: [], want: void}, ~, 33, Str, 6, true], # 34
  [Add, ~, [25, 15], ~, Int]]} # 35
```

## A method on each element of an array the sub filled by push

The topic is the element; a private array the callee cannot reach otherwise.

```perl
package N { sub new { bless { s => $_[1] }, $_[0] } sub set_stamp { $_[0]{s} = $_[1] } sub s { $_[0]{s} // "u" } }
sub f { my @stale; push @stale, N->new(1), N->new(2); $_->set_stamp(undef) for @stale; return join ",", map { $_->s } @stale }
print f(), "\n";
```

```behavior
parses: yes
```

```output
u,u
```

```ir
N::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [HashLiteral, ~, [1, 5], 0, HashRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7], ~, Scalar, 4], # 8
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [6, 8], 6, Unknown, 4, true], # 9
  [Return, {implicit: true}, [9], 9, ~, 9]]} # 10
N::s: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 7
  [DefinedOr, ~, [6, 7], ~, Scalar], # 8
  [Return, {implicit: true}, [8], 6, ~, 6]]} # 9
N::set_stamp: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [1, 5], ~, Scalar], # 6
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 7
  [Subscript, {kind: hash}, [6, 7], ~, Scalar], # 8
  [Assign, ~, [8, 4], 0, Scalar, 3, true], # 9
  [Return, {implicit: true}, [4], 9, ~, 9]]} # 10
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [PadAccess, {sigil: "@", symbol: stale}, ~, ~, Array], # 3
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: new, package: main, param_names: [], want: list}, [4, 5], 0, Object, 6, true], # 7
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 8
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: new, package: main, param_names: [], want: list}, [4, 8], 7, Object, 7, true], # 9
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [3, 7, 9], 9, Int, 9, true], # 10
  [Loop, {bound: entry}, [10], 10], # 11
  [Proj, {index: 1}, [11]], # 12
  [Region, {head: 11}, [12]], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Phi, {region: 14}, [2, 37], ~, Array], # 15
  [Phi, {memory: true, region: 11}, [10, 50], ~, Unknown], # 16
  [Phi, {memory: true, region: 13}, [16], ~, Unknown], # 17
  [Phi, {memory: true, region: 14}, [17, 36], ~, Unknown], # 18
  [Proj, {index: 1}, [14]], # 19
  [Region, {head: 14}, [19]], # 20
  [Phi, {memory: true, region: 20}, [18], ~, Unknown], # 21
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 15], ~, Str, 21], # 22
  [Return, ~, [22], 20, ~, 21], # 23
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 24
  [Phi, {region: 11}, [24, 26], ~, Int], # 25
  [Add, ~, [25, 5], ~, Int], # 26
  [Phi, {region: 14}, [24, 28], ~, Int], # 27
  [Add, ~, [27, 5], ~, Int], # 28
  [Count, ~, [3], ~, Int, 10], # 29
  [ArrayLiteral, ~, [3], ~, List], # 30
  [Subscript, {kind: array}, [30, 27], ~, Scalar, 18], # 31
  [Subscript, {kind: array}, [30, 27], ~, Scalar], # 32
  [Ref, ~, [32], ~, ScalarRef], # 33
  [Proj, {index: 0}, [14]], # 34
  [LocalAlias, {name: _}, [33], 34, Unknown, 18], # 35
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: s, package: main, param_names: [], want: list}, [31], 35, Unknown, 18, true], # 36
  [ListAppend, {collector: map}, [15, 36], ~, Array], # 37
  [Count, ~, [30], ~, Int, 18], # 38
  [Count, ~, [3], ~, Int, 16], # 39
  [Subscript, {kind: array}, [3, 25], ~, Scalar, 16], # 40
  [Proj, {index: 0}, [11]], # 41
  [Exists, {kind: array}, [3, 25], 41, Boolean, 16], # 42
  [Subscript, {kind: array}, [3, 25], ~, Scalar], # 43
  [ArrayLiteral, ~, [3], ~, List], # 44
  [NumGt, ~, [39, 25], 11, Boolean], # 45
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 46
  [Ref, ~, [43], ~, ScalarRef], # 47
  [TernaryExpr, ~, [42, 47, 46], ~, "Maybe[ScalarRef]"], # 48
  [LocalAlias, {name: _}, [48], 42, Unknown, 16], # 49
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: set_stamp, package: main, param_names: [], want: void}, [40, 46], 49, Unknown, 16, true], # 50
  [NumGt, ~, [38, 27], 14, Boolean], # 51
  [Count, ~, [30], ~, Int, 17]]} # 52
```

## A foreach, a grep and a call over a ternary list arm

The ternary is a list slice where it is indexed, and a list slice yields the elements themselves.

```perl
sub g { $_[0] = 9; scalar @_ } sub ok1 { $_ > 1 }
sub f { my ($x, $c) = @_; my $s = "";
  for my $e ($c ? @$x : ()) { $s .= $e }
  my $k = join ",", grep { ok1() } ($c ? @$x : ());
  my $n = g($c ? @$x : ());
  return "$s|$k|$n|@$x" }
print f([1, 2, 3], 1), " ", f([4], 0), "\n";
```

```behavior
parses: yes
```

```output
123|2,3|3|9 2 3 ||1|4
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [ArrayLiteral, ~, [2, 3, 4], 0, ArrayRef], # 5
  [MemStart], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::f, package: main, param_names: [], want: list}, [5, 2], 5, Str, 6, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 10
  [ArrayLiteral, ~, [10], 7, ArrayRef], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::f, package: main, param_names: [], want: list}, [11, 12], 11, Str, 7, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [8, 9, 14, 15], 13, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 13]]} # 17
main::f: {start: 0, returns: [35], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 65], ~, Str], # 3
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 6
  [ArrayLiteral, ~, ~, ~, Array], # 7
  [Proj, {index: 1}, [2]], # 8
  [Region, {head: 2}, [8]], # 9
  [Loop, {bound: entry}, [9], 9], # 10
  [Phi, {region: 10}, [7, 66], ~, Array], # 11
  [MemStart], # 12
  [Phi, {memory: true, region: 10}, [12, 63], ~, Unknown], # 13
  [Proj, {index: 1}, [10]], # 14
  [Region, {head: 10}, [14]], # 15
  [Phi, {memory: true, region: 15}, [13], ~, Unknown], # 16
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [6, 11], ~, Str, 16], # 17
  [Concat, ~, [5, 17], ~, Str], # 18
  [Concat, ~, [18, 4], ~, Str], # 19
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 20
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown], # 21
  [PostfixDeref, {sigil: "@"}, [21], ~, Array, 16], # 22
  [ArrayLiteral, ~, [22], ~, Array], # 23
  [ArrayLiteral, ~, ~, ~, Array], # 24
  [TernaryExpr, ~, [20, 23, 24], ~, Array], # 25
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::g, package: main, param_names: [], want: scalar}, [25], 15, Int, 16, true], # 26
  [Coerce, {from_repr: Unknown, to_repr: Str}, [26], ~, Str], # 27
  [Concat, ~, [19, 27], ~, Str], # 28
  [Concat, ~, [28, 4], ~, Str], # 29
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 26], # 30
  [Coerce, {from_repr: Scalar, to_repr: Str}, [30], ~, Str], # 31
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 6, package: main, sigil: "@", strict: false}, [21], 26, Array, 26, true], # 32
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [31, 32], ~, Str, 32], # 33
  [Concat, ~, [29, 33], ~, Str], # 34
  [Return, ~, [34], 32, ~, 32], # 35
  [PostfixDeref, {sigil: "@"}, [21], ~, Array, 12], # 36
  [ArrayLiteral, ~, [36], ~, Array], # 37
  [ArrayLiteral, ~, ~, ~, Array], # 38
  [TernaryExpr, ~, [20, 37, 38], ~, Array], # 39
  [ArrayLiteral, ~, [39], ~, Array], # 40
  [Count, ~, [40], ~, Int, 12], # 41
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 42
  [Phi, {region: 2}, [42, 49], ~, Int], # 43
  [NumGt, ~, [41, 43], 2, Boolean], # 44
  [Proj, {index: 0}, [2]], # 45
  [ArgsSource, ~, ~, ~, Array], # 46
  [Assign, {record: true, targets: 2}, [21, 20, 46], ~, List], # 47
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 48
  [Add, ~, [43, 48], ~, Int], # 49
  [Subscript, {kind: array}, [40, 43], ~, Scalar, 12], # 50
  [ArrayLiteral, ~, [36], ~, Array], # 51
  [ArrayLiteral, ~, ~, ~, Array], # 52
  [TernaryExpr, ~, [20, 51, 52], ~, Array], # 53
  [Count, ~, [53], ~, Int, 12], # 54
  [Phi, {region: 10}, [42, 64], ~, Int], # 55
  [Coerce, {from_repr: Unknown, to_repr: Str}, [50], ~, Str], # 56
  [Count, ~, [53], ~, Int, 13], # 57
  [NumGt, ~, [57, 55], 10, Boolean], # 58
  [Proj, {index: 0}, [10]], # 59
  [Subscript, {kind: array}, [53, 55], ~, Scalar, 13], # 60
  [Ref, ~, [60], ~, ScalarRef], # 61
  [LocalAlias, {name: _}, [61], 59, Unknown, 13], # 62
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::ok1, package: main, param_names: [], want: scalar}, ~, 62, Boolean, 13, true], # 63
  [Add, ~, [55, 48], ~, Int], # 64
  [Concat, ~, [3, 56], ~, Str], # 65
  [ListAppend, {collector: grep}, [11, 60, 63], ~, Array]]} # 66
main::g: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Assign, ~, [3, 4], 0, Int, 5, true], # 6
  [Count, ~, [1], ~, Int, 6], # 7
  [Return, {implicit: true}, [7], 6, ~, 6]]} # 8
main::ok1: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar, 1], # 2
  [Coerce, {from_repr: Scalar, to_repr: Num}, [2], ~, Num], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [NumGt, ~, [3, 4], ~, Boolean], # 5
  [Return, {implicit: true}, [5], 0, ~, 1]]} # 6
```

## A replacement that is one variable

A lone lexical is the replacement value; a lone capture is the substitution's own, not an earlier match's.

```perl
sub f { my ($y) = @_; my $u = "ab"; $u =~ s/a/$y/;
  my $t = "QQ"; $t =~ /(Q)/; my $w = "ayb"; $w =~ s/(y)/$1/;
  my $v = "sv_2mortal(x)"; $v =~ s/^sv_2mortal\((.+)\)$/$1/;
  return "$u $w $v" }
print f("Z"), "\n";
```

```behavior
parses: yes
```

```output
Zb ayb x
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: Z}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::f, package: main, param_names: [], want: list}, [2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, "Maybe[Boolean]"], # 7
  [Return, {implicit: true}, [1], 7, ~, 4]]} # 8
main::f: {start: 0, returns: [35], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: u}, ~, ~, Unknown, 1], # 2
  [Constant, {const_type: string, value: ab}, ~, ~, Str], # 3
  [Assign, ~, [2, 3], 0, Str, 1, true], # 4
  [PadAccess, {sigil: $, symbol: u}, ~, ~, Unknown, 4], # 5
  [PadAccess, {sigil: $, symbol: "y"}, ~, ~, Unknown], # 6
  [RegexSubst, {flags: "", pattern: a, replacement: ""}, [5, 6], 4, Str, 4, true], # 7
  [PadAccess, {sigil: $, symbol: w}, ~, ~, Unknown, 7], # 8
  [Constant, {const_type: string, value: ayb}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: QQ}, ~, ~, Str], # 10
  [RegexMatch, {flags: "", pattern: "(Q)"}, [10], 7, Boolean], # 11
  [Assign, ~, [8, 9], 11, Str, 7, true], # 12
  [PadAccess, {sigil: $, symbol: w}, ~, ~, Str, 12], # 13
  [RegexMatch, {flags: "", pattern: "(y)"}, [13], ~, Boolean], # 14
  [RegexCapture, {"n": 1}, [14], ~, Str], # 15
  [RegexSubst, {flags: "", pattern: "(y)", replacement: ""}, [13, 15], 12, Str, 12, true], # 16
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Unknown, 16], # 17
  [Constant, {const_type: string, value: "sv_2mortal(x)"}, ~, ~, Str], # 18
  [Assign, ~, [17, 18], 16, Str, 16, true], # 19
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Str, 19], # 20
  [RegexMatch, {flags: "", pattern: "^sv_2mortal\\((.+)\\)$"}, [20], ~, Boolean], # 21
  [RegexCapture, {"n": 1}, [21], ~, Str], # 22
  [RegexSubst, {flags: "", pattern: "^sv_2mortal\\((.+)\\)$", replacement: ""}, [20, 22], 19, Str, 19, true], # 23
  [PadAccess, {sigil: $, symbol: u}, ~, ~, Str, 23], # 24
  [Coerce, {from_repr: Unknown, to_repr: Str}, [24], ~, Str], # 25
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 26
  [Concat, ~, [25, 26], ~, Str], # 27
  [PadAccess, {sigil: $, symbol: w}, ~, ~, Str, 23], # 28
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 29
  [Concat, ~, [27, 29], ~, Str], # 30
  [Concat, ~, [30, 26], ~, Str], # 31
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Str, 23], # 32
  [Coerce, {from_repr: Unknown, to_repr: Str}, [32], ~, Str], # 33
  [Concat, ~, [31, 33], ~, Str], # 34
  [Return, ~, [34], 23, ~, 23], # 35
  [ArgsSource, ~, ~, ~, Array], # 36
  [Assign, {record: true, targets: 1}, [6, 36], ~, List]]} # 37
```

## A capture after a match on the right of an and

The match ran whenever the guarded body runs, so the body reads its capture.

```perl
sub f { my ($v) = @_; if (defined $v && $v =~ /^%\$(\w+)$/) { return $1 } return "-" }
print f(q{%$abc}), f("x"), f(undef), "\n";
```

```behavior
parses: yes
```

```output
abc--
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "%$abc"}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [6], 4, Str, 4, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [1], 7, Str, 7, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [5, 8, 10, 11], 9, "Maybe[Boolean]"], # 12
  [Return, {implicit: true}, [1], 12, ~, 9]]} # 13
main::f: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Unknown], # 1
  [RegexMatch, {flags: "", pattern: "^%\\$(\\w+)$"}, [1], ~, Boolean], # 2
  [RegexCapture, {"n": 1}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 4
  [Defined, ~, [1], ~, Boolean], # 5
  [And, ~, [5, 2], ~, Boolean], # 6
  [If, ~, [0, 6], 0], # 7
  [Proj, {index: 0}, [7]], # 8
  [Proj, {index: 1}, [7]], # 9
  [Region, {head: 7}, [8, 9]], # 10
  [Phi, {predecessors: [8, 9], region: 10}, [3, 4], ~, Str], # 11
  [MemStart], # 12
  [Return, ~, [11], 10, ~, 12], # 13
  [ArgsSource, ~, ~, ~, Array], # 14
  [Assign, {record: true, targets: 1}, [1, 14], ~, List]]} # 15
```

## A callee reading the topic over lists a builtin made

A list from values or sort has no holes to guard; the topic is aliased to each element.

```perl
package N { sub new { bless { i => $_[1] }, $_[0] } sub id { $_[0]{i} } }
sub f { my %c = (a => N->new(1), b => N->new(2)); my %m; my @f = values %c; $m{ $_->id } = $_ for @f;
  my $s = ""; sub g { $_ } $s .= g() for sort keys %m; return $s }
print f(), "\n";
```

```behavior
parses: yes
```

```output
12
```

```ir
N::id: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: i}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
N::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: i}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [HashLiteral, ~, [1, 5], 0, HashRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7], ~, Scalar, 4], # 8
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [6, 8], 6, Unknown, 4, true], # 9
  [Return, {implicit: true}, [9], 9, ~, 9]]} # 10
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: new, package: main, param_names: [], want: list}, [2, 4], 0, Object, 5, true], # 6
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: new, package: main, param_names: [], want: list}, [2, 3], 6, Object, 6, true], # 7
  [Loop, {bound: entry}, [7], 7], # 8
  [Proj, {index: 1}, [8]], # 9
  [Region, {head: 8}, [9]], # 10
  [Loop, {bound: entry}, [10], 10], # 11
  [Phi, {region: 11}, [1, 35], ~, Str], # 12
  [Proj, {index: 1}, [11]], # 13
  [Region, {head: 11}, [13]], # 14
  [Phi, {memory: true, region: 8}, [7, 51], ~, Scalar], # 15
  [Phi, {memory: true, region: 10}, [15], ~, Scalar], # 16
  [Phi, {memory: true, region: 11}, [16, 33], ~, Scalar], # 17
  [Phi, {memory: true, region: 14}, [17], ~, Scalar], # 18
  [Return, ~, [12], 14, ~, 18], # 19
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 20
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 21
  [HashLiteral, {sigil: "%", symbol: c}, [20, 6, 21, 7], ~, Hash], # 22
  [PadAccess, {sigil: "%", symbol: m}, ~, ~, Hash], # 23
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [23], ~, List, 16], # 24
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [24], ~, List, 16], # 25
  [ArrayLiteral, ~, [25], ~, Array], # 26
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 27
  [Phi, {region: 11}, [27, 38], ~, Int], # 28
  [Subscript, {kind: array}, [26, 28], ~, Scalar], # 29
  [Ref, ~, [29], ~, ScalarRef], # 30
  [Proj, {index: 0}, [11]], # 31
  [LocalAlias, {name: _}, [30], 31, Unknown, 17], # 32
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::g, package: main, param_names: [], want: scalar}, ~, 32, Scalar, 17, true], # 33
  [Coerce, {from_repr: Unknown, to_repr: Str}, [33], ~, Str], # 34
  [Concat, ~, [12, 34], ~, Str], # 35
  [Phi, {region: 8}, [27, 37], ~, Int], # 36
  [Add, ~, [36, 4], ~, Int], # 37
  [Add, ~, [28, 4], ~, Int], # 38
  [Call, {dispatch_kind: builtin, name: values, param_names: [], want: list}, [22], ~, List, 7], # 39
  [Count, ~, [39], ~, Int, 7], # 40
  [Count, ~, [26], ~, Int, 17], # 41
  [Count, ~, [39], ~, Int, 15], # 42
  [Subscript, {kind: array}, [39, 36], ~, Scalar, 15], # 43
  [Subscript, {kind: array}, [39, 36], ~, Scalar], # 44
  [NumGt, ~, [42, 36], 8, Boolean], # 45
  [Proj, {index: 0}, [8]], # 46
  [Ref, ~, [44], ~, ScalarRef], # 47
  [LocalAlias, {name: _}, [47], 46, Unknown, 15], # 48
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: id, package: main, param_names: [], want: scalar}, [43], 48, Unknown, 15, true], # 49
  [Subscript, {kind: hash}, [23, 49], ~, Scalar], # 50
  [Assign, ~, [50, 43], 49, Scalar, 49, true], # 51
  [NumGt, ~, [41, 28], 11, Boolean], # 52
  [Count, ~, [26], ~, Int, 16]]} # 53
main::g: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar, 1], # 2
  [Return, {implicit: true}, [2], 0, ~, 1]]} # 3
```

## A callee reference to the iterator over a named array or a grep result

The pass reads its element through a reference, so a reference the callee hands back is the element.

```perl
sub k { return \$_[0] } sub g { (1, 2, 3) }
sub f { my @a = g(); my $r; for my $x (@a) { $r = k($x) } $$r = 5;
  my @b = grep { $_ > 1 } g(); my $q; for my $x (@b) { ($q) = k($x) } $$q = 7; return "@a|@b" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
1 2 5|2 7
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [39], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: list}, ~, 0, List, 2, true], # 3
  [Loop, {bound: entry}, [3], 3], # 4
  [Phi, {region: 4}, [1, 53], ~, "Maybe[ScalarRef]"], # 5
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: $, strict: false}, [5], ~, Scalar], # 6
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 7
  [Proj, {index: 1}, [4]], # 8
  [Region, {head: 4}, [8]], # 9
  [Phi, {memory: true, region: 4}, [3, 53], ~, List], # 10
  [Phi, {memory: true, region: 9}, [10], ~, List], # 11
  [Assign, ~, [6, 7], 9, Int, 11, true], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::g, package: main, param_names: [], want: list}, ~, 12, List, 12, true], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Proj, {index: 1}, [14]], # 15
  [Region, {head: 14}, [15]], # 16
  [Loop, {bound: entry}, [16], 16], # 17
  [Phi, {region: 17}, [1, 68], ~, Unknown], # 18
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 3, package: main, sigil: $, strict: false}, [18], ~, Scalar], # 19
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 20
  [Proj, {index: 1}, [17]], # 21
  [Region, {head: 17}, [21]], # 22
  [Phi, {memory: true, region: 14}, [13, 23], ~, Unknown], # 23
  [Phi, {memory: true, region: 16}, [23], ~, Unknown], # 24
  [Phi, {memory: true, region: 17}, [24, 74], ~, Unknown], # 25
  [Phi, {memory: true, region: 22}, [25], ~, Unknown], # 26
  [Assign, ~, [19, 20], 22, Int, 26, true], # 27
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 27], # 28
  [Coerce, {from_repr: Scalar, to_repr: Str}, [28], ~, Str], # 29
  [ArrayLiteral, {sigil: "@", symbol: a}, [3], ~, Array], # 30
  [PostfixDeref, {sigil: "@"}, [30], ~, Array, 27], # 31
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [29, 31], ~, Str, 27], # 32
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 33
  [Concat, ~, [32, 33], ~, Str], # 34
  [ArrayLiteral, ~, ~, ~, Array], # 35
  [Phi, {region: 14}, [35, 60], ~, Array], # 36
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [29, 36], ~, Str, 27], # 37
  [Concat, ~, [34, 37], ~, Str], # 38
  [Return, ~, [38], 27, ~, 27], # 39
  [Count, ~, [30], ~, Int, 3], # 40
  [Count, ~, [30], ~, Int, 10], # 41
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 42
  [Phi, {region: 4}, [42, 75], ~, Int], # 43
  [Proj, {index: 0}, [4]], # 44
  [Exists, {kind: array}, [30, 43], 44, Boolean, 10], # 45
  [Subscript, {kind: array}, [30, 43], ~, Scalar], # 46
  [Subscript, {kind: array}, [30, 43], ~, Scalar, 10], # 47
  [NumGt, ~, [41, 43], 4, Boolean], # 48
  [Ref, ~, [46], ~, ScalarRef], # 49
  [TernaryExpr, ~, [45, 49, 1], 45, "Maybe[ScalarRef]"], # 50
  [PostfixDeref, {sigil: $}, [50], ~, Scalar, 10], # 51
  [TernaryExpr, ~, [45, 51, 47], ~, Scalar], # 52
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::k, package: main, param_names: [], want: scalar}, [52], 50, ScalarRef, 10, true], # 53
  [ArrayLiteral, ~, [13], ~, List], # 54
  [Phi, {region: 14}, [42, 79], ~, Int], # 55
  [Subscript, {kind: array}, [54, 55], ~, Scalar, 23], # 56
  [Coerce, {from_repr: Scalar, to_repr: Num}, [56], ~, Num], # 57
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 58
  [NumGt, ~, [57, 58], ~, Boolean], # 59
  [ListAppend, {collector: grep}, [36, 56, 59], ~, Array], # 60
  [Count, ~, [36], ~, Int, 24], # 61
  [Count, ~, [36], ~, Int, 25], # 62
  [Phi, {region: 17}, [42, 77], ~, Int], # 63
  [Proj, {index: 0}, [17]], # 64
  [Exists, {kind: array}, [36, 63], 64, Boolean, 25], # 65
  [Subscript, {kind: array}, [36, 63], ~, Scalar], # 66
  [Subscript, {kind: array}, [36, 63], ~, Scalar, 25], # 67
  [PadAccess, {sigil: $, symbol: q}, ~, ~, Unknown], # 68
  [Ref, ~, [66], ~, ScalarRef], # 69
  [TernaryExpr, ~, [65, 69, 1], 65, "Maybe[ScalarRef]"], # 70
  [PostfixDeref, {sigil: $}, [70], ~, Scalar, 25], # 71
  [TernaryExpr, ~, [65, 71, 67], ~, Scalar], # 72
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::k, package: main, param_names: [], want: list}, [72], 70, ScalarRef, 25, true], # 73
  [Assign, {targets: 1}, [68, 73], 73, ScalarRef, 73, true], # 74
  [Add, ~, [43, 58], ~, Int], # 75
  [NumGt, ~, [62, 63], 17, Boolean], # 76
  [Add, ~, [63, 58], ~, Int], # 77
  [Count, ~, [54], ~, Int, 23], # 78
  [Add, ~, [55, 58], ~, Int], # 79
  [NumGt, ~, [78, 55], 14, Boolean], # 80
  [Subscript, {kind: array}, [54, 55], ~, Scalar], # 81
  [Count, ~, [54], ~, Int, 13], # 82
  [Ref, ~, [81], ~, ScalarRef], # 83
  [Proj, {index: 0}, [14]], # 84
  [LocalAlias, {name: _}, [83], 84, Unknown, 23]]} # 85
main::g: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, List], # 4
  [Coerce, {from_repr: List, to_repr: Scalar}, [3], ~, Scalar], # 5
  [MemStart], # 6
  [Return, {implicit: true}, [4, 5], 0, ~, 6]]} # 7
main::k: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Ref, ~, [3], 0, ScalarRef, 4, true], # 5
  [Return, ~, [5], 5, ~, 5]]} # 6
```

## A written iterator walked along a chain over a private list

No call can reach the private list, so the write-back is the alias.

```perl
package N { sub new { bless { id => $_[1], prev => $_[2] }, $_[0] } sub prev { $_[0]{prev} } sub id { $_[0]{id} } }
sub f { my ($ret) = @_; my @chain; my %seen; my @seeds = grep { defined } ($ret->prev);
  for my $ctrl (@seeds) { while (defined $ctrl) { last if $seen{ $ctrl->id }++; push @chain, $ctrl->id; $ctrl = $ctrl->prev } }
  return "@chain|" . scalar(@seeds) }
print f(N->new(0, N->new(1, N->new(2, N->new(3))))), "\n";
```

```behavior
parses: yes
```

```output
1 2 3|1
```

```ir
N::id: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: id}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
N::new: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: id}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Constant, {const_type: string, value: prev}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7], ~, Scalar, 4], # 8
  [HashLiteral, ~, [1, 5, 6, 8], 0, HashRef], # 9
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [2, 10], ~, Scalar, 4], # 11
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [9, 11], 9, Unknown, 4, true], # 12
  [Return, {implicit: true}, [12], 12, ~, 12]]} # 13
N::prev: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: prev}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [MemStart], # 7
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: new, package: main, param_names: [], want: list}, [2, 6], 0, Object, 7, true], # 8
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: new, package: main, param_names: [], want: list}, [2, 5, 8], 8, Object, 8, true], # 9
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: new, package: main, param_names: [], want: list}, [2, 4, 9], 9, Object, 9, true], # 10
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: new, package: main, param_names: [], want: list}, [2, 3, 10], 10, Object, 10, true], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::f, package: main, param_names: [], want: list}, [11], 11, Str, 11, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [13, 14], 12, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 12]]} # 16
main::f: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: ret}, ~, ~, Unknown], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: prev, package: main, param_names: [], want: list}, [1], 0, Unknown, 2, true], # 3
  [Loop, {bound: entry}, [3], 3], # 4
  [Phi, {memory: true, region: 4}, [3, 5], ~, Unknown], # 5
  [Proj, {index: 1}, [4]], # 6
  [Region, {head: 4}, [6]], # 7
  [Phi, {memory: true, region: 7}, [5], ~, Unknown], # 8
  [Loop, {bound: entry}, [7], 7], # 9
  [Phi, {memory: true, region: 9}, [8, 56], ~, Unknown], # 10
  [Proj, {index: 1}, [9]], # 11
  [Region, {head: 9}, [11]], # 12
  [Phi, {memory: true, region: 12}, [10], ~, Unknown], # 13
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 13], # 14
  [Coerce, {from_repr: Scalar, to_repr: Str}, [14], ~, Str], # 15
  [PadAccess, {sigil: "@", symbol: chain}, ~, ~, Array], # 16
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [15, 16], ~, Str, 13], # 17
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [ArrayLiteral, ~, ~, ~, Array], # 20
  [Phi, {region: 4}, [20, 59], ~, Array], # 21
  [Count, ~, [21], ~, Int, 13], # 22
  [Concat, ~, [19, 22], ~, Str], # 23
  [Return, ~, [23], 12, ~, 13], # 24
  [ArrayLiteral, ~, [3], ~, List], # 25
  [Count, ~, [25], ~, Int, 3], # 26
  [ArgsSource, ~, ~, ~, Array], # 27
  [Assign, {record: true, targets: 1}, [1, 27], ~, List], # 28
  [Count, ~, [25], ~, Int, 5], # 29
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 30
  [Phi, {region: 4}, [30, 69], ~, Int], # 31
  [Subscript, {kind: array}, [25, 31], ~, Scalar, 5], # 32
  [Subscript, {kind: array}, [25, 31], ~, Scalar], # 33
  [NumGt, ~, [29, 31], 4, Boolean], # 34
  [Proj, {index: 0}, [4]], # 35
  [Phi, {region: 9}, [30, 71], ~, Int], # 36
  [Subscript, {kind: array}, [21, 36], ~, Scalar], # 37
  [Subscript, {kind: array}, [21, 36], ~, Scalar, 10], # 38
  [Proj, {index: 0}, [9]], # 39
  [Loop, {bound: each}, [39], 39], # 40
  [Phi, {region: 40}, [38, 67], ~, Unknown], # 41
  [Proj, {index: 1}, [40]], # 42
  [PadAccess, {sigil: "%", symbol: seen}, ~, ~, Hash], # 43
  [Proj, {index: 0}, [40]], # 44
  [Phi, {memory: true, region: 40}, [10, 67], ~, Unknown], # 45
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: id, package: main, param_names: [], want: scalar}, [41], 44, Unknown, 45, true], # 46
  [Subscript, {kind: hash}, [43, 46], ~, Scalar], # 47
  [Subscript, {kind: hash}, [43, 46], 46, Scalar, 46], # 48
  [Increment, ~, [48], ~, Scalar], # 49
  [Assign, ~, [47, 49], 48, Scalar, 46, true], # 50
  [DefinedOr, ~, [48, 30], ~, Scalar], # 51
  [If, ~, [50, 51], 50], # 52
  [Proj, {index: 0}, [52]], # 53
  [Region, {head: 40}, [42, 53]], # 54
  [Phi, {memory: true, region: 54}, [45, 50], ~, Unknown], # 55
  [Assign, ~, [37, 41], 54, Unknown, 55, true], # 56
  [Count, ~, [21], ~, Int, 10], # 57
  [Defined, ~, [32], ~, Boolean], # 58
  [ListAppend, {collector: grep}, [21, 32, 58], ~, Array], # 59
  [Ref, ~, [33], ~, ScalarRef], # 60
  [LocalAlias, {name: _}, [60], 35, Unknown, 5], # 61
  [Count, ~, [21], ~, Int, 8], # 62
  [NumGt, ~, [57, 36], 9, Boolean], # 63
  [Proj, {index: 1}, [52]], # 64
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: id, package: main, param_names: [], want: list}, [41], 64, Unknown, 50, true], # 65
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [16, 65], 65, Int, 65, true], # 66
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: prev, package: main, param_names: [], want: scalar}, [41], 66, Unknown, 66, true], # 67
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 68
  [Add, ~, [31, 68], ~, Int], # 69
  [Defined, ~, [41], 40, Boolean], # 70
  [Add, ~, [36, 68], ~, Int]]} # 71
```

## An arm that always goes round

Every path of the arm ends in next -- one through a nested next-if, one after an inner loop -- so it is a next, not a join.

```perl
sub f { my @c = @_; my @o; my $i = 0;
  while ($i <= $#c) { my $x = $c[$i];
    if ($x eq 'b') { if ($c[$i+1] eq 'w') { $i += 2; next } my $j = $i + 1; while ($j <= $#c) { $j++ } $i = $j; next }
    if ($x eq '.') { $i++; next }
    push @o, $x; $i++ }
  return "@o" }
print f(qw(a b w . c b x y)), "|", f(qw(a . b x)), "\n";
```

```behavior
parses: yes
```

```output
a c|a
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: w}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "."}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 8
  [MemStart], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::f, package: main, param_names: [], want: list}, [2, 3, 4, 5, 6, 3, 7, 8], 0, Str, 9, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::f, package: main, param_names: [], want: list}, [2, 5, 3, 7], 10, Str, 10, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [11, 12, 14, 15], 13, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 13]]} # 17
main::f: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Loop, {bound: each}, [0], 0], # 2
  [Phi, {memory: true, region: 2}, [1, 49], ~, Unknown], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Phi, {memory: true, region: 5}, [3], ~, Unknown], # 6
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 6], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [7], ~, Str], # 8
  [PadAccess, {sigil: "@", symbol: o}, ~, ~, Array], # 9
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [8, 9], ~, Str, 6], # 10
  [Return, ~, [10], 5, ~, 6], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Phi, {region: 2}, [12, 55], ~, Int], # 13
  [ArgsSource, ~, ~, ~, Array], # 14
  [Count, ~, [14], ~, Int, 3], # 15
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 16
  [Subtract, ~, [15, 16], ~, Int], # 17
  [NumLe, ~, [13, 17], 2, Boolean], # 18
  [Proj, {index: 0}, [2]], # 19
  [Subscript, {kind: array}, [14, 13], ~, Scalar, 3], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 22
  [StrEq, ~, [21, 22], ~, Boolean], # 23
  [If, ~, [19, 23], 19], # 24
  [Proj, {index: 1}, [24]], # 25
  [Constant, {const_type: string, value: "."}, ~, ~, Str], # 26
  [StrEq, ~, [21, 26], ~, Boolean], # 27
  [If, ~, [25, 27], 25], # 28
  [Proj, {index: 1}, [28]], # 29
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [9, 20], 29, Int, 3, true], # 30
  [Proj, {index: 0}, [24]], # 31
  [Add, ~, [13, 16], ~, Int], # 32
  [Subscript, {kind: array}, [14, 32], ~, Scalar, 3], # 33
  [Coerce, {from_repr: Unknown, to_repr: Str}, [33], ~, Str], # 34
  [Constant, {const_type: string, value: w}, ~, ~, Str], # 35
  [StrEq, ~, [34, 35], ~, Boolean], # 36
  [If, ~, [31, 36], 31], # 37
  [Proj, {index: 0}, [37]], # 38
  [Region, {head: 2}, [30, 38]], # 39
  [Phi, {memory: true, predecessors: [29, 38], region: 39}, [30, 3], ~, Unknown], # 40
  [Proj, {index: 1}, [37]], # 41
  [Loop, {bound: each}, [41], 41], # 42
  [Proj, {index: 1}, [42]], # 43
  [Region, {head: 42}, [43]], # 44
  [Region, {head: 2}, [39, 44]], # 45
  [Phi, {memory: true, region: 45}, [40, 3], ~, Unknown], # 46
  [Proj, {index: 0}, [28]], # 47
  [Region, {head: 2}, [45, 47]], # 48
  [Phi, {memory: true, region: 48}, [46, 3], ~, Unknown], # 49
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 50
  [Add, ~, [13, 50], ~, Int], # 51
  [Phi, {predecessors: [29, 38], region: 39}, [32, 51], ~, Int], # 52
  [Phi, {region: 42}, [32, 57], ~, Int], # 53
  [Phi, {region: 45}, [52, 53], ~, Int], # 54
  [Phi, {region: 48}, [54, 32], ~, Int], # 55
  [NumLe, ~, [53, 17], 42, Boolean], # 56
  [Add, ~, [53, 16], ~, Int], # 57
  [Proj, {index: 0}, [42]]]} # 58
```

## An element read before a call that may write it

A call may write any element it is passed; a read used after it is read at the top of the pass, or right after its own store.

```perl
sub emit { print "$_[0]\n" }
sub bump { $_[0] = uc $_[0] }
sub f { my @t = map { "L$_" } 0 .. 2;
  for my $i (0 .. $#t) { my $next = $i < $#t ? $t[$i+1] : 'undef'; emit($t[$i]); emit("br $next") }
  my @u = qw(a b); my $s = '';
  for my $i (0 .. $#u) { my $v = $u[$i]; bump($u[$i]); $s .= "$v$u[$i] " }
  return $s }
print f(), "\n";
```

```behavior
parses: yes
```

```output
L0
br L1
L1
br L2
L2
br undef
aA bB 
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::bump: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Call, {dispatch_kind: builtin, name: uc, param_names: []}, [4], ~, Str], # 5
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 6
  [Assign, ~, [6, 5], 0, Str, 3, true], # 7
  [Return, {implicit: true}, [5], 7, ~, 7]]} # 8
main::emit: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Print, ~, [7], 0, "Maybe[Boolean]"], # 8
  [Return, {implicit: true}, [8], 8, ~, 3]]} # 9
main::f: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Proj, {index: 1}, [2]], # 3
  [Region, {head: 2}, [3]], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Proj, {index: 1}, [5]], # 6
  [Region, {head: 5}, [6]], # 7
  [Loop, {bound: entry}, [7], 7], # 8
  [Phi, {region: 8}, [1, 41], ~, Str], # 9
  [Proj, {index: 1}, [8]], # 10
  [Region, {head: 8}, [10]], # 11
  [MemStart], # 12
  [Phi, {memory: true, region: 2}, [12, 13], ~, Unknown], # 13
  [Phi, {memory: true, region: 4}, [13], ~, Unknown], # 14
  [Phi, {memory: true, region: 5}, [14, 71], ~, Unknown], # 15
  [Phi, {memory: true, region: 7}, [15], ~, Unknown], # 16
  [Phi, {memory: true, region: 8}, [16, 37], ~, Unknown], # 17
  [Phi, {memory: true, region: 11}, [17], ~, Unknown], # 18
  [Return, ~, [9], 11, ~, 18], # 19
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 20
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 21
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 22
  [ArrayLiteral, ~, [20, 21, 22], ~, Array], # 23
  [PostfixDeref, {sigil: "@"}, [23], ~, Array, 12], # 24
  [Count, ~, [24], ~, Int, 13], # 25
  [Phi, {region: 2}, [20, 42], ~, Int], # 26
  [NumGt, ~, [25, 26], 2, Boolean], # 27
  [Proj, {index: 0}, [2]], # 28
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 29
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 30
  [ArrayLiteral, {sigil: "@", symbol: u}, [29, 30], ~, Array], # 31
  [Phi, {region: 8}, [20, 58], ~, Int], # 32
  [Subscript, {kind: array}, [31, 32], ~, Str, 17], # 33
  [Concat, ~, [9, 33], ~, Str], # 34
  [Subscript, {kind: array}, [31, 32], ~, Scalar], # 35
  [Proj, {index: 0}, [8]], # 36
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: main::bump, package: main, param_names: [], want: void}, [35], 36, Str, 17, true], # 37
  [Subscript, {kind: array}, [31, 32], ~, Str, 37], # 38
  [Concat, ~, [34, 38], ~, Str], # 39
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 40
  [Concat, ~, [39, 40], ~, Str], # 41
  [Add, ~, [26, 21], ~, Int], # 42
  [Subscript, {kind: array}, [24, 26], ~, Scalar, 13], # 43
  [Count, ~, [31], ~, Int, 16], # 44
  [Subtract, ~, [44, 21], ~, Int], # 45
  [Add, ~, [45, 21], ~, Int], # 46
  [NumGt, ~, [46, 32], 8, Boolean], # 47
  [Count, ~, [24], ~, Int, 12], # 48
  [Phi, {region: 5}, [20, 63], ~, Int], # 49
  [Coerce, {from_repr: Unknown, to_repr: Str}, [43], ~, Str], # 50
  [ArrayLiteral, ~, ~, ~, Array], # 51
  [Phi, {region: 2}, [51, 74], ~, Array], # 52
  [Count, ~, [52], ~, Int, 14], # 53
  [Subtract, ~, [53, 21], ~, Int], # 54
  [Add, ~, [54, 21], ~, Int], # 55
  [NumGt, ~, [55, 49], 5, Boolean], # 56
  [Proj, {index: 0}, [5]], # 57
  [Add, ~, [32, 21], ~, Int], # 58
  [Constant, {const_type: string, value: "br "}, ~, ~, Str], # 59
  [Count, ~, [52], ~, Int, 15], # 60
  [Subtract, ~, [60, 21], ~, Int], # 61
  [NumLt, ~, [49, 61], ~, Boolean], # 62
  [Add, ~, [49, 21], ~, Int], # 63
  [Subscript, {kind: array}, [52, 63], ~, Scalar, 15], # 64
  [Constant, {const_type: string, value: undef}, ~, ~, Str], # 65
  [TernaryExpr, ~, [62, 64, 65], ~, Unknown], # 66
  [Coerce, {from_repr: Unknown, to_repr: Str}, [66], ~, Str], # 67
  [Concat, ~, [59, 67], ~, Str], # 68
  [Subscript, {kind: array}, [52, 49], ~, Scalar], # 69
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::emit, package: main, param_names: [], want: void}, [69], 57, "Maybe[Boolean]", 15, true], # 70
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::emit, package: main, param_names: [], want: void}, [68], 70, "Maybe[Boolean]", 70, true], # 71
  [Constant, {const_type: string, value: L}, ~, ~, Str], # 72
  [Concat, ~, [72, 50], ~, Str], # 73
  [ListAppend, {collector: map}, [52, 73], ~, Array]]} # 74
```

## A map over a range counts the range

The count of a dereferenced literal list is the list's length, not the comma operator's last element.

```perl
my @t = map { "L$_" } 0 .. 2; my @n = map { $_ * 2 } 5 .. 7; print "@t @n\n";
```

```behavior
parses: yes
```

```output
L0 L1 L2 10 12 14
```

```ir
main::__PROGRAM__: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 2], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [ArrayLiteral, ~, ~, ~, Array], # 5
  [Loop, {bound: entry}, [0], 0], # 6
  [Phi, {region: 6}, [5, 51], ~, Array], # 7
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 7], ~, Str, 2], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [ArrayLiteral, ~, ~, ~, Array], # 11
  [Proj, {index: 1}, [6]], # 12
  [Region, {head: 6}, [12]], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Phi, {region: 14}, [11, 50], ~, Array], # 15
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 15], ~, Str, 2], # 16
  [Concat, ~, [10, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Proj, {index: 1}, [14]], # 20
  [Region, {head: 14}, [20]], # 21
  [Print, ~, [19], 21, "Maybe[Boolean]"], # 22
  [Return, {implicit: true}, [1], 22, ~, 2], # 23
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 24
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 25
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 26
  [ArrayLiteral, ~, [24, 25, 26], ~, Array], # 27
  [PostfixDeref, {sigil: "@"}, [27], ~, Array, 2], # 28
  [Count, ~, [28], ~, Int, 2], # 29
  [Phi, {region: 6}, [24, 46], ~, Int], # 30
  [NumGt, ~, [29, 30], 6, Boolean], # 31
  [Proj, {index: 0}, [6]], # 32
  [Subscript, {kind: array}, [28, 30], ~, Scalar, 2], # 33
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 34
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 35
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 36
  [ArrayLiteral, ~, [34, 35, 36], ~, Array], # 37
  [PostfixDeref, {sigil: "@"}, [37], ~, Array, 2], # 38
  [Count, ~, [38], ~, Int, 2], # 39
  [Phi, {region: 14}, [24, 49], ~, Int], # 40
  [Subscript, {kind: array}, [38, 40], ~, Scalar, 2], # 41
  [Coerce, {from_repr: Unknown, to_repr: Str}, [33], ~, Str], # 42
  [NumGt, ~, [39, 40], 14, Boolean], # 43
  [Coerce, {from_repr: Scalar, to_repr: Num}, [41], ~, Num], # 44
  [Multiply, ~, [44, 26], ~, Num], # 45
  [Add, ~, [30, 25], ~, Int], # 46
  [Constant, {const_type: string, value: L}, ~, ~, Str], # 47
  [Concat, ~, [47, 42], ~, Str], # 48
  [Add, ~, [40, 25], ~, Int], # 49
  [ListAppend, {collector: map}, [15, 45], ~, Array], # 50
  [ListAppend, {collector: map}, [7, 48], ~, Array], # 51
  [Proj, {index: 0}, [14]]]} # 52
```

## A plain sub declares its own self

Only a class body's $self is perl's; a plain sub's is a lexical, and a store's target is no read.

```perl
package C; sub new { bless {}, shift } sub g { "g$_[1]" }
sub f { my ($self, $to, @r) = @_; my $val = '';
  for my $i (0 .. $#r) { my $repr = $r[$i]; $val = $self->g($repr) if $repr ne $to }
  return $val }
package main; print C->new->f('Str', qw(Int Num Str)), "\n";
```

```behavior
parses: yes
```

```output
gNum
```

```ir
C::f: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 33], ~, Unknown], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [MemStart], # 6
  [Phi, {memory: true, region: 2}, [6, 34], ~, Unknown], # 7
  [Phi, {memory: true, region: 5}, [7], ~, Unknown], # 8
  [Return, ~, [3], 5, ~, 8], # 9
  [PadAccess, {sigil: "@", symbol: r}, ~, ~, Array], # 10
  [Count, ~, [10], ~, Int, 6], # 11
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 12
  [Subtract, ~, [11, 12], ~, Int], # 13
  [Add, ~, [13, 12], ~, Int], # 14
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 15
  [Phi, {region: 2}, [15, 35], ~, Int], # 16
  [NumGt, ~, [14, 16], 2, Boolean], # 17
  [Proj, {index: 0}, [2]], # 18
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 19
  [PadAccess, {sigil: $, symbol: repr}, ~, ~, Unknown, 7], # 20
  [Subscript, {kind: array}, [10, 16], ~, Scalar, 7], # 21
  [Assign, ~, [20, 21], 18, Scalar, 7, true], # 22
  [PadAccess, {sigil: $, symbol: repr}, ~, ~, Str, 22], # 23
  [Coerce, {from_repr: Unknown, to_repr: Str}, [23], ~, Str], # 24
  [PadAccess, {sigil: $, symbol: to}, ~, ~, Str], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 26
  [StrNe, ~, [24, 26], ~, Boolean], # 27
  [If, ~, [22, 27], 22], # 28
  [Proj, {index: 0}, [28]], # 29
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: g, package: C, param_names: [], want: scalar}, [19, 23], 29, Str, 22, true], # 30
  [Proj, {index: 1}, [28]], # 31
  [Region, {head: 28}, [30, 31]], # 32
  [Phi, {predecessors: [29, 31], region: 32}, [30, 3], ~, Unknown], # 33
  [Phi, {memory: true, predecessors: [29, 31], region: 32}, [30, 22], ~, Scalar], # 34
  [Add, ~, [16, 12], ~, Int], # 35
  [ArgsSource, ~, ~, ~, Array], # 36
  [Assign, {record: true, targets: 3}, [19, 25, 10, 36], ~, List]]} # 37
C::g: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: g}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Return, {implicit: true}, [7], 0, ~, 4]]} # 8
C::new: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [HashLiteral, ~, ~, 0, HashRef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [2], 1, Scalar, 3, true], # 4
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [1, 4], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: C}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: new, package: main, param_names: [], want: scalar}, [2], 0, Object, 3, true], # 4
  [Constant, {const_type: string, value: Str}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: Int}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: Num}, ~, ~, Str], # 7
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: f, package: main, param_names: [], want: list}, [4, 5, 6, 7, 5], 4, Unknown, 4, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
```

## A glob bind names its own package

*rr = \&A::rr under package B binds B::rr, which B's calls reach.

```perl
package A; sub rr { "rr$_[0]" }
package B; *rr = \&A::rr; sub f { return rr($_[0]) }
package main; *rr = \&A::rr; print B::f(3), rr(4), "\n";
```

```behavior
parses: yes
```

```output
rr3rr4
```

```ir
A::rr: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: rr}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Return, {implicit: true}, [7], 0, ~, 4]]} # 8
B::f: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: B::rr, package: B, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Return, ~, [5], 5, ~, 5]]} # 6
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 2
  [EntryDef, {package: main, sigil: "&", symbol: rr}, ~, ~, Unknown], # 3
  [Constant, {const_type: code, value: A::rr}, ~, ~, Code], # 4
  [Ref, ~, [4], ~, CodeRef], # 5
  [EntryDef, {package: B, sigil: "&", symbol: rr}, ~, ~, Unknown], # 6
  [PackageMark, {package: B}, ~, 0], # 7
  [MemStart], # 8
  [EntryWrite, {binds: true}, [6, 5], 7, Unknown, 8, true], # 9
  [PackageMark, {package: main}, ~, 9], # 10
  [EntryWrite, {binds: true}, [3, 5], 10, Unknown, 9, true], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: B::f, package: main, param_names: [], want: list}, [2], 11, Unknown, 11, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 14
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::rr, package: main, param_names: [], want: list}, [14], 12, Unknown, 12, true], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [13, 16, 17], 15, "Maybe[Boolean]"], # 18
  [Return, {implicit: true}, [1], 18, ~, 15]]} # 19
```

## A call into a package defined elsewhere

A package this program never defines is another module's, reached like an import.

```perl
eval 'package Other; sub g { "g$_[0]" } 1' or die;
sub f { return Other::g($_[0]) }
print f(2), "\n";
```

```behavior
parses: yes
```

```output
g2
```

```ir
main::__PROGRAM__: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [MemStart], # 3
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 3], # 4
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: "package Other; sub g { \"g$_[0]\" } 1"}, ~, ~, Str], # 6
  [Coerce, {from_repr: Str, to_repr: Code}, [6], 0, Code], # 7
  [EntryWrite, ~, [4, 5], 7, Unknown, 3, true], # 8
  [Exc, ~, [7]], # 9
  [Region, {catch: true, eval_id: 1}, [9]], # 10
  [EntryWrite, ~, [4, 9], 10, Unknown, 3, true], # 11
  [Region, ~, [8, 11]], # 12
  [Phi, {region: 12}, [7, 1], ~, Unknown], # 13
  [If, ~, [12, 13], 12], # 14
  [Proj, {index: 0}, [14]], # 15
  [Proj, {index: 1}, [14]], # 16
  [Phi, {memory: true, region: 12}, [8, 11], ~, Unknown], # 17
  [Unwind, {file: "/tmp/mvrHQew3rs/case.pl", line: 1}, ~, 16, ~, 17], # 18
  [Region, {head: 14}, [15, 18]], # 19
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2], 19, Unknown, 17, true], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 22
  [Print, ~, [21, 22], 20, "Maybe[Boolean]"], # 23
  [Return, {implicit: true}, [1], 23, ~, 20]]} # 24
main::f: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: Other::g, package: main, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Return, ~, [5], 5, ~, 5]]} # 6
```

## A defined-or defaulting to an allocation in a ternary arm

The allocation on the right of // moves control, so the arm is a real branch.

```perl
sub f { my ($r, $e) = @_; my $o = ""; for my $s ($e ? @{ $r->{s} // [] } : ()) { $o .= $s } return $o }
print f({s=>[1,2]}, 1), f({}, 1), f({s=>[3]}, 0), "\n";
```

```behavior
parses: yes
```

```output
12
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [ArrayLiteral, ~, [3, 4], 0, ArrayRef], # 5
  [HashLiteral, ~, [2, 5], 5, HashRef], # 6
  [MemStart], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [6, 3], 6, Str, 7, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [HashLiteral, ~, ~, 8, HashRef], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [10, 3], 10, Str, 8, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 13
  [ArrayLiteral, ~, [13], 11, ArrayRef], # 14
  [HashLiteral, ~, [2, 14], 14, HashRef], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [15, 16], 15, Str, 11, true], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Print, ~, [9, 12, 18, 19], 17, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 17]]} # 21
main::f: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: r}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 3
  [PadAccess, {sigil: $, symbol: e}, ~, ~, Unknown], # 4
  [If, ~, [0, 4], 0], # 5
  [Proj, {index: 0}, [5]], # 6
  [MemStart], # 7
  [Subscript, {kind: hash}, [2, 3], 6, Scalar, 7, true], # 8
  [Defined, ~, [8], ~, Boolean], # 9
  [If, ~, [8, 9], 8], # 10
  [Proj, {index: 0}, [10]], # 11
  [Proj, {index: 1}, [10]], # 12
  [ArrayLiteral, ~, ~, 12, ArrayRef], # 13
  [Region, {head: 10}, [11, 13]], # 14
  [Proj, {index: 1}, [5]], # 15
  [Region, {head: 5}, [14, 15]], # 16
  [Loop, {bound: entry}, [16], 16], # 17
  [Phi, {region: 17}, [1, 32], ~, Str], # 18
  [Proj, {index: 1}, [17]], # 19
  [Region, {head: 17}, [19]], # 20
  [Phi, {memory: true, predecessors: [6, 15], region: 16}, [8, 7], ~, Unknown], # 21
  [Return, ~, [18], 20, ~, 21], # 22
  [Phi, {predecessors: [11, 12], region: 14}, [8, 13], ~, Scalar], # 23
  [PostfixDeref, {sigil: "@"}, [23], ~, Array, 8], # 24
  [ArrayLiteral, ~, ~, ~, List], # 25
  [Phi, {predecessors: [6, 15], region: 16}, [24, 25], ~, List], # 26
  [ArrayLiteral, ~, [26], ~, Array], # 27
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 28
  [Phi, {region: 17}, [28, 39], ~, Int], # 29
  [Subscript, {kind: array}, [27, 29], ~, Scalar, 21], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [30], ~, Str], # 31
  [Concat, ~, [18, 31], ~, Str], # 32
  [Count, ~, [27], ~, Int, 21], # 33
  [ArgsSource, ~, ~, ~, Array], # 34
  [Assign, {record: true, targets: 2}, [2, 4, 34], ~, List], # 35
  [NumGt, ~, [33, 29], 17, Boolean], # 36
  [Proj, {index: 0}, [17]], # 37
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 38
  [Add, ~, [29, 38], ~, Int]]} # 39
```

## A reference to a ternary of variables

\($c ? $v : 0) refers to $v itself: the arms are spelled as locations.

```perl
package N { sub new { bless { v => $_[1] }, $_[0] } sub val { $_[0]{v} } }
sub f { my ($n) = @_; my $v = $n->val; return "v=${\(defined $v ? $v : q{u})}" }
sub g { my ($c) = @_; my $v = 7; my $r = \($c ? $v : 0); $$r = 9 if $c; my $s = 5; my $t = 6; my @r = \($c ? ($s, $t) : ()); ${$r[1]} = 0 if $c; return "$v $s $t" }
print f(N->new(5)), f(N->new(undef)), " ", g(1), " ", g(0), "\n";
```

```behavior
parses: yes
```

```output
v=5v=u 9 5 0 7 5 6
```

```ir
N::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: v}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [HashLiteral, ~, [1, 5], 0, HashRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7], ~, Scalar, 4], # 8
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [6, 8], 6, Unknown, 4, true], # 9
  [Return, {implicit: true}, [9], 9, ~, 9]]} # 10
N::val: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: v}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: new, package: main, param_names: [], want: list}, [2, 3], 0, Object, 4, true], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [5], 5, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: new, package: main, param_names: [], want: list}, [2, 1], 6, Object, 6, true], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [8], 8, Str, 8, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::g, package: main, param_names: [], want: list}, [12], 9, Str, 9, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 15
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::g, package: main, param_names: [], want: list}, [15], 13, Str, 13, true], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [7, 10, 11, 14, 11, 17, 18], 16, "Maybe[Boolean]"], # 19
  [Return, {implicit: true}, [1], 19, ~, 16]]} # 20
main::f: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "v="}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: val, package: main, param_names: [], want: scalar}, [2], 0, Unknown, 3, true], # 4
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Unknown, 4], # 5
  [Assign, ~, [5, 4], 4, Unknown, 4, true], # 6
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Unknown, 6], # 7
  [Defined, ~, [7], ~, Boolean], # 8
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 9
  [TernaryExpr, ~, [8, 7, 9], ~, Unknown], # 10
  [Ref, ~, [10], ~, Unknown], # 11
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: $, strict: false}, [11], ~, Scalar, 6], # 12
  [Coerce, {from_repr: Scalar, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [1, 13], ~, Str], # 14
  [Return, ~, [14], 6, ~, 6], # 15
  [ArgsSource, ~, ~, ~, Array], # 16
  [Assign, {record: true, targets: 1}, [2, 16], ~, List]]} # 17
main::g: {start: 0, returns: [51], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Unknown, 1], # 2
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 3
  [Assign, ~, [2, 3], 0, Int, 1, true], # 4
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 5
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Unknown, 4], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [TernaryExpr, ~, [5, 6, 7], ~, Unknown], # 8
  [Ref, ~, [8], ~, Unknown], # 9
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 3, package: main, sigil: $, strict: false}, [9], ~, Scalar], # 10
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 11
  [If, ~, [4, 5], 4], # 12
  [Proj, {index: 0}, [12]], # 13
  [Assign, ~, [10, 11], 13, Int, 4, true], # 14
  [Proj, {index: 1}, [12]], # 15
  [Region, {head: 12}, [15, 14]], # 16
  [Phi, {memory: true, predecessors: [15, 13], region: 16}, [4, 14], ~, Int], # 17
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 17], # 18
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 19
  [Assign, ~, [18, 19], 16, Int, 17, true], # 20
  [PadAccess, {sigil: $, symbol: t}, ~, ~, Unknown, 20], # 21
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 22
  [Assign, ~, [21, 22], 20, Int, 20, true], # 23
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 23], # 24
  [PadAccess, {sigil: $, symbol: t}, ~, ~, Unknown, 23], # 25
  [ArrayLiteral, ~, [24, 25], ~, Array], # 26
  [ArrayLiteral, ~, ~, ~, Array], # 27
  [TernaryExpr, ~, [5, 26, 27], ~, Array], # 28
  [Ref, ~, [28], ~, ArrayRef], # 29
  [ArrayLiteral, {sigil: "@", symbol: r}, [29], ~, Array], # 30
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 31
  [Subscript, {kind: array}, [30, 31], ~, Undef], # 32
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 3, package: main, sigil: $, strict: false}, [32], ~, Scalar], # 33
  [If, ~, [23, 5], 23], # 34
  [Proj, {index: 0}, [34]], # 35
  [Assign, ~, [33, 7], 35, Int, 23, true], # 36
  [Proj, {index: 1}, [34]], # 37
  [Region, {head: 34}, [37, 36]], # 38
  [Phi, {memory: true, predecessors: [37, 35], region: 38}, [23, 36], ~, Int], # 39
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Str, 39], # 40
  [Coerce, {from_repr: Unknown, to_repr: Str}, [40], ~, Str], # 41
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 42
  [Concat, ~, [41, 42], ~, Str], # 43
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Str, 39], # 44
  [Coerce, {from_repr: Unknown, to_repr: Str}, [44], ~, Str], # 45
  [Concat, ~, [43, 45], ~, Str], # 46
  [Concat, ~, [46, 42], ~, Str], # 47
  [PadAccess, {sigil: $, symbol: t}, ~, ~, Str, 39], # 48
  [Coerce, {from_repr: Unknown, to_repr: Str}, [48], ~, Str], # 49
  [Concat, ~, [47, 49], ~, Str], # 50
  [Return, ~, [50], 38, ~, 39], # 51
  [ArgsSource, ~, ~, ~, Array], # 52
  [Assign, {record: true, targets: 1}, [5, 52], ~, List]]} # 53
```

## A slice through a defaulted reference

A slice off a reference the program computed is a postfix slice of that expression.

```perl
sub f { my ($n) = @_; my $i = $n->{in} // []; my @r = grep { defined } @{[ @$i[1 .. $#$i] ]}; return "@r" }
print f({ in => [1, 2, 3] }), "|", f({}), "\n";
```

```behavior
parses: yes
```

```output
2 3|
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: in}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 5
  [ArrayLiteral, ~, [3, 4, 5], 0, ArrayRef], # 6
  [HashLiteral, ~, [2, 6], 6, HashRef], # 7
  [MemStart], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [7], 7, Str, 8, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 11
  [HashLiteral, ~, ~, 9, HashRef], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [12], 12, Str, 9, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [10, 11, 14, 15], 13, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 13]]} # 17
main::f: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 1
  [Constant, {const_type: string, value: in}, ~, ~, Str], # 2
  [MemStart], # 3
  [Subscript, {kind: hash}, [1, 2], 0, Scalar, 3, true], # 4
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 4], # 5
  [Coerce, {from_repr: Scalar, to_repr: Str}, [5], ~, Str], # 6
  [ArrayLiteral, ~, ~, ~, Array], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Defined, ~, [4], ~, Boolean], # 9
  [If, ~, [4, 9], 4], # 10
  [Proj, {index: 1}, [10]], # 11
  [ArrayLiteral, ~, ~, 11, ArrayRef], # 12
  [DefinedOr, ~, [4, 12], ~, Scalar], # 13
  [PostfixDeref, {sigil: "@"}, [13], ~, Array, 4], # 14
  [Count, ~, [14], ~, Int, 4], # 15
  [Subtract, ~, [15, 8], ~, Int], # 16
  [Range, ~, [8, 16], ~, List], # 17
  [Slice, {kind: array}, [17, 13], ~, List], # 18
  [Proj, {index: 0}, [10]], # 19
  [Region, {head: 10}, [19, 12]], # 20
  [ArrayLiteral, ~, [18], 20, ArrayRef], # 21
  [Loop, {bound: entry}, [21], 21], # 22
  [Phi, {region: 22}, [7, 37], ~, Array], # 23
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [6, 23], ~, Str, 4], # 24
  [Proj, {index: 1}, [22]], # 25
  [Region, {head: 22}, [25]], # 26
  [Return, ~, [24], 26, ~, 4], # 27
  [PostfixDeref, {sigil: "@"}, [21], ~, Array, 4], # 28
  [Count, ~, [28], ~, Int, 4], # 29
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 30
  [Phi, {region: 22}, [30, 38], ~, Int], # 31
  [Subscript, {kind: array}, [28, 31], ~, Scalar, 4], # 32
  [ArgsSource, ~, ~, ~, Array], # 33
  [Assign, {record: true, targets: 1}, [1, 33], ~, List], # 34
  [NumGt, ~, [29, 31], 22, Boolean], # 35
  [Defined, ~, [32], ~, Boolean], # 36
  [ListAppend, {collector: grep}, [23, 32, 36], ~, Array], # 37
  [Add, ~, [31, 8], ~, Int], # 38
  [Proj, {index: 0}, [22]]]} # 39
```

## A defined-or die after a list assign

The die arm pushes nothing; the list assign's residue is not the fallback.

```perl
sub p { ("p$_[0]", length $_[0]) }
sub f { my ($a, $b) = @_; my ($ap, $al) = p($a); my ($bp, $bl) = p($b); ($a, $b) = ($ap, $bp); my $l = $al // die "no ($a)"; return "$a $b $l" }
print f("x", "yy"), "\n";
```

```behavior
parses: yes
```

```output
px pyy 1
```

```ir
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: yy}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2, 3], 0, Str, 4, true], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, "Maybe[Boolean]"], # 8
  [Return, {implicit: true}, [1], 8, ~, 5]]} # 9
main::f: {start: 0, returns: [41], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: bp}, ~, ~, Unknown], # 1
  [PadAccess, {sigil: $, symbol: bl}, ~, ~, Unknown], # 2
  [PadAccess, {sigil: $, symbol: ap}, ~, ~, Unknown], # 3
  [PadAccess, {sigil: $, symbol: al}, ~, ~, Unknown], # 4
  [MemStart], # 5
  [PadAccess, {sigil: $, symbol: a}, ~, ~, Unknown, 5], # 6
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Unknown, 5], # 7
  [ArgsSource, ~, ~, ~, Array], # 8
  [Assign, {targets: 2}, [6, 7, 8], 0, List, 5, true], # 9
  [PadAccess, {sigil: $, symbol: a}, ~, ~, Unknown, 9], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::p, package: main, param_names: [], want: list}, [10], 9, List, 9, true], # 11
  [Assign, {targets: 2}, [3, 4, 11], 11, List, 11, true], # 12
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Unknown, 12], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::p, package: main, param_names: [], want: list}, [13], 12, List, 12, true], # 14
  [Assign, {targets: 2}, [1, 2, 14], 14, List, 14, true], # 15
  [PadAccess, {sigil: $, symbol: a}, ~, ~, Unknown, 15], # 16
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Unknown, 15], # 17
  [Assign, {targets: 2}, [16, 17, 3, 1], 15, List, 15, true], # 18
  [PadAccess, {sigil: $, symbol: a}, ~, ~, Str, 18], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 20
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 21
  [Concat, ~, [20, 21], ~, Str], # 22
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Str, 18], # 23
  [Coerce, {from_repr: Unknown, to_repr: Str}, [23], ~, Str], # 24
  [Concat, ~, [22, 24], ~, Str], # 25
  [Concat, ~, [25, 21], ~, Str], # 26
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 27
  [DefinedOr, ~, [4, 27], ~, Unknown], # 28
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 29
  [Concat, ~, [26, 29], ~, Str], # 30
  [Defined, ~, [4], ~, Boolean], # 31
  [If, ~, [18, 31], 18], # 32
  [Proj, {index: 0}, [32]], # 33
  [Constant, {const_type: string, value: "no ("}, ~, ~, Str], # 34
  [Concat, ~, [34, 20], ~, Str], # 35
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 36
  [Concat, ~, [35, 36], ~, Str], # 37
  [Proj, {index: 1}, [32]], # 38
  [Unwind, {file: "/tmp/mvrHQew3rs/case.pl", line: 2}, [37], 38, ~, 18], # 39
  [Region, {head: 32}, [33, 39]], # 40
  [Return, ~, [30], 40, ~, 18]]} # 41
main::p: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: p}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [5], ~, Str], # 8
  [Length, ~, [8], ~, Int], # 9
  [ArrayLiteral, ~, [7, 9], ~, List], # 10
  [Coerce, {from_repr: List, to_repr: Scalar}, [9], ~, Scalar], # 11
  [Return, {implicit: true}, [10, 11], 0, ~, 4]]} # 12
```

## Arrays carried past a next in a loop

The value a next carries to the step is an array: its latch is an array variable, never a count.

```perl
sub f {
    my @body; my @params; my $name;
    for my $x (@_) {
        if (!ref $x) { next if $x eq 'sub'; $name = $x; }
        elsif (ref $x eq 'ARRAY') { if (@params) { @body = $x->@* } else { @params = $x->@* } }
    }
    return "$name|@params|@body";
}
print f("sub", "n", [1, 2], [3, 4, 5]), "\n";
```

```behavior
parses: yes
```

```output
n|1 2|3 4 5
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: sub}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [ArrayLiteral, ~, [4, 5], 0, ArrayRef], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 8
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 9
  [ArrayLiteral, ~, [7, 8, 9], 6, ArrayRef], # 10
  [MemStart], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::f, package: main, param_names: [], want: list}, [2, 3, 6, 10], 10, Str, 11, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [13, 14], 12, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 12]]} # 16
main::f: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 82], ~, Unknown], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [MemStart], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 7], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [PadAccess, {sigil: "@", symbol: params}, ~, ~, Array], # 10
  [Phi, {region: 2}, [10, 81], ~, Array], # 11
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [9, 11], ~, Str, 7], # 12
  [Concat, ~, [6, 12], ~, Str], # 13
  [Concat, ~, [13, 5], ~, Str], # 14
  [PadAccess, {sigil: "@", symbol: body}, ~, ~, Array], # 15
  [Phi, {region: 2}, [15, 77], ~, Array], # 16
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [9, 16], ~, Str, 7], # 17
  [Concat, ~, [14, 17], ~, Str], # 18
  [Proj, {index: 1}, [2]], # 19
  [Region, {head: 2}, [19]], # 20
  [Return, ~, [18], 20, ~, 7], # 21
  [ArgsSource, ~, ~, ~, Array], # 22
  [Count, ~, [22], ~, Int, 7], # 23
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 24
  [Phi, {region: 2}, [24, 63], ~, Int], # 25
  [NumGt, ~, [23, 25], 2, Boolean], # 26
  [Proj, {index: 0}, [2]], # 27
  [Exists, {kind: array}, [22, 25], 27, Boolean, 7], # 28
  [Subscript, {kind: array}, [22, 25], ~, Scalar], # 29
  [Ref, ~, [29], ~, ScalarRef], # 30
  [TernaryExpr, ~, [28, 30, 1], 28, "Maybe[ScalarRef]"], # 31
  [PostfixDeref, {sigil: $}, [31], ~, Scalar, 7], # 32
  [Subscript, {kind: array}, [22, 25], ~, Scalar, 7], # 33
  [TernaryExpr, ~, [28, 32, 33], 31, Scalar], # 34
  [RefType, ~, [34], ~, Str, 7], # 35
  [PostfixDeref, {sigil: $}, [31], ~, Scalar, 7], # 36
  [Subscript, {kind: array}, [22, 25], ~, Scalar, 7], # 37
  [TernaryExpr, ~, [28, 36, 37], ~, Scalar], # 38
  [RefType, ~, [38], ~, Str, 7], # 39
  [Count, ~, [11], ~, Int, 7], # 40
  [PostfixDeref, {sigil: $}, [31], ~, Scalar, 7], # 41
  [Subscript, {kind: array}, [22, 25], ~, Scalar, 7], # 42
  [TernaryExpr, ~, [28, 41, 42], ~, Scalar], # 43
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 5, package: main, sigil: "@", strict: false}, [43], ~, Array, 7], # 44
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 5, package: main, sigil: "@", strict: false}, [43], ~, Array, 7], # 45
  [PostfixDeref, {sigil: $}, [31], ~, Scalar, 7], # 46
  [Subscript, {kind: array}, [22, 25], ~, Scalar, 7], # 47
  [TernaryExpr, ~, [28, 46, 47], ~, Scalar], # 48
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 5, package: main, sigil: "@", strict: false}, [48], ~, Array, 7], # 49
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 5, package: main, sigil: "@", strict: false}, [48], ~, Array, 7], # 50
  [PostfixDeref, {sigil: $}, [31], ~, Scalar, 7], # 51
  [Subscript, {kind: array}, [22, 25], ~, Scalar, 7], # 52
  [PostfixDeref, {sigil: $}, [31], ~, Scalar, 7], # 53
  [Subscript, {kind: array}, [22, 25], ~, Scalar, 7], # 54
  [TernaryExpr, ~, [28, 51, 52], ~, Scalar], # 55
  [TernaryExpr, ~, [28, 53, 54], ~, Scalar], # 56
  [Not, ~, [35], ~, Boolean], # 57
  [Constant, {const_type: string, value: ARRAY}, ~, ~, Str], # 58
  [StrEq, ~, [39, 58], ~, Boolean], # 59
  [TernaryExpr, ~, [40, 50, 16], ~, Array], # 60
  [TernaryExpr, ~, [40, 11, 45], ~, Array], # 61
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 62
  [Add, ~, [25, 62], ~, Int], # 63
  [TernaryExpr, ~, [59, 60, 16], ~, Array], # 64
  [If, ~, [34, 57], 34], # 65
  [Proj, {index: 0}, [65]], # 66
  [Coerce, {from_repr: Scalar, to_repr: Str}, [55], ~, Str], # 67
  [Constant, {const_type: string, value: sub}, ~, ~, Str], # 68
  [StrEq, ~, [67, 68], ~, Boolean], # 69
  [If, ~, [66, 69], 66], # 70
  [Proj, {index: 1}, [70]], # 71
  [Proj, {index: 1}, [65]], # 72
  [Region, {head: 65}, [71, 72]], # 73
  [Phi, {predecessors: [66, 72], region: 73}, [16, 64], ~, Array], # 74
  [Proj, {index: 0}, [70]], # 75
  [Region, {head: 2}, [73, 75]], # 76
  [Phi, {predecessors: [27, 75], region: 76}, [74, 16], ~, Array], # 77
  [Phi, {predecessors: [66, 72], region: 73}, [56, 3], ~, Unknown], # 78
  [TernaryExpr, ~, [59, 61, 11], ~, Array], # 79
  [Phi, {predecessors: [66, 72], region: 73}, [11, 79], ~, Array], # 80
  [Phi, {predecessors: [27, 75], region: 76}, [80, 11], ~, Array], # 81
  [Phi, {predecessors: [27, 75], region: 76}, [78, 3], ~, Unknown]]} # 82
```

## A push onto an array merged at a join

The mutator's container is the join variable itself, which is the aggregate.

```perl
sub f { my ($c, @n) = @_; my @l = (1); if ($c) { if ("@l" =~ /1/ && "@n" =~ /2/) { my @x; push @x, @n; @l = @x } } push @l, "}"; return "@l" }
print f(1, 2, 3), "|", f(0, 2), "\n";
```

```behavior
parses: yes
```

```output
2 3 }|1 }
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [2, 3, 4], 0, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [9, 3], 6, Str, 6, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [7, 8, 11, 12], 10, "Maybe[Boolean]"], # 13
  [Return, {implicit: true}, [1], 13, ~, 10]]} # 14
main::f: {start: 0, returns: [34], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [ArrayLiteral, {sigil: "@", symbol: l}, [1], ~, Array], # 2
  [PadAccess, {sigil: "@", symbol: x}, ~, ~, Array], # 3
  [PadAccess, {sigil: "@", symbol: "n"}, ~, ~, Unknown], # 4
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 0}, [6]], # 7
  [MemStart], # 8
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 8], # 9
  [Coerce, {from_repr: Scalar, to_repr: Str}, [9], ~, Str], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [10, 1], ~, Str], # 11
  [RegexMatch, {flags: "", pattern: "1"}, [11], ~, Boolean], # 12
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [10, 4], ~, Str, 8], # 13
  [RegexMatch, {flags: "", pattern: "2"}, [13], ~, Boolean], # 14
  [And, ~, [12, 14], ~, Boolean], # 15
  [If, ~, [7, 15], 7], # 16
  [Proj, {index: 0}, [16]], # 17
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [3, 4], 17, Int, 8, true], # 18
  [ArrayLiteral, {rebinds: true, sigil: "@", symbol: l}, [3], 18, Array], # 19
  [Proj, {index: 1}, [16]], # 20
  [Region, {head: 16}, [20, 19]], # 21
  [Phi, {predecessors: [20, 17], region: 21}, [2, 19], ~, Array], # 22
  [Proj, {index: 1}, [6]], # 23
  [Region, {head: 6}, [23, 21]], # 24
  [Phi, {predecessors: [23, 7], region: 24}, [2, 22], ~, Array], # 25
  [Constant, {const_type: string, value: "}"}, ~, ~, Str], # 26
  [Phi, {memory: true, predecessors: [20, 17], region: 21}, [8, 18], ~, Unknown], # 27
  [Phi, {memory: true, predecessors: [23, 7], region: 24}, [8, 27], ~, Unknown], # 28
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [25, 26], 24, Int, 28, true], # 29
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 29], # 30
  [Coerce, {from_repr: Scalar, to_repr: Str}, [30], ~, Str], # 31
  [PostfixDeref, {sigil: "@"}, [25], ~, Array, 29], # 32
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [31, 32], ~, Str, 29], # 33
  [Return, ~, [33], 29, ~, 29], # 34
  [ArgsSource, ~, ~, ~, Array], # 35
  [Assign, {record: true, targets: 2}, [5, 4, 35], ~, List]]} # 36
```

## A sort over a dereferenced element before a read of a sibling key

A dereference handed to a call gives it the elements, never the slot that holds the reference.

```perl
sub f { my ($registry) = @_; my @lines;
    for my $cname (sort keys %$registry) { my $reg = $registry->{$cname}; my $fields = $reg->{fields} // [];
        my $is = $reg->{is_class} ? 1 : 0; my @sorted = sort { $a->{i} <=> $b->{i} } @$fields;
        push @lines, "$cname:" . join(",", map { $_->{i} } @sorted) if $is }
    return "@lines" }
print f({ A => { is_class => 1, fields => [{ i => 2 }, { i => 1 }] }, B => { fields => [] } }), "\n";
```

```behavior
parses: yes
```

```output
A:1,2
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: A}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: is_class}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: string, value: fields}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: i}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [HashLiteral, ~, [6, 7], 0, HashRef], # 8
  [HashLiteral, ~, [6, 4], 8, HashRef], # 9
  [ArrayLiteral, ~, [8, 9], 9, ArrayRef], # 10
  [HashLiteral, ~, [3, 4, 5, 10], 10, HashRef], # 11
  [Constant, {const_type: string, value: B}, ~, ~, Str], # 12
  [ArrayLiteral, ~, ~, 11, ArrayRef], # 13
  [HashLiteral, ~, [5, 13], 13, HashRef], # 14
  [HashLiteral, ~, [2, 11, 12, 14], 14, HashRef], # 15
  [MemStart], # 16
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: main::f, package: main, param_names: [], want: list}, [15], 15, Str, 16, true], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Print, ~, [18, 19], 17, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 17]]} # 21
main::f: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: registry}, ~, ~, Unknown], # 1
  [MemStart], # 2
  [PostfixDeref, {sigil: "%"}, [1], 0, Hash, 2, true], # 3
  [Loop, {bound: entry}, [3], 3], # 4
  [Phi, {memory: true, region: 4}, [3, 63], ~, List], # 5
  [Proj, {index: 1}, [4]], # 6
  [Region, {head: 4}, [6]], # 7
  [Phi, {memory: true, region: 7}, [5], ~, List], # 8
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 8], # 9
  [Coerce, {from_repr: Scalar, to_repr: Str}, [9], ~, Str], # 10
  [PadAccess, {sigil: "@", symbol: lines}, ~, ~, Array], # 11
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [10, 11], ~, Str, 8], # 12
  [Return, ~, [12], 7, ~, 8], # 13
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [3], ~, List, 3], # 14
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [14], ~, List, 3], # 15
  [ArrayLiteral, ~, [15], ~, Array], # 16
  [Count, ~, [16], ~, Int, 3], # 17
  [ArgsSource, ~, ~, ~, Array], # 18
  [Assign, {record: true, targets: 1}, [1, 18], ~, List], # 19
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 20
  [Phi, {region: 4}, [20, 66], ~, Int], # 21
  [Subscript, {kind: array}, [16, 21], ~, Scalar], # 22
  [Proj, {index: 0}, [4]], # 23
  [Ref, ~, [22], 23, ScalarRef, 5], # 24
  [PostfixDeref, {sigil: $}, [24], 24, Scalar, 5], # 25
  [Subscript, {kind: hash}, [1, 25], 25, Scalar, 5, true], # 26
  [Count, ~, [16], ~, Int, 5], # 27
  [NumGt, ~, [27, 21], 4, Boolean], # 28
  [Constant, {const_type: string, value: fields}, ~, ~, Str], # 29
  [Subscript, {kind: hash}, [26, 29], 26, Scalar, 26, true], # 30
  [Defined, ~, [30], ~, Boolean], # 31
  [If, ~, [30, 31], 30], # 32
  [Proj, {index: 1}, [32]], # 33
  [ArrayLiteral, ~, ~, 33, ArrayRef], # 34
  [Proj, {index: 0}, [32]], # 35
  [Region, {head: 32}, [35, 34]], # 36
  [Phi, {predecessors: [35, 33], region: 36}, [30, 34], ~, Scalar], # 37
  [Constant, {const_type: string, value: is_class}, ~, ~, Str], # 38
  [Subscript, {kind: hash}, [26, 38], 36, Scalar, 30, true], # 39
  [PostfixDeref, {sigil: "@"}, [37], ~, Array, 39], # 40
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::f::__SORTCMP__:1, sort_package: main, want: list}, [40], 39, List, 39, true], # 41
  [PostfixDeref, {sigil: $}, [24], ~, Scalar, 41], # 42
  [Coerce, {from_repr: Scalar, to_repr: Str}, [42], ~, Str], # 43
  [Constant, {const_type: string, value: ":"}, ~, ~, Str], # 44
  [Concat, ~, [43, 44], ~, Str], # 45
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 46
  [ArrayLiteral, ~, ~, ~, Array], # 47
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 48
  [TernaryExpr, ~, [39, 48, 20], ~, Int], # 49
  [If, ~, [41, 49], 41], # 50
  [Proj, {index: 0}, [50]], # 51
  [Loop, {bound: entry}, [51], 51], # 52
  [Phi, {region: 52}, [47, 76], ~, Array], # 53
  [Phi, {memory: true, region: 52}, [41, 73], ~, List], # 54
  [Proj, {index: 1}, [52]], # 55
  [Region, {head: 52}, [55]], # 56
  [Phi, {memory: true, region: 56}, [54], ~, List], # 57
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [46, 53], ~, Str, 57], # 58
  [Concat, ~, [45, 58], ~, Str], # 59
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [11, 59], 56, Int, 57, true], # 60
  [Proj, {index: 1}, [50]], # 61
  [Region, {head: 50}, [60, 61]], # 62
  [Phi, {memory: true, predecessors: [51, 61], region: 62}, [60, 41], ~, List], # 63
  [Subscript, {kind: array}, [16, 21], ~, Scalar, 5], # 64
  [Subscript, {kind: array}, [16, 21], ~, Scalar, 41], # 65
  [Add, ~, [21, 48], ~, Int], # 66
  [Count, ~, [41], ~, Int, 41], # 67
  [Count, ~, [41], ~, Int, 54], # 68
  [Phi, {region: 52}, [20, 75], ~, Int], # 69
  [Subscript, {kind: array}, [41, 69], ~, Scalar, 54], # 70
  [Constant, {const_type: string, value: i}, ~, ~, Str], # 71
  [Proj, {index: 0}, [52]], # 72
  [Subscript, {kind: hash}, [70, 71], 72, Scalar, 54, true], # 73
  [NumGt, ~, [68, 69], 52, Boolean], # 74
  [Add, ~, [69, 48], ~, Int], # 75
  [ListAppend, {collector: map}, [53, 73], ~, Array]]} # 76
main::f::__SORTCMP__:1: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: a}, ~, ~, Scalar, 1], # 2
  [Constant, {const_type: string, value: i}, ~, ~, Str], # 3
  [Subscript, {kind: hash}, [2, 3], 0, Scalar, 1, true], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [EntryDef, {package: main, sigil: $, symbol: b}, ~, ~, Scalar, 4], # 6
  [Subscript, {kind: hash}, [6, 3], 4, Scalar, 4, true], # 7
  [Coerce, {from_repr: Scalar, to_repr: Num}, [7], ~, Num], # 8
  [NumCmp, ~, [5, 8], ~, Int], # 9
  [Return, {implicit: true}, [9], 7, ~, 7]]} # 10
```

## An array rewritten in two ifs, then iterated

Each if merges two arrays into an array, and the copy is read where it stands.

```perl
sub f { my @lines; push @lines, "a", "b"; if ($_[0]) { my @n; for my $l (@lines) { push @n, uc $l } @lines = @n }
  if ($_[1]) { my @n; for my $l (@lines) { push @n, "$l$l" } @lines = @n } my $s = ""; for my $l (@lines) { $s .= $l } return $s }
print f(1, 0), f(0, 1), f(1, 1), f(0, 0), "\n";
```

```behavior
parses: yes
```

```output
ABaabbAABBab
```

```ir
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2, 3], 0, Str, 4, true], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [3, 2], 5, Str, 5, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2, 2], 7, Str, 7, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [3, 3], 9, Str, 9, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [6, 8, 10, 12, 13], 11, "Maybe[Boolean]"], # 14
  [Return, {implicit: true}, [1], 14, ~, 11]]} # 15
main::f: {start: 0, returns: [40], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: lines}, ~, ~, Array], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 3, 4], 0, Int, 5, true], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Subscript, {kind: array}, [7, 8], ~, Scalar, 6], # 9
  [If, ~, [6, 9], 6], # 10
  [Proj, {index: 1}, [10]], # 11
  [PadAccess, {sigil: "@", symbol: "n"}, ~, ~, Array], # 12
  [Proj, {index: 0}, [10]], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Proj, {index: 1}, [14]], # 15
  [Region, {head: 14}, [15]], # 16
  [ArrayLiteral, {rebinds: true, sigil: "@", symbol: lines}, [12], 16, Array], # 17
  [Region, {head: 10}, [11, 17]], # 18
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 19
  [Phi, {memory: true, region: 14}, [6, 54], ~, Int], # 20
  [Phi, {memory: true, region: 16}, [20], ~, Int], # 21
  [Phi, {memory: true, predecessors: [11, 13], region: 18}, [6, 21], ~, Int], # 22
  [Subscript, {kind: array}, [7, 19], ~, Scalar, 22], # 23
  [If, ~, [18, 23], 18], # 24
  [Proj, {index: 1}, [24]], # 25
  [PadAccess, {sigil: "@", symbol: n__2}, ~, ~, Array], # 26
  [Proj, {index: 0}, [24]], # 27
  [Loop, {bound: entry}, [27], 27], # 28
  [Proj, {index: 1}, [28]], # 29
  [Region, {head: 28}, [29]], # 30
  [ArrayLiteral, {rebinds: true, sigil: "@", symbol: lines}, [26], 30, Array], # 31
  [Region, {head: 24}, [25, 31]], # 32
  [Loop, {bound: entry}, [32], 32], # 33
  [Phi, {region: 33}, [1, 47], ~, Str], # 34
  [Proj, {index: 1}, [33]], # 35
  [Region, {head: 33}, [35]], # 36
  [Phi, {memory: true, region: 28}, [22, 64], ~, Int], # 37
  [Phi, {memory: true, region: 30}, [37], ~, Int], # 38
  [Phi, {memory: true, predecessors: [25, 27], region: 32}, [22, 38], ~, Int], # 39
  [Return, ~, [34], 36, ~, 39], # 40
  [Count, ~, [2], ~, Int, 6], # 41
  [Phi, {predecessors: [11, 13], region: 18}, [2, 17], ~, Array], # 42
  [Phi, {predecessors: [25, 27], region: 32}, [42, 31], ~, Array], # 43
  [Phi, {region: 33}, [8, 66], ~, Int], # 44
  [Subscript, {kind: array}, [43, 44], ~, Scalar, 39], # 45
  [Coerce, {from_repr: Unknown, to_repr: Str}, [45], ~, Str], # 46
  [Concat, ~, [34, 46], ~, Str], # 47
  [Count, ~, [43], ~, Int, 39], # 48
  [Count, ~, [2], ~, Int, 20], # 49
  [Phi, {region: 14}, [8, 67], ~, Int], # 50
  [Subscript, {kind: array}, [2, 50], ~, Scalar, 20], # 51
  [Call, {dispatch_kind: builtin, name: uc, param_names: []}, [51], ~, Str], # 52
  [Proj, {index: 0}, [14]], # 53
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [12, 52], 53, Int, 20, true], # 54
  [Count, ~, [42], ~, Int, 22], # 55
  [NumGt, ~, [48, 44], 33, Boolean], # 56
  [NumGt, ~, [49, 50], 14, Boolean], # 57
  [Count, ~, [42], ~, Int, 37], # 58
  [Phi, {region: 28}, [8, 69], ~, Int], # 59
  [Subscript, {kind: array}, [42, 59], ~, Scalar, 37], # 60
  [Coerce, {from_repr: Scalar, to_repr: Str}, [60], ~, Str], # 61
  [Concat, ~, [61, 61], ~, Str], # 62
  [Proj, {index: 0}, [28]], # 63
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [26, 62], 63, Int, 37, true], # 64
  [Proj, {index: 0}, [33]], # 65
  [Add, ~, [44, 19], ~, Int], # 66
  [Add, ~, [50, 19], ~, Int], # 67
  [NumGt, ~, [58, 59], 28, Boolean], # 68
  [Add, ~, [59, 19], ~, Int]]} # 69
```

## A demoted parameter stored into again

At the sub's top level the store is the parameter itself; an inner my in a loop still shadows it.

```perl
use v5.42; sub g ($x) { "g$x" } sub f ($c) { $c = g($c); return g($c) }
sub h ($x) { my $r = \$x; my @l; for (1..2) { my $x = $_; push @l, \$x } $$r = 0; join ",", $x, map { $$_ } @l }
print f(1), " ", h(5), "\n";
```

```behavior
parses: yes
```

```output
gg1 0,1,2
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::h, package: main, param_names: [], want: list}, [7], 4, Str, 4, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [5, 6, 9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
main::f: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 1], # 2
  [Parameter, {index: 0, name: $c, sigil: $}, ~, ~, Unknown], # 3
  [Assign, ~, [2, 3], 0, Unknown, 1, true], # 4
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 4], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::g, package: main, param_names: [], want: scalar}, [5], 4, Str, 4, true], # 6
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 6], # 7
  [Assign, ~, [7, 6], 6, Str, 6, true], # 8
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 8], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::g, package: main, param_names: []}, [9], 8, Str, 8, true], # 10
  [Return, ~, [10], 10, ~, 10]]} # 11
main::g: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: g}, ~, ~, Str], # 1
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Concat, ~, [1, 3], ~, Str], # 4
  [MemStart], # 5
  [Return, {implicit: true}, [4], 0, ~, 5]]} # 6
main::h: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 2], # 3
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Unknown], # 4
  [Assign, ~, [3, 4], 0, Unknown, 2, true], # 5
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 5], # 6
  [Ref, ~, [6], ~, Unknown], # 7
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: $, strict: true}, [7], ~, Scalar], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Loop, {bound: entry}, [5], 5], # 10
  [Proj, {index: 1}, [10]], # 11
  [Region, {head: 10}, [11]], # 12
  [Phi, {memory: true, region: 10}, [5, 36], ~, Unknown], # 13
  [Phi, {memory: true, region: 12}, [13], ~, Unknown], # 14
  [Assign, ~, [8, 9], 12, Int, 14, true], # 15
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 15], # 16
  [ArrayLiteral, ~, ~, ~, Array], # 17
  [Loop, {bound: entry}, [15], 15], # 18
  [Phi, {region: 18}, [17, 42], ~, Array], # 19
  [Phi, {memory: true, region: 18}, [15, 41], ~, Scalar], # 20
  [Proj, {index: 1}, [18]], # 21
  [Region, {head: 18}, [21]], # 22
  [Phi, {memory: true, region: 22}, [20], ~, Scalar], # 23
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 16, 19], ~, Str, 23], # 24
  [Return, {implicit: true}, [24], 22, ~, 23], # 25
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 26
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 27
  [Phi, {region: 10}, [27, 46], ~, Int], # 28
  [NumGt, ~, [26, 28], 10, Boolean], # 29
  [Proj, {index: 0}, [10]], # 30
  [PadAccess, {sigil: "@", symbol: l}, ~, ~, Array], # 31
  [PadAccess, {sigil: $, symbol: x__2}, ~, ~, Unknown, 13], # 32
  [Assign, ~, [32, 28], 30, Int, 13, true], # 33
  [PadAccess, {sigil: $, symbol: x__2}, ~, ~, Unknown, 33], # 34
  [Ref, {fresh_each_pass: true}, [34], ~, Unknown], # 35
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [31, 35], 33, Int, 33, true], # 36
  [ArrayLiteral, ~, [31], ~, List], # 37
  [Phi, {region: 18}, [9, 48], ~, Int], # 38
  [Subscript, {kind: array}, [37, 38], ~, Scalar, 20], # 39
  [Proj, {index: 0}, [18]], # 40
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: $, strict: true}, [39], 40, Scalar, 20, true], # 41
  [ListAppend, {collector: map}, [19, 41], ~, Array], # 42
  [Count, ~, [37], ~, Int, 20], # 43
  [Count, ~, [37], ~, Int, 15], # 44
  [NumGt, ~, [43, 38], 18, Boolean], # 45
  [Add, ~, [28, 27], ~, Int], # 46
  [ArrayLiteral, ~, [31], ~, List], # 47
  [Add, ~, [38, 27], ~, Int]]} # 48
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
```

## A slice by a grep in an elsif arm

A named copy of the slice is declared after the grep's loop, not after the call it also reads.

```perl
sub mk { my ($op, @in) = @_; { op => $op, in => [@in] } } sub operation { $_[0]{op} } sub inputs { $_[0]{in} }
sub f { my ($c) = @_; my $op = operation($c); my @in = inputs($c)->@*; my @e;
  if ($op eq "A") { @e = @in } elsif ($op eq "H") { @e = @in[ grep { $_ % 2 } 0 .. $#in ] } else { return "u" } return "@e" }
print f(mk("A", 1, 2)), "|", f(mk("H", "k", 1, "j", 2)), "|", f(mk("X")), "\n";
```

```behavior
parses: yes
```

```output
1 2|1 2|u
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: A}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::mk, package: main, param_names: [], want: list}, [2, 3, 4], 0, HashRef, 5, true], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [6], 6, Str, 6, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: H}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: j}, ~, ~, Str], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::mk, package: main, param_names: [], want: list}, [10, 11, 3, 12, 4], 7, HashRef, 7, true], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [13], 13, Str, 13, true], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: X}, ~, ~, Str], # 16
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::mk, package: main, param_names: [], want: list}, [16], 14, HashRef, 14, true], # 17
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [17], 17, Str, 17, true], # 18
  [Coerce, {from_repr: Unknown, to_repr: Str}, [18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Print, ~, [8, 9, 15, 9, 19, 20], 18, "Maybe[Boolean]"], # 21
  [Return, {implicit: true}, [1], 21, ~, 18]]} # 22
main::f: {start: 0, returns: [37], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 2], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Assign, {targets: 1}, [3, 4], 0, List, 2, true], # 5
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 5], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::operation, package: main, param_names: [], want: scalar}, [6], 5, Scalar, 5, true], # 7
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown, 7], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::inputs, package: main, param_names: [], want: scalar}, [8], 7, Scalar, 7, true], # 9
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: "@", strict: false}, [9], 9, Array, 9, true], # 10
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 10], # 11
  [Coerce, {from_repr: Scalar, to_repr: Str}, [11], ~, Str], # 12
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: "@", strict: false}, [9], ~, Array, 9], # 13
  [ArrayLiteral, ~, ~, ~, Array], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 15
  [Constant, {const_type: string, value: A}, ~, ~, Str], # 16
  [StrEq, ~, [15, 16], ~, Boolean], # 17
  [If, ~, [10, 17], 10], # 18
  [Proj, {index: 1}, [18]], # 19
  [Constant, {const_type: string, value: H}, ~, ~, Str], # 20
  [StrEq, ~, [15, 20], ~, Boolean], # 21
  [If, ~, [19, 21], 19], # 22
  [Proj, {index: 0}, [22]], # 23
  [Loop, {bound: entry}, [23], 23], # 24
  [Phi, {region: 24}, [14, 50], ~, Array], # 25
  [Slice, {kind: array}, [25, 13], ~, List], # 26
  [ArrayLiteral, {sigil: "@", symbol: e}, [26], ~, Array], # 27
  [Proj, {index: 0}, [18]], # 28
  [Proj, {index: 1}, [24]], # 29
  [Region, {head: 24}, [29]], # 30
  [Region, {head: 18}, [28, 30]], # 31
  [Phi, {predecessors: [28, 19], region: 31}, [13, 27], ~, Array], # 32
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 32], ~, Str, 10], # 33
  [Proj, {index: 1}, [22]], # 34
  [Region, ~, [34, 31]], # 35
  [Phi, {predecessors: [34, 31], region: 35}, [1, 33], ~, Str], # 36
  [Return, ~, [36], 35, ~, 10], # 37
  [Count, ~, [13], ~, Int, 10], # 38
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 39
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 40
  [Subtract, ~, [38, 40], ~, Int], # 41
  [Range, ~, [39, 41], ~, List], # 42
  [Count, ~, [42], ~, Int, 10], # 43
  [Phi, {region: 24}, [39, 51], ~, Int], # 44
  [Subscript, {kind: array}, [42, 44], ~, Scalar, 10], # 45
  [NumGt, ~, [43, 44], 24, Boolean], # 46
  [Coerce, {from_repr: Scalar, to_repr: Num}, [45], ~, Num], # 47
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 48
  [Modulo, ~, [47, 48], ~, Int], # 49
  [ListAppend, {collector: grep}, [25, 45, 49], ~, Array], # 50
  [Add, ~, [44, 40], ~, Int], # 51
  [Proj, {index: 0}, [24]]]} # 52
main::inputs: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: in}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
main::mk: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: op}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: op}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: in}, ~, ~, Str], # 3
  [PadAccess, {sigil: "@", symbol: in}, ~, ~, Unknown], # 4
  [ArrayLiteral, ~, [4], 0, ArrayRef], # 5
  [HashLiteral, ~, [1, 2, 3, 5], 5, HashRef], # 6
  [MemStart], # 7
  [Return, {implicit: true}, [6], 6, ~, 7], # 8
  [ArgsSource, ~, ~, ~, Array], # 9
  [Assign, {record: true, targets: 2}, [2, 4, 9], ~, List]]} # 10
main::operation: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: op}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## A last after a postfix if pays the loop's exit

The payment walk passes the diamond by its merge, as the edge test does.

```perl
sub f { my ($c) = @_; my ($name, $base); my $k = 0;
  while ($k++ < 5) { if (ref $c eq 'HASH') { $name = $c->{n}; my $a = $c->{a}; $base = $a->[0] if @$a > 0; last } $c = { n => "x", a => [] } }
  return ($name // 'u') . ($base // 'u') }
print f({ n => "e", a => ["b"] }), f(1), "\n";
```

```behavior
parses: yes
```

```output
ebxu
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: e}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [ArrayLiteral, ~, [5], 0, ArrayRef], # 6
  [HashLiteral, ~, [2, 3, 4, 6], 6, HashRef], # 7
  [MemStart], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [7], 7, Str, 8, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::f, package: main, param_names: [], want: list}, [11], 9, Str, 9, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [10, 13, 14], 12, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 12]]} # 16
main::f: {start: 0, returns: [38], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 2
  [Loop, {bound: each}, [0], 0], # 3
  [Phi, {region: 3}, [2, 47], ~, Unknown], # 4
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 5
  [Proj, {index: 0}, [3]], # 6
  [MemStart], # 7
  [RefType, ~, [4], ~, Str, 7], # 8
  [Constant, {const_type: string, value: HASH}, ~, ~, Str], # 9
  [StrEq, ~, [8, 9], ~, Boolean], # 10
  [If, ~, [6, 10], 6], # 11
  [Proj, {index: 0}, [11]], # 12
  [Subscript, {kind: hash}, [4, 5], 12, Scalar, 7, true], # 13
  [Proj, {index: 1}, [3]], # 14
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 15
  [Subscript, {kind: hash}, [4, 15], 13, Scalar, 13, true], # 16
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 2, package: main, sigil: "@", strict: false}, [16], 16, Array, 16, true], # 17
  [Count, ~, [17], ~, Int, 17], # 18
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 19
  [NumGt, ~, [18, 19], ~, Boolean], # 20
  [If, ~, [17, 20], 17], # 21
  [Proj, {index: 1}, [21]], # 22
  [Proj, {index: 0}, [21]], # 23
  [Subscript, {kind: array}, [16, 19], 23, Scalar, 17, true], # 24
  [Region, {head: 21}, [22, 24]], # 25
  [Region, {head: 3}, [14, 25]], # 26
  [Phi, {region: 26}, [1, 13], ~, Undef], # 27
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 28
  [DefinedOr, ~, [27, 28], ~, "Maybe[Str]"], # 29
  [Coerce, {from_repr: "Maybe[Str]", to_repr: Str}, [29], ~, Str], # 30
  [Phi, {predecessors: [22, 23], region: 25}, [1, 24], ~, Scalar], # 31
  [Phi, {region: 26}, [1, 31], ~, Undef], # 32
  [DefinedOr, ~, [32, 28], ~, "Maybe[Str]"], # 33
  [Coerce, {from_repr: "Maybe[Str]", to_repr: Str}, [33], ~, Str], # 34
  [Concat, ~, [30, 34], ~, Str], # 35
  [Phi, {memory: true, predecessors: [22, 23], region: 25}, [17, 24], ~, List], # 36
  [Phi, {memory: true, region: 26}, [7, 36], ~, Unknown], # 37
  [Return, ~, [35], 26, ~, 37], # 38
  [Phi, {region: 3}, [19, 43], ~, Int], # 39
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 40
  [NumLt, ~, [39, 40], 3, Boolean], # 41
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 42
  [Add, ~, [39, 42], ~, Int], # 43
  [Proj, {index: 1}, [11]], # 44
  [ArrayLiteral, ~, ~, 44, ArrayRef], # 45
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 46
  [HashLiteral, ~, [5, 46, 15, 45], 45, HashRef], # 47
  [ArgsSource, ~, ~, ~, Array], # 48
  [Assign, {record: true, targets: 1}, [2, 48], ~, List]]} # 49
```

## Keys taken before a call writes through a reference

The keys are read where they stand, into a list, before the callee adds one.

```perl
sub add { my ($h) = @_; $h->{b} = 2; 2 }
sub f { my %pre = (a => 1); my $s = join(",", sort keys %pre); add(\%pre); return "$s|" . join(",", sort keys %pre) }
print f(), "\n";
```

```behavior
parses: yes
```

```output
a|a,b
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::add: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [PadAccess, {sigil: $, symbol: h}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Assign, ~, [4, 1], 0, Int, 5, true], # 6
  [Return, {implicit: true}, [1], 6, ~, 6], # 7
  [ArgsSource, ~, ~, ~, Array], # 8
  [Assign, {record: true, targets: 1}, [2, 8], ~, List]]} # 9
main::f: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [HashLiteral, {sigil: "%", symbol: pre}, [2, 3], ~, Hash], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [4], ~, List, 5], # 6
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [6], ~, List, 5], # 7
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 7], ~, Str, 5], # 8
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Ref, ~, [4], ~, HashRef], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::add, package: main, param_names: [], want: void}, [11], 0, Int, 5, true], # 12
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [4], ~, List, 12], # 13
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [13], ~, List, 12], # 14
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 14], ~, Str, 12], # 15
  [Concat, ~, [10, 15], ~, Str], # 16
  [Return, ~, [16], 12, ~, 12]]} # 17
```

## A slice through a scalar holding a reference

The scalar is spelled as itself and the slice is postfix: there is no array of that name.

```perl
sub f { my ($c, $i) = @_; return join "", grep { defined } @{$c}[$i + 1, $i + 2] } sub g { my ($h) = @_; return join ",", @{$h}{qw(a b)} }
print f([qw(a b c d)], 0), f([qw(a b)], 0), g({a => 1, b => 2}), "\n";
```

```behavior
parses: yes
```

```output
bcb1,2
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 5
  [ArrayLiteral, ~, [2, 3, 4, 5], 0, ArrayRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [MemStart], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [6, 7], 6, Str, 8, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [ArrayLiteral, ~, [2, 3], 9, ArrayRef], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [11, 7], 11, Str, 9, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 14
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 15
  [HashLiteral, ~, [2, 14, 3, 15], 12, HashRef], # 16
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::g, package: main, param_names: [], want: list}, [16], 16, Str, 12, true], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Print, ~, [10, 13, 18, 19], 17, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 17]]} # 21
main::f: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 24], ~, Array], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 4], ~, Str, 5], # 6
  [Proj, {index: 1}, [3]], # 7
  [Region, {head: 3}, [7]], # 8
  [Return, ~, [6], 8, ~, 5], # 9
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Num], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [Add, ~, [10, 11], ~, Num], # 12
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 13
  [Add, ~, [10, 13], ~, Num], # 14
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 15
  [Slice, {kind: array}, [12, 14, 15], ~, List], # 16
  [Count, ~, [16], ~, Int, 5], # 17
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 18
  [Phi, {region: 3}, [18, 25], ~, Int], # 19
  [NumGt, ~, [17, 19], 3, Boolean], # 20
  [Proj, {index: 0}, [3]], # 21
  [Subscript, {kind: array}, [16, 19], ~, Scalar, 5], # 22
  [Defined, ~, [22], ~, Boolean], # 23
  [ListAppend, {collector: grep}, [4, 22, 23], ~, Array], # 24
  [Add, ~, [19, 11], ~, Int], # 25
  [ArgsSource, ~, ~, ~, Array], # 26
  [Assign, {record: true, targets: 2}, [15, 10, 26], ~, List]]} # 27
main::g: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [PadAccess, {sigil: $, symbol: h}, ~, ~, Unknown], # 4
  [Slice, {kind: hash}, [2, 3, 4], ~, List], # 5
  [MemStart], # 6
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 5], ~, Str, 6], # 7
  [Return, ~, [7], 0, ~, 6], # 8
  [ArgsSource, ~, ~, ~, Array], # 9
  [Assign, {record: true, targets: 1}, [4, 9], ~, List]]} # 10
```

## A local before a for modifier, read by a call after it

The modifier's loop restores only what it localised; the sub's local stands until the sub returns.

```perl
package C; sub new { bless { cache => {}, bind => undef }, shift }
sub inner { my ($self) = @_; join ",", sort keys(($self->{bind} // {})->%*) }
sub f { my ($self, @args) = @_;
  unless (@args) { my $r = $self->inner; $self->{cache}{n} = $r; return $r }
  local $self->{bind} = { ($self->{bind} // {})->%* };
  $self->{bind}{$_} = 1 for @args;
  my $r = $self->inner; $self->{cache}{n} = $r; return $r }
package main; my $o = C->new; print $o->f(), "|", $o->f(qw(a b)), "|", $o->inner, "\n";
```

```behavior
parses: yes
```

```output
|a,b|
```

```ir
C::f: {start: 0, returns: [49], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 1
  [PadAccess, {sigil: "@", symbol: args}, ~, ~, Array], # 2
  [MemStart], # 3
  [Count, ~, [2], ~, Int, 3], # 4
  [If, ~, [0, 4], 0], # 5
  [Proj, {index: 1}, [5]], # 6
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: inner, package: C, param_names: [], want: scalar}, [1], 6, Str, 3, true], # 7
  [Constant, {const_type: string, value: bind}, ~, ~, Str], # 8
  [Subscript, {kind: hash}, [1, 8], ~, Scalar], # 9
  [Proj, {index: 0}, [5]], # 10
  [Subscript, {kind: hash}, [1, 8], 10, Scalar, 3, true], # 11
  [Defined, ~, [11], ~, Boolean], # 12
  [If, ~, [11, 12], 11], # 13
  [Proj, {index: 1}, [13]], # 14
  [HashLiteral, ~, ~, 14, HashRef], # 15
  [DefinedOr, ~, [11, 15], ~, Scalar], # 16
  [Proj, {index: 0}, [13]], # 17
  [Region, {head: 13}, [17, 15]], # 18
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 5, package: C, sigil: "%", strict: false}, [16], 18, Hash, 11, true], # 19
  [HashLiteral, ~, [19], 19, HashRef], # 20
  [Assign, {local: true}, [9, 20], 20, HashRef, 19, true], # 21
  [Loop, {bound: entry}, [21], 21], # 22
  [Proj, {index: 1}, [22]], # 23
  [Region, {head: 22}, [23]], # 24
  [Phi, {memory: true, region: 22}, [21, 65], ~, Scalar], # 25
  [Phi, {memory: true, region: 24}, [25], ~, Scalar], # 26
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: inner, package: C, param_names: [], want: scalar}, [1], 24, Str, 26, true], # 27
  [Constant, {const_type: string, value: cache}, ~, ~, Str], # 28
  [Subscript, {kind: hash}, [1, 28], 7, Scalar, 7], # 29
  [HashLiteral, ~, ~, 29, HashRef], # 30
  [DefinedOr, ~, [29, 30], ~, Scalar], # 31
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 32
  [Subscript, {kind: hash}, [31, 32], ~, Scalar], # 33
  [Subscript, {kind: hash}, [1, 28], ~, Scalar], # 34
  [Assign, ~, [34, 31], 30, Scalar, 7, true], # 35
  [Assign, ~, [33, 7], 35, Str, 35, true], # 36
  [Subscript, {kind: hash}, [1, 8], ~, Scalar, 19], # 37
  [Exists, {kind: hash}, [1, 8], ~, Boolean, 19], # 38
  [Subscript, {kind: hash}, [1, 28], 27, Scalar, 27], # 39
  [HashLiteral, ~, ~, 39, HashRef], # 40
  [DefinedOr, ~, [39, 40], ~, Scalar], # 41
  [Subscript, {kind: hash}, [41, 32], ~, Scalar], # 42
  [Assign, ~, [34, 41], 40, Scalar, 27, true], # 43
  [Assign, ~, [42, 27], 43, Str, 43, true], # 44
  [ElemRestore, {at_return: 1, kind: hash}, [1, 8, 37, 38], 44, Unknown, 44, true], # 45
  [Region, {head: 5}, [36, 45]], # 46
  [Phi, {predecessors: [6, 10], region: 46}, [7, 27], ~, Str], # 47
  [Phi, {exits: true, memory: true, predecessors: [6, 10], region: 46}, [36, 45], ~, Unknown], # 48
  [Return, ~, [47], 46, ~, 48], # 49
  [ArgsSource, ~, ~, ~, Array], # 50
  [Assign, {record: true, targets: 2}, [1, 2, 50], ~, List], # 51
  [Count, ~, [2], ~, Int, 21], # 52
  [Count, ~, [2], ~, Int, 25], # 53
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 54
  [Phi, {region: 22}, [54, 66], ~, Int], # 55
  [Subscript, {kind: array}, [2, 55], ~, Scalar, 25], # 56
  [Proj, {index: 0}, [22]], # 57
  [Subscript, {kind: hash}, [1, 8], 57, Scalar, 25], # 58
  [NumGt, ~, [53, 55], 22, Boolean], # 59
  [HashLiteral, ~, ~, 58, HashRef], # 60
  [DefinedOr, ~, [58, 60], ~, Scalar], # 61
  [Subscript, {kind: hash}, [61, 56], ~, Scalar], # 62
  [Assign, ~, [9, 61], 60, Scalar, 25, true], # 63
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 64
  [Assign, ~, [62, 64], 63, Int, 63, true], # 65
  [Add, ~, [55, 64], ~, Int]]} # 66
C::inner: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: bind}, ~, ~, Str], # 3
  [MemStart], # 4
  [Subscript, {kind: hash}, [2, 3], 0, Scalar, 4, true], # 5
  [Defined, ~, [5], ~, Boolean], # 6
  [If, ~, [5, 6], 5], # 7
  [Proj, {index: 1}, [7]], # 8
  [HashLiteral, ~, ~, 8, HashRef], # 9
  [DefinedOr, ~, [5, 9], ~, Scalar], # 10
  [Proj, {index: 0}, [7]], # 11
  [Region, {head: 7}, [11, 9]], # 12
  [PostfixDeref, {sigil: "%"}, [10], 12, Hash, 5, true], # 13
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [13], ~, List, 13], # 14
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [14], ~, List, 13], # 15
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 15], ~, Str, 13], # 16
  [Return, {implicit: true}, [16], 13, ~, 13], # 17
  [ArgsSource, ~, ~, ~, Array], # 18
  [Assign, {record: true, targets: 1}, [2, 18], ~, List]]} # 19
C::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: cache}, ~, ~, Str], # 1
  [HashLiteral, ~, ~, 0, HashRef], # 2
  [Constant, {const_type: string, value: bind}, ~, ~, Str], # 3
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 4
  [HashLiteral, ~, [1, 2, 3, 4], 2, HashRef], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [MemStart], # 7
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [6], 5, Scalar, 7, true], # 8
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [5, 8], 8, Unknown, 8, true], # 9
  [Return, {implicit: true}, [9], 9, ~, 9]]} # 10
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: C}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: new, package: main, param_names: [], want: scalar}, [2], 0, Object, 3, true], # 4
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: f, package: main, param_names: [], want: list}, [4], 4, Str, 4, true], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 9
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: f, package: main, param_names: [], want: list}, [4, 8, 9], 5, Str, 5, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: inner, package: main, param_names: [], want: list}, [4], 10, Str, 10, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [6, 7, 11, 7, 13, 14], 12, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 12]]} # 16
```

## A labelled last out of a nested loop over a body array

A count nothing reads is not bound after the outer loop, where the body's array does not exist.

```perl
package N { sub new { my ($c, @in) = @_; bless { in => [@in] }, $c } sub inputs { $_[0]{in} } }
package C { sub new { bless { memo => {} }, shift }
sub f { my ($self, $node) = @_; my $r = 0; $self->{memo}{"$node"} = 0;
  INPUT: for my $input ($node->inputs()->@*) { my @flat = (ref($input) eq 'ARRAY') ? $input->@* : ($input);
    for my $el (@flat) { next unless defined $el && ref $el; if ($self->f($el)) { $r = 1; last INPUT } } }
  return $self->{memo}{"$node"} = $r || 1 } }
print C->new->f(N->new(1, [2, 3])), C->new->f(N->new(1, [2, N->new])), "\n";
```

```behavior
parses: yes
```

```output
11
```

```ir
C::f: {start: 0, returns: [68], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [PadAccess, {sigil: $, symbol: node}, ~, ~, Unknown], # 3
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 4
  [Constant, {const_type: string, value: memo}, ~, ~, Str], # 5
  [MemStart], # 6
  [Subscript, {kind: hash}, [4, 5], 0, Scalar, 6], # 7
  [HashLiteral, ~, ~, 7, HashRef], # 8
  [DefinedOr, ~, [7, 8], ~, Scalar], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 10
  [Subscript, {kind: hash}, [9, 10], ~, Scalar], # 11
  [Subscript, {kind: hash}, [4, 5], ~, Scalar], # 12
  [Assign, ~, [12, 9], 8, Scalar, 6, true], # 13
  [Assign, ~, [11, 1], 13, Int, 13, true], # 14
  [Call, {dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: inputs, package: C, param_names: [], want: scalar}, [3], 14, Unknown, 14, true], # 15
  [Loop, {bound: entry}, [15], 15], # 16
  [Proj, {index: 1}, [16]], # 17
  [Phi, {memory: true, region: 16}, [15, 85], ~, Unknown], # 18
  [PostfixDeref, {sigil: "@"}, [15], ~, Array, 15], # 19
  [Phi, {region: 16}, [1, 72], ~, Int], # 20
  [Proj, {index: 0}, [16]], # 21
  [Exists, {kind: array}, [19, 20], 21, Boolean, 18], # 22
  [Subscript, {kind: array}, [19, 20], ~, Scalar], # 23
  [Ref, ~, [23], ~, ScalarRef], # 24
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 25
  [TernaryExpr, ~, [22, 24, 25], 22, "Maybe[ScalarRef]"], # 26
  [PostfixDeref, {sigil: $}, [26], ~, Scalar, 18], # 27
  [Subscript, {kind: array}, [19, 20], ~, Scalar, 18], # 28
  [TernaryExpr, ~, [22, 27, 28], 26, Scalar], # 29
  [RefType, ~, [29], ~, Str, 18], # 30
  [Constant, {const_type: string, value: ARRAY}, ~, ~, Str], # 31
  [StrEq, ~, [30, 31], ~, Boolean], # 32
  [PostfixDeref, {sigil: $}, [26], ~, Scalar, 18], # 33
  [Subscript, {kind: array}, [19, 20], ~, Scalar, 18], # 34
  [TernaryExpr, ~, [22, 33, 34], ~, Scalar], # 35
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 4, package: C, sigil: "@", strict: false}, [35], ~, Array, 18], # 36
  [PostfixDeref, {sigil: $}, [26], ~, Scalar, 18], # 37
  [Subscript, {kind: array}, [19, 20], ~, Scalar, 18], # 38
  [TernaryExpr, ~, [22, 37, 38], ~, Scalar], # 39
  [TernaryExpr, ~, [32, 36, 39], ~, List], # 40
  [ArrayLiteral, {sigil: "@", symbol: flat}, [40], 29, Array], # 41
  [Loop, {bound: entry}, [41], 41], # 42
  [Phi, {memory: true, region: 42}, [18, 88], ~, Unknown], # 43
  [PadAccess, {sigil: $, symbol: el}, ~, ~, Unknown, 43], # 44
  [Phi, {region: 42}, [1, 71], ~, Int], # 45
  [Subscript, {kind: array}, [41, 45], ~, Scalar, 43], # 46
  [Proj, {index: 0}, [42]], # 47
  [Assign, ~, [44, 46], 47, Scalar, 43, true], # 48
  [PadAccess, {sigil: $, symbol: el}, ~, ~, Unknown, 48], # 49
  [Defined, ~, [49], ~, Boolean], # 50
  [RefType, ~, [49], ~, Str, 48], # 51
  [And, ~, [50, 51], ~, Scalar], # 52
  [If, ~, [48, 52], 48], # 53
  [Proj, {index: 0}, [53]], # 54
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: f, package: C, param_names: [], want: scalar}, [4, 49], 54, Int, 48, true], # 55
  [If, ~, [55, 55], 55], # 56
  [Proj, {index: 0}, [56]], # 57
  [Region, {head: 16}, [17, 57]], # 58
  [Phi, {region: 58}, [1, 2], ~, Int], # 59
  [Or, ~, [59, 2], ~, Int], # 60
  [Phi, {memory: true, region: 58}, [18, 55], ~, Unknown], # 61
  [Subscript, {kind: hash}, [4, 5], 58, Scalar, 61], # 62
  [HashLiteral, ~, ~, 62, HashRef], # 63
  [DefinedOr, ~, [62, 63], ~, Scalar], # 64
  [Subscript, {kind: hash}, [64, 10], ~, Scalar], # 65
  [Assign, ~, [12, 64], 63, Scalar, 61, true], # 66
  [Assign, ~, [65, 60], 66, Int, 66, true], # 67
  [Return, ~, [60], 67, ~, 67], # 68
  [ArgsSource, ~, ~, ~, Array], # 69
  [Assign, {record: true, targets: 2}, [4, 3, 69], ~, List], # 70
  [Add, ~, [45, 2], ~, Int], # 71
  [Add, ~, [20, 2], ~, Int], # 72
  [Proj, {index: 1}, [53]], # 73
  [Proj, {index: 1}, [56]], # 74
  [Region, {head: 53}, [73, 74]], # 75
  [Phi, {memory: true, predecessors: [73, 54], region: 75}, [48, 55], ~, Scalar], # 76
  [PadAccess, {sigil: $, symbol: el}, ~, ~, Unknown, 76], # 77
  [Count, ~, [19], ~, Int, 18], # 78
  [NumGt, ~, [78, 20], 16, Boolean], # 79
  [Count, ~, [41], ~, Int, 43], # 80
  [NumGt, ~, [80, 45], 42, Boolean], # 81
  [Subscript, {kind: array}, [41, 45], ~, Scalar], # 82
  [Proj, {index: 1}, [42]], # 83
  [Region, {head: 42}, [83]], # 84
  [Phi, {memory: true, region: 84}, [43], ~, Unknown], # 85
  [Count, ~, [41], ~, Int, 18], # 86
  [Count, ~, [19], ~, Int, 15], # 87
  [Assign, {if_changed: true}, [82, 77], 75, Unknown, 76, true]]} # 88
C::new: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: memo}, ~, ~, Str], # 1
  [HashLiteral, ~, ~, 0, HashRef], # 2
  [HashLiteral, ~, [1, 2], 2, HashRef], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [4], 3, Scalar, 5, true], # 6
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [3, 6], 6, Unknown, 6, true], # 7
  [Return, {implicit: true}, [7], 7, ~, 7]]} # 8
N::inputs: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: in}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4], 0, Scalar, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
N::new: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: in}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: in}, ~, ~, Unknown], # 2
  [ArrayLiteral, ~, [2], 0, ArrayRef], # 3
  [HashLiteral, ~, [1, 3], 3, HashRef], # 4
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 5
  [MemStart], # 6
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [4, 5], 4, Unknown, 6, true], # 7
  [Return, {implicit: true}, [7], 7, ~, 7], # 8
  [ArgsSource, ~, ~, ~, Array], # 9
  [Assign, {record: true, targets: 2}, [5, 2, 9], ~, List]]} # 10
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: C}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [], want: scalar}, [2], 0, Object, 3, true], # 4
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [ArrayLiteral, ~, [7, 8], 4, ArrayRef], # 9
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [], want: list}, [5, 6, 9], 9, Object, 4, true], # 10
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: f, package: main, param_names: [], want: list}, [4, 10], 10, Int, 10, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [], want: scalar}, [2], 11, Object, 11, true], # 13
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [], want: list}, [5], 13, Object, 13, true], # 14
  [ArrayLiteral, ~, [7, 14], 14, ArrayRef], # 15
  [Call, {class_name: "N", dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: new, package: main, param_names: [], want: list}, [5, 6, 15], 15, Object, 14, true], # 16
  [Call, {class_name: C, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: f, package: main, param_names: [], want: list}, [13, 16], 16, Int, 16, true], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Print, ~, [12, 18, 19], 17, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 17]]} # 21
```

## A list assign from a match

A match in list context yields its captures, or nothing when it fails; one target keeps its parens.

```perl
sub f { my ($n) = @_; my ($c, $s) = ($n // "") =~ /^(.*)::([^:]+)$/; return defined $c ? "$c $s" : "none" }
my ($w) = "abc" =~ /b/; my ($x) = "abc" =~ /z/;
print f("A::b"), "|", f("q"), "|", $w, defined $x ? "d" : "u", "\n";
```

```behavior
parses: yes
```

```output
A b|none|1u
```

```ir
main::__PROGRAM__: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: A::b}, ~, ~, Str], # 2
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown], # 3
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 4
  [RegexMatch, {flags: "", pattern: z}, [4], ~, Boolean], # 5
  [PadAccess, {sigil: $, symbol: w}, ~, ~, Str], # 6
  [RegexMatch, {flags: "", pattern: b}, [4], ~, Boolean], # 7
  [MemStart], # 8
  [Assign, {targets: 1}, [6, 7], 0, Boolean, 8, true], # 9
  [Assign, {targets: 1}, [3, 5], 9, Boolean, 9, true], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [2], 10, Str, 10, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: q}, ~, ~, Str], # 14
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, [14], 11, Str, 11, true], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 17
  [Defined, ~, [3], ~, Boolean], # 18
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 19
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 20
  [TernaryExpr, ~, [18, 19, 20], ~, Str], # 21
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 22
  [Print, ~, [12, 13, 16, 13, 17, 21, 22], 15, "Maybe[Boolean]"], # 23
  [Return, {implicit: true}, [1], 23, ~, 15]]} # 24
main::f: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Str], # 1
  [Defined, ~, [1], ~, Boolean], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 3
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Concat, ~, [5, 7], ~, Str], # 8
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 9
  [TernaryExpr, ~, [2, 8, 9], ~, Str], # 10
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 11
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 12
  [DefinedOr, ~, [11, 12], ~, Unknown], # 13
  [RegexMatch, {flags: "", pattern: "^(.*)::([^:]+)$"}, [13], ~, Boolean], # 14
  [MemStart], # 15
  [Assign, {targets: 2}, [1, 6, 14], 0, List, 15, true], # 16
  [Return, ~, [10], 16, ~, 16], # 17
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 18
  [TernaryExpr, ~, [2, 8, 18], ~, "Maybe[Str]"], # 19
  [ArgsSource, ~, ~, ~, Array], # 20
  [Assign, {record: true, targets: 1}, [11, 20], ~, List]]} # 21
```

## Values read after a delete, before a store

The list is read into a temporary where it stands, after the delete and before the store.

```perl
my %h = (a => 1, c => 3); delete $h{c}; my @v = sort values %h; $h{d} = 4; print "@v ", scalar(keys %h), "\n";
```

```behavior
parses: yes
```

```output
1 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 5
  [HashLiteral, {sigil: "%", symbol: h}, [2, 3, 4, 5], ~, Hash], # 6
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 7
  [Subscript, {kind: hash}, [6, 7], ~, Undef], # 8
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 9
  [MemStart], # 10
  [Delete, {kind: hash}, [6, 4], 0, Scalar, 10, true], # 11
  [Assign, ~, [8, 9], 11, Int, 11, true], # 12
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 12], # 13
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 14
  [Call, {dispatch_kind: builtin, name: values, param_names: [], want: list}, [6], ~, List, 11], # 15
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [15], ~, List, 11], # 16
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [14, 16], ~, Str, 12], # 17
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: scalar}, [6], ~, Int, 12], # 20
  [Coerce, {from_repr: Int, to_repr: Str}, [20], ~, Str], # 21
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 22
  [Print, ~, [19, 21, 22], 12, "Maybe[Boolean]"], # 23
  [Return, {implicit: true}, [1], 23, ~, 12]]} # 24
```

## A do block yields its last statement

An earlier statement's leftover is no part of the value; a map over a shared array reads each element as a hash.

```perl
my @F = ({name => "a"}, {name => "b"}); sub ff { return @F }
my %I = do { my $i = 0; map { $_->{name} => $i++ } @F }; sub ix { $I{$_[0]} }
print ix("a"), ix("b"), scalar(ff()), "\n";
```

```behavior
parses: yes
```

```output
012
```

```ir
main::__PROGRAM__: {start: 0, returns: [29], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: F}, ~, ~, Array, 3], # 4
  [Constant, {const_type: string, value: name}, ~, ~, Str], # 5
  [HashLiteral, ~, [5, 2], 0, HashRef], # 6
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 7
  [HashLiteral, ~, [5, 7], 6, HashRef], # 8
  [ArrayLiteral, {sigil: "@", symbol: F}, [6, 8], 8, Array], # 9
  [Assign, ~, [4, 9], 9, List, 3, true], # 10
  [Loop, {bound: entry}, [10], 10], # 11
  [Phi, {memory: true, region: 11}, [10, 36], ~, List], # 12
  [Proj, {index: 1}, [11]], # 13
  [Region, {head: 11}, [13]], # 14
  [Phi, {memory: true, region: 14}, [12], ~, List], # 15
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: I}, ~, ~, Hash, 15], # 16
  [ArrayLiteral, ~, ~, ~, Array], # 17
  [Phi, {region: 11}, [17, 38], ~, Array], # 18
  [HashLiteral, {sigil: "%", symbol: I}, [18], 14, Hash], # 19
  [Assign, ~, [16, 19], 19, List, 15, true], # 20
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::ix, package: main, param_names: [], want: list}, [2], 20, Scalar, 20, true], # 21
  [Coerce, {from_repr: Unknown, to_repr: Str}, [21], ~, Str], # 22
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::ix, package: main, param_names: [], want: list}, [7], 21, Scalar, 21, true], # 23
  [Coerce, {from_repr: Unknown, to_repr: Str}, [23], ~, Str], # 24
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::ff, package: main, param_names: [], want: scalar}, ~, 23, Array, 23, true], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 26
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 27
  [Print, ~, [22, 24, 26, 27], 25, "Maybe[Boolean]"], # 28
  [Return, {implicit: true}, [1], 28, ~, 25], # 29
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: F}, ~, ~, Array], # 30
  [ArrayLiteral, ~, [30], ~, List], # 31
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 32
  [Phi, {region: 11}, [32, 43], ~, Int], # 33
  [Subscript, {kind: array}, [31, 33], ~, Scalar, 12], # 34
  [Proj, {index: 0}, [11]], # 35
  [Subscript, {kind: hash}, [34, 5], 35, Scalar, 12, true], # 36
  [Phi, {region: 11}, [32, 44], ~, Int], # 37
  [ListAppend, {collector: map}, [18, 36, 37], ~, Array], # 38
  [Count, ~, [31], ~, Int, 10], # 39
  [Count, ~, [31], ~, Int, 12], # 40
  [NumGt, ~, [40, 33], 11, Boolean], # 41
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 42
  [Add, ~, [33, 42], ~, Int], # 43
  [Add, ~, [37, 42], ~, Int], # 44
  [ArrayLiteral, ~, [30], ~, List]]} # 45
main::ff: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: F}, ~, ~, Array], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
main::ix: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: I}, ~, ~, Hash], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Subscript, {kind: hash}, [1, 5], ~, Scalar, 4], # 6
  [Return, {implicit: true}, [6], 0, ~, 4]]} # 7
```

## A length under use bytes

A do block holding `use bytes` counts octets; the pragma is part of the length, not of the block.

```perl
my $s = "\x{e9}"; utf8::upgrade($s);
print length($s), " ", do { use bytes; length($s) }, "\n";
```

```behavior
parses: yes
```

```output
1 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 2], # 3
  [Constant, {const_type: string, value: "\u00e9"}, ~, ~, Str], # 4
  [Assign, ~, [3, 4], 0, Str, 2, true], # 5
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown, 5], # 6
  [Call, {dispatch_kind: direct, external: true, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: utf8::upgrade, package: main, param_names: [], want: void, xs: true}, [6], 5, Unknown, 5, true], # 7
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Str, 7], # 8
  [Length, ~, [8], ~, Int], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [Length, {bytes: 1}, [8], ~, Int], # 12
  [Coerce, {from_repr: Int, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [10, 11, 13, 14], 7, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 7]]} # 16
"BEGIN 1": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: bytes}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: bytes.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2], 0, Unknown, 3, true], # 4
  [Call, {class_name: bytes, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: import, package: main, param_names: []}, [1], 4, Unknown, 4, true], # 5
  [Return, {implicit: true}, [5], 5, ~, 5]]} # 6
```

## A count through an element before a push

A count of an array reached through a hash element is taken where it is read, not after a later push into the same array.

```perl
sub f { my ($self, $t) = @_; my $g = scalar @{ $self->{s} }; push $self->{s}->@*, $t; return "x$g" }
my $o = { s => [] }; print f($o, "a"), f($o, "b"), "\n";
```

```behavior
parses: yes
```

```output
x0x1
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: o}, ~, ~, Unknown, 2], # 3
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 4
  [ArrayLiteral, ~, ~, 0, ArrayRef], # 5
  [HashLiteral, ~, [4, 5], 5, HashRef], # 6
  [Assign, ~, [3, 6], 6, HashRef, 2, true], # 7
  [PadAccess, {sigil: $, symbol: o}, ~, ~, Unknown, 7], # 8
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [8, 9], 7, Str, 7, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [PadAccess, {sigil: $, symbol: o}, ~, ~, Unknown, 10], # 12
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::f, package: main, param_names: [], want: list}, [12, 13], 10, Str, 10, true], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Print, ~, [11, 15, 16], 14, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [1], 17, ~, 14]]} # 18
main::f: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 3
  [MemStart], # 4
  [Subscript, {kind: hash}, [2, 3], 0, Scalar, 4, true], # 5
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 1, package: main, sigil: "@", strict: false}, [5], 5, Array, 5, true], # 6
  [Count, ~, [6], ~, Int, 6], # 7
  [Coerce, {from_repr: Int, to_repr: Str}, [7], ~, Str], # 8
  [Concat, ~, [1, 8], ~, Str], # 9
  [Subscript, {kind: hash}, [2, 3], 6, Scalar, 6], # 10
  [ArrayLiteral, ~, ~, 10, ArrayRef], # 11
  [DefinedOr, ~, [10, 11], ~, Scalar], # 12
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 13
  [Assign, ~, [13, 12], 11, Scalar, 6, true], # 14
  [PostfixDeref, {sigil: "@"}, [12], ~, Array, 14], # 15
  [PadAccess, {sigil: $, symbol: t}, ~, ~, Unknown], # 16
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [15, 16], 14, Int, 14, true], # 17
  [Return, ~, [9], 17, ~, 17], # 18
  [ArgsSource, ~, ~, ~, Array], # 19
  [Assign, {record: true, targets: 2}, [2, 16, 19], ~, List]]} # 20
```

## A grep calling a method over an array a sort filled

The array holds the sorted list; a method call in the grep body does not make the sort result a reference.

```perl
use v5.42; use experimental "class";
class K { method isn($x) { $x =~ /a/ }
  method f(@g) { my @r = sort @g; my @n = grep { $self->isn($_) } @r; return "@n" } }
print K->new->f(qw(ba x aa)), "\n";
```

```behavior
parses: yes
```

```output
aa ba
```

```ir
K::f: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {memory: true, region: 2}, [1, 25], ~, Unknown], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Phi, {memory: true, region: 5}, [3], ~, Unknown], # 6
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 6], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [7], ~, Str], # 8
  [ArrayLiteral, ~, ~, ~, Array], # 9
  [Phi, {region: 2}, [9, 26], ~, Array], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [8, 10], ~, Str, 6], # 11
  [Return, ~, [11], 5, ~, 6], # 12
  [Parameter, {index: 0, name: "@g", sigil: "@"}, ~, ~, Array], # 13
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [13], ~, List, 1], # 14
  [Count, ~, [14], ~, Int, 3], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Phi, {region: 2}, [16, 28], ~, Int], # 17
  [NumGt, ~, [15, 17], 2, Boolean], # 18
  [Proj, {index: 0}, [2]], # 19
  [Subscript, {kind: array}, [14, 17], ~, Scalar], # 20
  [Ref, ~, [20], ~, ScalarRef], # 21
  [LocalAlias, {name: _}, [21], 19, Unknown, 3], # 22
  [Subscript, {kind: array}, [14, 17], ~, Scalar, 3], # 23
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 24
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: isn, package: K, param_names: [], want: scalar}, [24, 23], 22, Boolean, 3, true], # 25
  [ListAppend, {collector: grep}, [10, 23, 25], ~, Array], # 26
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 27
  [Add, ~, [17, 27], ~, Int], # 28
  [Count, ~, [14], ~, Int, 1]]} # 29
K::isn: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Str], # 1
  [RegexMatch, {flags: u, pattern: a}, [1], ~, Boolean], # 2
  [MemStart], # 3
  [Return, {implicit: true}, [2], 0, ~, 3]]} # 4
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: new, package: main, param_names: [], want: scalar}, ~, 0, Object, 2, true], # 3
  [Constant, {const_type: string, value: ba}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: aa}, ~, ~, Str], # 6
  [Call, {class_name: K, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: f, package: main, param_names: [], want: list}, [3, 4, 5, 6], 3, Str, 3, true], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [8, 9], 7, "Maybe[Boolean]"], # 10
  [Return, {implicit: true}, [1], 10, ~, 7]]} # 11
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: experimental, dispatch_kind: method, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```

## An element read through a reference before a call passed the reference

A sub handed the hash reference may store into it; the element read before the call keeps the value it read.

```perl
my %v = (a => {n => "x"}, b => {n => "y"}); sub vars { \%v } sub emit { my $h = $_[0]; $h->{n} = "z"; "e" }
sub f { my @l; for my $k (sort keys vars()->%*) { my $info = vars()->{$k}; my $s = $info->{n}; my $e = emit($info); push @l, "$s=$e" } "@l" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
x=e y=e
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: v}, ~, ~, Hash, 2], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 6
  [HashLiteral, ~, [5, 6], 0, HashRef], # 7
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 9
  [HashLiteral, ~, [5, 9], 7, HashRef], # 10
  [HashLiteral, {sigil: "%", symbol: v}, [4, 7, 8, 10], 10, Hash], # 11
  [Assign, ~, [3, 11], 11, List, 2, true], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 12, Str, 12, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [14, 15], 13, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 13]]} # 17
main::emit: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: e}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3], ~, Scalar, 4], # 5
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 6
  [Subscript, {kind: hash}, [5, 6], ~, Scalar], # 7
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 8
  [Assign, ~, [7, 8], 0, Str, 4, true], # 9
  [Return, {implicit: true}, [1], 9, ~, 9]]} # 10
main::f: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::vars, package: main, param_names: [], want: scalar}, ~, 0, HashRef, 1, true], # 2
  [PostfixDeref, {sigil: "%"}, [2], 2, Hash, 2, true], # 3
  [Loop, {bound: entry}, [3], 3], # 4
  [Phi, {memory: true, region: 4}, [3, 38], ~, List], # 5
  [Proj, {index: 1}, [4]], # 6
  [Region, {head: 4}, [6]], # 7
  [Phi, {memory: true, region: 7}, [5], ~, List], # 8
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 8], # 9
  [Coerce, {from_repr: Scalar, to_repr: Str}, [9], ~, Str], # 10
  [PadAccess, {sigil: "@", symbol: l}, ~, ~, Array], # 11
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [10, 11], ~, Str, 8], # 12
  [Return, {implicit: true}, [12], 7, ~, 8], # 13
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [3], ~, List, 3], # 14
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [14], ~, List, 3], # 15
  [ArrayLiteral, ~, [15], ~, Array], # 16
  [Count, ~, [16], ~, Int, 3], # 17
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 18
  [Phi, {region: 4}, [18, 43], ~, Int], # 19
  [Subscript, {kind: array}, [16, 19], ~, Scalar], # 20
  [Proj, {index: 0}, [4]], # 21
  [Ref, ~, [20], 21, ScalarRef, 5], # 22
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::vars, package: main, param_names: [], want: scalar}, ~, 22, HashRef, 5, true], # 23
  [PostfixDeref, {sigil: $}, [22], 23, Scalar, 23], # 24
  [Subscript, {kind: hash}, [23, 24], 24, Scalar, 23, true], # 25
  [PadAccess, {sigil: $, symbol: info}, ~, ~, Unknown, 25], # 26
  [Assign, ~, [26, 25], 25, Scalar, 25, true], # 27
  [PadAccess, {sigil: $, symbol: info}, ~, ~, Unknown, 27], # 28
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 29
  [Subscript, {kind: hash}, [28, 29], 27, Scalar, 27, true], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [30], ~, Str], # 31
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 32
  [Concat, ~, [31, 32], ~, Str], # 33
  [PadAccess, {sigil: $, symbol: info}, ~, ~, Unknown, 30], # 34
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::emit, package: main, param_names: [], want: scalar}, [34], 30, Str, 30, true], # 35
  [Coerce, {from_repr: Unknown, to_repr: Str}, [35], ~, Str], # 36
  [Concat, ~, [33, 36], ~, Str], # 37
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [11, 37], 35, Int, 35, true], # 38
  [Count, ~, [16], ~, Int, 5], # 39
  [NumGt, ~, [39, 19], 4, Boolean], # 40
  [Subscript, {kind: array}, [16, 19], ~, Scalar, 23], # 41
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 42
  [Add, ~, [19, 42], ~, Int]]} # 43
main::vars: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: v}, ~, ~, Hash], # 1
  [Ref, ~, [1], ~, HashRef], # 2
  [MemStart], # 3
  [Return, {implicit: true}, [2], 0, ~, 3]]} # 4
```

## An element read before a call, used in an arm after it

The read comes before the call though its only use is guarded by a test after the call.

```perl
my %v = (a => {n => "x"}, b => {n => "y"}); sub vars { \%v } sub emit { my $h = $_[0]; $h->{n} = "z"; $_[1] }
sub f { my @l; for my $k (sort keys vars()->%*) { my $info = vars()->{$k}; my $s = $info->{n}; my $e = emit($info, $k eq "a" ? 1 : undef); push @l, "$s=$e" if defined $e } "@l" }
print f(), "\n";
```

```behavior
parses: yes
```

```output
x=1
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: v}, ~, ~, Hash, 2], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 6
  [HashLiteral, ~, [5, 6], 0, HashRef], # 7
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 9
  [HashLiteral, ~, [5, 9], 7, HashRef], # 10
  [HashLiteral, {sigil: "%", symbol: v}, [4, 7, 8, 10], 10, Hash], # 11
  [Assign, ~, [3, 11], 11, List, 2, true], # 12
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::f, package: main, param_names: [], want: list}, ~, 12, Str, 12, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [14, 15], 13, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 13]]} # 17
main::emit: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [1, 3], ~, Scalar, 4], # 5
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 6
  [Subscript, {kind: hash}, [5, 6], ~, Scalar], # 7
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 8
  [Assign, ~, [7, 8], 0, Str, 4, true], # 9
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 9], # 10
  [Return, {implicit: true}, [10], 9, ~, 9]]} # 11
main::f: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::vars, package: main, param_names: [], want: scalar}, ~, 0, HashRef, 1, true], # 2
  [PostfixDeref, {sigil: "%"}, [2], 2, Hash, 2, true], # 3
  [Loop, {bound: entry}, [3], 3], # 4
  [Phi, {memory: true, region: 4}, [3, 51], ~, List], # 5
  [Proj, {index: 1}, [4]], # 6
  [Region, {head: 4}, [6]], # 7
  [Phi, {memory: true, region: 7}, [5], ~, List], # 8
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 8], # 9
  [Coerce, {from_repr: Scalar, to_repr: Str}, [9], ~, Str], # 10
  [PadAccess, {sigil: "@", symbol: l}, ~, ~, Array], # 11
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [10, 11], ~, Str, 8], # 12
  [Return, {implicit: true}, [12], 7, ~, 8], # 13
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [3], ~, List, 3], # 14
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [14], ~, List, 3], # 15
  [ArrayLiteral, ~, [15], ~, Array], # 16
  [Count, ~, [16], ~, Int, 3], # 17
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 18
  [Phi, {region: 4}, [18, 56], ~, Int], # 19
  [Subscript, {kind: array}, [16, 19], ~, Scalar], # 20
  [Proj, {index: 0}, [4]], # 21
  [Ref, ~, [20], 21, ScalarRef, 5], # 22
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::vars, package: main, param_names: [], want: scalar}, ~, 22, HashRef, 5, true], # 23
  [PostfixDeref, {sigil: $}, [22], 23, Scalar, 23], # 24
  [Subscript, {kind: hash}, [23, 24], 24, Scalar, 23, true], # 25
  [PadAccess, {sigil: $, symbol: info}, ~, ~, Unknown, 25], # 26
  [Assign, ~, [26, 25], 25, Scalar, 25, true], # 27
  [PadAccess, {sigil: $, symbol: info}, ~, ~, Unknown, 27], # 28
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 29
  [Subscript, {kind: hash}, [28, 29], 27, Scalar, 27, true], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [30], ~, Str], # 31
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 32
  [Concat, ~, [31, 32], ~, Str], # 33
  [PadAccess, {sigil: $, symbol: info}, ~, ~, Unknown, 30], # 34
  [PostfixDeref, {sigil: $}, [22], 30, Scalar, 30], # 35
  [Coerce, {from_repr: Scalar, to_repr: Str}, [35], ~, Str], # 36
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 37
  [StrEq, ~, [36, 37], ~, Boolean], # 38
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 39
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 40
  [TernaryExpr, ~, [38, 39, 40], ~, "Maybe[Int]"], # 41
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::emit, package: main, param_names: [], want: scalar}, [34, 41], 35, Scalar, 30, true], # 42
  [Coerce, {from_repr: Unknown, to_repr: Str}, [42], ~, Str], # 43
  [Concat, ~, [33, 43], ~, Str], # 44
  [Defined, ~, [42], ~, Boolean], # 45
  [If, ~, [42, 45], 42], # 46
  [Proj, {index: 0}, [46]], # 47
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [11, 44], 47, Int, 42, true], # 48
  [Proj, {index: 1}, [46]], # 49
  [Region, {head: 46}, [48, 49]], # 50
  [Phi, {memory: true, predecessors: [47, 49], region: 50}, [48, 42], ~, Scalar], # 51
  [Count, ~, [16], ~, Int, 5], # 52
  [NumGt, ~, [52, 19], 4, Boolean], # 53
  [Subscript, {kind: array}, [16, 19], ~, Scalar, 23], # 54
  [Subscript, {kind: array}, [16, 19], ~, Scalar, 30], # 55
  [Add, ~, [19, 39], ~, Int]]} # 56
main::vars: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [PadAccess, {file: 1, shared: 1, sigil: "%", symbol: v}, ~, ~, Hash], # 1
  [Ref, ~, [1], ~, HashRef], # 2
  [MemStart], # 3
  [Return, {implicit: true}, [2], 0, ~, 3]]} # 4
```

## An element of a named array read before a call handed a reference to it

The call writes the array through the reference; the element read before the call keeps the value it read.

```perl
sub w { $_[0][$_[1]] = "z"; 1 } sub f { my @a = qw(a b c); my $s = ""; my $i = 0; while ($i < 2) { my $v = $a[$i + 1]; if ($v ne "q") { w(\@a, $i + 1) } $s .= $v; $i++ } "$s @a" } print f(), "\n";
```

```behavior
parses: yes
```

```output
bc a z z
```

```ir
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f, package: main, param_names: [], want: list}, ~, 0, Str, 2, true], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, "Maybe[Boolean]"], # 6
  [Return, {implicit: true}, [1], 6, ~, 3]]} # 7
main::f: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: each}, [0], 0], # 2
  [Phi, {region: 2}, [1, 38], ~, Str], # 3
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [MemStart], # 6
  [Phi, {memory: true, region: 2}, [6, 37], ~, Unknown], # 7
  [Proj, {index: 1}, [2]], # 8
  [Region, {head: 2}, [8]], # 9
  [Phi, {memory: true, region: 9}, [7], ~, Unknown], # 10
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 10], # 11
  [Coerce, {from_repr: Scalar, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 14
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 15
  [ArrayLiteral, {sigil: "@", symbol: a}, [13, 14, 15], ~, Array], # 16
  [PostfixDeref, {sigil: "@"}, [16], ~, Array, 10], # 17
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 17], ~, Str, 10], # 18
  [Concat, ~, [5, 18], ~, Str], # 19
  [Return, {implicit: true}, [19], 9, ~, 10], # 20
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 21
  [Phi, {region: 2}, [21, 27], ~, Int], # 22
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 23
  [NumLt, ~, [22, 23], 2, Boolean], # 24
  [Proj, {index: 0}, [2]], # 25
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 26
  [Add, ~, [22, 26], ~, Int], # 27
  [Subscript, {kind: array}, [16, 27], ~, Str, 7], # 28
  [Constant, {const_type: string, value: q}, ~, ~, Str], # 29
  [StrNe, ~, [28, 29], ~, Boolean], # 30
  [If, ~, [25, 30], 25], # 31
  [Ref, ~, [16], ~, ArrayRef], # 32
  [Proj, {index: 0}, [31]], # 33
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::w, package: main, param_names: [], want: void}, [32, 27], 33, Int, 7, true], # 34
  [Proj, {index: 1}, [31]], # 35
  [Region, {head: 31}, [34, 35]], # 36
  [Phi, {memory: true, predecessors: [33, 35], region: 36}, [34, 7], ~, Unknown], # 37
  [Concat, ~, [3, 28], ~, Str]]} # 38
main::w: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [2, 1], ~, Scalar, 5], # 6
  [Subscript, {kind: array}, [4, 6], ~, Scalar], # 7
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 8
  [Assign, ~, [7, 8], 0, Str, 5, true], # 9
  [Return, {implicit: true}, [1], 9, ~, 9]]} # 10
```

## A hash copied through a reference, then stored through it

The copy holds the values as they were; a store through the source reference after it is not seen.

```perl
sub f { my ($h) = @_; my %p = %$h; $h->{a} = 2; return "$p{a} $h->{a}" } print f({a=>1}), "\n";
```

```behavior
parses: yes
```

```output
1 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [HashLiteral, ~, [2, 3], 0, HashRef], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f, package: main, param_names: [], want: list}, [4], 4, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
main::f: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: h}, ~, ~, Unknown], # 1
  [MemStart], # 2
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 1, package: main, sigil: "%", strict: false}, [1], ~, Hash, 2], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Subscript, {kind: hash}, [1, 4], ~, Scalar], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 1, package: main, sigil: "%", strict: false}, [1], 0, Hash, 2, true], # 7
  [Assign, ~, [5, 6], 7, Int, 7, true], # 8
  [Subscript, {kind: hash}, [3, 4], ~, Scalar, 8], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Subscript, {kind: hash}, [1, 4], 8, Int, 8, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Concat, ~, [12, 14], ~, Str], # 15
  [Return, ~, [15], 13, ~, 13], # 16
  [ArgsSource, ~, ~, ~, Array], # 17
  [Assign, {record: true, targets: 1}, [1, 17], ~, List]]} # 18
```

## An array copied through a reference, then stored through it

The same for an array: the copy keeps the element the store replaced.

```perl
sub f { my ($h) = @_; my @p = @$h; $h->[0] = 2; return "$p[0] $h->[0]" } print f([1]), "\n";
```

```behavior
parses: yes
```

```output
1 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [ArrayLiteral, ~, [2], 0, ArrayRef], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f, package: main, param_names: [], want: list}, [3], 3, Str, 4, true], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, "Maybe[Boolean]"], # 8
  [Return, {implicit: true}, [1], 8, ~, 5]]} # 9
main::f: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: h}, ~, ~, Unknown], # 1
  [MemStart], # 2
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 1, package: main, sigil: "@", strict: false}, [1], ~, Array, 2], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Subscript, {kind: array}, [1, 4], ~, Scalar], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 1, package: main, sigil: "@", strict: false}, [1], 0, Array, 2, true], # 7
  [Assign, ~, [5, 6], 7, Int, 7, true], # 8
  [Subscript, {kind: array}, [3, 4], ~, Scalar, 8], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Subscript, {kind: array}, [1, 4], 8, Int, 8, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Concat, ~, [12, 14], ~, Str], # 15
  [Return, ~, [15], 13, ~, 13], # 16
  [ArgsSource, ~, ~, ~, Array], # 17
  [Assign, {record: true, targets: 1}, [1, 17], ~, List]]} # 18
```

## A copy read in a loop that stores through its source

The copy is taken once, before the loop; the loop stores through the source and keeps reading the copy.

```perl
sub f { my ($h) = @_; my %p = %$h; for my $k (sort keys %p) { my $v = $p{$k}; $h->{$k} = $v + 10; print "$v $p{$k};" } return "" } print f({a=>1, b=>2}), "\n";
```

```behavior
parses: yes
```

```output
1 1;2 2;
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [HashLiteral, ~, [2, 3, 4, 5], 0, HashRef], # 6
  [MemStart], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 1, name: main::f, package: main, param_names: [], want: list}, [6], 6, Str, 7, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
main::f: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: h}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [PostfixDeref, {eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 1, package: main, sigil: "%", strict: false}, [2], 0, Hash, 3, true], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Proj, {index: 1}, [5]], # 6
  [Region, {head: 5}, [6]], # 7
  [Phi, {memory: true, region: 5}, [4, 29], ~, List], # 8
  [Phi, {memory: true, region: 7}, [8], ~, List], # 9
  [Return, ~, [1], 7, ~, 9], # 10
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/mvrHQew3rs/case.pl", line: 1, package: main, sigil: "%", strict: false}, [2], ~, Hash, 3], # 11
  [Call, {dispatch_kind: builtin, name: keys, param_names: [], want: list}, [11], ~, List, 4], # 12
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [12], ~, List, 4], # 13
  [ArrayLiteral, ~, [13], ~, Array], # 14
  [Count, ~, [14], ~, Int, 4], # 15
  [ArgsSource, ~, ~, ~, Array], # 16
  [Assign, {record: true, targets: 1}, [2, 16], ~, List], # 17
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 18
  [Phi, {region: 5}, [18, 40], ~, Int], # 19
  [Subscript, {kind: array}, [14, 19], ~, Scalar, 8], # 20
  [Subscript, {kind: hash}, [2, 20], ~, Scalar], # 21
  [Count, ~, [14], ~, Int, 8], # 22
  [NumGt, ~, [22, 19], 5, Boolean], # 23
  [Proj, {index: 0}, [5]], # 24
  [Subscript, {kind: hash}, [11, 20], ~, Scalar, 8], # 25
  [Coerce, {from_repr: Scalar, to_repr: Num}, [25], ~, Num], # 26
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 27
  [Add, ~, [26, 27], ~, Num], # 28
  [Assign, ~, [21, 28], 24, Num, 8, true], # 29
  [Subscript, {kind: hash}, [11, 20], ~, Scalar, 29], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 31
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 32
  [Concat, ~, [31, 32], ~, Str], # 33
  [Coerce, {from_repr: Unknown, to_repr: Str}, [30], ~, Str], # 34
  [Concat, ~, [33, 34], ~, Str], # 35
  [Constant, {const_type: string, value: ";"}, ~, ~, Str], # 36
  [Concat, ~, [35, 36], ~, Str], # 37
  [Print, ~, [37], 29, "Maybe[Boolean]"], # 38
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 39
  [Add, ~, [19, 39], ~, Int]]} # 40
```
