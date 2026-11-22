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
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::describe, package: main, param_names: [], want: list}, [2, 3, 4], 0, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
main::describe: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Subscript, {kind: array}, [1, 8], ~, Scalar, 3], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Concat, ~, [7, 10], ~, Str], # 11
  [Concat, ~, [11, 6], ~, Str], # 12
  [Count, ~, [1], ~, Int, 3], # 13
  [Coerce, {from_repr: Int, to_repr: Str}, [13], ~, Str], # 14
  [Concat, ~, [12, 14], ~, Str], # 15
  [Return, ~, [15], 0, ~, 3]]} # 16
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
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::add_up, package: main, param_names: [], want: list}, [2], 0, Num, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::add_up, package: main, param_names: [], want: list}, [2, 7], 4, Num, 4, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Print, ~, [5, 6, 9, 10], 8, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 8]]} # 12
main::add_up: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Parameter, {index: 0, name: $a, sigil: $}, ~, ~, Num], # 1
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 2
  [Parameter, {default_when: absent, index: 1, name: $b, sigil: $}, [2], ~, Num], # 3
  [Add, ~, [1, 3], ~, Num], # 4
  [MemStart], # 5
  [Return, {implicit: true}, [4], 0, ~, 5]]} # 6
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1], 0, Unknown, 2, true], # 3
  [Return, {implicit: true}, [3], 3, ~, 3]]} # 4
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
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: aliased}, ~, ~, Unknown, 2], # 3
  [PadAccess, {sigil: $, symbol: untouched}, ~, ~, Unknown, 2], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Assign, {targets: 2}, [3, 4, 5, 5], 0, List, 2, true], # 6
  [PadAccess, {sigil: $, symbol: aliased}, ~, ~, Unknown, 6], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::bump_alias, package: main, param_names: [], want: void}, [7], 6, Scalar, 6, true], # 8
  [PadAccess, {sigil: $, symbol: untouched}, ~, ~, Unknown, 8], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: main::bump_copy, package: main, param_names: [], want: void}, [9], 8, Scalar, 8, true], # 10
  [PadAccess, {sigil: $, symbol: aliased}, ~, ~, Str, 10], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [PadAccess, {sigil: $, symbol: untouched}, ~, ~, Str, 10], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [14, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Print, ~, [19], 10, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 10]]} # 21
main::bump_alias: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], 0, Scalar, 3], # 4
  [DefinedOr, ~, [4, 2], ~, Scalar], # 5
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 6
  [Increment, ~, [4], ~, Scalar], # 7
  [Assign, ~, [6, 7], 4, Scalar, 3, true], # 8
  [Return, {implicit: true}, [5], 8, ~, 8]]} # 9
main::bump_copy: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [DefinedOr, ~, [1, 2], ~, Scalar], # 3
  [MemStart], # 4
  [Return, {implicit: true}, [3], 0, ~, 4], # 5
  [ArgsSource, ~, ~, ~, Array], # 6
  [Assign, {record: true, targets: 1}, [1, 6], ~, List], # 7
  [Increment, ~, [1], ~, Scalar]]} # 8
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
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: main::classify, package: main, param_names: [], want: list}, [2], 0, Str, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Constant, {const_type: integer, value: "-5"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: main::classify, package: main, param_names: [], want: list}, [7], 4, Str, 4, true], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: main::classify, package: main, param_names: [], want: list}, [10], 8, Str, 8, true], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Print, ~, [5, 6, 9, 6, 12, 13], 11, "Maybe[Boolean]"], # 14
  [Return, {implicit: true}, [1], 14, ~, 11]]} # 15
