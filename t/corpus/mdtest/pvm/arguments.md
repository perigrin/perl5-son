# Arguments

How a sub receives its parameters. Two protocols: `@_`, which is tier
02's array populated by the call, and a signature, which is the one
construct in this tier the optimiser does NOT erase.

**Tier 07 subroutines.** Introduces `anoncode`, `argcheck`,
`argdefelem`, `argelem`, `entersub`, `leavesub`, `lock`, `return`, `warn`.
Depends on 06_control.

The two protocols cannot share a sub without noise. Measured 5.42.0,
`@_` inside a signatured sub is populated but reading it warns --
`Use of @_ in scalar with signatured subroutine is experimental` -- and
a warning on stderr is not something this corpus pins.

## Arguments arrive in `@_`

A sub reads its arguments as array elements: `$_[0]`, `$_[1]`, and
`scalar @_` for the count.

THE CONSTRUCT IS SPELLED ENTIRELY IN TIER 02'S SYNTAX. `@_` is an array
and `$_[0]` is element access; nothing about reading arguments needs an
op this tier introduces. What makes it tier 07's is that `@_` is only
populated by a call, which is `entersub` -- the array exists, but outside
a sub it holds nothing a caller put there. So the body's ops are
`aelemfast`, `rv2av` and friends, all tier 02's, and this tier claims
none of them.

Measured 5.42.0, the body of `sub n { scalar @_ }` is `gv[*_]`,
`rv2av`, `av2arylen`, `leavesub` -- and that `leavesub` is invisible to a
lint reading the main program alone.

```perl
sub describe {
    return $_[0] . "-" . $_[1] . "-" . scalar(@_);
}
print describe("a", "b", "c"), "\n";
```

```behavior
parses: yes
```

```output
a-b-3
```

```ir
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 4
  [Call, {dispatch_kind: direct, name: main::describe, param_names: [], want: list}, [2, 3, 4], 0, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, Scalar], # 8
  [Return, ~, [1], 8]]} # 9
main::describe: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Subscript, ~, [1, 8, 3], ~, Scalar], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Concat, ~, [7, 10], ~, Str], # 11
  [Concat, ~, [11, 6], ~, Str], # 12
  [Count, ~, [1, 3], ~, Int], # 13
  [Coerce, {from_repr: Int, to_repr: Str}, [13], ~, Str], # 14
  [Concat, ~, [12, 14], ~, Str], # 15
  [Return, ~, [15], 0]]} # 16
```

## A signature names the parameters

`sub f ($a, $b = 3)` binds by position and supplies a default for the
ones omitted.

A SIGNATURE IS NOT ERASED, which is worth stating because it is the
opposite of what the rest of this tier warns about. Measured 5.42.0,
`sub f ($a, $b = 3) { $a + $b }` compiles to `argcheck(1,1,-)`, an
`argelem` per parameter, and an `argdefelem` guarding the default
expression -- distinct ops carrying the declared arity, not ordinary pad
assignments that happen to read `@_`. Compare `sub f { my ($a,$b) = @_ }`,
which is `padrange` and `aassign` and nothing else: the two spellings
really are different optrees.

All of which is inside the sub, where a main-program lint cannot see it.

`use v5.36` itself adds no ops. Measured, it changes the `nextstate` hint
flags -- `v:us,*,&,{,$,fea=6` instead of `v:{` -- and nothing more, so
the feature pragma this case needs costs the op stream nothing.

```perl
use v5.36;
sub add_up ($a, $b = 3) { $a + $b }
print add_up(1), " ", add_up(1, 10), "\n";
```

```behavior
parses: yes
```

```output
4 11
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::add_up, param_names: [], want: list}, [2], 0, Num], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, name: main::add_up, param_names: [], want: list}, [2, 6], 3, Num], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Print, ~, [4, 5, 8, 9], 7, Scalar], # 10
  [Return, ~, [1], 10]]} # 11
main::add_up: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $a, sigil: $}, ~, ~, Num], # 1
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 2
  [Parameter, {default_when: absent, index: 1, name: $b, sigil: $}, [2], ~, Num], # 3
  [Add, ~, [1, 3], ~, Num], # 4
  [Return, ~, [4], 0]]} # 5
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
```

## `@_` aliases the caller's variables

