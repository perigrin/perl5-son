# Subs

Named sub definitions, anonymous subs (closures), and chained sub calls.

The direct-call cases (F1 named sub, F1v void call) are GREEN; the CodeRef
cases (F2 closure, F3 chained) remain L: GAP — but CodeRef is runtime-free
(RF). Per the
runtime-free boundary, named subs and closures are RF: a CodeRef's
representation is a function pointer plus a captured-environment struct (NOT an
SV*), and a call is an indirect call. A statically-known call target is RF —
this is NOT "dynamic dispatch"; only a runtime-computed target would be
out-of-subset. These cases are GAPs only until the CodeRef representation and
call lowering are modelled — not because they need the interpreter. The
behavior is specified by the perl oracle; each GAP records the work-list item
that closes it.

Archive sources: `archive/pu-2026-03-24:t/corpus/ir/sub-simple.chalk` (F1),
`archive/pu-2026-03-24:t/corpus/ir/anon-sub.chalk` (F2),
`archive/pu-2026-03-24:t/corpus/ir/chain-call.chalk` (F3 — adapted from method
chain to sub chain for the subs topic).

## F1 named sub

A named sub is defined and immediately called. The sub returns a constant
integer value. The IR models the sub definition as a separate graph and the
call site as a Call node with dispatch_kind=direct — the target is statically
known (a bareword named sub), so it is a direct call, not dynamic dispatch. The
loader resolves the Call's name (main::foo) to the callee graph, and the backend
lowers the no-argument call by inlining the callee's result. This is RF: no
libperl/SV dependency.

Archive source: `sub helper($x) { return $x + 1; }` (sub-simple.chalk).

```perl
# source
use 5.42.0;
sub foo { return 1 }
say(foo());
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::foo") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%call : Int -> Str) :Str
%p  = Print(%co_p, %nl)
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
  [Call, {dispatch_kind: direct, name: main::foo, param_names: [], want: list}, ~, 0, Int], # 1
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 2
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 3
  [Print, ~, [2, 3], 1, Scalar], # 4
  [Return, ~, [4], 4]]} # 5
main::foo: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
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
```

## F1v void direct call

A named sub is called in VOID statement position — `side();` — for its side
effect, with its result discarded, and a later value is returned. The call is
NOT the return value; it is a statement effect that must be threaded onto the
control chain (is_stmt_effect) so it is ordered and survives DCE. Without that
threading the pushed Call is dead in void context and the call vanishes
silently (zhi 019f26a5). The loader seeds the single-exit Return from the
stmt-effect Call as well as the returned value, so the call is scheduled before
the Return. This is RF: a direct call to a statically-known target.

```perl
# source
use 5.42.0;
sub side { 42 }
my $n = 7;
side();
say($n);
```

```behavior
stdout: 7\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::side")
%n = Constant(7) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%n : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 1
  [Coerce, {from_repr: Int, to_repr: Str}, [1], ~, Str], # 2
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 3
  [Call, {dispatch_kind: direct, name: main::side, param_names: [], want: void}, ~, 0, Int], # 4
  [Print, ~, [2, 3], 4, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
main::side: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "42"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
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
```

## F2 anonymous sub

An anonymous sub (closure) is created with `sub { ... }`, stored in a lexical
variable as a CodeRef, and then invoked via the arrow-call syntax
`$fn->()`. The IR models this with an AnonSub node (which carries a nested
graph) and a Call node at the invocation site. This is RF: the closure lowers
to a function pointer plus a captured-environment struct (NOT an SV*), and the
arrow-call is an indirect call to a statically-known target. The GAP is only
that the CodeRef representation is not modelled yet.

Archive source: `my $fn = sub { return 1; };` (anon-sub.chalk).

```perl
# source
my $fn = sub { return 1 };
$fn->()
```

```behavior
return: 1
context: scalar
```

```ir
L: GAP(CodeRef is RF: a function pointer + captured-env struct, call = indirect call; GAP only until CodeRef representation is modelled, NOT a libperl/SV dependency)
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Call, {dispatch_kind: direct, name: main::corpus_case::__ANON__:4:2, param_names: []}, ~, 0, Int], # 1
  [Return, ~, [1], 1]]} # 2
main::corpus_case::__ANON__:4:2: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
```

## F3 chained sub calls

One sub calls another sub — a two-level call chain. The IR contains two Call
nodes at the respective call sites. Both are RF: each call target is
statically known, so each lowers to an indirect call through a function
pointer (not dynamic dispatch, which would require a runtime-computed target).
The GAP is only that the CodeRef representation and call lowering are not
modelled yet. This case is adapted from the archive chain-call idiom to stay
within the subs topic (the archive source was method chaining on an object,
which belongs to the classes topic).

```perl
# source
sub add1 { my ($x) = @_; return $x + 1 }
sub add2 { my ($x) = @_; return add1($x) + 1 }
add2(3)
```

```behavior
return: 5
context: scalar
```

```ir
L: GAP(CodeRef is RF: each call is an indirect call to a statically-known target via a function pointer; GAP only until CodeRef representation is modelled, NOT a libperl/SV dependency)
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::add1: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Num], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Add, ~, [1, 2], ~, Num], # 3
  [Return, ~, [3], 0], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Assign, ~, [1, 5], ~, List]]} # 6
main::add2: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {sigil: $, symbol: x}, [1], ~, Unknown], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [Assign, ~, [2, 3], 0, List], # 4
  [PadAccess, {sigil: $, symbol: x}, [4], ~, Unknown], # 5
  [Call, {dispatch_kind: direct, name: main::add1, param_names: [], want: scalar}, [5], 4, Num], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Add, ~, [6, 7], ~, Num], # 8
  [Return, ~, [8], 6]]} # 9
main::corpus_case: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 1
  [Call, {dispatch_kind: direct, name: main::add2, param_names: []}, [1], 0, Num], # 2
  [Return, ~, [2], 2]]} # 3
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
```

## F4 sub returning a list flattens into the caller's list assignment

