# Every construct, each beside another

One body holding every construct this tier introduces, each adjacent to
another -- and adjacent to 06_control, the tier this one depends on.

**Tier 07 subroutines.** Introduces `anoncode`, `argcheck`,
`argdefelem`, `argelem`, `entersub`, `leavesub`, `lock`, `return`, `warn`.
Depends on 06_control.

The tier's other cases are one construct each, which is what makes them
diagnosable: when the signature case refuses, the construct that refused
is the only one present. That same property is why a corpus of such cases
cannot reach an ADJACENCY bug -- a parser that handles every construct
alone and mis-handles a pair goes green over the pair.

## The whole tier in one body

Present here: a named sub, a signature with a default, `@_` read
positionally, `@_` WRITTEN through, five call forms, an anonymous sub,
`return` both early and trailing, `lock`, and the builtin extent pair.

THE ALIASING WRITE IS THE ONE CONSTRUCT WHOSE EFFECT IS VISIBLE FROM
OUTSIDE THE SUB. `bump($seen)` returns nothing anyone looks at, and
`$seen` is 1 in the printed line only because `$_[0]++` reached the
caller's variable. It sits next to a signatured sub on purpose: `pick`
binds its arguments by signature and `bump` by `@_`, so both of the
tier's argument protocols are in one body, which is the pair a parser
handling each alone can still get wrong. They are two subs rather than
one because, measured 5.42.0, reading `@_` inside a signatured sub warns
-- `Use of @_ in scalar with signatured subroutine is experimental` --
and a warning on stderr is noise this corpus has no section to pin.

THE PAIRING WITH 06_CONTROL IS NOT DECORATION. The `for` loop with `next`
inside the body is the earlier tier's construct sitting directly against
this tier's `return`, which is the pair the DEPENDS ON line names. A
`return` reached from inside a loop has to unwind the loop as well as the
sub, and nothing else in the corpus puts those two exits next to each
other.

THE PROTOTYPE NEEDS A FEATURE TOGGLE, and the reason is the sharpest
single measurement here. `sub g ($)` is a PROTOTYPE only where the
signatures feature is OFF. This body says `use v5.36`, which turns
signatures on, and under it perl reads the same three characters as a
SIGNATURE and enforces arity instead -- measured 5.42.0,
`use v5.36; sub g ($) { "g" } print g 1, 2;` gives
`Too many arguments for subroutine 'main::g' (got 2; expected 1)`, while
without the pragma `sub g ($) { "g[$_[0]]" } print g 1, 2` prints
`g[1]2`. The same three characters, two different features, and only the
feature state decides which. The `no feature "signatures"` /
`use feature "signatures"` pair around `sub g` is what lets both readings
live in one body: `pick` is declared above it and keeps its signature,
`g` is declared inside it and gets a prototype.

A BLOCK WOULD HAVE BEEN TIDIER AND IS MEASURABLY WRONG.
`{ no feature "signatures"; sub g ($) {...} }` compiles the bare braces
as a loop -- `enterloop`, `stub`, `leaveloop` -- and `stub` is an op
11_oo introduces, so the dependency lint correctly refuses a file
reaching four tiers forward to declare a sub. The file-scope toggle emits
no ops at all.

THE LAST TWO PRINTED LINES ARE THE ADJACENCY THAT MATTERS. `print f 1, 2`
and `print g 1, 2` are the same call-site shape and print different
things: `f` is greedy and takes both arguments, while `g`'s prototype
cuts the extent to one and the `2` falls through to the enclosing
`print`. A parser that handled each case alone and got the pair wrong
would go green over two separate cases and fail here, which is the whole
reason an adjacency case exists.

