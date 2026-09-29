# Every reference construct, each beside another

One body holding every construct this tier introduces, each adjacent to
another -- and adjacent to tier 07's subroutines, which is what this
tier depends on.

**Tier 08 references.** Introduces nothing of its own; it is the
mixture that is the subject. Depends on 07_subroutines.

WHY A MIXTURE NEEDS ITS OWN CASE. The tier's other cases are one
construct each, which is what makes them diagnosable: when the brace
dereference case refuses, the construct that refused is the only one
present. That same property is why such a corpus cannot reach an
ADJACENCY bug -- a parser that handles every construct alone and
mis-handles a pair goes green over the pair.

## The whole tier in one body

The constructs here are the backslash in both contexts, the anonymous
array, the arrow, all three whole-aggregate dereferences, the brace
element derefs, the code reference, `prototype` and `ref` -- adjacent
within one statement where the construct allows it, and on consecutive
statements where it does not. The two print statements put ten of them
side by side, which is where a parser that handles `$$s[0]` and
`${$l}[1]` separately but not next to each other would show it.

THE THREE SPELLINGS OF ONE OP are all here on consecutive lines:
`@{$s}`, `@$s` and `$s->@*` each emit `rv2av` and nothing in the op
stream separates them, so a parser that reads two of the three and
guesses at the third produces an identical optree for the wrong
program. Three lines apart is where that guess has to hold.

The tier's declared prerequisite is 07_subroutines, so the adjacency
pairs with it: `sub twice` is tier 07's, `\&twice` is this tier's, and
`$c->(21)` is the arrow applied to the result -- the two tiers touching
in one expression rather than in two separate files.

`\(@a)` is the one that needs care. It distributes: `@r` holds a list
of SCALAR references, one per element of `@a`, so `${$r[1]}` is 20 and
`$r[1]->[0]` dies with "Not an ARRAY reference". That failure is what
this body's first draft printed.

`prototype \&one` is here for the reason every other construct is:
adjacency. It sits between the code reference it needs and the
dereferences around it, so a parser that reads `prototype \&one` alone
but loses the following `@{$s}` shows it here and nowhere else. `sub
one ($)` carries the prototype the call never uses -- the sub is
declared to be REFLECTED, not to be called.

The hash is a NAMED one taken a reference to, not `{ k => 1 }`. The
anonymous hash constructor compiles to `emptyavhv`/`anonhash`, which
tier 11 claims, and a tier-08 case emitting a tier-11 op is what the
dependency lint refuses.

```perl
sub twice { return $_[0] * 2 }
sub one ($) { return $_[0] }
my @a = (10, 20);
my %h = (k => 1);
my $s = \@a;
my $hr = \%h;
my @r = \(@a);
my $l = [30, 40];
my $c = \&twice;
my $proto = prototype \&one;
my @at = @{$s};
my @sig = @$s;
my @post = $s->@*;
my %copy = %{$hr};
print ref($s), " ", $$s[0], " ", ${$r[1]}, " ", $l->[0], " ", ${$l}[1], " ", $c->(21), "\n";
print $at[0], " ", $sig[1], " ", $post[0], " ", $copy{k}, " ", $proto, "\n";
```

```behavior
parses: yes
```

```output
ARRAY 10 20 30 40 42
10 20 10 1 $
```

```ir
main::__PROGRAM__: {start: 0, returns: [48], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "20"}, ~, ~, Int], # 3
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3], ~, Array], # 4
  [Ref, ~, [4], ~, ArrayRef], # 5
  [MemStart], # 6
  [PostfixDeref, {sigil: "@"}, [5, 6], ~, Array], # 7
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 8
  [Subscript, ~, [7, 8, 6], ~, Scalar], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 11
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 12
  [Subscript, ~, [7, 12, 6], ~, Scalar], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 15
  [HashLiteral, {sigil: "%", symbol: h}, [15, 12], ~, Hash], # 16
  [Ref, ~, [16], ~, HashRef], # 17
  [PostfixDeref, {sigil: "%"}, [17, 6], ~, Hash], # 18
  [Subscript, ~, [18, 15, 6], ~, Scalar], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 20
  [Constant, {const_type: code, value: one}, ~, ~, Code], # 21
  [Ref, ~, [21], ~, CodeRef], # 22
  [Call, {dispatch_kind: builtin, name: prototype, param_names: []}, [22], ~, Scalar], # 23
  [Coerce, {from_repr: Scalar, to_repr: Str}, [23], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [RefType, ~, [5], ~, Str], # 26
  [Subscript, ~, [5, 8, 6], ~, Scalar], # 27
  [Coerce, {from_repr: Unknown, to_repr: Str}, [27], ~, Str], # 28
  [Ref, {each: true}, [4], ~, List], # 29
  [ArrayLiteral, {sigil: "@", symbol: r}, [29], ~, Array], # 30
  [Subscript, ~, [30, 12, 6], ~, Scalar], # 31
  [PostfixDeref, {sigil: $}, [31], ~, Scalar], # 32
  [Coerce, {from_repr: Scalar, to_repr: Str}, [32], ~, Str], # 33
  [Constant, {const_type: integer, value: "30"}, ~, ~, Int], # 34
  [Constant, {const_type: integer, value: "40"}, ~, ~, Int], # 35
  [ArrayLiteral, ~, [34, 35], ~, ArrayRef], # 36
  [Subscript, ~, [36, 8, 6], ~, Int], # 37
  [Coerce, {from_repr: Unknown, to_repr: Str}, [37], ~, Str], # 38
  [Subscript, ~, [36, 12, 6], ~, Int], # 39
  [Coerce, {from_repr: Unknown, to_repr: Str}, [39], ~, Str], # 40
  [Constant, {const_type: code, value: twice}, ~, ~, Code], # 41
  [Ref, ~, [41], ~, CodeRef], # 42
  [Constant, {const_type: integer, value: "21"}, ~, ~, Int], # 43
  [Call, {dispatch_kind: indirect, name: "", param_names: [], want: list}, [42, 43], 0, Unknown], # 44
  [Coerce, {from_repr: Unknown, to_repr: Str}, [44], ~, Str], # 45
  [Print, ~, [26, 11, 28, 11, 33, 11, 38, 11, 40, 11, 45, 25], 44, Scalar], # 46
  [Print, ~, [10, 11, 14, 11, 10, 11, 20, 11, 24, 25], 46, Scalar], # 47
  [Return, ~, [1], 47]]} # 48
main::one: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Return, ~, [4], 0]]} # 5
main::twice: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Return, ~, [7], 0]]} # 8
```