`sub inner { return (10, 20, 30) }` returns a LIST; `my @x = inner()` binds @x to
all three elements, so `scalar @x` is 3. Modeling this requires a multi-value
call return: the callee must yield every value (not just the last) AND the
caller's list-assignment must flatten them. The producer previously kept only
the last return value (`$args->[-1]` / a single `pop_node` at leavesub),
silently dropping 10 and 20, so `scalar @x` returned 1 -- a silent miscompile.

The sub body is compiled once and is context-independent, so the producer
cannot know the caller's runtime wantarray; a >1-value return cannot be soundly
collapsed to one scalar Return. Per GAP-not-miscompile the producer now refuses
the multi-value list return loudly (`_leavesub_returns_list` detects the trailing
OP_LIST / OP_RETURN with >1 value child). Flip to `L: GREEN` when a multi-value
return is modeled as a list result the caller's aassign flattens (this is the
list-flattening class variables.md A9-A11 at a sub-call boundary, and the
caller-side half of the no-Return list-returning method that poisons the shared
MOP -- Phase-5: Chalk::IR::Node::_serialize_inputs returns @parts). zhi 019f5e41.

```perl
# source
sub inner { return (10, 20, 30) }
my @x = inner();
scalar @x
```

```behavior
return: 3
context: scalar
```

```ir
%c1    = Constant(10) :Int
%c2    = Constant(20) :Int
%c3    = Constant(30) :Int
%arr   = ArrayLiteral(%c1, %c2, %c3) :ArrayRef
%len   = Length(%arr) :Int
return %len
L: GAP(multi-value list return: callee drops all-but-last, needs list-result + caller flatten)
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Call, {dispatch_kind: direct, name: main::inner, param_names: [], want: list}, ~, 0, List], # 1
  [ArrayLiteral, {sigil: "@", symbol: x}, [1], ~, Array], # 2
  [MemStart], # 3
  [Count, ~, [2, 3], ~, Int], # 4
  [Return, ~, [4], 1]]} # 5
main::inner: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "20"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "30"}, ~, ~, Int], # 3
  [ArrayLiteral, ~, [1, 2, 3], ~, List], # 4
  [Coerce, {from_repr: List, to_repr: Scalar}, [3], ~, Scalar], # 5
  [Return, ~, [4, 5], 0]]} # 6
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
```

## F5 direct sub call with arguments (t/ blocker: F3 argument binding)

A direct call to a named sub PASSING arguments (`f(10)` where `f` reads its
argument via `shift`/`@_`). Earlier work lowered a no-arg direct call (inline the
callee value); an arg-passing call binds the argument into the callee's parameter
read. Since the callee is INLINED (not a real call frame), the caller's Call input
is bound by SSA substitution to the callee's positional `shift @_` read — the
loader types the callee's `shift` read from the argument's repr (so the callee body
`$x + 1` carries an Int repr), and the backend intercepts the callee's `shift` node
during inlining and returns the caller's argument ref. This is the load-bearing
blocker for t/op (Test::More `is`/`ok` are arg-passing calls). GREEN for the sound
single-positional-`shift` shape; a callee that reads `@_` as an aggregate (a
list-assign `my ($a,$b)=@_` or a `$_[N]` subscript) or via multiple `shift`s (which
hash-cons to one node and lose their order) GAPs loudly — see F6/F7.

```perl
# source
use 5.42.0;
sub f { my $x = shift; $x + 1 }
my $r = f(10);
say($r);
```

```behavior
stdout: 11\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::f") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%call : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, [1], 0, Num], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
main::f: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1, 2], 0, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Num}, [3], ~, Num], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Add, ~, [4, 5], ~, Num], # 6
  [Return, ~, [6], 3]]} # 7
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
```

## F6 identity sub returns its shifted argument

A callee whose whole body is a single `shift` returns its first argument
unchanged. The `shift @_` read is the callee's Return value directly, so the
inline binding substitutes the caller's argument ref for the whole call — the
bilateral counterpart to F5 (F5 computes over the arg; F6 returns it verbatim).

```perl
# source
use 5.42.0;
sub id { shift }
say(id(99));
```

```behavior
stdout: 99\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::id") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%call : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "99"}, ~, ~, Int], # 1
  [Call, {dispatch_kind: direct, name: main::id, param_names: [], want: list}, [1], 0, Scalar], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
main::id: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1, 2], 0, Scalar], # 3
  [Return, ~, [3], 3]]} # 4
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
```

## F7 list-assign of @_ into named params GAPs

A callee that reads its arguments as an aggregate — `my ($a,$b) = @_` — does NOT
carry the positional binding the caller's args need: the producer emits the pad
params but does not connect the list-assign to `@_` in the graph, so the two
PadAccess reads have no def linking them to the caller's `3` and `4`. Inlining
binds only positional `shift @_` reads; this shape (and its `$_[N]`-subscript and
multiple-`shift` siblings) GAPs loudly rather than miscompiling to a stale/zero
value. Flip to GREEN when the producer connects `my (...) = @_` to the call
arguments (a multi-parameter binding, the caller-side analogue of F4's
multi-value return).

```perl
# source
sub add { my ($a, $b) = @_; $a + $b }
add(3, 4)
```

```behavior
return: 7
context: scalar
```

```ir
L: GAP(list-assign of @_ into named params — inlining binds only positional `shift @_`; `my (...) = @_` does not connect to the call arguments in the graph)
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::add: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: a}, ~, ~, Num], # 1
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Num], # 2
  [Add, ~, [1, 2], ~, Num], # 3
  [Return, ~, [3], 0], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Assign, ~, [1, 2, 5], ~, List]]} # 6
main::corpus_case: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::add, param_names: []}, [1, 2], 0, Num], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
```

## F8 positional `$_[0]` subscript binds the argument (t/cmd/elsif.t blocker)

