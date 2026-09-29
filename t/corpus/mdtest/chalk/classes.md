# Classes

`feature class` MOP idioms: class declaration, fields, methods, ADJUST blocks,
and inheritance via `:isa`.

All idioms in this topic are `L: GREEN` — `feature class` is statically/lexically
declared, so an object is a static `{class*, fields}` struct, a field read is a
known offset load, and method dispatch is a known per-class vtable slot + indirect
call (no runtime `@ISA` mutation in the subset). These are all runtime-free (RF).

## class-simple

A minimal `class C {}` with no fields or methods. Instantiating it produces an
object whose `ref()` is the class name. Because the class is statically declared,
the object is a static `{class*, fields}` struct — runtime-free.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Empty { }
my $e = Empty->new;
say(ref($e));
```

```behavior
stdout: Empty\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cls    = MOP::Class(name: "Empty")
%new_e  = Call(dispatch_kind: "method", name: "new", class: "Empty") :Object
%result = RefType(%new_e) :Str
%nl = Constant("\n") :Str
%p  = Print(%result, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Call, {class_name: Empty, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 1
  [RefType, ~, [1], ~, Str], # 2
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 3
  [Print, ~, [2, 3], 1, Scalar], # 4
  [Return, ~, [4], 4]]} # 5
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## field-basic

A field declared with `:param` requires the constructor to accept a named
argument. A method that returns the field value reads from the object struct at a
known offset — a typed struct field, not a Scalar SV* slot. The read is
runtime-free.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Animal {
    field $name :param;
    method name { return $name }
}
my $a = Animal->new(name => 'cat');
say($a->name);
```

```behavior
stdout: cat\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cls    = MOP::Class(name: "Animal")
%mf     = MOP::Field(class: %cls, name: "name", fieldix: 0, param: true, reader: false, has_default: false, type: "Str")
%fa     = FieldAccess(field_index: 0, field_stash: "Animal") :Str
%mi     = MOP::Method(class: %cls, name: "name", body: %fa, return_repr: "Str")
%nval   = Constant("cat") :Str
%new_a  = Call(%nval, dispatch_kind: "method", name: "new", class: "Animal", param_names: "name") :Object
%result = Call(%new_a, dispatch_kind: "method", name: "name", class: "Animal") :Str
%nl = Constant("\n") :Str
%p  = Print(%result, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
Animal::name: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Animal}, ~, ~, Unknown], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: cat}, ~, ~, Str], # 1
  [Call, {class_name: Animal, dispatch_kind: method, name: new, param_names: [name]}, [1], 0, Object], # 2
  [Call, {class_name: Animal, dispatch_kind: method, name: name, param_names: []}, [2], 2, Unknown], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## field-str-default

A `:param` field with a Str DEFAULT. Constructed with no argument, the field
takes its default value. The default is boxed into a %StrPair the same way a
supplied Str `:param` is, via the shared field-payload store helper — earlier
only Int defaults lowered and a Str default GAPped (019f4512).

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Greeter {
    field $msg :param = "hi";
    method hello { return $msg }
}
my $g = Greeter->new;
say($g->hello);
```

```behavior
stdout: hi\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cls    = MOP::Class(name: "Greeter")
%mf     = MOP::Field(class: %cls, name: "msg", fieldix: 0, param: true, reader: false, has_default: true, type: "Str")
%fa     = FieldAccess(field_index: 0, field_stash: "Greeter") :Str
%mi     = MOP::Method(class: %cls, name: "hello", body: %fa, return_repr: "Str")
%new_g  = Call(dispatch_kind: "method", name: "new", class: "Greeter") :Object
# `:Scalar`, NOT `:Str`. A `:param` field admits ANYTHING a caller
# passes -- measured, `P->new(msg => [1,2])` hands back an ArrayRef --
# so the field's type is the join of its default with what :param
# accepts, and the method returning it inherits that. The Str is a true
# fact about the INITIALISER and a false one about the FIELD.
%result = Call(%new_g, dispatch_kind: "method", name: "hello", class: "Greeter") :Scalar
%nl = Constant("\n") :Str
%p  = Print(%result, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
Greeter::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: hi}, ~, ~, Str], # 1
  [Return, ~, [1], 0]]} # 2
