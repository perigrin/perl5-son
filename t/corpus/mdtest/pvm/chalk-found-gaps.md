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
  [PadAccess, {shared: 1, sigil: "%", symbol: cache}, [3], ~, Unknown], # 4
  [Constant, {const_type: string, value: hb}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: cached}, ~, ~, Str], # 6
  [HashLiteral, {sigil: "%", symbol: cache}, [5, 6], 0, Hash], # 7
  [Assign, ~, [4, 7], 7, List], # 8
  [Call, {dispatch_kind: direct, name: main::make, param_names: [], want: list}, [2], 8, Scalar], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 12
  [Call, {dispatch_kind: direct, name: main::make, param_names: [], want: list}, [12], 9, Scalar], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 15
  [Call, {dispatch_kind: direct, name: main::make, param_names: [], want: list}, [15], 13, Scalar], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [10, 11, 14, 11, 17, 18], 16, Scalar], # 19
  [Return, {implicit: true}, [1], 19]]} # 20
main::make: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: phi}, ~, ~, Str], # 1
  [PadAccess, {shared: 1, sigil: "%", symbol: cache}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: h}, ~, ~, Str], # 3
  [PadAccess, {sigil: $, symbol: op}, ~, ~, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Concat, ~, [3, 5], ~, Str], # 6
  [MemStart], # 7
  [Subscript, {kind: hash}, [2, 6, 7], ~, Scalar], # 8
  [Constant, {const_type: string, value: "new "}, ~, ~, Str], # 9
  [Concat, ~, [9, 5], ~, Str], # 10
  [Constant, {const_type: string, value: P}, ~, ~, Str], # 11
  [StrEq, ~, [5, 11], ~, Boolean], # 12
  [If, ~, [0, 12], 0], # 13
  [Proj, {index: 0}, [13]], # 14
  [Proj, {index: 1}, [13]], # 15
  [If, ~, [15, 4], 15], # 16
  [Proj, {index: 0}, [16]], # 17
  [Constant, {const_type: string, value: "no op\n"}, ~, ~, Str], # 18
  [Proj, {index: 1}, [16]], # 19
  [Unwind, ~, [18], 19], # 20
  [Region, {head: 16}, [17, 20]], # 21
  [Exists, {kind: hash}, [2, 6, 7], ~, Boolean], # 22
  [If, ~, [21, 22], 21], # 23
  [Proj, {index: 0}, [23]], # 24
  [Proj, {index: 1}, [23]], # 25
  [Region, ~, [14, 24, 25]], # 26
  [Phi, {predecessors: [14, 24, 25], region: 26}, [1, 8, 10], ~, Scalar], # 27
  [Return, ~, [27], 26], # 28
  [ArgsSource, ~, ~, ~, Array], # 29
  [Assign, {targets: 1}, [4, 29], ~, List]]} # 30
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
Other::helper: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "other helper"}, ~, ~, Str], # 1
  [Return, {implicit: true}, [1], 0]]} # 2
Widget::call_main: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Call, {dispatch_kind: direct, name: main::helper, param_names: []}, ~, 0, Str], # 1
  [Return, {implicit: true}, [1], 1]]} # 2
Widget::ref_other: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: code, value: Other::helper}, ~, ~, Code], # 1
  [Ref, ~, [1], ~, CodeRef], # 2
  [Call, {dispatch_kind: indirect, name: "", param_names: []}, [2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: Widget, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 0, Object], # 2
  [Call, {class_name: Widget, dispatch_kind: method, name: call_main, param_names: [], want: list}, [2], 2, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "; "}, ~, ~, Str], # 5
  [Call, {class_name: Widget, dispatch_kind: method, name: ref_other, param_names: [], want: list}, [2], 3, Unknown], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [4, 5, 7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
main::helper: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "main helper"}, ~, ~, Str], # 1
  [Return, {implicit: true}, [1], 0]]} # 2
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: experimental, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
Node::name: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: name}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
Node::new: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [PadAccess, {sigil: "%", symbol: a}, ~, ~, Unknown], # 1
  [HashLiteral, ~, [1], 0, HashRef], # 2
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [2, 3, 4], ~, Unknown], # 5
  [Return, {implicit: true}, [5], 2], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Assign, {targets: 2}, [3, 1, 7], ~, List]]} # 8
Node::owner: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: owner}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
main::__PROGRAM__: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: Phi}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: M}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: X}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: L}, ~, ~, Str], # 5
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [name], want: scalar}, [5], 0, Object], # 6
  [PadAccess, {sigil: $, symbol: loop}, [6], ~, Unknown], # 7
  [Assign, ~, [7, 6], 6, Object], # 8
  [PadAccess, {sigil: $, symbol: loop}, [8], ~, Unknown], # 9
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 10
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [kind, owner, name], want: list}, [2, 9, 10], 8, Object], # 11
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [kind], want: list}, [4], 11, Object], # 12
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [name], want: list}, [3], 12, Object], # 13
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 14
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [kind, owner, name], want: list}, [2, 13, 14], 13, Object], # 15
  [PadAccess, {sigil: $, symbol: loop}, [15], ~, Unknown], # 16
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [kind, owner], want: list}, [2, 16], 15, Object], # 17
  [PadAccess, {sigil: $, symbol: loop}, [17], ~, Unknown], # 18
  [ArrayLiteral, {sigil: "@", symbol: nodes}, [11, 1, 12, 15, 17], ~, Array], # 19
  [Ref, ~, [19], ~, ArrayRef], # 20
  [Call, {dispatch_kind: direct, name: main::matching, param_names: [], want: list}, [18, 20], 17, Str], # 21
  [Coerce, {from_repr: Unknown, to_repr: Str}, [21], ~, Str], # 22
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 23
  [Print, ~, [22, 23], 21, Scalar], # 24
  [Return, {implicit: true}, [1], 24]]} # 25
main::matching: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: found}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [Loop, {bound: entry}, [0], 0], # 4
  [Phi, {memory: true, region: 4}, [3, 89], ~, Unknown], # 5
  [Proj, {index: 1}, [4]], # 6
  [Region, {head: 4}, [6]], # 7
  [Phi, {memory: true, region: 7}, [5], ~, Unknown], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 2, 8], ~, Str], # 9
  [Return, ~, [9], 7], # 10
  [PadAccess, {sigil: $, symbol: nodes}, ~, ~, Unknown], # 11
  [PostfixDeref, {sigil: "@"}, [11, 3], ~, Array], # 12
  [Count, ~, [12, 5], ~, Int], # 13
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 14
  [Phi, {region: 4}, [14, 77], ~, Int], # 15
  [NumGt, ~, [13, 15], 4, Boolean], # 16
  [Proj, {index: 0}, [4]], # 17
  [Exists, {kind: array}, [12, 15, 5], 17, Boolean], # 18
  [Subscript, {kind: array}, [12, 15], ~, Scalar], # 19
  [Ref, ~, [19], ~, ScalarRef], # 20
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 21
  [TernaryExpr, ~, [18, 20, 21], 18, Scalar], # 22
  [PadAccess, {sigil: $, symbol: loop}, ~, ~, Unknown], # 23
  [PostfixDeref, {sigil: $}, [22, 5], ~, Scalar], # 24
  [Subscript, {kind: array}, [12, 15, 5], ~, Scalar], # 25
  [TernaryExpr, ~, [18, 24, 25], ~, Scalar], # 26
  [Constant, {const_type: string, value: kind}, ~, ~, Str], # 27
  [PostfixDeref, {sigil: $}, [22, 5], ~, Scalar], # 28
  [Subscript, {kind: array}, [12, 15, 5], ~, Scalar], # 29
  [TernaryExpr, ~, [18, 28, 29], 22, Scalar], # 30
  [Defined, ~, [30], ~, Boolean], # 31
  [If, ~, [30, 31], 30], # 32
  [Proj, {index: 0}, [32]], # 33
  [Call, {dispatch_kind: method, name: can, param_names: [], want: scalar}, [26, 27], 33, Unknown], # 34
  [Proj, {index: 1}, [32]], # 35
  [Region, {head: 32}, [34, 35]], # 36
  [Phi, {memory: true, predecessors: [33, 35], region: 36}, [34, 5], ~, Unknown], # 37
  [PostfixDeref, {sigil: $}, [22, 37], ~, Scalar], # 38
  [Subscript, {kind: array}, [12, 15, 37], ~, Scalar], # 39
  [TernaryExpr, ~, [18, 38, 39], ~, Scalar], # 40
  [Phi, {predecessors: [33, 35], region: 36}, [34, 31], ~, Unknown], # 41
  [If, ~, [36, 41], 36], # 42
  [Proj, {index: 0}, [42]], # 43
  [Call, {dispatch_kind: method, name: kind, param_names: [], want: scalar}, [40], 43, Unknown], # 44
  [PostfixDeref, {sigil: $}, [22, 44], ~, Scalar], # 45
  [Subscript, {kind: array}, [12, 15, 44], ~, Scalar], # 46
  [TernaryExpr, ~, [18, 45, 46], ~, Scalar], # 47
  [Coerce, {from_repr: Unknown, to_repr: Str}, [44], ~, Str], # 48
  [Constant, {const_type: string, value: Phi}, ~, ~, Str], # 49
  [StrEq, ~, [48, 49], ~, Boolean], # 50
  [If, ~, [44, 50], 44], # 51
  [Proj, {index: 0}, [51]], # 52
  [Call, {dispatch_kind: method, name: owner, param_names: [], want: scalar}, [47], 52, Unknown], # 53
  [Defined, ~, [53], ~, Boolean], # 54
  [If, ~, [53, 54], 53], # 55
  [Proj, {index: 0}, [55]], # 56
  [Call, {dispatch_kind: method, name: name, param_names: [], want: scalar}, [53], 56, Unknown], # 57
  [Call, {dispatch_kind: method, name: name, param_names: [], want: scalar}, [23], 57, Unknown], # 58
  [Proj, {index: 1}, [55]], # 59
  [Region, {head: 55}, [58, 59]], # 60
  [Phi, {memory: true, predecessors: [56, 59], region: 60}, [58, 53], ~, Unknown], # 61
  [PostfixDeref, {sigil: $}, [22, 61], ~, Scalar], # 62
  [Subscript, {kind: array}, [12, 15, 61], ~, Scalar], # 63
  [TernaryExpr, ~, [18, 62, 63], ~, Scalar], # 64
  [Coerce, {from_repr: Unknown, to_repr: Str}, [57], ~, Str], # 65
  [Coerce, {from_repr: Unknown, to_repr: Str}, [58], ~, Str], # 66
  [StrEq, ~, [65, 66], ~, Boolean], # 67
  [Phi, {predecessors: [56, 59], region: 60}, [67, 54], ~, Boolean], # 68
  [If, ~, [60, 68], 60], # 69
  [Proj, {index: 0}, [69]], # 70
  [Call, {dispatch_kind: method, name: name, param_names: [], want: scalar}, [64], 70, Unknown], # 71
  [Defined, ~, [71], ~, Boolean], # 72
  [If, ~, [71, 72], 71], # 73
  [Proj, {index: 0}, [73]], # 74
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 71, 71], 74, Int], # 75
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 76
  [Add, ~, [15, 76], ~, Int], # 77
  [Proj, {index: 1}, [73]], # 78
  [Region, {head: 73}, [78, 75]], # 79
  [Phi, {memory: true, predecessors: [78, 74], region: 79}, [71, 75], ~, Unknown], # 80
  [Proj, {index: 1}, [42]], # 81
  [Region, {head: 42}, [81, 79]], # 82
  [Phi, {memory: true, predecessors: [81, 43], region: 82}, [37, 80], ~, Unknown], # 83
  [Proj, {index: 1}, [51]], # 84
  [Region, {head: 4}, [82, 84]], # 85
  [Phi, {memory: true, predecessors: [17, 84], region: 85}, [83, 44], ~, Unknown], # 86
  [Proj, {index: 1}, [69]], # 87
  [Region, {head: 4}, [85, 87]], # 88
  [Phi, {memory: true, region: 88}, [86, 61], ~, Unknown], # 89
  [Count, ~, [12, 3], ~, Int], # 90
  [ArgsSource, ~, ~, ~, Array], # 91
  [Assign, {targets: 2}, [23, 11, 91], ~, List]]} # 92
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
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: If}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [3], 0, ArrayRef], # 4
  [Call, {dispatch_kind: direct, name: main::walk, param_names: [], want: list}, [2, 4], 4, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: " | "}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: S}, ~, ~, Str], # 8
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 9
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 10
  [ArrayLiteral, ~, [9, 10], 5, ArrayRef], # 11
  [Call, {dispatch_kind: direct, name: main::walk, param_names: [], want: list}, [8, 11], 11, Str], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: X}, ~, ~, Str], # 14
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 15
  [ArrayLiteral, ~, [15], 12, ArrayRef], # 16
  [Call, {dispatch_kind: direct, name: main::walk, param_names: [], want: list}, [14, 16], 16, Str], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Print, ~, [6, 7, 13, 7, 18, 19], 17, Scalar], # 20
  [Return, {implicit: true}, [1], 20]]} # 21
main::walk: {start: 0, returns: [34], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "stopped at "}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: chain}, ~, ~, Unknown], # 2
  [PadAccess, {sigil: $, symbol: op}, ~, ~, Str], # 3
  [MemStart], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 5
  [Constant, {const_type: string, value: If}, ~, ~, Str], # 6
  [StrEq, ~, [5, 6], ~, Boolean], # 7
  [Constant, {const_type: string, value: S}, ~, ~, Str], # 8
  [StrEq, ~, [5, 8], ~, Boolean], # 9
  [Or, ~, [7, 9], ~, Boolean], # 10
  [If, ~, [0, 10], 0], # 11
  [Proj, {index: 0}, [11]], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 3, 4], 12, Int], # 13
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [13], ~, Scalar], # 14
  [Coerce, {from_repr: Scalar, to_repr: Str}, [14], ~, Str], # 15
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [15, 2, 13], ~, Str], # 16
  [Concat, ~, [1, 16], ~, Str], # 17
  [Proj, {index: 1}, [11]], # 18
  [If, ~, [13, 7], 13], # 19
  [Proj, {index: 1}, [19]], # 20
  [Region, {head: 11}, [18, 20]], # 21
  [Phi, {memory: true, predecessors: [18, 12], region: 21}, [4, 13], ~, Unknown], # 22
  [Loop, {bound: entry}, [21], 21], # 23
  [Phi, {memory: true, region: 23}, [22, 48], ~, Unknown], # 24
  [Proj, {index: 1}, [23]], # 25
  [Region, {head: 23}, [25]], # 26
  [Phi, {memory: true, region: 26}, [24], ~, Unknown], # 27
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [27], ~, Scalar], # 28
  [Coerce, {from_repr: Scalar, to_repr: Str}, [28], ~, Str], # 29
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [29, 2, 27], ~, Str], # 30
  [Proj, {index: 0}, [19]], # 31
  [Region, ~, [31, 26]], # 32
  [Phi, {predecessors: [31, 26], region: 32}, [17, 30], ~, Str], # 33
  [Return, ~, [33], 32], # 34
  [PadAccess, {sigil: $, symbol: items}, ~, ~, Unknown], # 35
  [PostfixDeref, {sigil: "@"}, [35, 22], ~, Array], # 36
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 37
  [Phi, {region: 23}, [37, 54], ~, Int], # 38
  [Proj, {index: 0}, [23]], # 39
  [Exists, {kind: array}, [36, 38, 22], 39, Boolean], # 40
  [Subscript, {kind: array}, [36, 38], ~, Scalar], # 41
  [Ref, ~, [41], ~, ScalarRef], # 42
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 43
  [TernaryExpr, ~, [40, 42, 43], 40, Scalar], # 44
  [PostfixDeref, {sigil: $}, [44, 22], ~, Scalar], # 45
  [Subscript, {kind: array}, [36, 38, 22], ~, Scalar], # 46
  [TernaryExpr, ~, [40, 45, 46], 44, Scalar], # 47
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 47, 22], 47, Int], # 48
  [ArgsSource, ~, ~, ~, Array], # 49
  [Assign, {targets: 2}, [3, 35, 49], ~, List], # 50
  [Count, ~, [36, 22], ~, Int], # 51
  [NumGt, ~, [51, 38], 23, Boolean], # 52
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 53
  [Add, ~, [38, 53], ~, Int]]} # 54
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
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: values}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 5
  [ArrayLiteral, ~, [3, 4, 5], 0, ArrayRef], # 6
  [Call, {dispatch_kind: direct, name: main::build, param_names: [], want: list}, [2, 6], 6, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Call, {dispatch_kind: direct, name: main::build, param_names: [], want: list}, ~, 7, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [8, 9, 11, 12], 10, Scalar], # 13
  [Return, {implicit: true}, [1], 13]]} # 14
main::build: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: inputs}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [HashLiteral, {sigil: "%", symbol: args}, [2], ~, Hash], # 3
  [Constant, {const_type: string, value: values}, ~, ~, Str], # 4
  [MemStart], # 5
  [Delete, {kind: hash}, [3, 4, 5], 0, Scalar], # 6
  [PadAccess, {sigil: $, symbol: values}, [6], ~, Unknown], # 7
  [Assign, ~, [7, 6], 6, Scalar], # 8
  [PadAccess, {sigil: $, symbol: values}, [8], ~, Unknown], # 9
  [Defined, ~, [9], ~, Boolean], # 10
  [If, ~, [8, 10], 8], # 11
  [Proj, {index: 1}, [11]], # 12
  [ArrayLiteral, ~, ~, 12, ArrayRef], # 13
  [Proj, {index: 0}, [11]], # 14
  [Region, {head: 11}, [14, 13]], # 15
  [Phi, {predecessors: [14, 12], region: 15}, [9, 13], ~, Unknown], # 16
  [Call, {dispatch_kind: direct, name: main::count_of, param_names: []}, [1, 16], 15, Str], # 17
  [Return, ~, [17], 17]]} # 18
main::count_of: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: label}, ~, ~, Str], # 1
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 2
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 3
  [Concat, ~, [2, 3], ~, Str], # 4
  [PadAccess, {sigil: $, symbol: list}, ~, ~, Unknown], # 5
  [MemStart], # 6
  [PostfixDeref, {sigil: "@"}, [5, 6], ~, Array], # 7
  [Count, ~, [7, 6], ~, Int], # 8
  [Concat, ~, [4, 8], ~, Str], # 9
  [Return, ~, [9], 0], # 10
  [ArgsSource, ~, ~, ~, Array], # 11
  [Assign, {targets: 2}, [1, 5, 11], ~, List]]} # 12
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
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Call, {dispatch_kind: direct, name: main::big, param_names: [], want: scalar}, [3], 0, Scalar], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "] ["}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: direct, name: main::big, param_names: [], want: list}, [7], 4, Scalar], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: value}, ~, ~, Str], # 10
  [Call, {dispatch_kind: direct, name: main::truthy, param_names: [], want: list}, [10], 8, Unknown], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Call, {dispatch_kind: direct, name: main::truthy, param_names: [], want: list}, [3], 11, Unknown], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 15
  [Print, ~, [2, 5, 6, 9, 6, 12, 6, 14, 15], 13, Scalar], # 16
  [Return, {implicit: true}, [1], 16]]} # 17
main::big: {start: 0, returns: [10], nodes: [
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
  [Return, ~, [9], 8], # 10
  [ArgsSource, ~, ~, ~, Array], # 11
  [Assign, {targets: 1}, [2, 11], ~, List]]} # 12
main::truthy: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: k}, ~, ~, Unknown], # 2
  [Not, ~, [2], ~, Boolean], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 0}, [4]], # 5
  [Proj, {index: 1}, [4]], # 6
  [Region, {head: 4}, [5, 6]], # 7
  [Phi, {predecessors: [5, 6], region: 7}, [1, 2], ~, Unknown], # 8
  [Return, ~, [8], 7], # 9
  [ArgsSource, ~, ~, ~, Array], # 10
  [Assign, {targets: 1}, [2, 10], ~, List]]} # 11
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
  [PadAccess, {shared: 1, sigil: $, symbol: seen}, [8], ~, Unknown], # 9
  [Assign, ~, [9, 4], 0, Int], # 10
  [EntryWrite, ~, [7, 4, 10], 10, Unknown], # 11
  [Call, {dispatch_kind: direct, name: main::tally, param_names: [], want: list}, [2, 3, 4, 5, 6], 11, Str], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [13, 14], 12, Scalar], # 15
  [Return, {implicit: true}, [1], 15]]} # 16
main::tally: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {memory: true, region: 2}, [1, 49], ~, Unknown], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Phi, {memory: true, region: 5}, [3], ~, Unknown], # 6
  [PadAccess, {shared: 1, sigil: $, symbol: seen}, [6], ~, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [EntryDef, {package: main, sigil: $, symbol: total}, [6], ~, Scalar], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [10, 12], ~, Str], # 13
  [Return, ~, [13], 5], # 14
  [ArgsSource, ~, ~, ~, Array], # 15
  [Count, ~, [15, 3], ~, Int], # 16
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 17
  [Phi, {region: 2}, [17, 26], ~, Int], # 18
  [NumGt, ~, [16, 18], 2, Boolean], # 19
  [Proj, {index: 0}, [2]], # 20
  [Subscript, {kind: array}, [15, 18, 3], ~, Scalar], # 21
  [Coerce, {from_repr: Scalar, to_repr: Num}, [21], ~, Num], # 22
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 23
  [NumGt, ~, [22, 23], ~, Boolean], # 24
  [If, ~, [20, 24], 20], # 25
  [Add, ~, [18, 23], ~, Int], # 26
  [Proj, {index: 1}, [25]], # 27
  [Proj, {index: 0}, [25]], # 28
  [PadAccess, {shared: 1, sigil: $, symbol: seen}, [3], ~, Unknown], # 29
  [Increment, ~, [29], ~, Scalar], # 30
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 31
  [NumGt, ~, [22, 31], ~, Boolean], # 32
  [If, ~, [28, 32], 28], # 33
  [Proj, {index: 0}, [33]], # 34
  [Assign, ~, [29, 30], 34, Scalar], # 35
  [Proj, {index: 1}, [33]], # 36
  [Region, {head: 33}, [36, 35]], # 37
  [Phi, {memory: true, predecessors: [36, 34], region: 37}, [3, 35], ~, Unknown], # 38
  [EntryDef, {package: main, sigil: $, symbol: total}, ~, ~, Scalar], # 39
  [Coerce, {from_repr: Scalar, to_repr: Num}, [39], ~, Num], # 40
  [Add, ~, [40, 22], ~, Num], # 41
  [If, ~, [37, 32], 37], # 42
  [Proj, {index: 0}, [42]], # 43
  [EntryWrite, ~, [39, 41, 38], 43, Unknown], # 44
  [Proj, {index: 1}, [42]], # 45
  [Region, {head: 42}, [45, 44]], # 46
  [Phi, {memory: true, predecessors: [45, 43], region: 46}, [38, 44], ~, Unknown], # 47
  [Region, {head: 25}, [27, 46]], # 48
  [Phi, {memory: true, predecessors: [27, 28], region: 48}, [3, 47], ~, Unknown], # 49
  [Count, ~, [15, 1], ~, Int]]} # 50
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
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [2, 3], 0, ArrayRef], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Proj, {index: 1}, [5]], # 6
  [Region, {head: 5}, [6]], # 7
  [Return, {implicit: true}, [1], 7], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 11
  [ArrayLiteral, ~, [1, 9, 10, 11, 4], ~, Array], # 12
  [MemStart], # 13
  [Phi, {memory: true, region: 5}, [13, 32], ~, Unknown], # 14
  [Phi, {memory: true, region: 7}, [14], ~, Unknown], # 15
  [Phi, {region: 5}, [9, 17], ~, Int], # 16
  [Add, ~, [16, 2], ~, Int], # 17
  [Count, ~, [12, 13], ~, Int], # 18
  [Count, ~, [12, 14], ~, Int], # 19
  [Subscript, {kind: array}, [12, 16], ~, Scalar], # 20
  [Subscript, {kind: array}, [12, 16, 14], ~, Scalar], # 21
  [Proj, {index: 0}, [5]], # 22
  [Ref, ~, [20], 22, ScalarRef], # 23
  [PostfixDeref, {sigil: $}, [23, 14], ~, Scalar], # 24
  [Call, {dispatch_kind: direct, name: main::by_ternary, param_names: [], want: scalar}, [24], 23, Unknown], # 25
  [Subscript, {kind: array}, [12, 16, 25], ~, Scalar], # 26
  [PostfixDeref, {sigil: $}, [23, 25], ~, Scalar], # 27
  [Call, {dispatch_kind: direct, name: main::by_dor, param_names: [], want: scalar}, [27], 25, Unknown], # 28
  [Subscript, {kind: array}, [12, 16, 28], ~, Scalar], # 29
  [NumGt, ~, [19, 16], 5, Boolean], # 30
  [PostfixDeref, {sigil: $}, [23, 28], ~, Scalar], # 31
  [Call, {dispatch_kind: direct, name: main::by_dor, param_names: [], want: list}, [31], 28, Unknown], # 32
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 33
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 34
  [Coerce, {from_repr: Unknown, to_repr: Str}, [32], ~, Str], # 35
  [StrEq, ~, [33, 34], ~, Boolean], # 36
  [Constant, {const_type: string, value: "same "}, ~, ~, Str], # 37
  [Constant, {const_type: string, value: "differ "}, ~, ~, Str], # 38
  [TernaryExpr, ~, [36, 37, 38], ~, Str], # 39
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 40
  [Print, ~, [39, 35, 40], 32, Scalar]]} # 41
main::by_dor: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Unknown], # 1
  [Defined, ~, [1], ~, Boolean], # 2
  [If, ~, [0, 2], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [ArrayLiteral, ~, ~, 4, ArrayRef], # 5
  [DefinedOr, ~, [1, 5], ~, Unknown], # 6
  [RefType, ~, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "ref("}, ~, ~, Str], # 8
  [MemStart], # 9
  [PostfixDeref, {sigil: "@"}, [6, 9], ~, Array], # 10
  [Count, ~, [10, 9], ~, Int], # 11
  [Coerce, {from_repr: Int, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [8, 12], ~, Str], # 13
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [TernaryExpr, ~, [7, 15, 6], ~, Unknown], # 16
  [Proj, {index: 0}, [3]], # 17
  [Region, {head: 3}, [17, 5]], # 18
  [Return, ~, [16], 18], # 19
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 20
  [TernaryExpr, ~, [7, 15, 20], ~, Scalar], # 21
  [ArgsSource, ~, ~, ~, Array], # 22
  [Assign, {targets: 1}, [1, 22], ~, List]]} # 23
main::by_ternary: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Unknown], # 1
  [Defined, ~, [1], ~, Boolean], # 2
  [If, ~, [0, 2], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [ArrayLiteral, ~, ~, 4, ArrayRef], # 5
  [Proj, {index: 0}, [3]], # 6
  [Region, {head: 3}, [6, 5]], # 7
  [Phi, {predecessors: [6, 4], region: 7}, [1, 5], ~, Unknown], # 8
  [RefType, ~, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "ref("}, ~, ~, Str], # 10
  [MemStart], # 11
  [PostfixDeref, {sigil: "@"}, [8, 11], ~, Array], # 12
  [Count, ~, [12, 11], ~, Int], # 13
  [Coerce, {from_repr: Int, to_repr: Str}, [13], ~, Str], # 14
  [Concat, ~, [10, 14], ~, Str], # 15
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [TernaryExpr, ~, [9, 17, 8], ~, Unknown], # 18
  [Return, ~, [18], 7], # 19
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 20
  [TernaryExpr, ~, [9, 17, 20], ~, Scalar], # 21
  [ArgsSource, ~, ~, ~, Array], # 22
  [Assign, {targets: 1}, [1, 22], ~, List]]} # 23
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
  [PadAccess, {shared: 1, sigil: $, symbol: fetches}, [3], ~, Unknown], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int], # 6
  [PadAccess, {shared: 1, sigil: $, symbol: fetches}, [6], ~, Unknown], # 7
  [Assign, ~, [7, 5], 6, Int], # 8
  [Call, {dispatch_kind: direct, name: main::next_value, param_names: [], want: scalar}, ~, 8, Str], # 9
  [Defined, ~, [9], ~, Boolean], # 10
  [If, ~, [9, 10], 9], # 11
  [Proj, {index: 0}, [11]], # 12
  [Call, {dispatch_kind: direct, name: main::next_value, param_names: [], want: scalar}, ~, 12, Str], # 13
  [Proj, {index: 1}, [11]], # 14
  [Region, {head: 11}, [13, 14]], # 15
  [Phi, {memory: true, predecessors: [12, 14], region: 15}, [13, 9], ~, Str], # 16
  [PadAccess, {shared: 1, sigil: $, symbol: fetches}, [16], ~, Str], # 17
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
  [Print, ~, [28], 15, Scalar], # 29
  [Assign, ~, [17, 5], 29, Int], # 30
  [Call, {dispatch_kind: direct, name: main::next_value, param_names: [], want: scalar}, ~, 30, Str], # 31
  [DefinedOr, ~, [31, 19], ~, Str], # 32
  [Coerce, {from_repr: Unknown, to_repr: Str}, [32], ~, Str], # 33
  [Concat, ~, [2, 33], ~, Str], # 34
  [Concat, ~, [34, 23], ~, Str], # 35
  [PadAccess, {shared: 1, sigil: $, symbol: fetches}, [31], ~, Str], # 36
  [Coerce, {from_repr: Unknown, to_repr: Str}, [36], ~, Str], # 37
  [Concat, ~, [35, 37], ~, Str], # 38
  [Concat, ~, [38, 27], ~, Str], # 39
  [Print, ~, [39], 31, Scalar], # 40
  [Return, {implicit: true}, [1], 40]]} # 41
main::next_value: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {shared: 1, sigil: $, symbol: fetches}, [1], ~, Unknown], # 2
  [Increment, ~, [2], ~, Scalar], # 3
  [Assign, ~, [2, 3], 0, Scalar], # 4
  [PadAccess, {shared: 1, sigil: $, symbol: fetches}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [NumGt, ~, [5, 6], ~, Boolean], # 7
  [Constant, {const_type: string, value: second}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: first}, ~, ~, Str], # 9
  [TernaryExpr, ~, [7, 8, 9], ~, Str], # 10
  [Return, ~, [10], 4]]} # 11
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
main::__PROGRAM__: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::collect, param_names: [], want: list}, [2], 0, List], # 3
  [ArrayLiteral, {sigil: "@", symbol: a}, [3], ~, Array], # 4
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, name: main::collect, param_names: [], want: list}, [1], 3, List], # 7
  [Call, {dispatch_kind: direct, name: main::pair, param_names: [], want: list}, [6], 7, List], # 8
  [Call, {dispatch_kind: direct, name: main::pair, param_names: [], want: scalar}, [5], 8, List], # 9
  [Count, ~, [4, 9], ~, Int], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 12
  [ArrayLiteral, {sigil: "@", symbol: b}, [7], ~, Array], # 13
  [Count, ~, [13, 9], ~, Int], # 14
  [Coerce, {from_repr: Int, to_repr: Str}, [14], ~, Str], # 15
  [ArrayLiteral, {sigil: "@", symbol: p}, [8], ~, Array], # 16
  [Count, ~, [16, 9], ~, Int], # 17
  [Coerce, {from_repr: Int, to_repr: Str}, [17], ~, Str], # 18
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 19
  [Concat, ~, [12, 19], ~, Str], # 20
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 21
  [Concat, ~, [20, 21], ~, Str], # 22
  [Print, ~, [11, 12, 15, 12, 18, 22], 9, Scalar], # 23
  [Return, {implicit: true}, [1], 23]]} # 24
main::collect: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Int], # 3
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
  [Return, ~, [15, 19], 14], # 20
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 21
  [Range, ~, [21, 3], ~, List], # 22
  [MemStart], # 23
  [Count, ~, [22, 23], ~, Int], # 24
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 25
  [Phi, {region: 8}, [25, 36], ~, Int], # 26
  [NumGt, ~, [24, 26], 8, Boolean], # 27
  [Proj, {index: 0}, [8]], # 28
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 29
  [Subscript, {kind: array}, [22, 26, 23], ~, Scalar], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [30], ~, Str], # 31
  [Concat, ~, [29, 31], ~, Str], # 32
  [ListAppend, {collector: map}, [9, 32], ~, Array], # 33
  [ArgsSource, ~, ~, ~, Array], # 34
  [Assign, {targets: 1}, [3, 34], ~, List], # 35
  [Add, ~, [26, 21], ~, Int]]} # 36
main::pair: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Num], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Add, ~, [2, 3], ~, Num], # 4
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
  [Return, ~, [11, 14], 10], # 15
  [ArgsSource, ~, ~, ~, Array], # 16
  [Assign, {targets: 1}, [2, 16], ~, List]]} # 17
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
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::range_of, param_names: [], want: list}, [2], 0, Int], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, name: main::range_of, param_names: [], want: list}, [6], 3, Int], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [4, 5, 8, 9], 7, Scalar], # 10
  [Return, {implicit: true}, [1], 10]]} # 11
main::range_of: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Int], # 3
  [Range, ~, [2, 3], ~, List], # 4
  [ArrayLiteral, {sigil: "@", symbol: c}, [4], ~, Array], # 5
  [MemStart], # 6
  [Count, ~, [5, 6], ~, Int], # 7
  [Not, ~, [3], ~, Boolean], # 8
  [If, ~, [0, 8], 0], # 9
  [Proj, {index: 0}, [9]], # 10
  [Proj, {index: 1}, [9]], # 11
  [Region, {head: 9}, [10, 11]], # 12
  [Phi, {predecessors: [10, 11], region: 12}, [1, 7], ~, Int], # 13
  [Return, ~, [13], 12], # 14
  [ArgsSource, ~, ~, ~, Array], # 15
  [Assign, {targets: 1}, [3, 15], ~, List]]} # 16
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
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::pick, param_names: [], want: list}, [2], 0, Int], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Call, {dispatch_kind: direct, name: main::pick, param_names: [], want: list}, [1], 3, Int], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [4, 5, 7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
main::pick: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: p}, ~, ~, Unknown], # 1
  [Defined, ~, [1], ~, Boolean], # 2
  [If, ~, [0, 2], 0], # 3
  [Proj, {index: 0}, [3]], # 4
  [Call, {dispatch_kind: direct, name: main::two, param_names: [], want: list}, ~, 4, List], # 5
  [ArrayLiteral, ~, ~, ~, List], # 6
  [Proj, {index: 1}, [3]], # 7
  [Region, {head: 3}, [5, 7]], # 8
  [Phi, {predecessors: [4, 7], region: 8}, [5, 6], ~, List], # 9
  [ArrayLiteral, {sigil: "@", symbol: c}, [9], ~, Array], # 10
  [MemStart], # 11
  [Phi, {memory: true, predecessors: [4, 7], region: 8}, [5, 11], ~, Unknown], # 12
  [Count, ~, [10, 12], ~, Int], # 13
  [Return, ~, [13], 8], # 14
  [ArgsSource, ~, ~, ~, Array], # 15
  [Assign, {targets: 1}, [1, 15], ~, List]]} # 16
main::two: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [ArrayLiteral, ~, [1, 2], ~, List], # 3
  [Coerce, {from_repr: List, to_repr: Scalar}, [2], ~, Scalar], # 4
  [Return, ~, [3, 4], 0]]} # 5
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
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: base}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [HashLiteral, ~, [2, 3], 0, HashRef], # 4
  [Call, {dispatch_kind: direct, name: main::branch, param_names: [], want: list}, [4], 4, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, Scalar], # 8
  [Return, {implicit: true}, [1], 8]]} # 9
main::add_key: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [PadAccess, {sigil: $, symbol: h}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: added}, ~, ~, Str], # 3
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 4
  [Assign, ~, [4, 1], 0, Int], # 5
  [Return, {implicit: true}, [1], 5], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Assign, {targets: 1}, [2, 7], ~, List]]} # 8
main::branch: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: src}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [PostfixDeref, {sigil: "%"}, [2, 3], ~, Hash], # 4
  [HashLiteral, {sigil: "%", symbol: then}, [4], ~, Hash], # 5
  [Ref, ~, [5], ~, HashRef], # 6
  [Call, {dispatch_kind: direct, name: main::add_key, param_names: [], want: void}, [6], 0, Int], # 7
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [4, 7], ~, List], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [8, 7], ~, List], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 9, 7], ~, Str], # 10
  [Constant, {const_type: string, value: " | "}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [5, 7], ~, List], # 13
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [13, 7], ~, List], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 14, 7], ~, Str], # 15
  [Concat, ~, [12, 15], ~, Str], # 16
  [Return, ~, [16], 7], # 17
  [ArgsSource, ~, ~, ~, Array], # 18
  [Assign, {targets: 1}, [2, 18], ~, List]]} # 19
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
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::find, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "; "}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, name: main::find, param_names: [], want: list}, [6], 3, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [4, 5, 8, 9], 7, Scalar], # 10
  [Return, {implicit: true}, [1], 10]]} # 11
main::find: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: found}, [1], ~, Unknown], # 2
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 3
  [Assign, ~, [2, 3], 0, Undef], # 4
  [PadAccess, {sigil: $, symbol: found}, [4], ~, Unknown], # 5
  [Constant, {const_type: string, value: it}, ~, ~, Str], # 6
  [PadAccess, {sigil: $, symbol: want}, ~, ~, Unknown], # 7
  [If, ~, [4, 7], 4], # 8
  [Proj, {index: 0}, [8]], # 9
  [Assign, ~, [5, 6], 9, Str], # 10
  [Proj, {index: 1}, [8]], # 11
  [Region, {head: 8}, [11, 10]], # 12
  [Phi, {memory: true, predecessors: [11, 9], region: 12}, [4, 10], ~, Scalar], # 13
  [PadAccess, {sigil: $, symbol: found}, [13], ~, Unknown], # 14
  [Call, {dispatch_kind: direct, name: main::load, param_names: []}, [14], 12, Str], # 15
  [Return, ~, [15], 15], # 16
  [ArgsSource, ~, ~, ~, Array], # 17
  [Assign, {targets: 1}, [7, 17], ~, List]]} # 18
main::load: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "loaded "}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Constant, {const_type: string, value: nothing}, ~, ~, Str], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Concat, ~, [1, 8], ~, Str], # 9
  [Return, {implicit: true}, [9], 0]]} # 10
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
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 4
  [Call, {dispatch_kind: direct, name: main::search, param_names: [], want: list}, [2, 3, 4], 0, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "; "}, ~, ~, Str], # 7
  [Call, {dispatch_kind: direct, name: main::search, param_names: [], want: list}, [2], 5, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [6, 7, 9, 10], 8, Scalar], # 11
  [Return, {implicit: true}, [1], 11]]} # 12
main::load: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "loaded "}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Constant, {const_type: string, value: nothing}, ~, ~, Str], # 6
  [DefinedOr, ~, [5, 6], ~, Scalar], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Concat, ~, [1, 8], ~, Str], # 9
  [Return, {implicit: true}, [9], 0]]} # 10
main::search: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: found}, [1], ~, Unknown], # 2
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 3
  [Assign, ~, [2, 3], 0, Undef], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Phi, {memory: true, region: 5}, [4, 6], ~, Unknown], # 6
  [PadAccess, {sigil: $, symbol: found}, [6], ~, Unknown], # 7
  [ArgsSource, ~, ~, ~, Array], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Phi, {region: 5}, [9, 29], ~, Int], # 10
  [Subscript, {kind: array}, [8, 10, 6], ~, Scalar], # 11
  [Proj, {index: 0}, [5]], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 13
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 14
  [StrEq, ~, [13, 14], ~, Boolean], # 15
  [If, ~, [12, 15], 12], # 16
  [Proj, {index: 0}, [16]], # 17
  [Assign, ~, [7, 11], 17, Scalar], # 18
  [Proj, {index: 1}, [5]], # 19
  [Region, {head: 5}, [19, 18]], # 20
  [Phi, {memory: true, region: 20}, [6, 18], ~, Unknown], # 21
  [PadAccess, {sigil: $, symbol: found}, [21], ~, Unknown], # 22
  [Call, {dispatch_kind: direct, name: main::load, param_names: []}, [22], 20, Str], # 23
  [Return, ~, [23], 23], # 24
  [Count, ~, [8, 4], ~, Int], # 25
  [Count, ~, [8, 6], ~, Int], # 26
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
  [Count, ~, [7, 8], ~, Int], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " ["}, ~, ~, Str], # 11
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [8], ~, Scalar], # 12
  [Coerce, {from_repr: Scalar, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 14
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 15
  [ArrayLiteral, ~, [14, 15], ~, List], # 16
  [Coerce, {from_repr: List, to_repr: Str}, [16], ~, Str], # 17
  [Repeat, ~, [17, 15], ~, List], # 18
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [13, 18, 8], ~, Str], # 19
  [Concat, ~, [11, 19], ~, Str], # 20
  [Constant, {const_type: string, value: "] "}, ~, ~, Str], # 21
  [Concat, ~, [20, 21], ~, Str], # 22
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 23
  [Repeat, ~, [23, 5], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [Print, ~, [10, 22, 24, 25], 0, Scalar], # 26
  [Return, {implicit: true}, [1], 26], # 27
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
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "*"}, ~, ~, Str], # 3
  [Call, {dispatch_kind: direct, name: main::describe, param_names: [], want: list}, [2, 3], 0, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 7
  [Call, {dispatch_kind: direct, name: main::describe, param_names: [], want: list}, [7], 4, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [ArrayLiteral, ~, [10], 8, ArrayRef], # 11
  [Constant, {const_type: string, value: "?"}, ~, ~, Str], # 12
  [Call, {dispatch_kind: direct, name: main::describe, param_names: [], want: list}, [11, 12], 11, Str], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [5, 6, 9, 6, 14, 15], 13, Scalar], # 16
  [Return, {implicit: true}, [1], 16]]} # 17
main::describe: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: value}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: m}, ~, ~, Str], # 2
  [StrGt, ~, [1, 2], ~, Boolean], # 3
  [Constant, {const_type: string, value: "+"}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 5
  [PadAccess, {sigil: $, symbol: quantifier}, ~, ~, Str], # 6
  [Defined, ~, [6], ~, Boolean], # 7
  [RefType, ~, [1], ~, Str], # 8
  [Constant, {const_type: string, value: "<ref>"}, ~, ~, Str], # 9
  [TernaryExpr, ~, [8, 9, 1], ~, Unknown], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [TernaryExpr, {rebind_arm: 1}, [7, 12, 10], 0, Unknown], # 13
  [TernaryExpr, {rebind_arm: 2}, [3, 4, 5], 13, Str], # 14
  [Concat, ~, [14, 13], ~, Str], # 15
  [Return, ~, [15], 14], # 16
  [ArgsSource, ~, ~, ~, Array], # 17
  [Assign, {targets: 2}, [1, 6, 17], ~, List]]} # 18
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
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 0, Int], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [5], 3, Int], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [4, 7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
main::f: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [ArrayLiteral, {sigil: "@", symbol: a}, [1], ~, Array], # 2
  [Subscript, {kind: array}, [2, 1], ~, Int], # 3
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [MemStart], # 6
  [Subscript, {kind: array}, [5, 1, 6], ~, Scalar], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [Assign, ~, [3, 4], 9, Int], # 10
  [Subscript, {kind: array}, [2, 1, 10], ~, Int], # 11
  [Constant, {const_type: integer, value: "8"}, ~, ~, Int], # 12
  [Proj, {index: 1}, [8]], # 13
  [Region, {head: 8}, [10, 13]], # 14
  [Phi, {predecessors: [9, 13], region: 14}, [11, 12], ~, Int], # 15
  [Return, ~, [15], 14], # 16
  [Phi, {memory: true, predecessors: [9, 13], region: 14}, [10, 6], ~, Unknown]]} # 17
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
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3], 0, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 7
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 8
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [7, 8], 4, Str], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [5, 6, 10, 11], 9, Scalar], # 12
  [Return, {implicit: true}, [1], 12]]} # 13
main::f: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: r}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [HashLiteral, {sigil: "%", symbol: o}, [2], ~, Hash], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [MemStart], # 5
  [Exists, {kind: hash}, [3, 4, 5], ~, Boolean], # 6
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 7
  [Constant, {const_type: string, value: dflt}, ~, ~, Str], # 8
  [TernaryExpr, ~, [6, 7, 8], ~, Unknown], # 9
  [Call, {dispatch_kind: direct, name: main::g, param_names: []}, [1, 9], 0, Str], # 10
  [Return, ~, [10], 10]]} # 11
main::g: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 2, 3], ~, Str], # 4
  [Return, ~, [4], 0]]} # 5
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
  [Subscript, {kind: hash}, [5, 4, 6], ~, Int], # 7
  [Constant, {const_type: integer, value: "8"}, ~, ~, Int], # 8
  [TernaryExpr, ~, [3, 7, 8], ~, Unknown], # 9
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [2, 9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Subscript, {kind: hash}, [5, 4], ~, Int], # 13
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: void}, [13], 0, Int], # 14
  [Subscript, {kind: hash}, [5, 4, 14], ~, Scalar], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [12, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Print, ~, [19], 14, Scalar], # 20
  [Return, {implicit: true}, [1], 20]]} # 21
main::g: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [Assign, ~, [4, 1], 0, Int], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
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
  [Subscript, {kind: hash}, [5, 3, 6], ~, Int], # 7
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 8
  [ArrayLiteral, {sigil: "@", symbol: a}, [8], ~, Array], # 9
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [9, 10, 6], ~, Int], # 11
  [Call, {dispatch_kind: builtin, name: sprintf, param_names: []}, [2, 7, 11], ~, Str], # 12
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [Subscript, {kind: array}, [9, 10], ~, Int], # 15
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 16
  [Subscript, {kind: hash}, [5, 3], ~, Int], # 17
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 18
  [Assign, ~, [17, 18], 0, Int], # 19
  [Assign, ~, [15, 16], 19, Int], # 20
  [Subscript, {kind: hash}, [5, 3, 20], ~, Int], # 21
  [Coerce, {from_repr: Unknown, to_repr: Str}, [21], ~, Str], # 22
  [Concat, ~, [14, 22], ~, Str], # 23
  [Concat, ~, [23, 13], ~, Str], # 24
  [Subscript, {kind: array}, [9, 10, 20], ~, Int], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 26
  [Concat, ~, [24, 26], ~, Str], # 27
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 28
  [Concat, ~, [27, 28], ~, Str], # 29
  [Print, ~, [29], 20, Scalar], # 30
  [Return, {implicit: true}, [1], 30]]} # 31
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
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
N::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [HashLiteral, ~, [1, 5], 0, HashRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7, 4], ~, Scalar], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [6, 8, 4], ~, Unknown], # 9
  [Return, {implicit: true}, [9], 6]]} # 10
main::__PROGRAM__: {start: 0, returns: [32], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [ArrayLiteral, ~, ~, ~, Array], # 4
  [Loop, {bound: entry}, [0], 0], # 5
  [Phi, {region: 5}, [4, 60], ~, Array], # 6
  [MemStart], # 7
  [Phi, {memory: true, region: 5}, [7, 49], ~, Unknown], # 8
  [Proj, {index: 1}, [5]], # 9
  [Region, {head: 5}, [9]], # 10
  [Phi, {memory: true, region: 10}, [8], ~, Unknown], # 11
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:1, sort_package: main, want: list}, [6, 11], 10, List], # 12
  [Loop, {bound: entry}, [12], 12], # 13
  [Phi, {memory: true, region: 13}, [12, 74], ~, Unknown], # 14
  [Proj, {index: 1}, [13]], # 15
  [Region, {head: 13}, [15]], # 16
  [Phi, {memory: true, region: 16}, [14], ~, Unknown], # 17
  [ArrayLiteral, ~, ~, ~, Array], # 18
  [Phi, {region: 13}, [18, 75], ~, Array], # 19
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [2, 19, 17], ~, Str], # 20
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 21
  [Print, ~, [20, 21], 16, Scalar], # 22
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:2, sort_package: main, want: list}, [6, 17], 22, List], # 23
  [Loop, {bound: entry}, [23], 23], # 24
  [Phi, {region: 24}, [3, 57], ~, Array], # 25
  [Phi, {memory: true, region: 24}, [23, 56], ~, Unknown], # 26
  [Proj, {index: 1}, [24]], # 27
  [Region, {head: 24}, [27]], # 28
  [Phi, {memory: true, region: 28}, [26], ~, Unknown], # 29
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [2, 25, 29], ~, Str], # 30
  [Print, ~, [30, 21], 28, Scalar], # 31
  [Return, {implicit: true}, [1], 31], # 32
  [Constant, {const_type: string, value: pear}, ~, ~, Str], # 33
  [Constant, {const_type: string, value: apple}, ~, ~, Str], # 34
  [Constant, {const_type: string, value: fig}, ~, ~, Str], # 35
  [ArrayLiteral, ~, [33, 34, 35], ~, List], # 36
  [Count, ~, [36, 8], ~, Int], # 37
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 38
  [Phi, {region: 5}, [38, 46], ~, Int], # 39
  [NumGt, ~, [37, 39], 5, Boolean], # 40
  [Proj, {index: 0}, [5]], # 41
  [Subscript, {kind: array}, [36, 39], ~, Scalar], # 42
  [Ref, ~, [42], ~, ScalarRef], # 43
  [LocalAlias, {name: _}, [43], 41, Unknown], # 44
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 45
  [Add, ~, [39, 45], ~, Int], # 46
  [Subscript, {kind: array}, [36, 39, 8], ~, Str], # 47
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 48
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [48, 47], 44, Object], # 49
  [Phi, {region: 24}, [38, 70], ~, Int], # 50
  [Subscript, {kind: array}, [23, 50, 26], ~, Scalar], # 51
  [Subscript, {kind: array}, [23, 50], ~, Scalar], # 52
  [Ref, ~, [52], ~, ScalarRef], # 53
  [Proj, {index: 0}, [24]], # 54
  [LocalAlias, {name: _}, [53], 54, Unknown], # 55
  [Call, {dispatch_kind: method, name: name, param_names: [], want: list}, [51], 55, Unknown], # 56
  [ListAppend, {collector: map}, [25, 56], ~, Array], # 57
  [Count, ~, [36, 7], ~, Int], # 58
  [Phi, {region: 13}, [38, 68], ~, Int], # 59
  [ListAppend, {collector: map}, [6, 49], ~, Array], # 60
  [Count, ~, [12, 12], ~, Int], # 61
  [Count, ~, [12, 14], ~, Int], # 62
  [Subscript, {kind: array}, [12, 59, 14], ~, Scalar], # 63
  [Subscript, {kind: array}, [12, 59], ~, Scalar], # 64
  [Count, ~, [23, 26], ~, Int], # 65
  [Count, ~, [23, 23], ~, Int], # 66
  [NumGt, ~, [65, 50], 24, Boolean], # 67
  [Add, ~, [59, 45], ~, Int], # 68
  [NumGt, ~, [62, 59], 13, Boolean], # 69
  [Add, ~, [50, 45], ~, Int], # 70
  [Proj, {index: 0}, [13]], # 71
  [Ref, ~, [64], ~, ScalarRef], # 72
  [LocalAlias, {name: _}, [72], 71, Unknown], # 73
  [Call, {dispatch_kind: method, name: name, param_names: [], want: list}, [63], 73, Unknown], # 74
  [ListAppend, {collector: map}, [19, 74], ~, Array]]} # 75
main::__PROGRAM__::__SORTCMP__:1: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: a}, ~, ~, Scalar], # 1
  [Call, {dispatch_kind: method, name: name, param_names: [], want: scalar}, [1], 0, Unknown], # 2
  [EntryDef, {package: main, sigil: $, symbol: b}, ~, ~, Scalar], # 3
  [Call, {dispatch_kind: method, name: name, param_names: [], want: scalar}, [3], 2, Unknown], # 4
  [StrCmp, ~, [2, 4], ~, Int], # 5
  [Return, {implicit: true}, [5], 4]]} # 6
main::__PROGRAM__::__SORTCMP__:2: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: a}, ~, ~, Scalar], # 1
  [Call, {dispatch_kind: method, name: name, param_names: [], want: scalar}, [1], 0, Unknown], # 2
  [Length, ~, [2], ~, Int], # 3
  [EntryDef, {package: main, sigil: $, symbol: b}, ~, ~, Scalar], # 4
  [Call, {dispatch_kind: method, name: name, param_names: [], want: scalar}, [4], 2, Unknown], # 5
  [Length, ~, [5], ~, Int], # 6
  [NumCmp, ~, [3, 6], ~, Int], # 7
  [Return, {implicit: true}, [7], 5]]} # 8
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
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [ArrayLiteral, {sigil: "@", symbol: a}, [3, 4, 5], ~, Array], # 6
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 1}, [8]], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:1, sort_package: main, want: list}, [6, 2], 9, List], # 10
  [Proj, {index: 0}, [8]], # 11
  [Region, {head: 8}, [11, 10]], # 12
  [Phi, {memory: true, predecessors: [11, 9], region: 12}, [2, 10], ~, Unknown], # 13
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [13], ~, Scalar], # 14
  [Coerce, {from_repr: Scalar, to_repr: Str}, [14], ~, Str], # 15
  [ArrayLiteral, {sigil: "@", symbol: a}, [10], ~, Array], # 16
  [Phi, {predecessors: [11, 9], region: 12}, [6, 16], ~, Array], # 17
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [15, 17, 13], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Concat, ~, [18, 19], ~, Str], # 20
  [Print, ~, [20], 12, Scalar], # 21
  [Return, {implicit: true}, [1], 21]]} # 22
main::__PROGRAM__::__SORTCMP__:1: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: a}, [1], ~, Scalar], # 2
  [Coerce, {from_repr: Scalar, to_repr: Num}, [2], ~, Num], # 3
  [EntryDef, {package: main, sigil: $, symbol: b}, [1], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [NumCmp, ~, [3, 5], ~, Int], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: "@", symbol: ARGV}, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [If, ~, [0, 2], 0], # 6
  [Proj, {index: 0}, [6]], # 7
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::c, sort_package: main, want: list}, [3, 4, 5], 7, List], # 8
  [And, ~, [2, 8], ~, List], # 9
  [ArrayLiteral, {sigil: "@", symbol: r}, [9], ~, Array], # 10
  [MemStart], # 11
  [Proj, {index: 1}, [6]], # 12
  [Region, {head: 6}, [12, 8]], # 13
  [Phi, {memory: true, predecessors: [12, 7], region: 13}, [11, 8], ~, Unknown], # 14
  [Count, ~, [10, 14], ~, Int], # 15
  [Coerce, {from_repr: Int, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [16, 17], 13, Scalar], # 18
  [Return, {implicit: true}, [1], 18]]} # 19
main::c: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: a}, [1], ~, Scalar], # 2
  [Coerce, {from_repr: Scalar, to_repr: Num}, [2], ~, Num], # 3
  [EntryDef, {package: main, sigil: $, symbol: b}, [1], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [NumCmp, ~, [3, 5], ~, Int], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
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
  [Not, ~, [11], ~, Boolean], # 12
  [If, ~, [0, 12], 0], # 13
  [Proj, {index: 0}, [13]], # 14
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 14, List], # 15
  [Proj, {index: 1}, [13]], # 16
  [Region, {head: 13}, [15, 16]], # 17
  [Print, ~, [10], 17, Scalar], # 18
  [Return, {implicit: true}, [1], 18], # 19
  [ArrayLiteral, ~, ~, ~, List], # 20
  [Phi, {predecessors: [14, 16], region: 17}, [15, 20], ~, List], # 21
  [MemStart], # 22
  [Phi, {memory: true, predecessors: [14, 16], region: 17}, [15, 22], ~, Unknown], # 23
  [Assign, {targets: 2}, [2, 6, 21], ~, List]]} # 24
main::f: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [ArrayLiteral, ~, [1, 2], ~, List], # 3
  [Coerce, {from_repr: List, to_repr: Scalar}, [2], ~, Scalar], # 4
  [Return, {implicit: true}, [3, 4], 0]]} # 5
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
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::w, param_names: [], want: list}, [2], 0, Scalar], # 3
  [ArrayLiteral, {sigil: "@", symbol: r}, [3], ~, Array], # 4
  [Call, {dispatch_kind: direct, name: main::w, param_names: [], want: scalar}, [2], 3, Scalar], # 5
  [Count, ~, [4, 5], ~, Int], # 6
  [Coerce, {from_repr: Int, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 8
  [Defined, ~, [5], ~, Boolean], # 9
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 11
  [TernaryExpr, ~, [9, 10, 11], ~, Str], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [Call, {dispatch_kind: direct, name: main::w, param_names: [], want: list}, [13], 5, Scalar], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Print, ~, [7, 8, 12, 8, 15, 16], 14, Scalar], # 17
  [Return, {implicit: true}, [1], 17]]} # 18
main::w: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [3, 4, 5], ~, Scalar], # 6
  [If, ~, [0, 6], 0], # 7
  [Proj, {index: 1}, [7]], # 8
  [Constant, {const_type: string, value: "x\n"}, ~, ~, Str], # 9
  [Proj, {index: 0}, [7]], # 10
  [Unwind, ~, [9], 10], # 11
  [Region, {head: 7}, [8, 11]], # 12
  [Region, {eval_entry: 0, eval_want: runtime}, [12]], # 13
  [Phi, {region: 13}, [1, 2], ~, Scalar], # 14
  [Return, ~, [14], 13]]} # 15
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
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
Node::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: id}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [HashLiteral, ~, [1, 5], 0, HashRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7, 4], ~, Scalar], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [6, 8, 4], ~, Unknown], # 9
  [Return, {implicit: true}, [9], 6]]} # 10
main::__PROGRAM__: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [ArrayLiteral, ~, ~, ~, Array], # 4
  [Loop, {bound: entry}, [0], 0], # 5
  [Phi, {region: 5}, [4, 51], ~, Array], # 6
  [HashLiteral, {sigil: "%", symbol: member}, [6], ~, Hash], # 7
  [MemStart], # 8
  [Phi, {memory: true, region: 5}, [8, 41], ~, Unknown], # 9
  [Proj, {index: 1}, [5]], # 10
  [Region, {head: 5}, [10]], # 11
  [Phi, {memory: true, region: 11}, [9], ~, Unknown], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: values, param_names: [], want: list}, [7, 12], ~, List], # 13
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:1, sort_package: main, want: list}, [13, 12], 11, List], # 14
  [Loop, {bound: entry}, [14], 14], # 15
  [Phi, {region: 15}, [3, 49], ~, Array], # 16
  [Phi, {memory: true, region: 15}, [14, 48], ~, Unknown], # 17
  [Proj, {index: 1}, [15]], # 18
  [Region, {head: 15}, [18]], # 19
  [Phi, {memory: true, region: 19}, [17], ~, Unknown], # 20
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [2, 16, 20], ~, Str], # 21
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 22
  [Print, ~, [21, 22], 19, Scalar], # 23
  [Return, {implicit: true}, [1], 23], # 24
  [Constant, {const_type: string, value: n3}, ~, ~, Str], # 25
  [Constant, {const_type: string, value: n1}, ~, ~, Str], # 26
  [Constant, {const_type: string, value: n2}, ~, ~, Str], # 27
  [ArrayLiteral, ~, [25, 26, 27], ~, List], # 28
  [Count, ~, [28, 9], ~, Int], # 29
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 30
  [Phi, {region: 5}, [30, 38], ~, Int], # 31
  [NumGt, ~, [29, 31], 5, Boolean], # 32
  [Proj, {index: 0}, [5]], # 33
  [Subscript, {kind: array}, [28, 31], ~, Scalar], # 34
  [Ref, ~, [34], ~, ScalarRef], # 35
  [LocalAlias, {name: _}, [35], 33, Unknown], # 36
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 37
  [Add, ~, [31, 37], ~, Int], # 38
  [Subscript, {kind: array}, [28, 31, 9], ~, Str], # 39
  [Constant, {const_type: string, value: Node}, ~, ~, Str], # 40
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [], want: list}, [40, 39], 36, Object], # 41
  [Phi, {region: 15}, [30, 55], ~, Int], # 42
  [Subscript, {kind: array}, [14, 42, 17], ~, Scalar], # 43
  [Subscript, {kind: array}, [14, 42], ~, Scalar], # 44
  [Ref, ~, [44], ~, ScalarRef], # 45
  [Proj, {index: 0}, [15]], # 46
  [LocalAlias, {name: _}, [45], 46, Unknown], # 47
  [Call, {dispatch_kind: method, name: id, param_names: [], want: list}, [43], 47, Unknown], # 48
  [ListAppend, {collector: map}, [16, 48], ~, Array], # 49
  [Count, ~, [28, 8], ~, Int], # 50
  [ListAppend, {collector: map}, [6, 39, 41], ~, Array], # 51
  [Count, ~, [14, 14], ~, Int], # 52
  [Count, ~, [14, 17], ~, Int], # 53
  [NumGt, ~, [53, 42], 15, Boolean], # 54
  [Add, ~, [42, 37], ~, Int]]} # 55
main::__PROGRAM__::__SORTCMP__:1: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: a}, ~, ~, Scalar], # 1
  [Call, {dispatch_kind: method, name: id, param_names: [], want: scalar}, [1], 0, Unknown], # 2
  [EntryDef, {package: main, sigil: $, symbol: b}, ~, ~, Scalar], # 3
  [Call, {dispatch_kind: method, name: id, param_names: [], want: scalar}, [3], 2, Unknown], # 4
  [StrCmp, ~, [2, 4], ~, Int], # 5
  [Return, {implicit: true}, [5], 4]]} # 6
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
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:1, sort_package: main, want: list}, [3, 4, 5], 0, List], # 6
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [7], ~, Str], # 8
  [Region, {eval_entry: 0, eval_want: list}, [6]], # 9
  [Phi, {region: 9}, [6, 1], ~, List], # 10
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [8, 10, 6], ~, Str], # 11
  [Concat, ~, [2, 11], ~, Str], # 12
  [Constant, {const_type: string, value: "] "}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [6], 9, Scalar], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [14, 16], ~, Str], # 17
  [Print, ~, [17], 15, Scalar], # 18
  [Return, {implicit: true}, [1], 18], # 19
  [ArrayLiteral, {sigil: "@", symbol: r}, [10], ~, Array]]} # 20
main::__PROGRAM__::__SORTCMP__:1: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: a}, [1], ~, Scalar], # 2
  [Coerce, {from_repr: Scalar, to_repr: Num}, [2], ~, Num], # 3
  [EntryDef, {package: main, sigil: $, symbol: b}, [1], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [NumCmp, ~, [3, 5], ~, Int], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [NumEq, ~, [3, 7], ~, Boolean], # 8
  [If, ~, [0, 8], 0], # 9
  [Proj, {index: 1}, [9]], # 10
  [Constant, {const_type: string, value: "boom\n"}, ~, ~, Str], # 11
  [Proj, {index: 0}, [9]], # 12
  [Unwind, ~, [11], 12], # 13
  [Region, {head: 9}, [10, 13]], # 14
  [Return, {implicit: true}, [6], 14]]} # 15
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
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: args}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [HashLiteral, ~, [2, 3], 0, HashRef], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: direct, name: main::repr, param_names: [], want: list}, [4, 5], 4, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 8
  [HashLiteral, ~, ~, 6, HashRef], # 9
  [Call, {dispatch_kind: direct, name: main::repr, param_names: [], want: list}, [9, 5], 9, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [HashLiteral, ~, ~, 10, HashRef], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [Call, {dispatch_kind: direct, name: main::repr, param_names: [], want: list}, [12, 13], 12, Str], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Print, ~, [7, 8, 11, 8, 15, 16], 14, Scalar], # 17
  [Return, {implicit: true}, [1], 17]]} # 18
main::repr: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: sig}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: args}, ~, ~, Str], # 3
  [MemStart], # 4
  [Subscript, {kind: hash}, [2, 3, 4], ~, Scalar], # 5
  [Coerce, {from_repr: Scalar, to_repr: Num}, [5], ~, Num], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Add, ~, [6, 7], ~, Num], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [PadAccess, {sigil: $, symbol: want}, ~, ~, Unknown], # 10
  [If, ~, [0, 10], 0], # 11
  [Proj, {index: 0}, [11]], # 12
  [Defined, ~, [5], ~, Boolean], # 13
  [Not, ~, [13], ~, Boolean], # 14
  [If, ~, [12, 14], 12], # 15
  [Proj, {index: 1}, [15]], # 16
  [Proj, {index: 1}, [11]], # 17
  [Region, {head: 11}, [16, 17]], # 18
  [Phi, {predecessors: [12, 17], region: 18}, [8, 9], ~, Num], # 19
  [Proj, {index: 0}, [15]], # 20
  [Region, ~, [20, 18]], # 21
  [Phi, {predecessors: [20, 18], region: 21}, [1, 19], ~, Str], # 22
  [Return, ~, [22], 21], # 23
  [ArgsSource, ~, ~, ~, Array], # 24
  [Assign, {targets: 2}, [2, 10, 24], ~, List]]} # 25
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
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: direct, name: main::count, param_names: [], want: list}, [2, 3, 4, 3, 5], 0, Int], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
main::count: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 31], ~, Int], # 3
  [Proj, {index: 1}, [2]], # 4
  [PadAccess, {sigil: "%", symbol: seen}, ~, ~, Unknown], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [Phi, {region: 2}, [1, 34], ~, Int], # 7
  [MemStart], # 8
  [Phi, {memory: true, region: 2}, [8, 32], ~, Unknown], # 9
  [Subscript, {kind: array}, [6, 7, 9], ~, Scalar], # 10
  [Subscript, {kind: hash}, [5, 10], ~, Scalar], # 11
  [Proj, {index: 0}, [2]], # 12
  [Coerce, {from_repr: Scalar, to_repr: Num}, [10], ~, Num], # 13
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 14
  [NumGt, ~, [13, 14], ~, Boolean], # 15
  [If, ~, [12, 15], 12], # 16
  [Proj, {index: 0}, [16]], # 17
  [Subscript, {kind: hash}, [5, 10, 9], 17, Scalar], # 18
  [Increment, ~, [18], ~, Scalar], # 19
  [Assign, ~, [11, 19], 18, Scalar], # 20
  [Proj, {index: 1}, [16]], # 21
  [Region, {head: 16}, [20, 21]], # 22
  [DefinedOr, ~, [18, 1], ~, Scalar], # 23
  [Phi, {predecessors: [17, 21], region: 22}, [23, 15], ~, Scalar], # 24
  [If, ~, [22, 24], 22], # 25
  [Proj, {index: 0}, [25]], # 26
  [Region, {head: 2}, [4, 26]], # 27
  [Return, ~, [3], 27], # 28
  [Count, ~, [6, 9], ~, Int], # 29
  [NumGt, ~, [29, 7], 2, Boolean], # 30
  [Add, ~, [3, 14], ~, Int], # 31
  [Phi, {memory: true, predecessors: [17, 21], region: 22}, [20, 9], ~, Unknown], # 32
  [Phi, {memory: true, region: 27}, [9, 32], ~, Unknown], # 33
  [Add, ~, [7, 14], ~, Int], # 34
  [Proj, {index: 1}, [25]], # 35
  [Count, ~, [6, 8], ~, Int]]} # 36
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
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: U}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: V}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 4
  [Call, {dispatch_kind: direct, name: main::unknowns, param_names: [], want: list}, [2, 1, 3, 4, 2], 0, Int], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, Scalar], # 8
  [Return, {implicit: true}, [1], 8]]} # 9
main::unknowns: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 34], ~, Int], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Return, ~, [3], 5], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [MemStart], # 8
  [Count, ~, [7, 8], ~, Int], # 9
  [Phi, {region: 2}, [1, 35], ~, Int], # 10
  [NumGt, ~, [9, 10], 2, Boolean], # 11
  [Proj, {index: 0}, [2]], # 12
  [Subscript, {kind: array}, [7, 10, 8], ~, Scalar], # 13
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
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 5
  [Call, {dispatch_kind: direct, name: main::upto_false, param_names: [], want: list}, [2, 3, 4, 5], 0, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
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
  [Subscript, {kind: array}, [6, 8, 9], ~, Scalar], # 10
  [If, ~, [5, 10], 5], # 11
  [Proj, {index: 1}, [11]], # 12
  [Region, {head: 2}, [4, 12]], # 13
  [Return, ~, [3], 13], # 14
  [Count, ~, [6, 9], ~, Int], # 15
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
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: string, value: "%x"}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, name: main::pairs, param_names: [], want: list}, [2, 3, 4, 5, 6], 0, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [8, 9], 7, Scalar], # 10
  [Return, {implicit: true}, [1], 10]]} # 11
main::pairs: {start: 0, returns: [35], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ", "}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: o}, ~, ~, Unknown], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Loop, {bound: each}, [0], 0], # 5
  [Phi, {region: 5}, [4, 41], ~, Int], # 6
  [MemStart], # 7
  [Subscript, {kind: array}, [3, 6, 7], ~, Scalar], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 12
  [Add, ~, [6, 12], ~, Int], # 13
  [Subscript, {kind: array}, [3, 13, 7], ~, Scalar], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Concat, ~, [11, 15], ~, Str], # 16
  [Proj, {index: 0}, [5]], # 17
  [Defined, ~, [8], ~, Boolean], # 18
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 19
  [RegexMatch, {flags: "", pattern: "^%(\\w+)$"}, [19], ~, Boolean], # 20
  [And, ~, [18, 20], ~, Boolean], # 21
  [If, ~, [17, 21], 17], # 22
  [Proj, {index: 1}, [22]], # 23
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 16, 7], 23, Int], # 24
  [Constant, {const_type: string, value: "spread "}, ~, ~, Str], # 25
  [RegexCapture, {"n": 1}, [20], ~, Str], # 26
  [Concat, ~, [25, 26], ~, Str], # 27
  [Proj, {index: 0}, [22]], # 28
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 27, 7], 28, Int], # 29
  [Region, {head: 5}, [24, 29]], # 30
  [Phi, {memory: true, predecessors: [23, 28], region: 30}, [24, 29], ~, Int], # 31
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 2, 31], ~, Str], # 32
  [Proj, {index: 1}, [5]], # 33
  [Region, {head: 5}, [33]], # 34
  [Return, ~, [32], 34], # 35
  [Count, ~, [3, 7], ~, Int], # 36
  [NumLt, ~, [6, 36], 5, Boolean], # 37
  [Subtract, ~, [6, 12], ~, Int], # 38
  [Phi, {predecessors: [23, 28], region: 30}, [6, 38], ~, Int], # 39
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 40
  [Add, ~, [39, 40], ~, Int]]} # 41
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
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [PadAccess, {sigil: "%", symbol: h}, ~, ~, Unknown], # 3
  [Ref, ~, [3], ~, Unknown], # 4
  [Constant, {const_type: string, value: "+"}, ~, ~, Str], # 5
  [Call, {dispatch_kind: direct, name: main::helpers, param_names: [], want: void}, [4, 5], 0, Int], # 6
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [3, 6], ~, List], # 7
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [7, 6], ~, List], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [2, 8, 6], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [9, 10], 6, Scalar], # 11
  [Return, {implicit: true}, [1], 11]]} # 12
main::helpers: {start: 0, returns: [24], nodes: [
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
  [Proj, {index: 0}, [6]], # 12
  [Constant, {const_type: string, value: plus}, ~, ~, Str], # 13
  [MemStart], # 14
  [Exists, {kind: hash}, [8, 13, 14], ~, Boolean], # 15
  [If, ~, [12, 15], 12], # 16
  [Proj, {index: 0}, [16]], # 17
  [Subscript, {kind: hash}, [8, 13], ~, Scalar], # 18
  [Proj, {index: 1}, [16]], # 19
  [Assign, ~, [18, 1], 19, Int], # 20
  [Region, {head: 16}, [17, 20]], # 21
  [Assign, ~, [10, 11], 21, Int], # 22
  [Region, {head: 6}, [7, 22]], # 23
  [Return, ~, [1], 23], # 24
  [Phi, {memory: true, predecessors: [7, 12], region: 23}, [14, 22], ~, Unknown], # 25
  [Phi, {memory: true, predecessors: [17, 19], region: 21}, [14, 20], ~, Unknown], # 26
  [ArgsSource, ~, ~, ~, Array], # 27
  [Assign, {targets: 2}, [8, 2, 27], ~, List]]} # 28
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
  [PadAccess, {sigil: "@", symbol: a}, ~, ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [MemStart], # 6
  [PadAccess, {sigil: "%", symbol: h}, ~, ~, Unknown], # 7
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 8
  [Subscript, {kind: hash}, [7, 8], ~, Scalar], # 9
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 10
  [Subscript, {kind: hash}, [7, 8, 6], 0, Scalar], # 11
  [Defined, ~, [11], ~, Boolean], # 12
  [If, ~, [11, 12], 11], # 13
  [Proj, {index: 1}, [13]], # 14
  [Assign, ~, [9, 1], 14, Undef], # 15
  [Assign, ~, [9, 10], 15, Int], # 16
  [Proj, {index: 0}, [13]], # 17
  [Region, {head: 13}, [17, 16]], # 18
  [Phi, {memory: true, predecessors: [17, 14], region: 18}, [6, 16], ~, Unknown], # 19
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 20
  [Subscript, {kind: hash}, [7, 20], ~, Scalar], # 21
  [Subscript, {kind: hash}, [7, 20, 19], 18, Scalar], # 22
  [Defined, ~, [22], ~, Boolean], # 23
  [If, ~, [22, 23], 22], # 24
  [Proj, {index: 1}, [24]], # 25
  [Assign, ~, [21, 1], 25, Undef], # 26
  [Proj, {index: 0}, [24]], # 27
  [Region, {head: 24}, [27, 26]], # 28
  [Phi, {memory: true, predecessors: [27, 25], region: 28}, [19, 26], ~, Unknown], # 29
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 30
  [If, ~, [28, 22], 28], # 31
  [Proj, {index: 1}, [31]], # 32
  [Assign, ~, [21, 30], 32, Int], # 33
  [Proj, {index: 0}, [31]], # 34
  [Region, {head: 31}, [34, 33]], # 35
  [Phi, {memory: true, predecessors: [34, 32], region: 35}, [29, 33], ~, Unknown], # 36
  [Subscript, {kind: hash}, [7, 20, 36], 35, Scalar], # 37
  [Defined, ~, [37], ~, Boolean], # 38
  [If, ~, [37, 38], 37], # 39
  [Proj, {index: 1}, [39]], # 40
  [Assign, ~, [21, 1], 40, Undef], # 41
  [Proj, {index: 0}, [39]], # 42
  [Region, {head: 39}, [42, 41]], # 43
  [Phi, {memory: true, predecessors: [42, 40], region: 43}, [36, 41], ~, Unknown], # 44
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 45
  [If, ~, [43, 37], 43], # 46
  [Proj, {index: 0}, [46]], # 47
  [Assign, ~, [21, 45], 47, Int], # 48
  [Proj, {index: 1}, [46]], # 49
  [Region, {head: 46}, [49, 48]], # 50
  [Phi, {memory: true, predecessors: [49, 47], region: 50}, [44, 48], ~, Unknown], # 51
  [Subscript, {kind: array}, [4, 5, 51], 50, Scalar], # 52
  [Defined, ~, [52], ~, Boolean], # 53
  [If, ~, [52, 53], 52], # 54
  [Proj, {index: 0}, [54]], # 55
  [Subscript, {kind: array}, [4, 5], ~, Scalar], # 56
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 57
  [Proj, {index: 1}, [54]], # 58
  [Assign, ~, [56, 1], 58, Undef], # 59
  [Assign, ~, [56, 57], 59, Int], # 60
  [Region, {head: 54}, [55, 60]], # 61
  [Loop, {bound: entry}, [61], 61], # 62
  [Phi, {region: 62}, [3, 89], ~, Array], # 63
  [Phi, {memory: true, predecessors: [55, 58], region: 61}, [51, 60], ~, Unknown], # 64
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [2, 63, 64], ~, Str], # 65
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 66
  [Count, ~, [4, 64], ~, Int], # 67
  [Coerce, {from_repr: Int, to_repr: Str}, [67], ~, Str], # 68
  [Subscript, {kind: array}, [4, 5, 64], ~, Scalar], # 69
  [Coerce, {from_repr: Unknown, to_repr: Str}, [69], ~, Str], # 70
  [Concat, ~, [66, 70], ~, Str], # 71
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 72
  [Concat, ~, [71, 72], ~, Str], # 73
  [Proj, {index: 1}, [62]], # 74
  [Region, {head: 62}, [74]], # 75
  [Print, ~, [65, 66, 68, 73], 75, Scalar], # 76
  [Return, {implicit: true}, [1], 76], # 77
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [7, 64], ~, List], # 78
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [78, 64], ~, List], # 79
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 80
  [Phi, {region: 62}, [80, 91], ~, Int], # 81
  [Subscript, {kind: array}, [79, 81, 64], ~, Scalar], # 82
  [Subscript, {kind: hash}, [7, 82, 64], ~, Scalar], # 83
  [Coerce, {from_repr: Unknown, to_repr: Str}, [83], ~, Str], # 84
  [Coerce, {from_repr: Unknown, to_repr: Str}, [82], ~, Str], # 85
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 86
  [Concat, ~, [85, 86], ~, Str], # 87
  [Concat, ~, [87, 84], ~, Str], # 88
  [ListAppend, {collector: map}, [63, 88], ~, Array], # 89
  [Count, ~, [79, 64], ~, Int], # 90
  [Add, ~, [81, 5], ~, Int], # 91
  [NumGt, ~, [90, 81], 62, Boolean], # 92
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
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [5], 3, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [4, 7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
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
  [Subscript, {kind: array}, [12, 13, 14], ~, Scalar], # 15
  [Coerce, {from_repr: Scalar, to_repr: Num}, [15], ~, Num], # 16
  [NumEq, ~, [4, 16], ~, Boolean], # 17
  [If, ~, [11, 17], 11], # 18
  [Proj, {index: 0}, [18]], # 19
  [Proj, {index: 1}, [3]], # 20
  [Region, {head: 3}, [20]], # 21
  [Region, ~, [19, 21]], # 22
  [Phi, {predecessors: [19, 21], region: 22}, [6, 7], ~, Str], # 23
  [Return, ~, [23], 22], # 24
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
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [8, 9, 10], 0, Int], # 11
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [11], ~, Scalar], # 12
  [Coerce, {from_repr: Scalar, to_repr: Str}, [12], ~, Str], # 13
  [PostfixDeref, {sigil: "@"}, [8, 11], ~, Array], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [13, 14, 11], ~, Str], # 15
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [ArrayLiteral, ~, ~, ~, Array], # 18
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 19
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 20
  [ArrayLiteral, ~, [19, 20], ~, Array], # 21
  [TernaryExpr, ~, [2, 18, 21], ~, Array], # 22
  [Count, ~, [22, 11], ~, Int], # 23
  [Coerce, {from_repr: Int, to_repr: Str}, [23], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [Print, ~, [17, 24, 25], 11, Scalar], # 26
  [Return, {implicit: true}, [1], 26]]} # 27
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
  [EntryWrite, ~, [2, 3, 4], 0, Unknown], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 5, Unknown], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [8], 6, Unknown], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " c="}, ~, ~, Str], # 11
  [EntryDef, {package: main, sigil: $, symbol: c}, [9], ~, Int], # 12
  [Coerce, {from_repr: Int, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [11, 13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [Print, ~, [7, 10, 16], 9, Scalar], # 17
  [Return, {implicit: true}, [1], 17]]} # 18
main::f: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Unknown], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Count, {presence_test: true}, [2, 3], ~, Int], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [NumGt, ~, [4, 5], ~, Boolean], # 6
  [If, ~, [0, 6], 0], # 7
  [Proj, {index: 1}, [7]], # 8
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, ~, 8, Int], # 9
  [Proj, {index: 0}, [7]], # 10
  [Region, {head: 7}, [10, 9]], # 11
  [Phi, {predecessors: [10, 8], region: 11}, [1, 9], ~, Unknown], # 12
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 13
  [Add, ~, [12, 13], ~, Unknown], # 14
  [Return, {implicit: true}, [14], 11], # 15
  [Phi, {memory: true, predecessors: [10, 8], region: 11}, [3, 9], ~, Unknown]]} # 16
main::g: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [EntryDef, {package: main, sigil: $, symbol: c}, ~, ~, Scalar], # 2
  [MemStart], # 3
  [EntryDef, {package: main, sigil: $, symbol: c}, [3], ~, Scalar], # 4
  [Increment, ~, [4], ~, Scalar], # 5
  [EntryWrite, ~, [2, 5, 3], 0, Unknown], # 6
  [Return, {implicit: true}, [1], 6]]} # 7
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
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
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::__PROGRAM__::__ANON__:1:2, param_names: [], want: list}, [2], 0, Num], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, name: main::__PROGRAM__::__ANON__:1:2, param_names: [], want: list}, [6], 3, Num], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [4, 5, 8, 9], 7, Scalar], # 10
  [Return, {implicit: true}, [1], 10]]} # 11
main::__PROGRAM__::__ANON__:1:2: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: x}, [1], ~, Unknown], # 2
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Unknown], # 3
  [Assign, ~, [2, 3], 0, Unknown], # 4
  [PadAccess, {sigil: $, symbol: x}, [4], ~, Unknown], # 5
  [Call, {dispatch_kind: direct, name: main::b::__ANON__:1:2, param_names: [], want: scalar}, [5], 4, Num], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Multiply, ~, [6, 7], ~, Num], # 8
  [Return, {implicit: true}, [8], 6]]} # 9
main::b::__ANON__:1:2: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Num], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Add, ~, [1, 2], ~, Num], # 3
  [Return, {implicit: true}, [3], 0]]} # 4
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
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
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, List], # 2
  [ArrayLiteral, ~, [2], ~, Array], # 3
  [Count, ~, [3, 2], ~, Int], # 4
  [Coerce, {from_repr: Int, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, ~, 2, Undef], # 8
  [ArrayLiteral, ~, [8], ~, Array], # 9
  [Count, ~, [9, 8], ~, Int], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [Concat, ~, [7, 11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [Print, ~, [14], 8, Scalar], # 15
  [Return, {implicit: true}, [1], 15]]} # 16
main::f: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, List], # 4
  [Coerce, {from_repr: List, to_repr: Scalar}, [3], ~, Scalar], # 5
  [Return, {implicit: true}, [4, 5], 0]]} # 6
main::g: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, {implicit: true, valueless: true}, [1], 0]]} # 2
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
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [2], ~, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [ArrayLiteral, {sigil: "@", symbol: b}, [5, 6, 7], ~, Array], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: reverse, param_names: []}, [8, 2], ~, List], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [4, 9, 2], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Print, ~, [12], 0, Scalar], # 13
  [Return, {implicit: true}, [1], 13], # 14
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
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 4
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3, 4], 0, Scalar], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, Scalar], # 8
  [Return, {implicit: true}, [1], 8]]} # 9
main::f: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 14], ~, Scalar], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Return, ~, [3], 5], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [MemStart], # 8
  [Count, ~, [7, 8], ~, Int], # 9
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 10
  [Phi, {region: 2}, [10, 16], ~, Int], # 11
  [NumGt, ~, [9, 11], 2, Boolean], # 12
  [Proj, {index: 0}, [2]], # 13
  [Subscript, {kind: array}, [7, 11, 8], ~, Scalar], # 14
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
main::__PROGRAM__: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: void}, ~, 0, Scalar], # 2
  [Return, {implicit: true}, [1], 2]]} # 3
main::f: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: a}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 3, 4, 5], 0, Int], # 6
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
  [Subscript, {kind: hash}, [12, 11, 16], ~, Scalar], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Concat, ~, [10, 18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [Print, ~, [21], 15, Scalar], # 22
  [Return, {implicit: true}, [22], 22], # 23
  [Count, ~, [2, 6], ~, Int], # 24
  [Count, ~, [2, 13], ~, Int], # 25
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 26
  [Phi, {region: 7}, [26, 29], ~, Int], # 27
  [Subscript, {kind: array}, [2, 27, 13], ~, Scalar], # 28
  [Add, ~, [27, 3], ~, Int], # 29
  [NumGt, ~, [25, 27], 7, Boolean], # 30
  [Proj, {index: 0}, [7]], # 31
  [Subscript, {kind: hash}, [12, 11], ~, Int], # 32
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 33
  [Assign, ~, [32, 33], 31, Int], # 34
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
  [PadAccess, {shared: 1, sigil: "@", symbol: arr}, [2], ~, Unknown], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [ArrayLiteral, {sigil: "@", symbol: arr}, [4, 5], 0, Array], # 6
  [Assign, ~, [3, 6], 6, List], # 7
  [Call, {dispatch_kind: direct, name: main::__PROGRAM__::__ANON__:1:3, param_names: [], want: list}, ~, 7, Int], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [9, 10], 8, Scalar], # 11
  [Return, {implicit: true}, [1], 11]]} # 12
main::__PROGRAM__::__ANON__:1:3: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: arr}, ~, ~, Scalar], # 1
  [MemStart], # 2
  [Count, ~, [1, 2], ~, Int], # 3
  [Return, {implicit: true}, [3], 0]]} # 4
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
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
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 40], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Phi, {region: 3}, [7, 37], ~, Int], # 8
  [Coerce, {from_repr: Int, to_repr: Str}, [8], ~, Str], # 9
  [Concat, ~, [6, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Proj, {index: 1}, [3]], # 13
  [Region, {head: 3}, [13]], # 14
  [Print, ~, [12], 14, Scalar], # 15
  [Return, {implicit: true}, [1], 15], # 16
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 17
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 18
  [Phi, {region: 3}, [18, 24], ~, Int], # 19
  [NumGt, ~, [17, 19], 3, Boolean], # 20
  [Proj, {index: 0}, [3]], # 21
  [NumGt, ~, [19, 18], ~, Boolean], # 22
  [If, ~, [21, 22], 21], # 23
  [Add, ~, [19, 18], ~, Int], # 24
  [Proj, {index: 0}, [23]], # 25
  [Loop, {bound: each}, [25], 25], # 26
  [Phi, {region: 26}, [7, 30], ~, Int], # 27
  [NumLt, ~, [27, 19], 26, Boolean], # 28
  [Proj, {index: 1}, [23]], # 29
  [Add, ~, [27, 18], ~, Int], # 30
  [Proj, {index: 1}, [26]], # 31
  [Region, {head: 26}, [31]], # 32
  [Region, {head: 23}, [32, 29]], # 33
  [Phi, {region: 26}, [8, 35], ~, Int], # 34
  [Add, ~, [34, 27], ~, Int], # 35
  [Proj, {index: 0}, [26]], # 36
  [Phi, {predecessors: [25, 29], region: 33}, [34, 8], ~, Int], # 37
  [Coerce, {from_repr: Int, to_repr: Str}, [34], ~, Str], # 38
  [Concat, ~, [4, 38], ~, Str], # 39
  [Phi, {predecessors: [25, 29], region: 33}, [39, 4], ~, Str]]} # 40
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
main::__PROGRAM__: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: "@", symbol: r}, ~, ~, Unknown], # 3
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Loop, {bound: entry}, [0], 0], # 6
  [Phi, {region: 6}, [5, 31], ~, Int], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [Multiply, ~, [7, 8], ~, Int], # 9
  [Proj, {index: 0}, [6]], # 10
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 11
  [Modulo, ~, [7, 11], ~, Int], # 12
  [If, ~, [10, 12], 10], # 13
  [Proj, {index: 1}, [13]], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [3, 9, 2], 14, Int], # 15
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [3, 4, 15], 15, Int], # 16
  [Proj, {index: 0}, [13]], # 17
  [Region, {head: 13}, [17, 16]], # 18
  [Phi, {memory: true, predecessors: [17, 14], region: 18}, [2, 16], ~, Unknown], # 19
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [19], ~, Scalar], # 20
  [Coerce, {from_repr: Scalar, to_repr: Str}, [20], ~, Str], # 21
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [21, 3, 19], ~, Str], # 22
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 23
  [Concat, ~, [22, 23], ~, Str], # 24
  [Proj, {index: 1}, [6]], # 25
  [Region, {head: 6}, [25]], # 26
  [Print, ~, [24], 26, Scalar], # 27
  [Return, {implicit: true}, [1], 27], # 28
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 29
  [NumGt, ~, [29, 7], 6, Boolean], # 30
  [Add, ~, [7, 5], ~, Int]]} # 31
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
  [PadAccess, {sigil: $, symbol: s}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: a1b2c}, ~, ~, Str], # 4
  [Assign, ~, [3, 4], 0, Str], # 5
  [PadAccess, {sigil: $, symbol: s}, [5], ~, Unknown], # 6
  [RegexSubst, {flags: g, pattern: "(\\d)", replacement: "", replacement_body: main::__PROGRAM__::__SUBSTREPL__:1}, [6, 5], 5, Str], # 7
  [PadAccess, {sigil: $, symbol: s}, [7], ~, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Print, ~, [11], 7, Scalar], # 12
  [Return, {implicit: true}, [1], 12]]} # 13
main::__PROGRAM__::__SUBSTREPL__:1: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [RegexMatch, {flags: g, pattern: "(\\d)"}, ~, ~, Boolean], # 1
  [RegexCapture, {"n": 1}, [1], ~, Str], # 2
  [Coerce, {from_repr: Str, to_repr: Num}, [2], ~, Num], # 3
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 4
  [Multiply, ~, [3, 4], ~, Num], # 5
  [Return, {implicit: true}, [5], 0]]} # 6
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
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a1}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b1}, ~, ~, Str], # 3
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3], ~, Array], # 4
  [Call, {dispatch_kind: direct, name: main::e, param_names: [], want: list}, [4], 0, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [5], ~, Scalar], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [PostfixDeref, {sigil: "@"}, [4, 5], ~, Array], # 10
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [9, 10, 5], ~, Str], # 11
  [Concat, ~, [7, 11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [Print, ~, [6, 14], 5, Scalar], # 15
  [Return, {implicit: true}, [1], 15]]} # 16
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
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 4, 9], ~, Str], # 10
  [Return, {implicit: true}, [10], 8], # 11
  [ArgsSource, ~, ~, ~, Array], # 12
  [Count, ~, [12, 6], ~, Int], # 13
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 14
  [Phi, {region: 3}, [14, 25], ~, Int], # 15
  [NumGt, ~, [13, 15], 3, Boolean], # 16
  [Proj, {index: 0}, [3]], # 17
  [Subscript, {kind: array}, [12, 15], ~, Scalar], # 18
  [Ref, ~, [18], ~, ScalarRef], # 19
  [LocalAlias, {name: _}, [19], 17, Unknown], # 20
  [Subscript, {kind: array}, [12, 15, 6], ~, Scalar], # 21
  [Call, {dispatch_kind: direct, name: main::e::__ANON__:1:1, param_names: [], want: list}, [21], 20, Str], # 22
  [ListAppend, {collector: map}, [4, 22], ~, Array], # 23
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 24
  [Add, ~, [15, 24], ~, Int], # 25
  [Count, ~, [12, 5], ~, Int]]} # 26
main::e::__ANON__:1:1: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: s}, [2], ~, Unknown], # 3
  [Parameter, {index: 0, name: $s, sigil: $}, ~, ~, Unknown], # 4
  [Assign, ~, [3, 4], 0, Unknown], # 5
  [PadAccess, {sigil: $, symbol: s}, [5], ~, Unknown], # 6
  [RegexSubst, {flags: u, pattern: "1", replacement: "9"}, [6, 5], 5, Str], # 7
  [PadAccess, {sigil: $, symbol: s}, [7], ~, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Concat, ~, [1, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Return, {implicit: true}, [12], 7]]} # 13
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
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
main::__PROGRAM__: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: void}, ~, 0, Scalar], # 2
  [Return, {implicit: true}, [1], 2]]} # 3
main::f: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "r="}, ~, ~, Str], # 1
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 2
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 3
  [MemStart], # 4
  [PadAccess, {sigil: $, symbol: i}, [4], ~, Unknown], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Assign, ~, [5, 6], 0, Int], # 7
  [Loop, {bound: each}, [7], 7], # 8
  [Proj, {index: 1}, [8]], # 9
  [Region, {head: 8}, [9]], # 10
  [Region, {eval_entry: 0}, [10]], # 11
  [Phi, {region: 11}, [2, 3], ~, Scalar], # 12
  [Coerce, {from_repr: Scalar, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [1, 13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [Print, ~, [16], 11, Scalar], # 17
  [Return, {implicit: true}, [17], 17], # 18
  [Phi, {memory: true, region: 8}, [7, 25], ~, Scalar], # 19
  [PadAccess, {sigil: $, symbol: i}, [19], ~, Num], # 20
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 21
  [NumLt, ~, [20, 21], 8, Boolean], # 22
  [Proj, {index: 0}, [8]], # 23
  [Increment, ~, [20], ~, Scalar], # 24
  [Assign, ~, [20, 24], 23, Scalar], # 25
  [Phi, {memory: true, region: 10}, [19], ~, Scalar], # 26
  [PadAccess, {sigil: $, symbol: i}, [25], ~, Str], # 27
  [Coerce, {from_repr: Unknown, to_repr: Str}, [27], ~, Str], # 28
  [Concat, ~, [28, 15], ~, Str], # 29
  [Print, ~, [29], 25, Scalar]]} # 30
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
main::__PROGRAM__: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 30], ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Phi, {region: 3}, [5, 26], ~, Int], # 6
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
  [Print, ~, [21], 18, Scalar], # 22
  [Return, {implicit: true}, [1], 22], # 23
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 24
  [NumGt, ~, [24, 6], 3, Boolean], # 25
  [Add, ~, [6, 5], ~, Int], # 26
  [Proj, {index: 0}, [12]], # 27
  [Proj, {index: 1}, [16]], # 28
  [Region, {head: 3}, [27, 28]], # 29
  [Phi, {predecessors: [27, 28], region: 29}, [4, 8], ~, Str]]} # 30
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
main::__PROGRAM__: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 7], ~, Str], # 4
  [Proj, {index: 0}, [3]], # 5
  [Loop, {bound: entry}, [5], 5], # 6
  [Phi, {region: 6}, [4, 16], ~, Str], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Phi, {region: 3}, [8, 32], ~, Int], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Concat, ~, [7, 10], ~, Str], # 11
  [Phi, {region: 6}, [8, 34], ~, Int], # 12
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
  [Print, ~, [26], 23, Scalar], # 27
  [Return, {implicit: true}, [1], 27], # 28
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 29
  [NumGt, ~, [29, 9], 3, Boolean], # 30
  [NumGt, ~, [29, 12], 6, Boolean], # 31
  [Add, ~, [9, 8], ~, Int], # 32
  [Proj, {index: 1}, [6]], # 33
  [Add, ~, [12, 8], ~, Int], # 34
  [Region, {head: 6}, [33]], # 35
  [Proj, {index: 1}, [21]]]} # 36
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
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 38], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Proj, {index: 1}, [3]], # 7
  [Region, {head: 3}, [7]], # 8
  [Print, ~, [6], 8, Scalar], # 9
  [Return, {implicit: true}, [1], 9], # 10
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 11
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 12
  [Phi, {region: 3}, [12, 19], ~, Int], # 13
  [NumGt, ~, [11, 13], 3, Boolean], # 14
  [Proj, {index: 0}, [3]], # 15
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 16
  [NumEq, ~, [13, 16], ~, Boolean], # 17
  [If, ~, [15, 17], 15], # 18
  [Add, ~, [13, 12], ~, Int], # 19
  [Coerce, {from_repr: Int, to_repr: Str}, [13], ~, Str], # 20
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 21
  [NumEq, ~, [13, 21], ~, Boolean], # 22
  [Proj, {index: 0}, [18]], # 23
  [Proj, {index: 1}, [18]], # 24
  [Concat, ~, [4, 20], ~, Str], # 25
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 26
  [Concat, ~, [25, 26], ~, Str], # 27
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 28
  [Concat, ~, [25, 28], ~, Str], # 29
  [If, ~, [24, 22], 24], # 30
  [Proj, {index: 1}, [30]], # 31
  [Region, {head: 3}, [31, 23]], # 32
  [Phi, {predecessors: [31, 23], region: 32}, [27, 29], ~, Str], # 33
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 34
  [Concat, ~, [25, 34], ~, Str], # 35
  [Proj, {index: 0}, [30]], # 36
  [Region, {head: 3}, [32, 36]], # 37
  [Phi, {region: 37}, [33, 35], ~, Str]]} # 38
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
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [Loop, {bound: each}, [0], 0], # 3
  [Phi, {region: 3}, [2, 47], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Phi, {region: 3}, [7, 41], ~, Int], # 8
  [Coerce, {from_repr: Int, to_repr: Str}, [8], ~, Str], # 9
  [Concat, ~, [6, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Proj, {index: 1}, [3]], # 13
  [Region, {head: 3}, [13]], # 14
  [Print, ~, [12], 14, Scalar], # 15
  [Return, {implicit: true}, [1], 15], # 16
  [Phi, {region: 3}, [7, 22], ~, Int], # 17
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 18
  [NumLt, ~, [17, 18], 3, Boolean], # 19
  [Proj, {index: 0}, [3]], # 20
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 21
  [Add, ~, [17, 21], ~, Int], # 22
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 23
  [NumEq, ~, [22, 23], ~, Boolean], # 24
  [If, ~, [20, 24], 20], # 25
  [Proj, {index: 0}, [25]], # 26
  [Proj, {index: 1}, [25]], # 27
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown], # 28
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 29
  [Assign, {targets: 2}, [28, 29, 2, 7], ~, List], # 30
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 31
  [NumEq, ~, [22, 31], ~, Boolean], # 32
  [If, ~, [27, 32], 27], # 33
  [Proj, {index: 1}, [33]], # 34
  [Region, {head: 3}, [34, 26]], # 35
  [Add, ~, [8, 21], ~, Int], # 36
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 37
  [Add, ~, [36, 37], ~, Int], # 38
  [Proj, {index: 0}, [33]], # 39
  [Region, {head: 3}, [35, 39]], # 40
  [Phi, {region: 40}, [36, 38], ~, Int], # 41
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 42
  [Concat, ~, [4, 42], ~, Str], # 43
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 44
  [Concat, ~, [4, 44], ~, Str], # 45
  [Phi, {predecessors: [34, 26], region: 35}, [43, 45], ~, Str], # 46
  [Phi, {region: 40}, [46, 4], ~, Str]]} # 47
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
  [Subscript, {kind: hash}, [1, 2, 3], ~, Scalar], # 4
  [Return, {implicit: true}, [4], 0]]} # 5
Box::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {shared: 1, sigil: $, symbol: made}, [2], ~, Unknown], # 3
  [Increment, ~, [3], ~, Scalar], # 4
  [Assign, ~, [3, 4], 0, Scalar], # 5
  [PadAccess, {shared: 1, sigil: $, symbol: made}, [5], ~, Unknown], # 6
  [HashLiteral, ~, [1, 6], 5, HashRef], # 7
  [Parameter, {index: 0, name: $c, sigil: $}, ~, ~, Unknown], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [7, 8, 5], ~, Unknown], # 9
  [Return, {implicit: true}, [9], 7]]} # 10
K::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Call, {class_name: Box, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 0, Object], # 1
  [Return, {implicit: true}, [1], 1]]} # 2
K::b: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [32], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {shared: 1, sigil: $, symbol: made}, [2], ~, Unknown], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Assign, ~, [3, 4], 0, Int], # 5
  [PackageMark, {package: K}, ~, 5], # 6
  [PackageMark, {package: main}, ~, 6], # 7
  [Call, {class_name: K, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 7, Object], # 8
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 10
  [Call, {class_name: K, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 8, Object], # 11
  [HashLiteral, ~, [9, 10], 11, HashRef], # 12
  [Constant, {const_type: string, value: Box}, ~, ~, Str], # 13
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [12, 13, 11], ~, Unknown], # 14
  [Call, {class_name: K, dispatch_kind: method, name: new, param_names: [b], want: scalar}, [14], 12, Object], # 15
  [Call, {class_name: K, dispatch_kind: method, name: b, param_names: [], want: scalar}, [8], 15, Scalar], # 16
  [Call, {class_name: K, dispatch_kind: method, name: "n", param_names: [], want: list}, [16], 16, Unknown], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Call, {class_name: K, dispatch_kind: method, name: b, param_names: [], want: scalar}, [11], 17, Scalar], # 19
  [Call, {class_name: K, dispatch_kind: method, name: "n", param_names: [], want: list}, [19], 19, Unknown], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Call, {class_name: K, dispatch_kind: method, name: b, param_names: [], want: scalar}, [15], 20, Scalar], # 22
  [Call, {class_name: K, dispatch_kind: method, name: "n", param_names: [], want: list}, [22], 22, Unknown], # 23
  [Coerce, {from_repr: Unknown, to_repr: Str}, [23], ~, Str], # 24
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 25
  [PadAccess, {shared: 1, sigil: $, symbol: made}, [23], ~, Str], # 26
  [Coerce, {from_repr: Unknown, to_repr: Str}, [26], ~, Str], # 27
  [Concat, ~, [25, 27], ~, Str], # 28
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 29
  [Concat, ~, [28, 29], ~, Str], # 30
  [Print, ~, [18, 21, 24, 30], 23, Scalar], # 31
  [Return, {implicit: true}, [1], 31]]} # 32
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: experimental, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
C::add: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [FieldAccess, {field_index: 0, field_stash: C}, ~, ~, Unknown], # 2
  [Parameter, {index: 0, name: $k, sigil: $}, ~, ~, Unknown], # 3
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 4
  [Assign, ~, [4, 1], 0, Int], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
C::n: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 1
  [Call, {dispatch_kind: direct, name: C::n::__ANON__:5:4, param_names: [], want: scalar}, [1], 0, Int], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Call, {dispatch_kind: direct, name: C::n::__ANON__:5:4, param_names: [], want: scalar}, [3], 2, Int], # 4
  [Concat, ~, [2, 4], ~, Str], # 5
  [Return, ~, [5], 4]]} # 6
C::n::__ANON__:5:4: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: C}, ~, ~, Unknown], # 1
  [Parameter, {index: 0, name: $k, sigil: $}, ~, ~, Unknown], # 2
  [MemStart], # 3
  [Exists, {kind: hash}, [1, 2, 3], ~, Boolean], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [TernaryExpr, ~, [4, 5, 6], ~, Int], # 7
  [Return, {implicit: true}, [7], 0]]} # 8
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: C}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [Call, {class_name: C, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 3, Object], # 4
  [Call, {class_name: C, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 4, Object], # 5
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 7
  [Call, {class_name: C, dispatch_kind: method, name: add, param_names: [], want: void}, [4, 7], 5, Int], # 8
  [Call, {class_name: C, dispatch_kind: method, name: add, param_names: [], want: void}, [5, 6], 8, Int], # 9
  [Call, {class_name: C, dispatch_kind: method, name: "n", param_names: [], want: list}, [4], 9, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Call, {class_name: C, dispatch_kind: method, name: "n", param_names: [], want: list}, [5], 10, Str], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [11, 13, 14], 12, Scalar], # 15
  [Return, {implicit: true}, [1], 15]]} # 16
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: experimental, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
K::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
K::bump: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 0, field_stash: K}, [1], ~, Int], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Add, ~, [2, 3], ~, Int], # 4
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Int], # 5
  [Assign, ~, [5, 4], 0, Int], # 6
  [Return, {implicit: true}, [4], 6]]} # 7
K::swap: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 0, field_stash: K}, [1], ~, Int], # 2
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 4
  [Assign, ~, [3, 4], 0, Int], # 5
  [FieldAccess, {field_index: 0, field_stash: K}, [5], ~, Int], # 6
  [Concat, ~, [2, 6], ~, Str], # 7
  [Return, ~, [7], 5]]} # 8
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: K}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [Call, {class_name: K, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 3, Object], # 4
  [Call, {class_name: K, dispatch_kind: method, name: swap, param_names: [], want: list}, [4], 4, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 7
  [Call, {class_name: K, dispatch_kind: method, name: bump, param_names: [], want: list}, [4], 5, Int], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [6, 7, 9, 10], 8, Scalar], # 11
  [Return, {implicit: true}, [1], 11]]} # 12
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: experimental, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
  [Phi, {memory: true, region: 6}, [5, 41], ~, Unknown], # 7
  [Proj, {index: 1}, [6]], # 8
  [Region, {head: 6}, [8]], # 9
  [Phi, {memory: true, region: 9}, [7], ~, Unknown], # 10
  [Loop, {bound: each}, [9], 9], # 11
  [Phi, {memory: true, region: 11}, [10, 50], ~, Unknown], # 12
  [Proj, {index: 1}, [11]], # 13
  [Region, {head: 11}, [13]], # 14
  [Phi, {memory: true, region: 14}, [12], ~, Unknown], # 15
  [Subscript, {kind: hash}, [4, 2, 15], ~, Scalar], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 20
  [HashLiteral, {sigil: "%", symbol: w}, [20, 3], ~, Hash], # 21
  [Subscript, {kind: hash}, [21, 20, 15], ~, Scalar], # 22
  [Coerce, {from_repr: Unknown, to_repr: Str}, [22], ~, Str], # 23
  [Concat, ~, [19, 23], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [Concat, ~, [24, 25], ~, Str], # 26
  [Print, ~, [26], 14, Scalar], # 27
  [Return, {implicit: true}, [1], 27], # 28
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 29
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 30
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 31
  [ArrayLiteral, {sigil: "@", symbol: a}, [29, 30, 31], ~, Array], # 32
  [Count, ~, [32, 7], ~, Int], # 33
  [Phi, {region: 6}, [3, 38], ~, Int], # 34
  [NumGt, ~, [33, 34], 6, Boolean], # 35
  [Proj, {index: 0}, [6]], # 36
  [Subscript, {kind: hash}, [4, 2, 7], 36, Scalar], # 37
  [Add, ~, [34, 29], ~, Int], # 38
  [Increment, ~, [37], ~, Scalar], # 39
  [Subscript, {kind: hash}, [4, 2], ~, Int], # 40
  [Assign, ~, [40, 39], 37, Scalar], # 41
  [Count, ~, [32, 5], ~, Int], # 42
  [Phi, {region: 11}, [3, 51], ~, Int], # 43
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 44
  [NumLt, ~, [43, 44], 11, Boolean], # 45
  [Proj, {index: 0}, [11]], # 46
  [Subscript, {kind: hash}, [21, 20], ~, Int], # 47
  [Subscript, {kind: hash}, [21, 20, 12], 46, Scalar], # 48
  [Increment, ~, [48], ~, Scalar], # 49
  [Assign, ~, [47, 49], 48, Scalar], # 50
  [Add, ~, [43, 29], ~, Int]]} # 51
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
main::__PROGRAM__: {start: 0, returns: [37], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "ok 3 "}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [EntryWrite, ~, [3, 4, 5], 0, Unknown], # 6
  [Loop, {bound: each}, [6], 6], # 7
  [Phi, {region: 7}, [4, 10], ~, Int], # 8
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 9
  [Add, ~, [8, 9], ~, Int], # 10
  [Phi, {memory: true, region: 7}, [6, 12], ~, Unknown], # 11
  [EntryWrite, ~, [3, 10, 11], 7, Unknown], # 12
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 13
  [NumEq, ~, [10, 13], ~, Boolean], # 14
  [If, ~, [12, 14], 12], # 15
  [Proj, {index: 0}, [15]], # 16
  [Region, {head: 7}, [16]], # 17
  [Phi, {memory: true, region: 17}, [12], ~, Unknown], # 18
  [EntryDef, {package: main, sigil: $, symbol: x}, [18], ~, Int], # 19
  [NumEq, ~, [19, 13], ~, Boolean], # 20
  [Constant, {const_type: string, value: "ok 2\n"}, ~, ~, Str], # 21
  [Constant, {const_type: string, value: "not ok 2\n"}, ~, ~, Str], # 22
  [TernaryExpr, ~, [20, 21, 22], ~, Str], # 23
  [Print, ~, [23], 17, Scalar], # 24
  [EntryWrite, ~, [3, 4, 18], 24, Unknown], # 25
  [Loop, {bound: each}, [25], 25], # 26
  [Phi, {memory: true, region: 26}, [25, 41], ~, Unknown], # 27
  [Proj, {index: 1}, [26]], # 28
  [Region, {head: 26}, [28]], # 29
  [Phi, {memory: true, region: 29}, [27], ~, Unknown], # 30
  [EntryDef, {package: main, sigil: $, symbol: x}, [30], ~, Int], # 31
  [Coerce, {from_repr: Int, to_repr: Str}, [31], ~, Str], # 32
  [Concat, ~, [2, 32], ~, Str], # 33
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 34
  [Concat, ~, [33, 34], ~, Str], # 35
  [Print, ~, [35], 29, Scalar], # 36
  [Return, {implicit: true}, [1], 36], # 37
  [Phi, {region: 26}, [4, 39], ~, Int], # 38
  [Add, ~, [38, 9], ~, Int], # 39
  [Proj, {index: 0}, [26]], # 40
  [EntryWrite, ~, [3, 39, 27], 40, Unknown], # 41
  [NumNe, ~, [38, 13], 26, Boolean], # 42
  [Proj, {index: 1}, [15]]]} # 43
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
  [Subscript, {kind: array}, [1, 6, 7], ~, Scalar], # 8
  [Delete, {kind: hash}, [5, 8, 7], 0, Scalar], # 9
  [Return, {implicit: true}, [9], 9]]} # 10
F::get: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 4
  [Subscript, {kind: hash}, [3, 4], ~, Scalar], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [MemStart], # 7
  [Subscript, {kind: array}, [1, 6, 7], ~, Scalar], # 8
  [Subscript, {kind: hash}, [5, 8, 7], ~, Scalar], # 9
  [Return, {implicit: true}, [9], 0]]} # 10
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
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [10, 11], 9, Scalar], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [9, 12, 12], ~, Unknown], # 13
  [Return, {implicit: true}, [13], 12]]} # 14
main::__PROGRAM__: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: F, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 0, Object], # 2
  [Loop, {bound: entry}, [2], 2], # 3
  [Phi, {memory: true, region: 3}, [2, 52], ~, Scalar], # 4
  [Proj, {index: 1}, [3]], # 5
  [Region, {head: 3}, [5]], # 6
  [Phi, {memory: true, region: 6}, [4], ~, Scalar], # 7
  [Loop, {bound: entry}, [6], 6], # 8
  [Phi, {memory: true, region: 8}, [7, 66], ~, Unknown], # 9
  [Proj, {index: 1}, [8]], # 10
  [Region, {head: 8}, [10]], # 11
  [Phi, {memory: true, region: 11}, [9], ~, Unknown], # 12
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [12], ~, Scalar], # 13
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 14
  [PadAccess, {sigil: "@", symbol: got}, ~, ~, Unknown], # 15
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [14, 15, 12], ~, Str], # 16
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 19
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 20
  [Subscript, {kind: hash}, [2, 20], ~, Scalar], # 21
  [PostfixDeref, {sigil: "%"}, [21, 12], ~, Hash], # 22
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [22, 12], ~, List], # 23
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [23, 12], ~, List], # 24
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [19, 24, 12], ~, Str], # 25
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 26
  [Print, ~, [18, 25, 26], 11, Scalar], # 27
  [Return, {implicit: true}, [1], 27], # 28
  [PostfixDeref, {sigil: "%"}, [21, 2], ~, Hash], # 29
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [29, 2], ~, List], # 30
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [30, 2], ~, List], # 31
  [ArrayLiteral, ~, [31], ~, Array], # 32
  [Count, ~, [32, 2], ~, Int], # 33
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 34
  [Phi, {region: 3}, [34, 68], ~, Int], # 35
  [Subscript, {kind: array}, [32, 35], ~, Scalar], # 36
  [Proj, {index: 0}, [3]], # 37
  [Ref, ~, [36], 37, ScalarRef], # 38
  [PostfixDeref, {sigil: $}, [38, 2], 38, Scalar], # 39
  [Subscript, {kind: array}, [32, 35, 2], ~, Scalar], # 40
  [PostfixDeref, {sigil: $}, [38, 2], ~, Scalar], # 41
  [Subscript, {kind: array}, [32, 35, 2], ~, Scalar], # 42
  [PadAccess, {sigil: "@", symbol: dead}, ~, ~, Scalar], # 43
  [Coerce, {from_repr: Scalar, to_repr: Str}, [39], ~, Str], # 44
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 45
  [StrEq, ~, [44, 45], ~, Boolean], # 46
  [If, ~, [39, 46], 39], # 47
  [Proj, {index: 1}, [47]], # 48
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [43, 41, 2], 48, Int], # 49
  [Proj, {index: 0}, [47]], # 50
  [Region, {head: 47}, [50, 49]], # 51
  [Phi, {memory: true, predecessors: [50, 48], region: 51}, [2, 49], ~, Scalar], # 52
  [PadAccess, {sigil: $, symbol: d}, [9], ~, Unknown], # 53
  [Phi, {region: 8}, [34, 72], ~, Int], # 54
  [Subscript, {kind: array}, [43, 54, 9], ~, Scalar], # 55
  [Proj, {index: 0}, [8]], # 56
  [Assign, ~, [53, 55], 56, Scalar], # 57
  [PadAccess, {sigil: $, symbol: d}, [57], ~, Unknown], # 58
  [Call, {class_name: F, dispatch_kind: method, name: get, param_names: [], want: list}, [2, 58], 57, Unknown], # 59
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [15, 59, 59], 59, Int], # 60
  [PadAccess, {sigil: $, symbol: d}, [60], ~, Unknown], # 61
  [Call, {class_name: F, dispatch_kind: method, name: drop, param_names: [], want: void}, [2, 61], 60, Unknown], # 62
  [NumGt, ~, [33, 35], 3, Boolean], # 63
  [PadAccess, {sigil: $, symbol: d}, [62], ~, Unknown], # 64
  [Subscript, {kind: array}, [43, 54], ~, Scalar], # 65
  [Assign, {if_changed: true}, [65, 64], 62, Unknown], # 66
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 67
  [Add, ~, [35, 67], ~, Int], # 68
  [Count, ~, [43, 7], ~, Int], # 69
  [Count, ~, [43, 9], ~, Int], # 70
  [NumGt, ~, [70, 54], 8, Boolean], # 71
  [Add, ~, [54, 67], ~, Int]]} # 72
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
  [PadAccess, {sigil: "@", symbol: dead}, ~, ~, Scalar], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [MemStart], # 5
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 8
  [ArrayLiteral, ~, [7, 8], 0, ArrayRef], # 9
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 10
  [ArrayLiteral, ~, [9, 10], 9, ArrayRef], # 11
  [ArrayLiteral, ~, [6], 11, ArrayRef], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 3, 4, 5], 12, Int], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Phi, {memory: true, region: 14}, [13, 81], ~, Unknown], # 15
  [Proj, {index: 1}, [14]], # 16
  [Region, {head: 14}, [16]], # 17
  [Phi, {memory: true, region: 17}, [15], ~, Unknown], # 18
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [18], ~, Scalar], # 19
  [Coerce, {from_repr: Scalar, to_repr: Str}, [19], ~, Str], # 20
  [PadAccess, {sigil: "@", symbol: seen}, ~, ~, Unknown], # 21
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [20, 21, 18], ~, Str], # 22
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 23
  [Concat, ~, [22, 23], ~, Str], # 24
  [Print, ~, [24], 17, Scalar], # 25
  [Return, {implicit: true}, [1], 25], # 26
  [HashLiteral, {sigil: "%", symbol: in}, [3, 11, 4, 12], ~, Hash], # 27
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 28
  [Phi, {region: 14}, [28, 60], ~, Int], # 29
  [Subscript, {kind: array}, [2, 29, 15], ~, Scalar], # 30
  [Subscript, {kind: hash}, [27, 30], ~, Scalar], # 31
  [PostfixDeref, {sigil: "@"}, [31, 15], ~, Array], # 32
  [Proj, {index: 0}, [14]], # 33
  [Loop, {bound: entry}, [33], 33], # 34
  [Phi, {region: 34}, [28, 59], ~, Int], # 35
  [Proj, {index: 0}, [34]], # 36
  [Exists, {kind: array}, [32, 35, 15], 36, Boolean], # 37
  [Subscript, {kind: array}, [32, 35], ~, Scalar], # 38
  [Ref, ~, [38], ~, ScalarRef], # 39
  [TernaryExpr, ~, [37, 39, 1], 37, Scalar], # 40
  [PostfixDeref, {sigil: $}, [40, 15], ~, Scalar], # 41
  [Subscript, {kind: array}, [32, 35, 15], ~, Scalar], # 42
  [PostfixDeref, {sigil: $}, [40, 15], ~, Scalar], # 43
  [Subscript, {kind: array}, [32, 35, 15], ~, Scalar], # 44
  [TernaryExpr, ~, [37, 43, 44], 40, Scalar], # 45
  [RefType, ~, [45], ~, Str], # 46
  [If, ~, [45, 46], 45], # 47
  [Proj, {index: 0}, [47]], # 48
  [TernaryExpr, ~, [37, 41, 42], 48, Scalar], # 49
  [PostfixDeref, {sigil: "@"}, [49, 15], ~, Array], # 50
  [Loop, {bound: entry}, [49], 49], # 51
  [Phi, {region: 51}, [28, 58], ~, Int], # 52
  [Proj, {index: 0}, [51]], # 53
  [Exists, {kind: array}, [50, 52, 15], 53, Boolean], # 54
  [Subscript, {kind: array}, [50, 52], ~, Scalar], # 55
  [Ref, ~, [55], ~, ScalarRef], # 56
  [TernaryExpr, ~, [54, 56, 1], 54, Scalar], # 57
  [Add, ~, [52, 7], ~, Int], # 58
  [Add, ~, [35, 7], ~, Int], # 59
  [Add, ~, [29, 7], ~, Int], # 60
  [PostfixDeref, {sigil: $}, [40, 15], ~, Scalar], # 61
  [PostfixDeref, {sigil: $}, [57, 15], ~, Scalar], # 62
  [Subscript, {kind: array}, [50, 52, 15], ~, Scalar], # 63
  [TernaryExpr, ~, [54, 62, 63], 57, Scalar], # 64
  [Subscript, {kind: array}, [32, 35, 15], ~, Scalar], # 65
  [TernaryExpr, ~, [37, 61, 65], ~, Scalar], # 66
  [Coerce, {from_repr: Scalar, to_repr: Str}, [30], ~, Str], # 67
  [Coerce, {from_repr: Scalar, to_repr: Str}, [64], ~, Str], # 68
  [Concat, ~, [67, 68], ~, Str], # 69
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [21, 69, 15], 64, Int], # 70
  [Count, ~, [50, 15], ~, Int], # 71
  [NumGt, ~, [71, 52], 51, Boolean], # 72
  [Count, ~, [32, 15], ~, Int], # 73
  [NumGt, ~, [73, 35], 34, Boolean], # 74
  [Count, ~, [2, 15], ~, Int], # 75
  [NumGt, ~, [75, 29], 14, Boolean], # 76
  [Count, ~, [2, 13], ~, Int], # 77
  [Phi, {memory: true, region: 34}, [15, 91], ~, Unknown], # 78
  [Proj, {index: 1}, [34]], # 79
  [Region, {head: 34}, [79]], # 80
  [Phi, {memory: true, region: 80}, [78], ~, Unknown], # 81
  [Coerce, {from_repr: Scalar, to_repr: Str}, [66], ~, Str], # 82
  [Concat, ~, [67, 82], ~, Str], # 83
  [Proj, {index: 1}, [47]], # 84
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [21, 83, 15], 84, Int], # 85
  [Phi, {memory: true, region: 51}, [15, 70], ~, Unknown], # 86
  [Proj, {index: 1}, [51]], # 87
  [Region, {head: 51}, [87]], # 88
  [Region, {head: 47}, [88, 85]], # 89
  [Phi, {memory: true, region: 88}, [86], ~, Unknown], # 90
  [Phi, {memory: true, predecessors: [48, 84], region: 89}, [90, 85], ~, Unknown]]} # 91
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
  [PadAccess, {sigil: "@", symbol: k}, ~, ~, Scalar], # 4
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 7
  [MemStart], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [4, 5, 6, 7, 8], 0, Int], # 9
  [Loop, {bound: entry}, [9], 9], # 10
  [Proj, {index: 1}, [10]], # 11
  [Region, {head: 10}, [11]], # 12
  [Loop, {bound: entry}, [12], 12], # 13
  [Phi, {region: 13}, [3, 63], ~, Array], # 14
  [Phi, {memory: true, region: 10}, [9, 51], ~, Unknown], # 15
  [Phi, {memory: true, region: 12}, [15], ~, Unknown], # 16
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [2, 14, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Proj, {index: 1}, [13]], # 19
  [Region, {head: 13}, [19]], # 20
  [Print, ~, [17, 18], 20, Scalar], # 21
  [Return, {implicit: true}, [1], 21], # 22
  [Count, ~, [4, 9], ~, Int], # 23
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 24
  [HashLiteral, {sigil: "%", symbol: s}, [7, 24], ~, Hash], # 25
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 26
  [Phi, {region: 10}, [26, 64], ~, Int], # 27
  [Subscript, {kind: array}, [4, 27, 15], ~, Scalar], # 28
  [Subscript, {kind: hash}, [25, 28], ~, Scalar], # 29
  [Proj, {index: 0}, [10]], # 30
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 31
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 32
  [HashLiteral, {sigil: "%", symbol: ann}, [5, 31, 7, 32], ~, Hash], # 33
  [Exists, {kind: hash}, [33, 28, 15], ~, Boolean], # 34
  [If, ~, [30, 34], 30], # 35
  [Proj, {index: 0}, [35]], # 36
  [Subscript, {kind: hash}, [25, 28, 15], 36, Scalar], # 37
  [Defined, ~, [37], ~, Boolean], # 38
  [If, ~, [37, 38], 37], # 39
  [Proj, {index: 1}, [39]], # 40
  [Assign, ~, [29, 1], 40, Undef], # 41
  [Count, ~, [4, 15], ~, Int], # 42
  [NumGt, ~, [42, 27], 10, Boolean], # 43
  [Subscript, {kind: hash}, [33, 28, 41], ~, Undef], # 44
  [Assign, ~, [29, 44], 41, Undef], # 45
  [Proj, {index: 0}, [39]], # 46
  [Region, {head: 39}, [46, 45]], # 47
  [Phi, {memory: true, predecessors: [46, 40], region: 47}, [15, 45], ~, Unknown], # 48
  [Proj, {index: 1}, [35]], # 49
  [Region, {head: 35}, [47, 49]], # 50
  [Phi, {memory: true, predecessors: [36, 49], region: 50}, [48, 15], ~, Unknown], # 51
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [25, 16], ~, List], # 52
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [52, 16], ~, List], # 53
  [Phi, {region: 13}, [26, 65], ~, Int], # 54
  [Subscript, {kind: array}, [53, 54, 16], ~, Scalar], # 55
  [Subscript, {kind: hash}, [25, 55, 16], ~, Scalar], # 56
  [Count, ~, [53, 16], ~, Int], # 57
  [Coerce, {from_repr: Unknown, to_repr: Str}, [55], ~, Str], # 58
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 59
  [Concat, ~, [58, 59], ~, Str], # 60
  [Coerce, {from_repr: Unknown, to_repr: Str}, [56], ~, Str], # 61
  [Concat, ~, [60, 61], ~, Str], # 62
  [ListAppend, {collector: map}, [14, 62], ~, Array], # 63
  [Add, ~, [27, 31], ~, Int], # 64
  [Add, ~, [54, 31], ~, Int], # 65
  [NumGt, ~, [57, 54], 13, Boolean], # 66
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
C::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, ArrayRef], # 1
  [Return, ~, [1], 0]]} # 2
C::children: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 0, field_stash: C}, [1], ~, Scalar], # 2
  [Return, {implicit: true}, [2], 0]]} # 3
C::leaves: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 1
  [AnonSub, {name: C::leaves::__ANON__:10:2}, ~, ~, CodeRef], # 2
  [Call, {class_name: C, dispatch_kind: method, name: walk_all, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
C::leaves::__ANON__:10:2: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $n, sigil: $}, ~, ~, Unknown], # 1
  [Return, ~, [1], 0]]} # 2
C::walk_all: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {sigil: "@", symbol: results}, ~, ~, Unknown], # 1
  [Loop, {bound: each}, [0], 0], # 2
  [Proj, {index: 1}, [2]], # 3
  [Region, {head: 2}, [3]], # 4
  [Return, ~, [1], 4], # 5
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 6
  [ArrayLiteral, {sigil: "@", symbol: stack}, [6], ~, Array], # 7
  [MemStart], # 8
  [Phi, {memory: true, region: 2}, [8, 25], ~, Unknown], # 9
  [Count, ~, [7, 9], ~, Int], # 10
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 11
  [NumNe, ~, [10, 11], 2, Boolean], # 12
  [Proj, {index: 0}, [2]], # 13
  [Parameter, {index: 0, name: $cb, sigil: $}, ~, ~, Unknown], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: pop, param_names: []}, [7, 9], 13, Scalar], # 15
  [PadAccess, {sigil: $, symbol: node}, [15], ~, Unknown], # 16
  [Assign, ~, [16, 15], 15, Scalar], # 17
  [PadAccess, {sigil: $, symbol: node}, [17], ~, Unknown], # 18
  [Call, {dispatch_kind: indirect, name: "", param_names: [], want: list}, [14, 18], 17, Unknown], # 19
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [1, 19, 19], 19, Int], # 20
  [Phi, {memory: true, region: 4}, [9], ~, Unknown], # 21
  [PadAccess, {sigil: $, symbol: node}, [20], ~, Unknown], # 22
  [Call, {dispatch_kind: method, name: children, param_names: [], want: scalar}, [22], 20, Unknown], # 23
  [PostfixDeref, {sigil: "@"}, [23, 23], ~, Array], # 24
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [7, 24, 23], 23, Int]]} # 25
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: C}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [Call, {class_name: C, dispatch_kind: method, name: new, param_names: [], want: list}, ~, 3, Object], # 4
  [Call, {class_name: C, dispatch_kind: method, name: new, param_names: [], want: list}, ~, 4, Object], # 5
  [ArrayLiteral, ~, [4, 5], 5, ArrayRef], # 6
  [Call, {class_name: C, dispatch_kind: method, name: new, param_names: [kids], want: scalar}, [6], 6, Object], # 7
  [Call, {class_name: C, dispatch_kind: method, name: leaves, param_names: [], want: list}, [7], 7, Unknown], # 8
  [ArrayLiteral, {sigil: "@", symbol: l}, [8], ~, Array], # 9
  [Call, {class_name: C, dispatch_kind: method, name: leaves, param_names: [], want: scalar}, [7], 8, Unknown], # 10
  [Count, ~, [9, 10], ~, Int], # 11
  [Coerce, {from_repr: Int, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Print, ~, [12, 17], 10, Scalar], # 18
  [Return, {implicit: true}, [1], 18]]} # 19
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: experimental, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3, 4], ~, Array], # 5
  [PadAccess, {sigil: "@", symbol: b}, ~, ~, Scalar], # 6
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 7
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 8
  [MemStart], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [6, 7, 8, 9], 0, Int], # 10
  [Count, ~, [5, 10], ~, Int], # 11
  [Call, {class_name: main, dispatch_kind: method, name: new, param_names: [ix], want: list}, [11], 10, Object], # 12
  [Coerce, {from_repr: Object, to_repr: Str}, [12], ~, Str], # 13
  [Count, ~, [6, 12], ~, Int], # 14
  [Call, {class_name: main, dispatch_kind: method, name: new, param_names: [ix], want: list}, [14], 12, Object], # 15
  [Coerce, {from_repr: Object, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [13, 16, 17], 15, Scalar], # 18
  [Return, {implicit: true}, [1], 18]]} # 19
main::new: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {sigil: "%", symbol: o}, ~, ~, Unknown], # 1
  [Constant, {const_type: string, value: ix}, ~, ~, Str], # 2
  [MemStart], # 3
  [Subscript, {kind: hash}, [1, 2, 3], ~, Scalar], # 4
  [Return, ~, [4], 0], # 5
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Assign, {targets: 2}, [6, 1, 7], ~, List]]} # 8
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
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::only, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: direct, name: main::only, param_names: [], want: list}, [5], 3, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [4, 7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
main::only: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: want}, [2], ~, Unknown], # 3
  [Parameter, {index: 0, name: $want, sigil: $}, ~, ~, Unknown], # 4
  [Assign, ~, [3, 4], 0, Unknown], # 5
  [MakeCell, {captured_written: false, cell_name: $want}, [1, 5], ~, Ref], # 6
  [AnonSub, {captures: [$want], name: main::only::__ANON__:3:4}, [6], ~, CodeRef], # 7
  [Call, {dispatch_kind: direct, name: main::walk, param_names: []}, [7], 5, Str], # 8
  [Return, {implicit: true}, [8], 8]]} # 9
main::only::__ANON__:3:4: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $n, sigil: $}, ~, ~, Num], # 1
  [CellParam, {index: 0, name: $want}, ~, ~, Ref], # 2
  [MemStart], # 3
  [CellRead, ~, [2, 3], ~, Unknown], # 4
  [NumEq, ~, [1, 4], ~, Boolean], # 5
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 6
  [TernaryExpr, ~, [5, 1, 6], ~, Unknown], # 7
  [Return, {implicit: true}, [7], 0]]} # 8
main::walk: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [Region, {head: 3}, [4]], # 5
  [Loop, {bound: entry}, [5], 5], # 6
  [Phi, {region: 6}, [2, 32], ~, Array], # 7
  [MemStart], # 8
  [Phi, {memory: true, region: 3}, [8, 39], ~, Unknown], # 9
  [Phi, {memory: true, region: 5}, [9], ~, Unknown], # 10
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 7, 10], ~, Str], # 11
  [Proj, {index: 1}, [6]], # 12
  [Region, {head: 6}, [12]], # 13
  [Return, {implicit: true}, [11], 13], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 16
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 17
  [ArrayLiteral, ~, [15, 16, 17], ~, List], # 18
  [Count, ~, [18, 9], ~, Int], # 19
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 20
  [Phi, {region: 3}, [20, 36], ~, Int], # 21
  [NumGt, ~, [19, 21], 3, Boolean], # 22
  [Proj, {index: 0}, [3]], # 23
  [Subscript, {kind: array}, [18, 21], ~, Scalar], # 24
  [Ref, ~, [24], ~, ScalarRef], # 25
  [LocalAlias, {name: _}, [25], 23, Unknown], # 26
  [ArrayLiteral, ~, ~, ~, Array], # 27
  [Phi, {region: 3}, [27, 47], ~, Array], # 28
  [Phi, {region: 6}, [20, 48], ~, Int], # 29
  [Subscript, {kind: array}, [28, 29, 10], ~, Scalar], # 30
  [Defined, ~, [30], ~, Boolean], # 31
  [ListAppend, {collector: grep}, [7, 30, 31], ~, Array], # 32
  [Count, ~, [28, 10], ~, Int], # 33
  [Proj, {index: 0}, [6]], # 34
  [Exists, {kind: array}, [28, 29, 10], 34, Boolean], # 35
  [Add, ~, [21, 15], ~, Int], # 36
  [Subscript, {kind: array}, [18, 21, 9], ~, Int], # 37
  [Parameter, {index: 0, name: $cb, sigil: $}, ~, ~, Unknown], # 38
  [Call, {dispatch_kind: indirect, name: "", param_names: [], want: list}, [38, 37], 26, Unknown], # 39
  [NumGt, ~, [33, 29], 6, Boolean], # 40
  [Subscript, {kind: array}, [28, 29], ~, Scalar], # 41
  [Ref, ~, [41], ~, ScalarRef], # 42
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 43
  [TernaryExpr, ~, [35, 42, 43], ~, Scalar], # 44
  [LocalAlias, {name: _}, [44], 35, Unknown], # 45
  [Count, ~, [18, 8], ~, Int], # 46
  [ListAppend, {collector: map}, [28, 39], ~, Array], # 47
  [Add, ~, [29, 15], ~, Int]]} # 48
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
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
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 0, List], # 3
  [ArrayLiteral, {sigil: "@", symbol: a}, [3], ~, Array], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, [2], 3, List], # 6
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, [5], 6, List], # 7
  [Count, ~, [4, 7], ~, Int], # 8
  [Coerce, {from_repr: Int, to_repr: Str}, [8], ~, Str], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [9, 10, 11, 12], 7, Scalar], # 13
  [Return, {implicit: true}, [1], 13]]} # 14
main::f: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown], # 1
  [If, ~, [0, 1], 0], # 2
  [Proj, {index: 0}, [2]], # 3
  [Call, {dispatch_kind: direct, name: main::g, param_names: []}, ~, 3, List], # 4
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 5
  [Proj, {index: 1}, [2]], # 6
  [Region, {head: 2}, [4, 6]], # 7
  [Phi, {predecessors: [3, 6], region: 7}, [4, 5], ~, List], # 8
  [Return, ~, [8], 7], # 9
  [ArgsSource, ~, ~, ~, Array], # 10
  [Assign, {targets: 1}, [1, 10], ~, List]]} # 11
main::g: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, List], # 4
  [Coerce, {from_repr: List, to_repr: Scalar}, [3], ~, Scalar], # 5
  [Return, ~, [4, 5], 0]]} # 6
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {shared: 1, sigil: "@", symbol: pending}, [2], ~, Unknown], # 3
  [ArrayLiteral, ~, ~, ~, Array], # 4
  [Assign, ~, [3, 4], 0, List], # 5
  [Loop, {bound: entry}, [5], 5], # 6
  [Phi, {region: 6}, [1, 46], ~, Str], # 7
  [Proj, {index: 1}, [6]], # 8
  [Region, {head: 6}, [8]], # 9
  [Return, ~, [7], 9], # 10
  [PadAccess, {shared: 1, sigil: "@", symbol: pending}, ~, ~, Scalar], # 11
  [MakeCell, {captured_written: false, cell_name: "@pending"}, [11, 5], ~, Ref], # 12
  [Phi, {memory: true, region: 6}, [12, 59], ~, List], # 13
  [PadAccess, {sigil: $, symbol: pos}, [13], ~, Unknown], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Phi, {region: 6}, [15, 65], ~, Int], # 16
  [Proj, {index: 0}, [6]], # 17
  [Assign, ~, [14, 16], 17, Int], # 18
  [PadAccess, {sigil: $, symbol: pos}, [18], ~, Unknown], # 19
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:1:3, param_names: [], want: void}, [19], 18, Int], # 20
  [PadAccess, {sigil: $, symbol: pos}, [20], ~, Num], # 21
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 22
  [Multiply, ~, [21, 22], ~, Num], # 23
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 24
  [NumEq, ~, [21, 24], ~, Boolean], # 25
  [If, ~, [20, 25], 20], # 26
  [Proj, {index: 0}, [26]], # 27
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:1:3, param_names: [], want: void}, [23], 27, Int], # 28
  [Proj, {index: 1}, [26]], # 29
  [Region, {head: 26}, [28, 29]], # 30
  [Phi, {memory: true, predecessors: [27, 29], region: 30}, [28, 20], ~, Int], # 31
  [Count, ~, [11, 31], ~, Int], # 32
  [If, ~, [30, 32], 30], # 33
  [Proj, {index: 0}, [33]], # 34
  [Loop, {bound: entry}, [34], 34], # 35
  [Phi, {region: 35}, [7, 58], ~, Str], # 36
  [PadAccess, {shared: 1, sigil: "@", symbol: pending}, [31], ~, Unknown], # 37
  [Proj, {index: 1}, [35]], # 38
  [Region, {head: 35}, [38]], # 39
  [ArrayLiteral, {sigil: "@", symbol: pending}, ~, 39, Array], # 40
  [Assign, ~, [37, 40], 40, List], # 41
  [Proj, {index: 1}, [33]], # 42
  [Region, {head: 33}, [41, 42]], # 43
  [Phi, {predecessors: [34, 42], region: 43}, [36, 7], ~, Str], # 44
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 45
  [Concat, ~, [44, 45], ~, Str], # 46
  [Phi, {memory: true, region: 9}, [13], ~, List], # 47
  [AnonSub, {captures: ["@pending"], name: main::f::__ANON__:1:3}, [12], ~, CodeRef], # 48
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 49
  [NumGt, ~, [49, 16], 6, Boolean], # 50
  [Proj, {index: 0}, [35]], # 51
  [Loop, {bound: entry}, [51], 51], # 52
  [Phi, {region: 52}, [36, 63], ~, Str], # 53
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 54
  [Phi, {region: 35}, [54, 66], ~, Int], # 55
  [Subscript, {kind: array}, [11, 55, 31], ~, Scalar], # 56
  [Coerce, {from_repr: Unknown, to_repr: Str}, [56], ~, Str], # 57
  [Concat, ~, [53, 57], ~, Str], # 58
  [Phi, {memory: true, predecessors: [34, 42], region: 43}, [41, 31], ~, List], # 59
  [Coerce, {from_repr: Scalar, to_repr: Str}, [56], ~, Str], # 60
  [Length, ~, [60], ~, Int], # 61
  [Coerce, {from_repr: Int, to_repr: Str}, [61], ~, Str], # 62
  [Concat, ~, [53, 62], ~, Str], # 63
  [NumGt, ~, [32, 55], 35, Boolean], # 64
  [Add, ~, [16, 15], ~, Int], # 65
  [Add, ~, [55, 15], ~, Int], # 66
  [Phi, {region: 52}, [15, 68], ~, Int], # 67
  [Add, ~, [67, 15], ~, Int], # 68
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 69
  [NumGt, ~, [69, 67], 52, Boolean], # 70
  [Proj, {index: 0}, [52]], # 71
  [Proj, {index: 1}, [52]], # 72
  [Region, {head: 52}, [72]]]} # 73
main::f::__ANON__:1:3: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: pending}, ~, ~, Unknown], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [1, 5, 4], 0, Int], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, [3], ~, Unknown], # 4
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 5
  [ArrayLiteral, {sigil: "@", symbol: p}, [5], 0, Array], # 6
  [Assign, ~, [4, 6], 6, List], # 7
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:1:4, param_names: [], want: void}, [2], 7, Int], # 8
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:1:4, param_names: [], want: void}, [1], 8, Int], # 9
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [9], ~, Scalar], # 10
  [Coerce, {from_repr: Scalar, to_repr: Str}, [10], ~, Str], # 11
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, [9], ~, Unknown], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [11, 12, 9], ~, Str], # 13
  [Constant, {const_type: string, value: "/"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 16
  [ArrayLiteral, {sigil: "@", symbol: p}, ~, 9, Array], # 17
  [Assign, ~, [12, 17], 17, List], # 18
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:1:4, param_names: [], want: void}, [16], 18, Int], # 19
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, [19], ~, Unknown], # 20
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [11, 20, 19], ~, Str], # 21
  [Concat, ~, [15, 21], ~, Str], # 22
  [Return, ~, [22], 19], # 23
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Scalar], # 24
  [MakeCell, {captured_written: false, cell_name: "@p"}, [24, 7], ~, Ref], # 25
  [AnonSub, {captures: ["@p"], name: main::f::__ANON__:1:4}, [25], ~, CodeRef]]} # 26
main::f::__ANON__:1:4: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Unknown], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [1, 5, 4], 0, Int], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, [2], ~, Unknown], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [ArrayLiteral, {sigil: "@", symbol: p}, [4], 0, Array], # 5
  [Assign, ~, [3, 5], 5, List], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [1, 25], ~, Str], # 8
  [Proj, {index: 1}, [7]], # 9
  [Region, {head: 7}, [9]], # 10
  [Return, ~, [8], 10], # 11
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Scalar], # 12
  [MakeCell, {captured_written: false, cell_name: "@p"}, [12, 6], ~, Ref], # 13
  [Phi, {memory: true, region: 7}, [13, 33], ~, Scalar], # 14
  [PadAccess, {sigil: $, symbol: x}, [14], ~, Unknown], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Phi, {region: 7}, [16, 27], ~, Int], # 17
  [Subscript, {kind: array}, [12, 17, 14], ~, Scalar], # 18
  [Proj, {index: 0}, [7]], # 19
  [Assign, ~, [15, 18], 19, Scalar], # 20
  [PadAccess, {sigil: $, symbol: x}, [20], ~, Unknown], # 21
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:1:4, param_names: [], want: void}, [21], 20, Scalar], # 22
  [PadAccess, {sigil: $, symbol: x}, [22], ~, Str], # 23
  [Coerce, {from_repr: Unknown, to_repr: Str}, [23], ~, Str], # 24
  [Concat, ~, [8, 24], ~, Str], # 25
  [Phi, {memory: true, region: 10}, [14], ~, Scalar], # 26
  [Add, ~, [17, 4], ~, Int], # 27
  [AnonSub, {captures: ["@p"], name: main::f::__ANON__:1:4}, [13], ~, CodeRef], # 28
  [Count, ~, [12, 13], ~, Int], # 29
  [Count, ~, [12, 14], ~, Int], # 30
  [NumGt, ~, [30, 17], 7, Boolean], # 31
  [Subscript, {kind: array}, [12, 17], ~, Scalar], # 32
  [Assign, {if_changed: true}, [32, 23], 22, Str]]} # 33
main::f::__ANON__:1:4: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 6
  [NumLt, ~, [5, 6], ~, Boolean], # 7
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Unknown], # 8
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 9
  [Add, ~, [5, 9], ~, Num], # 10
  [If, ~, [0, 7], 0], # 11
  [Proj, {index: 0}, [11]], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [8, 10, 3], 12, Int], # 13
  [And, ~, [7, 13], ~, Scalar], # 14
  [Proj, {index: 1}, [11]], # 15
  [Region, {head: 11}, [15, 13]], # 16
  [Return, {implicit: true}, [14], 16], # 17
  [Phi, {memory: true, predecessors: [15, 12], region: 16}, [3, 13], ~, Unknown]]} # 18
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::g: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, [4], ~, Unknown], # 5
  [HashLiteral, ~, ~, ~, Hash], # 6
  [Assign, ~, [5, 6], 0, List], # 7
  [Call, {dispatch_kind: direct, name: main::g::__ANON__:1:3, param_names: [], want: list}, [2, 3], 7, Scalar], # 8
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 9
  [Call, {dispatch_kind: direct, name: main::g::__ANON__:1:3, param_names: [], want: list}, [2, 9], 8, Scalar], # 10
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 11
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 12
  [Call, {dispatch_kind: direct, name: main::g::__ANON__:1:3, param_names: [], want: list}, [11, 12], 10, Scalar], # 13
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 8, 10, 13], ~, Str], # 14
  [Return, ~, [14], 13], # 15
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Scalar], # 16
  [MakeCell, {captured_written: false, cell_name: "%h"}, [16, 7], ~, Ref], # 17
  [AnonSub, {captures: ["%h"], name: main::g::__ANON__:1:3}, [17], ~, CodeRef]]} # 18
main::g::__ANON__:1:3: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Unknown], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Subscript, {kind: hash}, [1, 5, 4], 0, Scalar], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Subscript, {kind: hash}, [1, 5], ~, Scalar], # 8
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 9
  [Defined, ~, [6], ~, Boolean], # 10
  [If, ~, [6, 10], 6], # 11
  [Proj, {index: 1}, [11]], # 12
  [Assign, ~, [8, 9], 12, Undef], # 13
  [Subscript, {kind: array}, [2, 7, 13], ~, Undef], # 14
  [Proj, {index: 0}, [11]], # 15
  [Assign, ~, [8, 14], 13, Undef], # 16
  [Region, {head: 11}, [15, 16]], # 17
  [Phi, {predecessors: [15, 12], region: 17}, [6, 14], ~, Scalar], # 18
  [Return, {implicit: true}, [18], 17], # 19
  [Phi, {memory: true, predecessors: [15, 12], region: 17}, [4, 16], ~, Unknown]]} # 20
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Unknown], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: w}, [2], ~, Unknown], # 3
  [Assign, ~, [3, 1], 0, Undef], # 4
  [MakeCell, {captured_written: false, cell_name: $w}, [1, 4], ~, Ref], # 5
  [AnonSub, {captures: [$w], name: main::f::__ANON__:1:2}, [5], ~, CodeRef], # 6
  [CellWrite, ~, [5, 6, 5], 4, Scalar], # 7
  [CellRead, ~, [5, 7], ~, Unknown], # 8
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 9
  [Call, {dispatch_kind: indirect, name: "", param_names: []}, [8, 9], 7, Unknown], # 10
  [Return, ~, [10], 10]]} # 11
main::f::__ANON__:1:2: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [2, 3], 0, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [PadAccess, {sigil: $, symbol: w}, [4], ~, Unknown], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Subtract, ~, [5, 7], ~, Num], # 8
  [NumLe, ~, [5, 1], ~, Boolean], # 9
  [If, ~, [4, 9], 4], # 10
  [Proj, {index: 1}, [10]], # 11
  [Call, {dispatch_kind: indirect, name: "", param_names: [], want: scalar}, [6, 8], 11, Unknown], # 12
  [Add, ~, [5, 12], ~, Unknown], # 13
  [Proj, {index: 0}, [10]], # 14
  [Region, {head: 10}, [14, 12]], # 15
  [Phi, {predecessors: [14, 11], region: 15}, [1, 13], ~, Unknown], # 16
  [Return, ~, [16], 15], # 17
  [Phi, {memory: true, predecessors: [14, 11], region: 15}, [4, 12], ~, Unknown]]} # 18
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
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
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
  [Call, {dispatch_kind: direct, name: main::collect, param_names: [], want: list}, [13, 16], 16, Str], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Print, ~, [18, 19], 17, Scalar], # 20
  [Return, {implicit: true}, [1], 20]]} # 21
main::collect: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: tree}, [3], ~, Unknown], # 4
  [Parameter, {index: 0, name: $tree, sigil: $}, ~, ~, Unknown], # 5
  [Assign, ~, [4, 5], 0, Unknown], # 6
  [PadAccess, {sigil: $, symbol: dv}, [6], ~, Unknown], # 7
  [Parameter, {index: 1, name: $dv, sigil: $}, ~, ~, Unknown], # 8
  [Assign, ~, [7, 8], 6, Unknown], # 9
  [PadAccess, {sigil: $, symbol: walk}, [9], ~, Unknown], # 10
  [Assign, ~, [10, 2], 9, Undef], # 11
  [MakeCell, {captured_written: true, cell_name: $dv}, [2, 11], ~, Ref], # 12
  [MakeCell, {captured_written: false, cell_name: $walk}, [2, 12], ~, Ref], # 13
  [AnonSub, {captures: [$dv, $walk], name: main::collect::__ANON__:1:4}, [12, 13], ~, CodeRef], # 14
  [CellWrite, ~, [13, 14, 13], 11, Scalar], # 15
  [CellRead, ~, [13, 15], ~, Unknown], # 16
  [PadAccess, {sigil: $, symbol: tree}, [15], ~, Unknown], # 17
  [Call, {dispatch_kind: indirect, name: "", param_names: [], want: void}, [16, 17], 15, Unknown], # 18
  [CellRead, ~, [12, 18], ~, Unknown], # 19
  [PostfixDeref, {sigil: "%"}, [19, 18], ~, Hash], # 20
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [20, 18], ~, List], # 21
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [21, 18], ~, List], # 22
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 22, 18], ~, Str], # 23
  [Return, ~, [23], 18]]} # 24
main::collect::__ANON__:1:4: {start: 0, returns: [35], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [Constant, {const_type: boolean, value: ""}, ~, ~, Boolean], # 2
  [Parameter, {index: 0, name: $node, sigil: $}, ~, ~, Unknown], # 3
  [RefType, ~, [3], ~, Str], # 4
  [Not, ~, [4], ~, Boolean], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 0}, [6]], # 7
  [Proj, {index: 1}, [6]], # 8
  [Constant, {const_type: string, value: name}, ~, ~, Str], # 9
  [MemStart], # 10
  [Exists, {kind: hash}, [3, 9, 10], ~, Boolean], # 11
  [If, ~, [8, 11], 8], # 12
  [Proj, {index: 1}, [12]], # 13
  [PadAccess, {sigil: $, symbol: dv}, [10], ~, Unknown], # 14
  [Subscript, {kind: hash}, [3, 9, 10], ~, Scalar], # 15
  [Proj, {index: 0}, [12]], # 16
  [Subscript, {kind: hash}, [14, 15, 10], 16, Scalar], # 17
  [Defined, ~, [17], ~, Boolean], # 18
  [If, ~, [17, 18], 17], # 19
  [Proj, {index: 0}, [19]], # 20
  [Subscript, {kind: hash}, [14, 15], ~, Scalar], # 21
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 22
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 23
  [Proj, {index: 1}, [19]], # 24
  [Assign, ~, [21, 23], 24, Undef], # 25
  [Assign, ~, [21, 22], 25, Int], # 26
  [Region, {head: 19}, [20, 26]], # 27
  [Region, {head: 12}, [13, 27]], # 28
  [Loop, {bound: entry}, [28], 28], # 29
  [Proj, {index: 1}, [29]], # 30
  [Region, {head: 29}, [30]], # 31
  [Region, {head: 6}, [7, 31]], # 32
  [Phi, {predecessors: [7, 8], region: 32}, [1, 2], ~, List], # 33
  [Phi, {predecessors: [7, 8], region: 32}, [23, 2], ~, Scalar], # 34
  [Return, ~, [33, 34], 32], # 35
  [Constant, {const_type: string, value: kids}, ~, ~, Str], # 36
  [Subscript, {kind: hash}, [3, 36], ~, Scalar], # 37
  [Phi, {memory: true, predecessors: [20, 24], region: 27}, [10, 26], ~, Unknown], # 38
  [Phi, {memory: true, predecessors: [13, 16], region: 28}, [10, 38], ~, Unknown], # 39
  [PostfixDeref, {sigil: "@"}, [37, 39], ~, Array], # 40
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 41
  [Phi, {region: 29}, [41, 57], ~, Int], # 42
  [Phi, {memory: true, region: 29}, [39, 54], ~, Unknown], # 43
  [Proj, {index: 0}, [29]], # 44
  [Exists, {kind: array}, [40, 42, 43], 44, Boolean], # 45
  [Subscript, {kind: array}, [40, 42], ~, Scalar], # 46
  [Ref, ~, [46], ~, ScalarRef], # 47
  [TernaryExpr, ~, [45, 47, 23], 45, Scalar], # 48
  [Phi, {memory: true, region: 31}, [43], ~, Unknown], # 49
  [PostfixDeref, {sigil: $}, [48, 43], ~, Scalar], # 50
  [PadAccess, {sigil: $, symbol: walk}, [43], ~, Unknown], # 51
  [Subscript, {kind: array}, [40, 42, 43], ~, Scalar], # 52
  [TernaryExpr, ~, [45, 50, 52], ~, Scalar], # 53
  [Call, {dispatch_kind: indirect, name: "", param_names: [], want: void}, [51, 53], 48, Unknown], # 54
  [Count, ~, [40, 43], ~, Int], # 55
  [NumGt, ~, [55, 42], 29, Boolean], # 56
  [Add, ~, [42, 22], ~, Int], # 57
  [Count, ~, [40, 39], ~, Int]]} # 58
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.038"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
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
S::add: {start: 0, returns: [13], nodes: [
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
  [Unwind, ~, [9], 10], # 11
  [Region, {head: 7}, [8, 11]], # 12
  [Return, ~, [3], 12], # 13
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown], # 14
  [ArgsSource, ~, ~, ~, Array], # 15
  [Assign, {targets: 3}, [14, 1, 2, 15], ~, List]]} # 16
S::new: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [HashLiteral, ~, ~, 0, HashRef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [2, 3], 1, Scalar], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [1, 4, 4], ~, Unknown], # 5
  [Return, {implicit: true}, [5], 4]]} # 6
main::__PROGRAM__: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: S, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 0, Object], # 2
  [PadAccess, {sigil: $, symbol: s}, [2], ~, Unknown], # 3
  [Assign, ~, [3, 2], 2, Object], # 4
  [PadAccess, {sigil: $, symbol: s}, [4], ~, Unknown], # 5
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 7
  [Call, {dispatch_kind: direct, name: main::merge, param_names: [], want: list}, [5, 6, 7], 4, Unknown], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [PadAccess, {sigil: $, symbol: s}, [8], ~, Unknown], # 11
  [Call, {dispatch_kind: direct, name: main::merge, param_names: [], want: list}, [11, 1, 7], 8, Unknown], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [PadAccess, {sigil: $, symbol: s}, [12], ~, Unknown], # 14
  [Call, {dispatch_kind: direct, name: main::merge, param_names: [], want: scalar}, [14, 6, 6], 12, Unknown], # 15
  [Region, {eval_entry: 12}, [15]], # 16
  [Phi, {region: 16}, [15, 1], ~, Unknown], # 17
  [Constant, {const_type: string, value: "died: "}, ~, ~, Str], # 18
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [15], ~, Scalar], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 20
  [Concat, ~, [18, 20], ~, Str], # 21
  [DefinedOr, ~, [17, 21], ~, Unknown], # 22
  [Coerce, {from_repr: Unknown, to_repr: Str}, [22], ~, Str], # 23
  [Print, ~, [9, 10, 13, 10, 23], 16, Scalar], # 24
  [Return, {implicit: true}, [1], 24], # 25
  [Defined, ~, [17], ~, Boolean], # 26
  [TernaryExpr, ~, [26, 1, 21], ~, Scalar]]} # 27
main::merge: {start: 0, returns: [38], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 1
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: s}, [3], ~, Unknown], # 4
  [Parameter, {index: 0, name: $s, sigil: $}, ~, ~, Unknown], # 5
  [Assign, ~, [4, 5], 0, Unknown], # 6
  [PadAccess, {sigil: $, symbol: x}, [6], ~, Unknown], # 7
  [Parameter, {index: 1, name: $x, sigil: $}, ~, ~, Unknown], # 8
  [Assign, ~, [7, 8], 6, Unknown], # 9
  [PadAccess, {sigil: $, symbol: "y"}, [9], ~, Unknown], # 10
  [Parameter, {index: 2, name: $y, sigil: $}, ~, ~, Unknown], # 11
  [Assign, ~, [10, 11], 9, Unknown], # 12
  [PadAccess, {sigil: $, symbol: merged}, [12], ~, Unknown], # 13
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 14
  [PadAccess, {sigil: $, symbol: x}, [12], ~, Unknown], # 15
  [Defined, ~, [15], ~, Boolean], # 16
  [If, ~, [12, 16], 12], # 17
  [Proj, {index: 0}, [17]], # 18
  [Assign, ~, [13, 14], 18, Undef], # 19
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [19], ~, Scalar], # 20
  [PadAccess, {sigil: $, symbol: s}, [19], ~, Unknown], # 21
  [PadAccess, {sigil: $, symbol: x}, [19], ~, Unknown], # 22
  [PadAccess, {sigil: $, symbol: "y"}, [19], ~, Unknown], # 23
  [Call, {dispatch_kind: method, name: add, param_names: [], want: scalar}, [21, 22, 23], 19, Unknown], # 24
  [PadAccess, {sigil: $, symbol: merged}, [24], ~, Unknown], # 25
  [Assign, ~, [25, 24], 24, Unknown], # 26
  [Region, {eval_entry: 19}, [26]], # 27
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [26], 27, Scalar], # 28
  [EntryWrite, ~, [2, 20, 26], 28, Unknown], # 29
  [PadAccess, {sigil: $, symbol: merged}, [29], ~, Unknown], # 30
  [Proj, {index: 1}, [17]], # 31
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 32
  [Phi, {region: 27}, [32, 14], ~, Scalar], # 33
  [If, ~, [29, 33], 29], # 34
  [Proj, {index: 0}, [34]], # 35
  [Region, {head: 17}, [31, 35]], # 36
  [Phi, {predecessors: [31, 18], region: 36}, [1, 30], ~, Unknown], # 37
  [Return, ~, [37], 36], # 38
  [Phi, {memory: true, predecessors: [31, 18], region: 36}, [12, 29], ~, Unknown], # 39
  [PadAccess, {sigil: $, symbol: x}, [29], ~, Str], # 40
  [Proj, {index: 1}, [34]], # 41
  [Coerce, {from_repr: Unknown, to_repr: Str}, [40], ~, Str], # 42
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 43
  [Constant, {const_type: string, value: "Ambiguity for '"}, ~, ~, Str], # 44
  [Concat, ~, [44, 42], ~, Str], # 45
  [Constant, {const_type: string, value: "': "}, ~, ~, Str], # 46
  [Concat, ~, [45, 46], ~, Str], # 47
  [Concat, ~, [47, 43], ~, Str], # 48
  [Unwind, ~, [48], 41]]} # 49
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1], 4, Unknown], # 5
  [Return, {implicit: true}, [5], 5]]} # 6
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
  [EntryWrite, ~, [3, 4, 5], 0, Unknown], # 6
  [Call, {dispatch_kind: direct, name: main::h, param_names: [], want: list}, [2], 6, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 10
  [Call, {dispatch_kind: direct, name: main::h, param_names: [], want: list}, [10], 7, Str], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: " ["}, ~, ~, Str], # 13
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [11], 11, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Print, ~, [8, 9, 12, 17], 14, Scalar], # 18
  [Return, {implicit: true}, [1], 18]]} # 19
main::g: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Num], # 1
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
  [Unwind, ~, [10], 11], # 12
  [Region, {head: 4}, [5, 12]], # 13
  [Return, ~, [1], 13]]} # 14
main::h: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: "c:"}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: x}, [3], ~, Unknown], # 4
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Unknown], # 5
  [Assign, ~, [4, 5], 0, Unknown], # 6
  [PadAccess, {sigil: $, symbol: x}, [6], ~, Unknown], # 7
  [Call, {dispatch_kind: direct, name: main::g, param_names: []}, [7], 6, Num], # 8
  [Region, {eval_entry: 6}, [8]], # 9
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [8], 9, Scalar], # 10
  [Chomp, {kind: chomp}, [10], ~, Str], # 11
  [Concat, ~, [2, 11], ~, Str], # 12
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 13
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [6], ~, Scalar], # 14
  [EntryWrite, ~, [13, 14, 8], 10, Unknown], # 15
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 16
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 17
  [Phi, {region: 9}, [16, 17], ~, Scalar], # 18
  [If, ~, [15, 18], 15], # 19
  [Proj, {index: 0}, [19]], # 20
  [Proj, {index: 1}, [19]], # 21
  [Region, {head: 19}, [20, 21]], # 22
  [Phi, {predecessors: [20, 21], region: 22}, [1, 12], ~, Str], # 23
  [Return, ~, [23], 22], # 24
  [Phi, {predecessors: [20, 21], region: 22}, [8, 12], ~, Str], # 25
  [ChompValue, {kind: chomp}, [10], ~, Int]]} # 26
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1], 4, Unknown], # 5
  [Return, {implicit: true}, [5], 5]]} # 6
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
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: next}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 3
  [ArrayLiteral, ~, [3], 0, ArrayRef], # 4
  [HashLiteral, ~, [2, 4], 4, HashRef], # 5
  [HashLiteral, ~, [2, 5], 5, HashRef], # 6
  [Call, {dispatch_kind: direct, name: main::find, param_names: [], want: list}, [6], 6, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Constant, {const_type: ref, value: "1"}, ~, ~, ScalarRef], # 10
  [HashLiteral, ~, [2, 10], 7, HashRef], # 11
  [Call, {dispatch_kind: direct, name: main::find, param_names: [], want: list}, [11], 11, Str], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [HashLiteral, ~, [2, 1], 12, HashRef], # 14
  [Call, {dispatch_kind: direct, name: main::find, param_names: [], want: list}, [14], 14, Str], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [8, 9, 13, 9, 16, 17], 15, Scalar], # 18
  [Return, {implicit: true}, [1], 18]]} # 19
main::find: {start: 0, returns: [30], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $n, sigil: $}, ~, ~, Unknown], # 1
  [Loop, {bound: each}, [0], 0], # 2
  [Phi, {region: 2}, [1, 33], ~, Unknown], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [3, 4, 5], ~, Scalar], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 8
  [StrEq, ~, [7, 8], ~, Boolean], # 9
  [Constant, {const_type: string, value: found}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: other}, ~, ~, Str], # 11
  [TernaryExpr, ~, [9, 10, 11], ~, Str], # 12
  [Constant, {const_type: string, value: stop}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: end}, ~, ~, Str], # 14
  [Proj, {index: 0}, [2]], # 15
  [RefType, ~, [3], ~, Str], # 16
  [Constant, {const_type: string, value: ARRAY}, ~, ~, Str], # 17
  [StrEq, ~, [16, 17], ~, Boolean], # 18
  [If, ~, [15, 18], 15], # 19
  [Proj, {index: 0}, [19]], # 20
  [Proj, {index: 1}, [19]], # 21
  [Constant, {const_type: string, value: HASH}, ~, ~, Str], # 22
  [StrEq, ~, [16, 22], ~, Boolean], # 23
  [If, ~, [21, 23], 21], # 24
  [Proj, {index: 1}, [24]], # 25
  [Proj, {index: 1}, [2]], # 26
  [Region, {head: 2}, [26]], # 27
  [Region, ~, [20, 25, 27]], # 28
  [Phi, {predecessors: [20, 25, 27], region: 28}, [12, 13, 14], ~, Str], # 29
  [Return, ~, [29], 28], # 30
  [Defined, ~, [3], 2, Boolean], # 31
  [Constant, {const_type: string, value: next}, ~, ~, Str], # 32
  [Subscript, {kind: hash}, [3, 32, 5], ~, Scalar], # 33
  [Proj, {index: 0}, [24]]]} # 34
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
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
  [PadAccess, {shared: 1, sigil: "%", symbol: PARENT}, [4], ~, Unknown], # 5
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 7
  [HashLiteral, {sigil: "%", symbol: PARENT}, [2, 6, 6, 3, 3, 7], 0, Hash], # 8
  [Assign, ~, [5, 8], 8, List], # 9
  [Call, {dispatch_kind: direct, name: main::is_sub, param_names: [], want: list}, [2, 3], 9, Int], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 12
  [Call, {dispatch_kind: direct, name: main::is_sub, param_names: [], want: list}, [2, 12], 10, Int], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Call, {dispatch_kind: direct, name: main::is_sub, param_names: [], want: list}, [3, 7], 13, Int], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 17
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 18
  [ArrayLiteral, ~, ~, ~, Array], # 19
  [Loop, {bound: entry}, [15], 15], # 20
  [Phi, {region: 20}, [19, 42], ~, Array], # 21
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [18, 21, 15], ~, Str], # 22
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 23
  [Proj, {index: 1}, [20]], # 24
  [Region, {head: 20}, [24]], # 25
  [Print, ~, [11, 14, 16, 17, 22, 23], 25, Scalar], # 26
  [Return, {implicit: true}, [1], 26], # 27
  [PadAccess, {shared: 1, sigil: "%", symbol: cache}, [15], ~, Unknown], # 28
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [28, 15], ~, List], # 29
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [29, 15], ~, List], # 30
  [Count, ~, [30, 15], ~, Int], # 31
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 32
  [Phi, {region: 20}, [32, 46], ~, Int], # 33
  [Subscript, {kind: array}, [30, 33, 15], ~, Scalar], # 34
  [PadAccess, {shared: 1, sigil: "%", symbol: cache}, ~, ~, Unknown], # 35
  [Subscript, {kind: hash}, [35, 34, 15], ~, Scalar], # 36
  [Coerce, {from_repr: Unknown, to_repr: Str}, [34], ~, Str], # 37
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 38
  [Concat, ~, [37, 38], ~, Str], # 39
  [Coerce, {from_repr: Unknown, to_repr: Str}, [36], ~, Str], # 40
  [Concat, ~, [39, 40], ~, Str], # 41
  [ListAppend, {collector: map}, [21, 41], ~, Array], # 42
  [NumGt, ~, [31, 33], 20, Boolean], # 43
  [Proj, {index: 0}, [20]], # 44
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 45
  [Add, ~, [33, 45], ~, Int]]} # 46
main::is_sub: {start: 0, returns: [26], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [PadAccess, {shared: 1, sigil: "%", symbol: cache}, ~, ~, Unknown], # 3
  [PadAccess, {sigil: $, symbol: child}, ~, ~, Str], # 4
  [PadAccess, {sigil: $, symbol: parent}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Subscript, {kind: hash}, [3, 6], ~, Scalar], # 7
  [Loop, {bound: each}, [0], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [PadAccess, {shared: 1, sigil: "%", symbol: PARENT}, ~, ~, Unknown], # 10
  [Phi, {region: 8}, [4, 14], ~, Scalar], # 11
  [MemStart], # 12
  [Phi, {memory: true, region: 8}, [12, 13], ~, Unknown], # 13
  [Subscript, {kind: hash}, [10, 11, 13], ~, Scalar], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 16
  [StrEq, ~, [15, 16], ~, Boolean], # 17
  [If, ~, [9, 17], 9], # 18
  [Proj, {index: 0}, [18]], # 19
  [Assign, ~, [7, 1], 19, Int], # 20
  [Proj, {index: 1}, [8]], # 21
  [Region, {head: 8}, [21]], # 22
  [Assign, ~, [7, 2], 22, Int], # 23
  [Region, ~, [20, 23]], # 24
  [Phi, {predecessors: [19, 23], region: 24}, [1, 2], ~, Int], # 25
  [Return, ~, [25], 24], # 26
  [Not, ~, [14], ~, Boolean], # 27
  [Not, ~, [27], 8, Boolean], # 28
  [Proj, {index: 1}, [18]], # 29
  [Phi, {memory: true, region: 22}, [13], ~, Unknown], # 30
  [ArgsSource, ~, ~, ~, Array], # 31
  [Assign, {targets: 2}, [4, 5, 31], ~, List]]} # 32
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 42], ~, Str], # 3
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [MemStart], # 6
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [7], ~, Str], # 8
  [PadAccess, {sigil: "@", symbol: p}, ~, ~, Unknown], # 9
  [Phi, {region: 2}, [9, 44], ~, Unknown], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [8, 10], ~, Str], # 11
  [Concat, ~, [5, 11], ~, Str], # 12
  [Proj, {index: 1}, [2]], # 13
  [Region, {head: 2}, [13]], # 14
  [Return, ~, [12], 14], # 15
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 16
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 17
  [Phi, {region: 2}, [17, 25], ~, Int], # 18
  [NumGt, ~, [16, 18], 2, Boolean], # 19
  [Proj, {index: 0}, [2]], # 20
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 21
  [Modulo, ~, [18, 21], ~, Int], # 22
  [If, ~, [20, 22], 20], # 23
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 24
  [Add, ~, [18, 24], ~, Int], # 25
  [Proj, {index: 0}, [23]], # 26
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [10, 18], 26, Unknown], # 27
  [Proj, {index: 1}, [23]], # 28
  [Region, {head: 23}, [27, 28]], # 29
  [Count, ~, [10, 6], ~, Int], # 30
  [NumGt, ~, [30, 24], ~, Boolean], # 31
  [If, ~, [29, 31], 29], # 32
  [Proj, {index: 0}, [32]], # 33
  [Loop, {bound: entry}, [33], 33], # 34
  [Phi, {region: 34}, [3, 48], ~, Str], # 35
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 36
  [Concat, ~, [35, 36], ~, Str], # 37
  [Proj, {index: 1}, [34]], # 38
  [Region, {head: 34}, [38]], # 39
  [Proj, {index: 1}, [32]], # 40
  [Region, {head: 32}, [39, 40]], # 41
  [Phi, {predecessors: [33, 40], region: 41}, [37, 3], ~, Str], # 42
  [ArrayLiteral, {sigil: "@", symbol: p}, ~, ~, Array], # 43
  [Phi, {predecessors: [33, 40], region: 41}, [43, 10], ~, Array], # 44
  [Phi, {region: 34}, [17, 50], ~, Int], # 45
  [Subscript, {kind: array}, [10, 45, 6], ~, Scalar], # 46
  [Coerce, {from_repr: Unknown, to_repr: Str}, [46], ~, Str], # 47
  [Concat, ~, [35, 47], ~, Str], # 48
  [NumGt, ~, [30, 45], 34, Boolean], # 49
  [Add, ~, [45, 24], ~, Int], # 50
  [Proj, {index: 0}, [34]]]} # 51
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
K::__DEFAULT_0: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [HashLiteral, ~, [1, 2, 3, 4], ~, Hash], # 5
  [Return, ~, [5], 0], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [ArrayLiteral, ~, [2, 4, 7], ~, Array], # 8
  [Start], # 9
  [Return, ~, [8], 9]]} # 10
K::__DEFAULT_1: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, Array], # 4
  [Return, ~, [4], 0], # 5
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 7
  [HashLiteral, ~, [6, 1, 7, 2], ~, Hash], # 8
  [Start], # 9
  [Return, ~, [8], 9]]} # 10
K::n: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Hash], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: scalar}, [1, 2], ~, Int], # 3
  [FieldAccess, {field_index: 1, field_stash: K}, ~, ~, Array], # 4
  [Count, ~, [4, 2], ~, Int], # 5
  [Concat, ~, [3, 5], ~, Str], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
K::reset_h: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Hash], # 1
  [Assign, {targets: 1}, [1], 0, Unknown], # 2
  [Return, {implicit: true}, [2], 2]]} # 3
K::reset_l: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 1, field_stash: K}, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 2
  [Assign, {targets: 1}, [1, 2], 0, Int], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: K}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [Call, {class_name: K, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 3, Object], # 4
  [Call, {class_name: K, dispatch_kind: method, name: reset_h, param_names: [], want: scalar}, [4], 4, Unknown], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Call, {class_name: K, dispatch_kind: method, name: reset_l, param_names: [], want: list}, [4], 5, Int], # 7
  [ArrayLiteral, {sigil: "@", symbol: b}, [7], ~, Array], # 8
  [Count, ~, [8, 7], ~, Int], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Call, {class_name: K, dispatch_kind: method, name: "n", param_names: [], want: list}, [4], 7, Str], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [6, 10, 12, 13], 11, Scalar], # 14
  [Return, {implicit: true}, [1], 14]]} # 15
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: experimental, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: string, value: X}, ~, ~, Str], # 3
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, [2, 3], 0, Int], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Constant, {const_type: string, value: "Y"}, ~, ~, Str], # 7
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, [6, 7], 4, Int], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Unknown], # 11
  [Constant, {const_type: string, value: "0"}, ~, ~, Str], # 12
  [Subscript, {kind: hash}, [11, 12, 8], ~, Scalar], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Concat, ~, [10, 14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Print, ~, [5, 9, 17], 8, Scalar], # 18
  [Return, {implicit: true}, [1], 18]]} # 19
main::g: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Parameter, {index: 0, name: $k, sigil: $}, ~, ~, Unknown], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 0}, [4]], # 5
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Unknown], # 6
  [Subscript, {kind: hash}, [6, 3], ~, Scalar], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [Proj, {index: 1}, [4]], # 9
  [Assign, ~, [7, 8], 9, Int], # 10
  [Region, {head: 4}, [5, 10]], # 11
  [Phi, {predecessors: [5, 9], region: 11}, [1, 2], ~, Int], # 12
  [Return, {implicit: true}, [12], 11], # 13
  [MemStart], # 14
  [Phi, {memory: true, predecessors: [5, 9], region: 11}, [14, 10], ~, Unknown]]} # 15
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1], 4, Unknown], # 5
  [Return, {implicit: true}, [5], 5]]} # 6
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
main::__PROGRAM__: {start: 0, returns: [29], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: w}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [PadAccess, {sigil: "@", symbol: ag}, ~, ~, Unknown], # 7
  [Ref, ~, [7], ~, Unknown], # 8
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 12
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, [9, 12, 11, 11, 8], 0, Unknown], # 13
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, [9, 10, 11, 6, 8], 13, Unknown], # 14
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, [4, 5, 6, 6, 8], 14, Unknown], # 15
  [Loop, {bound: entry}, [15], 15], # 16
  [Phi, {region: 16}, [3, 41], ~, Array], # 17
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [2, 17, 15], ~, Str], # 18
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 19
  [PadAccess, {shared: 1, sigil: "%", symbol: c}, ~, ~, Unknown], # 20
  [Subscript, {kind: hash}, [20, 9, 15], ~, Scalar], # 21
  [Coerce, {from_repr: Unknown, to_repr: Str}, [21], ~, Str], # 22
  [Concat, ~, [19, 22], ~, Str], # 23
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 24
  [Concat, ~, [23, 24], ~, Str], # 25
  [Proj, {index: 1}, [16]], # 26
  [Region, {head: 16}, [26]], # 27
  [Print, ~, [18, 25], 27, Scalar], # 28
  [Return, {implicit: true}, [1], 28], # 29
  [ArrayLiteral, ~, [13, 14, 15], ~, List], # 30
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 31
  [Phi, {region: 16}, [31, 33], ~, Int], # 32
  [Add, ~, [32, 11], ~, Int], # 33
  [Count, ~, [30, 15], ~, Int], # 34
  [Subscript, {kind: array}, [30, 32, 15], ~, Scalar], # 35
  [Subscript, {kind: array}, [30, 32], ~, Scalar], # 36
  [NumGt, ~, [34, 32], 16, Boolean], # 37
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 38
  [DefinedOr, ~, [35, 38], ~, Scalar], # 39
  [Ref, ~, [36], ~, ScalarRef], # 40
  [ListAppend, {collector: map}, [17, 39], ~, Array], # 41
  [Proj, {index: 0}, [16]], # 42
  [LocalAlias, {name: _}, [40], 42, Unknown]]} # 43
main::g: {start: 0, returns: [38], nodes: [
  [Start], # 0
  [Parameter, {index: 4, name: $ag, sigil: $}, ~, ~, Unknown], # 1
  [PadAccess, {shared: 1, sigil: "%", symbol: c}, ~, ~, Unknown], # 2
  [Parameter, {index: 0, name: $k, sigil: $}, ~, ~, Unknown], # 3
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [2, 3, 5], ~, Scalar], # 6
  [Coerce, {from_repr: Scalar, to_repr: Str}, [6], ~, Str], # 7
  [Parameter, {index: 1, name: $v, sigil: $}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Exists, {kind: hash}, [2, 3, 5], ~, Boolean], # 10
  [If, ~, [0, 10], 0], # 11
  [Proj, {index: 0}, [11]], # 12
  [Assign, ~, [4, 9], 12, Str], # 13
  [PostfixDeref, {sigil: "@"}, [1, 13], ~, Array], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Parameter, {index: 2, name: $e, sigil: $}, ~, ~, Num], # 16
  [Parameter, {index: 3, name: $p, sigil: $}, ~, ~, Num], # 17
  [NumEq, ~, [16, 17], ~, Boolean], # 18
  [And, ~, [18, 1], ~, Unknown], # 19
  [If, ~, [13, 19], 13], # 20
  [Proj, {index: 0}, [20]], # 21
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [14, 15, 13], 21, Int], # 22
  [Proj, {index: 1}, [20]], # 23
  [Region, {head: 20}, [22, 23]], # 24
  [Phi, {predecessors: [21, 23], region: 24}, [22, 19], ~, Unknown], # 25
  [Proj, {index: 1}, [11]], # 26
  [Assign, ~, [4, 8], 26, Str], # 27
  [PostfixDeref, {sigil: "@"}, [1, 27], ~, Array], # 28
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 29
  [If, ~, [27, 19], 27], # 30
  [Proj, {index: 0}, [30]], # 31
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [28, 29, 27], 31, Int], # 32
  [Proj, {index: 1}, [30]], # 33
  [Region, {head: 30}, [32, 33]], # 34
  [Phi, {predecessors: [31, 33], region: 34}, [32, 19], ~, Unknown], # 35
  [Region, {head: 11}, [24, 34]], # 36
  [Phi, {predecessors: [12, 26], region: 36}, [25, 35], ~, Unknown], # 37
  [Return, {implicit: true}, [37], 36], # 38
  [Phi, {memory: true, predecessors: [21, 23], region: 24}, [22, 13], ~, Str], # 39
  [Phi, {memory: true, predecessors: [31, 33], region: 34}, [32, 27], ~, Str], # 40
  [Phi, {memory: true, predecessors: [12, 26], region: 36}, [39, 40], ~, Str]]} # 41
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1], 4, Unknown], # 5
  [Return, {implicit: true}, [5], 5]]} # 6
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
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [PadAccess, {shared: 1, sigil: "%", symbol: c}, ~, ~, Unknown], # 3
  [Subscript, {kind: hash}, [3, 2], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int], # 6
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, [2], 6, List], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 9
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, [9], 7, List], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 13
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, [13], 10, List], # 14
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 15
  [DefinedOr, ~, [14, 15], ~, List], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 18
  [Print, ~, [8, 11, 12, 17, 18], 14, Scalar], # 19
  [Return, {implicit: true}, [1], 19]]} # 20
main::f: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Return, {implicit: true}, [1], 0]]} # 2
main::g: {start: 0, returns: [32], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 4
  [MemStart], # 5
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [5], ~, Scalar], # 6
  [Parameter, {index: 0, name: $k, sigil: $}, ~, ~, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 9
  [StrEq, ~, [8, 9], ~, Boolean], # 10
  [If, ~, [0, 10], 0], # 11
  [Proj, {index: 1}, [11]], # 12
  [PadAccess, {shared: 1, sigil: "%", symbol: c}, ~, ~, Unknown], # 13
  [Exists, {kind: hash}, [13, 7, 5], ~, Boolean], # 14
  [If, ~, [12, 14], 12], # 15
  [Proj, {index: 0}, [15]], # 16
  [Call, {dispatch_kind: direct, name: main::f, param_names: []}, ~, 16, Int], # 17
  [Region, {eval_entry: 16}, [17]], # 18
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [17], 18, Scalar], # 19
  [EntryWrite, ~, [4, 6, 17], 19, Unknown], # 20
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 21
  [Phi, {region: 18}, [2, 21], ~, Scalar], # 22
  [If, ~, [20, 22], 20], # 23
  [Proj, {index: 0}, [23]], # 24
  [Proj, {index: 1}, [15]], # 25
  [Region, {head: 15}, [24, 25]], # 26
  [Phi, {predecessors: [16, 25], region: 26}, [2, 3], ~, Int], # 27
  [Proj, {index: 0}, [11]], # 28
  [Region, {head: 11}, [28, 26]], # 29
  [Phi, {predecessors: [28, 12], region: 29}, [1, 27], ~, List], # 30
  [Phi, {predecessors: [28, 12], region: 29}, [21, 27], ~, Scalar], # 31
  [Return, ~, [30, 31], 29], # 32
  [Phi, {memory: true, predecessors: [16, 25], region: 26}, [20, 5], ~, Unknown], # 33
  [Proj, {index: 1}, [23]], # 34
  [Constant, {const_type: string, value: "A: "}, ~, ~, Str], # 35
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 36
  [Concat, ~, [35, 36], ~, Str], # 37
  [Unwind, ~, [37], 34]]} # 38
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1], 4, Unknown], # 5
  [Return, {implicit: true}, [5], 5]]} # 6
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
  [PadAccess, {sigil: $, symbol: s}, [3], ~, Unknown], # 4
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int], # 6
  [PadAccess, {sigil: $, symbol: t}, [6], ~, Unknown], # 7
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 8
  [Assign, ~, [7, 8], 6, Int], # 9
  [PadAccess, {sigil: $, symbol: s}, [9], ~, Unknown], # 10
  [PadAccess, {sigil: $, symbol: t}, [9], ~, Unknown], # 11
  [ArrayLiteral, ~, [10, 11], ~, Array], # 12
  [ArrayLiteral, ~, ~, ~, Array], # 13
  [TernaryExpr, ~, [2, 12, 13], ~, Array], # 14
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: void}, [14], 9, Int], # 15
  [PadAccess, {sigil: $, symbol: s}, [15], ~, Str], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [PadAccess, {sigil: $, symbol: t}, [15], ~, Str], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Concat, ~, [19, 21], ~, Str], # 22
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 23
  [Concat, ~, [22, 23], ~, Str], # 24
  [Print, ~, [24], 15, Scalar], # 25
  [Return, {implicit: true}, [1], 25]]} # 26
main::g: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "42"}, ~, ~, Int], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [Assign, ~, [4, 1], 0, Int], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
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
O::m: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [Assign, ~, [4, 1], 0, Int], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
O::new: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [HashLiteral, ~, ~, 0, HashRef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [2, 3], 1, Scalar], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [1, 4, 4], ~, Unknown], # 5
  [Return, {implicit: true}, [5], 4]]} # 6
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Unknown], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Call, {class_name: O, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 0, Object], # 1
  [PadAccess, {sigil: $, symbol: x}, [1], ~, Unknown], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Assign, ~, [2, 3], 1, Int], # 4
  [PadAccess, {sigil: $, symbol: x}, [4], ~, Unknown], # 5
  [Call, {class_name: O, dispatch_kind: method, name: m, param_names: [], want: void}, [1, 5], 4, Unknown], # 6
  [PadAccess, {sigil: $, symbol: x}, [6], ~, Unknown], # 7
  [Return, ~, [7], 6]]} # 8
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
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [1, 2], 0, Scalar], # 3
  [HashLiteral, ~, [1], 3, HashRef], # 4
  [Constant, {const_type: string, value: K}, ~, ~, Str], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [4, 5, 3], ~, Unknown], # 6
  [Return, {implicit: true}, [6], 4]]} # 7
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: S}, ~, ~, Str], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 1], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: P}, ~, ~, Str], # 6
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [1, 6], 3, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [4, 5, 8, 9], 7, Scalar], # 10
  [Return, {implicit: true}, [1], 10]]} # 11
main::f: {start: 0, returns: [29], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Constant, {const_type: string, value: K}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: name}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 5
  [MemStart], # 6
  [PadAccess, {sigil: $, symbol: s}, [6], ~, Unknown], # 7
  [PadAccess, {sigil: $, symbol: p}, [6], ~, Unknown], # 8
  [ArgsSource, ~, ~, ~, Array], # 9
  [Assign, {targets: 2}, [7, 8, 9], 0, List], # 10
  [PadAccess, {sigil: $, symbol: s}, [10], ~, Unknown], # 11
  [Defined, ~, [11], ~, Boolean], # 12
  [Constant, {const_type: string, value: superclass}, ~, ~, Str], # 13
  [ArrayLiteral, ~, [13, 11], ~, Array], # 14
  [ArrayLiteral, ~, ~, ~, Array], # 15
  [TernaryExpr, ~, [12, 14, 15], ~, Array], # 16
  [PadAccess, {sigil: $, symbol: p}, [10], ~, Unknown], # 17
  [Defined, ~, [17], ~, Boolean], # 18
  [Constant, {const_type: string, value: parent}, ~, ~, Str], # 19
  [ArrayLiteral, ~, [19, 17], ~, Array], # 20
  [ArrayLiteral, ~, ~, ~, Array], # 21
  [TernaryExpr, ~, [18, 20, 21], ~, Array], # 22
  [Call, {class_name: K, dispatch_kind: method, name: new, param_names: [], want: scalar}, [3, 4, 5, 16, 22], 10, Object], # 23
  [Loop, {bound: entry}, [23], 23], # 24
  [Phi, {region: 24}, [2, 43], ~, Array], # 25
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 25, 23], ~, Str], # 26
  [Proj, {index: 1}, [24]], # 27
  [Region, {head: 24}, [27]], # 28
  [Return, ~, [26], 28], # 29
  [PostfixDeref, {sigil: "%"}, [23, 23], ~, Hash], # 30
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [30, 23], ~, List], # 31
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [31, 23], ~, List], # 32
  [Count, ~, [32, 23], ~, Int], # 33
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 34
  [Phi, {region: 24}, [34, 47], ~, Int], # 35
  [Subscript, {kind: array}, [32, 35, 23], ~, Scalar], # 36
  [Subscript, {kind: hash}, [23, 36, 23], ~, Scalar], # 37
  [Coerce, {from_repr: Unknown, to_repr: Str}, [36], ~, Str], # 38
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 39
  [Concat, ~, [38, 39], ~, Str], # 40
  [Coerce, {from_repr: Unknown, to_repr: Str}, [37], ~, Str], # 41
  [Concat, ~, [40, 41], ~, Str], # 42
  [ListAppend, {collector: map}, [25, 42], ~, Array], # 43
  [NumGt, ~, [33, 35], 24, Boolean], # 44
  [Proj, {index: 0}, [24]], # 45
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 46
  [Add, ~, [35, 46], ~, Int]]} # 47
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, [3], ~, Unknown], # 4
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 5
  [ArrayLiteral, {sigil: "@", symbol: p}, [5], 0, Array], # 6
  [Assign, ~, [4, 6], 6, List], # 7
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:1:4, param_names: [], want: void}, [2], 7, Int], # 8
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:1:4, param_names: [], want: void}, [1], 8, Int], # 9
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [9], ~, Scalar], # 10
  [Coerce, {from_repr: Scalar, to_repr: Str}, [10], ~, Str], # 11
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, [9], ~, Unknown], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [11, 12, 9], ~, Str], # 13
  [Constant, {const_type: string, value: "/"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 16
  [ArrayLiteral, {sigil: "@", symbol: p}, ~, 9, Array], # 17
  [Assign, ~, [12, 17], 17, List], # 18
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:1:4, param_names: [], want: void}, [16], 18, Int], # 19
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, [19], ~, Unknown], # 20
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [11, 20, 19], ~, Str], # 21
  [Concat, ~, [15, 21], ~, Str], # 22
  [Return, ~, [22], 19], # 23
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Scalar], # 24
  [MakeCell, {captured_written: false, cell_name: "@p"}, [24, 7], ~, Ref], # 25
  [AnonSub, {captures: ["@p"], name: main::f::__ANON__:1:4}, [25], ~, CodeRef]]} # 26
main::f::__ANON__:1:4: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Unknown], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [1, 5, 4], 0, Int], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Scalar], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, [3], ~, Unknown], # 4
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [HashLiteral, {sigil: "%", symbol: h}, [5, 6], 0, Hash], # 7
  [Assign, ~, [4, 7], 7, List], # 8
  [MakeCell, {captured_written: false, cell_name: "%h"}, [2, 8], ~, Ref], # 9
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, [9], ~, Unknown], # 10
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [10, 9], ~, List], # 11
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [11, 9], ~, List], # 12
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 14
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:1:4, param_names: [], want: void}, [14], 8, Int], # 15
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, [15], ~, Unknown], # 16
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [16, 15], ~, List], # 17
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [17, 15], ~, List], # 18
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 19
  [HashLiteral, {sigil: "%", symbol: h}, ~, 15, Hash], # 20
  [Assign, ~, [16, 20], 20, List], # 21
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:1:4, param_names: [], want: void}, [19], 21, Int], # 22
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, [22], ~, Unknown], # 23
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [23, 22], ~, List], # 24
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [24, 22], ~, List], # 25
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 12, 13, 18, 13, 25, 22], ~, Str], # 26
  [Return, ~, [26], 22], # 27
  [AnonSub, {captures: ["%h"], name: main::f::__ANON__:1:4}, [9], ~, CodeRef]]} # 28
main::f::__ANON__:1:4: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Unknown], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [3, 4, 5], ~, Scalar], # 6
  [Subscript, {kind: hash}, [2, 6], ~, Scalar], # 7
  [Assign, ~, [7, 1], 0, Int], # 8
  [Return, {implicit: true}, [1], 8]]} # 9
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
  [Phi, {memory: true, region: 3}, [2, 39], ~, Unknown], # 4
  [Proj, {index: 1}, [3]], # 5
  [Region, {head: 3}, [5]], # 6
  [Phi, {memory: true, region: 6}, [4], ~, Unknown], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [7], ~, Scalar], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 11
  [ArrayLiteral, {sigil: "@", symbol: a}, [10, 11], ~, Array], # 12
  [PostfixDeref, {sigil: "@"}, [12, 7], ~, Array], # 13
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [9, 13, 7], ~, Str], # 14
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [PadAccess, {sigil: "@", symbol: r}, ~, ~, Unknown], # 17
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [9, 17, 7], ~, Str], # 18
  [Concat, ~, [16, 18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [Print, ~, [21], 6, Scalar], # 22
  [Return, {implicit: true}, [1], 22], # 23
  [Count, ~, [12, 4], ~, Int], # 24
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 25
  [Phi, {region: 3}, [25, 32], ~, Int], # 26
  [NumGt, ~, [24, 26], 3, Boolean], # 27
  [Proj, {index: 0}, [3]], # 28
  [PadAccess, {sigil: $, symbol: i}, [4], ~, Unknown], # 29
  [Subscript, {kind: array}, [12, 26, 4], ~, Int], # 30
  [Assign, ~, [29, 30], 28, Int], # 31
  [Add, ~, [26, 10], ~, Int], # 32
  [Subscript, {kind: array}, [12, 26], ~, Scalar], # 33
  [PadAccess, {sigil: $, symbol: i}, [31], ~, Unknown], # 34
  [Call, {dispatch_kind: direct, name: main::__PROGRAM__::__ANON__:3:17, param_names: [], want: scalar}, [34, 10], 31, Num], # 35
  [Count, ~, [12, 2], ~, Int], # 36
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [17, 35, 35], 35, Int], # 37
  [PadAccess, {sigil: $, symbol: i}, [37], ~, Unknown], # 38
  [Assign, {if_changed: true}, [33, 38], 37, Unknown]]} # 39
main::__PROGRAM__::__ANON__:3:17: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Num], # 1
  [Parameter, {index: 1, name: $y, sigil: $}, ~, ~, Num], # 2
  [Add, ~, [1, 2], ~, Num], # 3
  [Return, {implicit: true}, [3], 0]]} # 4
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: each}, [0], 0], # 2
  [Phi, {region: 2}, [1, 21], ~, Str], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Return, {implicit: true}, [3], 5], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 8
  [ArrayLiteral, {sigil: "@", symbol: w}, [7, 8], ~, Array], # 9
  [MemStart], # 10
  [Phi, {memory: true, region: 2}, [10, 19], ~, Unknown], # 11
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [9, 11], 2, Int], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [NumNe, ~, [12, 13], 2, Boolean], # 14
  [Proj, {index: 0}, [2]], # 15
  [PadAccess, {sigil: $, symbol: "n"}, [12], ~, Unknown], # 16
  [Assign, ~, [16, 12], 12, Int], # 17
  [PadAccess, {sigil: $, symbol: "n"}, [17], ~, Unknown], # 18
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, [18], 15, Str], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 20
  [Concat, ~, [3, 20], ~, Str], # 21
  [Phi, {memory: true, region: 5}, [11], ~, Unknown]]} # 22
main::g: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "<"}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Constant, {const_type: string, value: ">"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Return, {implicit: true}, [9], 0]]} # 10
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
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, [4], ~, Unknown], # 5
  [Constant, {const_type: string, value: v}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 7
  [HashLiteral, ~, [6, 7], 0, HashRef], # 8
  [HashLiteral, {sigil: "%", symbol: h}, [2, 8], 8, Hash], # 9
  [Assign, ~, [5, 9], 9, List], # 10
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3], 10, Unknown], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 13
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [13, 3], 11, Unknown], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 16], 14, Unknown], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Print, ~, [12, 15, 18, 19], 17, Scalar], # 20
  [Return, {implicit: true}, [1], 20]]} # 21
main::f: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: "on"}, ~, ~, Unknown], # 1
  [PadAccess, {shared: 1, sigil: "%", symbol: h}, ~, ~, Unknown], # 2
  [PadAccess, {sigil: $, symbol: k}, ~, ~, Unknown], # 3
  [MemStart], # 4
  [Subscript, {kind: hash}, [2, 3, 4], ~, Scalar], # 5
  [And, ~, [1, 5], ~, Unknown], # 6
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 7
  [TernaryExpr, ~, [1, 5, 7], ~, Unknown], # 8
  [Constant, {const_type: string, value: v}, ~, ~, Str], # 9
  [Subscript, {kind: hash}, [8, 9, 4], ~, Scalar], # 10
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 11
  [TernaryExpr, {rebind_arm: 1}, [6, 10, 11], 0, Unknown], # 12
  [Return, ~, [12], 12], # 13
  [ArgsSource, ~, ~, ~, Array], # 14
  [Assign, {targets: 2}, [3, 1, 14], ~, List], # 15
  [TernaryExpr, ~, [1, 2, 7], ~, Unknown]]} # 16
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
K::__DEFAULT_0: {start: 0, returns: [10], nodes: [
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
  [Return, {implicit: true}, [9], 8]]} # 10
K::g: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, List], # 1
  [Constant, {const_type: string, value: r}, ~, ~, Str], # 2
  [Subscript, {kind: hash}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: "7"}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 8
  [Subscript, {kind: hash}, [1, 8, 5], ~, Scalar], # 9
  [PostfixDeref, {sigil: "@"}, [9, 5], ~, Array], # 10
  [Count, ~, [10, 5], ~, Int], # 11
  [Coerce, {from_repr: Int, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [7, 12], ~, Str], # 13
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [1, 5], ~, List], # 15
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [15, 5], ~, List], # 16
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [14, 16, 5], ~, Str], # 17
  [Concat, ~, [13, 17], ~, Str], # 18
  [Return, {implicit: true}, [18], 0]]} # 19
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: K}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [Call, {class_name: K, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 3, Object], # 4
  [Call, {class_name: K, dispatch_kind: method, name: g, param_names: [], want: list}, [4], 4, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, Scalar], # 8
  [Return, {implicit: true}, [1], 8]]} # 9
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: experimental, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "ab@xcd"}, ~, ~, Str], # 2
  [Call, {dispatch_kind: direct, name: main::run, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Return, {implicit: true}, [1], 6]]} # 7
main::g: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Add, ~, [5, 6], ~, Num], # 7
  [Return, {implicit: true}, [7], 0]]} # 8
main::run: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: in}, [2], ~, Unknown], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Assign, {targets: 1}, [3, 4], 0, List], # 5
  [PadAccess, {sigil: $, symbol: pos}, [5], ~, Unknown], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Assign, ~, [6, 7], 5, Int], # 8
  [Loop, {bound: each}, [8], 8], # 9
  [Phi, {region: 9}, [1, 32], ~, Str], # 10
  [Proj, {index: 1}, [9]], # 11
  [Region, {head: 9}, [11]], # 12
  [Return, ~, [10], 12], # 13
  [Phi, {memory: true, region: 9}, [8, 36], ~, Scalar], # 14
  [PadAccess, {sigil: $, symbol: in}, [14], ~, Str], # 15
  [PadAccess, {sigil: $, symbol: pos}, [14], ~, Num], # 16
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 17
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [15, 16, 17], ~, Str], # 18
  [Concat, ~, [10, 18], ~, Str], # 19
  [Increment, ~, [16], ~, Scalar], # 20
  [Proj, {index: 0}, [9]], # 21
  [Constant, {const_type: string, value: "@"}, ~, ~, Str], # 22
  [StrEq, ~, [18, 22], ~, Boolean], # 23
  [If, ~, [21, 23], 21], # 24
  [Proj, {index: 1}, [24]], # 25
  [Assign, ~, [16, 20], 25, Scalar], # 26
  [Proj, {index: 0}, [24]], # 27
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, [15, 16], 27, Num], # 28
  [PadAccess, {sigil: $, symbol: pos}, [28], ~, Unknown], # 29
  [Assign, ~, [29, 28], 28, Num], # 30
  [Region, {head: 9}, [26, 30]], # 31
  [Phi, {predecessors: [25, 27], region: 31}, [19, 10], ~, Str], # 32
  [Phi, {memory: true, region: 12}, [14], ~, Scalar], # 33
  [Length, ~, [15], ~, Int], # 34
  [NumLt, ~, [16, 34], 9, Boolean], # 35
  [Phi, {memory: true, predecessors: [25, 27], region: 31}, [26, 30], ~, Scalar]]} # 36
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
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "ab@xcd@yz"}, ~, ~, Str], # 2
  [Call, {dispatch_kind: direct, name: main::run, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: "ab@x"}, ~, ~, Str], # 6
  [Call, {dispatch_kind: direct, name: main::run, param_names: [], want: list}, [6], 3, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [4, 5, 8, 9], 7, Scalar], # 10
  [Return, {implicit: true}, [1], 10]]} # 11
main::run: {start: 0, returns: [47], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: each}, [0], 0], # 2
  [Phi, {region: 2}, [1, 53], ~, Str], # 3
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [MemStart], # 6
  [PadAccess, {sigil: "@", symbol: err}, ~, ~, Scalar], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Phi, {region: 2}, [8, 50], ~, Int], # 9
  [Proj, {index: 0}, [2]], # 10
  [PadAccess, {sigil: $, symbol: in}, ~, ~, Str], # 11
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 12
  [Call, {dispatch_kind: builtin, name: substr, param_names: []}, [11, 9, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "@"}, ~, ~, Str], # 14
  [StrEq, ~, [13, 14], ~, Boolean], # 15
  [If, ~, [10, 15], 10], # 16
  [Proj, {index: 0}, [16]], # 17
  [Count, ~, [7, 6], ~, Int], # 18
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 19
  [NumLt, ~, [18, 19], ~, Boolean], # 20
  [If, ~, [17, 20], 17], # 21
  [Proj, {index: 0}, [21]], # 22
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [7, 9, 6], 22, Int], # 23
  [Proj, {index: 1}, [16]], # 24
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 25
  [Add, ~, [9, 25], ~, Int], # 26
  [Length, ~, [11], ~, Int], # 27
  [NumLt, ~, [26, 27], ~, Boolean], # 28
  [If, ~, [23, 28], 23], # 29
  [Proj, {index: 0}, [29]], # 30
  [Loop, {bound: entry}, [30], 30], # 31
  [Proj, {index: 1}, [31]], # 32
  [Region, {head: 31}, [32]], # 33
  [Region, {head: 2}, [24, 33]], # 34
  [Phi, {memory: true, predecessors: [24, 30], region: 34}, [6, 23], ~, Unknown], # 35
  [Proj, {index: 1}, [21]], # 36
  [Proj, {index: 1}, [29]], # 37
  [Region, {head: 21}, [36, 37]], # 38
  [Phi, {memory: true, predecessors: [36, 22], region: 38}, [6, 23], ~, Unknown], # 39
  [Proj, {index: 1}, [2]], # 40
  [Region, {head: 2}, [40, 38]], # 41
  [Phi, {memory: true, region: 41}, [35, 39], ~, Unknown], # 42
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [42], ~, Scalar], # 43
  [Coerce, {from_repr: Scalar, to_repr: Str}, [43], ~, Str], # 44
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [44, 7, 42], ~, Str], # 45
  [Concat, ~, [5, 45], ~, Str], # 46
  [Return, ~, [46], 41], # 47
  [NumLt, ~, [9, 27], 2, Boolean], # 48
  [Add, ~, [9, 12], ~, Int], # 49
  [Phi, {predecessors: [24, 30], region: 34}, [49, 26], ~, Int], # 50
  [Concat, ~, [3, 13], ~, Str], # 51
  [Phi, {region: 31}, [3, 62], ~, Str], # 52
  [Phi, {predecessors: [24, 30], region: 34}, [51, 52], ~, Str], # 53
  [ArgsSource, ~, ~, ~, Array], # 54
  [Assign, {targets: 1}, [11, 54], ~, List], # 55
  [Constant, {const_type: string, value: "<"}, ~, ~, Str], # 56
  [Concat, ~, [52, 56], ~, Str], # 57
  [Phi, {region: 31}, [12, 63], ~, Int], # 58
  [Coerce, {from_repr: Int, to_repr: Str}, [58], ~, Str], # 59
  [Concat, ~, [57, 59], ~, Str], # 60
  [Constant, {const_type: string, value: ">"}, ~, ~, Str], # 61
  [Concat, ~, [60, 61], ~, Str], # 62
  [Add, ~, [58, 12], ~, Int], # 63
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 64
  [NumGt, ~, [64, 58], 31, Boolean], # 65
  [Proj, {index: 0}, [31]]]} # 66
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
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 4
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3, 4], 0, Unknown], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, Scalar], # 8
  [Return, {implicit: true}, [1], 8]]} # 9
main::f: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: "n"}, [1], ~, Unknown], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Assign, ~, [2, 3], 0, Int], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Phi, {memory: true, region: 5}, [4, 21], ~, Scalar], # 6
  [Proj, {index: 1}, [5]], # 7
  [Region, {head: 5}, [7]], # 8
  [Phi, {memory: true, region: 8}, [6], ~, Scalar], # 9
  [PadAccess, {sigil: $, symbol: "n"}, [9], ~, Unknown], # 10
  [Region, {eval_entry: 4}, [8]], # 11
  [Return, ~, [10], 11], # 12
  [ArgsSource, ~, ~, ~, Array], # 13
  [Count, ~, [13, 4], ~, Int], # 14
  [Phi, {region: 5}, [3, 23], ~, Int], # 15
  [Count, ~, [13, 6], ~, Int], # 16
  [NumGt, ~, [16, 15], 5, Boolean], # 17
  [Proj, {index: 0}, [5]], # 18
  [PadAccess, {sigil: $, symbol: "n"}, [6], ~, Unknown], # 19
  [Subscript, {kind: array}, [13, 15, 6], ~, Scalar], # 20
  [Assign, ~, [19, 20], 18, Scalar], # 21
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 22
  [Add, ~, [15, 22], ~, Int], # 23
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 24
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 25
  [StrEq, ~, [24, 25], ~, Boolean], # 26
  [If, ~, [21, 26], 21], # 27
  [Proj, {index: 0}, [27]], # 28
  [Proj, {index: 1}, [27]], # 29
  [Constant, {const_type: string, value: "d\n"}, ~, ~, Str], # 30
  [Unwind, ~, [30], 28], # 31
  [Region, {head: 27}, [31, 29]]]} # 32
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
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 0, Unknown], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [5], 3, Unknown], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [4, 7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
main::f: {start: 0, returns: [32], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: x}, [2], ~, Unknown], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Assign, ~, [3, 4], 0, Int], # 5
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [5], ~, Scalar], # 6
  [PadAccess, {sigil: $, symbol: x}, [5], ~, Unknown], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Assign, ~, [7, 8], 5, Int], # 9
  [PadAccess, {sigil: $, symbol: x}, [9], ~, Unknown], # 10
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 11
  [Parameter, {index: 0, name: $d, sigil: $}, ~, ~, Unknown], # 12
  [If, ~, [9, 12], 9], # 13
  [Proj, {index: 1}, [13]], # 14
  [Constant, {const_type: string, value: "no\n"}, ~, ~, Str], # 15
  [Proj, {index: 0}, [13]], # 16
  [Unwind, ~, [15], 16], # 17
  [Region, {head: 13}, [14, 17]], # 18
  [Assign, ~, [10, 11], 18, Int], # 19
  [Region, {eval_entry: 5}, [19]], # 20
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [19], 20, Scalar], # 21
  [EntryWrite, ~, [1, 6, 19], 21, Unknown], # 22
  [PadAccess, {sigil: $, symbol: x}, [22], ~, Unknown], # 23
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 24
  [Phi, {region: 20}, [8, 24], ~, Scalar], # 25
  [If, ~, [22, 25], 22], # 26
  [Proj, {index: 0}, [26]], # 27
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 28
  [Proj, {index: 1}, [26]], # 29
  [Print, ~, [28], 29, Scalar], # 30
  [Region, {head: 26}, [27, 30]], # 31
  [Return, ~, [23], 31], # 32
  [Phi, {predecessors: [27, 29], region: 31}, [11, 30], ~, Scalar]]} # 33
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1], 4, Unknown], # 5
  [Return, {implicit: true}, [5], 5]]} # 6
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
O::m: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 6
  [StrEq, ~, [5, 6], ~, Boolean], # 7
  [Call, {dispatch_kind: builtin, name: uc, param_names: []}, [4], ~, Str], # 8
  [And, ~, [7, 8], ~, Scalar], # 9
  [If, ~, [0, 7], 0], # 10
  [Proj, {index: 1}, [10]], # 11
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 12
  [Proj, {index: 0}, [10]], # 13
  [Assign, ~, [12, 8], 13, Str], # 14
  [Region, {head: 10}, [11, 14]], # 15
  [Return, {implicit: true}, [9], 15], # 16
  [Phi, {memory: true, predecessors: [11, 13], region: 15}, [3, 14], ~, Unknown]]} # 17
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {memory: true, region: 3}, [2, 37], ~, Unknown], # 4
  [Proj, {index: 1}, [3]], # 5
  [Region, {head: 3}, [5]], # 6
  [Phi, {memory: true, region: 6}, [4], ~, Unknown], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [7], ~, Scalar], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 12
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [10, 11, 12], ~, List], # 13
  [ArrayLiteral, {sigil: "@", symbol: "n"}, [13], ~, Array], # 14
  [PostfixDeref, {sigil: "@"}, [14, 7], ~, Array], # 15
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [9, 15, 7], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [Print, ~, [18], 6, Scalar], # 19
  [Return, {implicit: true}, [1], 19], # 20
  [Count, ~, [14, 4], ~, Int], # 21
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 22
  [Phi, {region: 3}, [22, 30], ~, Int], # 23
  [NumGt, ~, [21, 23], 3, Boolean], # 24
  [Proj, {index: 0}, [3]], # 25
  [PadAccess, {sigil: $, symbol: x}, [4], ~, Unknown], # 26
  [Subscript, {kind: array}, [14, 23, 4], ~, Scalar], # 27
  [Assign, ~, [26, 27], 25, Scalar], # 28
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 29
  [Add, ~, [23, 29], ~, Int], # 30
  [Subscript, {kind: array}, [14, 23], ~, Scalar], # 31
  [PadAccess, {sigil: $, symbol: x}, [28], ~, Unknown], # 32
  [Constant, {const_type: string, value: O}, ~, ~, Str], # 33
  [Call, {class_name: O, dispatch_kind: method, name: m, param_names: [], want: void}, [33, 32], 28, Unknown], # 34
  [Count, ~, [14, 2], ~, Int], # 35
  [PadAccess, {sigil: $, symbol: x}, [34], ~, Unknown], # 36
  [Assign, {if_changed: true}, [31, 36], 34, Unknown]]} # 37
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 37], ~, Str], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Return, {implicit: true}, [3], 5], # 6
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 8
  [ArrayLiteral, ~, [7, 8], ~, Array], # 9
  [MemStart], # 10
  [Count, ~, [9, 10], ~, Int], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Phi, {region: 2}, [12, 39], ~, Int], # 13
  [NumGt, ~, [11, 13], 2, Boolean], # 14
  [Proj, {index: 0}, [2]], # 15
  [Subscript, {kind: array}, [9, 13, 10], ~, Str], # 16
  [Concat, ~, [3, 16], ~, Str], # 17
  [ArrayLiteral, ~, ~, ~, Array], # 18
  [Loop, {bound: entry}, [15], 15], # 19
  [Phi, {region: 19}, [18, 60], ~, Array], # 20
  [Subscript, {kind: array}, [20, 12, 10], ~, Scalar], # 21
  [Proj, {index: 1}, [19]], # 22
  [Region, {head: 19}, [22]], # 23
  [Count, ~, [20, 10], ~, Int], # 24
  [If, ~, [23, 24], 23], # 25
  [Proj, {index: 0}, [25]], # 26
  [Loop, {bound: entry}, [26], 26], # 27
  [Phi, {region: 27}, [21, 66], ~, Scalar], # 28
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 29
  [Concat, ~, [17, 29], ~, Str], # 30
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 31
  [Concat, ~, [30, 31], ~, Str], # 32
  [Proj, {index: 1}, [25]], # 33
  [Proj, {index: 1}, [27]], # 34
  [Region, {head: 27}, [34]], # 35
  [Region, {head: 25}, [33, 35]], # 36
  [Phi, {predecessors: [33, 26], region: 36}, [3, 32], ~, Str], # 37
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 38
  [Add, ~, [13, 38], ~, Int], # 39
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 40
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 41
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 42
  [ArrayLiteral, ~, [40, 41, 42], ~, List], # 43
  [Count, ~, [43, 10], ~, Int], # 44
  [Phi, {region: 19}, [12, 63], ~, Int], # 45
  [NumGt, ~, [44, 45], 19, Boolean], # 46
  [Proj, {index: 0}, [19]], # 47
  [Subscript, {kind: array}, [43, 45, 10], ~, Str], # 48
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 49
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 50
  [HashLiteral, {sigil: "%", symbol: idom}, [40, 38, 41, 49, 42, 50], ~, Hash], # 51
  [Exists, {kind: hash}, [51, 48, 10], ~, Boolean], # 52
  [Subtract, ~, [24, 38], ~, Int], # 53
  [Range, ~, [38, 53], ~, List], # 54
  [Slice, {kind: array}, [54, 20], ~, List], # 55
  [ArrayLiteral, ~, [55], ~, Array], # 56
  [Count, ~, [56, 10], ~, Int], # 57
  [Phi, {region: 27}, [12, 64], ~, Int], # 58
  [Subscript, {kind: array}, [56, 58, 10], ~, Scalar], # 59
  [ListAppend, {collector: grep}, [20, 48, 52], ~, Array], # 60
  [NumGt, ~, [57, 58], 27, Boolean], # 61
  [Coerce, {from_repr: Unknown, to_repr: Str}, [59], ~, Str], # 62
  [Add, ~, [45, 38], ~, Int], # 63
  [Add, ~, [58, 38], ~, Int], # 64
  [Coerce, {from_repr: Scalar, to_repr: Str}, [28], ~, Str], # 65
  [Concat, ~, [65, 62], ~, Str], # 66
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
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
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
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [5, 10], 10, Str], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [12, 13], 11, Scalar], # 14
  [Return, {implicit: true}, [1], 14]]} # 15
main::f: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [1], ~, Scalar], # 2
  [Coerce, {from_repr: Scalar, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Parameter, {index: 0, name: $r, sigil: $}, ~, ~, Unknown], # 6
  [Slice, {kind: array}, [4, 5, 6], ~, List], # 7
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [3, 7, 1], ~, Str], # 8
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 12
  [Parameter, {index: 1, name: $h, sigil: $}, ~, ~, Unknown], # 13
  [Slice, {kind: hash}, [11, 12, 13], ~, List], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [3, 14, 1], ~, Str], # 15
  [Concat, ~, [10, 15], ~, Str], # 16
  [Return, ~, [16], 0], # 17
  [ArrayLiteral, {sigil: "@", symbol: b}, [14], ~, Array], # 18
  [ArrayLiteral, {sigil: "@", symbol: a}, [7], ~, Array]]} # 19
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
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
K::__DEFAULT_0: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, Array], # 4
  [Return, ~, [4], 0]]} # 5
K::s: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [1], ~, Scalar], # 2
  [Coerce, {from_repr: Scalar, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [FieldAccess, {field_index: 0, field_stash: K}, ~, ~, Array], # 6
  [Slice, {kind: array}, [4, 5, 6], ~, List], # 7
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [3, 7, 1], ~, Str], # 8
  [Return, {implicit: true}, [8], 0], # 9
  [ArrayLiteral, {sigil: "@", symbol: x}, [7], ~, Array]]} # 10
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: K}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [Call, {class_name: K, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 3, Object], # 4
  [Call, {class_name: K, dispatch_kind: method, name: s, param_names: [], want: list}, [4], 4, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, Scalar], # 8
  [Return, {implicit: true}, [1], 8]]} # 9
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: experimental, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 4
  [Call, {dispatch_kind: direct, name: main::order, param_names: [], want: list}, [2, 3, 4], 0, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: p}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: q}, ~, ~, Str], # 9
  [Call, {dispatch_kind: direct, name: main::order, param_names: [], want: list}, [8, 9], 5, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [6, 7, 11, 12], 10, Scalar], # 13
  [Return, {implicit: true}, [1], 13]]} # 14
main::order: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: "%", symbol: rpo}, [3], ~, Unknown], # 4
  [HashLiteral, ~, ~, ~, Hash], # 5
  [Assign, ~, [4, 5], 0, List], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {memory: true, region: 7}, [6, 27], ~, List], # 8
  [Proj, {index: 1}, [7]], # 9
  [Region, {head: 7}, [9]], # 10
  [Phi, {memory: true, region: 10}, [8], ~, List], # 11
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp_body: main::order::__SORTCMP__:1, sort_package: main, want: list}, [2, 11], 10, List], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 12, 12], ~, Str], # 13
  [Return, ~, [13], 12], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: reverse, param_names: []}, [2, 6], ~, List], # 15
  [ArrayLiteral, ~, [15], ~, Array], # 16
  [Count, ~, [16, 6], ~, Int], # 17
  [Count, ~, [16, 8], ~, Int], # 18
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 19
  [Phi, {region: 7}, [19, 29], ~, Int], # 20
  [NumGt, ~, [18, 20], 7, Boolean], # 21
  [Proj, {index: 0}, [7]], # 22
  [PadAccess, {shared: 1, sigil: "%", symbol: rpo}, ~, ~, Unknown], # 23
  [Subscript, {kind: array}, [16, 20, 8], ~, Scalar], # 24
  [Subscript, {kind: hash}, [23, 24], ~, Scalar], # 25
  [Phi, {region: 7}, [19, 30], ~, Int], # 26
  [Assign, ~, [25, 26], 22, Int], # 27
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 28
  [Add, ~, [20, 28], ~, Int], # 29
  [Add, ~, [26, 28], ~, Int]]} # 30
main::order::__SORTCMP__:1: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "%", symbol: rpo}, ~, ~, Unknown], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: a}, [2], ~, Scalar], # 3
  [Subscript, {kind: hash}, [1, 3, 2], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [EntryDef, {package: main, sigil: $, symbol: b}, [2], ~, Scalar], # 6
  [Subscript, {kind: hash}, [1, 6, 2], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Num}, [7], ~, Num], # 8
  [NumCmp, ~, [5, 8], ~, Int], # 9
  [Return, {implicit: true}, [9], 0]]} # 10
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [MemStart], # 4
  [PadAccess, {shared: 1, sigil: "@", symbol: seen}, [4], ~, Unknown], # 5
  [ArrayLiteral, ~, ~, ~, Array], # 6
  [Assign, ~, [5, 6], 0, List], # 7
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:2:3, param_names: [], want: scalar}, [1, 2, 3], 7, Int], # 8
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 9
  [Call, {dispatch_kind: direct, name: main::f::__ANON__:2:3, param_names: [], want: scalar}, [9], 8, Int], # 10
  [Add, ~, [8, 10], ~, Int], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [10], ~, Scalar], # 15
  [Coerce, {from_repr: Scalar, to_repr: Str}, [15], ~, Str], # 16
  [PadAccess, {shared: 1, sigil: "@", symbol: seen}, [10], ~, Unknown], # 17
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [16, 17, 10], ~, Str], # 18
  [Concat, ~, [14, 18], ~, Str], # 19
  [Return, ~, [19], 10], # 20
  [PadAccess, {shared: 1, sigil: "@", symbol: seen}, ~, ~, Scalar], # 21
  [MakeCell, {captured_written: false, cell_name: "@seen"}, [21, 7], ~, Ref], # 22
  [AnonSub, {captures: ["@seen"], name: main::f::__ANON__:2:3}, [22], ~, CodeRef]]} # 23
main::f::__ANON__:2:3: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Parameter, {index: 1, name: "@rest", sigil: "@"}, ~, ~, Array], # 1
  [PadAccess, {shared: 1, sigil: "@", symbol: seen}, ~, ~, Unknown], # 2
  [Parameter, {index: 0, name: $id, sigil: $}, ~, ~, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: ":"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [MemStart], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [7], ~, Scalar], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [9, 1, 7], ~, Str], # 10
  [Concat, ~, [6, 10], ~, Str], # 11
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 11, 7], 0, Int], # 12
  [Count, ~, [1, 12], ~, Int], # 13
  [Return, ~, [13], 12]]} # 14
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
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
K::__DEFAULT_0: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 4
  [ArrayLiteral, ~, [1, 2, 3, 4], ~, ArrayRef], # 5
  [Return, ~, [5], 0]]} # 6
K::s: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [1], ~, Scalar], # 2
  [Coerce, {from_repr: Scalar, to_repr: Str}, [2], ~, Str], # 3
  [ArrayLiteral, ~, ~, ~, Array], # 4
  [Loop, {bound: entry}, [0], 0], # 5
  [Phi, {region: 5}, [4, 28], ~, Array], # 6
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [3, 6, 1], ~, Str], # 7
  [Proj, {index: 1}, [5]], # 8
  [Region, {head: 5}, [8]], # 9
  [Return, {implicit: true}, [7], 9], # 10
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 11
  [FieldAccess, {field_index: 0, field_stash: K}, [1], ~, ArrayRef], # 12
  [PostfixDeref, {sigil: "@"}, [12, 1], ~, Array], # 13
  [Count, ~, [13, 1], ~, Int], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Subtract, ~, [14, 15], ~, Int], # 16
  [Subtract, ~, [16, 15], ~, Int], # 17
  [Range, ~, [11, 17], ~, List], # 18
  [Slice, {kind: array}, [18, 12], ~, List], # 19
  [Count, ~, [19, 1], ~, Int], # 20
  [Phi, {region: 5}, [11, 29], ~, Int], # 21
  [NumGt, ~, [20, 21], 5, Boolean], # 22
  [Proj, {index: 0}, [5]], # 23
  [Subscript, {kind: array}, [19, 21, 1], ~, Scalar], # 24
  [Coerce, {from_repr: Scalar, to_repr: Num}, [24], ~, Num], # 25
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 26
  [NumGt, ~, [25, 26], ~, Boolean], # 27
  [ListAppend, {collector: grep}, [6, 24, 27], ~, Array], # 28
  [Add, ~, [21, 15], ~, Int]]} # 29
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: K}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [Call, {class_name: K, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 3, Object], # 4
  [Call, {class_name: K, dispatch_kind: method, name: s, param_names: [], want: list}, [4], 4, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, Scalar], # 8
  [Return, {implicit: true}, [1], 8]]} # 9
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: experimental, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Return, {implicit: true}, [4], 0]]} # 5
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3, 2], 0, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3, 6], 4, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [5, 8, 9], 7, Scalar], # 10
  [Return, {implicit: true}, [1], 10]]} # 11
main::f: {start: 0, returns: [40], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: O}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: l}, [2], ~, Unknown], # 3
  [Parameter, {index: 0, name: $l, sigil: $}, ~, ~, Unknown], # 4
  [Assign, ~, [3, 4], 0, Unknown], # 5
  [PadAccess, {sigil: $, symbol: r}, [5], ~, Unknown], # 6
  [Parameter, {index: 1, name: $r, sigil: $}, ~, ~, Unknown], # 7
  [Assign, ~, [6, 7], 5, Unknown], # 8
  [PadAccess, {sigil: $, symbol: l}, [8], ~, Unknown], # 9
  [Call, {class_name: O, dispatch_kind: method, name: m, param_names: [], want: void}, [1, 9], 8, Unknown], # 10
  [PadAccess, {sigil: $, symbol: r}, [10], ~, Unknown], # 11
  [Call, {class_name: O, dispatch_kind: method, name: m, param_names: [], want: void}, [1, 11], 10, Unknown], # 12
  [PadAccess, {sigil: $, symbol: c}, [12], ~, Unknown], # 13
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 14
  [Assign, ~, [13, 14], 12, Undef], # 15
  [PadAccess, {sigil: $, symbol: j}, [15], ~, Unknown], # 16
  [Assign, ~, [16, 14], 15, Undef], # 17
  [PadAccess, {sigil: $, symbol: c}, [17], ~, Unknown], # 18
  [PadAccess, {sigil: $, symbol: j}, [17], ~, Unknown], # 19
  [PadAccess, {sigil: $, symbol: l}, [17], ~, Unknown], # 20
  [PadAccess, {sigil: $, symbol: r}, [17], ~, Unknown], # 21
  [Parameter, {index: 2, name: $v, sigil: $}, ~, ~, Unknown], # 22
  [If, ~, [17, 22], 17], # 23
  [Proj, {index: 0}, [23]], # 24
  [Assign, {targets: 2}, [18, 19, 20, 21], 24, List], # 25
  [Proj, {index: 1}, [23]], # 26
  [Assign, {targets: 2}, [18, 19, 21, 20], 26, List], # 27
  [Region, {head: 23}, [25, 27]], # 28
  [Phi, {memory: true, predecessors: [24, 26], region: 28}, [25, 27], ~, List], # 29
  [PadAccess, {sigil: $, symbol: c}, [29], ~, Unknown], # 30
  [PadAccess, {sigil: $, symbol: j}, [29], ~, Unknown], # 31
  [Call, {class_name: O, dispatch_kind: method, name: m, param_names: [], want: void}, [1, 30, 31], 28, Unknown], # 32
  [PadAccess, {sigil: $, symbol: c}, [32], ~, Str], # 33
  [Coerce, {from_repr: Unknown, to_repr: Str}, [33], ~, Str], # 34
  [Constant, {const_type: string, value: ">"}, ~, ~, Str], # 35
  [Concat, ~, [34, 35], ~, Str], # 36
  [PadAccess, {sigil: $, symbol: j}, [32], ~, Str], # 37
  [Coerce, {from_repr: Unknown, to_repr: Str}, [37], ~, Str], # 38
  [Concat, ~, [36, 38], ~, Str], # 39
  [Return, ~, [39], 32], # 40
  [Phi, {predecessors: [24, 26], region: 28}, [20, 21], ~, Unknown], # 41
  [Phi, {predecessors: [24, 26], region: 28}, [21, 20], ~, Unknown]]} # 42
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [ArrayLiteral, ~, [1, 2], 0, ArrayRef], # 3
  [ArrayLiteral, ~, [3], 3, ArrayRef], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [4, 5], ~, ArrayRef], # 6
  [MemStart], # 7
  [Subscript, {kind: array}, [6, 5, 7], ~, Scalar], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Subscript, {kind: array}, [6, 1, 7], ~, Scalar], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [11, 13], ~, Str], # 14
  [Concat, ~, [14, 10], ~, Str], # 15
  [Subscript, {kind: array}, [6, 5], ~, Scalar], # 16
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 17
  [Assign, ~, [16, 17], 4, Int], # 18
  [Subscript, {kind: array}, [6, 5, 18], ~, Int], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 20
  [Concat, ~, [15, 20], ~, Str], # 21
  [Return, ~, [21], 18], # 22
  [PadAccess, {sigil: $, symbol: lv}, ~, ~, Unknown], # 23
  [PadAccess, {sigil: $, symbol: val}, ~, ~, Unknown], # 24
  [Assign, {targets: 2}, [23, 24, 8, 12], ~, List]]} # 25
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [12], nodes: [
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
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, ~, 0, List], # 10
  [Assign, {targets: 2}, [1, 5, 10], 10, List], # 11
  [Return, {implicit: true}, [9], 11]]} # 12
main::g: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [ArrayLiteral, ~, [1, 2], ~, List], # 3
  [Coerce, {from_repr: List, to_repr: Scalar}, [2], ~, Scalar], # 4
  [Return, {implicit: true}, [3, 4], 0]]} # 5
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
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [5], 3, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [4, 7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
main::f: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [PadAccess, {sigil: $, symbol: lo}, ~, ~, Unknown], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [3, 1, 4], ~, Scalar], # 5
  [If, ~, [0, 5], 0], # 6
  [Proj, {index: 1}, [6]], # 7
  [Proj, {index: 0}, [6]], # 8
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, ~, 8, List], # 9
  [Assign, {targets: 1}, [2, 9], 9, List], # 10
  [Region, {head: 6}, [7, 10]], # 11
  [Phi, {predecessors: [7, 8], region: 11}, [1, 2], ~, Unknown], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Return, {implicit: true}, [13], 11], # 14
  [Phi, {memory: true, predecessors: [7, 8], region: 11}, [4, 9], ~, Unknown]]} # 15
main::g: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [ArrayLiteral, ~, [1, 2], ~, List], # 3
  [Coerce, {from_repr: List, to_repr: Scalar}, [2], ~, Scalar], # 4
  [Return, {implicit: true}, [3, 4], 0]]} # 5
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
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "a\\nb-d]"}, ~, ~, Str], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Return, {implicit: true}, [1], 6]]} # 7
main::esc: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [1, 4, 5], ~, Scalar], # 6
  [Subscript, {kind: array}, [3, 6, 5], ~, Scalar], # 7
  [Call, {dispatch_kind: builtin, name: ord, param_names: []}, [7], ~, Int], # 8
  [Constant, {const_type: integer, value: "100"}, ~, ~, Int], # 9
  [Add, ~, [8, 9], ~, Int], # 10
  [ArrayLiteral, ~, [10, 4], ~, List], # 11
  [Coerce, {from_repr: List, to_repr: Scalar}, [4], ~, Scalar], # 12
  [Return, ~, [11, 12], 0]]} # 13
main::f: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Constant, {const_type: regex, value: ""}, ~, ~, Regex], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Subscript, {kind: array}, [3, 4, 1], ~, Scalar], # 5
  [Call, {dispatch_kind: builtin, name: split, param_names: []}, [2, 5, 4], ~, List], # 6
  [ArrayLiteral, {sigil: "@", symbol: chars}, [6], 0, Array], # 7
  [Loop, {bound: each}, [7], 7], # 8
  [Phi, {memory: true, region: 8}, [1, 68], ~, Unknown], # 9
  [Proj, {index: 1}, [8]], # 10
  [Proj, {index: 0}, [8]], # 11
  [Phi, {region: 8}, [4, 71], ~, Unknown], # 12
  [Subscript, {kind: array}, [7, 12, 9], ~, Scalar], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 15
  [StrEq, ~, [14, 15], ~, Boolean], # 16
  [If, ~, [11, 16], 11], # 17
  [Proj, {index: 0}, [17]], # 18
  [Region, {head: 8}, [10, 18]], # 19
  [Phi, {memory: true, region: 19}, [9, 9], ~, Unknown], # 20
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [20], ~, Scalar], # 21
  [Coerce, {from_repr: Scalar, to_repr: Str}, [21], ~, Str], # 22
  [PadAccess, {sigil: "@", symbol: ranges}, ~, ~, Unknown], # 23
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [22, 23, 20], ~, Str], # 24
  [Return, ~, [24], 19], # 25
  [Count, ~, [7, 9], ~, Int], # 26
  [Ref, ~, [7], ~, ArrayRef], # 27
  [PadAccess, {sigil: $, symbol: lo_used}, ~, ~, Num], # 28
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 29
  [Add, ~, [28, 29], ~, Num], # 30
  [PadAccess, {sigil: $, symbol: lo}, ~, ~, Unknown], # 31
  [Add, ~, [12, 29], ~, Unknown], # 32
  [Proj, {index: 1}, [17]], # 33
  [Constant, {const_type: string, value: "\\"}, ~, ~, Str], # 34
  [StrEq, ~, [14, 34], ~, Boolean], # 35
  [If, ~, [33, 35], 33], # 36
  [Proj, {index: 0}, [36]], # 37
  [Call, {dispatch_kind: direct, name: main::esc, param_names: [], want: list}, [27, 32], 37, List], # 38
  [Assign, {targets: 2}, [31, 28, 38], 38, List], # 39
  [Call, {dispatch_kind: builtin, name: ord, param_names: []}, [13], ~, Int], # 40
  [Proj, {index: 1}, [36]], # 41
  [Assign, {targets: 2}, [31, 28, 40, 29], 41, List], # 42
  [Region, {head: 36}, [39, 42]], # 43
  [Phi, {predecessors: [37, 41], region: 43}, [30, 29], ~, Num], # 44
  [Add, ~, [12, 44], ~, Unknown], # 45
  [Phi, {memory: true, predecessors: [37, 41], region: 43}, [39, 42], ~, List], # 46
  [Subscript, {kind: array}, [7, 45, 46], ~, Scalar], # 47
  [Add, ~, [45, 29], ~, Unknown], # 48
  [Subscript, {kind: array}, [7, 48, 46], ~, Scalar], # 49
  [Subtract, ~, [26, 29], ~, Int], # 50
  [NumLe, ~, [12, 50], 8, Boolean], # 51
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 52
  [DefinedOr, ~, [47, 52], ~, Scalar], # 53
  [Call, {dispatch_kind: builtin, name: ord, param_names: []}, [49], ~, Int], # 54
  [Phi, {predecessors: [37, 41], region: 43}, [31, 40], ~, Unknown], # 55
  [Coerce, {from_repr: Unknown, to_repr: Str}, [55], ~, Str], # 56
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 57
  [Concat, ~, [56, 57], ~, Str], # 58
  [Concat, ~, [58, 54], ~, Str], # 59
  [Coerce, {from_repr: Unknown, to_repr: Str}, [53], ~, Str], # 60
  [StrEq, ~, [60, 57], ~, Boolean], # 61
  [If, ~, [43, 61], 43], # 62
  [Proj, {index: 0}, [62]], # 63
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [23, 59, 46], 63, Int], # 64
  [Proj, {index: 1}, [62]], # 65
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [23, 55, 46], 65, Int], # 66
  [Region, {head: 8}, [66, 64]], # 67
  [Phi, {memory: true, predecessors: [65, 63], region: 67}, [66, 64], ~, Int], # 68
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 69
  [Add, ~, [45, 69], ~, Unknown], # 70
  [Phi, {predecessors: [65, 63], region: 67}, [45, 70], ~, Unknown]]} # 71
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
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "a,b"}, ~, ~, Str], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Return, {implicit: true}, [1], 6]]} # 7
main::f: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: regex, value: ","}, ~, ~, Regex], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Call, {dispatch_kind: builtin, name: split, param_names: []}, [1, 5, 3], ~, List], # 6
  [ArrayLiteral, {sigil: "@", symbol: c}, [6], 0, Array], # 7
  [Ref, ~, [7], ~, ArrayRef], # 8
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [7, 9, 4], 7, Int], # 10
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, [8], 10, Int], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [11], ~, Scalar], # 15
  [Coerce, {from_repr: Scalar, to_repr: Str}, [15], ~, Str], # 16
  [PostfixDeref, {sigil: "@"}, [7, 11], ~, Array], # 17
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [16, 17, 11], ~, Str], # 18
  [Concat, ~, [14, 18], ~, Str], # 19
  [Return, {implicit: true}, [19], 11]]} # 20
main::g: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [PostfixDeref, {sigil: "@"}, [4, 3], ~, Array], # 5
  [Count, ~, [5, 3], ~, Int], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3, 4, 5], 0, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 8
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3], 6, Str], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [7, 8, 10, 11], 9, Scalar], # 12
  [Return, {implicit: true}, [1], 12]]} # 13
main::f: {start: 0, returns: [42], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Proj, {index: 1}, [3]], # 4
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 5
  [MemStart], # 6
  [Phi, {memory: true, region: 3}, [6, 48], ~, Unknown], # 7
  [PadAccess, {sigil: $, symbol: c}, [7], ~, Unknown], # 8
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 9
  [ArgsSource, ~, ~, ~, Array], # 10
  [Phi, {region: 3}, [2, 45], ~, Int], # 11
  [Proj, {index: 0}, [3]], # 12
  [Exists, {kind: array}, [10, 11, 7], 12, Boolean], # 13
  [Subscript, {kind: array}, [10, 11], ~, Scalar], # 14
  [Ref, ~, [14], ~, ScalarRef], # 15
  [TernaryExpr, ~, [13, 15, 9], 13, Scalar], # 16
  [Assign, ~, [8, 9], 16, Undef], # 17
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [17], ~, Scalar], # 18
  [PostfixDeref, {sigil: $}, [16, 17], ~, Scalar], # 19
  [Subscript, {kind: array}, [10, 11, 17], ~, Scalar], # 20
  [TernaryExpr, ~, [13, 19, 20], ~, Scalar], # 21
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, [21], 17, Num], # 22
  [PadAccess, {sigil: $, symbol: c}, [22], ~, Unknown], # 23
  [Assign, ~, [23, 22], 22, Num], # 24
  [Region, {eval_entry: 17}, [24]], # 25
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [24], 25, Scalar], # 26
  [EntryWrite, ~, [5, 18, 24], 26, Unknown], # 27
  [Phi, {region: 25}, [1, 9], ~, Scalar], # 28
  [If, ~, [27, 28], 27], # 29
  [Proj, {index: 1}, [29]], # 30
  [Region, {head: 3}, [4, 30]], # 31
  [Phi, {region: 31}, [1, 2], ~, Int], # 32
  [Coerce, {from_repr: Int, to_repr: Str}, [32], ~, Str], # 33
  [Constant, {const_type: string, value: ":"}, ~, ~, Str], # 34
  [Concat, ~, [33, 34], ~, Str], # 35
  [Phi, {memory: true, region: 31}, [7, 27], ~, Unknown], # 36
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [36], ~, Scalar], # 37
  [Coerce, {from_repr: Scalar, to_repr: Str}, [37], ~, Str], # 38
  [PadAccess, {sigil: "@", symbol: out}, ~, ~, Unknown], # 39
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [38, 39, 36], ~, Str], # 40
  [Concat, ~, [35, 40], ~, Str], # 41
  [Return, ~, [41], 31], # 42
  [Count, ~, [10, 7], ~, Int], # 43
  [NumGt, ~, [43, 11], 3, Boolean], # 44
  [Add, ~, [11, 1], ~, Int], # 45
  [PadAccess, {sigil: $, symbol: c}, [27], ~, Unknown], # 46
  [Proj, {index: 0}, [29]], # 47
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [39, 46, 27], 47, Int], # 48
  [Count, ~, [10, 6], ~, Int]]} # 49
main::g: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [NumEq, ~, [5, 8], ~, Boolean], # 9
  [If, ~, [0, 9], 0], # 10
  [Proj, {index: 1}, [10]], # 11
  [Constant, {const_type: string, value: "no\n"}, ~, ~, Str], # 12
  [Proj, {index: 0}, [10]], # 13
  [Unwind, ~, [12], 13], # 14
  [Region, {head: 10}, [11, 14]], # 15
  [Return, ~, [7], 15]]} # 16
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1], 4, Unknown], # 5
  [Return, {implicit: true}, [5], 5]]} # 6
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
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3, 4, 5], 0, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
main::f: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 53], ~, Int], # 3
  [Coerce, {from_repr: Int, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: ":"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [MemStart], # 7
  [Phi, {memory: true, region: 2}, [7, 50], ~, Unknown], # 8
  [Proj, {index: 1}, [2]], # 9
  [Region, {head: 2}, [9]], # 10
  [Phi, {memory: true, region: 10}, [8], ~, Unknown], # 11
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [11], ~, Scalar], # 12
  [Coerce, {from_repr: Scalar, to_repr: Str}, [12], ~, Str], # 13
  [PadAccess, {sigil: "@", symbol: out}, ~, ~, Unknown], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [13, 14, 11], ~, Str], # 15
  [Concat, ~, [6, 15], ~, Str], # 16
  [Return, ~, [16], 10], # 17
  [ArgsSource, ~, ~, ~, Array], # 18
  [Count, ~, [18, 8], ~, Int], # 19
  [Phi, {region: 2}, [1, 25], ~, Int], # 20
  [NumGt, ~, [19, 20], 2, Boolean], # 21
  [Proj, {index: 0}, [2]], # 22
  [Exists, {kind: array}, [18, 20, 8], 22, Boolean], # 23
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 24
  [Add, ~, [20, 24], ~, Int], # 25
  [Subscript, {kind: array}, [18, 20], ~, Scalar], # 26
  [PadAccess, {sigil: $, symbol: c}, [8], ~, Unknown], # 27
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 28
  [Ref, ~, [26], ~, ScalarRef], # 29
  [TernaryExpr, ~, [23, 29, 28], 23, Scalar], # 30
  [Assign, ~, [27, 28], 30, Undef], # 31
  [Subscript, {kind: array}, [18, 20, 31], ~, Scalar], # 32
  [PostfixDeref, {sigil: $}, [30, 31], ~, Scalar], # 33
  [TernaryExpr, ~, [23, 33, 32], ~, Scalar], # 34
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 35
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [31], ~, Scalar], # 36
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, [34], 31, Num], # 37
  [PadAccess, {sigil: $, symbol: c}, [37], ~, Unknown], # 38
  [Assign, ~, [38, 37], 37, Num], # 39
  [Region, {eval_entry: 31}, [39]], # 40
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [39], 40, Scalar], # 41
  [EntryWrite, ~, [35, 36, 39], 41, Unknown], # 42
  [PadAccess, {sigil: $, symbol: c}, [42], ~, Unknown], # 43
  [Phi, {region: 40}, [24, 28], ~, Scalar], # 44
  [If, ~, [42, 44], 42], # 45
  [Proj, {index: 0}, [45]], # 46
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [14, 43, 42], 46, Int], # 47
  [Proj, {index: 1}, [45]], # 48
  [Region, {head: 2}, [47, 48]], # 49
  [Phi, {memory: true, predecessors: [46, 48], region: 49}, [47, 42], ~, Unknown], # 50
  [Count, ~, [18, 7], ~, Int], # 51
  [Add, ~, [3, 24], ~, Int], # 52
  [Phi, {predecessors: [46, 48], region: 49}, [3, 52], ~, Int]]} # 53
main::g: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [NumEq, ~, [5, 8], ~, Boolean], # 9
  [If, ~, [0, 9], 0], # 10
  [Proj, {index: 1}, [10]], # 11
  [Constant, {const_type: string, value: "no\n"}, ~, ~, Str], # 12
  [Proj, {index: 0}, [10]], # 13
  [Unwind, ~, [12], 13], # 14
  [Region, {head: 10}, [11, 14]], # 15
  [Return, ~, [7], 15]]} # 16
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1], 4, Unknown], # 5
  [Return, {implicit: true}, [5], 5]]} # 6
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
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3, 4, 5], 0, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 8
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3], 6, Str], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [7, 8, 10, 11], 9, Scalar], # 12
  [Return, {implicit: true}, [1], 12]]} # 13
main::f: {start: 0, returns: [44], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: R}, ~, ~, Str], # 1
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar], # 2
  [MemStart], # 3
  [Loop, {bound: entry}, [0], 0], # 4
  [Phi, {memory: true, region: 4}, [3, 50], ~, Unknown], # 5
  [PadAccess, {sigil: $, symbol: c}, [5], ~, Unknown], # 6
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 7
  [ArgsSource, ~, ~, ~, Array], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Phi, {region: 4}, [9, 47], ~, Int], # 10
  [Proj, {index: 0}, [4]], # 11
  [Exists, {kind: array}, [8, 10, 5], 11, Boolean], # 12
  [Subscript, {kind: array}, [8, 10], ~, Scalar], # 13
  [Ref, ~, [13], ~, ScalarRef], # 14
  [TernaryExpr, ~, [12, 14, 7], 12, Scalar], # 15
  [Assign, ~, [6, 7], 15, Undef], # 16
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [16], ~, Scalar], # 17
  [PostfixDeref, {sigil: $}, [15, 16], ~, Scalar], # 18
  [Subscript, {kind: array}, [8, 10, 16], ~, Scalar], # 19
  [TernaryExpr, ~, [12, 18, 19], ~, Scalar], # 20
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, [20], 16, Num], # 21
  [PadAccess, {sigil: $, symbol: c}, [21], ~, Unknown], # 22
  [Assign, ~, [22, 21], 21, Num], # 23
  [Region, {eval_entry: 16}, [23]], # 24
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [23], 24, Scalar], # 25
  [EntryWrite, ~, [2, 17, 23], 25, Unknown], # 26
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [26], ~, Scalar], # 27
  [Coerce, {from_repr: Scalar, to_repr: Str}, [27], ~, Str], # 28
  [PadAccess, {sigil: "@", symbol: out}, ~, ~, Unknown], # 29
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [28, 29, 26], ~, Str], # 30
  [Concat, ~, [1, 30], ~, Str], # 31
  [Proj, {index: 1}, [4]], # 32
  [Region, {head: 4}, [32]], # 33
  [Phi, {memory: true, region: 33}, [5], ~, Unknown], # 34
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [34], ~, Scalar], # 35
  [Coerce, {from_repr: Scalar, to_repr: Str}, [35], ~, Str], # 36
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [36, 29, 34], ~, Str], # 37
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 38
  [Phi, {region: 24}, [38, 7], ~, Scalar], # 39
  [If, ~, [26, 39], 26], # 40
  [Proj, {index: 1}, [40]], # 41
  [Region, ~, [41, 33]], # 42
  [Phi, {predecessors: [41, 33], region: 42}, [31, 37], ~, Str], # 43
  [Return, ~, [43], 42], # 44
  [Count, ~, [8, 5], ~, Int], # 45
  [NumGt, ~, [45, 10], 4, Boolean], # 46
  [Add, ~, [10, 38], ~, Int], # 47
  [PadAccess, {sigil: $, symbol: c}, [26], ~, Unknown], # 48
  [Proj, {index: 0}, [40]], # 49
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [29, 48, 26], 49, Int], # 50
  [Count, ~, [8, 3], ~, Int]]} # 51
main::g: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 8
  [NumEq, ~, [5, 8], ~, Boolean], # 9
  [If, ~, [0, 9], 0], # 10
  [Proj, {index: 1}, [10]], # 11
  [Constant, {const_type: string, value: "no\n"}, ~, ~, Str], # 12
  [Proj, {index: 0}, [10]], # 13
  [Unwind, ~, [12], 13], # 14
  [Region, {head: 10}, [11, 14]], # 15
  [Return, ~, [7], 15]]} # 16
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1], 4, Unknown], # 5
  [Return, {implicit: true}, [5], 5]]} # 6
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
main::__PROGRAM__: {start: 0, returns: [36], nodes: [
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
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3, 4], 15, Unknown], # 16
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [16], ~, Scalar], # 17
  [Coerce, {from_repr: Scalar, to_repr: Str}, [17], ~, Str], # 18
  [ArrayLiteral, ~, ~, ~, Array], # 19
  [Phi, {region: 13}, [19, 72], ~, Array], # 20
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [18, 20, 16], ~, Str], # 21
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 22
  [Concat, ~, [21, 22], ~, Str], # 23
  [ArrayLiteral, {sigil: "@", symbol: l}, [16], ~, Array], # 24
  [Count, ~, [24, 16], ~, Int], # 25
  [Coerce, {from_repr: Int, to_repr: Str}, [25], ~, Str], # 26
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 27
  [ArrayLiteral, ~, ~, ~, Array], # 28
  [Loop, {bound: entry}, [16], 16], # 29
  [Phi, {region: 29}, [28, 63], ~, Array], # 30
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [27, 30, 16], ~, Str], # 31
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 32
  [Proj, {index: 1}, [29]], # 33
  [Region, {head: 29}, [33]], # 34
  [Print, ~, [23, 26, 22, 31, 32], 34, Scalar], # 35
  [Return, {implicit: true}, [1], 35], # 36
  [ArrayLiteral, ~, [9, 10, 11, 12], ~, List], # 37
  [Phi, {region: 13}, [4, 39], ~, Int], # 38
  [Add, ~, [38, 2], ~, Int], # 39
  [Phi, {region: 29}, [4, 41], ~, Int], # 40
  [Add, ~, [40, 2], ~, Int], # 41
  [MemStart], # 42
  [Count, ~, [37, 42], ~, Int], # 43
  [Phi, {memory: true, region: 13}, [42, 69], ~, Unknown], # 44
  [Count, ~, [37, 44], ~, Int], # 45
  [Subscript, {kind: array}, [37, 38, 44], ~, ArrayRef], # 46
  [Subscript, {kind: array}, [37, 38], ~, Scalar], # 47
  [PadAccess, {shared: 1, sigil: "%", symbol: t}, [16], ~, Unknown], # 48
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [48, 16], ~, List], # 49
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [49, 16], ~, List], # 50
  [Count, ~, [50, 16], ~, Int], # 51
  [Subscript, {kind: array}, [50, 40, 16], ~, Scalar], # 52
  [PadAccess, {shared: 1, sigil: "%", symbol: t}, ~, ~, Unknown], # 53
  [Subscript, {kind: hash}, [53, 52, 16], ~, Scalar], # 54
  [NumGt, ~, [45, 38], 13, Boolean], # 55
  [PostfixDeref, {sigil: "@"}, [46, 44], ~, Array], # 56
  [Ref, ~, [47], ~, ScalarRef], # 57
  [Coerce, {from_repr: Unknown, to_repr: Str}, [52], ~, Str], # 58
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 59
  [Concat, ~, [58, 59], ~, Str], # 60
  [Coerce, {from_repr: Unknown, to_repr: Str}, [54], ~, Str], # 61
  [Concat, ~, [60, 61], ~, Str], # 62
  [ListAppend, {collector: map}, [30, 62], ~, Array], # 63
  [Proj, {index: 0}, [13]], # 64
  [NumGt, ~, [51, 40], 29, Boolean], # 65
  [Proj, {index: 0}, [29]], # 66
  [Phi, {memory: true, region: 15}, [44], ~, Unknown], # 67
  [LocalAlias, {name: _}, [57], 64, Unknown], # 68
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, [56], 68, Unknown], # 69
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 70
  [DefinedOr, ~, [69, 70], ~, Unknown], # 71
  [ListAppend, {collector: map}, [20, 71], ~, Array]]} # 72
main::f: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 2
  [PadAccess, {sigil: $, symbol: a}, ~, ~, Unknown], # 3
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Unknown], # 4
  [And, ~, [3, 4], ~, Unknown], # 5
  [And, ~, [2, 5], ~, Unknown], # 6
  [PadAccess, {shared: 1, sigil: "%", symbol: t}, ~, ~, Unknown], # 7
  [Subscript, {kind: hash}, [7, 4], ~, Scalar], # 8
  [If, ~, [0, 2], 0], # 9
  [Proj, {index: 0}, [9]], # 10
  [If, ~, [10, 5], 10], # 11
  [Proj, {index: 0}, [11]], # 12
  [Assign, ~, [8, 3], 12, Unknown], # 13
  [Proj, {index: 1}, [9]], # 14
  [Proj, {index: 1}, [11]], # 15
  [Region, {head: 9}, [14, 15]], # 16
  [Region, ~, [13, 16]], # 17
  [Phi, {predecessors: [12, 16], region: 17}, [1, 6], ~, Unknown], # 18
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 19
  [Phi, {predecessors: [12, 16], region: 17}, [19, 6], ~, Unknown], # 20
  [Return, ~, [18, 20], 17], # 21
  [ArgsSource, ~, ~, ~, Array], # 22
  [Assign, {targets: 3}, [2, 3, 4, 22], ~, List]]} # 23
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
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
N::inputs: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: i}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
N::new: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: o}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Constant, {const_type: string, value: i}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7, 4], ~, Scalar], # 8
  [Constant, {const_type: string, value: id}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [2, 10, 4], ~, Scalar], # 11
  [HashLiteral, ~, [1, 5, 6, 8, 9, 11], 0, HashRef], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [Subscript, {kind: array}, [2, 13, 4], ~, Scalar], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [12, 14, 4], ~, Unknown], # 15
  [Return, {implicit: true}, [15], 12]]} # 16
N::operation: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: o}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
main::__PROGRAM__: {start: 0, returns: [51], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [MemStart], # 4
  [PadAccess, {sigil: $, symbol: s}, [4], ~, Unknown], # 5
  [HashLiteral, ~, ~, 0, HashRef], # 6
  [Assign, ~, [5, 6], 6, HashRef], # 7
  [PadAccess, {sigil: $, symbol: s}, [7], ~, Unknown], # 8
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: Phi}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: VarDecl}, ~, ~, Str], # 11
  [ArrayLiteral, ~, ~, 7, ArrayRef], # 12
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 13
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [9, 11, 12, 13], 12, Object], # 14
  [ArrayLiteral, ~, [14], 14, ArrayRef], # 15
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [PadAccess], want: list}, [15], 15, Object], # 16
  [ArrayLiteral, ~, [16], 16, ArrayRef], # 17
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 18
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [9, 10, 17, 18], 17, Object], # 19
  [Constant, {const_type: string, value: R}, ~, ~, Str], # 20
  [Call, {dispatch_kind: direct, name: main::upd, param_names: [], want: void}, [8, 19, 20], 19, List], # 21
  [PadAccess, {sigil: $, symbol: s}, [21], ~, Unknown], # 22
  [ArrayLiteral, ~, [1], 21, ArrayRef], # 23
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [PadAccess], want: list}, [23], 23, Object], # 24
  [ArrayLiteral, ~, [24], 24, ArrayRef], # 25
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 26
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [9, 10, 25, 26], 25, Object], # 27
  [Constant, {const_type: string, value: Q}, ~, ~, Str], # 28
  [Call, {dispatch_kind: direct, name: main::upd, param_names: [], want: void}, [22, 27, 28], 27, List], # 29
  [PadAccess, {sigil: $, symbol: s}, [29], ~, Unknown], # 30
  [ArrayLiteral, ~, ~, 29, ArrayRef], # 31
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 32
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [9, 10, 31, 32], 31, Object], # 33
  [Constant, {const_type: string, value: Z}, ~, ~, Str], # 34
  [Call, {dispatch_kind: direct, name: main::upd, param_names: [], want: void}, [30, 33, 34], 33, List], # 35
  [Loop, {bound: entry}, [35], 35], # 36
  [Phi, {region: 36}, [3, 69], ~, Array], # 37
  [Phi, {memory: true, region: 36}, [35, 38], ~, Unknown], # 38
  [Proj, {index: 1}, [36]], # 39
  [Region, {head: 36}, [39]], # 40
  [Phi, {memory: true, region: 40}, [38], ~, Unknown], # 41
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [2, 37, 41], ~, Str], # 42
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 43
  [PadAccess, {sigil: $, symbol: s}, [41], ~, Unknown], # 44
  [Constant, {const_type: string, value: p}, ~, ~, Str], # 45
  [Subscript, {kind: hash}, [44, 45, 41], ~, Scalar], # 46
  [PostfixDeref, {sigil: "%"}, [46, 41], ~, Hash], # 47
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [2, 47, 41], ~, Str], # 48
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 49
  [Print, ~, [42, 43, 48, 49], 40, Scalar], # 50
  [Return, {implicit: true}, [1], 50], # 51
  [PadAccess, {sigil: $, symbol: s}, [35], ~, Unknown], # 52
  [Constant, {const_type: string, value: t}, ~, ~, Str], # 53
  [Subscript, {kind: hash}, [52, 53], ~, Scalar], # 54
  [PostfixDeref, {sigil: "%"}, [54, 35], ~, Hash], # 55
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [55, 35], ~, List], # 56
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [56, 35], ~, List], # 57
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 58
  [Phi, {region: 36}, [58, 75], ~, Int], # 59
  [Subscript, {kind: array}, [57, 59, 38], ~, Scalar], # 60
  [Coerce, {from_repr: Unknown, to_repr: Str}, [60], ~, Str], # 61
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 62
  [Concat, ~, [61, 62], ~, Str], # 63
  [PadAccess, {sigil: $, symbol: s}, [38], ~, Unknown], # 64
  [Subscript, {kind: hash}, [64, 53], ~, Scalar], # 65
  [Subscript, {kind: hash}, [65, 60, 38], ~, Scalar], # 66
  [Coerce, {from_repr: Unknown, to_repr: Str}, [66], ~, Str], # 67
  [Concat, ~, [63, 67], ~, Str], # 68
  [ListAppend, {collector: map}, [37, 68], ~, Array], # 69
  [Count, ~, [57, 38], ~, Int], # 70
  [NumGt, ~, [70, 59], 36, Boolean], # 71
  [Proj, {index: 0}, [36]], # 72
  [Count, ~, [57, 35], ~, Int], # 73
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 74
  [Add, ~, [59, 74], ~, Int]]} # 75
main::upd: {start: 0, returns: [62], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [ArrayLiteral, ~, ~, ~, List], # 2
  [ArrayLiteral, ~, ~, ~, List], # 3
  [PadAccess, {sigil: $, symbol: phi}, ~, ~, Unknown], # 4
  [Call, {dispatch_kind: method, name: inputs, param_names: [], want: scalar}, [4], 0, Unknown], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Subscript, {kind: array}, [5, 6, 5], ~, Scalar], # 7
  [Defined, ~, [5], ~, Boolean], # 8
  [PostfixDeref, {sigil: "@"}, [5, 5], ~, Array], # 9
  [Count, ~, [9, 5], ~, Int], # 10
  [And, ~, [8, 10], ~, Scalar], # 11
  [Not, ~, [11], ~, Boolean], # 12
  [If, ~, [5, 12], 5], # 13
  [Proj, {index: 1}, [13]], # 14
  [Defined, ~, [7], ~, Boolean], # 15
  [Not, ~, [15], ~, Boolean], # 16
  [If, ~, [14, 16], 14], # 17
  [Proj, {index: 1}, [17]], # 18
  [Call, {dispatch_kind: method, name: operation, param_names: [], want: scalar}, [7], 18, Unknown], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 20
  [Constant, {const_type: string, value: PadAccess}, ~, ~, Str], # 21
  [StrEq, ~, [20, 21], ~, Boolean], # 22
  [If, ~, [19, 22], 19], # 23
  [Proj, {index: 0}, [23]], # 24
  [Call, {dispatch_kind: method, name: inputs, param_names: [], want: scalar}, [7], 24, Unknown], # 25
  [Subscript, {kind: array}, [25, 6, 25], ~, Scalar], # 26
  [Defined, ~, [26], ~, Boolean], # 27
  [If, ~, [25, 27], 25], # 28
  [Proj, {index: 0}, [28]], # 29
  [Call, {dispatch_kind: method, name: operation, param_names: [], want: scalar}, [26], 29, Unknown], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [30], ~, Str], # 31
  [Constant, {const_type: string, value: VarDecl}, ~, ~, Str], # 32
  [StrEq, ~, [31, 32], ~, Boolean], # 33
  [Proj, {index: 1}, [28]], # 34
  [Region, {head: 28}, [30, 34]], # 35
  [Phi, {predecessors: [29, 34], region: 35}, [33, 27], ~, Boolean], # 36
  [And, ~, [22, 36], ~, Boolean], # 37
  [Proj, {index: 0}, [13]], # 38
  [Proj, {index: 0}, [17]], # 39
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 40
  [Constant, {const_type: string, value: p}, ~, ~, Str], # 41
  [Subscript, {kind: hash}, [40, 41], ~, Scalar], # 42
  [Constant, {const_type: string, value: t}, ~, ~, Str], # 43
  [Subscript, {kind: hash}, [40, 43], ~, Scalar], # 44
  [If, ~, [35, 36], 35], # 45
  [Proj, {index: 0}, [45]], # 46
  [Call, {dispatch_kind: method, name: id, param_names: [], want: scalar}, [26], 46, Unknown], # 47
  [Subscript, {kind: hash}, [44, 47], ~, Scalar], # 48
  [PadAccess, {sigil: $, symbol: ref}, ~, ~, Unknown], # 49
  [Assign, ~, [48, 49], 47, Unknown], # 50
  [Call, {dispatch_kind: method, name: id, param_names: [], want: scalar}, [26], 50, Unknown], # 51
  [Call, {dispatch_kind: method, name: id, param_names: [], want: scalar}, [4], 51, Unknown], # 52
  [Subscript, {kind: hash}, [42, 52], ~, Scalar], # 53
  [Assign, ~, [53, 51], 52, Unknown], # 54
  [Proj, {index: 1}, [23]], # 55
  [Proj, {index: 1}, [45]], # 56
  [Region, {head: 23}, [55, 56]], # 57
  [Region, ~, [38, 39, 54, 57]], # 58
  [Phi, {predecessors: [38, 39, 46, 18], region: 58}, [1, 2, 3, 37], ~, List], # 59
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 60
  [Phi, {predecessors: [38, 39, 46, 18], region: 58}, [60, 60, 60, 37], ~, Scalar], # 61
  [Return, ~, [59, 61], 58], # 62
  [ArgsSource, ~, ~, ~, Array], # 63
  [Assign, {targets: 3}, [40, 4, 49, 63], ~, List], # 64
  [Phi, {predecessors: [55, 24], region: 57}, [60, 26], ~, Scalar], # 65
  [Phi, {memory: true, predecessors: [29, 34], region: 35}, [30, 25], ~, Unknown], # 66
  [Phi, {memory: true, predecessors: [55, 24], region: 57}, [19, 66], ~, Unknown]]} # 67
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
  [PadAccess, {sigil: $, symbol: s}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [HashLiteral, ~, [4, 5], 0, HashRef], # 6
  [Assign, ~, [3, 6], 6, HashRef], # 7
  [PadAccess, {sigil: $, symbol: s}, [7], ~, Unknown], # 8
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 9
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [8, 9], 7, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: " | "}, ~, ~, Str], # 12
  [PadAccess, {sigil: $, symbol: s}, [10], ~, Unknown], # 13
  [Call, {dispatch_kind: direct, name: main::h, param_names: [], want: list}, [13], 10, Str], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Print, ~, [11, 12, 15, 16], 14, Scalar], # 17
  [Return, {implicit: true}, [1], 17]]} # 18
main::f: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: self}, [1], ~, Unknown], # 2
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Assign, {targets: 2}, [2, 3, 4], 0, List], # 5
  [PadAccess, {sigil: $, symbol: self}, [5], ~, Unknown], # 6
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 7
  [Subscript, {kind: hash}, [6, 7], ~, Scalar], # 8
  [Subscript, {kind: hash}, [6, 7, 5], ~, Scalar], # 9
  [Defined, ~, [9], ~, Boolean], # 10
  [If, ~, [5, 10], 5], # 11
  [Proj, {index: 1}, [11]], # 12
  [HashLiteral, ~, ~, 12, HashRef], # 13
  [DefinedOr, ~, [9, 13], ~, Scalar], # 14
  [PostfixDeref, {sigil: "%"}, [14, 5], ~, Hash], # 15
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 16
  [Proj, {index: 0}, [11]], # 17
  [Region, {head: 11}, [17, 13]], # 18
  [HashLiteral, ~, [15, 3, 16], 18, HashRef], # 19
  [Assign, {local: true}, [8, 19], 19, HashRef], # 20
  [PadAccess, {sigil: $, symbol: self}, [20], ~, Unknown], # 21
  [Call, {dispatch_kind: direct, name: main::h, param_names: []}, [21], 20, Str], # 22
  [Return, ~, [22], 22], # 23
  [Exists, {kind: hash}, [6, 7, 5], ~, Boolean]]} # 24
main::h: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [3, 4], 0, Scalar], # 5
  [Loop, {bound: entry}, [5], 5], # 6
  [Phi, {region: 6}, [2, 45], ~, Array], # 7
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 7, 5], ~, Str], # 8
  [Proj, {index: 1}, [6]], # 9
  [Region, {head: 6}, [9]], # 10
  [Return, {implicit: true}, [8], 10], # 11
  [PostfixDeref, {sigil: "%"}, [5, 5], ~, Hash], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [12, 5], ~, List], # 13
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [13, 5], ~, List], # 14
  [Count, ~, [14, 5], ~, Int], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Phi, {region: 6}, [16, 47], ~, Int], # 17
  [Subscript, {kind: array}, [14, 17, 5], ~, Scalar], # 18
  [Subscript, {kind: hash}, [5, 18, 5], ~, Scalar], # 19
  [Subscript, {kind: hash}, [5, 18], ~, Scalar], # 20
  [PostfixDeref, {sigil: "%"}, [20, 5], ~, Hash], # 21
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [21, 5], ~, List], # 22
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [22, 5], ~, List], # 23
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 24
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [24, 23, 5], ~, Str], # 25
  [NumGt, ~, [15, 17], 6, Boolean], # 26
  [Proj, {index: 0}, [6]], # 27
  [Coerce, {from_repr: Unknown, to_repr: Str}, [18], ~, Str], # 28
  [RefType, ~, [19], ~, Str], # 29
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 30
  [DefinedOr, ~, [19, 30], ~, Scalar], # 31
  [Constant, {const_type: string, value: "{"}, ~, ~, Str], # 32
  [Concat, ~, [32, 25], ~, Str], # 33
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 34
  [Concat, ~, [28, 34], ~, Str], # 35
  [Constant, {const_type: string, value: "}"}, ~, ~, Str], # 36
  [Concat, ~, [33, 36], ~, Str], # 37
  [If, ~, [27, 29], 27], # 38
  [Proj, {index: 0}, [38]], # 39
  [Proj, {index: 1}, [38]], # 40
  [Region, {head: 38}, [39, 40]], # 41
  [Phi, {predecessors: [39, 40], region: 41}, [37, 31], ~, Scalar], # 42
  [Coerce, {from_repr: Scalar, to_repr: Str}, [42], ~, Str], # 43
  [Concat, ~, [35, 43], ~, Str], # 44
  [ListAppend, {collector: map}, [7, 44], ~, Array], # 45
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 46
  [Add, ~, [17, 46], ~, Int]]} # 47
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
  [PadAccess, {sigil: $, symbol: s}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [HashLiteral, ~, [4, 5, 6, 7], 0, HashRef], # 8
  [Assign, ~, [3, 8], 8, HashRef], # 9
  [PadAccess, {sigil: $, symbol: s}, [9], ~, Unknown], # 10
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 11
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [10, 11], 9, Str], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: " | "}, ~, ~, Str], # 14
  [PadAccess, {sigil: $, symbol: s}, [12], ~, Unknown], # 15
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 16
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [15, 16], 12, Str], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [PadAccess, {sigil: $, symbol: s}, [17], ~, Unknown], # 19
  [Call, {dispatch_kind: direct, name: main::h, param_names: [], want: list}, [19], 17, Str], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 22
  [Print, ~, [13, 14, 18, 14, 21, 22], 20, Scalar], # 23
  [Return, {implicit: true}, [1], 23]]} # 24
main::f: {start: 0, returns: [28], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: self}, [2], ~, Unknown], # 3
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Assign, {targets: 2}, [3, 4, 5], 0, List], # 6
  [PadAccess, {sigil: $, symbol: self}, [6], ~, Unknown], # 7
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 8
  [Subscript, {kind: hash}, [7, 8], ~, Scalar], # 9
  [If, ~, [6, 4], 6], # 10
  [Proj, {index: 0}, [10]], # 11
  [Assign, {local: true}, [9, 4], 11, Unknown], # 12
  [PadAccess, {sigil: $, symbol: self}, [12], ~, Unknown], # 13
  [Call, {dispatch_kind: direct, name: main::h, param_names: [], want: scalar}, [13], 12, Str], # 14
  [Proj, {index: 1}, [10]], # 15
  [Subscript, {kind: hash}, [7, 8, 6], ~, Scalar], # 16
  [Exists, {kind: hash}, [7, 8, 6], ~, Boolean], # 17
  [ElemRestore, {kind: hash}, [7, 8, 16, 17, 14], 14, Unknown], # 18
  [Region, {head: 10}, [15, 18]], # 19
  [Phi, {predecessors: [15, 11], region: 19}, [1, 14], ~, Str], # 20
  [Coerce, {from_repr: Unknown, to_repr: Str}, [20], ~, Str], # 21
  [Constant, {const_type: string, value: " / "}, ~, ~, Str], # 22
  [Concat, ~, [21, 22], ~, Str], # 23
  [Phi, {memory: true, predecessors: [15, 11], region: 19}, [6, 18], ~, Unknown], # 24
  [PadAccess, {sigil: $, symbol: self}, [24], ~, Unknown], # 25
  [Call, {dispatch_kind: direct, name: main::h, param_names: [], want: scalar}, [25], 19, Str], # 26
  [Concat, ~, [23, 26], ~, Str], # 27
  [Return, ~, [27], 26]]} # 28
main::h: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [3, 4], 0, Scalar], # 5
  [Loop, {bound: entry}, [5], 5], # 6
  [Phi, {region: 6}, [2, 29], ~, Array], # 7
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 7, 5], ~, Str], # 8
  [Proj, {index: 1}, [6]], # 9
  [Region, {head: 6}, [9]], # 10
  [Return, {implicit: true}, [8], 10], # 11
  [PostfixDeref, {sigil: "%"}, [5, 5], ~, Hash], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [12, 5], ~, List], # 13
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [13, 5], ~, List], # 14
  [Count, ~, [14, 5], ~, Int], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Phi, {region: 6}, [16, 31], ~, Int], # 17
  [Subscript, {kind: array}, [14, 17, 5], ~, Scalar], # 18
  [Subscript, {kind: hash}, [5, 18, 5], ~, Scalar], # 19
  [NumGt, ~, [15, 17], 6, Boolean], # 20
  [Proj, {index: 0}, [6]], # 21
  [Coerce, {from_repr: Unknown, to_repr: Str}, [18], ~, Str], # 22
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 23
  [DefinedOr, ~, [19, 23], ~, Scalar], # 24
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 25
  [Concat, ~, [22, 25], ~, Str], # 26
  [Coerce, {from_repr: Scalar, to_repr: Str}, [24], ~, Str], # 27
  [Concat, ~, [26, 27], ~, Str], # 28
  [ListAppend, {collector: map}, [7, 28], ~, Array], # 29
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 30
  [Add, ~, [17, 30], ~, Int]]} # 31
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
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [HashLiteral, ~, [2, 3], 0, HashRef], # 4
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [4], 4, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, Scalar], # 8
  [Return, {implicit: true}, [1], 8]]} # 9
main::f: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 3
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 5
  [Assign, {local: true}, [4, 5], 0, Int], # 6
  [PostfixDeref, {sigil: "%"}, [2, 6], ~, Hash], # 7
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [7, 6], ~, List], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [8, 6], ~, List], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 9, 6], ~, Str], # 10
  [Constant, {const_type: string, value: " / "}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [MemStart], # 13
  [Subscript, {kind: hash}, [2, 3, 13], ~, Scalar], # 14
  [Exists, {kind: hash}, [2, 3, 13], ~, Boolean], # 15
  [ElemRestore, {kind: hash}, [2, 3, 14, 15, 6], 6, Unknown], # 16
  [PostfixDeref, {sigil: "%"}, [2, 16], ~, Hash], # 17
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [17, 16], ~, List], # 18
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [18, 16], ~, List], # 19
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 19, 16], ~, Str], # 20
  [Concat, ~, [12, 20], ~, Str], # 21
  [Return, ~, [21], 16], # 22
  [ArgsSource, ~, ~, ~, Array], # 23
  [Assign, {targets: 1}, [2, 23], ~, List]]} # 24
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
  [EntryWrite, ~, [3, 2, 4], 0, Unknown], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 5, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: " | "}, ~, ~, Str], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [9], 6, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [EntryDef, {package: main, sigil: $, symbol: g}, [10], ~, Int], # 12
  [Coerce, {from_repr: Int, to_repr: Str}, [12], ~, Str], # 13
  [Concat, ~, [8, 13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [Print, ~, [7, 8, 11, 16], 10, Scalar], # 17
  [Return, {implicit: true}, [1], 17]]} # 18
main::f: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [EntryDef, {package: main, sigil: $, symbol: g}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [MemStart], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Subscript, {kind: array}, [5, 6, 4], ~, Scalar], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [EntryWrite, ~, [2, 3, 4], 9, Unknown], # 10
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, ~, 10, Str], # 11
  [Proj, {index: 1}, [8]], # 12
  [EntryDef, {package: main, sigil: $, symbol: g}, [4], ~, Scalar], # 13
  [EntryWrite, ~, [2, 13, 11], 11, Unknown], # 14
  [Region, {head: 8}, [12, 14]], # 15
  [Phi, {predecessors: [12, 9], region: 15}, [1, 11], ~, Str], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, ~, 15, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [Return, ~, [21], 20], # 22
  [Phi, {memory: true, predecessors: [12, 9], region: 15}, [4, 14], ~, Unknown]]} # 23
main::g: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "g="}, ~, ~, Str], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: g}, [2], ~, Scalar], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Concat, ~, [1, 4], ~, Str], # 5
  [Return, {implicit: true}, [5], 0]]} # 6
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
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [2, 3], 1, Scalar], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [1, 4, 4], ~, Unknown], # 5
  [Return, {implicit: true}, [5], 4]]} # 6
K::ok: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Return, {implicit: true}, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Call, {class_name: K, dispatch_kind: method, name: new, param_names: [], want: list}, ~, 0, Object], # 3
  [Call, {class_name: K, dispatch_kind: method, name: new, param_names: [], want: list}, ~, 3, Object], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Phi, {region: 5}, [2, 38], ~, Array], # 6
  [Phi, {memory: true, region: 5}, [4, 36], ~, Unknown], # 7
  [Proj, {index: 1}, [5]], # 8
  [Region, {head: 5}, [8]], # 9
  [Phi, {memory: true, region: 9}, [7], ~, Unknown], # 10
  [Count, ~, [6, 10], ~, Int], # 11
  [Coerce, {from_repr: Int, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [12, 13], 9, Scalar], # 14
  [Return, {implicit: true}, [1], 14], # 15
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 16
  [ArrayLiteral, {sigil: "@", symbol: a}, [3, 16, 4], ~, Array], # 17
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 18
  [Phi, {region: 5}, [18, 40], ~, Int], # 19
  [Proj, {index: 0}, [5]], # 20
  [Exists, {kind: array}, [17, 19, 7], 20, Boolean], # 21
  [Subscript, {kind: array}, [17, 19], ~, Scalar], # 22
  [Ref, ~, [22], ~, ScalarRef], # 23
  [TernaryExpr, ~, [21, 23, 1], ~, Scalar], # 24
  [Count, ~, [17, 4], ~, Int], # 25
  [Count, ~, [17, 7], ~, Int], # 26
  [Subscript, {kind: array}, [17, 19, 7], ~, Scalar], # 27
  [LocalAlias, {name: _}, [24], 21, Unknown], # 28
  [NumGt, ~, [26, 19], 5, Boolean], # 29
  [Call, {dispatch_kind: builtin, name: blessed, param_names: []}, [27], ~, Unknown], # 30
  [If, ~, [28, 30], 28], # 31
  [Proj, {index: 0}, [31]], # 32
  [Call, {dispatch_kind: method, name: ok, param_names: [], want: scalar}, [27], 32, Unknown], # 33
  [Proj, {index: 1}, [31]], # 34
  [Region, {head: 31}, [33, 34]], # 35
  [Phi, {memory: true, predecessors: [32, 34], region: 35}, [33, 7], ~, Unknown], # 36
  [Phi, {predecessors: [32, 34], region: 35}, [33, 30], ~, Unknown], # 37
  [ListAppend, {collector: grep}, [6, 27, 37], ~, Array], # 38
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 39
  [Add, ~, [19, 39], ~, Int]]} # 40
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: Scalar::Util}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: blessed}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "Scalar/Util.pm"}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: Scalar::Util, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3], 0, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [3, 2], 4, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 2], 6, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [3, 3], 8, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [5, 7, 9, 11, 12], 10, Scalar], # 13
  [Return, {implicit: true}, [1], 13]]} # 14
main::f: {start: 0, returns: [37], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: lines}, ~, ~, Scalar], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 3, 4, 5], 0, Int], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Subscript, {kind: array}, [7, 8, 6], ~, Scalar], # 9
  [If, ~, [6, 9], 6], # 10
  [Proj, {index: 1}, [10]], # 11
  [PadAccess, {sigil: "@", symbol: "n"}, ~, ~, Unknown], # 12
  [Proj, {index: 0}, [10]], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Proj, {index: 1}, [14]], # 15
  [Region, {head: 14}, [15]], # 16
  [ArrayLiteral, {rebinds: true, sigil: "@", symbol: lines}, [12], 16, Array], # 17
  [Region, {head: 10}, [11, 17]], # 18
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 19
  [Phi, {memory: true, region: 14}, [6, 43], ~, Int], # 20
  [Phi, {memory: true, region: 16}, [20], ~, Int], # 21
  [Phi, {memory: true, predecessors: [11, 13], region: 18}, [6, 21], ~, Int], # 22
  [Subscript, {kind: array}, [7, 19, 22], ~, Scalar], # 23
  [If, ~, [18, 23], 18], # 24
  [Proj, {index: 1}, [24]], # 25
  [PadAccess, {sigil: "@", symbol: n__2}, ~, ~, Unknown], # 26
  [Proj, {index: 0}, [24]], # 27
  [Loop, {bound: entry}, [27], 27], # 28
  [Proj, {index: 1}, [28]], # 29
  [Region, {head: 28}, [29]], # 30
  [ArrayLiteral, {rebinds: true, sigil: "@", symbol: lines}, [26], 30, Array], # 31
  [Region, {head: 24}, [25, 31]], # 32
  [Loop, {bound: entry}, [32], 32], # 33
  [Phi, {region: 33}, [1, 52], ~, Str], # 34
  [Proj, {index: 1}, [33]], # 35
  [Region, {head: 33}, [35]], # 36
  [Return, ~, [34], 36], # 37
  [Count, ~, [2, 6], ~, Int], # 38
  [Phi, {region: 14}, [8, 61], ~, Int], # 39
  [Subscript, {kind: array}, [2, 39, 6], ~, Scalar], # 40
  [Call, {dispatch_kind: builtin, name: uc, param_names: []}, [40], ~, Str], # 41
  [Proj, {index: 0}, [14]], # 42
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [12, 41, 6], 42, Int], # 43
  [Phi, {predecessors: [11, 13], region: 18}, [2, 17], ~, Array], # 44
  [Phi, {predecessors: [25, 27], region: 32}, [44, 31], ~, Array], # 45
  [Phi, {region: 33}, [8, 67], ~, Int], # 46
  [Phi, {memory: true, region: 28}, [22, 60], ~, Int], # 47
  [Phi, {memory: true, region: 30}, [47], ~, Int], # 48
  [Phi, {memory: true, predecessors: [25, 27], region: 32}, [22, 48], ~, Int], # 49
  [Subscript, {kind: array}, [45, 46, 49], ~, Scalar], # 50
  [Coerce, {from_repr: Unknown, to_repr: Str}, [50], ~, Str], # 51
  [Concat, ~, [34, 51], ~, Str], # 52
  [NumGt, ~, [38, 39], 14, Boolean], # 53
  [Count, ~, [44, 22], ~, Int], # 54
  [Phi, {region: 28}, [8, 66], ~, Int], # 55
  [Subscript, {kind: array}, [44, 55, 22], ~, Scalar], # 56
  [Coerce, {from_repr: Scalar, to_repr: Str}, [56], ~, Str], # 57
  [Concat, ~, [57, 57], ~, Str], # 58
  [Proj, {index: 0}, [28]], # 59
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [26, 58, 22], 59, Int], # 60
  [Add, ~, [39, 19], ~, Int], # 61
  [NumGt, ~, [54, 55], 28, Boolean], # 62
  [Count, ~, [45, 49], ~, Int], # 63
  [NumGt, ~, [63, 46], 33, Boolean], # 64
  [Proj, {index: 0}, [33]], # 65
  [Add, ~, [55, 19], ~, Int], # 66
  [Add, ~, [46, 19], ~, Int]]} # 67
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
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [5, 2], 3, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [4, 7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
main::f: {start: 0, returns: [35], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: "n"}, ~, ~, Unknown], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Subscript, {kind: array}, [5, 6, 4], ~, Scalar], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 3, 4], 9, Int], # 10
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [10], ~, Scalar], # 11
  [Coerce, {from_repr: Scalar, to_repr: Str}, [11], ~, Str], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [12, 2, 10], ~, Str], # 13
  [Concat, ~, [1, 13], ~, Str], # 14
  [Constant, {const_type: string, value: ";"}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [Proj, {index: 1}, [8]], # 17
  [Region, {head: 8}, [17, 10]], # 18
  [Phi, {predecessors: [17, 9], region: 18}, [1, 16], ~, Str], # 19
  [PadAccess, {sigil: "@", symbol: n__2}, ~, ~, Unknown], # 20
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 21
  [Phi, {memory: true, predecessors: [17, 9], region: 18}, [4, 10], ~, Unknown], # 22
  [Subscript, {kind: array}, [5, 3, 22], ~, Scalar], # 23
  [If, ~, [18, 23], 18], # 24
  [Proj, {index: 0}, [24]], # 25
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [20, 21, 22], 25, Int], # 26
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [26], ~, Scalar], # 27
  [Coerce, {from_repr: Scalar, to_repr: Str}, [27], ~, Str], # 28
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [28, 20, 26], ~, Str], # 29
  [Concat, ~, [19, 29], ~, Str], # 30
  [Concat, ~, [30, 15], ~, Str], # 31
  [Proj, {index: 1}, [24]], # 32
  [Region, {head: 24}, [32, 26]], # 33
  [Phi, {predecessors: [32, 25], region: 33}, [19, 31], ~, Str], # 34
  [Return, {implicit: true}, [34], 33], # 35
  [Phi, {memory: true, predecessors: [32, 25], region: 33}, [22, 26], ~, Unknown]]} # 36
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
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::mk, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 4
  [Call, {dispatch_kind: direct, name: main::mk, param_names: [], want: list}, ~, 2, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [3, 4, 6, 7], 5, Scalar], # 8
  [Return, {implicit: true}, [1], 8]]} # 9
main::mk: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, [3], ~, Unknown], # 4
  [ArrayLiteral, ~, ~, ~, Array], # 5
  [Assign, ~, [4, 5], 0, List], # 6
  [Call, {dispatch_kind: direct, name: main::mk::__ANON__:1:3, param_names: [], want: void}, [2], 6, Int], # 7
  [Call, {dispatch_kind: direct, name: main::mk::__ANON__:1:3, param_names: [], want: void}, [1], 7, Int], # 8
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [8], ~, Scalar], # 9
  [Coerce, {from_repr: Scalar, to_repr: Str}, [9], ~, Str], # 10
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, [8], ~, Unknown], # 11
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [10, 11, 8], ~, Str], # 12
  [Return, ~, [12], 8], # 13
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Scalar], # 14
  [MakeCell, {captured_written: false, cell_name: "@p"}, [14, 6], ~, Ref], # 15
  [AnonSub, {captures: ["@p"], name: main::mk::__ANON__:1:3}, [15], ~, CodeRef]]} # 16
main::mk::__ANON__:1:3: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: p}, ~, ~, Unknown], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [1, 5, 4], 0, Int], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: l}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 6
  [ArrayLiteral, ~, [4, 5, 6], 0, ArrayRef], # 7
  [Assign, ~, [3, 7], 7, ArrayRef], # 8
  [Loop, {bound: entry}, [8], 8], # 9
  [Phi, {region: 9}, [1, 44], ~, Str], # 10
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Phi, {memory: true, region: 9}, [8, 38], ~, Scalar], # 13
  [Proj, {index: 1}, [9]], # 14
  [Region, {head: 9}, [14]], # 15
  [Phi, {memory: true, region: 15}, [13], ~, Scalar], # 16
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [16], ~, Scalar], # 17
  [Coerce, {from_repr: Scalar, to_repr: Str}, [17], ~, Str], # 18
  [PadAccess, {sigil: $, symbol: l}, [16], ~, Unknown], # 19
  [PostfixDeref, {sigil: "@"}, [19, 16], ~, Array], # 20
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [18, 20, 16], ~, Str], # 21
  [Concat, ~, [12, 21], ~, Str], # 22
  [Return, {implicit: true}, [22], 15], # 23
  [PadAccess, {sigil: $, symbol: l}, [8], ~, Unknown], # 24
  [PostfixDeref, {sigil: "@"}, [24, 8], ~, Array], # 25
  [Count, ~, [25, 8], ~, Int], # 26
  [Count, ~, [25, 13], ~, Int], # 27
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 28
  [Phi, {region: 9}, [28, 46], ~, Int], # 29
  [Proj, {index: 0}, [9]], # 30
  [Exists, {kind: array}, [25, 29, 13], 30, Boolean], # 31
  [Subscript, {kind: array}, [25, 29], ~, Scalar], # 32
  [PadAccess, {sigil: $, symbol: l}, [13], ~, Unknown], # 33
  [Phi, {region: 9}, [28, 47], ~, Int], # 34
  [Ref, ~, [32], ~, ScalarRef], # 35
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 36
  [TernaryExpr, ~, [31, 35, 36], 31, Scalar], # 37
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: void}, [33, 34], 37, Str], # 38
  [Subscript, {kind: array}, [25, 29, 38], ~, Scalar], # 39
  [NumGt, ~, [27, 29], 9, Boolean], # 40
  [PostfixDeref, {sigil: $}, [37, 38], ~, Scalar], # 41
  [TernaryExpr, ~, [31, 41, 39], 38, Scalar], # 42
  [Coerce, {from_repr: Scalar, to_repr: Str}, [42], ~, Str], # 43
  [Concat, ~, [10, 43], ~, Str], # 44
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 45
  [Add, ~, [29, 45], ~, Int], # 46
  [Add, ~, [34, 45], ~, Int]]} # 47
main::g: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, {kind: array}, [1, 4, 5], ~, Scalar], # 6
  [Subscript, {kind: array}, [3, 6, 5], ~, Scalar], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "!"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Subscript, {kind: array}, [3, 6], ~, Scalar], # 11
  [Assign, ~, [11, 10], 0, Str], # 12
  [Return, {implicit: true}, [10], 12], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 14
  [Concat, ~, [14, 9], ~, Str]]} # 15
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: l}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 7
  [ArrayLiteral, ~, [4, 5, 6, 7], 0, ArrayRef], # 8
  [Assign, ~, [3, 8], 8, ArrayRef], # 9
  [Loop, {bound: entry}, [9], 9], # 10
  [Phi, {region: 10}, [1, 51], ~, Str], # 11
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Phi, {memory: true, region: 10}, [9, 41], ~, Scalar], # 14
  [Proj, {index: 1}, [10]], # 15
  [Region, {head: 10}, [15]], # 16
  [Phi, {memory: true, region: 16}, [14], ~, Scalar], # 17
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [17], ~, Scalar], # 18
  [Coerce, {from_repr: Scalar, to_repr: Str}, [18], ~, Str], # 19
  [PadAccess, {sigil: $, symbol: l}, [17], ~, Unknown], # 20
  [PostfixDeref, {sigil: "@"}, [20, 17], ~, Array], # 21
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [19, 21, 17], ~, Str], # 22
  [Concat, ~, [13, 22], ~, Str], # 23
  [Return, {implicit: true}, [23], 16], # 24
  [PadAccess, {sigil: $, symbol: l}, [9], ~, Unknown], # 25
  [PostfixDeref, {sigil: "@"}, [25, 9], ~, Array], # 26
  [Count, ~, [26, 9], ~, Int], # 27
  [Count, ~, [26, 14], ~, Int], # 28
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 29
  [Phi, {region: 10}, [29, 53], ~, Int], # 30
  [Proj, {index: 0}, [10]], # 31
  [Exists, {kind: array}, [26, 30, 14], 31, Boolean], # 32
  [Subscript, {kind: array}, [26, 30], ~, Scalar], # 33
  [Subscript, {kind: array}, [26, 30, 14], ~, Scalar], # 34
  [PadAccess, {sigil: $, symbol: l}, [14], ~, Unknown], # 35
  [Ref, ~, [33], ~, ScalarRef], # 36
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 37
  [TernaryExpr, ~, [32, 36, 37], 32, Scalar], # 38
  [PostfixDeref, {sigil: $}, [38, 14], ~, Scalar], # 39
  [TernaryExpr, ~, [32, 39, 34], 38, Scalar], # 40
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: void}, [35], 40, Scalar], # 41
  [Subscript, {kind: array}, [26, 30, 41], ~, Scalar], # 42
  [NumGt, ~, [28, 30], 10, Boolean], # 43
  [Coerce, {from_repr: Scalar, to_repr: Str}, [40], ~, Str], # 44
  [Concat, ~, [11, 44], ~, Str], # 45
  [PostfixDeref, {sigil: $}, [38, 41], ~, Scalar], # 46
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
  [PostfixDeref, {sigil: "@"}, [3, 4], ~, Array], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [5, 4], 0, Scalar], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
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
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [13], ~, Scalar], # 14
  [Coerce, {from_repr: Scalar, to_repr: Str}, [14], ~, Str], # 15
  [PostfixDeref, {sigil: "@"}, [4, 13], ~, Array], # 16
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [15, 16, 13], ~, Str], # 17
  [Concat, ~, [8, 17], ~, Str], # 18
  [Return, {implicit: true}, [18], 12], # 19
  [Count, ~, [4, 9], ~, Int], # 20
  [Count, ~, [4, 10], ~, Int], # 21
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 22
  [Phi, {region: 5}, [22, 39], ~, Int], # 23
  [Proj, {index: 0}, [5]], # 24
  [Exists, {kind: array}, [4, 23, 10], 24, Boolean], # 25
  [Subscript, {kind: array}, [4, 23], ~, Scalar], # 26
  [Subscript, {kind: array}, [4, 23, 10], ~, Scalar], # 27
  [Ref, ~, [26], ~, ScalarRef], # 28
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 29
  [TernaryExpr, ~, [25, 28, 29], 25, Scalar], # 30
  [PostfixDeref, {sigil: $}, [30, 10], ~, Scalar], # 31
  [TernaryExpr, ~, [25, 31, 27], ~, Scalar], # 32
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: void}, [32], 30, Str], # 33
  [Subscript, {kind: array}, [4, 23, 33], ~, Scalar], # 34
  [NumGt, ~, [21, 23], 5, Boolean], # 35
  [PostfixDeref, {sigil: $}, [30, 33], ~, Scalar], # 36
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
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Call, {dispatch_kind: builtin, name: uc, param_names: []}, [4], ~, Str], # 5
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 6
  [Assign, ~, [6, 5], 0, Str], # 7
  [Return, {implicit: true}, [5], 7]]} # 8
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
main::__PROGRAM__: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: void}, ~, 0, Scalar], # 2
  [Return, {implicit: true}, [1], 2]]} # 3
main::f: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: a}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [Assign, ~, [4, 3], 0, Int], # 5
  [Loop, {bound: entry}, [5], 5], # 6
  [Phi, {region: 6}, [1, 40], ~, Str], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Phi, {memory: true, region: 6}, [5, 33], ~, Int], # 9
  [Proj, {index: 1}, [6]], # 10
  [Region, {head: 6}, [10]], # 11
  [Phi, {memory: true, region: 11}, [9], ~, Int], # 12
  [Exists, {kind: array}, [2, 8, 12], ~, Boolean], # 13
  [Constant, {const_type: string, value: e}, ~, ~, Str], # 14
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 15
  [TernaryExpr, ~, [13, 14, 15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [7, 16, 17], 11, Scalar], # 18
  [Return, {implicit: true}, [18], 18], # 19
  [Count, ~, [2, 5], ~, Int], # 20
  [Phi, {region: 6}, [8, 22], ~, Int], # 21
  [Add, ~, [21, 3], ~, Int], # 22
  [Count, ~, [2, 9], ~, Int], # 23
  [NumGt, ~, [23, 21], 6, Boolean], # 24
  [Proj, {index: 0}, [6]], # 25
  [Subscript, {kind: array}, [2, 8], ~, Scalar], # 26
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 27
  [Exists, {kind: array}, [2, 21, 9], 25, Boolean], # 28
  [Subscript, {kind: array}, [2, 21], ~, Scalar], # 29
  [Ref, ~, [29], ~, ScalarRef], # 30
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 31
  [TernaryExpr, ~, [28, 30, 31], 28, Scalar], # 32
  [Assign, ~, [26, 27], 32, Int], # 33
  [PostfixDeref, {sigil: $}, [32, 33], ~, Scalar], # 34
  [Subscript, {kind: array}, [2, 21, 33], ~, Scalar], # 35
  [TernaryExpr, ~, [28, 34, 35], 33, Scalar], # 36
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 37
  [DefinedOr, ~, [36, 37], ~, Scalar], # 38
  [Coerce, {from_repr: Scalar, to_repr: Str}, [38], ~, Str], # 39
  [Concat, ~, [7, 39], ~, Str]]} # 40
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
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [2, 3], 1, Scalar], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [1, 4, 4], ~, Unknown], # 5
  [Return, {implicit: true}, [5], 4]]} # 6
C::subs: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: S}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Call, {class_name: S, dispatch_kind: method, name: new, param_names: []}, [1, 2], 0, Object], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [Call, {class_name: S, dispatch_kind: method, name: new, param_names: []}, [1, 4], 3, Object], # 5
  [Call, {class_name: S, dispatch_kind: method, name: new, param_names: []}, [1, 2], 5, Object], # 6
  [ArrayLiteral, ~, [3, 5, 6], ~, List], # 7
  [Coerce, {from_repr: List, to_repr: Scalar}, [6], ~, Scalar], # 8
  [Return, {implicit: true}, [7, 8], 6]]} # 9
S::name: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
S::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [HashLiteral, ~, [1, 5], 0, HashRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7, 4], ~, Scalar], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [6, 8, 4], ~, Unknown], # 9
  [Return, {implicit: true}, [9], 6]]} # 10
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: C, dispatch_kind: method, name: new, param_names: [], want: list}, ~, 0, Object], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 2, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Return, {implicit: true}, [1], 6]]} # 7
main::f: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [PadAccess, {sigil: $, symbol: cls}, ~, ~, Unknown], # 3
  [Constant, {const_type: string, value: subs}, ~, ~, Str], # 4
  [ArrayLiteral, ~, ~, 0, ArrayRef], # 5
  [HashLiteral, ~, [4, 5], 5, HashRef], # 6
  [Call, {dispatch_kind: method, name: subs, param_names: [], want: list}, [3], 6, Unknown], # 7
  [Loop, {bound: entry}, [7], 7], # 8
  [Proj, {index: 1}, [8]], # 9
  [Region, {head: 8}, [9]], # 10
  [Loop, {bound: entry}, [10], 10], # 11
  [Phi, {region: 11}, [2, 33], ~, Array], # 12
  [Phi, {memory: true, region: 8}, [7, 68], ~, Unknown], # 13
  [Phi, {memory: true, region: 10}, [13], ~, Unknown], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 12, 14], ~, Str], # 15
  [Proj, {index: 1}, [11]], # 16
  [Region, {head: 11}, [16]], # 17
  [Return, {implicit: true}, [15], 17], # 18
  [Subscript, {kind: hash}, [6, 4], ~, ArrayRef], # 19
  [PostfixDeref, {sigil: "@"}, [19, 14], ~, Array], # 20
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 21
  [Phi, {region: 11}, [21, 82], ~, Int], # 22
  [Subscript, {kind: array}, [20, 22, 14], ~, Scalar], # 23
  [Constant, {const_type: string, value: name}, ~, ~, Str], # 24
  [Subscript, {kind: hash}, [23, 24, 14], ~, Scalar], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 26
  [Constant, {const_type: string, value: ":"}, ~, ~, Str], # 27
  [Concat, ~, [26, 27], ~, Str], # 28
  [Constant, {const_type: string, value: same}, ~, ~, Str], # 29
  [Subscript, {kind: hash}, [23, 29, 14], ~, Scalar], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [30], ~, Str], # 31
  [Concat, ~, [28, 31], ~, Str], # 32
  [ListAppend, {collector: map}, [12, 32], ~, Array], # 33
  [Count, ~, [20, 14], ~, Int], # 34
  [ArrayLiteral, ~, [7], ~, Array], # 35
  [Count, ~, [35, 7], ~, Int], # 36
  [Phi, {region: 8}, [21, 91], ~, Int], # 37
  [Subscript, {kind: array}, [35, 37], ~, Scalar], # 38
  [Proj, {index: 0}, [8]], # 39
  [Ref, ~, [38], 39, ScalarRef], # 40
  [PostfixDeref, {sigil: $}, [40, 13], ~, Scalar], # 41
  [Call, {dispatch_kind: method, name: name, param_names: [], want: scalar}, [41], 40, Unknown], # 42
  [PostfixDeref, {sigil: "@"}, [19, 42], ~, Array], # 43
  [Loop, {bound: entry}, [42], 42], # 44
  [Phi, {memory: true, region: 44}, [42, 45], ~, Unknown], # 45
  [Proj, {index: 1}, [44]], # 46
  [Region, {head: 44}, [46]], # 47
  [Phi, {memory: true, region: 47}, [45], ~, Unknown], # 48
  [PostfixDeref, {sigil: $}, [40, 48], ~, Scalar], # 49
  [ArrayLiteral, ~, ~, ~, Array], # 50
  [Phi, {region: 44}, [50, 90], ~, Array], # 51
  [Count, ~, [51], ~, Int], # 52
  [If, ~, [47, 52], 47], # 53
  [Proj, {index: 1}, [53]], # 54
  [Call, {dispatch_kind: direct, name: main::root, param_names: [], want: scalar}, [49], 54, ScalarRef], # 55
  [PostfixDeref, {sigil: "@"}, [19, 55], ~, Array], # 56
  [PostfixDeref, {sigil: $}, [55, 55], ~, Scalar], # 57
  [Coerce, {from_repr: Scalar, to_repr: Num}, [57], ~, Num], # 58
  [PostfixDeref, {sigil: $}, [40, 55], 55, Scalar], # 59
  [Coerce, {from_repr: Scalar, to_repr: Num}, [59], ~, Num], # 60
  [NumEq, ~, [58, 60], ~, Boolean], # 61
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 62
  [TernaryExpr, ~, [61, 62, 21], ~, Int], # 63
  [HashLiteral, ~, [24, 42, 29, 63], 59, HashRef], # 64
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [56, 64, 55], 64, Int], # 65
  [Proj, {index: 0}, [53]], # 66
  [Region, {head: 53}, [66, 65]], # 67
  [Phi, {memory: true, predecessors: [66, 54], region: 67}, [48, 65], ~, Unknown], # 68
  [Count, ~, [35, 13], ~, Int], # 69
  [Subscript, {kind: array}, [35, 37, 13], ~, Scalar], # 70
  [NumGt, ~, [34, 22], 11, Boolean], # 71
  [Proj, {index: 0}, [11]], # 72
  [ArgsSource, ~, ~, ~, Array], # 73
  [Assign, {targets: 1}, [3, 73], ~, List], # 74
  [Subscript, {kind: array}, [35, 37, 48], ~, Scalar], # 75
  [Subscript, {kind: array}, [35, 37, 55], ~, Scalar], # 76
  [NumGt, ~, [69, 37], 8, Boolean], # 77
  [Count, ~, [43, 42], ~, Int], # 78
  [Count, ~, [43, 45], ~, Int], # 79
  [Phi, {region: 44}, [21, 93], ~, Int], # 80
  [Subscript, {kind: array}, [43, 80, 45], ~, Scalar], # 81
  [Add, ~, [22, 62], ~, Int], # 82
  [Subscript, {kind: hash}, [81, 24, 45], ~, Scalar], # 83
  [Coerce, {from_repr: Unknown, to_repr: Str}, [42], ~, Str], # 84
  [NumGt, ~, [79, 80], 44, Boolean], # 85
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 86
  [DefinedOr, ~, [83, 86], ~, Scalar], # 87
  [Coerce, {from_repr: Unknown, to_repr: Str}, [87], ~, Str], # 88
  [StrEq, ~, [88, 84], ~, Boolean], # 89
  [ListAppend, {collector: grep}, [51, 81, 89], ~, Array], # 90
  [Add, ~, [37, 62], ~, Int], # 91
  [Proj, {index: 0}, [44]], # 92
  [Add, ~, [80, 62], ~, Int]]} # 93
main::root: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Ref, ~, [3], ~, ScalarRef], # 4
  [Return, ~, [4], 0], # 5
  [PadAccess, {sigil: $, symbol: s}, ~, ~, Unknown], # 6
  [Assign, {targets: 1}, [6, 1], ~, List]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [HashLiteral, ~, [2, 3], 0, HashRef], # 4
  [MemStart], # 5
  [PostfixDeref, {sigil: "%"}, [4, 5], ~, Hash], # 6
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [6, 5], ~, List], # 7
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [7, 5], ~, List], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 8, 5], ~, Str], # 9
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 10
  [Subscript, {kind: hash}, [4, 10], ~, Undef], # 11
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 12
  [Assign, ~, [11, 12], 4, Int], # 13
  [Return, ~, [9], 13]]} # 14
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: a}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 3, 4, 5], 0, Int], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [1, 52], ~, Str], # 8
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Phi, {memory: true, region: 7}, [6, 46], ~, Unknown], # 11
  [Proj, {index: 1}, [7]], # 12
  [Region, {head: 7}, [12]], # 13
  [Phi, {memory: true, region: 13}, [11], ~, Unknown], # 14
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [14], ~, Scalar], # 15
  [Coerce, {from_repr: Scalar, to_repr: Str}, [15], ~, Str], # 16
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [16, 2, 14], ~, Str], # 17
  [Concat, ~, [10, 17], ~, Str], # 18
  [Return, ~, [18], 13], # 19
  [Count, ~, [2, 6], ~, Int], # 20
  [Count, ~, [2, 11], ~, Int], # 21
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 22
  [Phi, {region: 7}, [22, 40], ~, Int], # 23
  [Proj, {index: 0}, [7]], # 24
  [Exists, {kind: array}, [2, 23, 11], 24, Boolean], # 25
  [Subscript, {kind: array}, [2, 23], ~, Scalar], # 26
  [Subscript, {kind: array}, [2, 23, 11], ~, Scalar], # 27
  [Ref, ~, [26], ~, ScalarRef], # 28
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 29
  [TernaryExpr, ~, [25, 28, 29], 25, Scalar], # 30
  [PostfixDeref, {sigil: $}, [30, 11], ~, Scalar], # 31
  [TernaryExpr, ~, [25, 31, 27], 30, Scalar], # 32
  [EntryDef, {package: main, sigil: $, symbol: _}, [11], 32, Scalar], # 33
  [Loop, {bound: entry}, [33], 33], # 34
  [Phi, {memory: true, region: 34}, [11, 50], ~, Unknown], # 35
  [Count, ~, [2, 35], ~, Int], # 36
  [Phi, {region: 34}, [22, 39], ~, Int], # 37
  [Subscript, {kind: array}, [2, 37], ~, Scalar], # 38
  [Add, ~, [37, 3], ~, Int], # 39
  [Add, ~, [23, 3], ~, Int], # 40
  [NumGt, ~, [21, 23], 7, Boolean], # 41
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 42
  [Proj, {index: 1}, [34]], # 43
  [Region, {head: 34}, [43]], # 44
  [Phi, {memory: true, region: 44}, [35], ~, Unknown], # 45
  [EntryWrite, ~, [42, 33, 45], 44, Unknown], # 46
  [NumGt, ~, [36, 37], 34, Boolean], # 47
  [Proj, {index: 0}, [34]], # 48
  [EntryWrite, ~, [42, 22, 35], 48, Unknown], # 49
  [Assign, ~, [38, 22], 49, Int], # 50
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 39], ~, Str], # 3
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [MemStart], # 6
  [Phi, {memory: true, region: 2}, [6, 41], ~, Unknown], # 7
  [Proj, {index: 1}, [2]], # 8
  [Region, {head: 2}, [8]], # 9
  [Phi, {memory: true, region: 9}, [7], ~, Unknown], # 10
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [10], ~, Scalar], # 11
  [Coerce, {from_repr: Scalar, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 13
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 14
  [ArrayLiteral, {sigil: "@", symbol: a}, [13, 14], ~, Array], # 15
  [PostfixDeref, {sigil: "@"}, [15, 10], ~, Array], # 16
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [12, 16, 10], ~, Str], # 17
  [Concat, ~, [5, 17], ~, Str], # 18
  [Return, ~, [18], 9], # 19
  [Count, ~, [15, 7], ~, Int], # 20
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 21
  [Phi, {region: 2}, [21, 26], ~, Int], # 22
  [NumGt, ~, [20, 22], 2, Boolean], # 23
  [Proj, {index: 0}, [2]], # 24
  [Exists, {kind: array}, [15, 22, 7], 24, Boolean], # 25
  [Add, ~, [22, 13], ~, Int], # 26
  [Subscript, {kind: array}, [15, 22], ~, Scalar], # 27
  [Ref, ~, [15], ~, ArrayRef], # 28
  [Subscript, {kind: array}, [28, 21], ~, Scalar], # 29
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 30
  [Ref, ~, [27], ~, ScalarRef], # 31
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 32
  [TernaryExpr, ~, [25, 31, 32], 25, Scalar], # 33
  [Assign, ~, [29, 30], 33, Int], # 34
  [Subscript, {kind: array}, [15, 22, 34], ~, Scalar], # 35
  [PostfixDeref, {sigil: $}, [33, 34], ~, Scalar], # 36
  [TernaryExpr, ~, [25, 36, 35], 34, Scalar], # 37
  [Coerce, {from_repr: Scalar, to_repr: Str}, [37], ~, Str], # 38
  [Concat, ~, [3, 38], ~, Str], # 39
  [Constant, {const_type: integer, value: "8"}, ~, ~, Int], # 40
  [Assign, ~, [29, 40], 37, Int], # 41
  [Count, ~, [15, 6], ~, Int]]} # 42
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [1], ~, Scalar], # 2
  [Coerce, {from_repr: Scalar, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [3, 4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [ArrayLiteral, {sigil: "@", symbol: "n"}, [4, 5], ~, Array], # 9
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [9, 10], ~, Int], # 11
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: void}, [11], 0, Int], # 12
  [Loop, {bound: entry}, [12], 12], # 13
  [Phi, {memory: true, region: 13}, [12, 35], ~, Int], # 14
  [Proj, {index: 1}, [13]], # 15
  [Region, {head: 13}, [15]], # 16
  [Phi, {memory: true, region: 16}, [14], ~, Int], # 17
  [PostfixDeref, {sigil: "@"}, [9, 17], ~, Array], # 18
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [3, 18, 17], ~, Str], # 19
  [Concat, ~, [8, 19], ~, Str], # 20
  [Return, ~, [20], 16], # 21
  [ArrayLiteral, ~, [4], ~, Array], # 22
  [PostfixDeref, {sigil: "@"}, [22, 12], ~, Array], # 23
  [Slice, {kind: array}, [23, 9], ~, List], # 24
  [ArrayLiteral, ~, [24], ~, Array], # 25
  [Count, ~, [25, 12], ~, Int], # 26
  [Count, ~, [25, 14], ~, Int], # 27
  [Phi, {region: 13}, [10, 36], ~, Int], # 28
  [NumGt, ~, [27, 28], 13, Boolean], # 29
  [Proj, {index: 0}, [13]], # 30
  [Subscript, {kind: array}, [25, 28, 14], ~, Scalar], # 31
  [Subscript, {kind: array}, [25, 28], ~, Scalar], # 32
  [Ref, ~, [32], ~, ScalarRef], # 33
  [LocalAlias, {name: _}, [33], 30, Unknown], # 34
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: void}, [31], 34, Int], # 35
  [Add, ~, [28, 4], ~, Int]]} # 36
main::g: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Subscript, {kind: array}, [2, 3], ~, Scalar], # 4
  [Assign, ~, [4, 1], 0, Int], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {memory: true, region: 2}, [1, 29], ~, Unknown], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Phi, {memory: true, region: 5}, [3], ~, Unknown], # 6
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 9
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 10
  [ArrayLiteral, {sigil: "@", symbol: "n"}, [9, 10], ~, Array], # 11
  [PostfixDeref, {sigil: "@"}, [11, 6], ~, Array], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [8, 12, 6], ~, Str], # 13
  [Return, ~, [13], 5], # 14
  [Count, ~, [11, 3], ~, Int], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Phi, {region: 2}, [16, 21], ~, Int], # 17
  [NumGt, ~, [15, 17], 2, Boolean], # 18
  [Proj, {index: 0}, [2]], # 19
  [Exists, {kind: array}, [11, 17, 3], 19, Boolean], # 20
  [Add, ~, [17, 9], ~, Int], # 21
  [Subscript, {kind: array}, [11, 17, 3], ~, Int], # 22
  [Subscript, {kind: array}, [11, 17], ~, Scalar], # 23
  [Ref, ~, [23], ~, ScalarRef], # 24
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 25
  [TernaryExpr, ~, [20, 24, 25], ~, Scalar], # 26
  [LocalAlias, {name: _}, [26], 20, Unknown], # 27
  [Count, ~, [11, 1], ~, Int], # 28
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: void}, [22], 27, Num]]} # 29
main::g: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 8
  [Assign, ~, [8, 7], 0, Num], # 9
  [Return, {implicit: true}, [7], 9]]} # 10
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Int], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Proj, {index: 1}, [2]], # 3
  [Region, {head: 2}, [3]], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Phi, {region: 5}, [1, 41], ~, Int], # 6
  [Proj, {index: 1}, [5]], # 7
  [Region, {head: 5}, [7]], # 8
  [Return, ~, [6], 8], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 11
  [ArrayLiteral, ~, [1, 10, 11], ~, Array], # 12
  [MemStart], # 13
  [PostfixDeref, {sigil: "@"}, [12, 13], ~, Array], # 14
  [Phi, {memory: true, region: 2}, [13, 15], ~, Unknown], # 15
  [Count, ~, [14, 15], ~, Int], # 16
  [Phi, {region: 2}, [1, 46], ~, Int], # 17
  [NumGt, ~, [16, 17], 2, Boolean], # 18
  [Proj, {index: 0}, [2]], # 19
  [ArrayLiteral, ~, ~, ~, Array], # 20
  [Phi, {region: 2}, [20, 48], ~, Array], # 21
  [Ref, ~, [21], ~, ArrayRef], # 22
  [Phi, {memory: true, region: 4}, [15], ~, Unknown], # 23
  [Phi, {memory: true, region: 5}, [23, 67], ~, Unknown], # 24
  [PadAccess, {sigil: $, symbol: pos}, [24], ~, Unknown], # 25
  [Phi, {region: 5}, [1, 49], ~, Int], # 26
  [Proj, {index: 0}, [5]], # 27
  [Assign, ~, [25, 26], 27, Int], # 28
  [PadAccess, {sigil: $, symbol: pos}, [28], ~, Unknown], # 29
  [Call, {dispatch_kind: direct, name: main::set, param_names: [], want: void}, [22, 29], 28, Int], # 30
  [EnvRead, {key: P}, ~, ~, Str], # 31
  [DefinedOr, ~, [31, 10], ~, Str], # 32
  [If, ~, [30, 32], 30], # 33
  [Proj, {index: 0}, [33]], # 34
  [Loop, {bound: entry}, [34], 34], # 35
  [Phi, {region: 35}, [6, 45], ~, Int], # 36
  [Proj, {index: 1}, [35]], # 37
  [Region, {head: 35}, [37]], # 38
  [Proj, {index: 1}, [33]], # 39
  [Region, {head: 33}, [38, 39]], # 40
  [Phi, {predecessors: [34, 39], region: 40}, [36, 6], ~, Int], # 41
  [Phi, {memory: true, region: 8}, [24], ~, Unknown], # 42
  [ArrayLiteral, ~, ~, 19, ArrayRef], # 43
  [Phi, {region: 35}, [1, 52], ~, Int], # 44
  [Add, ~, [36, 10], ~, Int], # 45
  [Add, ~, [17, 10], ~, Int], # 46
  [Subscript, {kind: array}, [14, 17, 15], ~, Scalar], # 47
  [ListAppend, {collector: map}, [21, 43], ~, Array], # 48
  [Add, ~, [26, 10], ~, Int], # 49
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 50
  [NumGt, ~, [50, 26], 5, Boolean], # 51
  [Add, ~, [44, 10], ~, Int], # 52
  [PadAccess, {sigil: $, symbol: pos}, [30], ~, Num], # 53
  [Subscript, {kind: array}, [21, 53], ~, Scalar], # 54
  [PostfixDeref, {sigil: "@"}, [54, 30], ~, Array], # 55
  [Count, ~, [55, 30], ~, Int], # 56
  [NumGt, ~, [56, 44], 35, Boolean], # 57
  [Subtract, ~, [53, 10], ~, Num], # 58
  [Subscript, {kind: array}, [21, 58], ~, Scalar], # 59
  [NumGt, ~, [53, 10], ~, Boolean], # 60
  [If, ~, [40, 60], 40], # 61
  [Proj, {index: 0}, [61]], # 62
  [ArrayLiteral, ~, ~, 62, ArrayRef], # 63
  [Assign, ~, [59, 63], 63, ArrayRef], # 64
  [Proj, {index: 1}, [61]], # 65
  [Region, {head: 61}, [64, 65]], # 66
  [Phi, {memory: true, predecessors: [62, 65], region: 66}, [64, 30], ~, Scalar], # 67
  [Count, ~, [14, 13], ~, Int], # 68
  [Proj, {index: 0}, [35]]]} # 69
main::set: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 1
  [PadAccess, {sigil: $, symbol: p}, ~, ~, Unknown], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [PostfixDeref, {sigil: "@"}, [3, 4], ~, Array], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 7
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 8
  [ArrayLiteral, ~, [6, 7, 8], 0, ArrayRef], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [5, 9, 4], 9, Int], # 10
  [Return, {implicit: true}, [10], 10], # 11
  [ArgsSource, ~, ~, ~, Array], # 12
  [Assign, {targets: 2}, [1, 2, 12], ~, List]]} # 13
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
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
N::n: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
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
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [6, 7, 8], ~, Unknown], # 9
  [Return, {implicit: true}, [9], 6], # 10
  [ArgsSource, ~, ~, ~, Array], # 11
  [Assign, {targets: 3}, [7, 2, 4, 11], ~, List]]} # 12
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [2, 3], 0, Object], # 4
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [a], want: list}, [4], 4, Object], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [5], 5, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
main::f: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: ctx}, [2], ~, Unknown], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Assign, {targets: 1}, [3, 4], 0, List], # 5
  [PadAccess, {sigil: $, symbol: ctx}, [5], ~, Unknown], # 6
  [Call, {dispatch_kind: direct, name: main::vals, param_names: [], want: list}, [6], 5, List], # 7
  [Loop, {bound: entry}, [7], 7], # 8
  [Proj, {index: 1}, [8]], # 9
  [Region, {head: 8}, [9]], # 10
  [Loop, {bound: each}, [10], 10], # 11
  [Phi, {region: 11}, [1, 64], ~, Str], # 12
  [PadAccess, {sigil: "@", symbol: stmts}, ~, ~, Scalar], # 13
  [Phi, {memory: true, region: 8}, [7, 57], ~, List], # 14
  [Phi, {memory: true, region: 10}, [14], ~, List], # 15
  [Phi, {memory: true, region: 11}, [15, 70], ~, List], # 16
  [Proj, {index: 1}, [11]], # 17
  [Region, {head: 11}, [17]], # 18
  [Phi, {memory: true, region: 18}, [16], ~, List], # 19
  [Count, ~, [13, 19], ~, Int], # 20
  [Concat, ~, [12, 20], ~, Str], # 21
  [Return, ~, [21], 18], # 22
  [ArrayLiteral, ~, [7], ~, Array], # 23
  [Count, ~, [23, 7], ~, Int], # 24
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 25
  [Phi, {region: 8}, [25, 72], ~, Int], # 26
  [Subscript, {kind: array}, [23, 26], ~, Scalar], # 27
  [Proj, {index: 0}, [8]], # 28
  [Ref, ~, [27], 28, ScalarRef], # 29
  [PostfixDeref, {sigil: $}, [29, 7], 29, Scalar], # 30
  [Subscript, {kind: array}, [23, 26, 7], ~, Scalar], # 31
  [PostfixDeref, {sigil: $}, [29, 7], ~, Scalar], # 32
  [Subscript, {kind: array}, [23, 26, 7], ~, Scalar], # 33
  [PostfixDeref, {sigil: $}, [29, 7], ~, Scalar], # 34
  [Subscript, {kind: array}, [23, 26, 7], ~, Scalar], # 35
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 36
  [Exists, {kind: hash}, [34, 36, 7], ~, Boolean], # 37
  [PostfixDeref, {sigil: $}, [29, 7], ~, Scalar], # 38
  [Subscript, {kind: array}, [23, 26, 7], ~, Scalar], # 39
  [RefType, ~, [30], ~, Str], # 40
  [Constant, {const_type: string, value: ARRAY}, ~, ~, Str], # 41
  [StrEq, ~, [40, 41], ~, Boolean], # 42
  [If, ~, [30, 42], 30], # 43
  [Proj, {index: 1}, [43]], # 44
  [RefType, ~, [32], ~, Str], # 45
  [Constant, {const_type: string, value: HASH}, ~, ~, Str], # 46
  [StrEq, ~, [45, 46], ~, Boolean], # 47
  [And, ~, [47, 37], ~, Boolean], # 48
  [If, ~, [44, 48], 44], # 49
  [Proj, {index: 0}, [49]], # 50
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [13, 38, 7], 50, Int], # 51
  [Proj, {index: 1}, [49]], # 52
  [Region, {head: 49}, [52, 51]], # 53
  [Phi, {memory: true, predecessors: [52, 50], region: 53}, [7, 51], ~, List], # 54
  [Proj, {index: 0}, [43]], # 55
  [Region, {head: 43}, [55, 53]], # 56
  [Phi, {memory: true, predecessors: [55, 44], region: 56}, [7, 54], ~, List], # 57
  [PadAccess, {sigil: $, symbol: ctx}, [15], ~, Unknown], # 58
  [ArrayLiteral, {sigil: "@", symbol: walk}, [58], ~, Array], # 59
  [Call, {dispatch_kind: builtin, memory_input: true, name: pop, param_names: []}, [59, 16], 11, Scalar], # 60
  [Proj, {index: 0}, [11]], # 61
  [Call, {dispatch_kind: method, name: "n", param_names: [], want: scalar}, [60], 61, Unknown], # 62
  [Coerce, {from_repr: Unknown, to_repr: Str}, [62], ~, Str], # 63
  [Concat, ~, [12, 63], ~, Str], # 64
  [NumGt, ~, [24, 26], 8, Boolean], # 65
  [Not, ~, [60], ~, Boolean], # 66
  [Not, ~, [66], 11, Boolean], # 67
  [Call, {dispatch_kind: method, name: kids, param_names: [], want: scalar}, [60], 62, Unknown], # 68
  [PostfixDeref, {sigil: "@"}, [68, 68], ~, Array], # 69
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [59, 69, 68], 68, Int], # 70
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 71
  [Add, ~, [26, 71], ~, Int]]} # 72
main::vals: {start: 0, returns: [10], nodes: [
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
  [Return, {implicit: true}, [8, 9], 7]]} # 10
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 1
  [MemStart], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {memory: true, region: 3}, [2, 43], ~, Unknown], # 4
  [Proj, {index: 1}, [3]], # 5
  [Region, {head: 3}, [5]], # 6
  [Phi, {memory: true, region: 6}, [4], ~, Unknown], # 7
  [Loop, {bound: entry}, [6], 6], # 8
  [Phi, {memory: true, region: 8}, [7, 64], ~, Unknown], # 9
  [Proj, {index: 1}, [8]], # 10
  [Region, {head: 8}, [10]], # 11
  [Phi, {memory: true, region: 11}, [9], ~, Unknown], # 12
  [Loop, {bound: entry}, [11], 11], # 13
  [Phi, {memory: true, region: 13}, [12, 50], ~, Unknown], # 14
  [Proj, {index: 1}, [13]], # 15
  [Region, {head: 13}, [15]], # 16
  [Phi, {memory: true, region: 16}, [14], ~, Unknown], # 17
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [17], ~, Scalar], # 18
  [Coerce, {from_repr: Scalar, to_repr: Str}, [18], ~, Str], # 19
  [ArrayLiteral, ~, ~, ~, Array], # 20
  [Phi, {region: 3}, [20, 44], ~, Array], # 21
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [19, 21, 17], ~, Str], # 22
  [Concat, ~, [1, 22], ~, Str], # 23
  [Return, ~, [23], 16], # 24
  [Constant, {const_type: string, value: ax}, ~, ~, Str], # 25
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 26
  [Constant, {const_type: string, value: xc}, ~, ~, Str], # 27
  [ArrayLiteral, {sigil: "@", symbol: a}, [25, 26, 27], ~, Array], # 28
  [Count, ~, [28, 4], ~, Int], # 29
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 30
  [Phi, {region: 3}, [30, 36], ~, Int], # 31
  [NumGt, ~, [29, 31], 3, Boolean], # 32
  [Proj, {index: 0}, [3]], # 33
  [Exists, {kind: array}, [28, 31, 4], 33, Boolean], # 34
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 35
  [Add, ~, [31, 35], ~, Int], # 36
  [Subscript, {kind: array}, [28, 31, 4], ~, Str], # 37
  [Subscript, {kind: array}, [28, 31], ~, Scalar], # 38
  [Ref, ~, [38], ~, ScalarRef], # 39
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 40
  [TernaryExpr, ~, [34, 39, 40], ~, Scalar], # 41
  [LocalAlias, {name: _}, [41], 34, Unknown], # 42
  [Call, {dispatch_kind: direct, name: main::is_x, param_names: [], want: scalar}, ~, 42, Boolean], # 43
  [ListAppend, {collector: grep}, [21, 37, 43], ~, Array], # 44
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 45
  [Phi, {region: 13}, [35, 63], ~, Int], # 46
  [NumGt, ~, [45, 46], 13, Boolean], # 47
  [Proj, {index: 0}, [13]], # 48
  [LocalAlias, {name: _}, [46], 48, Unknown], # 49
  [Call, {dispatch_kind: direct, name: main::show, param_names: [], want: void}, ~, 49, Scalar], # 50
  [Count, ~, [28, 2], ~, Int], # 51
  [Count, ~, [28, 7], ~, Int], # 52
  [Count, ~, [28, 9], ~, Int], # 53
  [Phi, {region: 8}, [30, 62], ~, Int], # 54
  [Proj, {index: 0}, [8]], # 55
  [Exists, {kind: array}, [28, 54, 9], 55, Boolean], # 56
  [Subscript, {kind: array}, [28, 54], ~, Scalar], # 57
  [NumGt, ~, [53, 54], 8, Boolean], # 58
  [Ref, ~, [57], ~, ScalarRef], # 59
  [TernaryExpr, ~, [56, 59, 40], ~, Scalar], # 60
  [LocalAlias, {name: _}, [60], 56, Unknown], # 61
  [Add, ~, [54, 35], ~, Int], # 62
  [Add, ~, [46, 35], ~, Int], # 63
  [Call, {dispatch_kind: direct, name: main::show, param_names: [], want: void}, ~, 61, Scalar]]} # 64
main::is_x: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 1
  [Coerce, {from_repr: Scalar, to_repr: Str}, [1], ~, Str], # 2
  [RegexMatch, {flags: "", pattern: x}, [2], ~, Boolean], # 3
  [Return, {implicit: true}, [3], 0]]} # 4
main::show: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: _}, [1], ~, Scalar], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Print, ~, [3], 0, Scalar], # 4
  [Return, {implicit: true}, [4], 4]]} # 5
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::bump: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 1
  [Coerce, {from_repr: Scalar, to_repr: Str}, [1], ~, Str], # 2
  [Constant, {const_type: string, value: "!"}, ~, ~, Str], # 3
  [Concat, ~, [2, 3], ~, Str], # 4
  [MemStart], # 5
  [EntryWrite, ~, [1, 4, 5], 0, Unknown], # 6
  [Return, {implicit: true}, [4], 6]]} # 7
main::f: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar], # 1
  [Constant, {const_type: string, value: top}, ~, ~, Str], # 2
  [MemStart], # 3
  [EntryWrite, ~, [1, 2, 3], 0, Unknown], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Phi, {memory: true, region: 5}, [4, 34], ~, Unknown], # 6
  [Proj, {index: 1}, [5]], # 7
  [Region, {head: 5}, [7]], # 8
  [Phi, {memory: true, region: 8}, [6], ~, Unknown], # 9
  [EntryDef, {package: main, sigil: $, symbol: _}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [9], ~, Scalar], # 13
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 16
  [ArrayLiteral, {sigil: "@", symbol: a}, [15, 16], ~, Array], # 17
  [PostfixDeref, {sigil: "@"}, [17, 9], ~, Array], # 18
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [14, 18, 9], ~, Str], # 19
  [Concat, ~, [12, 19], ~, Str], # 20
  [Return, ~, [20], 8], # 21
  [Count, ~, [17, 4], ~, Int], # 22
  [Count, ~, [17, 6], ~, Int], # 23
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 24
  [Phi, {region: 5}, [24, 35], ~, Int], # 25
  [NumGt, ~, [23, 25], 5, Boolean], # 26
  [Proj, {index: 0}, [5]], # 27
  [Exists, {kind: array}, [17, 25, 6], 27, Boolean], # 28
  [Subscript, {kind: array}, [17, 25], ~, Scalar], # 29
  [Ref, ~, [29], ~, ScalarRef], # 30
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 31
  [TernaryExpr, ~, [28, 30, 31], ~, Scalar], # 32
  [LocalAlias, {name: _}, [32], 28, Unknown], # 33
  [Call, {dispatch_kind: direct, name: main::bump, param_names: [], want: void}, ~, 33, Str], # 34
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
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [HashLiteral, ~, [1, 5], 0, HashRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7, 4], ~, Scalar], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [6, 8, 4], ~, Unknown], # 9
  [Return, {implicit: true}, [9], 6]]} # 10
N::s: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 7
  [DefinedOr, ~, [6, 7], ~, Scalar], # 8
  [Return, {implicit: true}, [8], 0]]} # 9
N::set_stamp: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [1, 5], ~, Scalar], # 6
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 7
  [Subscript, {kind: hash}, [6, 7], ~, Scalar], # 8
  [Assign, ~, [8, 4], 0, Scalar], # 9
  [Return, {implicit: true}, [4], 9]]} # 10
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [PadAccess, {sigil: "@", symbol: stale}, ~, ~, Scalar], # 3
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [4, 5], 0, Object], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [4, 7], 6, Object], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [3, 6, 8, 8], 8, Int], # 9
  [Loop, {bound: entry}, [9], 9], # 10
  [Proj, {index: 1}, [10]], # 11
  [Region, {head: 10}, [11]], # 12
  [Loop, {bound: entry}, [12], 12], # 13
  [Phi, {region: 13}, [2, 36], ~, Array], # 14
  [Phi, {memory: true, region: 10}, [9, 48], ~, Unknown], # 15
  [Phi, {memory: true, region: 12}, [15], ~, Unknown], # 16
  [Phi, {memory: true, region: 13}, [16, 35], ~, Unknown], # 17
  [Proj, {index: 1}, [13]], # 18
  [Region, {head: 13}, [18]], # 19
  [Phi, {memory: true, region: 19}, [17], ~, Unknown], # 20
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 14, 20], ~, Str], # 21
  [Return, ~, [21], 19], # 22
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 23
  [Phi, {region: 10}, [23, 25], ~, Int], # 24
  [Add, ~, [24, 5], ~, Int], # 25
  [Phi, {region: 13}, [23, 27], ~, Int], # 26
  [Add, ~, [26, 5], ~, Int], # 27
  [Count, ~, [3, 9], ~, Int], # 28
  [ArrayLiteral, ~, [3], ~, List], # 29
  [Subscript, {kind: array}, [29, 26, 17], ~, Scalar], # 30
  [Subscript, {kind: array}, [29, 26], ~, Scalar], # 31
  [Ref, ~, [31], ~, ScalarRef], # 32
  [Proj, {index: 0}, [13]], # 33
  [LocalAlias, {name: _}, [32], 33, Unknown], # 34
  [Call, {dispatch_kind: method, name: s, param_names: [], want: list}, [30], 34, Unknown], # 35
  [ListAppend, {collector: map}, [14, 35], ~, Array], # 36
  [Count, ~, [3, 15], ~, Int], # 37
  [Subscript, {kind: array}, [3, 24, 15], ~, Scalar], # 38
  [Proj, {index: 0}, [10]], # 39
  [Exists, {kind: array}, [3, 24, 15], 39, Boolean], # 40
  [Subscript, {kind: array}, [3, 24], ~, Scalar], # 41
  [ArrayLiteral, ~, [3], ~, List], # 42
  [NumGt, ~, [37, 24], 10, Boolean], # 43
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 44
  [Ref, ~, [41], ~, ScalarRef], # 45
  [TernaryExpr, ~, [40, 45, 44], ~, Scalar], # 46
  [LocalAlias, {name: _}, [46], 40, Unknown], # 47
  [Call, {dispatch_kind: method, name: set_stamp, param_names: [], want: void}, [38, 44], 47, Unknown], # 48
  [Count, ~, [29, 17], ~, Int], # 49
  [NumGt, ~, [49, 26], 13, Boolean], # 50
  [Count, ~, [29, 16], ~, Int]]} # 51
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
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [ArrayLiteral, ~, [2, 3, 4], 0, ArrayRef], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [5, 2], 5, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 8
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 9
  [ArrayLiteral, ~, [9], 6, ArrayRef], # 10
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 11
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [10, 11], 10, Str], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [7, 8, 13, 14], 12, Scalar], # 15
  [Return, {implicit: true}, [1], 15]]} # 16
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
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [6, 11, 16], ~, Str], # 17
  [Concat, ~, [5, 17], ~, Str], # 18
  [Concat, ~, [18, 4], ~, Str], # 19
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 20
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown], # 21
  [PostfixDeref, {sigil: "@"}, [21, 16], ~, Array], # 22
  [ArrayLiteral, ~, [22], ~, Array], # 23
  [ArrayLiteral, ~, ~, ~, Array], # 24
  [TernaryExpr, ~, [20, 23, 24], ~, Array], # 25
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, [25], 15, Int], # 26
  [Coerce, {from_repr: Unknown, to_repr: Str}, [26], ~, Str], # 27
  [Concat, ~, [19, 27], ~, Str], # 28
  [Concat, ~, [28, 4], ~, Str], # 29
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [26], ~, Scalar], # 30
  [Coerce, {from_repr: Scalar, to_repr: Str}, [30], ~, Str], # 31
  [PostfixDeref, {sigil: "@"}, [21, 26], ~, Array], # 32
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [31, 32, 26], ~, Str], # 33
  [Concat, ~, [29, 33], ~, Str], # 34
  [Return, ~, [34], 26], # 35
  [PostfixDeref, {sigil: "@"}, [21, 12], ~, Array], # 36
  [ArrayLiteral, ~, [36], ~, Array], # 37
  [ArrayLiteral, ~, ~, ~, Array], # 38
  [TernaryExpr, ~, [20, 37, 38], ~, Array], # 39
  [ArrayLiteral, ~, [39], ~, Array], # 40
  [Count, ~, [40, 12], ~, Int], # 41
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 42
  [Phi, {region: 2}, [42, 47], ~, Int], # 43
  [NumGt, ~, [41, 43], 2, Boolean], # 44
  [Proj, {index: 0}, [2]], # 45
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 46
  [Add, ~, [43, 46], ~, Int], # 47
  [Subscript, {kind: array}, [40, 43, 12], ~, Scalar], # 48
  [ArgsSource, ~, ~, ~, Array], # 49
  [Assign, {targets: 2}, [21, 20, 49], ~, List], # 50
  [ArrayLiteral, ~, [36], ~, Array], # 51
  [ArrayLiteral, ~, ~, ~, Array], # 52
  [TernaryExpr, ~, [20, 51, 52], ~, Array], # 53
  [Count, ~, [53, 12], ~, Int], # 54
  [Phi, {region: 10}, [42, 64], ~, Int], # 55
  [Coerce, {from_repr: Unknown, to_repr: Str}, [48], ~, Str], # 56
  [Count, ~, [53, 13], ~, Int], # 57
  [NumGt, ~, [57, 55], 10, Boolean], # 58
  [Proj, {index: 0}, [10]], # 59
  [Subscript, {kind: array}, [53, 55, 13], ~, Scalar], # 60
  [Ref, ~, [60], ~, ScalarRef], # 61
  [LocalAlias, {name: _}, [61], 59, Unknown], # 62
  [Call, {dispatch_kind: direct, name: main::ok1, param_names: [], want: scalar}, ~, 62, Boolean], # 63
  [Add, ~, [55, 46], ~, Int], # 64
  [Concat, ~, [3, 56], ~, Str], # 65
  [ListAppend, {collector: grep}, [11, 60, 63], ~, Array]]} # 66
main::g: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 4
  [Assign, ~, [3, 4], 0, Int], # 5
  [Count, ~, [1, 5], ~, Int], # 6
  [Return, {implicit: true}, [6], 5]]} # 7
main::ok1: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: _}, [1], ~, Scalar], # 2
  [Coerce, {from_repr: Scalar, to_repr: Num}, [2], ~, Num], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [NumGt, ~, [3, 4], ~, Boolean], # 5
  [Return, {implicit: true}, [5], 0]]} # 6
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
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: Z}, ~, ~, Str], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Return, {implicit: true}, [1], 6]]} # 7
main::f: {start: 0, returns: [35], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: u}, [1], ~, Unknown], # 2
  [Constant, {const_type: string, value: ab}, ~, ~, Str], # 3
  [Assign, ~, [2, 3], 0, Str], # 4
  [PadAccess, {sigil: $, symbol: u}, [4], ~, Unknown], # 5
  [PadAccess, {sigil: $, symbol: "y"}, ~, ~, Unknown], # 6
  [RegexSubst, {flags: "", pattern: a, replacement: ""}, [5, 6, 4], 4, Str], # 7
  [PadAccess, {sigil: $, symbol: w}, [7], ~, Unknown], # 8
  [Constant, {const_type: string, value: ayb}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: QQ}, ~, ~, Str], # 10
  [RegexMatch, {flags: "", pattern: "(Q)"}, [10], 7, Boolean], # 11
  [Assign, ~, [8, 9], 11, Str], # 12
  [PadAccess, {sigil: $, symbol: w}, [12], ~, Str], # 13
  [RegexMatch, {flags: "", pattern: "(y)"}, [13], ~, Boolean], # 14
  [RegexCapture, {"n": 1}, [14], ~, Str], # 15
  [RegexSubst, {flags: "", pattern: "(y)", replacement: ""}, [13, 15, 12], 12, Str], # 16
  [PadAccess, {sigil: $, symbol: v}, [16], ~, Unknown], # 17
  [Constant, {const_type: string, value: "sv_2mortal(x)"}, ~, ~, Str], # 18
  [Assign, ~, [17, 18], 16, Str], # 19
  [PadAccess, {sigil: $, symbol: v}, [19], ~, Str], # 20
  [RegexMatch, {flags: "", pattern: "^sv_2mortal\\((.+)\\)$"}, [20], ~, Boolean], # 21
  [RegexCapture, {"n": 1}, [21], ~, Str], # 22
  [RegexSubst, {flags: "", pattern: "^sv_2mortal\\((.+)\\)$", replacement: ""}, [20, 22, 19], 19, Str], # 23
  [PadAccess, {sigil: $, symbol: u}, [23], ~, Str], # 24
  [Coerce, {from_repr: Unknown, to_repr: Str}, [24], ~, Str], # 25
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 26
  [Concat, ~, [25, 26], ~, Str], # 27
  [PadAccess, {sigil: $, symbol: w}, [23], ~, Str], # 28
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 29
  [Concat, ~, [27, 29], ~, Str], # 30
  [Concat, ~, [30, 26], ~, Str], # 31
  [PadAccess, {sigil: $, symbol: v}, [23], ~, Str], # 32
  [Coerce, {from_repr: Unknown, to_repr: Str}, [32], ~, Str], # 33
  [Concat, ~, [31, 33], ~, Str], # 34
  [Return, ~, [34], 23], # 35
  [ArgsSource, ~, ~, ~, Array], # 36
  [Assign, {targets: 1}, [6, 36], ~, List]]} # 37
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
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "%$abc"}, ~, ~, Str], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [5], 3, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [1], 6, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [4, 7, 9, 10], 8, Scalar], # 11
  [Return, {implicit: true}, [1], 11]]} # 12
main::f: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: v}, ~, ~, Str], # 1
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
  [Return, ~, [11], 10], # 12
  [ArgsSource, ~, ~, ~, Array], # 13
  [Assign, {targets: 1}, [1, 13], ~, List]]} # 14
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
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
N::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: i}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [HashLiteral, ~, [1, 5], 0, HashRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7, 4], ~, Scalar], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [6, 8, 4], ~, Unknown], # 9
  [Return, {implicit: true}, [9], 6]]} # 10
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [2, 4], 0, Object], # 5
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [2, 3], 5, Object], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Proj, {index: 1}, [7]], # 8
  [Region, {head: 7}, [8]], # 9
  [Loop, {bound: entry}, [9], 9], # 10
  [Phi, {region: 10}, [1, 32], ~, Str], # 11
  [Proj, {index: 1}, [10]], # 12
  [Region, {head: 10}, [12]], # 13
  [Return, ~, [11], 13], # 14
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 15
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 16
  [HashLiteral, {sigil: "%", symbol: c}, [15, 5, 16, 6], ~, Hash], # 17
  [PadAccess, {sigil: "%", symbol: m}, ~, ~, Unknown], # 18
  [Phi, {memory: true, region: 7}, [6, 49], ~, Scalar], # 19
  [Phi, {memory: true, region: 9}, [19], ~, Scalar], # 20
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [18, 20], ~, List], # 21
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [21, 20], ~, List], # 22
  [ArrayLiteral, ~, [22], ~, Array], # 23
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 24
  [Phi, {region: 10}, [24, 37], ~, Int], # 25
  [Subscript, {kind: array}, [23, 25], ~, Scalar], # 26
  [Ref, ~, [26], ~, ScalarRef], # 27
  [Proj, {index: 0}, [10]], # 28
  [LocalAlias, {name: _}, [27], 28, Unknown], # 29
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, ~, 29, Scalar], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [30], ~, Str], # 31
  [Concat, ~, [11, 31], ~, Str], # 32
  [Phi, {memory: true, region: 10}, [20, 30], ~, Scalar], # 33
  [Phi, {memory: true, region: 13}, [33], ~, Scalar], # 34
  [Phi, {region: 7}, [24, 36], ~, Int], # 35
  [Add, ~, [35, 4], ~, Int], # 36
  [Add, ~, [25, 4], ~, Int], # 37
  [Call, {dispatch_kind: builtin, memory_input: true, name: values, param_names: [], want: list}, [17, 6], ~, List], # 38
  [Count, ~, [38, 6], ~, Int], # 39
  [Count, ~, [38, 19], ~, Int], # 40
  [Subscript, {kind: array}, [38, 35, 19], ~, Scalar], # 41
  [Subscript, {kind: array}, [38, 35], ~, Scalar], # 42
  [NumGt, ~, [40, 35], 7, Boolean], # 43
  [Proj, {index: 0}, [7]], # 44
  [Ref, ~, [42], ~, ScalarRef], # 45
  [LocalAlias, {name: _}, [45], 44, Unknown], # 46
  [Call, {dispatch_kind: method, name: id, param_names: [], want: scalar}, [41], 46, Unknown], # 47
  [Subscript, {kind: hash}, [18, 47], ~, Scalar], # 48
  [Assign, ~, [48, 41], 47, Scalar], # 49
  [Count, ~, [23, 33], ~, Int], # 50
  [NumGt, ~, [50, 25], 10, Boolean], # 51
  [Count, ~, [23, 20], ~, Int]]} # 52
main::g: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: _}, [1], ~, Scalar], # 2
  [Return, {implicit: true}, [2], 0]]} # 3
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::f: {start: 0, returns: [32], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, ~, 0, List], # 2
  [Loop, {bound: entry}, [2], 2], # 3
  [Phi, {region: 3}, [1, 47], ~, Scalar], # 4
  [PostfixDeref, {sigil: $}, [4], ~, Scalar], # 5
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 6
  [Proj, {index: 1}, [3]], # 7
  [Region, {head: 3}, [7]], # 8
  [Assign, ~, [5, 6], 8, Int], # 9
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, ~, 9, List], # 10
  [Loop, {bound: entry}, [10], 10], # 11
  [Proj, {index: 1}, [11]], # 12
  [Region, {head: 11}, [12]], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Phi, {region: 14}, [1, 67], ~, Unknown], # 15
  [PostfixDeref, {sigil: $}, [15], ~, Scalar], # 16
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 17
  [Proj, {index: 1}, [14]], # 18
  [Region, {head: 14}, [18]], # 19
  [Assign, ~, [16, 17], 19, Int], # 20
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [20], ~, Scalar], # 21
  [Coerce, {from_repr: Scalar, to_repr: Str}, [21], ~, Str], # 22
  [ArrayLiteral, {sigil: "@", symbol: a}, [2], ~, Array], # 23
  [PostfixDeref, {sigil: "@"}, [23, 20], ~, Array], # 24
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [22, 24, 20], ~, Str], # 25
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 26
  [Concat, ~, [25, 26], ~, Str], # 27
  [ArrayLiteral, ~, ~, ~, Array], # 28
  [Phi, {region: 11}, [28, 59], ~, Array], # 29
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [22, 29, 20], ~, Str], # 30
  [Concat, ~, [27, 30], ~, Str], # 31
  [Return, ~, [31], 20], # 32
  [Count, ~, [23, 2], ~, Int], # 33
  [Phi, {memory: true, region: 3}, [2, 47], ~, List], # 34
  [Count, ~, [23, 34], ~, Int], # 35
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 36
  [Phi, {region: 3}, [36, 68], ~, Int], # 37
  [Proj, {index: 0}, [3]], # 38
  [Exists, {kind: array}, [23, 37, 34], 38, Boolean], # 39
  [Subscript, {kind: array}, [23, 37], ~, Scalar], # 40
  [Subscript, {kind: array}, [23, 37, 34], ~, Scalar], # 41
  [NumGt, ~, [35, 37], 3, Boolean], # 42
  [Ref, ~, [40], ~, ScalarRef], # 43
  [TernaryExpr, ~, [39, 43, 1], 39, Scalar], # 44
  [PostfixDeref, {sigil: $}, [44, 34], ~, Scalar], # 45
  [TernaryExpr, ~, [39, 45, 41], ~, Scalar], # 46
  [Call, {dispatch_kind: direct, name: main::k, param_names: [], want: scalar}, [46], 44, ScalarRef], # 47
  [Phi, {memory: true, region: 8}, [34], ~, List], # 48
  [Phi, {memory: true, region: 11}, [10, 49], ~, Unknown], # 49
  [Phi, {memory: true, region: 13}, [49], ~, Unknown], # 50
  [Phi, {memory: true, region: 14}, [50, 75], ~, Unknown], # 51
  [Phi, {memory: true, region: 19}, [51], ~, Unknown], # 52
  [ArrayLiteral, ~, [10], ~, List], # 53
  [Phi, {region: 11}, [36, 77], ~, Int], # 54
  [Subscript, {kind: array}, [53, 54, 49], ~, Scalar], # 55
  [Coerce, {from_repr: Scalar, to_repr: Num}, [55], ~, Num], # 56
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 57
  [NumGt, ~, [56, 57], ~, Boolean], # 58
  [ListAppend, {collector: grep}, [29, 55, 58], ~, Array], # 59
  [Count, ~, [29, 50], ~, Int], # 60
  [Count, ~, [29, 51], ~, Int], # 61
  [Phi, {region: 14}, [36, 76], ~, Int], # 62
  [Proj, {index: 0}, [14]], # 63
  [Exists, {kind: array}, [29, 62, 51], 63, Boolean], # 64
  [Subscript, {kind: array}, [29, 62], ~, Scalar], # 65
  [Subscript, {kind: array}, [29, 62, 51], ~, Scalar], # 66
  [PadAccess, {sigil: $, symbol: q}, ~, ~, Unknown], # 67
  [Add, ~, [37, 57], ~, Int], # 68
  [NumGt, ~, [61, 62], 14, Boolean], # 69
  [Ref, ~, [65], ~, ScalarRef], # 70
  [TernaryExpr, ~, [64, 70, 1], 64, Scalar], # 71
  [PostfixDeref, {sigil: $}, [71, 51], ~, Scalar], # 72
  [TernaryExpr, ~, [64, 72, 66], ~, Scalar], # 73
  [Call, {dispatch_kind: direct, name: main::k, param_names: [], want: list}, [73], 71, ScalarRef], # 74
  [Assign, {targets: 1}, [67, 74], 74, ScalarRef], # 75
  [Add, ~, [62, 57], ~, Int], # 76
  [Add, ~, [54, 57], ~, Int], # 77
  [Count, ~, [53, 49], ~, Int], # 78
  [NumGt, ~, [78, 54], 11, Boolean], # 79
  [Subscript, {kind: array}, [53, 54], ~, Scalar], # 80
  [Count, ~, [53, 10], ~, Int], # 81
  [Ref, ~, [80], ~, ScalarRef], # 82
  [Proj, {index: 0}, [11]], # 83
  [LocalAlias, {name: _}, [82], 83, Unknown]]} # 84
main::g: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, List], # 4
  [Coerce, {from_repr: List, to_repr: Scalar}, [3], ~, Scalar], # 5
  [Return, {implicit: true}, [4, 5], 0]]} # 6
main::k: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Ref, ~, [3], ~, ScalarRef], # 4
  [Return, ~, [4], 0]]} # 5
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
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
N::new: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: id}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Constant, {const_type: string, value: prev}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7, 4], ~, Scalar], # 8
  [HashLiteral, ~, [1, 5, 6, 8], 0, HashRef], # 9
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 10
  [Subscript, {kind: array}, [2, 10, 4], ~, Scalar], # 11
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [9, 11, 4], ~, Unknown], # 12
  [Return, {implicit: true}, [12], 9]]} # 13
N::prev: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: prev}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [2, 6], 0, Object], # 7
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [2, 5, 7], 7, Object], # 8
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [2, 4, 8], 8, Object], # 9
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [2, 3, 9], 9, Object], # 10
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [10], 10, Str], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [12, 13], 11, Scalar], # 14
  [Return, {implicit: true}, [1], 14]]} # 15
main::f: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: ret}, ~, ~, Unknown], # 1
  [Call, {dispatch_kind: method, name: prev, param_names: [], want: list}, [1], 0, Unknown], # 2
  [Loop, {bound: entry}, [2], 2], # 3
  [Phi, {memory: true, region: 3}, [2, 4], ~, Unknown], # 4
  [Proj, {index: 1}, [3]], # 5
  [Region, {head: 3}, [5]], # 6
  [Phi, {memory: true, region: 6}, [4], ~, Unknown], # 7
  [Loop, {bound: entry}, [6], 6], # 8
  [Phi, {memory: true, region: 8}, [7, 60], ~, Unknown], # 9
  [Proj, {index: 1}, [8]], # 10
  [Region, {head: 8}, [10]], # 11
  [Phi, {memory: true, region: 11}, [9], ~, Unknown], # 12
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [12], ~, Scalar], # 13
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 14
  [PadAccess, {sigil: "@", symbol: chain}, ~, ~, Unknown], # 15
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [14, 15, 12], ~, Str], # 16
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [ArrayLiteral, ~, ~, ~, Array], # 19
  [Phi, {region: 3}, [19, 36], ~, Array], # 20
  [Count, ~, [20, 12], ~, Int], # 21
  [Concat, ~, [18, 21], ~, Str], # 22
  [Return, ~, [22], 11], # 23
  [ArrayLiteral, ~, [2], ~, List], # 24
  [Count, ~, [24, 2], ~, Int], # 25
  [ArgsSource, ~, ~, ~, Array], # 26
  [Assign, {targets: 1}, [1, 26], ~, List], # 27
  [Count, ~, [24, 4], ~, Int], # 28
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 29
  [Phi, {region: 3}, [29, 63], ~, Int], # 30
  [Subscript, {kind: array}, [24, 30, 4], ~, Scalar], # 31
  [Subscript, {kind: array}, [24, 30], ~, Scalar], # 32
  [NumGt, ~, [28, 30], 3, Boolean], # 33
  [Proj, {index: 0}, [3]], # 34
  [Defined, ~, [31], ~, Boolean], # 35
  [ListAppend, {collector: grep}, [20, 31, 35], ~, Array], # 36
  [Ref, ~, [32], ~, ScalarRef], # 37
  [LocalAlias, {name: _}, [37], 34, Unknown], # 38
  [Count, ~, [20, 7], ~, Int], # 39
  [Count, ~, [20, 9], ~, Int], # 40
  [Phi, {region: 8}, [29, 69], ~, Int], # 41
  [Subscript, {kind: array}, [20, 41, 9], ~, Scalar], # 42
  [Subscript, {kind: array}, [20, 41], ~, Scalar], # 43
  [NumGt, ~, [40, 41], 8, Boolean], # 44
  [Proj, {index: 0}, [8]], # 45
  [Loop, {bound: each}, [45], 45], # 46
  [Phi, {region: 46}, [42, 67], ~, Unknown], # 47
  [Proj, {index: 1}, [46]], # 48
  [PadAccess, {sigil: "%", symbol: seen}, ~, ~, Unknown], # 49
  [Proj, {index: 0}, [46]], # 50
  [Call, {dispatch_kind: method, name: id, param_names: [], want: scalar}, [47], 50, Unknown], # 51
  [Subscript, {kind: hash}, [49, 51], ~, Scalar], # 52
  [Subscript, {kind: hash}, [49, 51, 51], 51, Scalar], # 53
  [Increment, ~, [53], ~, Scalar], # 54
  [Assign, ~, [52, 54], 53, Scalar], # 55
  [DefinedOr, ~, [53, 29], ~, Scalar], # 56
  [If, ~, [55, 56], 55], # 57
  [Proj, {index: 0}, [57]], # 58
  [Region, {head: 46}, [48, 58]], # 59
  [Assign, ~, [43, 47], 59, Unknown], # 60
  [Phi, {memory: true, region: 46}, [9, 67], ~, Unknown], # 61
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 62
  [Add, ~, [30, 62], ~, Int], # 63
  [Proj, {index: 1}, [57]], # 64
  [Call, {dispatch_kind: method, name: id, param_names: [], want: list}, [47], 64, Unknown], # 65
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [15, 65, 65], 65, Int], # 66
  [Call, {dispatch_kind: method, name: prev, param_names: [], want: scalar}, [47], 66, Unknown], # 67
  [Phi, {memory: true, region: 59}, [61, 55], ~, Unknown], # 68
  [Add, ~, [41, 62], ~, Int], # 69
  [Defined, ~, [47], 46, Boolean]]} # 70
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
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: w}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "."}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 8
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3, 4, 5, 6, 3, 7, 8], 0, Str], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 11
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 5, 3, 7], 9, Str], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [10, 11, 13, 14], 12, Scalar], # 15
  [Return, {implicit: true}, [1], 15]]} # 16
main::f: {start: 0, returns: [44], nodes: [
  [Start], # 0
  [PadAccess, {sigil: "@", symbol: o}, ~, ~, Unknown], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Loop, {bound: each}, [0], 0], # 4
  [Phi, {region: 4}, [3, 53], ~, Int], # 5
  [MemStart], # 6
  [Subscript, {kind: array}, [2, 5, 6], ~, Scalar], # 7
  [Proj, {index: 0}, [4]], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 9
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 10
  [StrEq, ~, [9, 10], ~, Boolean], # 11
  [If, ~, [8, 11], 8], # 12
  [Proj, {index: 1}, [12]], # 13
  [Constant, {const_type: string, value: "."}, ~, ~, Str], # 14
  [StrEq, ~, [9, 14], ~, Boolean], # 15
  [If, ~, [13, 15], 13], # 16
  [Proj, {index: 1}, [16]], # 17
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [1, 7, 6], 17, Int], # 18
  [Proj, {index: 0}, [12]], # 19
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 20
  [Add, ~, [5, 20], ~, Int], # 21
  [Subscript, {kind: array}, [2, 21, 6], ~, Scalar], # 22
  [Coerce, {from_repr: Unknown, to_repr: Str}, [22], ~, Str], # 23
  [Constant, {const_type: string, value: w}, ~, ~, Str], # 24
  [StrEq, ~, [23, 24], ~, Boolean], # 25
  [If, ~, [19, 25], 19], # 26
  [Proj, {index: 0}, [26]], # 27
  [Region, {head: 4}, [18, 27]], # 28
  [Phi, {memory: true, predecessors: [17, 27], region: 28}, [18, 6], ~, Unknown], # 29
  [Proj, {index: 1}, [26]], # 30
  [Loop, {bound: each}, [30], 30], # 31
  [Proj, {index: 1}, [31]], # 32
  [Region, {head: 31}, [32]], # 33
  [Region, {head: 4}, [28, 33]], # 34
  [Phi, {memory: true, region: 34}, [29, 6], ~, Unknown], # 35
  [Proj, {index: 0}, [16]], # 36
  [Region, {head: 4}, [34, 36]], # 37
  [Phi, {memory: true, region: 37}, [35, 6], ~, Unknown], # 38
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [38], ~, Scalar], # 39
  [Coerce, {from_repr: Scalar, to_repr: Str}, [39], ~, Str], # 40
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [40, 1, 38], ~, Str], # 41
  [Proj, {index: 1}, [4]], # 42
  [Region, {head: 4}, [42]], # 43
  [Return, ~, [41], 43], # 44
  [Count, ~, [2, 6], ~, Int], # 45
  [Subtract, ~, [45, 20], ~, Int], # 46
  [NumLe, ~, [5, 46], 4, Boolean], # 47
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 48
  [Add, ~, [5, 48], ~, Int], # 49
  [Phi, {predecessors: [17, 27], region: 28}, [21, 49], ~, Int], # 50
  [Phi, {region: 31}, [21, 55], ~, Int], # 51
  [Phi, {region: 34}, [50, 51], ~, Int], # 52
  [Phi, {region: 37}, [52, 21], ~, Int], # 53
  [NumLe, ~, [51, 46], 31, Boolean], # 54
  [Add, ~, [51, 20], ~, Int], # 55
  [Proj, {index: 0}, [31]]]} # 56
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::bump: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Call, {dispatch_kind: builtin, name: uc, param_names: []}, [4], ~, Str], # 5
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 6
  [Assign, ~, [6, 5], 0, Str], # 7
  [Return, {implicit: true}, [5], 7]]} # 8
main::emit: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Print, ~, [7], 0, Scalar], # 8
  [Return, {implicit: true}, [8], 8]]} # 9
main::f: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Proj, {index: 1}, [2]], # 3
  [Region, {head: 2}, [3]], # 4
  [Loop, {bound: entry}, [4], 4], # 5
  [Proj, {index: 1}, [5]], # 6
  [Region, {head: 5}, [6]], # 7
  [Loop, {bound: entry}, [7], 7], # 8
  [Phi, {region: 8}, [1, 40], ~, Str], # 9
  [Proj, {index: 1}, [8]], # 10
  [Region, {head: 8}, [10]], # 11
  [Return, ~, [9], 11], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 14
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 15
  [ArrayLiteral, ~, [13, 14, 15], ~, Array], # 16
  [MemStart], # 17
  [PostfixDeref, {sigil: "@"}, [16, 17], ~, Array], # 18
  [Phi, {memory: true, region: 2}, [17, 19], ~, Unknown], # 19
  [Count, ~, [18, 19], ~, Int], # 20
  [Phi, {region: 2}, [13, 42], ~, Int], # 21
  [NumGt, ~, [20, 21], 2, Boolean], # 22
  [Proj, {index: 0}, [2]], # 23
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 24
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 25
  [ArrayLiteral, {sigil: "@", symbol: u}, [24, 25], ~, Array], # 26
  [Phi, {region: 8}, [13, 58], ~, Int], # 27
  [Phi, {memory: true, region: 4}, [19], ~, Unknown], # 28
  [Phi, {memory: true, region: 5}, [28, 73], ~, Unknown], # 29
  [Phi, {memory: true, region: 7}, [29], ~, Unknown], # 30
  [Phi, {memory: true, region: 8}, [30, 36], ~, Unknown], # 31
  [Subscript, {kind: array}, [26, 27, 31], ~, Str], # 32
  [Concat, ~, [9, 32], ~, Str], # 33
  [Subscript, {kind: array}, [26, 27], ~, Scalar], # 34
  [Proj, {index: 0}, [8]], # 35
  [Call, {dispatch_kind: direct, name: main::bump, param_names: [], want: void}, [34], 35, Str], # 36
  [Subscript, {kind: array}, [26, 27, 36], ~, Str], # 37
  [Concat, ~, [33, 37], ~, Str], # 38
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 39
  [Concat, ~, [38, 39], ~, Str], # 40
  [Phi, {memory: true, region: 11}, [31], ~, Unknown], # 41
  [Add, ~, [21, 14], ~, Int], # 42
  [Subscript, {kind: array}, [18, 21, 19], ~, Scalar], # 43
  [Count, ~, [26, 30], ~, Int], # 44
  [Subtract, ~, [44, 14], ~, Int], # 45
  [Add, ~, [45, 14], ~, Int], # 46
  [NumGt, ~, [46, 27], 8, Boolean], # 47
  [Count, ~, [18, 17], ~, Int], # 48
  [Phi, {region: 5}, [13, 59], ~, Int], # 49
  [Coerce, {from_repr: Unknown, to_repr: Str}, [43], ~, Str], # 50
  [ArrayLiteral, ~, ~, ~, Array], # 51
  [Phi, {region: 2}, [51, 74], ~, Array], # 52
  [Count, ~, [52, 28], ~, Int], # 53
  [Subtract, ~, [53, 14], ~, Int], # 54
  [Add, ~, [54, 14], ~, Int], # 55
  [NumGt, ~, [55, 49], 5, Boolean], # 56
  [Proj, {index: 0}, [5]], # 57
  [Add, ~, [27, 14], ~, Int], # 58
  [Add, ~, [49, 14], ~, Int], # 59
  [Count, ~, [52, 29], ~, Int], # 60
  [Subtract, ~, [60, 14], ~, Int], # 61
  [NumLt, ~, [49, 61], ~, Boolean], # 62
  [Subscript, {kind: array}, [52, 49], ~, Scalar], # 63
  [Constant, {const_type: string, value: L}, ~, ~, Str], # 64
  [Concat, ~, [64, 50], ~, Str], # 65
  [Constant, {const_type: string, value: "br "}, ~, ~, Str], # 66
  [Subscript, {kind: array}, [52, 59, 29], ~, Scalar], # 67
  [Constant, {const_type: string, value: undef}, ~, ~, Str], # 68
  [TernaryExpr, ~, [62, 67, 68], ~, Unknown], # 69
  [Coerce, {from_repr: Unknown, to_repr: Str}, [69], ~, Str], # 70
  [Concat, ~, [66, 70], ~, Str], # 71
  [Call, {dispatch_kind: direct, name: main::emit, param_names: [], want: void}, [63], 57, Scalar], # 72
  [Call, {dispatch_kind: direct, name: main::emit, param_names: [], want: void}, [71], 72, Scalar], # 73
  [ListAppend, {collector: map}, [52, 65], ~, Array]]} # 74
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
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [2], ~, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [ArrayLiteral, ~, ~, ~, Array], # 5
  [Loop, {bound: entry}, [0], 0], # 6
  [Phi, {region: 6}, [5, 52], ~, Array], # 7
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [4, 7, 2], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [ArrayLiteral, ~, ~, ~, Array], # 11
  [Proj, {index: 1}, [6]], # 12
  [Region, {head: 6}, [12]], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Phi, {region: 14}, [11, 51], ~, Array], # 15
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [4, 15, 2], ~, Str], # 16
  [Concat, ~, [10, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Proj, {index: 1}, [14]], # 20
  [Region, {head: 14}, [20]], # 21
  [Print, ~, [19], 21, Scalar], # 22
  [Return, {implicit: true}, [1], 22], # 23
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 24
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 25
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 26
  [ArrayLiteral, ~, [24, 25, 26], ~, Array], # 27
  [PostfixDeref, {sigil: "@"}, [27, 2], ~, Array], # 28
  [Count, ~, [28, 2], ~, Int], # 29
  [Phi, {region: 6}, [24, 33], ~, Int], # 30
  [NumGt, ~, [29, 30], 6, Boolean], # 31
  [Proj, {index: 0}, [6]], # 32
  [Add, ~, [30, 25], ~, Int], # 33
  [Subscript, {kind: array}, [28, 30, 2], ~, Scalar], # 34
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 35
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 36
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 37
  [ArrayLiteral, ~, [35, 36, 37], ~, Array], # 38
  [PostfixDeref, {sigil: "@"}, [38, 2], ~, Array], # 39
  [Count, ~, [39, 2], ~, Int], # 40
  [Phi, {region: 14}, [24, 48], ~, Int], # 41
  [Subscript, {kind: array}, [39, 41, 2], ~, Scalar], # 42
  [Coerce, {from_repr: Unknown, to_repr: Str}, [34], ~, Str], # 43
  [NumGt, ~, [40, 41], 14, Boolean], # 44
  [Proj, {index: 0}, [14]], # 45
  [Coerce, {from_repr: Scalar, to_repr: Num}, [42], ~, Num], # 46
  [Multiply, ~, [46, 26], ~, Num], # 47
  [Add, ~, [41, 25], ~, Int], # 48
  [Constant, {const_type: string, value: L}, ~, ~, Str], # 49
  [Concat, ~, [49, 43], ~, Str], # 50
  [ListAppend, {collector: map}, [15, 47], ~, Array], # 51
  [ListAppend, {collector: map}, [7, 50], ~, Array]]} # 52
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
C::f: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 32], ~, Unknown], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Return, ~, [3], 5], # 6
  [PadAccess, {sigil: "@", symbol: r}, ~, ~, Scalar], # 7
  [MemStart], # 8
  [Count, ~, [7, 8], ~, Int], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Subtract, ~, [9, 10], ~, Int], # 11
  [Add, ~, [11, 10], ~, Int], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [Phi, {region: 2}, [13, 34], ~, Int], # 14
  [NumGt, ~, [12, 14], 2, Boolean], # 15
  [Proj, {index: 0}, [2]], # 16
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 17
  [Phi, {memory: true, region: 2}, [8, 35], ~, Unknown], # 18
  [PadAccess, {sigil: $, symbol: repr}, [18], ~, Unknown], # 19
  [Subscript, {kind: array}, [7, 14, 18], ~, Scalar], # 20
  [Assign, ~, [19, 20], 16, Scalar], # 21
  [PadAccess, {sigil: $, symbol: repr}, [21], ~, Str], # 22
  [Coerce, {from_repr: Unknown, to_repr: Str}, [22], ~, Str], # 23
  [PadAccess, {sigil: $, symbol: to}, ~, ~, Str], # 24
  [Coerce, {from_repr: Unknown, to_repr: Str}, [24], ~, Str], # 25
  [StrNe, ~, [23, 25], ~, Boolean], # 26
  [If, ~, [21, 26], 21], # 27
  [Proj, {index: 0}, [27]], # 28
  [Call, {class_name: C, dispatch_kind: method, name: g, param_names: [], want: scalar}, [17, 22], 28, Unknown], # 29
  [Proj, {index: 1}, [27]], # 30
  [Region, {head: 27}, [29, 30]], # 31
  [Phi, {predecessors: [28, 30], region: 31}, [29, 3], ~, Unknown], # 32
  [Phi, {memory: true, region: 5}, [18], ~, Unknown], # 33
  [Add, ~, [14, 10], ~, Int], # 34
  [Phi, {memory: true, predecessors: [28, 30], region: 31}, [29, 21], ~, Unknown], # 35
  [ArgsSource, ~, ~, ~, Array], # 36
  [Assign, {targets: 3}, [17, 24, 7, 36], ~, List]]} # 37
C::g: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: g}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Return, {implicit: true}, [7], 0]]} # 8
C::new: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [HashLiteral, ~, ~, 0, HashRef], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [2, 3], 1, Scalar], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [1, 4, 4], ~, Unknown], # 5
  [Return, {implicit: true}, [5], 4]]} # 6
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: C, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 0, Object], # 2
  [Constant, {const_type: string, value: Str}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: Int}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: Num}, ~, ~, Str], # 5
  [Call, {class_name: C, dispatch_kind: method, name: f, param_names: [], want: list}, [2, 3, 4, 5, 3], 2, Unknown], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
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
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Return, {implicit: true}, [7], 0]]} # 8
B::f: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Call, {dispatch_kind: direct, name: B::rr, param_names: []}, [3], 0, Unknown], # 4
  [Return, ~, [4], 4]]} # 5
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 2
  [EntryDef, {package: main, sigil: "&", symbol: rr}, ~, ~, Unknown], # 3
  [Constant, {const_type: code, value: A::rr}, ~, ~, Code], # 4
  [Ref, ~, [4], ~, CodeRef], # 5
  [EntryDef, {package: B, sigil: "&", symbol: rr}, ~, ~, Unknown], # 6
  [MemStart], # 7
  [PackageMark, {package: B}, ~, 0], # 8
  [EntryWrite, {binds: true}, [6, 5, 7], 8, Unknown], # 9
  [PackageMark, {package: main}, ~, 9], # 10
  [EntryWrite, {binds: true}, [3, 5, 9], 10, Unknown], # 11
  [Call, {dispatch_kind: direct, name: B::f, param_names: [], want: list}, [2], 11, Unknown], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 14
  [Call, {dispatch_kind: direct, name: main::rr, param_names: [], want: list}, [14], 12, Unknown], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [13, 16, 17], 15, Scalar], # 18
  [Return, {implicit: true}, [1], 18]]} # 19
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
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 2
  [Constant, {const_type: string, value: "package Other; sub g { \"g$_[0]\" } 1"}, ~, ~, Str], # 3
  [Coerce, {from_repr: Str, to_repr: Code}, [3], 0, Code], # 4
  [Region, ~, [4]], # 5
  [Phi, {region: 5}, [4, 1], ~, Unknown], # 6
  [If, ~, [5, 6], 5], # 7
  [Proj, {index: 0}, [7]], # 8
  [Proj, {index: 1}, [7]], # 9
  [Unwind, ~, ~, 9], # 10
  [Region, {head: 7}, [8, 10]], # 11
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 11, Unknown], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [13, 14], 12, Scalar], # 15
  [Return, {implicit: true}, [1], 15]]} # 16
main::f: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Call, {dispatch_kind: direct, name: Other::g, param_names: []}, [3], 0, Unknown], # 4
  [Return, ~, [4], 4]]} # 5
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
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [ArrayLiteral, ~, [3, 4], 0, ArrayRef], # 5
  [HashLiteral, ~, [2, 5], 5, HashRef], # 6
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [6, 3], 6, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [HashLiteral, ~, ~, 7, HashRef], # 9
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [9, 3], 9, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 12
  [ArrayLiteral, ~, [12], 10, ArrayRef], # 13
  [HashLiteral, ~, [2, 13], 13, HashRef], # 14
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 15
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [14, 15], 14, Str], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [8, 11, 17, 18], 16, Scalar], # 19
  [Return, {implicit: true}, [1], 19]]} # 20
main::f: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: e}, ~, ~, Unknown], # 2
  [If, ~, [0, 2], 0], # 3
  [Proj, {index: 0}, [3]], # 4
  [PadAccess, {sigil: $, symbol: r}, ~, ~, Unknown], # 5
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 6
  [MemStart], # 7
  [Subscript, {kind: hash}, [5, 6, 7], ~, Scalar], # 8
  [Defined, ~, [8], ~, Boolean], # 9
  [If, ~, [4, 9], 4], # 10
  [Proj, {index: 0}, [10]], # 11
  [Proj, {index: 1}, [10]], # 12
  [ArrayLiteral, ~, ~, 12, ArrayRef], # 13
  [Region, {head: 10}, [11, 13]], # 14
  [Proj, {index: 1}, [3]], # 15
  [Region, {head: 3}, [14, 15]], # 16
  [Loop, {bound: entry}, [16], 16], # 17
  [Phi, {region: 17}, [1, 31], ~, Str], # 18
  [Proj, {index: 1}, [17]], # 19
  [Region, {head: 17}, [19]], # 20
  [Return, ~, [18], 20], # 21
  [Phi, {predecessors: [11, 12], region: 14}, [8, 13], ~, Scalar], # 22
  [PostfixDeref, {sigil: "@"}, [22, 7], ~, Array], # 23
  [ArrayLiteral, ~, ~, ~, List], # 24
  [Phi, {predecessors: [4, 15], region: 16}, [23, 24], ~, List], # 25
  [ArrayLiteral, ~, [25], ~, Array], # 26
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 27
  [Phi, {region: 17}, [27, 38], ~, Int], # 28
  [Subscript, {kind: array}, [26, 28, 7], ~, Scalar], # 29
  [Coerce, {from_repr: Unknown, to_repr: Str}, [29], ~, Str], # 30
  [Concat, ~, [18, 30], ~, Str], # 31
  [ArgsSource, ~, ~, ~, Array], # 32
  [Assign, {targets: 2}, [5, 2, 32], ~, List], # 33
  [Count, ~, [26, 7], ~, Int], # 34
  [NumGt, ~, [34, 28], 17, Boolean], # 35
  [Proj, {index: 0}, [17]], # 36
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 37
  [Add, ~, [28, 37], ~, Int]]} # 38
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
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [HashLiteral, ~, [1, 5], 0, HashRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Subscript, {kind: array}, [2, 7, 4], ~, Scalar], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [6, 8, 4], ~, Unknown], # 9
  [Return, {implicit: true}, [9], 6]]} # 10
N::val: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: v}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 3
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [2, 3], 0, Object], # 4
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [4], 4, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [2, 1], 5, Object], # 7
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [7], 7, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, [11], 8, Str], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 14
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, [14], 12, Str], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [6, 9, 10, 13, 10, 16, 17], 15, Scalar], # 18
  [Return, {implicit: true}, [1], 18]]} # 19
main::f: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "v="}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 2
  [Call, {dispatch_kind: method, name: val, param_names: [], want: scalar}, [2], 0, Unknown], # 3
  [PadAccess, {sigil: $, symbol: v}, [3], ~, Unknown], # 4
  [Assign, ~, [4, 3], 3, Unknown], # 5
  [PadAccess, {sigil: $, symbol: v}, [5], ~, Unknown], # 6
  [Defined, ~, [6], ~, Boolean], # 7
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 8
  [TernaryExpr, ~, [7, 6, 8], ~, Unknown], # 9
  [Ref, ~, [9], ~, Unknown], # 10
  [PostfixDeref, {sigil: $}, [10, 5], ~, Scalar], # 11
  [Coerce, {from_repr: Scalar, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [1, 12], ~, Str], # 13
  [Return, ~, [13], 5], # 14
  [ArgsSource, ~, ~, ~, Array], # 15
  [Assign, {targets: 1}, [2, 15], ~, List]]} # 16
main::g: {start: 0, returns: [51], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: v}, [1], ~, Unknown], # 2
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 3
  [Assign, ~, [2, 3], 0, Int], # 4
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 5
  [PadAccess, {sigil: $, symbol: v}, [4], ~, Unknown], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [TernaryExpr, ~, [5, 6, 7], ~, Unknown], # 8
  [Ref, ~, [8], ~, Unknown], # 9
  [PostfixDeref, {sigil: $}, [9], ~, Scalar], # 10
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 11
  [If, ~, [4, 5], 4], # 12
  [Proj, {index: 0}, [12]], # 13
  [Assign, ~, [10, 11], 13, Int], # 14
  [Proj, {index: 1}, [12]], # 15
  [Region, {head: 12}, [15, 14]], # 16
  [Phi, {memory: true, predecessors: [15, 13], region: 16}, [4, 14], ~, Int], # 17
  [PadAccess, {sigil: $, symbol: s}, [17], ~, Unknown], # 18
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 19
  [Assign, ~, [18, 19], 16, Int], # 20
  [PadAccess, {sigil: $, symbol: t}, [20], ~, Unknown], # 21
  [Constant, {const_type: integer, value: "6"}, ~, ~, Int], # 22
  [Assign, ~, [21, 22], 20, Int], # 23
  [PadAccess, {sigil: $, symbol: s}, [23], ~, Unknown], # 24
  [PadAccess, {sigil: $, symbol: t}, [23], ~, Unknown], # 25
  [ArrayLiteral, ~, [24, 25], ~, Array], # 26
  [ArrayLiteral, ~, ~, ~, Array], # 27
  [TernaryExpr, ~, [5, 26, 27], ~, Array], # 28
  [Ref, ~, [28], ~, ArrayRef], # 29
  [ArrayLiteral, {sigil: "@", symbol: r}, [29], ~, Array], # 30
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 31
  [Subscript, {kind: array}, [30, 31], ~, Undef], # 32
  [PostfixDeref, {sigil: $}, [32], ~, Scalar], # 33
  [If, ~, [23, 5], 23], # 34
  [Proj, {index: 0}, [34]], # 35
  [Assign, ~, [33, 7], 35, Int], # 36
  [Proj, {index: 1}, [34]], # 37
  [Region, {head: 34}, [37, 36]], # 38
  [Phi, {memory: true, predecessors: [37, 35], region: 38}, [23, 36], ~, Int], # 39
  [PadAccess, {sigil: $, symbol: v}, [39], ~, Str], # 40
  [Coerce, {from_repr: Unknown, to_repr: Str}, [40], ~, Str], # 41
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 42
  [Concat, ~, [41, 42], ~, Str], # 43
  [PadAccess, {sigil: $, symbol: s}, [39], ~, Str], # 44
  [Coerce, {from_repr: Unknown, to_repr: Str}, [44], ~, Str], # 45
  [Concat, ~, [43, 45], ~, Str], # 46
  [Concat, ~, [46, 42], ~, Str], # 47
  [PadAccess, {sigil: $, symbol: t}, [39], ~, Str], # 48
  [Coerce, {from_repr: Unknown, to_repr: Str}, [48], ~, Str], # 49
  [Concat, ~, [47, 49], ~, Str], # 50
  [Return, ~, [50], 38], # 51
  [ArgsSource, ~, ~, ~, Array], # 52
  [Assign, {targets: 1}, [5, 52], ~, List]]} # 53
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
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: in}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 5
  [ArrayLiteral, ~, [3, 4, 5], 0, ArrayRef], # 6
  [HashLiteral, ~, [2, 6], 6, HashRef], # 7
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [7], 7, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 10
  [HashLiteral, ~, ~, 8, HashRef], # 11
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [11], 11, Str], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [9, 10, 13, 14], 12, Scalar], # 15
  [Return, {implicit: true}, [1], 15]]} # 16
main::f: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [1], ~, Scalar], # 2
  [Coerce, {from_repr: Scalar, to_repr: Str}, [2], ~, Str], # 3
  [ArrayLiteral, ~, ~, ~, Array], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 6
  [Constant, {const_type: string, value: in}, ~, ~, Str], # 7
  [Subscript, {kind: hash}, [6, 7, 1], ~, Scalar], # 8
  [Defined, ~, [8], ~, Boolean], # 9
  [If, ~, [0, 9], 0], # 10
  [Proj, {index: 1}, [10]], # 11
  [ArrayLiteral, ~, ~, 11, ArrayRef], # 12
  [DefinedOr, ~, [8, 12], ~, Scalar], # 13
  [PostfixDeref, {sigil: "@"}, [13, 1], ~, Array], # 14
  [Count, ~, [14, 1], ~, Int], # 15
  [Subtract, ~, [15, 5], ~, Int], # 16
  [Range, ~, [5, 16], ~, List], # 17
  [Slice, {kind: array}, [17, 13], ~, List], # 18
  [Proj, {index: 0}, [10]], # 19
  [Region, {head: 10}, [19, 12]], # 20
  [ArrayLiteral, ~, [18], 20, ArrayRef], # 21
  [Loop, {bound: entry}, [21], 21], # 22
  [Phi, {region: 22}, [4, 33], ~, Array], # 23
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [3, 23, 1], ~, Str], # 24
  [Proj, {index: 1}, [22]], # 25
  [Region, {head: 22}, [25]], # 26
  [Return, ~, [24], 26], # 27
  [PostfixDeref, {sigil: "@"}, [21, 1], ~, Array], # 28
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 29
  [Phi, {region: 22}, [29, 39], ~, Int], # 30
  [Subscript, {kind: array}, [28, 30, 1], ~, Scalar], # 31
  [Defined, ~, [31], ~, Boolean], # 32
  [ListAppend, {collector: grep}, [23, 31, 32], ~, Array], # 33
  [Count, ~, [28, 1], ~, Int], # 34
  [NumGt, ~, [34, 30], 22, Boolean], # 35
  [Proj, {index: 0}, [22]], # 36
  [ArgsSource, ~, ~, ~, Array], # 37
  [Assign, {targets: 1}, [6, 37], ~, List], # 38
  [Add, ~, [30, 5], ~, Int]]} # 39
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
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: yy}, ~, ~, Str], # 3
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3], 0, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, Scalar], # 7
  [Return, {implicit: true}, [1], 7]]} # 8
main::f: {start: 0, returns: [38], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: a}, [1], ~, Unknown], # 2
  [PadAccess, {sigil: $, symbol: b}, [1], ~, Unknown], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Assign, {targets: 2}, [2, 3, 4], 0, List], # 5
  [PadAccess, {sigil: $, symbol: a}, [5], ~, Unknown], # 6
  [Call, {dispatch_kind: direct, name: main::p, param_names: [], want: list}, [6], 5, List], # 7
  [PadAccess, {sigil: $, symbol: b}, [7], ~, Unknown], # 8
  [Call, {dispatch_kind: direct, name: main::p, param_names: [], want: list}, [8], 7, List], # 9
  [PadAccess, {sigil: $, symbol: a}, [9], ~, Unknown], # 10
  [PadAccess, {sigil: $, symbol: b}, [9], ~, Unknown], # 11
  [PadAccess, {sigil: $, symbol: ap}, ~, ~, Unknown], # 12
  [PadAccess, {sigil: $, symbol: bp}, ~, ~, Unknown], # 13
  [Assign, {targets: 2}, [10, 11, 12, 13], 9, List], # 14
  [PadAccess, {sigil: $, symbol: a}, [14], ~, Str], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [PadAccess, {sigil: $, symbol: b}, [14], ~, Str], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 20
  [Concat, ~, [18, 20], ~, Str], # 21
  [Concat, ~, [21, 17], ~, Str], # 22
  [PadAccess, {sigil: $, symbol: al}, ~, ~, Unknown], # 23
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 24
  [DefinedOr, ~, [23, 24], ~, Unknown], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 26
  [Concat, ~, [22, 26], ~, Str], # 27
  [Defined, ~, [23], ~, Boolean], # 28
  [If, ~, [14, 28], 14], # 29
  [Proj, {index: 0}, [29]], # 30
  [Constant, {const_type: string, value: "no ("}, ~, ~, Str], # 31
  [Concat, ~, [31, 16], ~, Str], # 32
  [Constant, {const_type: string, value: ")"}, ~, ~, Str], # 33
  [Concat, ~, [32, 33], ~, Str], # 34
  [Proj, {index: 1}, [29]], # 35
  [Unwind, ~, [34], 35], # 36
  [Region, {head: 29}, [30, 36]], # 37
  [Return, ~, [27], 37], # 38
  [Assign, {targets: 2}, [12, 23, 7], ~, List], # 39
  [PadAccess, {sigil: $, symbol: bl}, ~, ~, Unknown], # 40
  [Assign, {targets: 2}, [13, 40, 9], ~, List]]} # 41
main::p: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: p}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [5], ~, Str], # 8
  [Length, ~, [8], ~, Int], # 9
  [ArrayLiteral, ~, [7, 9], ~, List], # 10
  [Coerce, {from_repr: List, to_repr: Scalar}, [9], ~, Scalar], # 11
  [Return, {implicit: true}, [10, 11], 0]]} # 12
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
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
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
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3, 6, 10], 10, Str], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [12, 13], 11, Scalar], # 14
  [Return, {implicit: true}, [1], 14]]} # 15
main::f: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 77], ~, Unknown], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [MemStart], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [7], ~, Scalar], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [PadAccess, {sigil: "@", symbol: params}, ~, ~, Unknown], # 10
  [Phi, {region: 2}, [10, 80], ~, Unknown], # 11
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [9, 11], ~, Str], # 12
  [Concat, ~, [6, 12], ~, Str], # 13
  [Concat, ~, [13, 5], ~, Str], # 14
  [PadAccess, {sigil: "@", symbol: body}, ~, ~, Unknown], # 15
  [Phi, {region: 2}, [15, 73], ~, Unknown], # 16
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [9, 16], ~, Str], # 17
  [Concat, ~, [14, 17], ~, Str], # 18
  [Proj, {index: 1}, [2]], # 19
  [Region, {head: 2}, [19]], # 20
  [Return, ~, [18], 20], # 21
  [ArgsSource, ~, ~, ~, Array], # 22
  [Count, ~, [22, 7], ~, Int], # 23
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 24
  [Phi, {region: 2}, [24, 30], ~, Int], # 25
  [NumGt, ~, [23, 25], 2, Boolean], # 26
  [Proj, {index: 0}, [2]], # 27
  [Exists, {kind: array}, [22, 25, 7], 27, Boolean], # 28
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 29
  [Add, ~, [25, 29], ~, Int], # 30
  [Subscript, {kind: array}, [22, 25], ~, Scalar], # 31
  [Subscript, {kind: array}, [22, 25, 7], ~, Scalar], # 32
  [Subscript, {kind: array}, [22, 25, 7], ~, Scalar], # 33
  [Subscript, {kind: array}, [22, 25, 7], ~, Scalar], # 34
  [Subscript, {kind: array}, [22, 25, 7], ~, Scalar], # 35
  [Subscript, {kind: array}, [22, 25, 7], ~, Scalar], # 36
  [Subscript, {kind: array}, [22, 25, 7], ~, Scalar], # 37
  [Ref, ~, [31], ~, ScalarRef], # 38
  [TernaryExpr, ~, [28, 38, 1], 28, Scalar], # 39
  [PostfixDeref, {sigil: $}, [39, 7], ~, Scalar], # 40
  [TernaryExpr, ~, [28, 40, 32], 39, Scalar], # 41
  [PostfixDeref, {sigil: $}, [39, 7], ~, Scalar], # 42
  [TernaryExpr, ~, [28, 42, 33], ~, Scalar], # 43
  [PostfixDeref, {sigil: $}, [39, 7], ~, Scalar], # 44
  [TernaryExpr, ~, [28, 44, 34], ~, Scalar], # 45
  [PostfixDeref, {sigil: $}, [39, 7], ~, Scalar], # 46
  [TernaryExpr, ~, [28, 46, 35], ~, Scalar], # 47
  [PostfixDeref, {sigil: $}, [39, 7], ~, Scalar], # 48
  [TernaryExpr, ~, [28, 48, 36], ~, Scalar], # 49
  [PostfixDeref, {sigil: $}, [39, 7], ~, Scalar], # 50
  [TernaryExpr, ~, [28, 50, 37], ~, Scalar], # 51
  [RefType, ~, [43], ~, Str], # 52
  [Constant, {const_type: string, value: ARRAY}, ~, ~, Str], # 53
  [StrEq, ~, [52, 53], ~, Boolean], # 54
  [Count, ~, [11, 7], ~, Int], # 55
  [PostfixDeref, {sigil: "@"}, [47, 7], ~, Array], # 56
  [TernaryExpr, ~, [55, 56, 16], ~, Array], # 57
  [TernaryExpr, ~, [54, 57, 16], ~, Array], # 58
  [RefType, ~, [41], ~, Str], # 59
  [Not, ~, [59], ~, Boolean], # 60
  [If, ~, [41, 60], 41], # 61
  [Proj, {index: 0}, [61]], # 62
  [Coerce, {from_repr: Scalar, to_repr: Str}, [49], ~, Str], # 63
  [Constant, {const_type: string, value: sub}, ~, ~, Str], # 64
  [StrEq, ~, [63, 64], ~, Boolean], # 65
  [If, ~, [62, 65], 62], # 66
  [Proj, {index: 1}, [66]], # 67
  [Proj, {index: 1}, [61]], # 68
  [Region, {head: 61}, [67, 68]], # 69
  [Phi, {predecessors: [62, 68], region: 69}, [16, 58], ~, Array], # 70
  [Proj, {index: 0}, [66]], # 71
  [Region, {head: 2}, [69, 71]], # 72
  [Phi, {predecessors: [27, 71], region: 72}, [70, 16], ~, Array], # 73
  [PostfixDeref, {sigil: "@"}, [45, 7], ~, Array], # 74
  [Phi, {predecessors: [62, 68], region: 69}, [51, 3], ~, Unknown], # 75
  [TernaryExpr, ~, [55, 11, 74], ~, Array], # 76
  [Phi, {predecessors: [27, 71], region: 72}, [75, 3], ~, Unknown], # 77
  [TernaryExpr, ~, [54, 76, 11], ~, Array], # 78
  [Phi, {predecessors: [62, 68], region: 69}, [11, 78], ~, Array], # 79
  [Phi, {predecessors: [27, 71], region: 72}, [79, 11], ~, Array]]} # 80
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
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3, 4], 0, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [8, 3], 5, Str], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [6, 7, 10, 11], 9, Scalar], # 12
  [Return, {implicit: true}, [1], 12]]} # 13
main::f: {start: 0, returns: [34], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [ArrayLiteral, {sigil: "@", symbol: l}, [1], ~, Array], # 2
  [PadAccess, {sigil: "@", symbol: x}, ~, ~, Unknown], # 3
  [PadAccess, {sigil: "@", symbol: "n"}, ~, ~, Unknown], # 4
  [MemStart], # 5
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 6
  [If, ~, [0, 6], 0], # 7
  [Proj, {index: 0}, [7]], # 8
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [5], ~, Scalar], # 9
  [Coerce, {from_repr: Scalar, to_repr: Str}, [9], ~, Str], # 10
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [10, 1], ~, Str], # 11
  [RegexMatch, {flags: "", pattern: "1"}, [11], ~, Boolean], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [10, 4, 5], ~, Str], # 13
  [RegexMatch, {flags: "", pattern: "2"}, [13], ~, Boolean], # 14
  [And, ~, [12, 14], ~, Boolean], # 15
  [If, ~, [8, 15], 8], # 16
  [Proj, {index: 0}, [16]], # 17
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [3, 4, 5], 17, Int], # 18
  [ArrayLiteral, {rebinds: true, sigil: "@", symbol: l}, [3], 18, Array], # 19
  [Proj, {index: 1}, [16]], # 20
  [Region, {head: 16}, [20, 19]], # 21
  [Phi, {predecessors: [20, 17], region: 21}, [2, 19], ~, Array], # 22
  [Proj, {index: 1}, [7]], # 23
  [Region, {head: 7}, [23, 21]], # 24
  [Phi, {predecessors: [23, 8], region: 24}, [2, 22], ~, Array], # 25
  [Constant, {const_type: string, value: "}"}, ~, ~, Str], # 26
  [Phi, {memory: true, predecessors: [20, 17], region: 21}, [5, 18], ~, Unknown], # 27
  [Phi, {memory: true, predecessors: [23, 8], region: 24}, [5, 27], ~, Unknown], # 28
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [25, 26, 28], 24, Int], # 29
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [29], ~, Scalar], # 30
  [Coerce, {from_repr: Scalar, to_repr: Str}, [30], ~, Str], # 31
  [PostfixDeref, {sigil: "@"}, [25, 29], ~, Array], # 32
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [31, 32, 29], ~, Str], # 33
  [Return, ~, [33], 29], # 34
  [ArgsSource, ~, ~, ~, Array], # 35
  [Assign, {targets: 2}, [6, 4, 35], ~, List]]} # 36
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
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
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
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [15], 15, Str], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [17, 18], 16, Scalar], # 19
  [Return, {implicit: true}, [1], 19]]} # 20
main::f: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {memory: true, region: 2}, [1, 61], ~, Unknown], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Phi, {memory: true, region: 5}, [3], ~, Unknown], # 6
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [7], ~, Str], # 8
  [PadAccess, {sigil: "@", symbol: lines}, ~, ~, Unknown], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [8, 9, 6], ~, Str], # 10
  [Return, ~, [10], 5], # 11
  [PadAccess, {sigil: $, symbol: registry}, ~, ~, Unknown], # 12
  [PostfixDeref, {sigil: "%"}, [12, 1], ~, Hash], # 13
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [13, 1], ~, List], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [14, 1], ~, List], # 15
  [ArrayLiteral, ~, [15], ~, Array], # 16
  [Count, ~, [16, 3], ~, Int], # 17
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 18
  [Phi, {region: 2}, [18, 56], ~, Int], # 19
  [NumGt, ~, [17, 19], 2, Boolean], # 20
  [Proj, {index: 0}, [2]], # 21
  [Subscript, {kind: array}, [16, 19], ~, Scalar], # 22
  [Ref, ~, [22], 21, ScalarRef], # 23
  [PostfixDeref, {sigil: $}, [23, 3], 23, Scalar], # 24
  [Subscript, {kind: hash}, [12, 24, 3], ~, Scalar], # 25
  [Constant, {const_type: string, value: fields}, ~, ~, Str], # 26
  [Subscript, {kind: hash}, [25, 26, 3], ~, Scalar], # 27
  [Defined, ~, [27], ~, Boolean], # 28
  [If, ~, [24, 28], 24], # 29
  [Proj, {index: 1}, [29]], # 30
  [ArrayLiteral, ~, ~, 30, ArrayRef], # 31
  [Proj, {index: 0}, [29]], # 32
  [Region, {head: 29}, [32, 31]], # 33
  [Phi, {predecessors: [32, 30], region: 33}, [27, 31], ~, Scalar], # 34
  [PostfixDeref, {sigil: "@"}, [34, 3], ~, Array], # 35
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp_body: main::f::__SORTCMP__:1, sort_package: main, want: list}, [35, 3], 33, List], # 36
  [PostfixDeref, {sigil: $}, [23, 36], ~, Scalar], # 37
  [Coerce, {from_repr: Scalar, to_repr: Str}, [37], ~, Str], # 38
  [Constant, {const_type: string, value: ":"}, ~, ~, Str], # 39
  [Concat, ~, [38, 39], ~, Str], # 40
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 41
  [ArrayLiteral, ~, ~, ~, Array], # 42
  [Constant, {const_type: string, value: is_class}, ~, ~, Str], # 43
  [Subscript, {kind: hash}, [25, 43, 3], ~, Scalar], # 44
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 45
  [TernaryExpr, ~, [44, 45, 18], ~, Int], # 46
  [If, ~, [36, 46], 36], # 47
  [Proj, {index: 0}, [47]], # 48
  [Loop, {bound: entry}, [48], 48], # 49
  [Phi, {region: 49}, [42, 70], ~, Array], # 50
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [41, 50, 36], ~, Str], # 51
  [Concat, ~, [40, 51], ~, Str], # 52
  [Proj, {index: 1}, [49]], # 53
  [Region, {head: 49}, [53]], # 54
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [9, 52, 36], 54, Int], # 55
  [Add, ~, [19, 45], ~, Int], # 56
  [Subscript, {kind: array}, [16, 19, 3], ~, Scalar], # 57
  [Subscript, {kind: array}, [16, 19, 36], ~, Scalar], # 58
  [Proj, {index: 1}, [47]], # 59
  [Region, {head: 47}, [55, 59]], # 60
  [Phi, {memory: true, predecessors: [48, 59], region: 60}, [55, 36], ~, List], # 61
  [Count, ~, [16, 1], ~, Int], # 62
  [Phi, {region: 49}, [18, 68], ~, Int], # 63
  [Count, ~, [36, 36], ~, Int], # 64
  [Subscript, {kind: array}, [36, 63, 36], ~, Scalar], # 65
  [Constant, {const_type: string, value: i}, ~, ~, Str], # 66
  [Subscript, {kind: hash}, [65, 66, 36], ~, Scalar], # 67
  [Add, ~, [63, 45], ~, Int], # 68
  [NumGt, ~, [64, 63], 49, Boolean], # 69
  [ListAppend, {collector: map}, [50, 67], ~, Array], # 70
  [ArgsSource, ~, ~, ~, Array], # 71
  [Assign, {targets: 1}, [12, 71], ~, List], # 72
  [Proj, {index: 0}, [49]]]} # 73
main::f::__SORTCMP__:1: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [MemStart], # 1
  [EntryDef, {package: main, sigil: $, symbol: a}, [1], ~, Scalar], # 2
  [Constant, {const_type: string, value: i}, ~, ~, Str], # 3
  [Subscript, {kind: hash}, [2, 3, 1], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [EntryDef, {package: main, sigil: $, symbol: b}, [1], ~, Scalar], # 6
  [Subscript, {kind: hash}, [6, 3, 1], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Num}, [7], ~, Num], # 8
  [NumCmp, ~, [5, 8], ~, Int], # 9
  [Return, {implicit: true}, [9], 0]]} # 10
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
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 3], 0, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [3, 2], 4, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2, 2], 6, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [3, 3], 8, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [5, 7, 9, 11, 12], 10, Scalar], # 13
  [Return, {implicit: true}, [1], 13]]} # 14
main::f: {start: 0, returns: [37], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: lines}, ~, ~, Scalar], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [2, 3, 4, 5], 0, Int], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Subscript, {kind: array}, [7, 8, 6], ~, Scalar], # 9
  [If, ~, [6, 9], 6], # 10
  [Proj, {index: 1}, [10]], # 11
  [PadAccess, {sigil: "@", symbol: "n"}, ~, ~, Unknown], # 12
  [Proj, {index: 0}, [10]], # 13
  [Loop, {bound: entry}, [13], 13], # 14
  [Proj, {index: 1}, [14]], # 15
  [Region, {head: 14}, [15]], # 16
  [ArrayLiteral, {rebinds: true, sigil: "@", symbol: lines}, [12], 16, Array], # 17
  [Region, {head: 10}, [11, 17]], # 18
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 19
  [Phi, {memory: true, region: 14}, [6, 43], ~, Int], # 20
  [Phi, {memory: true, region: 16}, [20], ~, Int], # 21
  [Phi, {memory: true, predecessors: [11, 13], region: 18}, [6, 21], ~, Int], # 22
  [Subscript, {kind: array}, [7, 19, 22], ~, Scalar], # 23
  [If, ~, [18, 23], 18], # 24
  [Proj, {index: 1}, [24]], # 25
  [PadAccess, {sigil: "@", symbol: n__2}, ~, ~, Unknown], # 26
  [Proj, {index: 0}, [24]], # 27
  [Loop, {bound: entry}, [27], 27], # 28
  [Proj, {index: 1}, [28]], # 29
  [Region, {head: 28}, [29]], # 30
  [ArrayLiteral, {rebinds: true, sigil: "@", symbol: lines}, [26], 30, Array], # 31
  [Region, {head: 24}, [25, 31]], # 32
  [Loop, {bound: entry}, [32], 32], # 33
  [Phi, {region: 33}, [1, 52], ~, Str], # 34
  [Proj, {index: 1}, [33]], # 35
  [Region, {head: 33}, [35]], # 36
  [Return, ~, [34], 36], # 37
  [Count, ~, [2, 6], ~, Int], # 38
  [Phi, {region: 14}, [8, 61], ~, Int], # 39
  [Subscript, {kind: array}, [2, 39, 6], ~, Scalar], # 40
  [Call, {dispatch_kind: builtin, name: uc, param_names: []}, [40], ~, Str], # 41
  [Proj, {index: 0}, [14]], # 42
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [12, 41, 6], 42, Int], # 43
  [Phi, {predecessors: [11, 13], region: 18}, [2, 17], ~, Array], # 44
  [Phi, {predecessors: [25, 27], region: 32}, [44, 31], ~, Array], # 45
  [Phi, {region: 33}, [8, 67], ~, Int], # 46
  [Phi, {memory: true, region: 28}, [22, 60], ~, Int], # 47
  [Phi, {memory: true, region: 30}, [47], ~, Int], # 48
  [Phi, {memory: true, predecessors: [25, 27], region: 32}, [22, 48], ~, Int], # 49
  [Subscript, {kind: array}, [45, 46, 49], ~, Scalar], # 50
  [Coerce, {from_repr: Unknown, to_repr: Str}, [50], ~, Str], # 51
  [Concat, ~, [34, 51], ~, Str], # 52
  [NumGt, ~, [38, 39], 14, Boolean], # 53
  [Count, ~, [44, 22], ~, Int], # 54
  [Phi, {region: 28}, [8, 66], ~, Int], # 55
  [Subscript, {kind: array}, [44, 55, 22], ~, Scalar], # 56
  [Coerce, {from_repr: Scalar, to_repr: Str}, [56], ~, Str], # 57
  [Concat, ~, [57, 57], ~, Str], # 58
  [Proj, {index: 0}, [28]], # 59
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [26, 58, 22], 59, Int], # 60
  [Add, ~, [39, 19], ~, Int], # 61
  [NumGt, ~, [54, 55], 28, Boolean], # 62
  [Count, ~, [45, 49], ~, Int], # 63
  [NumGt, ~, [63, 46], 33, Boolean], # 64
  [Proj, {index: 0}, [33]], # 65
  [Add, ~, [55, 19], ~, Int], # 66
  [Add, ~, [46, 19], ~, Int]]} # 67
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
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, name: main::h, param_names: [], want: list}, [6], 3, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [4, 5, 8, 9], 7, Scalar], # 10
  [Return, {implicit: true}, [1], 10]]} # 11
main::f: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: c}, [1], ~, Unknown], # 2
  [Parameter, {index: 0, name: $c, sigil: $}, ~, ~, Unknown], # 3
  [Assign, ~, [2, 3], 0, Unknown], # 4
  [PadAccess, {sigil: $, symbol: c}, [4], ~, Unknown], # 5
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, [5], 4, Str], # 6
  [PadAccess, {sigil: $, symbol: c}, [6], ~, Unknown], # 7
  [Assign, ~, [7, 6], 6, Str], # 8
  [PadAccess, {sigil: $, symbol: c}, [8], ~, Unknown], # 9
  [Call, {dispatch_kind: direct, name: main::g, param_names: []}, [9], 8, Str], # 10
  [Return, ~, [10], 10]]} # 11
main::g: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: g}, ~, ~, Str], # 1
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Concat, ~, [1, 3], ~, Str], # 4
  [Return, {implicit: true}, [4], 0]]} # 5
main::h: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: x}, [2], ~, Unknown], # 3
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Unknown], # 4
  [Assign, ~, [3, 4], 0, Unknown], # 5
  [PadAccess, {sigil: $, symbol: x}, [5], ~, Unknown], # 6
  [Ref, ~, [6], ~, Unknown], # 7
  [PostfixDeref, {sigil: $}, [7], ~, Scalar], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Loop, {bound: entry}, [5], 5], # 10
  [Proj, {index: 1}, [10]], # 11
  [Region, {head: 10}, [11]], # 12
  [Assign, ~, [8, 9], 12, Int], # 13
  [PadAccess, {sigil: $, symbol: x}, [13], ~, Unknown], # 14
  [ArrayLiteral, ~, ~, ~, Array], # 15
  [Loop, {bound: entry}, [13], 13], # 16
  [Phi, {region: 16}, [15, 39], ~, Array], # 17
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 14, 17, 13], ~, Str], # 18
  [Proj, {index: 1}, [16]], # 19
  [Region, {head: 16}, [19]], # 20
  [Return, {implicit: true}, [18], 20], # 21
  [Phi, {memory: true, region: 10}, [5, 33], ~, Unknown], # 22
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 23
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 24
  [Phi, {region: 10}, [24, 43], ~, Int], # 25
  [NumGt, ~, [23, 25], 10, Boolean], # 26
  [Proj, {index: 0}, [10]], # 27
  [PadAccess, {sigil: "@", symbol: l}, ~, ~, Unknown], # 28
  [PadAccess, {sigil: $, symbol: x}, [22], ~, Unknown], # 29
  [Assign, ~, [29, 25], 27, Int], # 30
  [PadAccess, {sigil: $, symbol: x}, [30], ~, Unknown], # 31
  [Ref, ~, [31], ~, Unknown], # 32
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [28, 32, 30], 30, Int], # 33
  [Phi, {memory: true, region: 12}, [22], ~, Unknown], # 34
  [ArrayLiteral, ~, [28], ~, List], # 35
  [Phi, {region: 16}, [9, 45], ~, Int], # 36
  [Subscript, {kind: array}, [35, 36, 13], ~, Scalar], # 37
  [PostfixDeref, {sigil: $}, [37, 13], ~, Scalar], # 38
  [ListAppend, {collector: map}, [17, 38], ~, Array], # 39
  [Count, ~, [35, 13], ~, Int], # 40
  [NumGt, ~, [40, 36], 16, Boolean], # 41
  [Proj, {index: 0}, [16]], # 42
  [Add, ~, [25, 24], ~, Int], # 43
  [ArrayLiteral, ~, [28], ~, List], # 44
  [Add, ~, [36, 24], ~, Int]]} # 45
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
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
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: A}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [Call, {dispatch_kind: direct, name: main::mk, param_names: [], want: list}, [2, 3, 4], 0, HashRef], # 5
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [5], 5, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: H}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: j}, ~, ~, Str], # 11
  [Call, {dispatch_kind: direct, name: main::mk, param_names: [], want: list}, [9, 10, 3, 11, 4], 6, HashRef], # 12
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [12], 12, Str], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: X}, ~, ~, Str], # 15
  [Call, {dispatch_kind: direct, name: main::mk, param_names: [], want: list}, [15], 13, HashRef], # 16
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [16], 16, Str], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 19
  [Print, ~, [7, 8, 14, 8, 18, 19], 17, Scalar], # 20
  [Return, {implicit: true}, [1], 20]]} # 21
main::f: {start: 0, returns: [36], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: c}, [2], ~, Unknown], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Assign, {targets: 1}, [3, 4], 0, List], # 5
  [PadAccess, {sigil: $, symbol: c}, [5], ~, Unknown], # 6
  [Call, {dispatch_kind: direct, name: main::operation, param_names: [], want: scalar}, [6], 5, Scalar], # 7
  [PadAccess, {sigil: $, symbol: c}, [7], ~, Unknown], # 8
  [Call, {dispatch_kind: direct, name: main::inputs, param_names: [], want: scalar}, [8], 7, Scalar], # 9
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [9], ~, Scalar], # 10
  [Coerce, {from_repr: Scalar, to_repr: Str}, [10], ~, Str], # 11
  [PostfixDeref, {sigil: "@"}, [9, 9], ~, Array], # 12
  [ArrayLiteral, ~, ~, ~, Array], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 14
  [Constant, {const_type: string, value: A}, ~, ~, Str], # 15
  [StrEq, ~, [14, 15], ~, Boolean], # 16
  [If, ~, [9, 16], 9], # 17
  [Proj, {index: 1}, [17]], # 18
  [Constant, {const_type: string, value: H}, ~, ~, Str], # 19
  [StrEq, ~, [14, 19], ~, Boolean], # 20
  [If, ~, [18, 20], 18], # 21
  [Proj, {index: 0}, [21]], # 22
  [Loop, {bound: entry}, [22], 22], # 23
  [Phi, {region: 23}, [13, 49], ~, Array], # 24
  [Slice, {kind: array}, [24, 12], ~, List], # 25
  [ArrayLiteral, {sigil: "@", symbol: e}, [25], ~, Array], # 26
  [Proj, {index: 0}, [17]], # 27
  [Proj, {index: 1}, [23]], # 28
  [Region, {head: 23}, [28]], # 29
  [Region, {head: 17}, [27, 29]], # 30
  [Phi, {predecessors: [27, 18], region: 30}, [12, 26], ~, Array], # 31
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [11, 31, 9], ~, Str], # 32
  [Proj, {index: 1}, [21]], # 33
  [Region, ~, [33, 30]], # 34
  [Phi, {predecessors: [33, 30], region: 34}, [1, 32], ~, Str], # 35
  [Return, ~, [35], 34], # 36
  [Count, ~, [12, 9], ~, Int], # 37
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 38
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 39
  [Subtract, ~, [37, 39], ~, Int], # 40
  [Range, ~, [38, 40], ~, List], # 41
  [Count, ~, [41, 9], ~, Int], # 42
  [Phi, {region: 23}, [38, 50], ~, Int], # 43
  [Subscript, {kind: array}, [41, 43, 9], ~, Scalar], # 44
  [NumGt, ~, [42, 43], 23, Boolean], # 45
  [Coerce, {from_repr: Scalar, to_repr: Num}, [44], ~, Num], # 46
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 47
  [Modulo, ~, [46, 47], ~, Int], # 48
  [ListAppend, {collector: grep}, [24, 44, 48], ~, Array], # 49
  [Add, ~, [43, 39], ~, Int], # 50
  [Proj, {index: 0}, [23]]]} # 51
main::inputs: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: in}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
main::mk: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: op}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: op}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: in}, ~, ~, Str], # 3
  [PadAccess, {sigil: "@", symbol: in}, ~, ~, Unknown], # 4
  [ArrayLiteral, ~, [4], 0, ArrayRef], # 5
  [HashLiteral, ~, [1, 2, 3, 5], 5, HashRef], # 6
  [Return, {implicit: true}, [6], 6], # 7
  [ArgsSource, ~, ~, ~, Array], # 8
  [Assign, {targets: 2}, [2, 4, 8], ~, List]]} # 9
main::operation: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: op}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
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
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: e}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [ArrayLiteral, ~, [5], 0, ArrayRef], # 6
  [HashLiteral, ~, [2, 3, 4, 6], 6, HashRef], # 7
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [7], 7, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [10], 8, Str], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [9, 12, 13], 11, Scalar], # 14
  [Return, {implicit: true}, [1], 14]]} # 15
main::f: {start: 0, returns: [32], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 2
  [Loop, {bound: each}, [0], 0], # 3
  [Phi, {region: 3}, [2, 41], ~, Unknown], # 4
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 5
  [MemStart], # 6
  [Subscript, {kind: hash}, [4, 5, 6], ~, Scalar], # 7
  [Proj, {index: 1}, [3]], # 8
  [Proj, {index: 0}, [3]], # 9
  [RefType, ~, [4], ~, Str], # 10
  [Constant, {const_type: string, value: HASH}, ~, ~, Str], # 11
  [StrEq, ~, [10, 11], ~, Boolean], # 12
  [If, ~, [9, 12], 9], # 13
  [Proj, {index: 0}, [13]], # 14
  [Region, {head: 3}, [8, 14]], # 15
  [Phi, {region: 15}, [1, 7], ~, Undef], # 16
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 17
  [DefinedOr, ~, [16, 17], ~, Scalar], # 18
  [Coerce, {from_repr: Scalar, to_repr: Str}, [18], ~, Str], # 19
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 20
  [Subscript, {kind: hash}, [4, 20, 6], ~, Scalar], # 21
  [PostfixDeref, {sigil: "@"}, [21, 6], ~, Array], # 22
  [Count, ~, [22, 6], ~, Int], # 23
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 24
  [NumGt, ~, [23, 24], ~, Boolean], # 25
  [Subscript, {kind: array}, [21, 24, 6], ~, Scalar], # 26
  [TernaryExpr, ~, [25, 26, 1], ~, Unknown], # 27
  [Phi, {region: 15}, [1, 27], ~, Undef], # 28
  [DefinedOr, ~, [28, 17], ~, Scalar], # 29
  [Coerce, {from_repr: Scalar, to_repr: Str}, [29], ~, Str], # 30
  [Concat, ~, [19, 30], ~, Str], # 31
  [Return, ~, [31], 15], # 32
  [Phi, {region: 3}, [24, 37], ~, Int], # 33
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 34
  [NumLt, ~, [33, 34], 3, Boolean], # 35
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 36
  [Add, ~, [33, 36], ~, Int], # 37
  [Proj, {index: 1}, [13]], # 38
  [ArrayLiteral, ~, ~, 38, ArrayRef], # 39
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 40
  [HashLiteral, ~, [5, 40, 20, 39], 39, HashRef], # 41
  [ArgsSource, ~, ~, ~, Array], # 42
  [Assign, {targets: 1}, [2, 42], ~, List]]} # 43
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
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 0, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, {implicit: true}, [1], 5]]} # 6
main::add: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [PadAccess, {sigil: $, symbol: h}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 4
  [Assign, ~, [4, 1], 0, Int], # 5
  [Return, {implicit: true}, [1], 5], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Assign, {targets: 1}, [2, 7], ~, List]]} # 8
main::f: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [HashLiteral, {sigil: "%", symbol: pre}, [2, 3], ~, Hash], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [4, 5], ~, List], # 6
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [6, 5], ~, List], # 7
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 7, 5], ~, Str], # 8
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Ref, ~, [4], ~, HashRef], # 11
  [Call, {dispatch_kind: direct, name: main::add, param_names: [], want: void}, [11], 0, Int], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [4, 12], ~, List], # 13
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [13, 12], ~, List], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 14, 12], ~, Str], # 15
  [Concat, ~, [10, 15], ~, Str], # 16
  [Return, ~, [16], 12]]} # 17
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
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 5
  [ArrayLiteral, ~, [2, 3, 4, 5], 0, ArrayRef], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [6, 7], 6, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [ArrayLiteral, ~, [2, 3], 8, ArrayRef], # 10
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [10, 7], 10, Str], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 13
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 14
  [HashLiteral, ~, [2, 13, 3, 14], 11, HashRef], # 15
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, [15], 15, Str], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [9, 12, 17, 18], 16, Scalar], # 19
  [Return, {implicit: true}, [1], 19]]} # 20
main::f: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [ArrayLiteral, ~, ~, ~, Array], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {region: 3}, [2, 24], ~, Array], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 4, 5], ~, Str], # 6
  [Proj, {index: 1}, [3]], # 7
  [Region, {head: 3}, [7]], # 8
  [Return, ~, [6], 8], # 9
  [PadAccess, {sigil: $, symbol: i}, ~, ~, Num], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [Add, ~, [10, 11], ~, Num], # 12
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 13
  [Add, ~, [10, 13], ~, Num], # 14
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 15
  [Slice, {kind: array}, [12, 14, 15], ~, List], # 16
  [Count, ~, [16, 5], ~, Int], # 17
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 18
  [Phi, {region: 3}, [18, 25], ~, Int], # 19
  [NumGt, ~, [17, 19], 3, Boolean], # 20
  [Proj, {index: 0}, [3]], # 21
  [Subscript, {kind: array}, [16, 19, 5], ~, Scalar], # 22
  [Defined, ~, [22], ~, Boolean], # 23
  [ListAppend, {collector: grep}, [4, 22, 23], ~, Array], # 24
  [Add, ~, [19, 11], ~, Int], # 25
  [ArgsSource, ~, ~, ~, Array], # 26
  [Assign, {targets: 2}, [15, 10, 26], ~, List]]} # 27
main::g: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [PadAccess, {sigil: $, symbol: h}, ~, ~, Unknown], # 4
  [Slice, {kind: hash}, [2, 3, 4], ~, List], # 5
  [MemStart], # 6
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 5, 6], ~, Str], # 7
  [Return, ~, [7], 0], # 8
  [ArgsSource, ~, ~, ~, Array], # 9
  [Assign, {targets: 1}, [4, 9], ~, List]]} # 10
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
C::f: {start: 0, returns: [34], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 1
  [PadAccess, {sigil: "@", symbol: args}, ~, ~, Scalar], # 2
  [MemStart], # 3
  [Count, ~, [2, 3], ~, Int], # 4
  [If, ~, [0, 4], 0], # 5
  [Proj, {index: 1}, [5]], # 6
  [Call, {class_name: C, dispatch_kind: method, name: inner, param_names: [], want: scalar}, [1], 6, Unknown], # 7
  [Constant, {const_type: string, value: bind}, ~, ~, Str], # 8
  [Subscript, {kind: hash}, [1, 8], ~, Scalar], # 9
  [Subscript, {kind: hash}, [1, 8, 3], ~, Scalar], # 10
  [Proj, {index: 0}, [5]], # 11
  [Defined, ~, [10], ~, Boolean], # 12
  [If, ~, [11, 12], 11], # 13
  [Proj, {index: 1}, [13]], # 14
  [HashLiteral, ~, ~, 14, HashRef], # 15
  [DefinedOr, ~, [10, 15], ~, Scalar], # 16
  [PostfixDeref, {sigil: "%"}, [16, 3], ~, Hash], # 17
  [Proj, {index: 0}, [13]], # 18
  [Region, {head: 13}, [18, 15]], # 19
  [HashLiteral, ~, [17], 19, HashRef], # 20
  [Assign, {local: true}, [9, 20], 20, HashRef], # 21
  [Loop, {bound: entry}, [21], 21], # 22
  [Proj, {index: 1}, [22]], # 23
  [Region, {head: 22}, [23]], # 24
  [Call, {class_name: C, dispatch_kind: method, name: inner, param_names: [], want: scalar}, [1], 24, Unknown], # 25
  [Constant, {const_type: string, value: cache}, ~, ~, Str], # 26
  [Subscript, {kind: hash}, [1, 26], ~, Scalar], # 27
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 28
  [Subscript, {kind: hash}, [27, 28], ~, Scalar], # 29
  [Assign, ~, [29, 7], 7, Unknown], # 30
  [Assign, ~, [29, 25], 25, Unknown], # 31
  [Region, {head: 5}, [30, 31]], # 32
  [Phi, {predecessors: [6, 11], region: 32}, [7, 25], ~, Unknown], # 33
  [Return, ~, [33], 32], # 34
  [ArgsSource, ~, ~, ~, Array], # 35
  [Assign, {targets: 2}, [1, 2, 35], ~, List], # 36
  [Count, ~, [2, 21], ~, Int], # 37
  [Phi, {memory: true, region: 22}, [21, 49], ~, Scalar], # 38
  [Count, ~, [2, 38], ~, Int], # 39
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 40
  [Phi, {region: 22}, [40, 50], ~, Int], # 41
  [Subscript, {kind: array}, [2, 41, 38], ~, Scalar], # 42
  [Exists, {kind: hash}, [1, 8, 3], ~, Boolean], # 43
  [Phi, {memory: true, region: 24}, [38], ~, Scalar], # 44
  [NumGt, ~, [39, 41], 22, Boolean], # 45
  [Subscript, {kind: hash}, [9, 42], ~, Scalar], # 46
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 47
  [Proj, {index: 0}, [22]], # 48
  [Assign, ~, [46, 47], 48, Int], # 49
  [Add, ~, [41, 47], ~, Int]]} # 50
C::inner: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: bind}, ~, ~, Str], # 3
  [MemStart], # 4
  [Subscript, {kind: hash}, [2, 3, 4], ~, Scalar], # 5
  [Defined, ~, [5], ~, Boolean], # 6
  [If, ~, [0, 6], 0], # 7
  [Proj, {index: 1}, [7]], # 8
  [HashLiteral, ~, ~, 8, HashRef], # 9
  [DefinedOr, ~, [5, 9], ~, Scalar], # 10
  [PostfixDeref, {sigil: "%"}, [10, 4], ~, Hash], # 11
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [11, 4], ~, List], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [12, 4], ~, List], # 13
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [1, 13, 4], ~, Str], # 14
  [Proj, {index: 0}, [7]], # 15
  [Region, {head: 7}, [15, 9]], # 16
  [Return, {implicit: true}, [14], 16], # 17
  [ArgsSource, ~, ~, ~, Array], # 18
  [Assign, {targets: 1}, [2, 18], ~, List]]} # 19
C::new: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: cache}, ~, ~, Str], # 1
  [HashLiteral, ~, ~, 0, HashRef], # 2
  [Constant, {const_type: string, value: bind}, ~, ~, Str], # 3
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 4
  [HashLiteral, ~, [1, 2, 3, 4], 2, HashRef], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [MemStart], # 7
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [6, 7], 5, Scalar], # 8
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [5, 8, 8], ~, Unknown], # 9
  [Return, {implicit: true}, [9], 8]]} # 10
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: C, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 0, Object], # 2
  [Call, {class_name: C, dispatch_kind: method, name: f, param_names: [], want: list}, [2], 2, Unknown], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 7
  [Call, {class_name: C, dispatch_kind: method, name: f, param_names: [], want: list}, [2, 6, 7], 3, Unknown], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Call, {class_name: C, dispatch_kind: method, name: inner, param_names: [], want: list}, [2], 8, Unknown], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [4, 5, 9, 5, 11, 12], 10, Scalar], # 13
  [Return, {implicit: true}, [1], 13]]} # 14
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
C::f: {start: 0, returns: [57], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [PadAccess, {sigil: $, symbol: node}, ~, ~, Unknown], # 3
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 4
  [Constant, {const_type: string, value: memo}, ~, ~, Str], # 5
  [Subscript, {kind: hash}, [4, 5], ~, Scalar], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 7
  [Subscript, {kind: hash}, [6, 7], ~, Scalar], # 8
  [Assign, ~, [8, 1], 0, Int], # 9
  [Call, {dispatch_kind: method, name: inputs, param_names: [], want: scalar}, [3], 9, Unknown], # 10
  [Loop, {bound: entry}, [10], 10], # 11
  [Proj, {index: 1}, [11]], # 12
  [Phi, {memory: true, region: 11}, [10, 71], ~, Unknown], # 13
  [PostfixDeref, {sigil: "@"}, [10, 10], ~, Array], # 14
  [Phi, {region: 11}, [1, 60], ~, Int], # 15
  [Proj, {index: 0}, [11]], # 16
  [Exists, {kind: array}, [14, 15, 13], 16, Boolean], # 17
  [Subscript, {kind: array}, [14, 15], ~, Scalar], # 18
  [Ref, ~, [18], ~, ScalarRef], # 19
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 20
  [TernaryExpr, ~, [17, 19, 20], 17, Scalar], # 21
  [PostfixDeref, {sigil: $}, [21, 13], ~, Scalar], # 22
  [Subscript, {kind: array}, [14, 15, 13], ~, Scalar], # 23
  [TernaryExpr, ~, [17, 22, 23], 21, Scalar], # 24
  [RefType, ~, [24], ~, Str], # 25
  [Constant, {const_type: string, value: ARRAY}, ~, ~, Str], # 26
  [StrEq, ~, [25, 26], ~, Boolean], # 27
  [PostfixDeref, {sigil: $}, [21, 13], ~, Scalar], # 28
  [Subscript, {kind: array}, [14, 15, 13], ~, Scalar], # 29
  [TernaryExpr, ~, [17, 28, 29], ~, Scalar], # 30
  [PostfixDeref, {sigil: "@"}, [30, 13], ~, Array], # 31
  [PostfixDeref, {sigil: $}, [21, 13], ~, Scalar], # 32
  [Subscript, {kind: array}, [14, 15, 13], ~, Scalar], # 33
  [TernaryExpr, ~, [17, 32, 33], ~, Scalar], # 34
  [TernaryExpr, ~, [27, 31, 34], ~, List], # 35
  [ArrayLiteral, {sigil: "@", symbol: flat}, [35], 24, Array], # 36
  [Loop, {bound: entry}, [36], 36], # 37
  [Phi, {memory: true, region: 37}, [13, 78], ~, Unknown], # 38
  [PadAccess, {sigil: $, symbol: el}, [38], ~, Unknown], # 39
  [Phi, {region: 37}, [1, 59], ~, Int], # 40
  [Subscript, {kind: array}, [36, 40, 38], ~, Scalar], # 41
  [Proj, {index: 0}, [37]], # 42
  [Assign, ~, [39, 41], 42, Scalar], # 43
  [PadAccess, {sigil: $, symbol: el}, [43], ~, Unknown], # 44
  [Defined, ~, [44], ~, Boolean], # 45
  [RefType, ~, [44], ~, Str], # 46
  [And, ~, [45, 46], ~, Scalar], # 47
  [If, ~, [43, 47], 43], # 48
  [Proj, {index: 0}, [48]], # 49
  [Call, {class_name: C, dispatch_kind: method, name: f, param_names: [], want: scalar}, [4, 44], 49, Unknown], # 50
  [If, ~, [50, 50], 50], # 51
  [Proj, {index: 0}, [51]], # 52
  [Region, {head: 11}, [12, 52]], # 53
  [Phi, {region: 53}, [1, 2], ~, Int], # 54
  [Or, ~, [54, 2], ~, Int], # 55
  [Assign, ~, [8, 55], 53, Int], # 56
  [Return, ~, [55], 56], # 57
  [Count, ~, [14, 10], ~, Int], # 58
  [Add, ~, [40, 2], ~, Int], # 59
  [Add, ~, [15, 2], ~, Int], # 60
  [Phi, {memory: true, region: 53}, [13, 50], ~, Unknown], # 61
  [Count, ~, [14, 13], ~, Int], # 62
  [NumGt, ~, [62, 15], 11, Boolean], # 63
  [Count, ~, [36, 38], ~, Int], # 64
  [NumGt, ~, [64, 40], 37, Boolean], # 65
  [Subscript, {kind: array}, [36, 40], ~, Scalar], # 66
  [ArgsSource, ~, ~, ~, Array], # 67
  [Assign, {targets: 2}, [4, 3, 67], ~, List], # 68
  [Proj, {index: 1}, [37]], # 69
  [Region, {head: 37}, [69]], # 70
  [Phi, {memory: true, region: 70}, [38], ~, Unknown], # 71
  [Count, ~, [36, 13], ~, Int], # 72
  [Proj, {index: 1}, [48]], # 73
  [Proj, {index: 1}, [51]], # 74
  [Region, {head: 48}, [73, 74]], # 75
  [Phi, {memory: true, predecessors: [73, 49], region: 75}, [43, 50], ~, Unknown], # 76
  [PadAccess, {sigil: $, symbol: el}, [76], ~, Unknown], # 77
  [Assign, {if_changed: true}, [66, 77], 75, Unknown]]} # 78
C::new: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: memo}, ~, ~, Str], # 1
  [HashLiteral, ~, ~, 0, HashRef], # 2
  [HashLiteral, ~, [1, 2], 2, HashRef], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, memory_input: true, name: shift, param_names: []}, [4, 5], 3, Scalar], # 6
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [3, 6, 6], ~, Unknown], # 7
  [Return, {implicit: true}, [7], 6]]} # 8
N::inputs: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 3
  [Constant, {const_type: string, value: in}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, {kind: hash}, [3, 4, 5], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
N::new: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: in}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: in}, ~, ~, Unknown], # 2
  [ArrayLiteral, ~, [2], 0, ArrayRef], # 3
  [HashLiteral, ~, [1, 3], 3, HashRef], # 4
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 5
  [MemStart], # 6
  [Call, {dispatch_kind: builtin, memory_input: true, name: bless, param_names: []}, [4, 5, 6], ~, Unknown], # 7
  [Return, {implicit: true}, [7], 4], # 8
  [ArgsSource, ~, ~, ~, Array], # 9
  [Assign, {targets: 2}, [5, 2, 9], ~, List]]} # 10
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: C, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 0, Object], # 2
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [ArrayLiteral, ~, [5, 6], 2, ArrayRef], # 7
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [3, 4, 7], 7, Object], # 8
  [Call, {class_name: C, dispatch_kind: method, name: f, param_names: [], want: list}, [2, 8], 8, Unknown], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Call, {class_name: C, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 9, Object], # 11
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, ~, 11, Object], # 12
  [ArrayLiteral, ~, [5, 12], 12, ArrayRef], # 13
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [3, 4, 13], 13, Object], # 14
  [Call, {class_name: C, dispatch_kind: method, name: f, param_names: [], want: list}, [11, 14], 14, Unknown], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [10, 16, 17], 15, Scalar], # 18
  [Return, {implicit: true}, [1], 18]]} # 19
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
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: A::b}, ~, ~, Str], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: q}, ~, ~, Str], # 6
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [6], 3, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [PadAccess, {sigil: $, symbol: w}, ~, ~, Str], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown], # 11
  [Defined, ~, [11], ~, Boolean], # 12
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: u}, ~, ~, Str], # 14
  [TernaryExpr, ~, [12, 13, 14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Print, ~, [4, 5, 8, 5, 10, 15, 16], 7, Scalar], # 17
  [Return, {implicit: true}, [1], 17], # 18
  [Constant, {const_type: string, value: abc}, ~, ~, Str], # 19
  [RegexMatch, {flags: "", pattern: b}, [19], ~, Boolean], # 20
  [Assign, {targets: 1}, [9, 20], ~, Boolean], # 21
  [RegexMatch, {flags: "", pattern: z}, [19], ~, Boolean], # 22
  [Assign, {targets: 1}, [11, 22], ~, Boolean]]} # 23
main::f: {start: 0, returns: [11], nodes: [
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
  [Return, ~, [10], 0], # 11
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 12
  [TernaryExpr, ~, [2, 8, 12], ~, Scalar], # 13
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 14
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 15
  [DefinedOr, ~, [14, 15], ~, Unknown], # 16
  [RegexMatch, {flags: "", pattern: "^(.*)::([^:]+)$"}, [16], ~, Boolean], # 17
  [Assign, {targets: 2}, [1, 6, 17], ~, List], # 18
  [ArgsSource, ~, ~, ~, Array], # 19
  [Assign, {targets: 1}, [14, 19], ~, List]]} # 20
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
  [Delete, {kind: hash}, [6, 4, 10], 0, Scalar], # 11
  [Assign, ~, [8, 9], 11, Int], # 12
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [12], ~, Scalar], # 13
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 14
  [Call, {dispatch_kind: builtin, memory_input: true, name: values, param_names: [], want: list}, [6, 11], ~, List], # 15
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [15, 11], ~, List], # 16
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [14, 16, 12], ~, Str], # 17
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: scalar}, [6, 12], ~, Int], # 20
  [Coerce, {from_repr: Int, to_repr: Str}, [20], ~, Str], # 21
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 22
  [Print, ~, [19, 21, 22], 12, Scalar], # 23
  [Return, {implicit: true}, [1], 23]]} # 24
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
main::__PROGRAM__: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {shared: 1, sigil: "@", symbol: F}, [3], ~, Unknown], # 4
  [Constant, {const_type: string, value: name}, ~, ~, Str], # 5
  [HashLiteral, ~, [5, 2], 0, HashRef], # 6
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 7
  [HashLiteral, ~, [5, 7], 6, HashRef], # 8
  [ArrayLiteral, {sigil: "@", symbol: F}, [6, 8], 8, Array], # 9
  [Assign, ~, [4, 9], 9, List], # 10
  [PadAccess, {shared: 1, sigil: "%", symbol: I}, [10], ~, Unknown], # 11
  [ArrayLiteral, ~, ~, ~, Array], # 12
  [Loop, {bound: entry}, [10], 10], # 13
  [Phi, {region: 13}, [12, 35], ~, Array], # 14
  [Proj, {index: 1}, [13]], # 15
  [Region, {head: 13}, [15]], # 16
  [HashLiteral, {sigil: "%", symbol: I}, [14], 16, Hash], # 17
  [Assign, ~, [11, 17], 17, List], # 18
  [Call, {dispatch_kind: direct, name: main::ix, param_names: [], want: list}, [2], 18, Scalar], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 20
  [Call, {dispatch_kind: direct, name: main::ix, param_names: [], want: list}, [7], 19, Scalar], # 21
  [Coerce, {from_repr: Unknown, to_repr: Str}, [21], ~, Str], # 22
  [Call, {dispatch_kind: direct, name: main::ff, param_names: [], want: scalar}, ~, 21, Unknown], # 23
  [Coerce, {from_repr: Unknown, to_repr: Str}, [23], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [Print, ~, [20, 22, 24, 25], 23, Scalar], # 26
  [Return, {implicit: true}, [1], 26], # 27
  [PadAccess, {shared: 1, sigil: "@", symbol: F}, ~, ~, Unknown], # 28
  [ArrayLiteral, ~, [28], ~, List], # 29
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 30
  [Phi, {region: 13}, [30, 40], ~, Int], # 31
  [Subscript, {kind: array}, [29, 31, 10], ~, Scalar], # 32
  [Subscript, {kind: hash}, [32, 5, 10], ~, Scalar], # 33
  [Phi, {region: 13}, [30, 41], ~, Int], # 34
  [ListAppend, {collector: map}, [14, 33, 34], ~, Array], # 35
  [Count, ~, [29, 10], ~, Int], # 36
  [NumGt, ~, [36, 31], 13, Boolean], # 37
  [Proj, {index: 0}, [13]], # 38
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 39
  [Add, ~, [31, 39], ~, Int], # 40
  [Add, ~, [34, 39], ~, Int], # 41
  [ArrayLiteral, ~, [28], ~, List]]} # 42
main::ff: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: F}, ~, ~, Unknown], # 1
  [Return, ~, [1], 0]]} # 2
main::ix: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "%", symbol: I}, ~, ~, Unknown], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Subscript, {kind: hash}, [1, 5, 4], ~, Scalar], # 6
  [Return, {implicit: true}, [6], 0]]} # 7
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
  [PadAccess, {sigil: $, symbol: s}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: "\u00e9"}, ~, ~, Str], # 4
  [Assign, ~, [3, 4], 0, Str], # 5
  [PadAccess, {sigil: $, symbol: s}, [5], ~, Unknown], # 6
  [Call, {dispatch_kind: direct, external: true, name: utf8::upgrade, param_names: [], want: void}, [6], 5, Unknown], # 7
  [PadAccess, {sigil: $, symbol: s}, [7], ~, Str], # 8
  [Length, ~, [8], ~, Int], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [Length, {bytes: 1}, [8], ~, Int], # 12
  [Coerce, {from_repr: Int, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Print, ~, [10, 11, 13, 14], 7, Scalar], # 15
  [Return, {implicit: true}, [1], 15]]} # 16
"BEGIN 1": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: bytes}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: bytes.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: bytes, dispatch_kind: method, name: import, param_names: []}, [1], 4, Unknown], # 5
  [Return, {implicit: true}, [5], 5]]} # 6
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
  [PadAccess, {sigil: $, symbol: o}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 4
  [ArrayLiteral, ~, ~, 0, ArrayRef], # 5
  [HashLiteral, ~, [4, 5], 5, HashRef], # 6
  [Assign, ~, [3, 6], 6, HashRef], # 7
  [PadAccess, {sigil: $, symbol: o}, [7], ~, Unknown], # 8
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 9
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [8, 9], 7, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [PadAccess, {sigil: $, symbol: o}, [10], ~, Unknown], # 12
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 13
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [12, 13], 10, Str], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Print, ~, [11, 15, 16], 14, Scalar], # 17
  [Return, {implicit: true}, [1], 17]]} # 18
main::f: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 1
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 2
  [Constant, {const_type: string, value: s}, ~, ~, Str], # 3
  [MemStart], # 4
  [Subscript, {kind: hash}, [2, 3, 4], ~, Scalar], # 5
  [PostfixDeref, {sigil: "@"}, [5, 4], ~, Array], # 6
  [Count, ~, [6, 4], ~, Int], # 7
  [Coerce, {from_repr: Int, to_repr: Str}, [7], ~, Str], # 8
  [Concat, ~, [1, 8], ~, Str], # 9
  [Subscript, {kind: hash}, [2, 3], ~, Scalar], # 10
  [PostfixDeref, {sigil: "@"}, [10, 4], ~, Array], # 11
  [PadAccess, {sigil: $, symbol: t}, ~, ~, Unknown], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [11, 12, 4], 0, Int], # 13
  [Return, ~, [9], 13], # 14
  [ArgsSource, ~, ~, ~, Array], # 15
  [Assign, {targets: 2}, [2, 12, 15], ~, List]]} # 16
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
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [7], ~, Str], # 8
  [ArrayLiteral, ~, ~, ~, Array], # 9
  [Phi, {region: 2}, [9, 26], ~, Array], # 10
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [8, 10, 6], ~, Str], # 11
  [Return, ~, [11], 5], # 12
  [Parameter, {index: 0, name: "@g", sigil: "@"}, ~, ~, Array], # 13
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [13, 1], ~, List], # 14
  [Count, ~, [14, 3], ~, Int], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Phi, {region: 2}, [16, 28], ~, Int], # 17
  [NumGt, ~, [15, 17], 2, Boolean], # 18
  [Proj, {index: 0}, [2]], # 19
  [Subscript, {kind: array}, [14, 17], ~, Scalar], # 20
  [Ref, ~, [20], ~, ScalarRef], # 21
  [LocalAlias, {name: _}, [21], 19, Unknown], # 22
  [Subscript, {kind: array}, [14, 17, 3], ~, Scalar], # 23
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 24
  [Call, {class_name: K, dispatch_kind: method, name: isn, param_names: [], want: scalar}, [24, 23], 22, Boolean], # 25
  [ListAppend, {collector: grep}, [10, 23, 25], ~, Array], # 26
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 27
  [Add, ~, [17, 27], ~, Int], # 28
  [Count, ~, [14, 1], ~, Int]]} # 29
K::isn: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Str], # 1
  [RegexMatch, {flags: u, pattern: a}, [1], ~, Boolean], # 2
  [Return, {implicit: true}, [2], 0]]} # 3
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: K, dispatch_kind: method, name: new, param_names: [], want: scalar}, ~, 0, Object], # 2
  [Constant, {const_type: string, value: ba}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: aa}, ~, ~, Str], # 5
  [Call, {class_name: K, dispatch_kind: method, name: f, param_names: [], want: list}, [2, 3, 4, 5], 2, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, Scalar], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, {implicit: true}, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, memory_input: true, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: experimental, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, {implicit: true}, [6], 6]]} # 7
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
  [PadAccess, {shared: 1, sigil: "%", symbol: v}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 6
  [HashLiteral, ~, [5, 6], 0, HashRef], # 7
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 9
  [HashLiteral, ~, [5, 9], 7, HashRef], # 10
  [HashLiteral, {sigil: "%", symbol: v}, [4, 7, 8, 10], 10, Hash], # 11
  [Assign, ~, [3, 11], 11, List], # 12
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 12, Str], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [14, 15], 13, Scalar], # 16
  [Return, {implicit: true}, [1], 16]]} # 17
main::emit: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: e}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [2, 3, 4], ~, Scalar], # 5
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 6
  [Subscript, {kind: hash}, [5, 6], ~, Scalar], # 7
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 8
  [Assign, ~, [7, 8], 0, Str], # 9
  [Return, {implicit: true}, [1], 9]]} # 10
main::f: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Call, {dispatch_kind: direct, name: main::vars, param_names: [], want: scalar}, ~, 0, Unknown], # 1
  [Loop, {bound: entry}, [1], 1], # 2
  [Phi, {memory: true, region: 2}, [1, 38], ~, Unknown], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Phi, {memory: true, region: 5}, [3], ~, Unknown], # 6
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [7], ~, Str], # 8
  [PadAccess, {sigil: "@", symbol: l}, ~, ~, Unknown], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [8, 9, 6], ~, Str], # 10
  [Return, {implicit: true}, [10], 5], # 11
  [PostfixDeref, {sigil: "%"}, [1, 1], ~, Hash], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [12, 1], ~, List], # 13
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [13, 1], ~, List], # 14
  [ArrayLiteral, ~, [14], ~, Array], # 15
  [Count, ~, [15, 1], ~, Int], # 16
  [Count, ~, [15, 3], ~, Int], # 17
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 18
  [Phi, {region: 2}, [18, 41], ~, Int], # 19
  [NumGt, ~, [17, 19], 2, Boolean], # 20
  [Proj, {index: 0}, [2]], # 21
  [Subscript, {kind: array}, [15, 19], ~, Scalar], # 22
  [Ref, ~, [22], 21, ScalarRef], # 23
  [Call, {dispatch_kind: direct, name: main::vars, param_names: [], want: scalar}, ~, 23, Unknown], # 24
  [PadAccess, {sigil: $, symbol: info}, [24], ~, Unknown], # 25
  [PostfixDeref, {sigil: $}, [23, 24], 24, Scalar], # 26
  [Subscript, {kind: hash}, [24, 26, 24], ~, Scalar], # 27
  [Assign, ~, [25, 27], 26, Scalar], # 28
  [PadAccess, {sigil: $, symbol: info}, [28], ~, Unknown], # 29
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 30
  [Subscript, {kind: hash}, [29, 30, 28], ~, Scalar], # 31
  [Coerce, {from_repr: Unknown, to_repr: Str}, [31], ~, Str], # 32
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 33
  [Concat, ~, [32, 33], ~, Str], # 34
  [Call, {dispatch_kind: direct, name: main::emit, param_names: [], want: scalar}, [29], 28, Str], # 35
  [Coerce, {from_repr: Unknown, to_repr: Str}, [35], ~, Str], # 36
  [Concat, ~, [34, 36], ~, Str], # 37
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [9, 37, 35], 35, Int], # 38
  [Subscript, {kind: array}, [15, 19, 24], ~, Scalar], # 39
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 40
  [Add, ~, [19, 40], ~, Int]]} # 41
main::vars: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "%", symbol: v}, ~, ~, Unknown], # 1
  [Ref, ~, [1], ~, Unknown], # 2
  [Return, {implicit: true}, [2], 0]]} # 3
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
  [PadAccess, {shared: 1, sigil: "%", symbol: v}, [2], ~, Unknown], # 3
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 6
  [HashLiteral, ~, [5, 6], 0, HashRef], # 7
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 9
  [HashLiteral, ~, [5, 9], 7, HashRef], # 10
  [HashLiteral, {sigil: "%", symbol: v}, [4, 7, 8, 10], 10, Hash], # 11
  [Assign, ~, [3, 11], 11, List], # 12
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, ~, 12, Str], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [14, 15], 13, Scalar], # 16
  [Return, {implicit: true}, [1], 16]]} # 17
main::emit: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, {kind: array}, [1, 3, 4], ~, Scalar], # 5
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 6
  [Subscript, {kind: hash}, [5, 6], ~, Scalar], # 7
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 8
  [Assign, ~, [7, 8], 0, Str], # 9
  [Subscript, {kind: array}, [1, 2, 9], ~, Str], # 10
  [Return, {implicit: true}, [10], 9]]} # 11
main::f: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Call, {dispatch_kind: direct, name: main::vars, param_names: [], want: scalar}, ~, 0, Unknown], # 1
  [Loop, {bound: entry}, [1], 1], # 2
  [Phi, {memory: true, region: 2}, [1, 51], ~, Unknown], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Phi, {memory: true, region: 5}, [3], ~, Unknown], # 6
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Str}, [7], ~, Str], # 8
  [PadAccess, {sigil: "@", symbol: l}, ~, ~, Unknown], # 9
  [Call, {dispatch_kind: builtin, memory_input: true, name: join, param_names: []}, [8, 9, 6], ~, Str], # 10
  [Return, {implicit: true}, [10], 5], # 11
  [PostfixDeref, {sigil: "%"}, [1, 1], ~, Hash], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [12, 1], ~, List], # 13
  [Call, {dispatch_kind: builtin, memory_input: true, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [13, 1], ~, List], # 14
  [ArrayLiteral, ~, [14], ~, Array], # 15
  [Count, ~, [15, 1], ~, Int], # 16
  [Count, ~, [15, 3], ~, Int], # 17
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 18
  [Phi, {region: 2}, [18, 54], ~, Int], # 19
  [NumGt, ~, [17, 19], 2, Boolean], # 20
  [Proj, {index: 0}, [2]], # 21
  [Subscript, {kind: array}, [15, 19], ~, Scalar], # 22
  [Ref, ~, [22], 21, ScalarRef], # 23
  [Call, {dispatch_kind: direct, name: main::vars, param_names: [], want: scalar}, ~, 23, Unknown], # 24
  [PadAccess, {sigil: $, symbol: info}, [24], ~, Unknown], # 25
  [PostfixDeref, {sigil: $}, [23, 24], 24, Scalar], # 26
  [Subscript, {kind: hash}, [24, 26, 24], ~, Scalar], # 27
  [Assign, ~, [25, 27], 26, Scalar], # 28
  [PadAccess, {sigil: $, symbol: info}, [28], ~, Unknown], # 29
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 30
  [Subscript, {kind: hash}, [29, 30, 28], ~, Scalar], # 31
  [Coerce, {from_repr: Unknown, to_repr: Str}, [31], ~, Str], # 32
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 33
  [Concat, ~, [32, 33], ~, Str], # 34
  [PostfixDeref, {sigil: $}, [23, 28], 28, Scalar], # 35
  [Coerce, {from_repr: Scalar, to_repr: Str}, [35], ~, Str], # 36
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 37
  [StrEq, ~, [36, 37], ~, Boolean], # 38
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 39
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 40
  [TernaryExpr, ~, [38, 39, 40], ~, Scalar], # 41
  [Call, {dispatch_kind: direct, name: main::emit, param_names: [], want: scalar}, [29, 41], 35, Str], # 42
  [Coerce, {from_repr: Unknown, to_repr: Str}, [42], ~, Str], # 43
  [Concat, ~, [34, 43], ~, Str], # 44
  [Defined, ~, [42], ~, Boolean], # 45
  [If, ~, [42, 45], 42], # 46
  [Proj, {index: 0}, [46]], # 47
  [Call, {dispatch_kind: builtin, memory_input: true, name: push, param_names: []}, [9, 44, 42], 47, Int], # 48
  [Proj, {index: 1}, [46]], # 49
  [Region, {head: 46}, [48, 49]], # 50
  [Phi, {memory: true, predecessors: [47, 49], region: 50}, [48, 42], ~, Str], # 51
  [Subscript, {kind: array}, [15, 19, 24], ~, Scalar], # 52
  [Subscript, {kind: array}, [15, 19, 28], ~, Scalar], # 53
  [Add, ~, [19, 39], ~, Int]]} # 54
main::vars: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "%", symbol: v}, ~, ~, Unknown], # 1
  [Ref, ~, [1], ~, Unknown], # 2
  [Return, {implicit: true}, [2], 0]]} # 3
```