`$_[0]++` inside a sub increments the CALLER's variable, because the
elements of `@_` are not copies of the arguments -- they ARE the
arguments, the same SVs under different names.

THIS IS THE CASE THE `@_` READING CASE IS NOT. Reading `$_[0]` is
something every array in the language supports and therefore measures
nothing about `@_` in particular. Writing through it is the whole
difference: an ordinary array's element is its own storage and a write to
it is local, and `@_`'s is not. The contrast is in the source rather than
in prose about it -- `bump_alias` writes through `$_[0]` and the caller
sees the change; `bump_copy` takes the conventional `my ($n) = @_` copy
and writes to that, and the caller does not. Same increment, same op, two
different variables, which is why `$untouched` stays 1.

MEASURED 5.42.0, THE OPS ARE THE SAME, and that is the finding.
`bump_alias` is `aelemfast[*_]`, `postinc`, `leavesub`; `bump_copy` is
`padrange`, `aassign`, `padsv`, `postinc`, `leavesub`. One `postinc`
each. The aliasing is not an op and not a flag on one: it is a property
of what `aelemfast[*_]` fetches, established when `entersub` filled `@_`
with the caller's SVs rather than with copies of them. No op claim can
express it and no optree comparison can find it -- only running the
program can, which is why this case leans on its pinned output entirely.

```perl
sub bump_alias {
    $_[0]++;
}
sub bump_copy {
    my ($n) = @_;
    $n++;
}
my ($aliased, $untouched) = (1, 1);
bump_alias($aliased);
bump_copy($untouched);
print "$aliased $untouched\n";
```

```behavior
parses: yes
```

```output
2 1
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: aliased}, [2], ~, Unknown], # 3
  [PadAccess, {sigil: $, symbol: untouched}, [2], ~, Unknown], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Assign, ~, [3, 4, 5, 5], 0, List], # 6
  [PadAccess, {sigil: $, symbol: aliased}, [6], ~, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [PadAccess, {sigil: $, symbol: untouched}, [6], ~, Str], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [10, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Call, {dispatch_kind: direct, name: main::bump_alias, param_names: [], want: void}, [7], 6, Scalar], # 16
  [Call, {dispatch_kind: direct, name: main::bump_copy, param_names: [], want: void}, [11], 16, Unknown], # 17
  [Print, ~, [15], 17, Scalar], # 18
  [Return, ~, [1], 18]]} # 19
main::bump_alias: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Subscript, ~, [1, 2], ~, Scalar], # 5
  [Increment, ~, [4], ~, Scalar], # 6
  [Assign, ~, [5, 6], 0, Scalar], # 7
  [Return, ~, [4], 7]]} # 8
main::bump_copy: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 1
  [Return, ~, [1], 0], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [Assign, ~, [1, 3], ~, List], # 4
  [Increment, ~, [1], ~, Scalar]]} # 5
```

## Explicit return, early and trailing

An explicit `return` leaves the sub with a value, and an early `return`
inside a branch leaves it before the last statement runs.

THE SOURCE CONSTRUCT AND THE OP ARE DIFFERENT THINGS. A `return` that IS
the last thing the body does compiles to nothing: the value is already on
the stack and `leavesub` takes it, so perl deletes the op. Only a return
that jumps -- guarded by a branch, with statements after it -- survives.
Measured 5.42.0, `sub f { return $_[0] + 1 }` is `aelemfast_lex_or_rv2av`,
`const`, `add`, `leavesub` and no `return`; `sub g { return 1 if $_[0]; 0 }`
compiles `and` guarding a `pushmark`/`return` pair.

That is why this tier declares 06_control as its prerequisite. Without a
branch there is no early exit, without an early exit there is no `return`
op, and the construct the tier is named for would be unobservable in any
optree the corpus could produce.

Both of those live in the sub's own optree, which a main-program
measurement does not reach. The BEHAVIOUR is what this case asserts and
it distinguishes the two: `classify(0)` prints `zero` only if the early
return fired, and `positive` only if it did not.

```perl
sub classify {
    return "zero" if $_[0] == 0;
    return "negative" if $_[0] < 0;
    return "positive";
}
print classify(0), " ", classify(-5), " ", classify(7), "\n";
```

```behavior
parses: yes
```