Greeter::hello: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Greeter}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Call, {class_name: Greeter, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 1
  [Call, {class_name: Greeter, dispatch_kind: method, name: hello, param_names: []}, [1], 1, Scalar], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## field-attrs

Fields may combine `:param` (constructor binding) and `:reader` (auto-generated
accessor method). The `:reader` attribute tells the MOP to synthesize a method
that returns the field value — a known vtable slot returning a known struct
offset load, statically resolved. Runtime-free.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Pair {
    field $left  :param :reader;
    field $right :param :reader;
}
my $p = Pair->new(left => 10, right => 20);
say($p->left + $p->right);
```

```behavior
stdout: 30\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cls    = MOP::Class(name: "Pair")
%mf_l   = MOP::Field(class: %cls, name: "left",  fieldix: 0, param: true, reader: true, has_default: false, type: "Int")
%mf_r   = MOP::Field(class: %cls, name: "right", fieldix: 1, param: true, reader: true, has_default: false, type: "Int")
%lval   = Constant(10) :Int
%rval   = Constant(20) :Int
%new_p  = Call(%lval, %rval, dispatch_kind: "method", name: "new", class: "Pair", param_names: "left,right") :Object
%lr     = Call(%new_p, dispatch_kind: "method", name: "left", class: "Pair")  :Int
%rr     = Call(%new_p, dispatch_kind: "method", name: "right", class: "Pair") :Int
%result = Add(%lr, %rr) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
Pair::left: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Pair}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
Pair::right: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 1, field_stash: Pair}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "20"}, ~, ~, Int], # 2
  [Call, {class_name: Pair, dispatch_kind: method, name: new, param_names: [left, right]}, [1, 2], 0, Object], # 3
  [Call, {class_name: Pair, dispatch_kind: method, name: left, param_names: []}, [3], 3, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Call, {class_name: Pair, dispatch_kind: method, name: right, param_names: []}, [3], 4, Scalar], # 6
  [Coerce, {from_repr: Scalar, to_repr: Num}, [6], ~, Num], # 7
  [Add, ~, [5, 7], ~, Num], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [9, 10], 6, Scalar], # 11
  [Return, ~, [11], 11]]} # 12
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## field-attrs-custom-param

A `:reader` field whose `:param(NAME)` gives the constructor parameter a name
DIFFERENT from the field variable (`field $left :param(alpha) :reader`). The
reader accessor is still named after the VARIABLE (`left`), not the param. The
field's variable name must come from the class's own field metadata
(`xhv_class_fields`), not `$` . param_name -- else the reader is mis-detected and
emitted as a shadowing user-method that GAPs (zhi 019f4625). Neither field is
referenced by any method or ADJUST body, which is exactly the case that exposed
the bug.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Pair {
    field $left  :param(alpha) :reader;
    field $right :param(beta)  :reader;
}
my $p = Pair->new(alpha => 10, beta => 20);
say($p->left - $p->right);
```

```behavior
stdout: -10\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cls    = MOP::Class(name: "Pair")
%mf_l   = MOP::Field(class: %cls, name: "left",  fieldix: 0, param: true, reader: true, has_default: false, type: "Int")
%mf_r   = MOP::Field(class: %cls, name: "right", fieldix: 1, param: true, reader: true, has_default: false, type: "Int")
%lval   = Constant(10) :Int
%rval   = Constant(20) :Int
%new_p  = Call(%lval, %rval, dispatch_kind: "method", name: "new", class: "Pair", param_names: "alpha,beta") :Object
%lr     = Call(%new_p, dispatch_kind: "method", name: "left", class: "Pair")  :Int
%rr     = Call(%new_p, dispatch_kind: "method", name: "right", class: "Pair") :Int
%result = Subtract(%lr, %rr) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
Pair::left: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Pair}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
Pair::right: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 1, field_stash: Pair}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "20"}, ~, ~, Int], # 2
  [Call, {class_name: Pair, dispatch_kind: method, name: new, param_names: [alpha, beta]}, [1, 2], 0, Object], # 3
  [Call, {class_name: Pair, dispatch_kind: method, name: left, param_names: []}, [3], 3, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Call, {class_name: Pair, dispatch_kind: method, name: right, param_names: []}, [3], 4, Scalar], # 6
  [Coerce, {from_repr: Scalar, to_repr: Num}, [6], ~, Num], # 7
  [Subtract, ~, [5, 7], ~, Num], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [9, 10], 6, Scalar], # 11
  [Return, ~, [11], 11]]} # 12
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## method-simple

