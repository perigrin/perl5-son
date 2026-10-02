# Gaps chalk's own test suite found

Three programs reduced from failures in chalk's test suite run against a
lib/ that B::SoN had translated and emitted back. In each, a write into a
class field or an ADJUST block was dropped without a word, and the object
came back built wrong: the corpus had no case for it. Added here by B::SoN
and sent to pvm to place in its tiers; this file is replaced when the
corpus is next copied from pvm.

**Tier 11 oo.** Introduces nothing. Depends on 11_oo.

## A string built into a field

perl fuses the build and the store into one op -- `$log .= "<$x>"` and
`$log = "[$log]"` are each a `multiconcat` writing the field's slot, with
no assignment op to see. A reader that takes the slot for a lexical
rebinds a name and never writes the field. Both forms, in a method and in
an ADJUST block.

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
Log::__ADJUST_0: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Log}, ~, 0, Str], # 1
  [Constant, {const_type: string, value: start}, ~, ~, Str], # 2
  [Concat, ~, [1, 2], ~, Str], # 3
  [FieldAccess, {field_index: 0, field_stash: Log}, ~, ~, Str], # 4
  [Assign, ~, [4, 3], 1, Str], # 5
  [Return, ~, [3], 5]]} # 6
Log::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Return, ~, [1], 0]]} # 2
Log::add: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Unknown], # 1
  [FieldAccess, {field_index: 0, field_stash: Log}, ~, ~, Str], # 2
  [FieldAccess, {field_index: 0, field_stash: Log}, ~, 0, Str], # 3
  [Constant, {const_type: string, value: "<"}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Str], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Concat, ~, [5, 7], ~, Str], # 8
  [Constant, {const_type: string, value: ">"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Assign, ~, [2, 10], 3, Str], # 11
  [Return, ~, [1], 11]]} # 12
Log::close: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Log}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 3
  [Concat, ~, [2, 3], ~, Str], # 4
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Assign, ~, [1, 6], 0, Str], # 7
  [Return, ~, [1], 7]]} # 8
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: Log, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 2
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 3
  [Call, {class_name: Log, dispatch_kind: method, name: add, param_names: []}, [2, 3], 2, Unknown], # 4
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 5
  [Call, {class_name: Log, dispatch_kind: method, name: add, param_names: []}, [4, 5], 4, Unknown], # 6
  [Call, {class_name: Log, dispatch_kind: method, name: close, param_names: []}, [6], 6, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [8, 9], 7, Scalar], # 10
  [Return, ~, [1], 10]]} # 11
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

## `//=` into a field from a call

The right side of `//=` runs only when the field is undefined, and the
store happens only then. Here it is a method call, so running it on the
other path is observable in the call count. chalk's IR nodes default their
operands this way in ADJUST.

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
Node::__ADJUST_0: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 1, field_stash: Node}, ~, 0, Scalar], # 1
  [Defined, ~, [1], ~, Boolean], # 2
  [If, ~, [1, 2], 1], # 3
  [Proj, {index: 0}, [3]], # 4
  [FieldAccess, {field_index: 1, field_stash: Node}, ~, ~, Scalar], # 5
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 6
  [Proj, {index: 1}, [3]], # 7
  [Call, {class_name: Node, dispatch_kind: method, name: first, param_names: []}, [6], 7, Scalar], # 8
  [Assign, ~, [5, 8], 8, Scalar], # 9
  [Region, {head: 3}, [4, 9]], # 10
  [FieldAccess, {field_index: 1, field_stash: Node}, ~, 10, Scalar], # 11
  [Return, ~, [11], 11]]} # 12
Node::__DEFAULT_1: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
Node::__DEFAULT_2: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Node::calls: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 2, field_stash: Node}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Node::first: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Node}, ~, ~, Unknown], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2, 3], ~, Scalar], # 4
  [FieldAccess, {field_index: 2, field_stash: Node}, ~, ~, Int], # 5
  [FieldAccess, {field_index: 2, field_stash: Node}, ~, 0, Int], # 6
  [Increment, ~, [6], ~, Scalar], # 7
  [Assign, ~, [5, 7], 6, Scalar], # 8
  [Return, ~, [4], 8]]} # 9
Node::left: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 1, field_stash: Node}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ","}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "8"}, ~, ~, Int], # 4
  [ArrayLiteral, ~, [3, 4], 0, ArrayRef], # 5
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [inputs]}, [5], 5, Object], # 6
  [ArrayLiteral, ~, [3, 4], 6, ArrayRef], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Call, {class_name: Node, dispatch_kind: method, name: new, param_names: [inputs, left]}, [7, 8], 7, Object], # 9
  [Call, {class_name: Node, dispatch_kind: method, name: left, param_names: []}, [6], 9, Scalar], # 10
  [Call, {class_name: Node, dispatch_kind: method, name: calls, param_names: []}, [6], 10, Int], # 11
  [Call, {class_name: Node, dispatch_kind: method, name: left, param_names: []}, [9], 11, Scalar], # 12
  [Call, {class_name: Node, dispatch_kind: method, name: calls, param_names: []}, [9], 12, Int], # 13
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 10, 11, 12, 13], ~, Str], # 14
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Print, ~, [14, 15], 13, Scalar], # 16
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

## A subclass's ADJUST when its parent has one

Every ADJUST block of the class chain runs, parent's first. A reader that
separates the class's own blocks from the inherited ones by counting the
parent's must count them -- the class's own block is the one this case
watches.

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
Base::__ADJUST_0: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Base}, ~, 0, Str], # 1
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 2
  [Concat, ~, [1, 2], ~, Str], # 3
  [FieldAccess, {field_index: 0, field_stash: Base}, ~, ~, Str], # 4
  [Assign, ~, [4, 3], 1, Str], # 5
  [Return, ~, [3], 5]]} # 6
Base::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Return, ~, [1], 0]]} # 2
Base::mark: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [FieldAccess, {field_index: 0, field_stash: Base}, ~, ~, Str], # 2
  [FieldAccess, {field_index: 0, field_stash: Base}, ~, 0, Str], # 3
  [Parameter, {index: 0, name: $c, sigil: $}, ~, ~, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Concat, ~, [3, 5], ~, Str], # 6
  [Assign, ~, [2, 6], 3, Str], # 7
  [Return, ~, [1], 7]]} # 8
Base::trail: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Base}, ~, ~, Str], # 1
  [Return, ~, [1], 0]]} # 2
Derived::__ADJUST_0: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 1
  [Constant, {const_type: string, value: d}, ~, ~, Str], # 2
  [Call, {class_name: Derived, dispatch_kind: method, name: mark, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {class_name: Derived, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 2
  [Call, {class_name: Derived, dispatch_kind: method, name: trail, param_names: []}, [2], 2, Unknown], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Return, ~, [1], 6]]} # 7
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