A callee that reads its first argument as `$_[0]` (a subscript on `@_`, not
`shift @_`). The producer emits `Subscript(Constant("_"), Constant(0), Mem)` —
the `@_` array by name at index 0. Inlining binds it exactly like a positional
`shift @_`: the caller's argument ref substitutes for the Subscript node during
inlining (keyed by refaddr, consulted before _lower_subscript). This is the
t/cmd/elsif.t blocker (`sub foo { if ($_[0] == 1) {...} }`). GREEN for a single
`$_[N]` read; multiple distinct `$_[N]` subscripts (arg 0 AND arg 1) are a
multi-positional shape that still GAPs (like multiple `shift`s).

```perl
# source
use 5.42.0;
sub f { $_[0] + 1 }
say(f(10));
```

```behavior
stdout: 11\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::f") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%call : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [1], 0, Num], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
main::f: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [Add, ~, [5, 6], ~, Num], # 7
  [Return, ~, [7], 0]]} # 8
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
```

## F9 effectful callee inline threads its print in program order (Slice B Commit 2-print)

A callee whose body performs an effect (`print`) and then returns a value that
the caller uses — `sub f { print "x"; 2 } my $r = f(); $r`. The callee's Return
value subgraph is just the constant `2`, but its `control_in` chain carries the
`print "x"` (`Return.control_in -> Print -> Start`, program order). Slice B
Commit 1 first converted the silent drop into a loud GAP (`_lower_call_direct`
died unless the callee's `Return.control_in` was `undef`/`Start`). Commit
2-print now threads a STRAIGHT-LINE Print-only chain (no Region/Loop/If/Assign
anywhere on it): `_collect_straight_line_effect_chain` walks `control_in` back
to `Start`, and `_lower_inlined_effects_then_value` drives it through
`process_control_node` (oldest-first) inside the arg-bind frame, splicing the
callee's `print "x"` onto the caller's control chain BEFORE the Return value is
lowered — `lli` now emits `xInt:2`, matching perl. Any OTHER effect shape
(Assign/store, or a Region/Loop/If on the chain — the parked loop-store slice)
still GAPs; see F12.

```perl
# source
use 5.42.0;
sub f { print "x"; 2 }
my $r = f();
say($r);
```

```behavior
stdout: x2\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::f") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%call : Int -> Str) :Str
%p  = Print(%co_p, %nl)
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
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, ~, 0, Int], # 1
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 2
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 3
  [Print, ~, [2, 3], 1, Scalar], # 4
  [Return, ~, [4], 4]]} # 5
main::f: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 2
  [Print, ~, [2], 0, Scalar], # 3
  [Return, ~, [1], 3]]} # 4
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
```

## F10 cross-graph cache-collision: caller AND callee both print, order preserved

The load-bearing hazard: `lower_value`'s cache is keyed by the node's STRING id
(`Print#N`), and each graph numbers its nodes from its OWN factory — a callee
`Print#N` can collide with an unrelated CALLER `Print#N`. A caller print
BEFORE the call, plus an inlined callee print, both survive and land in
program order only if the inliner does not silently serve the callee's print
from the caller's cached ref (or vice versa). `_lower_inlined_effects_then_value`
swaps the WHOLE cache to a fresh hash for the duration of the callee's chain
drive (mirrors the existing refaddr-keyed `_arg_bind` frame pattern), so the
callee's `Print` node is never cache-hit against the caller's identically-numbered
node.

```perl
# source
use 5.42.0;
sub f { print "callee"; 2 }
print "caller";
my $r = f();
say($r);
```

```behavior
stdout: callercallee2\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::f") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%call : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: caller}, ~, ~, Str], # 1
  [Print, ~, [1], 0, Scalar], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, ~, 2, Int], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Return, ~, [6], 6]]} # 7
main::f: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [Constant, {const_type: string, value: callee}, ~, ~, Str], # 2
  [Print, ~, [2], 0, Scalar], # 3
  [Return, ~, [1], 3]]} # 4
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
```

## F11 same effectful callee inlined at two call sites emits its print twice

Side-effecting ops STAY cached once lowered (they execute once at their
control position) — so a naive fix that merely computed the callee's effect
under its real string id would drop the SECOND inline's print (the two calls'
`Print` nodes are the SAME node object, cached after the first inline). Since
`_lower_inlined_effects_then_value` swaps to a fresh cache per INLINE
INSTANCE (not per node), each call site re-lowers and re-emits the callee's
print independently — matching perl, which runs the sub body twice.

```perl
# source
use 5.42.0;
sub f { print "y"; 2 }
my $a = f();
my $b = f();
say($a + $b);
```

```behavior
stdout: yy4\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call1 = Call(dispatch_kind: "direct", name: "main::f") :Int
%call2 = Call(dispatch_kind: "direct", name: "main::f") :Int
%sum   = Add(%call1, %call2) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%sum : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, ~, 0, Int], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, ~, 1, Int], # 2
  [Add, ~, [1, 2], ~, Int], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 2, Scalar], # 6
  [Return, ~, [6], 6]]} # 7
main::f: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 2
  [Print, ~, [2], 0, Scalar], # 3
  [Return, ~, [1], 3]]} # 4
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
```

## F12 loop-effect callee (parked loop-store shape) still GAPs, not a broken lowering

A callee whose control chain contains a `Region` (a loop that prints, then
returns a value) is the PARKED loop-store shape (Slice B Commit 2-loop-store,
not built here — memory-SSA re-entrancy is a separate slice).
`_collect_straight_line_effect_chain` GAPs loudly on any non-`Print`,
non-`Start` node it meets walking `control_in` — a `Region` here included — so
this shape is never attempted, only ever a clean GAP, never a reordered or
dropped effect.

```perl
# source
sub g { for my $i (1..2) { print "z" } 9 }
my $r = g();
$r
```

```behavior
stdout: zz
return: 9
context: scalar
```

```ir
L: GAP(direct call to 'g': callee has effect(s) on its control chain (print/store/...) that inlining does not yet thread in program order)
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: scalar}, ~, 0, Int], # 1
  [Return, ~, [1], 1]]} # 2
main::g: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Proj, {index: 1}, [2]], # 3
  [Region, {head: 2}, [3]], # 4
  [Return, ~, [1], 4], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Phi, {region: 2}, [7, 13], ~, Int], # 8
  [NumGt, ~, [6, 8], 2, Boolean], # 9
  [Proj, {index: 0}, [2]], # 10
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 11
  [Print, ~, [11], 10, Scalar], # 12
  [Add, ~, [8, 7], ~, Int]]} # 13
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.042"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
```