A method that ignores `$self` and returns a literal value is the simplest
non-trivial method. The dispatch path is a known per-class vtable slot + indirect
call (static, no runtime `@ISA` mutation), so it is runtime-free.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Greeter {
    method greet { return 42 }
}
my $g = Greeter->new;
say($g->greet);
```

```behavior
stdout: 42\n
return: Bool:1
context: scalar
```

Measured 2026-08-30 against producer `8c15e32`: the producer emits this cleanly
-- a `Parameter` node carrying the bound argument -- and the BACKEND refuses it.

L: GAP: LLVM backend: cannot lower op=Parameter (not in literal-arithmetic slice)

This is a DIFFERENT blocker from subs.md F17, and the difference is the useful
part. F17 (`sub f($x)`) LOWERS and silently produces no output: the call site
never binds the argument, so the callee reads nothing. Here the argument IS
bound -- the producer built a `Parameter` node for it -- and the backend has no
lowering for that op at all. One is a missing call-site binding; the other is a
missing node lowering. A fix for either leaves the other standing.

Together they are the whole parameterised-call story, and at 920 method uses
plus 94 sub uses they are the largest single idiom gap between the corpus and
`lib/Chalk/`.

```ir
%start = Start()
%cls    = MOP::Class(name: "Greeter")
%body   = Constant(42) :Int
%mi     = MOP::Method(class: %cls, name: "greet", body: %body, return_repr: "Int")
%new_g  = Call(dispatch_kind: "method", name: "new", class: "Greeter") :Object
%result = Call(%new_g, dispatch_kind: "method", name: "greet", class: "Greeter") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
Greeter::greet: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "42"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Call, {class_name: Greeter, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 1
  [Call, {class_name: Greeter, dispatch_kind: method, name: greet, param_names: []}, [1], 1, Int], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## method-call

A method that mutates a field (`$n += 1`) followed by a method that reads the
same field exercises the full object-mutation + read sequence. The field write is
a store to a known struct offset and the read is a load from the same offset —
typed struct fields, not Scalar SV* slots. Both are runtime-free.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method inc { $n += 1 }
    method val { return $n }
}
my $c = Counter->new(n => 10);
$c->inc;
say($c->val);
```

```behavior
stdout: 11\n
return: Bool:1
context: scalar
```

```ir
%cls       = MOP::Class(name: "Counter")
%mf_n      = MOP::Field(class: %cls, name: "n", fieldix: 0, param: true, reader: false, has_default: false, type: "Int")
%fa_n_lv   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%fa_n_rd   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%one       = Constant(1) :Int
%n_plus1   = Add(%fa_n_rd, %one) :Int
%fw_n      = Assign(%fa_n_lv, %n_plus1) :Int
%mi_inc    = MOP::Method(class: %cls, name: "inc", body: %fw_n, return_repr: "Int")
%fa_n2     = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%mi_val    = MOP::Method(class: %cls, name: "val", body: %fa_n2, return_repr: "Int")
%ten       = Constant(10) :Int
%new_c     = Call(%ten, dispatch_kind: "method", name: "new", class: "Counter", param_names: "n") :Object
%inc_call  = Call(%new_c, dispatch_kind: "method", name: "inc", class: "Counter") :Int
%result    = Call(%new_c, dispatch_kind: "method", name: "val", class: "Counter") :Int
control: %inc_call -> %result
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
L: GREEN
```

```son
Counter::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Counter::inc: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Counter}, ~, ~, Scalar], # 1
  [Coerce, {from_repr: Scalar, to_repr: Num}, [1], ~, Num], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Add, ~, [2, 3], ~, Num], # 4
  [Assign, ~, [1, 4], 0, Num], # 5
  [Return, ~, [4], 5]]} # 6
Counter::val: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Counter}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 1
  [Call, {class_name: Counter, dispatch_kind: method, name: new, param_names: ["n"]}, [1], 0, Object], # 2
  [Call, {class_name: Counter, dispatch_kind: method, name: inc, param_names: []}, [2], 2, Num], # 3
  [Call, {class_name: Counter, dispatch_kind: method, name: val, param_names: []}, [2], 3, Scalar], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, Scalar], # 7
  [Return, ~, [7], 7]]} # 8
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## method-call-chain

A CHAIN of two void mutating calls followed by a read: `$c->inc; $c->inc;
$c->val`. Each `inc` stores the incremented field back, and the two stores are
memory-ordered (call 2 observes call 1's store), so `val` reads the accumulated
value. The non-tail `inc` is a void statement effect threaded via control_in;
without ordering both it and the field mutation would be lost (zhi 019f2dee).

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method inc { $n += 1 }
    method val { return $n }
}
my $c = Counter->new(n => 10);
$c->inc;
$c->inc;
say($c->val);
```

```behavior
stdout: 12\n
return: Bool:1
context: scalar
```

```ir
%cls       = MOP::Class(name: "Counter")
%mf_n      = MOP::Field(class: %cls, name: "n", fieldix: 0, param: true, reader: false, has_default: false, type: "Int")
%ten       = Constant(10) :Int
%new_c     = Call(%ten, dispatch_kind: "method", name: "new", class: "Counter", param_names: "n") :Object
%inc1      = Call(%new_c, dispatch_kind: "method", name: "inc", class: "Counter") :Int
%inc2      = Call(%new_c, dispatch_kind: "method", name: "inc", class: "Counter") :Int
%result    = Call(%new_c, dispatch_kind: "method", name: "val", class: "Counter") :Int
control: %inc1 -> %inc2 -> %result
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
L: GREEN
```

```son
Counter::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Counter::inc: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Counter}, ~, ~, Scalar], # 1
  [Coerce, {from_repr: Scalar, to_repr: Num}, [1], ~, Num], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Add, ~, [2, 3], ~, Num], # 4
  [Assign, ~, [1, 4], 0, Num], # 5
  [Return, ~, [4], 5]]} # 6
Counter::val: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Counter}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 1
  [Call, {class_name: Counter, dispatch_kind: method, name: new, param_names: ["n"]}, [1], 0, Object], # 2
  [Call, {class_name: Counter, dispatch_kind: method, name: inc, param_names: []}, [2], 2, Num], # 3
  [Call, {class_name: Counter, dispatch_kind: method, name: inc, param_names: []}, [2], 3, Num], # 4
  [Call, {class_name: Counter, dispatch_kind: method, name: val, param_names: []}, [2], 4, Scalar], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, Scalar], # 8
  [Return, ~, [8], 8]]} # 9
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## class-isa

