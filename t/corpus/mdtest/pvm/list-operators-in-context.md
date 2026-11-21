# List operators, each asked twice

Five operators that answer a different question depending on what
received the answer. Each appears twice below, once with the `s` flag
and once with `l`, because one half alone asks the parser for one answer
where the construct has two.

**Tier 03 context.** Introduces `reverse`, `sort`, `localtime`,
`mapstart`, `mapwhile`, `grepstart`, `grepwhile`. Depends on
02_variables.

None of these cases is separated from its own other half by an op NAME.
`my $x = reverse @a` emits `reverse sK/1` and `my @b = reverse @a`
emits `reverse lK/1` -- same op, same operand, different answer. The
discrimination is in the flag and in the OUTPUT, which is why the output
blocks carry this topic's weight.

## `reverse`: reversed elements, or a reversed string

In list context `reverse` reverses the elements; in scalar context it
concatenates them and reverses the characters. Same op and same operand
twice: `my @b = reverse @a` emits `reverse lK/1`, `my $s = reverse @a`
emits `reverse sK/1`. The CONTEXT FLAG is the claim; the targ number
beside it is pad allocation and is not stable enough to assert.

The scalar result is `321` and not `3 2 1`: reversing in scalar context
first joins the list with nothing between the elements, then reverses
the resulting string. A parser that treats the two as one operation on
"a value" has no way to say which of these it means.

```perl
my @a = (1, 2, 3);
my @b = reverse @a;
my $s = reverse @a;
print "@b $s\n";
```

```behavior
parses: yes
```

```output
3 2 1 321
```

```tokens
one variable whose text is "@b"
one variable whose text is "$s"
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 2], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: builtin, name: reverse, param_names: []}, [5, 6, 7], ~, List], # 8
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 8], ~, Str, 2], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Call, {dispatch_kind: builtin, name: reverse, param_names: []}, [5, 6, 7], ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Print, ~, [15], 0, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 2], # 17
  [ArrayLiteral, {sigil: "@", symbol: a}, [5, 6, 7], ~, Array]]} # 18
```

## `sort`, and the `() =` count idiom in both contexts

`sort` in list context returns the sorted elements. The second statement
is the count idiom, `my $n = () = sort @a`, which is the only way to
observe the list-versus-scalar distinction on an `aassign`: the inner
assignment to an empty list runs in list context, and the outer
assignment then asks it how many elements it moved --
`aassign sKS` -- the `s` is the claim, and the targ number beside it
is pad allocation rather than something to assert.

The third statement is that same idiom with an ARRAY receiving it, and
it is what makes the second a pair rather than a single measurement:
`my @c = (() = sort @a)` emits an `aassign` too. Same op, same
operand, same spelling of the idiom, and unrelated answers. In scalar
context the empty-list assignment reports how many elements it moved,
which is 3; in list context it yields what it assigned, which is the
empty list, so `@c` has 0 elements. Nothing in the source says which.
Without the third statement the `aassign` here is only ever seen with
`s`, and the claim that context is a flag would be made by a case that
never shows the other value of the flag.

No comparator block appears on purpose: `sort { $a <=> $b } @a` would
drag in a block and the comparison operator, which belong to later
tiers. Default sort is a string sort, which is why the digits come back
in the order they do.

```perl
my @a = (3, 1, 2);
my @b = sort @a;
my $n = () = sort @a;
my @c = (() = sort @a);
print "@b $n ", scalar(@c), "\n";
```

```behavior
parses: yes
```

```output
1 2 3 3 0
```

```tokens
one variable whose text is "$n"
one variable whose text is "@b"
```

```ir
main::__PROGRAM__: {start: 0, returns: [22], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 2], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [5, 6, 7], ~, List], # 8
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 8], ~, Str, 2], # 9
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [5, 6, 7], ~, List], # 12
  [Count, ~, [12], ~, Int, 2], # 13
  [Coerce, {from_repr: Int, to_repr: Str}, [13], ~, Str], # 14
  [Concat, ~, [11, 14], ~, Str], # 15
  [Concat, ~, [15, 10], ~, Str], # 16
  [ArrayLiteral, {sigil: "@", symbol: c}, ~, ~, Array], # 17
  [Count, ~, [17], ~, Int, 2], # 18
  [Coerce, {from_repr: Int, to_repr: Str}, [18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Print, ~, [16, 19, 20], 0, "Maybe[Boolean]"], # 21
  [Return, {implicit: true}, [1], 21, ~, 2], # 22
  [ArrayLiteral, {sigil: "@", symbol: a}, [5, 6, 7], ~, Array], # 23
  [Call, {dispatch_kind: builtin, name: sort, param_names: [], sort_cmp: string, sort_order: ascending}, [5, 6, 7], ~, List]]} # 24
```

