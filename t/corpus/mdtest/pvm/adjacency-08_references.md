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
main::__PROGRAM__: {start: 0, returns: [56], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "20"}, ~, ~, Int], # 3
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3], ~, Array], # 4
  [Ref, ~, [4], ~, ArrayRef], # 5
  [MemStart], # 6
  [Ref, {each: true}, [4], 0, List, 6, true], # 7
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/ucZOh245UI/case.pl", line: 11, package: main, sigil: "@", strict: false}, [5], ~, Array, 7], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Constant, {const_type: code, value: main::twice}, ~, ~, Code], # 10
  [Ref, ~, [10], ~, CodeRef], # 11
  [Constant, {const_type: integer, value: "21"}, ~, ~, Int], # 12
  [ArrayLiteral, {sigil: "@", symbol: r}, [7], ~, Array], # 13
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 14
  [Constant, {const_type: string, value: k}, ~, ~, Str], # 15
  [HashLiteral, {sigil: "%", symbol: h}, [15, 14], ~, Hash], # 16
  [Ref, ~, [16], ~, HashRef], # 17
  [Constant, {const_type: integer, value: "30"}, ~, ~, Int], # 18
  [Constant, {const_type: integer, value: "40"}, ~, ~, Int], # 19
  [ArrayLiteral, ~, [18, 19], 7, ArrayRef], # 20
  [PostfixDeref, {eval_id: ~, file: "/tmp/ucZOh245UI/case.pl", line: 11, package: main, sigil: "@", strict: false}, [5], 20, Array, 7, true], # 21
  [PostfixDeref, {eval_id: ~, file: "/tmp/ucZOh245UI/case.pl", line: 12, package: main, sigil: "@", strict: false}, [5], 21, Array, 21, true], # 22
  [PostfixDeref, {eval_id: ~, file: "/tmp/ucZOh245UI/case.pl", line: 13, package: main, sigil: "@", strict: false}, [5], 22, Array, 22, true], # 23
  [PostfixDeref, {eval_id: ~, file: "/tmp/ucZOh245UI/case.pl", line: 14, package: main, sigil: "%", strict: false}, [17], 23, Hash, 23, true], # 24
  [Subscript, {kind: array}, [5, 9], 24, Scalar, 24, true], # 25
  [Subscript, {kind: array}, [13, 14], ~, Scalar, 25], # 26
  [PostfixDeref, {eval_id: ~, file: "/tmp/ucZOh245UI/case.pl", line: 15, package: main, sigil: $, strict: false}, [26], 25, Scalar, 25, true], # 27
  [Call, {dispatch_kind: indirect, file: "/tmp/ucZOh245UI/case.pl", line: 15, name: "", package: main, param_names: [], want: list}, [11, 12], 27, Unknown, 27, true], # 28
  [Subscript, {kind: array}, [8, 9], ~, Scalar, 28], # 29
  [Coerce, {from_repr: Unknown, to_repr: Str}, [29], ~, Str], # 30
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 31
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/ucZOh245UI/case.pl", line: 12, package: main, sigil: "@", strict: false}, [5], ~, Array, 21], # 32
  [Subscript, {kind: array}, [32, 14], ~, Scalar, 28], # 33
  [Coerce, {from_repr: Unknown, to_repr: Str}, [33], ~, Str], # 34
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/ucZOh245UI/case.pl", line: 13, package: main, sigil: "@", strict: false}, [5], ~, Array, 22], # 35
  [Subscript, {kind: array}, [35, 9], ~, Scalar, 28], # 36
  [Coerce, {from_repr: Unknown, to_repr: Str}, [36], ~, Str], # 37
  [PostfixDeref, {copy: 1, eval_id: ~, file: "/tmp/ucZOh245UI/case.pl", line: 14, package: main, sigil: "%", strict: false}, [17], ~, Hash, 23], # 38
  [Subscript, {kind: hash}, [38, 15], ~, Scalar, 28], # 39
  [Coerce, {from_repr: Unknown, to_repr: Str}, [39], ~, Str], # 40
  [Constant, {const_type: code, value: main::one}, ~, ~, Code], # 41
  [Ref, ~, [41], ~, CodeRef], # 42
  [Call, {dispatch_kind: builtin, name: prototype, param_names: []}, [42], ~, Scalar], # 43
  [Coerce, {from_repr: Scalar, to_repr: Str}, [43], ~, Str], # 44
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 45
  [RefType, ~, [5], ~, Str, 24], # 46
  [Coerce, {from_repr: Unknown, to_repr: Str}, [25], ~, Str], # 47
  [Coerce, {from_repr: Scalar, to_repr: Str}, [27], ~, Str], # 48
  [Subscript, {kind: array}, [20, 9], ~, Int, 27], # 49
  [Coerce, {from_repr: Unknown, to_repr: Str}, [49], ~, Str], # 50
  [Subscript, {kind: array}, [20, 14], ~, Int, 27], # 51
  [Coerce, {from_repr: Unknown, to_repr: Str}, [51], ~, Str], # 52
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 53
  [Print, ~, [46, 31, 47, 31, 48, 31, 50, 31, 52, 31, 53, 45], 28, "Maybe[Boolean]"], # 54
  [Print, ~, [30, 31, 34, 31, 37, 31, 40, 31, 44, 45], 54, "Maybe[Boolean]"], # 55
  [Return, {implicit: true}, [1], 55, ~, 28]]} # 56
main::one: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Return, ~, [4], 0, ~, 3]]} # 5
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