A child class that inherits a method from a parent class via `:isa(Parent)`.
The inherited-method lookup is a static vtable/MRO resolution at compile time
(classes are lexically declared, no runtime `@ISA` mutation in the subset), so it
is runtime-free.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Base { method kind { return 'base' } }
class Child :isa(Base) { }
my $c = Child->new;
say($c->kind);
```

```behavior
stdout: base\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%base_cls  = MOP::Class(name: "Base")
%kind_body = Constant("base") :Str
%mi_kind   = MOP::Method(class: %base_cls, name: "kind", body: %kind_body, return_repr: "Str")
%child_cls = MOP::Class(name: "Child", parent: "Base")
%new_c     = Call(dispatch_kind: "method", name: "new", class: "Child") :Object
%result    = Call(%new_c, dispatch_kind: "method", name: "kind", class: "Child") :Str
%nl = Constant("\n") :Str
%p  = Print(%result, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
Base::kind: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: base}, ~, ~, Str], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Call, {class_name: Child, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 1
  [Call, {class_name: Child, dispatch_kind: method, name: kind, param_names: []}, [1], 1, Unknown], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## adjust

An `ADJUST` block runs after the constructor has bound all `:param` fields. It
can compute derived fields from the constructor arguments. ADJUST is constructor
code writing known struct field offsets — typed struct fields, not Scalar SV*
slots — so it is runtime-free.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Box {
    field $val    :param = 0;
    field $double;
    ADJUST { $double = $val * 2 }
    method double { return $double }
}
my $b = Box->new(val => 7);
say($b->double);
```

```behavior
stdout: 14\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cls       = MOP::Class(name: "Box")
%mf_val    = MOP::Field(class: %cls, name: "val",    fieldix: 0, param: true,  reader: false, has_default: false, type: "Int")
%mf_dbl    = MOP::Field(class: %cls, name: "double", fieldix: 1, param: false, reader: false, has_default: false, type: "Int")
%fa_val    = FieldAccess(field_index: 0, field_stash: "Box") :Int
%two       = Constant(2) :Int
%dbl_val   = Multiply(%fa_val, %two) :Int
%fa_dbl_lv = FieldAccess(field_index: 1, field_stash: "Box") :Int
%fw_dbl    = Assign(%fa_dbl_lv, %dbl_val) :Int
%adj       = MOP::Adjust(class: %cls, body: [%fw_dbl])
%fa_dbl    = FieldAccess(field_index: 1, field_stash: "Box") :Int
%mi_dbl    = MOP::Method(class: %cls, name: "double", body: %fa_dbl, return_repr: "Int")
%seven     = Constant(7) :Int
%new_b     = Call(%seven, dispatch_kind: "method", name: "new", class: "Box", param_names: "val") :Object
%result    = Call(%new_b, dispatch_kind: "method", name: "double", class: "Box") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
Box::__ADJUST_0: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Box}, ~, ~, Scalar], # 1
  [Coerce, {from_repr: Scalar, to_repr: Num}, [1], ~, Num], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Multiply, ~, [2, 3], ~, Num], # 4
  [FieldAccess, {field_index: 1, field_stash: Box}, ~, ~, Unknown], # 5
  [Assign, ~, [5, 4], 0, Num], # 6
  [Return, ~, [4], 6]]} # 7
Box::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Box::double: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 1, field_stash: Box}, ~, ~, Unknown], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 1
  [Call, {class_name: Box, dispatch_kind: method, name: new, param_names: [val]}, [1], 0, Object], # 2
  [Call, {class_name: Box, dispatch_kind: method, name: double, param_names: []}, [2], 2, Unknown], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## conditional-void-call

A void mutating method call GUARDED by a runtime condition: `$c->inc if $x > 3`.
The call runs only when the guard is true, so its field store is
control-dependent on the branch: it is walked on the true Proj (control-threaded)
and a Region merges the taken/not-taken edges. The post-branch `val` read
observes the merged state. Without building the branch control flow, the void
call rebinds no pad slot and the effect is silently dropped when taken (zhi
019f2df7). The invocant (the `new` construction bound to `$c`) is used both in
the guarded arm and after the merge, so it is pre-lowered in the dominating
pre-branch block.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method inc { $n = $n + 1 }
    method val { return $n }
}
my $c = Counter->new(n => 10);
my $x = 5;
$c->inc if $x > 3;
say($c->val);
```

```behavior
stdout: 11\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%ten       = Constant(10) :Int
%new_c     = Call(%ten, dispatch_kind: "method", name: "new", class: "Counter", param_names: "n") :Object
%five      = Constant(5) :Int
%three     = Constant(3) :Int
%cmp       = NumGt(%five, %three) :Boolean
%if        = If(%cmp)
%proj0     = Proj(%if, index: 0)
%proj1     = Proj(%if, index: 1)
%inc       = Call(%new_c, dispatch_kind: "method", name: "inc", class: "Counter") :Int
%region    = Region(%proj1, %inc)
%result    = Call(%new_c, dispatch_kind: "method", name: "val", class: "Counter") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
branch_control: %proj0 -> %inc
control: %start -> %p
L: GREEN
```

```son
Counter::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Counter::inc: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Counter}, ~, ~, Scalar], # 1
  [Coerce, {from_repr: Scalar, to_repr: Num}, [1], ~, Num], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Add, ~, [2, 3], ~, Num], # 4
  [Assign, ~, [1, 4], 0, Num], # 5
  [Return, ~, [4], 5]]} # 6
