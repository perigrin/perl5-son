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
  [HashLiteral, {sigil: "%", symbol: cache}, [5, 6], ~, Hash], # 7
  [Assign, ~, [4, 7], 0, List], # 8
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
Node::new: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {sigil: "%", symbol: a}, ~, ~, Unknown], # 1
  [HashLiteral, ~, [1], 0, HashRef], # 2
  [PadAccess, {sigil: $, symbol: c}, ~, ~, Unknown], # 3
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [2, 3], ~, Unknown], # 4
  [Return, {implicit: true}, [4], 2], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [Assign, {targets: 2}, [3, 1, 6], ~, List]]} # 7
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
main::matching: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: found}, ~, ~, Unknown], # 2
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 2], ~, Str], # 3
  [Loop, {bound: entry}, [0], 0], # 4
  [Proj, {index: 1}, [4]], # 5
  [Region, {head: 4}, [5]], # 6
  [Return, ~, [3], 6], # 7
  [PadAccess, {sigil: $, symbol: nodes}, ~, ~, Unknown], # 8
  [MemStart], # 9
  [PostfixDeref, {sigil: "@"}, [8, 9], ~, Array], # 10
  [Count, ~, [10, 9], ~, Int], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Phi, {region: 4}, [12, 54], ~, Int], # 13
  [NumGt, ~, [11, 13], 4, Boolean], # 14
  [Proj, {index: 0}, [4]], # 15
  [Subscript, {kind: array}, [10, 13, 9], ~, Scalar], # 16
  [Defined, ~, [16], ~, Boolean], # 17
  [If, ~, [15, 17], 15], # 18
  [PadAccess, {sigil: $, symbol: loop}, ~, ~, Unknown], # 19
  [Constant, {const_type: string, value: kind}, ~, ~, Str], # 20
  [Proj, {index: 0}, [18]], # 21
  [Call, {dispatch_kind: method, name: can, param_names: [], want: scalar}, [16, 20], 21, Unknown], # 22
  [Proj, {index: 1}, [18]], # 23
  [Region, {head: 18}, [22, 23]], # 24
  [Phi, {predecessors: [21, 23], region: 24}, [22, 17], ~, Unknown], # 25
  [If, ~, [24, 25], 24], # 26
  [Proj, {index: 0}, [26]], # 27
  [Call, {dispatch_kind: method, name: kind, param_names: [], want: scalar}, [16], 27, Unknown], # 28
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 29
  [Constant, {const_type: string, value: Phi}, ~, ~, Str], # 30
  [StrEq, ~, [29, 30], ~, Boolean], # 31
  [If, ~, [28, 31], 28], # 32
  [Proj, {index: 0}, [32]], # 33
  [Call, {dispatch_kind: method, name: owner, param_names: [], want: scalar}, [16], 33, Unknown], # 34
  [Defined, ~, [34], ~, Boolean], # 35
  [If, ~, [34, 35], 34], # 36
  [Proj, {index: 0}, [36]], # 37
  [Call, {dispatch_kind: method, name: name, param_names: [], want: scalar}, [34], 37, Unknown], # 38
  [Call, {dispatch_kind: method, name: name, param_names: [], want: scalar}, [19], 38, Unknown], # 39
  [Proj, {index: 1}, [36]], # 40
  [Region, {head: 36}, [39, 40]], # 41
  [Coerce, {from_repr: Unknown, to_repr: Str}, [38], ~, Str], # 42
  [Coerce, {from_repr: Unknown, to_repr: Str}, [39], ~, Str], # 43
  [StrEq, ~, [42, 43], ~, Boolean], # 44
  [Phi, {predecessors: [37, 40], region: 41}, [44, 35], ~, Boolean], # 45
  [If, ~, [41, 45], 41], # 46
  [Proj, {index: 0}, [46]], # 47
  [Call, {dispatch_kind: method, name: name, param_names: [], want: scalar}, [16], 47, Unknown], # 48
  [Defined, ~, [48], ~, Boolean], # 49
  [If, ~, [48, 49], 48], # 50
  [Proj, {index: 0}, [50]], # 51
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 48], 51, Unknown], # 52
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 53
  [Add, ~, [13, 53], ~, Int], # 54
  [Proj, {index: 1}, [50]], # 55
  [Region, {head: 50}, [55, 52]], # 56
  [Phi, {predecessors: [21, 23], region: 24}, [22, 9], ~, Unknown], # 57
  [Proj, {index: 1}, [26]], # 58
  [Region, {head: 26}, [58, 56]], # 59
  [Phi, {predecessors: [58, 27], region: 59}, [57, 48], ~, Unknown], # 60
  [ArgsSource, ~, ~, ~, Array], # 61
  [Assign, {targets: 2}, [19, 8, 61], ~, List], # 62
  [Proj, {index: 1}, [32]], # 63
  [Region, {head: 4}, [59, 63]], # 64
  [Phi, {predecessors: [15, 63], region: 64}, [60, 28], ~, Unknown], # 65
  [Phi, {predecessors: [37, 40], region: 41}, [39, 34], ~, Unknown], # 66
  [Proj, {index: 1}, [46]], # 67
  [Region, {head: 4}, [64, 67]], # 68
  [Phi, {region: 68}, [65, 66], ~, Unknown]]} # 69
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
main::walk: {start: 0, returns: [29], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "stopped at "}, ~, ~, Str], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [2], ~, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [PadAccess, {sigil: "@", symbol: chain}, ~, ~, Unknown], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 5], ~, Str], # 8
  [PadAccess, {sigil: $, symbol: op}, ~, ~, Str], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: If}, ~, ~, Str], # 11
  [StrEq, ~, [10, 11], ~, Boolean], # 12
  [Constant, {const_type: string, value: S}, ~, ~, Str], # 13
  [StrEq, ~, [10, 13], ~, Boolean], # 14
  [Or, ~, [12, 14], ~, Boolean], # 15
  [If, ~, [0, 15], 0], # 16
  [Proj, {index: 0}, [16]], # 17
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [5, 9], 17, Unknown], # 18
  [If, ~, [18, 12], 18], # 19
  [Proj, {index: 0}, [19]], # 20
  [Proj, {index: 1}, [16]], # 21
  [Proj, {index: 1}, [19]], # 22
  [Region, {head: 16}, [21, 22]], # 23
  [Loop, {bound: entry}, [23], 23], # 24
  [Proj, {index: 1}, [24]], # 25
  [Region, {head: 24}, [25]], # 26
  [Region, ~, [20, 26]], # 27
  [Phi, {predecessors: [20, 26], region: 27}, [7, 8], ~, Str], # 28
  [Return, ~, [28], 27], # 29
  [PadAccess, {sigil: $, symbol: items}, ~, ~, Unknown], # 30
  [PostfixDeref, {sigil: "@"}, [30, 2], ~, Array], # 31
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 32
  [Phi, {region: 24}, [32, 42], ~, Int], # 33
  [Subscript, {kind: array}, [31, 33, 2], ~, Scalar], # 34
  [Proj, {index: 0}, [24]], # 35
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [5, 34], 35, Unknown], # 36
  [ArgsSource, ~, ~, ~, Array], # 37
  [Assign, {targets: 2}, [9, 30, 37], ~, List], # 38
  [Count, ~, [31, 2], ~, Int], # 39
  [NumGt, ~, [39, 33], 24, Boolean], # 40
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 41
  [Add, ~, [33, 41], ~, Int]]} # 42
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
main::build: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: inputs}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [HashLiteral, {sigil: "%", symbol: args}, [2], ~, Hash], # 3
  [Constant, {const_type: string, value: values}, ~, ~, Str], # 4
  [MemStart], # 5
  [Delete, {kind: hash}, [3, 4, 5], 0, Scalar], # 6
  [Defined, ~, [6], ~, Boolean], # 7
  [If, ~, [6, 7], 6], # 8
  [Proj, {index: 1}, [8]], # 9
  [ArrayLiteral, ~, ~, 9, ArrayRef], # 10
  [Proj, {index: 0}, [8]], # 11
  [Region, {head: 8}, [11, 10]], # 12
  [Phi, {predecessors: [11, 9], region: 12}, [6, 10], ~, Scalar], # 13
  [Call, {dispatch_kind: direct, name: main::count_of, param_names: []}, [1, 13], 12, Str], # 14
  [Return, ~, [14], 14]]} # 15
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
main::tally: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 47], ~, Unknown], # 3
  [PadAccess, {shared: 1, sigil: $, symbol: seen}, [3], ~, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [EntryDef, {package: main, sigil: $, symbol: total}, [3], ~, Scalar], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Concat, ~, [7, 9], ~, Str], # 10
  [Proj, {index: 1}, [2]], # 11
  [Region, {head: 2}, [11]], # 12
  [Return, ~, [10], 12], # 13
  [ArgsSource, ~, ~, ~, Array], # 14
  [Count, ~, [14, 1], ~, Int], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Phi, {region: 2}, [16, 25], ~, Int], # 17
  [NumGt, ~, [15, 17], 2, Boolean], # 18
  [Proj, {index: 0}, [2]], # 19
  [Subscript, {kind: array}, [14, 17, 3], ~, Scalar], # 20
  [Coerce, {from_repr: Scalar, to_repr: Num}, [20], ~, Num], # 21
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 22
  [NumGt, ~, [21, 22], ~, Boolean], # 23
  [If, ~, [19, 23], 19], # 24
  [Add, ~, [17, 22], ~, Int], # 25
  [Proj, {index: 1}, [24]], # 26
  [Proj, {index: 0}, [24]], # 27
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 28
  [NumGt, ~, [21, 28], ~, Boolean], # 29
  [EntryDef, {package: main, sigil: $, symbol: total}, ~, ~, Scalar], # 30
  [Coerce, {from_repr: Scalar, to_repr: Num}, [30], ~, Num], # 31
  [Add, ~, [31, 21], ~, Num], # 32
  [If, ~, [27, 29], 27], # 33
  [Proj, {index: 1}, [33]], # 34
  [Increment, ~, [4], ~, Scalar], # 35
  [Proj, {index: 0}, [33]], # 36
  [Assign, ~, [4, 35], 36, Scalar], # 37
  [Region, {head: 33}, [34, 37]], # 38
  [If, ~, [38, 29], 38], # 39
  [Proj, {index: 1}, [39]], # 40
  [Phi, {predecessors: [34, 36], region: 38}, [3, 37], ~, Unknown], # 41
  [Proj, {index: 0}, [39]], # 42
  [EntryWrite, ~, [30, 32, 41], 42, Unknown], # 43
  [Region, {head: 39}, [40, 43]], # 44
  [Region, {head: 24}, [26, 44]], # 45
  [Phi, {predecessors: [40, 42], region: 44}, [41, 43], ~, Unknown], # 46
  [Phi, {predecessors: [26, 27], region: 45}, [3, 46], ~, Unknown]]} # 47
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
  [Phi, {region: 5}, [9, 14], ~, Int], # 13
  [Add, ~, [13, 2], ~, Int], # 14
  [MemStart], # 15
  [Count, ~, [12, 15], ~, Int], # 16
  [Phi, {region: 5}, [15, 28], ~, Unknown], # 17
  [Subscript, {kind: array}, [12, 13, 17], ~, Scalar], # 18
  [NumGt, ~, [16, 13], 5, Boolean], # 19
  [Proj, {index: 0}, [5]], # 20
  [PadAccess, {sigil: $, symbol: in}, [17], ~, Unknown], # 21
  [Assign, ~, [21, 18], 20, Scalar], # 22
  [PadAccess, {sigil: $, symbol: in}, [22], ~, Unknown], # 23
  [Call, {dispatch_kind: direct, name: main::by_ternary, param_names: [], want: scalar}, [23], 22, Unknown], # 24
  [PadAccess, {sigil: $, symbol: in}, [24], ~, Unknown], # 25
  [Call, {dispatch_kind: direct, name: main::by_dor, param_names: [], want: scalar}, [25], 24, Unknown], # 26
  [PadAccess, {sigil: $, symbol: in}, [26], ~, Unknown], # 27
  [Call, {dispatch_kind: direct, name: main::by_dor, param_names: [], want: list}, [27], 26, Unknown], # 28
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 29
  [Coerce, {from_repr: Unknown, to_repr: Str}, [24], ~, Str], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [26], ~, Str], # 31
  [StrEq, ~, [30, 31], ~, Boolean], # 32
  [Constant, {const_type: string, value: "same "}, ~, ~, Str], # 33
  [Constant, {const_type: string, value: "differ "}, ~, ~, Str], # 34
  [TernaryExpr, ~, [32, 33, 34], ~, Str], # 35
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 36
  [Print, ~, [35, 29, 36], 28, Scalar]]} # 37
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
  [Phi, {predecessors: [12, 14], region: 15}, [13, 9], ~, Str], # 16
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
  [Phi, {predecessors: [4, 7], region: 8}, [5, 11], ~, Unknown], # 12
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
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [8], ~, List], # 9
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 9], ~, Str], # 10
  [Constant, {const_type: string, value: " | "}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [5, 7], ~, List], # 13
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [13], ~, List], # 14
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 14], ~, Str], # 15
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
main::find: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: found}, [1], ~, Unknown], # 2
  [Constant, {const_type: string, value: it}, ~, ~, Str], # 3
  [PadAccess, {sigil: $, symbol: want}, ~, ~, Unknown], # 4
  [If, ~, [0, 4], 0], # 5
  [Proj, {index: 0}, [5]], # 6
  [Assign, ~, [2, 3], 6, Str], # 7
  [Proj, {index: 1}, [5]], # 8
  [Region, {head: 5}, [8, 7]], # 9
  [Phi, {predecessors: [8, 6], region: 9}, [1, 7], ~, Unknown], # 10
  [PadAccess, {sigil: $, symbol: found}, [10], ~, Unknown], # 11
  [Call, {dispatch_kind: direct, name: main::load, param_names: []}, [11], 9, Str], # 12
  [Return, ~, [12], 12], # 13
  [ArgsSource, ~, ~, ~, Array], # 14
  [Assign, {targets: 1}, [4, 14], ~, List]]} # 15
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
main::search: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 3], ~, Unknown], # 3
  [PadAccess, {sigil: $, symbol: found}, [3], ~, Unknown], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Phi, {region: 2}, [6, 25], ~, Int], # 7
  [Subscript, {kind: array}, [5, 7, 3], ~, Scalar], # 8
  [Proj, {index: 0}, [2]], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 10
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 11
  [StrEq, ~, [10, 11], ~, Boolean], # 12
  [If, ~, [9, 12], 9], # 13
  [Proj, {index: 0}, [13]], # 14
  [Assign, ~, [4, 8], 14, Scalar], # 15
  [Proj, {index: 1}, [2]], # 16
  [Region, {head: 2}, [16, 15]], # 17
  [Phi, {region: 17}, [3, 15], ~, Unknown], # 18
  [PadAccess, {sigil: $, symbol: found}, [18], ~, Unknown], # 19
  [Call, {dispatch_kind: direct, name: main::load, param_names: []}, [19], 17, Str], # 20
  [Return, ~, [20], 20], # 21
  [Count, ~, [5, 1], ~, Int], # 22
  [NumGt, ~, [22, 7], 2, Boolean], # 23
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 24
  [Add, ~, [7, 24], ~, Int], # 25
  [Proj, {index: 1}, [13]]]} # 26
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
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [13, 18], ~, Str], # 19
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
  [Phi, {predecessors: [9, 13], region: 14}, [10, 6], ~, Unknown]]} # 17
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
main::g: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 2], ~, Str], # 3
  [Return, ~, [3], 0]]} # 4
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
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [6, 8], ~, Unknown], # 9
  [Return, {implicit: true}, [9], 6]]} # 10