## F13 unused-result call still threads its effect (perl5-son R1.0 effect-by-default)

`sub f { print "x"; 2 } my $r = f(); 3` — like F9, but `$r` is never read: the
call's VALUE is completely dead, only its EFFECT matters, and the trailing
statement (`3`) is a different, unrelated value than the call's return. Before
perl5-son's R1.0 fix, `FromOptree::_handle_entersub` only pinned a Call's
`control_in` `if $void` — a non-void call (this one binds `$r`, so it is NOT
OPf_WANT_VOID) got NO control pin at all. Unpinned, the Call was unreachable
from Return, and the producer's reachability walk dropped it entirely: the
loaded caller graph was literally Start / Constant / Return, with no Call node
at all, and `print "x"` silently vanished (perl prints `x`; chalk printed
nothing). The fix pins `control_in` unconditionally (void or not) and advances
the sim's control to the Call before deciding whether to also push its value,
so the call survives and orders correctly regardless of whether its result is
used.

```perl
# source
use 5.42.0;
sub f { print "x"; 2 }
my $r = f();
say(3);
```

```behavior
stdout: x3\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::f") :Int
%n    = Constant(3) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%n : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 1
  [Coerce, {from_repr: Int, to_repr: Str}, [1], ~, Str], # 2
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 3
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, ~, 0, Int], # 4
  [Print, ~, [2, 3], 4, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
main::f: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 2
  [Print, ~, [2], 0, Scalar], # 3
  [Return, ~, [1], 3]]} # 4
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
```

## F14 two calls to one sub with DIFFERENT arguments

The value miscompile the memoisation path produces, and the reason F11 does not
catch it: F11's callee PRINTS, so its visible output comes from the effect
chain, which IS re-driven per call site. The VALUE is lowered once through the
shared `{cache}` and served to the second site with the first site's argument
baked in.

Measured before the fix (Chalk 5c34fdf9 and earlier): `f(1)+f(2)` gave 4 where perl gives 6, and the emitted
LLVM contained exactly ONE `mul` for two calls.

Arguments must DIFFER. `f(3)+f(3)` passes today by coincidence -- the single
cached computation happens to be the right answer for both.

```perl
# source
use 5.42.0;
sub f { my $n = shift; $n * 2 }
print f(1) + f(2), "\n";
```

```behavior
stdout: 6\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1   = Constant(1) :Int
%f1   = Call(%c1, dispatch_kind: "direct", name: "main::f") :Int
%c2   = Constant(2) :Int
%f2   = Call(%c2, dispatch_kind: "direct", name: "main::f") :Int
%sum  = Add(%f1, %f2) :Int
%co   = Coerce(%sum : Int -> Str) :Str
%nl   = Constant("\n") :Str
%p    = Print(%co, %nl)
return %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, [1], 0, Num], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, [3], 2, Num], # 4
  [Add, ~, [2, 4], ~, Num], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 4, Scalar], # 8
  [Return, ~, [8], 8]]} # 9
main::f: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1, 2], 0, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Num}, [3], ~, Num], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Multiply, ~, [4, 5], ~, Num], # 6
  [Return, ~, [6], 3]]} # 7
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
```

The two Calls stay DISTINCT nodes with distinct arguments -- that is the whole
contract here. Before the fix the graph was the same shape but the LOWERING
collapsed both to one computation, so the shape leg alone could never have
caught this; only the behavior leg did.

Written from measured output. An earlier version of this block expected a
folded `Constant(6)`, which nothing produces: the producer does not
constant-fold across a call, and Print takes its operands directly rather than
through a Concat.

## F15 the same call nested in its own argument

`f(f(1))` -- the same defect reached differently. The inner call's value is
cached, then the outer call reads that cache entry rather than computing over
the inner result. Worth its own case: an argument-binding fix could plausibly
close F14 and not this.

Measured before the fix (Chalk 5c34fdf9 and earlier): 2 where perl gives 4.

```perl
# source
use 5.42.0;
sub f { my $n = shift; $n * 2 }
print f(f(1)), "\n";
```

```behavior
stdout: 4\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1   = Constant(1) :Int
%inner = Call(%c1, dispatch_kind: "direct", name: "main::f") :Int
%outer = Call(%inner, dispatch_kind: "direct", name: "main::f") :Int
%co   = Coerce(%outer : Int -> Str) :Str
%nl   = Constant("\n") :Str
%p    = Print(%co, %nl)
return %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [1], 0, Num], # 2
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [2], 2, Num], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Return, ~, [6], 6]]} # 7
main::f: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1, 2], 0, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Num}, [3], ~, Num], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Multiply, ~, [4, 5], ~, Num], # 6
  [Return, ~, [6], 3]]} # 7
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
```

The nesting is visible in the edge: the outer Call takes the INNER Call as its
argument, rather than both reading the same constant. That is what makes this
case distinct from F14 -- an argument-binding fix could plausibly close F14 and
leave this one broken.

Written from measured output; see the note under F14 about the folded
`Constant(4)` an earlier version of this block expected.

## F16 two calls in separate statements

The same defect outside a single expression, so a fix scoped to one expression
tree does not close it. Measured before the fix (Chalk 5c34fdf9 and earlier): `2 2` where perl gives `2 4`.

```perl
# source
use 5.42.0;
sub f { my $n = shift; $n * 2 }
my $a = f(1);
my $b = f(2);
print "$a $b\n";
```