Counter::val: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Counter}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 1
  [Call, {class_name: Counter, dispatch_kind: method, name: new, param_names: ["n"]}, [1], 0, Object], # 2
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [NumGt, ~, [3, 4], ~, Boolean], # 5
  [If, ~, [2, 5], 2], # 6
  [Proj, {index: 1}, [6]], # 7
  [Proj, {index: 0}, [6]], # 8
  [Call, {class_name: Counter, dispatch_kind: method, name: inc, param_names: []}, [2], 8, Num], # 9
  [Region, {head: 6}, [7, 9]], # 10
  [Call, {class_name: Counter, dispatch_kind: method, name: val, param_names: []}, [2], 10, Scalar], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [12, 13], 11, Scalar], # 14
  [Return, ~, [14], 14]]} # 15
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## method-branched-field-store

A method whose body is an if/else that mutates a field in BOTH arms
(`method bump { if ($n < 100) { $n = $n + 5 } else { $n = $n + 1 } }`). Each arm's
field store is control-dependent on its own branch Proj and a Region merges the
arms, so the mutation persists exactly like a straight-line `$n += 1` store. The
method body lowers through the same control-chain elaboration the top-level graph
uses; a linear control_in walk would stop at the merge Region and drop the arm
stores, leaving the field unmutated (zhi 019f5368: `bump; val` returned 10, not
15). The method's own return value is the discarded assignment residual (Undef).

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method bump { if ($n < 100) { $n = $n + 5 } else { $n = $n + 1 } }
    method val { $n }
}
my $c = Counter->new(n => 10);
$c->bump;
say($c->val);
```

```behavior
stdout: 15\n
return: Bool:1
context: scalar
```

```ir
%cls       = MOP::Class(name: "Counter")
%mf_n      = MOP::Field(class: %cls, name: "n", fieldix: 0, param: true, reader: false, has_default: false, type: "Int")
%fa_rd     = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%hundred   = Constant(100) :Int
%cmp       = NumLt(%fa_rd, %hundred) :Boolean
%if        = If(%cmp)
%proj0     = Proj(%if, index: 0)
%proj1     = Proj(%if, index: 1)
%five      = Constant(5) :Int
%sum_t     = Add(%fa_rd, %five) :Int
%fa_lv_t   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%store_t   = Assign(%fa_lv_t, %sum_t) :Int
%one       = Constant(1) :Int
%sum_f     = Add(%fa_rd, %one) :Int
%fa_lv_f   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%store_f   = Assign(%fa_lv_f, %sum_f) :Int
%region    = Region(%store_t, %store_f)
%mi_bump   = MOP::Method(class: %cls, name: "bump", body: %region, return_repr: "Undef")
%fa_val    = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%mi_val    = MOP::Method(class: %cls, name: "val", body: %fa_val, return_repr: "Int")
%ten       = Constant(10) :Int
%new_c     = Call(%ten, dispatch_kind: "method", name: "new", class: "Counter", param_names: "n") :Object
%bump_call = Call(%new_c, dispatch_kind: "method", name: "bump", class: "Counter") :Undef
%result    = Call(%new_c, dispatch_kind: "method", name: "val", class: "Counter") :Int
control: %bump_call -> %result
branch_control: %proj0 -> %store_t
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
L: GREEN
```

```son
Counter::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Counter::bump: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [FieldAccess, {field_index: 0, field_stash: Counter}, ~, ~, Scalar], # 2
  [Coerce, {from_repr: Scalar, to_repr: Num}, [2], ~, Num], # 3
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 4
  [Add, ~, [3, 4], ~, Num], # 5
  [Constant, {const_type: integer, value: "100"}, ~, ~, Int], # 6
  [NumLt, ~, [3, 6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [Assign, ~, [2, 5], 9, Num], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [Add, ~, [3, 11], ~, Num], # 12
  [Proj, {index: 1}, [8]], # 13
  [Assign, ~, [2, 12], 13, Num], # 14
  [Region, {head: 8}, [10, 14]], # 15
  [Return, ~, [1], 15]]} # 16
Counter::val: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Counter}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 1
  [Call, {class_name: Counter, dispatch_kind: method, name: new, param_names: ["n"]}, [1], 0, Object], # 2
  [Call, {class_name: Counter, dispatch_kind: method, name: bump, param_names: []}, [2], 2, Undef], # 3
  [Call, {class_name: Counter, dispatch_kind: method, name: val, param_names: []}, [2], 3, Scalar], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, Scalar], # 7
  [Return, ~, [7], 7]]} # 8
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## method-branched-field-store-else-arm