main::__PROGRAM__: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [ArrayLiteral, ~, ~, ~, Array], # 4
  [Loop, {bound: entry}, [0], 0], # 5
  [Phi, {region: 5}, [4, 41], ~, Array], # 6
  [ArrayLiteral, ~, ~, ~, Array], # 7
  [Proj, {index: 1}, [5]], # 8
  [Region, {head: 5}, [8]], # 9
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:1, sort_package: main, want: list}, [6], 9, List], # 10
  [Loop, {bound: entry}, [10], 10], # 11
  [Phi, {region: 11}, [7, 57], ~, Array], # 12
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Proj, {index: 1}, [11]], # 15
  [Region, {head: 11}, [15]], # 16
  [Print, ~, [13, 14], 16, Scalar], # 17
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:2, sort_package: main, want: list}, [6], 17, List], # 18
  [Loop, {bound: entry}, [18], 18], # 19
  [Phi, {region: 19}, [3, 46], ~, Array], # 20
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 20], ~, Str], # 21
  [Proj, {index: 1}, [19]], # 22
  [Region, {head: 19}, [22]], # 23
  [Print, ~, [21, 14], 23, Scalar], # 24
  [Return, {implicit: true}, [1], 24], # 25
  [Constant, {const_type: string, value: pear}, ~, ~, Str], # 26
  [Constant, {const_type: string, value: apple}, ~, ~, Str], # 27
  [Constant, {const_type: string, value: fig}, ~, ~, Str], # 28
  [ArrayLiteral, ~, [26, 27, 28], ~, List], # 29
  [MemStart], # 30
  [Count, ~, [29, 30], ~, Int], # 31
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 32
  [Phi, {region: 5}, [32, 40], ~, Int], # 33
  [NumGt, ~, [31, 33], 5, Boolean], # 34
  [Proj, {index: 0}, [5]], # 35
  [Constant, {const_type: string, value: "N"}, ~, ~, Str], # 36
  [Subscript, {kind: array}, [29, 33, 30], ~, Str], # 37
  [Call, {class_name: "N", dispatch_kind: method, name: new, param_names: [], want: list}, [36, 37], 35, Object], # 38
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 39
  [Add, ~, [33, 39], ~, Int], # 40
  [ListAppend, {collector: map}, [6, 38], ~, Array], # 41
  [Phi, {region: 19}, [32, 54], ~, Int], # 42
  [Subscript, {kind: array}, [18, 42, 18], ~, Scalar], # 43
  [Proj, {index: 0}, [19]], # 44
  [Call, {dispatch_kind: method, name: name, param_names: [], want: list}, [43], 44, Unknown], # 45
  [ListAppend, {collector: map}, [20, 45], ~, Array], # 46
  [Phi, {region: 11}, [32, 52], ~, Int], # 47
  [Count, ~, [10, 10], ~, Int], # 48
  [Subscript, {kind: array}, [10, 47, 10], ~, Scalar], # 49
  [Count, ~, [18, 18], ~, Int], # 50
  [NumGt, ~, [50, 42], 19, Boolean], # 51
  [Add, ~, [47, 39], ~, Int], # 52
  [NumGt, ~, [48, 47], 11, Boolean], # 53
  [Add, ~, [42, 39], ~, Int], # 54
  [Proj, {index: 0}, [11]], # 55
  [Call, {dispatch_kind: method, name: name, param_names: [], want: list}, [49], 55, Unknown], # 56
  [ListAppend, {collector: map}, [12, 56], ~, Array]]} # 57
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
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:1, sort_package: main, want: list}, [6], 9, List], # 10
  [Proj, {index: 0}, [8]], # 11
  [Region, {head: 8}, [11, 10]], # 12
  [Phi, {predecessors: [11, 9], region: 12}, [2, 10], ~, Unknown], # 13
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [13], ~, Scalar], # 14
  [Coerce, {from_repr: Scalar, to_repr: Str}, [14], ~, Str], # 15
  [ArrayLiteral, {sigil: "@", symbol: a}, [10], ~, Array], # 16
  [Phi, {predecessors: [11, 9], region: 12}, [6, 16], ~, Array], # 17
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [15, 17], ~, Str], # 18
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
  [Phi, {predecessors: [12, 7], region: 13}, [11, 8], ~, Unknown], # 14
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
  [Phi, {predecessors: [14, 16], region: 17}, [15, 22], ~, Unknown], # 23
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
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [6, 8], ~, Unknown], # 9
  [Return, {implicit: true}, [9], 6]]} # 10