```behavior
stdout: 2 4\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c2   = Constant(2) :Int
%c4   = Constant(4) :Int
%sp   = Constant(" ") :Str
%nl   = Constant("\n") :Str
%p    = Print(%nl)
return %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, [1], 0, Num], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: scalar}, [6], 2, Num], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Concat, ~, [5, 8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Print, ~, [11], 7, Scalar], # 12
  [Return, ~, [12], 12]]} # 13
main::f: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1, 2], 0, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Num}, [3], ~, Num], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [Multiply, ~, [4, 5], ~, Num], # 6
  [Return, ~, [6], 3]]} # 7
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
```

## F17 named sub with a signature parameter

A sub declared with a signature (`sub f($x)`) called with one argument. This is
the single most common sub form in `lib/Chalk/` -- 94 uses, against ZERO corpus
coverage before this case.

The argument reaches the callee: `lli` prints 42, as perl does. The callee body
lives in its own graph (`main::f`), so the program graph names only the call
boundary -- the `Constant(41)` bound as the Call's argument, and the `:Int`
result the signature-bound `$x + 1` yields.

THIS SPEC READ `:Num` UNTIL THE TYPING CAUGHT UP WITH IT. The producer cannot
see a callee's arguments, so it widens a signature-bound parameter to `Num` and
`$x + 1` came back `Num` on the wire. That is honest ahead-of-time typing, not
a defect -- but this loader has the whole program, sees the one callsite pass
`Constant(41) :Int`, and `41 + 1` is an integer. The spec recorded the
producer's limit as though it were the answer.

RECORDED HONESTLY BECAUSE I GOT IT WRONG FIRST: my probe called
`Chalk::Target::LLVM->lower` on this shape, saw no exception, and I wrote the
case GREEN. Lowering is not executing. The behavioural leg caught it on the
first gate run, and the case sat as a GAP (direct-call argument binding, F3)
until the argument actually flowed. This is precisely the trap the bson session
measured on the producer side the same day -- a broken implementation that
closes more holes than the correct one scores better on coverage alone -- and a
corpus case declared from a lowering probe rather than an execution is the same
error in the other direction.

```perl
# source
use 5.42.0;
sub f($x) { $x + 1 }
say(f(41));
```

```behavior
stdout: 42\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c41  = Constant(41) :Int
%call = Call(%c41, dispatch_kind: "direct", name: "main::f") :Int
%co   = Coerce(%call : Int -> Str) :Str
%nl   = Constant("\n") :Str
%p    = Print(%co, %nl)
return %p
control: %start -> %call -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "41"}, ~, ~, Int], # 1
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [1], 0, Num], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
main::f: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $x, sigil: $}, ~, ~, Num], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Add, ~, [1, 2], ~, Num], # 3
  [Return, ~, [3], 0]]} # 4
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
```

The `Constant(41)` is wired INTO the Call, not merely present beside it -- that
edge is the parameter binding this case exists to hold. Written from the
measured graph: the Call is stamped `:Num` (not `:Int`), so the Coerce into
Print's operand is `Num -> Str`.

## F18 sort with a comparator block

`sort { $a <=> $b }` -- 16 uses in `lib/Chalk/`. The comparator BLOCK does not
survive to the IR: perl folds a recognised numeric/string comparator into the
sort op itself, so the producer ships the COMPARISON KIND and DIRECTION as
fields on the Call (`sort_cmp`, `sort_order`) rather than a callable body. That
folding is what makes this lowerable without a general block-call mechanism.

THE OPERANDS ARE BARE SCALARS, NOT AN AGGREGATE, and that is what blocked the
lowering after the wire was already complete. perl flattens a literal list into
sort's argument slots, so `sort { ... } (3,1,2)` arrives as a Call with THREE
`Constant :Int` inputs -- no array anywhere. `_lower_builtin_sort` had been
written against the only shape that ever reached it, `sort keys %h`, whose
single operand IS an aggregate; it took `inputs[0]` as "the" operand and
refused anything not Array/ArrayRef. It now materialises its N scalar operands
into an `%Array` of `%Slot` through the same helper the array-literal path uses.

F19 and F20 are NOT closed by this and are no longer the same gap: they build a
result list with `ListAppend`, which has no lowering, and a general
block-calling mechanism is exactly what they still need.