The `else`-arm sibling of method-branched-field-store: constructing with `n = 200`
makes `$n < 100` FALSE, so the ELSE arm (`$n = $n + 1`, control-dependent on Proj
index 1) runs and the field becomes 201. This is the bilateral coverage for the
branch — the then-arm case (n = 10 -> 15) never exercises the else store, so a
miscompile that drops only the else arm or selects the wrong Proj would gate-green
without it.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method bump { if ($n < 100) { $n = $n + 5 } else { $n = $n + 1 } }
    method val { $n }
}
my $c = Counter->new(n => 200);
$c->bump;
say($c->val);
```

```behavior
stdout: 201\n
return: Bool:1
context: scalar
```

```ir
%cls       = MOP::Class(name: "Counter")
%mf_n      = MOP::Field(class: %cls, name: "n", fieldix: 0, param: true, reader: false, has_default: false, type: "Int")
%fa_rd     = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%hundred   = Constant(100) :Int
%cmp       = NumLt(%fa_rd, %hundred) :Boolean
%if        = If(%cmp)
%proj0     = Proj(%if, index: 0)
%proj1     = Proj(%if, index: 1)
%five      = Constant(5) :Int
%sum_t     = Add(%fa_rd, %five) :Int
%fa_lv_t   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%store_t   = Assign(%fa_lv_t, %sum_t) :Int
%one       = Constant(1) :Int
%sum_f     = Add(%fa_rd, %one) :Int
%fa_lv_f   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%store_f   = Assign(%fa_lv_f, %sum_f) :Int
%region    = Region(%store_t, %store_f)
%mi_bump   = MOP::Method(class: %cls, name: "bump", body: %region, return_repr: "Undef")
%fa_val    = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%mi_val    = MOP::Method(class: %cls, name: "val", body: %fa_val, return_repr: "Int")
%c200      = Constant(200) :Int
%new_c     = Call(%c200, dispatch_kind: "method", name: "new", class: "Counter", param_names: "n") :Object
%bump_call = Call(%new_c, dispatch_kind: "method", name: "bump", class: "Counter") :Undef
%result    = Call(%new_c, dispatch_kind: "method", name: "val", class: "Counter") :Int
control: %bump_call -> %result
branch_control: %proj1 -> %store_f
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
L: GREEN
```

```son
Counter::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Counter::bump: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [FieldAccess, {field_index: 0, field_stash: Counter}, ~, ~, Scalar], # 2
  [Coerce, {from_repr: Scalar, to_repr: Num}, [2], ~, Num], # 3
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 4
  [Add, ~, [3, 4], ~, Num], # 5
  [Constant, {const_type: integer, value: "100"}, ~, ~, Int], # 6
  [NumLt, ~, [3, 6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 0}, [8]], # 9
  [Assign, ~, [2, 5], 9, Num], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [Add, ~, [3, 11], ~, Num], # 12
  [Proj, {index: 1}, [8]], # 13
  [Assign, ~, [2, 12], 13, Num], # 14
  [Region, {head: 8}, [10, 14]], # 15
  [Return, ~, [1], 15]]} # 16
Counter::val: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Counter}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "200"}, ~, ~, Int], # 1
  [Call, {class_name: Counter, dispatch_kind: method, name: new, param_names: ["n"]}, [1], 0, Object], # 2
  [Call, {class_name: Counter, dispatch_kind: method, name: bump, param_names: []}, [2], 2, Undef], # 3
  [Call, {class_name: Counter, dispatch_kind: method, name: val, param_names: []}, [2], 3, Scalar], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, Scalar], # 7
  [Return, ~, [7], 7]]} # 8
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## self-method-call in a value position

