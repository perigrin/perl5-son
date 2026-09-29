# Taking a reference

The constructs that PRODUCE a reference -- the backslash in both
contexts, the anonymous array constructor -- and the builtin that reads
one back.

**Tier 08 references.** Introduces `anonlist`, `prototype`, `ref`,
`refgen`, `rv2cv`, `rv2sv`, `srefgen`. Depends on 07_subroutines.

Every case takes a reference to a VARIABLE, never to a literal. `my $r
= \1` arrives as `const[IV \1] s/FOLD` and emits no `srefgen` at all:
the optimiser erases the very construct the tier is about. The array
and hash fixtures are what defeat that, and it is the same lesson tier
01 learned from `1+2`.

Nor does any case print a reference. A reference stringifies as
`ARRAY(0x5606f0a12345)` and the address changes every run, so `ref`
supplies the stable category name instead.

## The backslash in scalar context

`\@a` in scalar context is one op, `srefgen`, and the array it points
at stays reachable through the scalar that holds it.

The optree is `padav[@a] lRM`, then `srefgen sK/1`, then
`padsv_store[$s]` -- the array is loaded first and the reference taken
of it, which is why this tier cannot precede tier 02.

```perl
my @a = (10, 20);
my $s = \@a;
print "$$s[0] $$s[1]\n";
```

```behavior
parses: yes
```

```output
10 20
```

```tokens
one operator whose text is "\\"
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "20"}, ~, ~, Int], # 3
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3], ~, Array], # 4
  [Ref, ~, [4], ~, ArrayRef], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [MemStart], # 7
  [Subscript, ~, [5, 6, 7], ~, Scalar], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 12
  [Subscript, ~, [5, 12, 7], ~, Scalar], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Concat, ~, [11, 14], ~, Str], # 15
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Print, ~, [17], 0, Scalar], # 18
  [Return, ~, [1], 18]]} # 19
```

## The same backslash in list context

The SAME backslash in list context is a DIFFERENT op: `\(@a)` emits
`refgen`, not `srefgen`, and distributes over the array's elements.

This case and the scalar one above differ in source only by the
parentheses and the assignment target, and perl compiles them to two
different ops. That is why the tier claims both: one spelling in the
source is two ops in the optree, and a corpus that wrote only the
scalar form would claim an op it never exercised.

The distribution is the second surprise. `\(@a)` is not a reference to
the array -- it is a LIST of references, one per element, so `$r[0]` is
a SCALAR reference and `${$r[0]}` is the element behind it. Writing
`$r[0]->[0]` instead dies with "Not an ARRAY reference", which is how
this case arrived at its current form.

```perl
my @a = (10, 20);
my @r = \(@a);
print ${$r[0]}, " ", ${$r[1]}, "\n";
```

```behavior
parses: yes
```

```output
10 20
```

```tokens
one operator whose text is "\\"
```

```ir
main::__PROGRAM__: {start: 0, returns: [19], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "20"}, ~, ~, Int], # 3
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3], ~, Array], # 4
  [Ref, {each: true}, [4], ~, List], # 5
  [ArrayLiteral, {sigil: "@", symbol: r}, [5], ~, Array], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [MemStart], # 8
  [Subscript, ~, [6, 7, 8], ~, Scalar], # 9
  [PostfixDeref, {sigil: $}, [9], ~, Scalar], # 10
  [Coerce, {from_repr: Scalar, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 12
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 13
  [Subscript, ~, [6, 13, 8], ~, Scalar], # 14
  [PostfixDeref, {sigil: $}, [14], ~, Scalar], # 15
  [Coerce, {from_repr: Scalar, to_repr: Str}, [15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Print, ~, [11, 12, 16, 17], 0, Scalar], # 18
  [Return, ~, [1], 18]]} # 19
```

## The anonymous array constructor

`[10, 20, 30]` builds an array and yields a reference to it in one op,
`anonlist`, with no named array anywhere in the program.

The anonymous HASH constructor is deliberately NOT here. `{}` and
`{ %a }` compile to `emptyavhv` and `anonhash`, which tier 11 claims
where objects are built; writing one in this tier would use an op a
LATER tier owns and the lint would refuse it. `[...]` alone is tier
08's.

`ref` is what makes the assertion deterministic -- it prints the stable
category name rather than an address that changes every run.

```perl
my $r = [10, 20, 30];
print scalar(@$r), " ", ref($r), "\n";
```

```behavior
parses: yes
```

```output
3 ARRAY
```

```tokens
one operator whose text is "["
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "20"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "30"}, ~, ~, Int], # 4
  [ArrayLiteral, ~, [2, 3, 4], ~, ArrayRef], # 5
  [MemStart], # 6
  [PostfixDeref, {sigil: "@"}, [5, 6], ~, Array], # 7
  [Count, ~, [7, 6], ~, Int], # 8
  [Coerce, {from_repr: Int, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [RefType, ~, [5], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [9, 10, 11, 12], 0, Scalar], # 13
  [Return, ~, [1], 13]]} # 14
```

## `ref` over all three referent kinds

`ref` reports what a reference points at, and it is the one operation
in this tier that has no home in an earlier one. The tier description
does not mention it; the op measurement is where it came from. Its
operand is a reference and its result is a plain string, so no earlier
tier can claim it -- there is nothing for it to be about before this
tier.

It is also what every other case here leans on for determinism.

The three categories are measured together because the op is the same
for all of them: `ref` does not discriminate by sigil, the referent
does.

```perl
my @a = (1);
my %h = (k => 1);
my $n = 5;
my $ar = \@a;
my $hr = \%h;
my $sr = \$n;
print ref($ar), " ", ref($hr), " ", ref($sr), " ", ${$sr}, "\n";
```

```behavior
parses: yes
```

```output
ARRAY HASH SCALAR 5
```

```tokens
one operator whose text is "{"
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [ArrayLiteral, {sigil: "@", symbol: a}, [2], ~, Array], # 3
  [Ref, ~, [3], ~, ArrayRef], # 4
  [RefType, ~, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 7
  [HashLiteral, {sigil: "%", symbol: h}, [7, 2], ~, Hash], # 8
  [Ref, ~, [8], ~, HashRef], # 9
  [RefType, ~, [9], ~, Str], # 10
  [MemStart], # 11
  [PadAccess, {sigil: $, symbol: "n"}, [11], ~, Unknown], # 12
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 13
  [Assign, ~, [12, 13], 0, Int], # 14
  [PadAccess, {sigil: $, symbol: "n"}, [14], ~, Unknown], # 15
  [Ref, ~, [15], ~, Unknown], # 16
  [RefType, ~, [16], ~, Str], # 17
  [PostfixDeref, {sigil: $}, [16], ~, Scalar], # 18
  [Coerce, {from_repr: Scalar, to_repr: Str}, [18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Print, ~, [5, 6, 10, 6, 17, 6, 19, 20], 14, Scalar], # 21
  [Return, ~, [1], 21]]} # 22
```