```perl
# source
use 5.42.0;
my @s = sort { $a <=> $b } (3,1,2);
say($s[0]);
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

```ir
%three = Constant(3) :Int
%one   = Constant(1) :Int
%two   = Constant(2) :Int
%sorted = Call(%three, %one, %two, dispatch_kind: "builtin", name: "sort") :Array
%idx   = Constant(0) :Int
%elem  = Subscript(%sorted, %idx) :Scalar
# `Scalar`, not `Unknown`. The element read out of a runtime-ordered
# array is a tagged cell -- which reading lands at index 0 is decided at
# runtime -- and `Scalar` is the name for that. It read `Unknown` until
# the loader learned to narrow a Coerce whose operand is Scalar;
# `Unknown` means "nothing ever typed this", which was never true here.
%co    = Coerce(%elem : Scalar -> Str) :Str
%nl    = Constant("\n") :Str
%p     = Print(%co, %nl)
return %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: numeric, sort_order: ascending}, [1, 2, 3], ~, List], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Subscript, ~, [4, 5, 6], ~, Scalar], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [8, 9], 0, Scalar], # 10
  [Return, ~, [10], 10]]} # 11
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
```

The `Subscript` reads `:Scalar` and its `Coerce` reads `from_repr: Unknown`
because an element read out of a runtime-ordered array is not statically
narrowable to the element type -- sort's result is an `%Array` of `%Slot`, and
which slot lands at index 0 is decided at runtime. The tagged read is the
correct lowering, not a missing inference.

NOTE ON THE INVARIANT LEG: this case reports `op Call has undef control_in
(broken effect chain)`. That is the known false positive documented at
`references.md:508-517` -- `@CONTROL_CHAIN_OPS` lists `Call` unconditionally,
but `sort`, `keys` and `join` are PURE value producers, so being off the
control chain is correct for them. Filed there rather than fixed here, because
loosening a rule that polices every case in order to pass one is how a real
effect-ordering bug gets through.

## F19 grep with a block

`grep { ... }` -- part of the 277 grep/map block uses in `lib/Chalk/`. Same
blocker as F18.

THE ACCUMULATOR IS A LOOP-CARRIED %Array*, not a value copied per iteration.
`ListAppend(acc, ...)` mutates the buffer behind the pointer and returns the
SAME pointer, so the loop Phi merges one address with itself and the growth
lives in the header (len/cap) rather than in the SSA graph.

ARITY DOES NOT IDENTIFY THE SHAPE, which is why F19 and F20 are separate cases
rather than one. Measured against the producer:

    grep { $_ > 1 } (3,1,2)    ListAppend(Phi:Array, Subscript:Int, NumGt:Boolean)
    map  { $_ * 2 } (1,2)      ListAppend(Phi:Array, Multiply:Int)
    map  { ($_,$_) } (1,2)     ListAppend(Phi:Array, Subscript:Int, Subscript:Int)

grep's three-input form and map's pair form have THE SAME ARITY and mean
different things -- grep's last input is a BOOLEAN GATE, map's is a SECOND
ELEMENT. The lowering distinguishes them by the input's STAMP at the last
position, never by counting, and a lowering that counted would be wrong for
one of the two whichever way it guessed.

```perl
# source
use 5.42.0;
my @g = grep { $_ > 1 } (3,1,2);
say(scalar(@g));
```

```behavior
stdout: 2\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c3    = Constant(3) :Int
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%zero  = Constant(0) :Int
%src   = ArrayLiteral(%c3, %c1, %c2) :Array
%acc0  = ArrayLiteral() :Array
%loop  = Loop(%start)
%i     = Phi(%zero) :Int
%acc   = Phi(%acc0) :Array
%elem  = Subscript(%src, %i) :Int
%keep  = NumGt(%elem, %c1) :Boolean
%app   = ListAppend(%acc, %elem, %keep) :Array
%inext = Add(%i, %c1) :Int
%n     = Count(%acc) :Int
%co    = Coerce(%n : Int -> Str) :Str
%nl    = Constant("\n") :Str
%p     = Print(%co, %nl)
return %p
loop_backedge: %i -> %inext
loop_backedge: %acc -> %app
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, Array], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 24], ~, Array], # 3
  [MemStart], # 4
  [Count, ~, [3, 4], ~, Int], # 5
  [Coerce, {from_repr: Int, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Proj, {index: 1}, [2]], # 8
  [Region, {head: 2}, [8]], # 9
  [Print, ~, [6, 7], 9, Scalar], # 10
  [Return, ~, [10], 10], # 11
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 12
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 13
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 14
  [ArrayLiteral, ~, [12, 13, 14], ~, List], # 15
  [Count, ~, [15, 4], ~, Int], # 16
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 17
  [Phi, {region: 2}, [17, 21], ~, Int], # 18
  [NumGt, ~, [16, 18], 2, Boolean], # 19
  [Proj, {index: 0}, [2]], # 20
  [Add, ~, [18, 13], ~, Int], # 21
  [Subscript, ~, [15, 18, 4], ~, Int], # 22
  [NumGt, ~, [22, 13], ~, Boolean], # 23
  [ListAppend, {collector: grep}, [3, 22, 23], ~, Array]]} # 24
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
```

L: GAP: LLVM backend: cannot lower op=Call (not in literal-arithmetic slice)

## F20 map with a block

`map { ... }` -- the other half of the 277. Same blocker as F18.

THE ACCUMULATOR IS A LOOP-CARRIED %Array*, not a value copied per iteration.
`ListAppend(acc, ...)` mutates the buffer behind the pointer and returns the
SAME pointer, so the loop Phi merges one address with itself and the growth
lives in the header (len/cap) rather than in the SSA graph.

ARITY DOES NOT IDENTIFY THE SHAPE, which is why F19 and F20 are separate cases
rather than one. Measured against the producer:

    grep { $_ > 1 } (3,1,2)    ListAppend(Phi:Array, Subscript:Int, NumGt:Boolean)
    map  { $_ * 2 } (1,2)      ListAppend(Phi:Array, Multiply:Int)
    map  { ($_,$_) } (1,2)     ListAppend(Phi:Array, Subscript:Int, Subscript:Int)

grep's three-input form and map's pair form have THE SAME ARITY and mean
different things -- grep's last input is a BOOLEAN GATE, map's is a SECOND
ELEMENT. The lowering distinguishes them by the input's STAMP at the last
position, never by counting, and a lowering that counted would be wrong for
one of the two whichever way it guessed.

```perl
# source
use 5.42.0;
my @m = map { $_ * 2 } (1,2);
say($m[1]);
```

```behavior
stdout: 4\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%zero  = Constant(0) :Int
%src   = ArrayLiteral(%c1, %c2) :Array
%acc0  = ArrayLiteral() :Array
%loop  = Loop(%start)
%i     = Phi(%zero) :Int
%acc   = Phi(%acc0) :Array
%elem  = Subscript(%src, %i) :Int
%doubled = Multiply(%elem, %c2) :Int
%app   = ListAppend(%acc, %doubled) :Array
%inext = Add(%i, %c1) :Int
# `say($m[1])` -- an INDEXED READ of the result, not a count. The read is
# `:Scalar` because an element out of the accumulator is a tagged cell: which
# reading lands at index 1 is decided by what the loop appended, so it is
# unboxed at the Coerce rather than known statically.
%one   = Constant(1) :Int
%out   = Subscript(%acc, %one) :Scalar
%co    = Coerce(%out : Scalar -> Str) :Str
%nl    = Constant("\n") :Str
%p     = Print(%co, %nl)
return %p
loop_backedge: %i -> %inext
loop_backedge: %acc -> %app
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, Array], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 23], ~, Array], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Subscript, ~, [3, 4, 5], ~, Scalar], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Proj, {index: 1}, [2]], # 9
  [Region, {head: 2}, [9]], # 10
  [Print, ~, [7, 8], 10, Scalar], # 11
  [Return, ~, [11], 11], # 12
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 13
  [ArrayLiteral, ~, [4, 13], ~, List], # 14
  [Count, ~, [14, 5], ~, Int], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Phi, {region: 2}, [16, 20], ~, Int], # 17
  [NumGt, ~, [15, 17], 2, Boolean], # 18
  [Proj, {index: 0}, [2]], # 19
  [Add, ~, [17, 4], ~, Int], # 20
  [Subscript, ~, [14, 17, 5], ~, Int], # 21
  [Multiply, ~, [21, 13], ~, Int], # 22
  [ListAppend, {collector: map}, [3, 22], ~, Array]]} # 23
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
```

L: GAP: LLVM backend: cannot lower op=Call (not in literal-arithmetic slice)

## F21 postfix hash dereference `->%*`

`$h->%*` -- 85 uses in `lib/Chalk/`, no corpus coverage before this case.

It was filed because the backend CRASHED rather than refusing:

    Can't call method "id" on an undefined value at lib/Chalk/Target/LLVM/Context.pm

A crash is not a refusal. The GAP-not-miscompile invariant says an unsupported
construct must be REFUSED with a message naming what is missing; dying on an
undefined value names nothing and cannot be distinguished from a bug in a
supported path. That distinction is now closed the other way: the form lowers
and runs, printing 1 as perl does.

The array form `->@*` lowers too (5 corpus cases), so neither form is special.

```perl
# source
use 5.42.0;
my $h = {a=>1};
my %c = $h->%*;
say($c{a});
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%ka    = Constant("a") :Str
%v1    = Constant(1) :Int
%hash  = HashLiteral(%ka, %v1) :Hash
%lk    = Constant("a") :Str
%r     = Subscript(%hash, %lk) :Int
%co    = Coerce(%r : Int -> Str) :Str
%nl    = Constant("\n") :Str
%p     = Print(%co, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [HashLiteral, ~, [1, 2], ~, HashRef], # 3
  [MemStart], # 4
  [PostfixDeref, {sigil: "%"}, [3, 4], ~, Hash], # 5
  [Subscript, ~, [5, 1, 4], ~, Scalar], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 0, Scalar], # 9
  [Return, ~, [9], 9]]} # 10
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
```

Written from the measured graph. Two things it records that a guess would miss:

The `HashLiteral` is `:Hash`, not the `:HashRef` that R5's `my $r = {a=>1}`
carries. The whole `{a=>1}` / `->%*` / `my %c` round trip propagates away in the
optree before B::SoN walks -- the hash is never materialised as a ref -- so the
real graph reaches `$c{a}` as a direct Subscript over the literal.

There is NO `PostfixDeref` node, and naming one would be wrong twice over. The
deref-scaffolding rule subsumes a spec PostfixDeref whenever the real graph
carries none, so the line would be unenforced -- its `sigil:` never compared,
making an `@` deref indistinguishable from a `%` one. Worse, it would not be
valid IR: PostfixDeref requires a ref-typed input, and the propagated aggregate
here is a plain `:Hash`, so the spec-invariant leg rejects the block outright.
R5 can name a PostfixDeref because its `$r` really is a `:HashRef`; this case
has no ref left to deref.

The enforced content is therefore the aggregate kind, the key Constant, the
Subscript operand ORDER, and the `:Int` element repr -- each confirmed to FAIL
the check when perturbed.

## F22 polymorphic callee: one sub called with Int and with Str

The shape the corpus has NEVER contained. G7's census over 231 cases found **4
multi-callsite callees and ZERO polymorphic**, and recorded what that costs:
"on every gate case `join(args) == args[0]`, and gather-then-stamp is
behaviourally IDENTICAL to first-caller-wins: **the gate holds whether the join
is correct, inverted, or absent.**" This case is the discriminator that was
missing.

Measured 2026-08-30 against producer `8c15e32`: the JOIN IS CORRECT and the
LOWERING IS NOT. `_seed_direct_call_arg_reprs` stamps the shared `shift` read
`Str` — the join of `Int` and `Str`, not first-caller-wins, which would give
`Int` — and both Call nodes carry `Str`. So T1 gets the right answer.

The backend then emits invalid IR:

    error: '%tmp_1' defined with type 'i64' but expected '%Str = type { i8*, i64, i32 }'
      %tmp_2 = extractvalue %Str %tmp_1, 0   ; %Str.ptr

The callee body is emitted once, at the JOINED type (`%Str`), but the `Int`
call site passes its argument as a raw `i64`. Nothing coerces at the boundary.
This is a T2 gap, not a typing one: T1 correctly says "this parameter is Str at
one site and Int at the other, so the parameter is Str", and lowering needs
either a `Coerce[Int -> Str]` at the narrowing call site or a per-callsite
specialisation of the callee.

It is also the first case where the argument join is OBSERVABLE. Every other
corpus case is monomorphic, so this is the only one that would go red if the
join were inverted or deleted.

```perl
# source
use 5.42.0;
sub id { my $x = shift; return $x }
say(id(1));
say(id("hi"));
```

```behavior
stdout: 1\nhi\n
return: Bool:1
context: scalar
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: hi}, ~, ~, Str], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::id, param_names: [], want: list}, [2], 0, Scalar], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Call, {dispatch_kind: direct, name: main::id, param_names: [], want: list}, [1], 6, Scalar], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Print, ~, [8, 5], 7, Scalar], # 9
  [Return, ~, [9], 9]]} # 10