`@greedy` and `@cut` stand the BUILTIN extent question beside the
user-sub one. `warn "a", "b"` is greedy and yields ONE value;
`warn("a"), "b"` is cut by the paren and yields TWO -- the `12` on the
third printed line. A user sub's extent is decided by its DECLARATION and
a builtin's by a PAREN at the call site, and a parser can implement
either and not the other. `local $SIG{__WARN__} = sub { }` is what makes
the pair observable at all: `warn` writes to STDERR, which the pinned
output does not read, and an installed handler is called INSTEAD of that
write, leaving `warn`'s RETURN VALUE as the only thing to count.

WHY THIS USED TO REFUSE, AND WHAT THE REFUSAL TURNED OUT TO BE. This case
carried a `refuses: trailing_tokens` marker blaming the two parenless call
sites -- `print f 1, 2` and `print g 1, 2` -- on the grounds that the
parser read the callee as a complete term and then met a number with no
operator between them. Measured at dc1bea2c that was three Unknown nodes.

That cause is gone and it is NOT what the marker was still measuring at
the end. Measured directly, each of the four suspects parses clean on its
own today:

    sub f { return "f" }  print f 1, 2;                          0 Unknown
    no feature "signatures"; sub g ($) {...} print g 1, 2;        0
    local $SIG{__WARN__} = sub { }; my @greedy = (warn "a", "b"); 0
    local $SIG{__WARN__} = sub { }; my @cut = (warn("a"), "b");   0

The parenless call form landed, and the extent cases with it. What was
left was ONE Unknown, and it came from the pragma pair this file's own
prose is proudest of. `no feature "signatures"` did not turn the feature
off -- the lexer had three paths to `signatures = true` and none to
false -- so `sub g ($)` was read as a SIGNATURE, and the `return` in its
body refused. The bisect is worth keeping because it is counter-intuitive:
the line alone parsed clean, and needed the pragma, a non-empty
prototype AND a `return` together to fail. An empty `()` stayed clean
because there is nothing inside it to misread as a parameter list.

So this file found the bug its own sharpest paragraph describes, by
asserting the behaviour rather than the mechanism -- and it found it while
its marker was pointing at something else entirely. The marker came off
with issue 01a0dd6f.

THIS IS ALSO THE TIER'S SHARPEST STATEMENT OF WHAT THE OP LINT CAN AND
CANNOT SEE. The source below contains a signature, a parameter default, a
loop, a `next`, three `return`s, an aliasing write through `$_[0]` and an
ampersand call, and the MAIN program's op stream contains exactly two ops
this tier introduces -- `anoncode` and `entersub` -- and not one op from
06_control either, because the loop is inside the sub too. Everything
else compiled into a CV that `-MO=Concise,-exec` does not print.
Measured with the sub bodies included, the same source adds seventeen
ops: `aelemfast and argcheck argdefelem argelem enteriter eq iter join
leaveloop leavesub lt multiconcat next postinc return rv2av unstack`.
That difference is the size of the blind spot, in one file.

```perl
use v5.36;
sub pick ($n, $label = "small") {
    return $label if $n < 10;
    for my $i (1 .. 2) {
        next if $i == 1;
        return "big-" . $i;
    }
    return "none";
}
sub bump { $_[0]++ }
sub answer { 42 }
sub f { return "f[" . join("-", @_) . "]" }
no feature "signatures";
sub g ($) { return "g[" . $_[0] . "]" }
use feature "signatures";
my $anon = sub { pick($_[0]) . "/" . &pick($_[1], "tiny") };
my $seen = 0;
bump($seen);
my $n = $seen;
lock($n);
local $SIG{__WARN__} = sub { };
my @greedy = (warn "a", "b");
my @cut = (warn("a"), "b");
print pick(1), " ", pick(50), " ", $anon->(2, 3), " ", $seen, "\n";
print &answer, " ", answer(), " ", answer, "\n";
print scalar @greedy, scalar @cut, "\n";
print f 1, 2;
print "\n";
print g 1, 2;
print "\n";
```

```behavior
parses: yes
```

```output
small big-2 small/tiny 1
42 42 42
12
f[1-2]
g[1]2
```