A method that calls a SIBLING method on `$self` in a value position
(`method pick { $self->flag() ? 10 : 20 }`). The `$self->flag()` Call records its
statically-known class (the enclosing class, from the CV stash) so the backend
dispatches it, and the self receiver lowers to the method's %self object pointer
(zhi 019f5dec). This is the most common method-dispatch shape in real lib/ methods
(e.g. Chalk::Grammar::Symbol::to_string calls `$self->is_terminal()`).

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Widget {
    method flag { 1 }
    method pick { $self->flag() ? 10 : 20 }
}
say(Widget->new->pick);
```

```behavior
stdout: 10\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cls    = MOP::Class(name: "Widget")
%new_w  = Call(dispatch_kind: "method", name: "new", class: "Widget") :Object
%result = Call(%new_w, dispatch_kind: "method", name: "pick", class: "Widget") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
Widget::flag: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Widget::pick: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 1
  [Call, {class_name: Widget, dispatch_kind: method, name: flag, param_names: []}, [1], 0, Int], # 2
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "20"}, ~, ~, Int], # 4
  [TernaryExpr, ~, [2, 3, 4], ~, Int], # 5
  [Return, ~, [5], 2]]} # 6
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Call, {class_name: Widget, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 1
  [Call, {class_name: Widget, dispatch_kind: method, name: pick, param_names: []}, [1], 1, Int], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## self-method-call result feeding arithmetic

A method whose body CONSUMES a self-call in a computed expression
(`method use_it { $self->a() + 1 }`). The self-call `$self->a()` is typed from
the callee's return_repr, and `use_it`'s own return_repr is then that Add's Int --
but only on a LATER inference pass, since the Add has no repr until its self-call
input is stamped. The loader's return_repr inference is a FIXPOINT (stamp calls +
re-propagate until stable), so a caller of `use_it` gets its repr (zhi 019f5e57).
This arith-over-call pattern is pervasive in real lib/ methods.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Adder {
    method base { 5 }
    method plus_one { $self->base() + 1 }
}
say(Adder->new->plus_one);
```

```behavior
stdout: 6\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cls    = MOP::Class(name: "Adder")
%new_a  = Call(dispatch_kind: "method", name: "new", class: "Adder") :Object
%result = Call(%new_a, dispatch_kind: "method", name: "plus_one", class: "Adder") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
Adder::base: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Adder::plus_one: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: self}, ~, ~, Object], # 1
  [Call, {class_name: Adder, dispatch_kind: method, name: base, param_names: []}, [1], 0, Int], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Add, ~, [2, 3], ~, Int], # 4
  [Return, ~, [4], 2]]} # 5
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Call, {class_name: Adder, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 1
  [Call, {class_name: Adder, dispatch_kind: method, name: plus_one, param_names: []}, [1], 1, Int], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## conditional string append (.= guarded by a postfix if)

A method that appends to a string only when a field is defined
(`method m { my $s = $v; $s .= $q if defined $q; $s }`) currently GAPs at the
method body root NO representation -- the branch-guarded `.=` field/local append in
a return-value position is not yet lowered (distinct from the branch-guarded
element/field STORE, which is; this is a value-context conditional Concat). This is
the second NO-REPR trigger in Chalk::Grammar::Symbol::to_string
(`$str .= $quantifier if defined $quantifier`).

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Tagged {
    field $v :param;
    field $q :param = undef;
    method render {
        my $s = $v;
        $s .= $q if defined $q;
        $s
    }
}
Tagged->new(v => "a", q => "b")->render
```

```behavior
return: Str:ab
context: scalar
```

```ir
L: GAP(a value-context conditional string append -- $s .= $x if defined $x -- feeding the method return is not yet lowered; the branch-guarded Concat residual reaches the method body root with no representation)
```

```son
Tagged::render: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 1, field_stash: Tagged}, ~, ~, Str], # 1
  [Defined, ~, [1], ~, Boolean], # 2
  [FieldAccess, {field_index: 0, field_stash: Tagged}, ~, ~, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [TernaryExpr, ~, [2, 5, 3], ~, Unknown], # 6
  [Return, ~, [6], 0]]} # 7
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 2
  [Call, {class_name: Tagged, dispatch_kind: method, name: new, param_names: [v, q]}, [1, 2], 0, Object], # 3
  [Call, {class_name: Tagged, dispatch_kind: method, name: render, param_names: []}, [3], 3, Unknown], # 4
  [Return, ~, [4], 4]]} # 5
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## arrayref-field element read

A field whose default is an aggregate literal (`field $items = [10,20,30]`) is
an ArrayRef, and reading an element by index (`$items->[0]`) yields the element.
The producer once dropped an aggregate field default entirely (only scalar const
defaults were emitted), so the field typed as its first element's scalar type
("integer") and the read GAPped. Now the producer emits the anonlist default as
an ArrayRef graph, the loader lifts the field type to ArrayRef (and the field's
element type from the default's elements), and the backend reads the boxed i8*
payload (inttoptr) so _container_ptr can index it. This is the field foundation
for `for my $x ($items->@*)` (the #1 lib/ blocker; the foreach loop itself still
GAPs on the loop-carried element stamp -- a follow-up). zhi 019f61ad.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Bag {
    field $items = [10, 20, 30];
    method first { $items->[0] }
}
say(Bag->new->first);
```

```behavior
stdout: 10\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cls    = MOP::Class(name: "Bag")
%new_b  = Call(dispatch_kind: "method", name: "new", class: "Bag") :Object
%result = Call(%new_b, dispatch_kind: "method", name: "first", class: "Bag") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
Bag::__DEFAULT_0: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "20"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "30"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, Unknown], # 4
  [Return, ~, [4], 0]]} # 5
Bag::first: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Bag}, ~, ~, ArrayRef], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Return, ~, [4], 0]]} # 5
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Call, {class_name: Bag, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 1
  [Call, {class_name: Bag, dispatch_kind: method, name: first, param_names: []}, [1], 1, Scalar], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## foreach over an arrayref field

`for my $x ($items->@*)` where `$items` is an arrayref field iterates its
elements. This is the #1 Phase-5 lib/ blocker (28 methods -- e.g.
Chalk::Grammar::Rule::is_terminal_rule's `for my $alt ($expressions->@*)`). The
field-deref bound (a FieldAccess) routes into the array-foreach translation, and
the loop-carried accumulator's back-edge (`Add($s_phi, Subscript)`, where the
element Subscript's stamp is deferred to the loader) no longer GAPs at the
loop-Phi stamp check: a numeric accumulator recurrence keeps its init stamp (the
fixpoint no-op), and the loader types the element read. zhi 019f6198, 019f61ad.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Bag {
    field $items = [10, 20, 30];
    method total { my $s = 0; for my $x ($items->@*) { $s = $s + $x } $s }
}
say(Bag->new->total);
```

```behavior
stdout: 60\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cls    = MOP::Class(name: "Bag")
%new_b  = Call(dispatch_kind: "method", name: "new", class: "Bag") :Object
%result = Call(%new_b, dispatch_kind: "method", name: "total", class: "Bag") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
Bag::__DEFAULT_0: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "20"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "30"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, Unknown], # 4
  [Return, ~, [4], 0]]} # 5
