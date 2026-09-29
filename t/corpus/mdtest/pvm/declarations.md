# Lexical declarations

`my`, `our` and `state`: three ways to bind a NAME for a region of
source, told apart by what the name refers to and when its
initialisation runs.

**Tier 05 scoping.** Introduces `enterloop`, `leaveloop`, `once`.
Depends on 04_operators.

THREE OPS FOR FIVE CONSTRUCTS IS NOT TIDY, AND IT IS WHAT PERL EMITS.
Measured under 5.42.0 with `perl -MO=Concise,-exec`, `my` has no op of
its own: `my $x = 1` compiles to `const` then `padsv_store[$x]
vKS/LVINTRO`, both tier 01's, claimed there. `our` emits `gvsv` and
`sassign`, both tier 02's. What separates them is a FLAG -- `gvsv[*x]
s/OURINTR` against plain `gvsv[*x] s` -- and the ops list does not
record flags. Only `state` adds an op of its own, `once`.

So the op stream cannot tell these cases from earlier tiers' cases, and
the OUTPUT is what distinguishes them. Every case below prints from two
live declarations of the same name, because a parser that conflates two
of these forms still produces a plausible tree and is caught only by the
value it prints.

## `my` shadows, and the outer binding survives

This is where `my` stops being scaffolding. Tier 01 writes `my $x = 1`
in every case, but only to hold a literal still; nothing there asks what
the `my` does. Here the question is the scope, and the answer is visible
only because two declarations of the SAME NAME are live at once and
print different values.

The op stream cannot tell this case from a tier 01 one. Both emit
`const` then `padsv_store[$x] vKS/LVINTRO`, and the two `$x` differ only
by pad slot -- `[$x:1,5]` against `[$x:3,4]` in the concise output. That
is the honest position of this whole tier: what distinguishes it is the
declared subject, not the op set.

The block brings `enterloop`/`leaveloop` with it, which is this tier's
own op pair and the subject of the bare block case.

```perl
my $x = 1;
{
  my $x = 2;
  print "$x\n";
}
print "$x\n";
```

```behavior
parses: yes
```

```output
2
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Coerce, {from_repr: Int, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Coerce, {from_repr: Int, to_repr: Str}, [6], ~, Str], # 7
  [Concat, ~, [7, 4], ~, Str], # 8
  [Print, ~, [8], 0, Scalar], # 9
  [Print, ~, [5], 9, Scalar], # 10
  [Return, ~, [1], 10]]} # 11
```

## `our` names a package variable, and the shadow proves it

`our $x = 1` looks like `my $x = 1` and is nothing like it: `my` makes a
pad slot, `our` makes a lexically-scoped NAME for a symbol-table entry
that already exists. The probe is the shadow -- inside the block `$x` is
the `my`, and `$main::x` is the `our`'s referent, unshadowed and still
1. A parser that read `our` as `my` would print `2 2`, or nothing at
all.

It emits no op of its own; `gvsv` and `sassign` are tier 02's, and the
difference from a bare assignment is the `s/OURINTR` flag the ops list
cannot see. The output is what distinguishes the constructs here, which
is why the case exists even though the op stream has nothing new to
show.

No `use strict`, so the qualified `$main::x` needs no declaration of its
own; the `our` on line 1 is what makes the unqualified `$x` inside the
block refer to the same scalar.

```perl
our $x = 1;
{
  my $x = 2;
  print "$x $main::x\n";
}
print "$x\n";
```

```behavior
parses: yes
```

```output
2 1
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [EntryWrite, ~, [2, 3, 4], 0, Unknown], # 5
  [EntryDef, {package: main, sigil: $, symbol: x}, [5], ~, Int], # 6
  [Coerce, {from_repr: Int, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Concat, ~, [13, 7], ~, Str], # 14
  [Concat, ~, [14, 8], ~, Str], # 15
  [Print, ~, [15], 5, Scalar], # 16
  [Print, ~, [9], 16, Scalar], # 17
  [Return, ~, [1], 17]]} # 18
```

## `state` scopes like `my`, and initialises once

`state $n = 1` compiles to `once(other->...)` wrapped around an
otherwise ordinary `padsv_store[$n] vKS/LVINTRO,STATE`. The pad op is
tier 01's; `once` is the whole of what `state` adds, and it is this
tier's only op a single construct owns outright.

WHAT THIS CASE CANNOT SHOW, and why that is not a gap. The point of
`state` is that the value persists across calls, which needs a sub to
call twice. `sub` is tier 07 and `entersub` is not in this tier's
budget; a bare block is the only re-enterable-LOOKING construct
available and it is not re-enterable -- it runs exactly once, so `once`
firing once is indistinguishable from an ordinary initialisation. The
behavioural probe for persistence belongs to tier 07. What is asserted
here is the part that IS observable: the declaration compiles, and its
scoping is lexical.

The `use feature "state"` line is a tier 12 construct in a tier 05 case,
affordable because it emits NO RUNTIME OP -- measured, not assumed.
Under `-MO=Concise,-exec` the pragma leaves nothing in the op stream at
all; it only flips a bit in the `nextstate` hints field
(`v:%,{,fea=15`), and the lint reads op names, not hints. `use v5.36`
was measured too: same ops, a different hints value. The explicit
feature import is preferred because it names the one thing this case
needs rather than dragging in a bundle.

```perl
use feature "state";
state $n = 1;
{
  state $n = 2;
  print "$n\n";
}
print "$n\n";
```

```behavior
parses: yes
```

```output
2
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Coerce, {from_repr: Int, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Coerce, {from_repr: Int, to_repr: Str}, [6], ~, Str], # 7
  [Concat, ~, [7, 4], ~, Str], # 8
  [Print, ~, [8], 0, Scalar], # 9
  [Print, ~, [5], 9, Scalar], # 10
  [Return, ~, [1], 10]]} # 11
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: state}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```