## `localtime`: a nine-element list, or one string

The sharpest discriminator in the tier, because its two contexts return
unrelated TYPES. `reverse` and `sort` return rearrangements of the same
data either way. `localtime` in list context is
(sec,min,hour,mday,mon,year,wday,yday,isdst), and in scalar context a
formatted string like `Sun Sep 21 14:03:11 2026`. Nothing about the call
site says which; the assignment target decides.

What this case pins is deliberately NOT the time. `localtime` depends on
the clock and the timezone, so pinning either result verbatim would make
it fail tomorrow and in another zone. Both assertions are facts about
SHAPE: the list has nine elements always, and the scalar string is one
element always. That is exactly the contextual difference, and it is the
part that does not move.

```perl
my $n = () = localtime;
my $s = localtime;
my @c = ($s);
print "$n ", scalar(@c), "\n";
```

```behavior
parses: yes
```

```output
9 1
```

```tokens
one variable whose text is "$n"
one word whose text is "scalar"
```

```ir
main::__PROGRAM__: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: builtin, name: localtime, param_names: []}, ~, ~, List], # 2
  [MemStart], # 3
  [Count, ~, [2], ~, Int, 3], # 4
  [Coerce, {from_repr: Int, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Call, {dispatch_kind: builtin, name: localtime, param_names: []}, ~, ~, Scalar], # 8
  [ArrayLiteral, {sigil: "@", symbol: c}, [8], ~, Array], # 9
  [Count, ~, [9], ~, Int, 3], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [7, 11, 12], 0, "Maybe[Boolean]"], # 13
  [Return, {implicit: true}, [1], 13, ~, 3]]} # 14
```

## `map BLOCK` and `map EXPR`, a fork the optree cannot see

`map` takes either a BLOCK or an EXPRESSION, and the two forms are a
genuine parse fork -- `map BLOCK LIST` takes no comma after the block,
`map EXPR, LIST` requires one. Measured, `my @b = map { $_ } @a` and
`my @b = map($_, @a)` emit the same ops, in the same order, with the
same flags and targs:

    pushmark, pushmark, padav[@a] lM, mapstart lK, mapwhile lK, gvsv[*_]

So nothing an op-name lint reads distinguishes the halves, and a parser
that took the comma form for the block form emits an identical optree.
This case therefore asserts at the TOKEN STREAM: the comma IS the fork,
the source is written to contain exactly one (`qw()` builds the list
without any), and the token fact counts it. A parser that admitted a
comma after a block, or required one, changes that count.

What is not identical is not an op. The two optrees differ in the COP
SEQUENCE RANGE beside each lexical: `padav[@a:1,5]` under the block form
against `padav[@a:1,3]` under the expression form. A block is a SCOPE,
and measured, a bare `{ 1; }` standing where the map block stands
advances the counter by exactly the same 2. The trace is in pad
metadata, which the op-name lint does not read. "Byte-identical" is too
strong; "identical in every op" is the measured claim.

The fourth statement is the discriminating pair: `my $n = map { $_ } @a`
emits `mapstart sK` where the two before it emit `mapstart lK`, and in
scalar context the answer is the COUNT of what the list form returns.

The list is opened up by `$ENV{M}` because a CONSTANT argument erases
the construct. `$ENV{M}` is unset when the runner executes, so
`"$ENV{M}a"` is the one-character string `a` -- opaque at compile time,
fixed at run time, and the reason the first element comes back `a`
rather than the `x` that `qw` put there. No arithmetic appears in the
block on purpose: `map { $_ + 1 } @a` emits `add`, which is tier 04's. A
bare `$_` is the smallest body that is still a body.

```perl
my @a = qw(x y z);
$a[0] = "$ENV{M}a";
my @block = map { $_ } @a;
my @expr  = map($_, @a);
my $n = map { $_ } @a;
print "@block @expr $n\n";
```

```behavior
parses: yes
```

```output
a y z a y z 3
```

```tokens
one operator whose text is ","
one variable whose text is "@block"
one variable whose text is "@expr"
```