```ir
main::__PROGRAM__: {start: 0, returns: [57], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 6
  [Call, {dispatch_kind: builtin, name: warn, param_names: []}, [5, 6], ~, Unknown], # 7
  [ArrayLiteral, {sigil: "@", symbol: greedy}, [7], ~, Array], # 8
  [EntryDef, {package: main, sigil: "%", symbol: SIG}, ~, ~, Hash], # 9
  [Constant, {const_type: string, value: __WARN__}, ~, ~, Str], # 10
  [Subscript, ~, [9, 10], ~, Scalar], # 11
  [AnonSub, {name: main::__PROGRAM__::__ANON__:21:8}, ~, ~, CodeRef], # 12
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown], # 13
  [MemStart], # 14
  [PadAccess, {sigil: $, symbol: seen}, [14], ~, Unknown], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Assign, ~, [15, 16], 0, Int], # 17
  [PadAccess, {sigil: $, symbol: seen}, [17], ~, Unknown], # 18
  [Call, {dispatch_kind: direct, name: main::bump, param_names: [], want: void}, [18], 17, Scalar], # 19
  [Call, {dispatch_kind: builtin, name: lock, param_names: []}, [13], 19, Unknown], # 20
  [Assign, ~, [11, 12], 20, CodeRef], # 21
  [Count, ~, [8, 21], ~, Int], # 22
  [Coerce, {from_repr: Int, to_repr: Str}, [22], ~, Str], # 23
  [Call, {dispatch_kind: builtin, name: warn, param_names: []}, [5], ~, Unknown], # 24
  [ArrayLiteral, {sigil: "@", symbol: cut}, [24, 6], ~, Array], # 25
  [Count, ~, [25, 21], ~, Int], # 26
  [Coerce, {from_repr: Int, to_repr: Str}, [26], ~, Str], # 27
  [Call, {dispatch_kind: direct, name: main::pick, param_names: [], want: list}, [3], 21, Unknown], # 28
  [Coerce, {from_repr: Unknown, to_repr: Str}, [28], ~, Str], # 29
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 30
  [Constant, {const_type: integer, value: "50"}, ~, ~, Int], # 31
  [Call, {dispatch_kind: direct, name: main::pick, param_names: [], want: list}, [31], 28, Unknown], # 32
  [Coerce, {from_repr: Unknown, to_repr: Str}, [32], ~, Str], # 33
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 34
  [Call, {dispatch_kind: direct, name: main::__PROGRAM__::__ANON__:16:2, param_names: [], want: list}, [4, 34], 32, Str], # 35
  [Coerce, {from_repr: Unknown, to_repr: Str}, [35], ~, Str], # 36
  [PadAccess, {sigil: $, symbol: seen}, [21], ~, Str], # 37
  [Coerce, {from_repr: Unknown, to_repr: Str}, [37], ~, Str], # 38
  [Print, ~, [29, 30, 33, 30, 36, 30, 38, 2], 35, Scalar], # 39
  [Call, {dispatch_kind: direct, name: main::answer, param_names: [], shares_args: true, want: list}, ~, 39, Int], # 40
  [Coerce, {from_repr: Unknown, to_repr: Str}, [40], ~, Str], # 41
  [Call, {dispatch_kind: direct, name: main::answer, param_names: [], want: list}, ~, 40, Int], # 42
  [Coerce, {from_repr: Unknown, to_repr: Str}, [42], ~, Str], # 43
  [Call, {dispatch_kind: direct, name: main::answer, param_names: [], want: list}, ~, 42, Int], # 44
  [Coerce, {from_repr: Unknown, to_repr: Str}, [44], ~, Str], # 45
  [Print, ~, [41, 30, 43, 30, 45, 2], 44, Scalar], # 46
  [Print, ~, [23, 27, 2], 46, Scalar], # 47
  [Call, {dispatch_kind: direct, name: main::f, param_names: [], want: list}, [3, 4], 47, Str], # 48
  [Coerce, {from_repr: Unknown, to_repr: Str}, [48], ~, Str], # 49
  [Print, ~, [49], 48, Scalar], # 50
  [Print, ~, [2], 50, Scalar], # 51
  [Call, {dispatch_kind: direct, name: main::g, param_names: [], want: list}, [3], 51, Str], # 52
  [Coerce, {from_repr: Unknown, to_repr: Str}, [52], ~, Str], # 53
  [Coerce, {from_repr: Int, to_repr: Str}, [4], ~, Str], # 54
  [Print, ~, [53, 54], 52, Scalar], # 55
  [Print, ~, [2], 55, Scalar], # 56
  [Return, ~, [1], 56]]} # 57
main::__PROGRAM__::__ANON__:16:2: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [Subscript, ~, [1, 2], ~, Scalar], # 3
  [Call, {dispatch_kind: direct, name: main::pick, param_names: [], want: scalar}, [3], 0, Unknown], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "/"}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 8
  [Subscript, ~, [1, 8], ~, Scalar], # 9
  [Constant, {const_type: string, value: tiny}, ~, ~, Str], # 10
  [Call, {dispatch_kind: direct, name: main::pick, param_names: [], want: scalar}, [9, 10], 4, Unknown], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [7, 12], ~, Str], # 13
  [Return, ~, [13], 11]]} # 14
main::__PROGRAM__::__ANON__:21:8: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::answer: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "42"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
main::bump: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Subscript, ~, [1, 2], ~, Scalar], # 5
  [Increment, ~, [4], ~, Scalar], # 6
  [Assign, ~, [5, 6], 0, Scalar], # 7
  [Return, ~, [4], 7]]} # 8
main::f: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "f["}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: "-"}, ~, ~, Str], # 2
  [ArgsSource, ~, ~, ~, Array], # 3
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [2, 3], ~, Str], # 4
  [Concat, ~, [1, 4], ~, Str], # 5
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 6
  [Concat, ~, [5, 6], ~, Str], # 7
  [Return, ~, [7], 0]]} # 8
main::g: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "g["}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, ~, [2, 3, 4], ~, Scalar], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Return, ~, [9], 0]]} # 10
main::pick: {start: 0, returns: [24], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: small}, ~, ~, Str], # 1
  [Parameter, {default_when: absent, index: 1, name: $label, sigil: $}, [1], ~, Unknown], # 2
  [Constant, {const_type: string, value: big-}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Parameter, {index: 0, name: $n, sigil: $}, ~, ~, Num], # 5
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 6
  [NumLt, ~, [5, 6], ~, Boolean], # 7
  [If, ~, [0, 7], 0], # 8
  [Proj, {index: 1}, [8]], # 9
  [Loop, {bound: entry}, [9], 9], # 10
  [Phi, {region: 10}, [4, 28], ~, Int], # 11
  [Coerce, {from_repr: Int, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [3, 12], ~, Str], # 13
  [Constant, {const_type: string, value: none}, ~, ~, Str], # 14
  [Proj, {index: 0}, [8]], # 15
  [Proj, {index: 0}, [10]], # 16
  [NumEq, ~, [11, 4], ~, Boolean], # 17
  [If, ~, [16, 17], 16], # 18
  [Proj, {index: 1}, [18]], # 19
  [Proj, {index: 1}, [10]], # 20
  [Region, {head: 10}, [20]], # 21
  [Region, ~, [15, 19, 21]], # 22
  [Phi, {predecessors: [15, 19, 9], region: 22}, [2, 13, 14], ~, Unknown], # 23
  [Return, ~, [23], 22], # 24
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 25
  [NumGt, ~, [25, 11], 10, Boolean], # 26
  [Proj, {index: 0}, [18]], # 27
  [Add, ~, [11, 4], ~, Int]]} # 28
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: number, value: "5.036"}, ~, ~, Num], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: signatures}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: unimport, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
"BEGIN 3": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: signatures}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```