main::classify: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: zero}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: negative}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: positive}, ~, ~, Str], # 3
  [ArgsSource, ~, ~, ~, Array], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [MemStart], # 6
  [Subscript, {kind: array}, [4, 5], ~, Scalar, 6], # 7
  [Coerce, {from_repr: Scalar, to_repr: Num}, [7], ~, Num], # 8
  [NumEq, ~, [8, 5], ~, Boolean], # 9
  [If, ~, [0, 9], 0], # 10
  [Proj, {index: 1}, [10]], # 11
  [NumLt, ~, [8, 5], ~, Boolean], # 12
  [If, ~, [11, 12], 11], # 13
  [Proj, {index: 0}, [13]], # 14
  [Proj, {index: 1}, [13]], # 15
  [Region, {head: 13}, [14, 15]], # 16
  [Phi, {predecessors: [14, 15], region: 16}, [2, 3], ~, Str], # 17
  [Proj, {index: 0}, [10]], # 18
  [Region, {head: 10}, [18, 16]], # 19
  [Phi, {predecessors: [18, 11], region: 19}, [1, 17], ~, Str], # 20
  [Return, ~, [20], 19, ~, 6]]} # 21
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
  [MemStart], # 2
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::bare, package: main, param_names: [], want: list}, ~, 0, List, 2, true], # 3
  [ArrayLiteral, {sigil: "@", symbol: empty}, [3], ~, Array], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::valued, package: main, param_names: [], want: list}, ~, 3, Str, 3, true], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::bare, package: main, param_names: [], want: scalar}, ~, 5, List, 5, true], # 6
  [Count, ~, [4], ~, Int, 6], # 7
  [Coerce, {from_repr: Int, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [ArrayLiteral, {sigil: "@", symbol: one}, [5], ~, Array], # 10
  [Count, ~, [10], ~, Int, 6], # 11
  [Coerce, {from_repr: Int, to_repr: Str}, [11], ~, Str], # 12
  [Defined, ~, [6], ~, Boolean], # 13
  [Constant, {const_type: string, value: def}, ~, ~, Str], # 14
  [Constant, {const_type: string, value: undef}, ~, ~, Str], # 15
  [TernaryExpr, ~, [13, 14, 15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [8, 9, 12, 9, 16, 17], 6, "Maybe[Boolean]"], # 18
  [Return, {implicit: true}, [1], 18, ~, 6]]} # 19
main::bare: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [ArrayLiteral, ~, ~, ~, List], # 1
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 2
  [MemStart], # 3
  [Return, ~, [1, 2], 0, ~, 3]]} # 4
main::valued: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: v}, ~, ~, Str], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
```

## A `map` topic passed to a sub

`$_` inside `map` is an alias for the current element, and passing it
to a sub passes that alias on, so perl flags the `gvsv` `OPf_MOD`. It
is still a read of the current element, not of the global `$_`: an
implementation that reads the flag as a write, or the op as the
global, prints the wrong thing. Found by B::SoN translating chalk's
lib/ and running chalk's own suite against the emitted Perl.

```perl
sub shout { return uc $_[0] }
my @loud = map { shout($_) } qw(a b c);
print "@loud\n";
```

```behavior
parses: yes
```

```output
A B C
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {memory: true, region: 3}, [2, 30], ~, Unknown], # 4
  [Proj, {index: 1}, [3]], # 5
  [Region, {head: 3}, [5]], # 6
  [Phi, {memory: true, region: 6}, [4], ~, Unknown], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 7], # 8
  [Coerce, {from_repr: Scalar, to_repr: Str}, [8], ~, Str], # 9
  [ArrayLiteral, ~, ~, ~, Array], # 10
  [Phi, {region: 3}, [10, 34], ~, Array], # 11
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [9, 11], ~, Str, 7], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [Print, ~, [14], 6, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 7], # 16
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 17
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 18
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 19
  [ArrayLiteral, ~, [17, 18, 19], ~, List], # 20
  [Count, ~, [20], ~, Int, 4], # 21
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 22
  [Phi, {region: 3}, [22, 32], ~, Int], # 23
  [NumGt, ~, [21, 23], 3, Boolean], # 24
  [Proj, {index: 0}, [3]], # 25
  [Subscript, {kind: array}, [20, 23], ~, Scalar], # 26
  [Ref, ~, [26], ~, ScalarRef], # 27
  [LocalAlias, {name: _}, [27], 25, Unknown, 4], # 28
  [Subscript, {kind: array}, [20, 23], ~, Str, 4], # 29
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::shout, package: main, param_names: [], want: list}, [29], 28, Str, 4, true], # 30
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 31
  [Add, ~, [23, 31], ~, Int], # 32
  [Count, ~, [20], ~, Int, 2], # 33
  [ListAppend, {collector: map}, [11, 30], ~, Array]]} # 34