```ir
main::__PROGRAM__: {start: 0, returns: [42], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 4
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3, 4], ~, Array], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Subscript, {kind: array}, [5, 6], ~, Str], # 7
  [EnvRead, {key: M}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [MemStart], # 11
  [Assign, ~, [7, 10], 0, Str, 11, true], # 12
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 12], # 13
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 14
  [ArrayLiteral, ~, ~, ~, Array], # 15
  [Loop, {bound: entry}, [12], 12], # 16
  [Phi, {region: 16}, [15, 55], ~, Array], # 17
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [14, 17], ~, Str, 12], # 18
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 19
  [Concat, ~, [18, 19], ~, Str], # 20
  [ArrayLiteral, ~, ~, ~, Array], # 21
  [Proj, {index: 1}, [16]], # 22
  [Region, {head: 16}, [22]], # 23
  [Loop, {bound: entry}, [23], 23], # 24
  [Phi, {region: 24}, [21, 56], ~, Array], # 25
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [14, 25], ~, Str, 12], # 26
  [Concat, ~, [20, 26], ~, Str], # 27
  [Concat, ~, [27, 19], ~, Str], # 28
  [ArrayLiteral, ~, ~, ~, Array], # 29
  [Proj, {index: 1}, [24]], # 30
  [Region, {head: 24}, [30]], # 31
  [Loop, {bound: entry}, [31], 31], # 32
  [Phi, {region: 32}, [29, 57], ~, Array], # 33
  [Count, ~, [33], ~, Int], # 34
  [Coerce, {from_repr: Int, to_repr: Str}, [34], ~, Str], # 35
  [Concat, ~, [28, 35], ~, Str], # 36
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 37
  [Concat, ~, [36, 37], ~, Str], # 38
  [Proj, {index: 1}, [32]], # 39
  [Region, {head: 32}, [39]], # 40
  [Print, ~, [38], 40, "Maybe[Boolean]"], # 41
  [Return, {implicit: true}, [1], 41, ~, 12], # 42
  [PostfixDeref, {sigil: "@"}, [5], ~, Array, 12], # 43
  [Count, ~, [43], ~, Int, 12], # 44
  [Phi, {region: 16}, [6, 59], ~, Int], # 45
  [Subscript, {kind: array}, [43, 45], ~, Scalar, 12], # 46
  [Phi, {region: 24}, [6, 60], ~, Int], # 47
  [Subscript, {kind: array}, [43, 47], ~, Scalar, 12], # 48
  [Phi, {region: 32}, [6, 61], ~, Int], # 49
  [Subscript, {kind: array}, [43, 49], ~, Scalar, 12], # 50
  [NumGt, ~, [44, 45], 16, Boolean], # 51
  [NumGt, ~, [44, 47], 24, Boolean], # 52
  [NumGt, ~, [44, 49], 32, Boolean], # 53
  [Proj, {index: 0}, [16]], # 54
  [ListAppend, {collector: map}, [17, 46], ~, Array], # 55
  [ListAppend, {collector: map}, [25, 48], ~, Array], # 56
  [ListAppend, {collector: map}, [33, 50], ~, Array], # 57
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 58
  [Add, ~, [45, 58], ~, Int], # 59
  [Add, ~, [47, 58], ~, Int], # 60
  [Add, ~, [49, 58], ~, Int], # 61
  [Proj, {index: 0}, [24]], # 62
  [Proj, {index: 0}, [32]]]} # 63
```

## `grep BLOCK` and `grep EXPR`, where the arities disagree

The same fork as `map`, measured again for the other keyword and
holding: block form and comma form emit

    pushmark, pushmark, padav[@a] lM, grepstart lK, grepwhile lK, gvsv[*_]

The syntactic difference is a COMMA, which the optree does not record,
so the token stream is the only place the fork is observable. The source
holds exactly one comma and the token fact counts it. As with `map`, the
block form advances each lexical's COP SEQUENCE RANGE by 2, which is pad
metadata rather than an op.

WHERE grep IS SHARPER THAN map, and the reason both cases exist rather
than one: `map` in scalar context returns the count of what it would
have returned in list context, so its two halves report the same NUMBER
in different shapes. `grep` FILTERS, so the count is not the input's --
from three elements it keeps two, the scalar half reports 2 and the list
half produces the two surviving strings. Nothing folds; the
discrimination is between a count and the things counted, and they have
different arities from the input as well as from each other.

`$a[0]` is set from `$ENV{G}` for two reasons at once. A constant
argument erases the construct -- a wholly-constant grep folds and leaves
no `grepstart` to measure -- and grep needs an element that is FALSE, or
it filters nothing and the two contexts stop disagreeing about arity.
`$ENV{G}` is unset when the runner executes, so the element is undef,
which is both opaque at compile time and false at run time.

