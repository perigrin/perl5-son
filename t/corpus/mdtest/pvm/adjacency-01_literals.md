# Every literal, each beside another

One body holding every spelling this tier's cases introduce, each
adjacent to another.

**Tier 01 literals.** Introduces nothing of its own; it is the mixture
that is the subject. Depends on nothing, so there is no earlier tier to
pair with -- the adjacency is entirely within 01.

WHY A MIXTURE NEEDS ITS OWN CASE. The tier's other cases are one
construct each, which is what makes them diagnosable: when the leading
point refused, the construct that refused was the only one present. That
same property is why a corpus of such cases cannot reach an ADJACENCY
bug -- a parser that handles every construct alone and mishandles a pair
goes green over the pair.

MEASURED perl 5.42.0, and this is not hypothetical:

    class Foo { ADJUST { 1 } }                   0 Unknowns
    class Foo { ADJUST { 1 } method m { 2 } }    1 Unknown, swallowing both

`ADJUST` alone parses; `ADJUST` followed by anything does not. No
one-construct-per-case corpus can ever see that, because every case is
one construct by definition.

`TestTierLiteralsAdjacency` reads the tier's construct sources for the
literal each binds and requires the spelling to appear here, so this
body cannot fall behind the tier by a construct. It cannot check the
ADJACENCY itself; see the note in that test about `padrange` absorbing
`pushmark`, which is why more adjacent constructs emit FEWER ops.

## The whole tier in one body

Every numeric spelling the tier introduces -- binary, decimal,
hexadecimal, leading point, negative, octal by leading zero, octal by
prefix, signed exponent, trailing point, underscore separators, and both
v-string forms -- plus an integer, a single-quoted string, an
interpolating string and a `q` list.

This body refused from 7711154e until issue
01a0c13f-97f5-7f98-b32d-07245ec6ddfe, and it refused for a BORROWED
reason: the `.5` on line 4 was the leading-point gap reaching here, not
a second bug. The note recorded at the time said an adjacency case
cannot pass while any construct it holds refuses, and that composing
only the working constructs would make it green and make it stop
covering the tier. Fixing the lexer cleared both in one change, which is
that prediction coming true.

The tier's other two refusals -- the exponent split and the v-strings --
are LEXICAL and produce no Unknown at all, so they leave no code here to
name. See `TestTierLiteralsRefusalsCited` for why a case must not name a
refusal it does not have.

`qw(a b c)` prints as `abc` rather than `a b c`: in a print LIST the
three words are separate arguments and `$,` is unset, so nothing
separates them. Binding them to an array instead would print `a b c` --
but it would also emit `aassign`, `padav` and `join`, which are
02_variables' array machinery and unclaimed here. The lint caught that,
and this is the version that keeps `qw` in the tier that owns it.

```perl
my $bin = 0b1010;
my $dec = 0.5;
my $hex = 0xff;
my $lead = .5;
my $neg = -1;
my $oct = 0377;
my $octp = 0o377;
my $exp = 5e-1;
my $trail = 1.;
my $usep = 4_294_967_296;
my $vb = 65.66.67;
my $vv = v65.66.67;
my $int = 42;
my $sq = 'plain';
my $dq = "$int-$dec";
my $esc = "a\nb";
my $qop = q(one);
print "$bin $dec $hex $lead $neg $oct $octp $exp $trail $usep $vb $vv $int $sq $dq ", qw(a b c), " $qop ", $esc, "\n";
```

```behavior
parses: yes
```

```output
10 0.5 255 0.5 -1 255 255 0.5 1 4294967296 ABC ABC 42 plain 42-0.5 abc one a
b
```

```ir
main::__PROGRAM__: {start: 0, returns: [60], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 2
  [Coerce, {from_repr: Int, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 4
  [Concat, ~, [3, 4], ~, Str], # 5
  [Constant, {const_type: number, value: "0.5"}, ~, ~, Num], # 6
  [Coerce, {from_repr: Num, to_repr: Str}, [6], ~, Str], # 7
  [Concat, ~, [5, 7], ~, Str], # 8
  [Concat, ~, [8, 4], ~, Str], # 9
  [Constant, {const_type: integer, value: "255"}, ~, ~, Int], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [Concat, ~, [9, 11], ~, Str], # 12
  [Concat, ~, [12, 4], ~, Str], # 13
  [Concat, ~, [13, 7], ~, Str], # 14
  [Concat, ~, [14, 4], ~, Str], # 15
  [Constant, {const_type: integer, value: "-1"}, ~, ~, Int], # 16
  [Coerce, {from_repr: Int, to_repr: Str}, [16], ~, Str], # 17
  [Concat, ~, [15, 17], ~, Str], # 18
  [Concat, ~, [18, 4], ~, Str], # 19
  [Concat, ~, [19, 11], ~, Str], # 20
  [Concat, ~, [20, 4], ~, Str], # 21
  [Concat, ~, [21, 11], ~, Str], # 22
  [Concat, ~, [22, 4], ~, Str], # 23
  [Concat, ~, [23, 7], ~, Str], # 24
  [Concat, ~, [24, 4], ~, Str], # 25
  [Constant, {const_type: number, value: "1"}, ~, ~, Num], # 26
  [Coerce, {from_repr: Num, to_repr: Str}, [26], ~, Str], # 27
  [Concat, ~, [25, 27], ~, Str], # 28
  [Concat, ~, [28, 4], ~, Str], # 29
  [Constant, {const_type: integer, value: "4294967296"}, ~, ~, Int], # 30
  [Coerce, {from_repr: Int, to_repr: Str}, [30], ~, Str], # 31
  [Concat, ~, [29, 31], ~, Str], # 32
  [Concat, ~, [32, 4], ~, Str], # 33
  [Constant, {const_type: string, value: ABC}, ~, ~, Str], # 34
  [Concat, ~, [33, 34], ~, Str], # 35
  [Concat, ~, [35, 4], ~, Str], # 36
  [Concat, ~, [36, 34], ~, Str], # 37
  [Concat, ~, [37, 4], ~, Str], # 38
  [Constant, {const_type: integer, value: "42"}, ~, ~, Int], # 39
  [Coerce, {from_repr: Int, to_repr: Str}, [39], ~, Str], # 40
  [Concat, ~, [38, 40], ~, Str], # 41
  [Concat, ~, [41, 4], ~, Str], # 42
  [Constant, {const_type: string, value: plain}, ~, ~, Str], # 43
  [Concat, ~, [42, 43], ~, Str], # 44
  [Concat, ~, [44, 4], ~, Str], # 45
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 46
  [Concat, ~, [40, 46], ~, Str], # 47
  [Concat, ~, [47, 7], ~, Str], # 48
  [Concat, ~, [45, 48], ~, Str], # 49
  [Concat, ~, [49, 4], ~, Str], # 50
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 51
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 52
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 53
  [Constant, {const_type: string, value: one}, ~, ~, Str], # 54
  [Concat, ~, [4, 54], ~, Str], # 55
  [Concat, ~, [55, 4], ~, Str], # 56
  [Constant, {const_type: string, value: "a\nb"}, ~, ~, Str], # 57
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 58
  [Print, ~, [50, 51, 52, 53, 56, 57, 58], 0, Scalar], # 59
  [Return, ~, [1], 59], # 60
  [PadAccess, {sigil: $, symbol: dq}, ~, ~, Str], # 61
  [VarDecl, {scope: my}, [61, 48]]]} # 62
```