main::id: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: shift, param_names: []}, [1, 2], 0, Scalar], # 3
  [Return, ~, [3], 3]]} # 4
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
```

L: GAP: the callee is emitted once at the joined type (%Str) but the Int callsite passes a raw i64 -- no coercion at the call boundary

## F23 `map` in SCALAR context is a count, not a stringified list

The polarity F20 cannot see. F20 reads `my @m = map {...}` -- LIST context --
and every corpus case for map and grep does the same, so the scalar reading had
no coverage at all. It was a live miscompile on the producer side: map and grep
lower to a counted loop with a `ListAppend` accumulator, and the scalar reading
took the ACCUMULATOR, emitting `Coerce(Phi:Array -> Str)` -- stringifying the
result list where perl prints a count. Fixed in perl5-son 07fcdca, which now
inserts a `Count` before the coercion.

Measured on 5.42.0, and the two readings are not close:

    my $n = map  { $_*2 } (1,2,3)    3          a count
    my @l = map  { $_*2 } (1,2,3)    (2,4,6)    the values

Third instance of the same shape as `scalar reverse` and `scalar keys`: one
rule covering several builtins, satisfied only by the ones that really are
counts. The optree carried the answer the whole time (`mapstart sK` vs `lK`)
and nothing read it.

Filed as a pair with F20 for the reason the `exists` pair exists: a fix that
made BOTH readings a count would pass a scalar-only case, and a fix that made
both a list would pass a list-only case. Neither polarity alone can catch its
own inversion.

```perl
# source
use 5.42.0;
my $n = map { $_ * 2 } (1,2,3);
print $n, "\n";
```

```behavior
stdout: 3\n
return: Bool:1
context: scalar
```

```ir
L: GAP(Length.operand reaches the backend with no representation -- the ListAppend accumulator is untyped; same blocker as F19/F20, not a context defect)
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, Array], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 24], ~, Array], # 3
  [Count, ~, [3], ~, Int], # 4
  [Coerce, {from_repr: Int, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Proj, {index: 1}, [2]], # 7
  [Region, {head: 2}, [7]], # 8
  [Print, ~, [5, 6], 8, Scalar], # 9
  [Return, ~, [9], 9], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 12
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 13
  [ArrayLiteral, ~, [11, 12, 13], ~, List], # 14
  [MemStart], # 15
  [Count, ~, [14, 15], ~, Int], # 16
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 17
  [Phi, {region: 2}, [17, 21], ~, Int], # 18
  [NumGt, ~, [16, 18], 2, Boolean], # 19
  [Proj, {index: 0}, [2]], # 20
  [Add, ~, [18, 11], ~, Int], # 21
  [Subscript, ~, [14, 18, 15], ~, Int], # 22
  [Multiply, ~, [22, 12], ~, Int], # 23
  [ListAppend, {collector: map}, [3, 23], ~, Array]]} # 24
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
```

## F24 `grep` in SCALAR context is a count

The same defect and the same fix, reached through the other block-taking
builtin. Kept separate from F23 because a fix scoped to one builtin closes only
that one -- the reason F18/F19/F20 are three cases rather than one.

    my $n = grep { $_>1 } (1,2,3)    2          a count
    my @l = grep { $_>1 } (1,2,3)    (2,3)      the values

```perl
# source
use 5.42.0;
my $n = grep { $_ > 1 } (1,2,3);
print $n, "\n";
```

```behavior
stdout: 2\n
return: Bool:1
context: scalar
```

```ir
L: GAP(Length.operand reaches the backend with no representation -- the ListAppend accumulator is untyped; same blocker as F19/F20, not a context defect)
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, Array], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 24], ~, Array], # 3
  [Count, ~, [3], ~, Int], # 4
  [Coerce, {from_repr: Int, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Proj, {index: 1}, [2]], # 7
  [Region, {head: 2}, [7]], # 8
  [Print, ~, [5, 6], 8, Scalar], # 9
  [Return, ~, [9], 9], # 10
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 11
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 12
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 13
  [ArrayLiteral, ~, [11, 12, 13], ~, List], # 14
  [MemStart], # 15
  [Count, ~, [14, 15], ~, Int], # 16
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 17
  [Phi, {region: 2}, [17, 21], ~, Int], # 18
  [NumGt, ~, [16, 18], 2, Boolean], # 19
  [Proj, {index: 0}, [2]], # 20
  [Add, ~, [18, 11], ~, Int], # 21
  [Subscript, ~, [14, 18, 15], ~, Int], # 22
  [NumGt, ~, [22, 11], ~, Boolean], # 23
  [ListAppend, {collector: grep}, [3, 22, 23], ~, Array]]} # 24
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
```

## F25 `split` in scalar context

`split` in scalar context yields the FIELD COUNT. It used to take down the
producer's stack simulator rather than refusing: `split` is registered as a
'mark' pop, but the scalar form has NO pushmark (the list form fuses into the
assignment), so `pop_to_mark` died with "No mark on mark stack".

THAT CLASS IS WORSE THAN A GAP: an internal error sends the reader after a
simulator bug instead of a named construct, so the honest refusal underneath it
never gets written. It now refuses by name (perl5-son 07fcdca).

```perl
# source
use 5.42.0;
my $n = split(/,/, "a,b");
print $n, "\n";
```

```behavior
stdout: 2\n
return: Bool:1
context: scalar
```

```ir
L: GAP(split refuses by name: the fields are not built at this point, so a shape whose operands are not on the stack cannot be constructed)
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: regex, value: ","}, ~, ~, Regex], # 1
  [Constant, {const_type: string, value: "a,b"}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Call, {dispatch_kind: builtin, name: split, param_names: []}, [1, 2, 3], ~, List], # 4
  [MemStart], # 5
  [Count, ~, [4, 5], ~, Int], # 6
  [Coerce, {from_repr: Int, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 0, Scalar], # 9
  [Return, ~, [9], 9]]} # 10
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
```

## F26 `split` in list context

The other polarity, written at the same time rather than later. `split` in list
context yields the fields themselves.

```perl
# source
use 5.42.0;
my @f = split(/,/, "a,b");
print $f[0], "\n";
```

```behavior
stdout: a\n
return: Bool:1
context: scalar
```

```ir
L: GAP(split refuses by name: the fields are not built at this point, so a shape whose operands are not on the stack cannot be constructed)
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: regex, value: ","}, ~, ~, Regex], # 1
  [Constant, {const_type: string, value: "a,b"}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [Call, {dispatch_kind: builtin, name: split, param_names: []}, [1, 2, 3], ~, List], # 4
  [MemStart], # 5
  [Subscript, ~, [4, 3, 5], ~, Scalar], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 0, Scalar], # 9
  [Return, ~, [9], 9]]} # 10
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
```
