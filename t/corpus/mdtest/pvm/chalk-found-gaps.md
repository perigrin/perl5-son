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
  [Exists, ~, [2, 6, 7], ~, Boolean], # 22
  [If, ~, [21, 22], 21], # 23
  [Proj, {index: 0}, [23]], # 24
  [Proj, {index: 1}, [23]], # 25
  [Region, ~, [14, 24, 25]], # 26
  [Phi, {predecessors: [14, 24, 25], region: 26}, [1, 8, 10], ~, Scalar], # 27
  [Return, ~, [27], 26], # 28
  [ArgsSource, ~, ~, ~, Array], # 29
  [Assign, ~, [4, 29], ~, List]]} # 30
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
  [Assign, ~, [3, 1, 6], ~, List]]} # 7
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
  [Phi, {predecessors: [58, 47], region: 59}, [57, 48], ~, Unknown], # 60
  [ArgsSource, ~, ~, ~, Array], # 61
  [Assign, ~, [19, 8, 61], ~, List], # 62
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
  [Assign, ~, [9, 30, 37], ~, List], # 38
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
  [Delete, ~, [3, 4, 5], 0, Scalar], # 6
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
  [Assign, ~, [1, 5, 11], ~, List]]} # 12
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
  [Assign, ~, [2, 11], ~, List]]} # 12
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
  [Assign, ~, [2, 10], ~, List]]} # 11
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
main::tally: {start: 0, returns: [44], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {shared: 1, sigil: $, symbol: seen}, [1], ~, Unknown], # 2
  [Increment, ~, [2], ~, Scalar], # 3
  [Loop, {bound: entry}, [0], 0], # 4
  [Proj, {index: 0}, [4]], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Phi, {region: 4}, [7, 47], ~, Int], # 8
  [Subscript, {kind: array}, [6, 8, 1], ~, Scalar], # 9
  [Coerce, {from_repr: Scalar, to_repr: Num}, [9], ~, Num], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [NumGt, ~, [10, 11], ~, Boolean], # 12
  [If, ~, [5, 12], 5], # 13
  [Proj, {index: 0}, [13]], # 14
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 15
  [NumGt, ~, [10, 15], ~, Boolean], # 16
  [If, ~, [14, 16], 14], # 17
  [Proj, {index: 0}, [17]], # 18
  [Assign, ~, [2, 3], 18, Scalar], # 19
  [Proj, {index: 1}, [17]], # 20
  [Region, {head: 17}, [20, 19]], # 21
  [Phi, {predecessors: [20, 18], region: 21}, [1, 19], ~, Unknown], # 22
  [EntryDef, {package: main, sigil: $, symbol: total}, ~, ~, Scalar], # 23
  [Coerce, {from_repr: Scalar, to_repr: Num}, [23], ~, Num], # 24
  [Add, ~, [24, 10], ~, Num], # 25
  [If, ~, [21, 16], 21], # 26
  [Proj, {index: 0}, [26]], # 27
  [EntryWrite, ~, [23, 25, 22], 27, Unknown], # 28
  [Proj, {index: 1}, [26]], # 29
  [Region, {head: 26}, [29, 28]], # 30
  [Phi, {predecessors: [29, 27], region: 30}, [22, 28], ~, Unknown], # 31
  [Proj, {index: 1}, [13]], # 32
  [Region, {head: 13}, [32, 30]], # 33
  [Phi, {predecessors: [32, 14], region: 33}, [1, 31], ~, Unknown], # 34
  [PadAccess, {shared: 1, sigil: $, symbol: seen}, [34], ~, Str], # 35
  [Coerce, {from_repr: Unknown, to_repr: Str}, [35], ~, Str], # 36
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 37
  [Concat, ~, [36, 37], ~, Str], # 38
  [EntryDef, {package: main, sigil: $, symbol: total}, [34], ~, Scalar], # 39
  [Coerce, {from_repr: Unknown, to_repr: Str}, [39], ~, Str], # 40
  [Concat, ~, [38, 40], ~, Str], # 41
  [Proj, {index: 1}, [4]], # 42
  [Region, {head: 4}, [42]], # 43
  [Return, ~, [41], 43], # 44
  [Count, ~, [6, 1], ~, Int], # 45
  [NumGt, ~, [45, 8], 4, Boolean], # 46
  [Add, ~, [8, 11], ~, Int]]} # 47
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
  [Subscript, {kind: array}, [12, 13, 15], ~, Scalar], # 17
  [NumGt, ~, [16, 13], 5, Boolean], # 18
  [Proj, {index: 0}, [5]], # 19
  [PadAccess, {sigil: $, symbol: in}, [15], ~, Unknown], # 20
  [Assign, ~, [20, 17], 19, Scalar], # 21
  [PadAccess, {sigil: $, symbol: in}, [21], ~, Unknown], # 22
  [Call, {dispatch_kind: direct, name: main::by_ternary, param_names: [], want: scalar}, [22], 21, Unknown], # 23
  [PadAccess, {sigil: $, symbol: in}, [23], ~, Unknown], # 24
  [Call, {dispatch_kind: direct, name: main::by_dor, param_names: [], want: scalar}, [24], 23, Unknown], # 25
  [Coerce, {from_repr: Unknown, to_repr: Str}, [23], ~, Str], # 26
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 27
  [PadAccess, {sigil: $, symbol: in}, [25], ~, Unknown], # 28
  [Call, {dispatch_kind: direct, name: main::by_dor, param_names: [], want: list}, [28], 25, Unknown], # 29
  [StrEq, ~, [26, 27], ~, Boolean], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [29], ~, Str], # 31
  [Constant, {const_type: string, value: "same "}, ~, ~, Str], # 32
  [Constant, {const_type: string, value: "differ "}, ~, ~, Str], # 33
  [TernaryExpr, ~, [30, 32, 33], ~, Str], # 34
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 35
  [Print, ~, [34, 31, 35], 29, Scalar]]} # 36
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
  [Assign, ~, [1, 22], ~, List]]} # 23
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
  [Assign, ~, [1, 22], ~, List]]} # 23
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
  [Assign, ~, [3, 34], ~, List], # 35
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
  [Assign, ~, [2, 16], ~, List]]} # 17
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
  [Assign, ~, [3, 15], ~, List]]} # 16
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
  [Assign, ~, [1, 15], ~, List]]} # 16
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
  [Assign, ~, [2, 7], ~, List]]} # 8
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
  [Assign, ~, [2, 18], ~, List]]} # 19
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
  [Assign, ~, [4, 14], ~, List]]} # 15
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
main::search: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: found}, [1], ~, Unknown], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [Loop, {bound: entry}, [0], 0], # 5
  [Phi, {region: 5}, [4, 24], ~, Int], # 6
  [Subscript, {kind: array}, [3, 6, 1], ~, Scalar], # 7
  [Proj, {index: 0}, [5]], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 9
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 10
  [StrEq, ~, [9, 10], ~, Boolean], # 11
  [If, ~, [8, 11], 8], # 12
  [Proj, {index: 0}, [12]], # 13
  [Assign, ~, [2, 7], 13, Scalar], # 14
  [Proj, {index: 1}, [5]], # 15
  [Region, {head: 5}, [15, 14]], # 16
  [Phi, {region: 16}, [1, 14], ~, Unknown], # 17
  [PadAccess, {sigil: $, symbol: found}, [17], ~, Unknown], # 18
  [Call, {dispatch_kind: direct, name: main::load, param_names: []}, [18], 16, Str], # 19
  [Return, ~, [19], 19], # 20
  [Count, ~, [3, 1], ~, Int], # 21
  [NumGt, ~, [21, 6], 5, Boolean], # 22
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 23
  [Add, ~, [6, 23], ~, Int], # 24
  [Proj, {index: 1}, [12]]]} # 25
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
  [Assign, ~, [1, 6, 17], ~, List]]} # 18
```