Bag::total: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 15], ~, Int], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [Return, ~, [3], 5], # 6
  [FieldAccess, {field_index: 0, field_stash: Bag}, ~, ~, ArrayRef], # 7
  [MemStart], # 8
  [Count, ~, [7, 8], ~, Int], # 9
  [Phi, {region: 2}, [1, 17], ~, Int], # 10
  [NumGt, ~, [9, 10], 2, Boolean], # 11
  [Proj, {index: 0}, [2]], # 12
  [Subscript, ~, [7, 10, 8], ~, Scalar], # 13
  [Coerce, {from_repr: Scalar, to_repr: Num}, [13], ~, Num], # 14
  [Add, ~, [3, 14], ~, Num], # 15
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 16
  [Add, ~, [10, 16], ~, Int]]} # 17
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Call, {class_name: Bag, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 1
  [Call, {class_name: Bag, dispatch_kind: method, name: total, param_names: []}, [1], 1, Int], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## print a method-call result (the coercion the producer cannot insert)

`Print` takes Str, and a non-Str argument is bridged by a `Coerce(X -> Str)`.
The producer inserts that at its build site — but only for an argument that
carries a STAMP there. A method call has no return type until the LOADER
resolves the callee, so the producer sees an unstamped argument and correctly
declines to guess.

The coercion is therefore inserted by the loader instead, after every repr
fixpoint has run — the first point at which the operand's representation is
actually known. Without it a `print $obj->method` reached the backend as
`Print(Call :Int)` and GAPped with "Print of a Int arg", even though the
producer had done nothing wrong.

```perl
# source
use 5.42.0;
use experimental 'class';
class Counter {
    field $n :param = 5;
    method get { $n }
}
my $c = Counter->new;
print $c->get, "\n";
say(1);
```

```behavior
stdout: 5\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cls  = MOP::Class(name: "Counter")
%new  = Call(dispatch_kind: "method", name: "new", class: "Counter") :Object
%get  = Call(%new, dispatch_kind: "method", name: "get", class: "Counter") :Int
%sg   = Coerce(%get, from_repr: "Int", to_repr: "Str") :Str
%nl   = Constant("\n") :Str
%p    = Print(%sg, %nl)
%one  = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%one : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
Counter::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Counter::get: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Counter}, ~, ~, Scalar], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Coerce, {from_repr: Int, to_repr: Str}, [1], ~, Str], # 2
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 3
  [Call, {class_name: Counter, dispatch_kind: method, name: new, param_names: []}, ~, 0, Object], # 4
  [Call, {class_name: Counter, dispatch_kind: method, name: get, param_names: []}, [4], 4, Scalar], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Print, ~, [6, 3], 5, Scalar], # 7
  [Print, ~, [2, 3], 7, Scalar], # 8
  [Return, ~, [8], 8]]} # 9
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: experimental}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: experimental.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: experimental, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

## method with a signature parameter

`method plus($k)` -- a method taking an argument beyond the invocant. This is
the single most common declaration form in `lib/Chalk/`: 920 uses, against ZERO
corpus coverage before this case. Every method the compiler's own source
defines has this shape.

```perl
# source
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method plus($k) { $n + $k }
}
say(Counter->new(n => 10)->plus(32));
```

```behavior
stdout: 42\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cls  = MOP::Class(name: "Counter")
%ten  = Constant(10) :Int
%new  = Call(%ten, dispatch_kind: "method", name: "new", class: "Counter") :Object
%k    = Constant(32) :Int
%plus = Call(%new, %k, dispatch_kind: "method", name: "plus", class: "Counter") :Int
%sp   = Coerce(%plus, from_repr: "Int", to_repr: "Str") :Str
%nl   = Constant("\n") :Str
%p    = Print(%sp, %nl)
return %p
control: %start -> %new -> %plus -> %p
L: GREEN
```

```son
Counter::__DEFAULT_0: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
Counter::plus: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [FieldAccess, {field_index: 0, field_stash: Counter}, ~, ~, Scalar], # 1
  [Coerce, {from_repr: Scalar, to_repr: Num}, [1], ~, Num], # 2
  [Parameter, {index: 0, name: $k, sigil: $}, ~, ~, Num], # 3
  [Add, ~, [2, 3], ~, Num], # 4
  [Return, ~, [4], 0]]} # 5
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 1
  [Call, {class_name: Counter, dispatch_kind: method, name: new, param_names: ["n"]}, [1], 0, Object], # 2
  [Constant, {const_type: integer, value: "32"}, ~, ~, Int], # 3
  [Call, {class_name: Counter, dispatch_kind: method, name: plus, param_names: []}, [2, 3], 2, Num], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, Scalar], # 7
  [Return, ~, [7], 7]]} # 8
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 4": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: warnings, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```