Written as a bare `$a[0] = $ENV{G}` rather than `"$ENV{G}"`, which is
what the `map` case uses. Measured, the interpolating form of a lone
variable emits `stringify`, and `stringify` is claimed by NO tier -- so
quotes that read as harmless would fail the corpus lint for an op the
READMEs do not yet describe. The plain assignment emits
`aelemfastlex_store` and `multideref`, both tier 02's. No comparison
appears in the block on purpose: `grep { $_ gt "a" } @a` emits `gt`,
which is tier 04's. A bare `$_` tests the element's own truth, which is
the smallest predicate there is.

```perl
my @a = qw(x y z);
$a[0] = $ENV{G};
my @block = grep { $_ } @a;
my @expr  = grep($_, @a);
my $n = grep { $_ } @a;
print "@block @expr $n\n";
```

```behavior
parses: yes
```

```output
y z y z 2
```

```tokens
one operator whose text is ","
one variable whose text is "@block"
one variable whose text is "@expr"
```

```ir
main::__PROGRAM__: {start: 0, returns: [40], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: z}, ~, ~, Str], # 4
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3, 4], ~, Array], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Subscript, {kind: array}, [5, 6], ~, Str], # 7
  [EnvRead, {key: G}, ~, ~, Str], # 8
  [MemStart], # 9
  [Assign, ~, [7, 8], 0, Str, 9, true], # 10
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 10], # 11
  [Coerce, {from_repr: Scalar, to_repr: Str}, [11], ~, Str], # 12
  [ArrayLiteral, ~, ~, ~, Array], # 13
  [Loop, {bound: entry}, [10], 10], # 14
  [Phi, {region: 14}, [13, 53], ~, Array], # 15
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 15], ~, Str, 10], # 16
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [ArrayLiteral, ~, ~, ~, Array], # 19
  [Proj, {index: 1}, [14]], # 20
  [Region, {head: 14}, [20]], # 21
  [Loop, {bound: entry}, [21], 21], # 22
  [Phi, {region: 22}, [19, 54], ~, Array], # 23
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [12, 23], ~, Str, 10], # 24
  [Concat, ~, [18, 24], ~, Str], # 25
  [Concat, ~, [25, 17], ~, Str], # 26
  [ArrayLiteral, ~, ~, ~, Array], # 27
  [Proj, {index: 1}, [22]], # 28
  [Region, {head: 22}, [28]], # 29
  [Loop, {bound: entry}, [29], 29], # 30
  [Phi, {region: 30}, [27, 55], ~, Array], # 31
  [Count, ~, [31], ~, Int], # 32
  [Coerce, {from_repr: Int, to_repr: Str}, [32], ~, Str], # 33
  [Concat, ~, [26, 33], ~, Str], # 34
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 35
  [Concat, ~, [34, 35], ~, Str], # 36
  [Proj, {index: 1}, [30]], # 37
  [Region, {head: 30}, [37]], # 38
  [Print, ~, [36], 38, "Maybe[Boolean]"], # 39
  [Return, {implicit: true}, [1], 39, ~, 10], # 40
  [PostfixDeref, {sigil: "@"}, [5], ~, Array, 10], # 41
  [Count, ~, [41], ~, Int, 10], # 42
  [Phi, {region: 14}, [6, 57], ~, Int], # 43
  [Subscript, {kind: array}, [41, 43], ~, Scalar, 10], # 44
  [Phi, {region: 22}, [6, 58], ~, Int], # 45
  [Subscript, {kind: array}, [41, 45], ~, Scalar, 10], # 46
  [Phi, {region: 30}, [6, 59], ~, Int], # 47
  [Subscript, {kind: array}, [41, 47], ~, Scalar, 10], # 48
  [NumGt, ~, [42, 43], 14, Boolean], # 49
  [NumGt, ~, [42, 45], 22, Boolean], # 50
  [NumGt, ~, [42, 47], 30, Boolean], # 51
  [Proj, {index: 0}, [14]], # 52
  [ListAppend, {collector: grep}, [15, 44, 44], ~, Array], # 53
  [ListAppend, {collector: grep}, [23, 46, 46], ~, Array], # 54
  [ListAppend, {collector: grep}, [31, 48, 48], ~, Array], # 55
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 56
  [Add, ~, [43, 56], ~, Int], # 57
  [Add, ~, [45, 56], ~, Int], # 58
  [Add, ~, [47, 56], ~, Int], # 59
  [Proj, {index: 0}, [22]], # 60
  [Proj, {index: 0}, [30]]]} # 61
```