main::shout: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Call, {dispatch_kind: builtin, name: uc, param_names: []}, [4], ~, Str], # 5
  [Return, ~, [5], 0, ~, 3]]} # 6
```

## A loop variable passed to a sub

The argument is an alias the callee could write through `$_[0]`, and
it is still the loop's value on each pass: `twice` reads `1`, `2` and
`3`. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl, which compiled and gave a wrong answer.

```perl
sub twice { return $_[0] * 2 }
my @r;
for my $n (1 .. 3) { push @r, twice($n) }
print "@r\n";
```

```behavior
parses: yes
```

```output
2 4 6
```

```ir
main::__PROGRAM__: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {memory: true, region: 3}, [2, 25], ~, Unknown], # 4
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
  [Constant, {const_type: integer, value: "4"}, ~, ~, Int], # 16
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 17
  [Phi, {region: 3}, [17, 26], ~, Int], # 18
  [NumGt, ~, [16, 18], 3, Boolean], # 19
  [Proj, {index: 0}, [3]], # 20
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown, 4], # 21
  [Assign, ~, [21, 18], 20, Int, 4, true], # 22
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown, 22], # 23
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::twice, package: main, param_names: [], want: list}, [23], 22, Num, 22, true], # 24
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [10, 24], 24, Int, 24, true], # 25
  [Add, ~, [18, 17], ~, Int]]} # 26
main::twice: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Return, ~, [7], 0, ~, 3]]} # 8
```

## A foreach alias written through `$_[0]`

`$x` aliases each element of `@a`, and `$_[0]` aliases `$x`, so the
callee's `$_[0]++` reaches the array itself. Found by B::SoN translating chalk's lib/ and running chalk's own suite
against the emitted Perl, which compiled and gave a wrong answer.

```perl
sub bump { $_[0]++ }
my @a = (1, 2);
for my $x (@a) { bump($x) }
print "@a\n";
```

```behavior
parses: yes
```

```output
2 3
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [Loop, {bound: entry}, [0], 0], # 3
  [Phi, {memory: true, region: 3}, [2, 31], ~, Unknown], # 4
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
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 15
  [Concat, ~, [14, 15], ~, Str], # 16
  [Print, ~, [16], 6, "Maybe[Boolean]"], # 17
  [Return, {implicit: true}, [1], 17, ~, 7], # 18
  [Count, ~, [12], ~, Int, 4], # 19
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 20
  [Phi, {region: 3}, [20, 32], ~, Int], # 21
  [NumGt, ~, [19, 21], 3, Boolean], # 22
  [Proj, {index: 0}, [3]], # 23
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 4], # 24
  [Subscript, {kind: array}, [12, 21], ~, Int, 4], # 25
  [Assign, ~, [24, 25], 23, Int, 4, true], # 26
  [Subscript, {kind: array}, [12, 21], ~, Scalar], # 27
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 26], # 28
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::bump, package: main, param_names: [], want: void}, [28], 26, Scalar, 26, true], # 29
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 29], # 30
  [Assign, {if_changed: true}, [27, 30], 29, Unknown, 29, true], # 31
  [Add, ~, [21, 10], ~, Int], # 32
  [Count, ~, [12], ~, Int, 2]]} # 33