main::__PROGRAM__: {start: 0, returns: [30], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [ArrayLiteral, ~, ~, ~, Array], # 3
  [ArrayLiteral, ~, ~, ~, Array], # 4
  [Loop, {bound: entry}, [0], 0], # 5
  [Phi, {region: 5}, [4, 35], ~, Array], # 6
  [HashLiteral, {sigil: "%", symbol: member}, [6], ~, Hash], # 7
  [Constant, {const_type: string, value: Node}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: n3}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: n1}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: n2}, ~, ~, Str], # 11
  [ArrayLiteral, ~, [9, 10, 11], ~, List], # 12
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 13
  [Phi, {region: 5}, [13, 34], ~, Int], # 14
  [MemStart], # 15
  [Subscript, {kind: array}, [12, 14, 15], ~, Str], # 16
  [Proj, {index: 0}, [5]], # 17
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [], want: list}, [8, 16], 17, Object], # 18
  [Call, {dispatch_kind: builtin, memory_input: true, name: values, param_names: [], want: list}, [7, 18], ~, List], # 19
  [Proj, {index: 1}, [5]], # 20
  [Region, {head: 5}, [20]], # 21
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp_body: main::__PROGRAM__::__SORTCMP__:1, sort_package: main, want: list}, [19], 21, List], # 22
  [Loop, {bound: entry}, [22], 22], # 23
  [Phi, {region: 23}, [3, 40], ~, Array], # 24
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 24], ~, Str], # 25
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 26
  [Proj, {index: 1}, [23]], # 27
  [Region, {head: 23}, [27]], # 28
  [Print, ~, [25, 26], 28, Scalar], # 29
  [Return, {implicit: true}, [1], 29], # 30
  [Count, ~, [12, 15], ~, Int], # 31
  [NumGt, ~, [31, 14], 5, Boolean], # 32
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 33
  [Add, ~, [14, 33], ~, Int], # 34
  [ListAppend, {collector: map}, [6, 16, 18], ~, Array], # 35
  [Phi, {region: 23}, [13, 43], ~, Int], # 36
  [Subscript, {kind: array}, [22, 36, 22], ~, Scalar], # 37
  [Proj, {index: 0}, [23]], # 38
  [Call, {dispatch_kind: method, name: id, param_names: [], want: list}, [37], 38, Unknown], # 39
  [ListAppend, {collector: map}, [24, 39], ~, Array], # 40
  [Count, ~, [22, 22], ~, Int], # 41
  [NumGt, ~, [41, 36], 23, Boolean], # 42
  [Add, ~, [36, 33], ~, Int]]} # 43
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
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [8, 10], ~, Str], # 11
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
  [Phi, {region: 2}, [8, 32], ~, Unknown], # 9
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
  [Count, ~, [6, 8], ~, Int], # 29
  [NumGt, ~, [29, 7], 2, Boolean], # 30
  [Add, ~, [3, 14], ~, Int], # 31
  [Phi, {predecessors: [17, 21], region: 22}, [20, 9], ~, Unknown], # 32
  [Phi, {region: 27}, [9, 32], ~, Unknown], # 33
  [Add, ~, [7, 14], ~, Int], # 34
  [Proj, {index: 1}, [25]]]} # 35
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
main::pairs: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ", "}, ~, ~, Str], # 1
  [PadAccess, {sigil: "@", symbol: o}, ~, ~, Unknown], # 2
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [1, 2], ~, Str], # 3
  [Loop, {bound: each}, [0], 0], # 4
  [Proj, {index: 1}, [4]], # 5
  [Region, {head: 4}, [5]], # 6
  [Return, ~, [3], 6], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Phi, {region: 4}, [8, 40], ~, Int], # 9
  [ArgsSource, ~, ~, ~, Array], # 10
  [MemStart], # 11
  [Count, ~, [10, 11], ~, Int], # 12
  [NumLt, ~, [9, 12], 4, Boolean], # 13
  [Proj, {index: 0}, [4]], # 14
  [Subscript, {kind: array}, [10, 9, 11], ~, Scalar], # 15
  [Defined, ~, [15], ~, Boolean], # 16
  [Coerce, {from_repr: Scalar, to_repr: Str}, [15], ~, Str], # 17
  [RegexMatch, {flags: "", pattern: "^%(\\w+)$"}, [17], ~, Boolean], # 18
  [And, ~, [16, 18], ~, Boolean], # 19
  [If, ~, [14, 19], 14], # 20
  [Constant, {const_type: string, value: "spread "}, ~, ~, Str], # 21
  [RegexCapture, {"n": 1}, [18], ~, Str], # 22
  [Concat, ~, [21, 22], ~, Str], # 23
  [Proj, {index: 0}, [20]], # 24
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 23], 24, Unknown], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 26
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 27
  [Concat, ~, [26, 27], ~, Str], # 28
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 29
  [Add, ~, [9, 29], ~, Int], # 30
  [Subscript, {kind: array}, [10, 30, 11], ~, Scalar], # 31
  [Coerce, {from_repr: Unknown, to_repr: Str}, [31], ~, Str], # 32
  [Concat, ~, [28, 32], ~, Str], # 33
  [Proj, {index: 1}, [20]], # 34
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [2, 33], 34, Unknown], # 35
  [Subtract, ~, [9, 29], ~, Int], # 36
  [Region, {head: 4}, [35, 25]], # 37
  [Phi, {predecessors: [34, 24], region: 37}, [9, 36], ~, Int], # 38
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 39
  [Add, ~, [38, 39], ~, Int]]} # 40
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
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [7], ~, List], # 8
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 8], ~, Str], # 9
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
  [Phi, {predecessors: [7, 12], region: 23}, [14, 22], ~, Unknown], # 25
  [Phi, {predecessors: [17, 19], region: 21}, [14, 20], ~, Unknown], # 26
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
  [Phi, {predecessors: [17, 14], region: 18}, [6, 16], ~, Unknown], # 19
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 20
  [Subscript, {kind: hash}, [7, 20], ~, Scalar], # 21
  [Subscript, {kind: hash}, [7, 20, 19], 18, Scalar], # 22
  [Defined, ~, [22], ~, Boolean], # 23
  [If, ~, [22, 23], 22], # 24
  [Proj, {index: 1}, [24]], # 25
  [Assign, ~, [21, 1], 25, Undef], # 26
  [Proj, {index: 0}, [24]], # 27
  [Region, {head: 24}, [27, 26]], # 28
  [Phi, {predecessors: [27, 25], region: 28}, [19, 26], ~, Unknown], # 29
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 30
  [If, ~, [28, 22], 28], # 31
  [Proj, {index: 1}, [31]], # 32
  [Assign, ~, [21, 30], 32, Int], # 33
  [Proj, {index: 0}, [31]], # 34
  [Region, {head: 31}, [34, 33]], # 35
  [Phi, {predecessors: [34, 32], region: 35}, [29, 33], ~, Unknown], # 36
  [Subscript, {kind: hash}, [7, 20, 36], 35, Scalar], # 37
  [Defined, ~, [37], ~, Boolean], # 38
  [If, ~, [37, 38], 37], # 39
  [Proj, {index: 1}, [39]], # 40
  [Assign, ~, [21, 1], 40, Undef], # 41
  [Proj, {index: 0}, [39]], # 42
  [Region, {head: 39}, [42, 41]], # 43
  [Phi, {predecessors: [42, 40], region: 43}, [36, 41], ~, Unknown], # 44
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 45
  [If, ~, [43, 37], 43], # 46
  [Proj, {index: 0}, [46]], # 47
  [Assign, ~, [21, 45], 47, Int], # 48
  [Proj, {index: 1}, [46]], # 49
  [Region, {head: 46}, [49, 48]], # 50
  [Phi, {predecessors: [49, 47], region: 50}, [44, 48], ~, Unknown], # 51
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
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 63], ~, Str], # 64
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 65
  [Phi, {predecessors: [55, 58], region: 61}, [51, 60], ~, Unknown], # 66
  [Count, ~, [4, 66], ~, Int], # 67
  [Coerce, {from_repr: Int, to_repr: Str}, [67], ~, Str], # 68
  [Subscript, {kind: array}, [4, 5, 66], ~, Scalar], # 69
  [Coerce, {from_repr: Unknown, to_repr: Str}, [69], ~, Str], # 70
  [Concat, ~, [65, 70], ~, Str], # 71
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 72
  [Concat, ~, [71, 72], ~, Str], # 73
  [Proj, {index: 1}, [62]], # 74
  [Region, {head: 62}, [74]], # 75
  [Print, ~, [64, 65, 68, 73], 75, Scalar], # 76
  [Return, {implicit: true}, [1], 76], # 77
  [Call, {dispatch_kind: builtin, memory_input: true, name: keys, param_names: [], want: list}, [7, 66], ~, List], # 78
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [78], ~, List], # 79
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 80
  [Phi, {region: 62}, [80, 91], ~, Int], # 81
  [Subscript, {kind: array}, [79, 81, 66], ~, Scalar], # 82
  [Subscript, {kind: hash}, [7, 82, 66], ~, Scalar], # 83
  [Coerce, {from_repr: Unknown, to_repr: Str}, [83], ~, Str], # 84
  [Coerce, {from_repr: Unknown, to_repr: Str}, [82], ~, Str], # 85
  [Constant, {const_type: string, value: "="}, ~, ~, Str], # 86
  [Concat, ~, [85, 86], ~, Str], # 87
  [Concat, ~, [87, 84], ~, Str], # 88
  [ListAppend, {collector: map}, [63, 88], ~, Array], # 89
  [Count, ~, [79, 66], ~, Int], # 90
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
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [13, 14], ~, Str], # 15
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
  [Phi, {predecessors: [10, 8], region: 11}, [3, 9], ~, Unknown]]} # 16
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
  [Call, {dispatch_kind: builtin, name: reverse, param_names: []}, [8], ~, List], # 9
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Print, ~, [12], 0, Scalar], # 13
  [Return, {implicit: true}, [1], 13], # 14
  [ArrayLiteral, {sigil: "@", symbol: b}, [9], ~, Array]]} # 15
```
