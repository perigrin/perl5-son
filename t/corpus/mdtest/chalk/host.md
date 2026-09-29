# Host interface and magic-var graph edges

`$1`..`$9` and `%ENV` per the runtime-free boundary
(`docs/architecture/runtime-free-boundary.md`): a capture var is an OUTPUT of a
regex-match operation — reading `$1` is reading a slot of the match node's
result, a value on a graph edge, not ambient interpreter state. `%ENV` is host
process state read via the plain C `getenv` — the host-interface layer, not
libperl. Both are RF (campaign group G7).

Deferred (zero uses in lib/, tracked follow-up): `@ARGV`/`$0` (argv plumbing),
`$!` (needs failing-syscall ops the slice does not have), I/O config vars, env
WRITES, `$&`/group-0 exposure, and the undef face of a missing `%ENV` key /
failed-match `$N` (composes with the L3 Undef representation later; today a
missing env key reads as the empty string and the corpus only exercises the
set-key path).

## H1 capture read ($1)

Reading `$1` after a match is a `RegexCapture` node taking the match node as
input — the captured bytes are copied into a fresh NUL-terminated buffer at
the offsets the G6 matcher records (every Str value in the backend is
NUL-terminated; no `%MatchResult` struct is materialized).

```perl
# source
use 5.42.0;
my $s = "ab-cd";
$s =~ /(\w+)-(\w+)/;
say($1);
```

```behavior
stdout: ab\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s      = Constant("ab-cd") :Str
%m      = RegexMatch(%s, pattern: "(\w+)-(\w+)") :Boolean
%result = RegexCapture(%m, n: 1) :Str
%nl = Constant("\n") :Str
%p  = Print(%result, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ab-cd}, ~, ~, Str], # 1
  [RegexMatch, {flags: "", pattern: "(\\w+)-(\\w+)"}, [1], ~, Boolean], # 2
  [RegexCapture, {"n": 1}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 0, Scalar], # 5
  [Return, ~, [5], 5]]} # 6
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

## H2 guarded capture (the dominant lib/ idiom)

lib/'s 96 `$N` reads overwhelmingly sit behind a match guard:
`if ($x =~ /.../) { ... $1 ... }`. The guarded form reads the capture only on
the matched path; the ternary face here is Int (`length($1)`).

```perl
# source
use 5.42.0;
my $s = "foo";
say($s =~ /(o+)/ ? length($1) : 0);
```

```behavior
stdout: 2\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s      = Constant("foo") :Str
%m      = RegexMatch(%s, pattern: "(o+)") :Boolean
%cap    = RegexCapture(%m, n: 1) :Str
%len    = Length(%cap) :Int
%zero   = Constant(0) :Int
%result = TernaryExpr(%m, %len, %zero) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: foo}, ~, ~, Str], # 1
  [RegexMatch, {flags: "", pattern: "(o+)"}, [1], ~, Boolean], # 2
  [RegexCapture, {"n": 1}, [2], ~, Str], # 3
  [Length, ~, [3], ~, Int], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [TernaryExpr, ~, [2, 4, 5], ~, Int], # 6
  [Coerce, {from_repr: Int, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 0, Scalar], # 9
  [Return, ~, [9], 9]]} # 10
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

## H3 environment read (%ENV)

`$ENV{KEY}` is an `EnvRead` node lowering to the host C `getenv` (+ a runtime
`strlen` for the value length). The runner sets `CHALK_G7_TEST=hostval` before
running this case; both the perl oracle and lli inherit the environment, so
the declared return is exact under the runner.

```perl
# source
use 5.42.0;
say($ENV{CHALK_G7_TEST});
```

```behavior
stdout: hostval\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%result = EnvRead(key: "CHALK_G7_TEST") :Str
%nl = Constant("\n") :Str
%p  = Print(%result, %nl)
return %p
control: %start -> %p
L: GREEN
```

```son
main::__PROGRAM__: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Return, ~, [1], 0]]} # 2
main::corpus_case: {start: 0, returns: [4], nodes: [
  [Start], # 0
  [EnvRead, {key: CHALK_G7_TEST}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 2
  [Print, ~, [1, 2], 0, Scalar], # 3
  [Return, ~, [3], 3]]} # 4
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
