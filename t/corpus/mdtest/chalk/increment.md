# Increment

Pre-increment (`++$i`) and post-increment (`$i++`) idioms. Both are
read-modify-write (RMW): read the current value, add 1, write the result
back to the variable slot, then return the post-write value. Both produce
the same return value when `return $i` follows the increment.

The RMW write-back uses `CompoundAssign(op: "+=")` — the accurate Chalk IR
node for pre/post-increment. The LLVM target handles `CompoundAssign` through
the same `_lower_assign` code path as plain `Assign`.

The B1 stale-read guard does NOT fire on these cases because the RMW
internal read (`$i_r`), the lhs slot (`$i_l`), and the final return read
(`$i`) are **distinct PadAccess nodes**: each has a different `varname`,
so `content_hash` gives each a unique id. They do not alias, and no
poisoning occurs.

## K1 pre-increment (++$i; return $i)

Pre-increment reads the current value of `$i`, adds 1, writes the result
back, and the subsequent `return $i` sees the incremented value.

```perl
# source
use 5.42.0;
my $i = 0; ++$i; say($i);
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

```ir
%c0    = Constant(0) :Int
%iname = Constant("i") :Str
%vd    = VarDecl(%iname, %c0) :Int
%c1    = Constant(1) :Int
%read  = PadAccess(%vd, "$i_r") :Int    # RMW internal read — distinct node from final read
%add   = Add(%read, %c1) :Int
%lhs   = PadAccess(%vd, "$i_l") :Int    # lhs slot for write-back — distinct from read nodes
%ca    = CompoundAssign(%lhs, %add, op: "+=") :Int   # write-back: ++$i is a += 1
%ret_r = PadAccess(%vd, "$i") :Int      # final return read — distinct from RMW read
%nl = Constant("\n") :Str
%co_p = Coerce(%ret_r : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %vd -> %ca -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Add, ~, [1, 2], ~, Int], # 3
  [Coerce, {from_repr: Int, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 0, Scalar], # 6
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
```

## K2 post-increment ($i++; return $i)

Post-increment has the same side-effect graph as pre-increment when the
return is of `$i` (not the expression `$i++`). The distinction between `++$i`
(returns new value) and `$i++` (returns old value) is immaterial here because
the return statement reads `$i` after the increment completes in both cases.

```perl
# source
use 5.42.0;
my $i = 0; $i++; say($i);
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

```ir
%c0    = Constant(0) :Int
%iname = Constant("i") :Str
%vd    = VarDecl(%iname, %c0) :Int
%c1    = Constant(1) :Int
%read  = PadAccess(%vd, "$i_r") :Int    # RMW internal read — distinct node from final read
%add   = Add(%read, %c1) :Int
%lhs   = PadAccess(%vd, "$i_l") :Int    # lhs slot for write-back
%ca    = CompoundAssign(%lhs, %add, op: "+=") :Int   # write-back: $i++ side-effect is += 1
%ret_r = PadAccess(%vd, "$i") :Int      # final return read — distinct from RMW read
%nl = Constant("\n") :Str
%co_p = Coerce(%ret_r : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %vd -> %ca -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Add, ~, [1, 2], ~, Int], # 3
  [Coerce, {from_repr: Int, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 0, Scalar], # 6
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
```