```output
zero negative positive
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::classify, param_names: [], want: list}, [2], 0, Str], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 5
  [Constant, {const_type: integer, value: "-5"}, ~, ~, Int], # 6
  [Call, {dispatch_kind: direct, name: main::classify, param_names: [], want: list}, [6], 3, Str], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 9
  [Call, {dispatch_kind: direct, name: main::classify, param_names: [], want: list}, [9], 7, Str], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [4, 5, 8, 5, 11, 12], 10, Scalar], # 13
  [Return, ~, [1], 13]]} # 14
main::classify: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: zero}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: negative}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: positive}, ~, ~, Str], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Subscript, ~, [4, 5, 6], ~, Scalar], # 7
  [Coerce, {from_repr: Scalar, to_repr: Num}, [7], ~, Num], # 8
  [NumEq, ~, [8, 5], ~, Boolean], # 9
  [If, ~, [0, 9], 0], # 10
  [Proj, {index: 0}, [10]], # 11
  [Proj, {index: 1}, [10]], # 12
  [NumLt, ~, [8, 5], ~, Boolean], # 13
  [If, ~, [12, 13], 12], # 14
  [Proj, {index: 0}, [14]], # 15
  [Proj, {index: 1}, [14]], # 16
  [Region, ~, [11, 15, 16]], # 17
  [Phi, {predecessors: [11, 15, 16], region: 17}, [1, 2, 3], ~, Str], # 18
  [Return, ~, [18], 17]]} # 19
```

## A bare `return` needs no terminator before the closing brace

`return` with no argument and NO SEMICOLON, last in the sub's body. perl
makes a statement's final `;` optional before a `}`, so `sub f { return }`
is legal -- and it is how perl's own suite writes an early-exit stub:
`sub A::MODIFY_SCALAR_ATTRIBUTES { return }` opens both `op/attrs.t` and
`uni/attrs.t`.

THE PARSER READ THE CLOSER AS THE OPERAND. `parseReturn` asked whether the
next token was a semicolon and, at the end of a block, it is a `}` -- so
the operand hunt consumed the brace, taking it out of the enclosing sub and
leaving canon to emit a spurious `};`. Measured across perl.git `t/`, four
files and 61 Unknown nodes (issue 01a0dfb8). `last`, `next` and `redo`
never had the bug: they ask whether the next token is a WORD that could be
a label, which a closer is not.

WHAT THE OUTPUT PINS IS THE VALUE, not the parse. A bare `return` yields
the EMPTY LIST in list context and `undef` in scalar context, and those are
different claims -- `scalar(@empty)` is 0 rather than 1, so the empty list
is genuinely empty and not a one-element list holding `undef`. A parser
that swallowed the brace could still print this if it recovered, which is
why the unit tests assert the canonical text as well.

```perl
sub bare { return }
sub valued { return "v" }
my @empty = bare();
my @one   = valued();
my $scalar = bare();
print scalar(@empty), " ", scalar(@one), " ",
      (defined $scalar ? "def" : "undef"), "\n";
```

```behavior
parses: yes
```

```output
0 1 undef
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: direct, name: main::bare, param_names: [], want: list}, ~, 0, Undef], # 2
  [ArrayLiteral, {sigil: "@", symbol: empty}, [2], ~, Array], # 3
  [MemStart], # 4
  [Count, ~, [3, 4], ~, Int], # 5
  [Coerce, {from_repr: Int, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 7
  [Call, {dispatch_kind: direct, name: main::valued, param_names: [], want: list}, ~, 2, Str], # 8
  [ArrayLiteral, {sigil: "@", symbol: one}, [8], ~, Array], # 9
  [Count, ~, [9, 4], ~, Int], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [Call, {dispatch_kind: direct, name: main::bare, param_names: [], want: scalar}, ~, 8, Undef], # 12
  [Defined, ~, [12], ~, Boolean], # 13
  [Constant, {const_type: string, value: def}, ~, ~, Str], # 14
  [Constant, {const_type: string, value: undef}, ~, ~, Str], # 15
  [TernaryExpr, ~, [13, 14, 15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [6, 7, 11, 7, 16, 17], 12, Scalar], # 18
  [Return, ~, [1], 18]]} # 19
main::bare: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::valued: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: v}, ~, ~, Str], # 1
  [Return, ~, [1], 0]]} # 2
```