main::bump: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], 0, Scalar, 3], # 4
  [DefinedOr, ~, [4, 2], ~, Scalar], # 5
  [Subscript, {kind: array}, [1, 2], ~, Scalar], # 6
  [Increment, ~, [4], ~, Scalar], # 7
  [Assign, ~, [6, 7], 4, Scalar, 3, true], # 8
  [Return, {implicit: true}, [5], 8, ~, 8]]} # 9
```

## An iterator passed to a call, over read-only values

A foreach iterator aliases its element, and a callee given it may change the element through `$_[0]`. These elements are constants, which perl never writes: writing each one back after the body dies "Modification of a read-only value". Found by B::SoN translating chalk's lib/ and running chalk's own suite against the emitted Perl.

```perl
sub id { $_[0] }
sub keep {
    my $out = "";
    for my $x (@_) {
        next unless id($x) > 1;
        $out .= $x;
    }
    return $out;
}
print keep(1, 2, 3), "\n";
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
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 10, name: main::keep, package: main, param_names: [], want: list}, [2, 3, 4], 0, Str, 5, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 6, "Maybe[Boolean]"], # 9
  [Return, {implicit: true}, [1], 9, ~, 6]]} # 10
main::id: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Return, {implicit: true}, [4], 0, ~, 3]]} # 5
main::keep: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Phi, {region: 2}, [1, 37], ~, Str], # 3
  [Proj, {index: 1}, [2]], # 4
  [Region, {head: 2}, [4]], # 5
  [MemStart], # 6
  [Phi, {memory: true, region: 2}, [6, 24], ~, Unknown], # 7
  [Phi, {memory: true, region: 5}, [7], ~, Unknown], # 8
  [Return, ~, [3], 5, ~, 8], # 9
  [ArgsSource, ~, ~, ~, Array], # 10
  [Count, ~, [10], ~, Int, 7], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Phi, {region: 2}, [12, 38], ~, Int], # 13
  [NumGt, ~, [11, 13], 2, Boolean], # 14
  [Proj, {index: 0}, [2]], # 15
  [Exists, {kind: array}, [10, 13], 15, Boolean, 7], # 16
  [Subscript, {kind: array}, [10, 13], ~, Scalar], # 17
  [Ref, ~, [17], ~, ScalarRef], # 18
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 19
  [TernaryExpr, ~, [16, 18, 19], 16, "Maybe[ScalarRef]"], # 20
  [PostfixDeref, {sigil: $}, [20], ~, Scalar, 7], # 21
  [Subscript, {kind: array}, [10, 13], ~, Scalar, 7], # 22
  [TernaryExpr, ~, [16, 21, 22], ~, Scalar], # 23
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::id, package: main, param_names: [], want: scalar}, [23], 20, Scalar, 7, true], # 24
  [PostfixDeref, {sigil: $}, [20], ~, Scalar, 24], # 25
  [Subscript, {kind: array}, [10, 13], ~, Scalar, 24], # 26
  [Coerce, {from_repr: Scalar, to_repr: Num}, [24], ~, Num], # 27
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 28
  [NumGt, ~, [27, 28], ~, Boolean], # 29
  [If, ~, [24, 29], 24], # 30
  [Proj, {index: 0}, [30]], # 31
  [TernaryExpr, ~, [16, 25, 26], 31, Scalar], # 32
  [Coerce, {from_repr: Scalar, to_repr: Str}, [32], ~, Str], # 33
  [Concat, ~, [3, 33], ~, Str], # 34
  [Proj, {index: 1}, [30]], # 35
  [Region, {head: 30}, [35, 32]], # 36
  [Phi, {predecessors: [35, 31], region: 36}, [3, 34], ~, Str], # 37
  [Add, ~, [13, 28], ~, Int], # 38
  [Count, ~, [10], ~, Int, 6]]} # 39
```
