# Declaring and calling

A subroutine is declared, and then reached. This topic is the two halves
of that: where the CV comes from -- a named declaration, an anonymous
expression -- and the four spellings that call it.

**Tier 07 subroutines.** Introduces `anoncode`, `argcheck`,
`argdefelem`, `argelem`, `entersub`, `leavesub`, `lock`, `return`, `warn`.
Depends on 06_control.

`entersub` COVERS EVERY CALL FORM, and the differences are flags:
`f(1)`, bare `f`, `&f` and `&f(2)` all emit it, the ampersand forms
carrying `/AMPER` and the code-reference call `/STRICT`. A lint that
reads op NAMES sees one construct where the language has four, which is
why this tier needs one case per form rather than one op claim.

## A named subroutine, declared and called

`sub f {...}` installs a CV under a package name and `f(1)` calls it
through that name.

THE DECLARATION EMITS NOTHING into the main program. It is compile-time:
the CV is built and installed, and the main optree that runs afterwards
contains only the call -- `pushmark`, the `gv` naming the sub, and
`entersub`. Measured 5.42.0, `sub f { $_[0] + 1 } print f(1), "\n"`
gives `gv[IV \&main::f]` rather than `gv[*f]`, because the call resolved
to the CV at compile time: the sub was already declared when the call was
compiled. A call compiled BEFORE the declaration gets `gv[*f]` and looks
the name up at run time. Same op either way.

The body, where this tier's subject actually lives, is a separate optree
that `-MO=Concise,-exec` never prints.

```perl
sub double { $_[0] * 2 }
print double(21), "\n";
```

```behavior
parses: yes
```

```output
42
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "21"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::double, package: main, param_names: [], want: list}, [2], 0, Num, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, "Maybe[Boolean]"], # 7
  [Return, {implicit: true}, [1], 7, ~, 4]]} # 8
main::double: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Return, {implicit: true}, [7], 0, ~, 3]]} # 8
```

## An anonymous subroutine is a value

`sub { ... }` builds a closure in the enclosing scope and yields it;
`$c->(4)` calls it through the variable holding it.

This is the ONE PLACE a subroutine construct emits an op into the main
program, and the reason `anoncode` is in this tier's INTRODUCES list at
all. A named declaration vanishes at compile time; an anonymous one
cannot, because the closure has to be built where it is written --
`anoncode` is that build, and it runs every time control reaches the
expression. Measured 5.42.0, `my $c = sub { $_[0] * 2 }` compiles
`anoncode[CV CODE]` then `padsv_store`, and the call is `entersub[t3]`
with the CV coming off the pad instead of out of a `gv`.

`anoncode[CV CODE]` is opaque on purpose: the body it wraps is a CV that
B::Concise prints only when asked for it by name, and an anonymous sub
has no name to ask with.

```perl
my $triple = sub { $_[0] * 3 };
print $triple->(14), "\n";
```

```behavior
parses: yes
```

```output
42
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "14"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::__PROGRAM__::__ANON__:1:2, package: main, param_names: [], want: list}, [2], 0, Num, 3, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, "Maybe[Boolean]"], # 7
  [Return, {implicit: true}, [1], 7, ~, 4]]} # 8
main::__PROGRAM__::__ANON__:1:2: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Return, {implicit: true}, [7], 0, ~, 3]]} # 8
```

## Four spellings of one call

`f(...)`, bare `f`, `&f` and `&f(...)` all compile to `entersub`, and
only `/AMPER` in the flags column distinguishes the ampersand pair.

THE SEMANTIC DIFFERENCE IS REAL AND THIS FILE ONCE NAMED IT WITHOUT
ASSERTING IT. `&f` with no parens passes the CALLER's `@_` through
untouched rather than an empty list. The earlier source used
`sub answer { 42 }`, which ignores its arguments, so all four spellings
printed 42 and a parser that never implemented the forwarding passed:
the header said the distinction was real and the pin said nothing.

Two changes make it observable and both are necessary -- the callee
REPORTS its arguments, and the calls happen INSIDE a sub whose own `@_`
is non-empty. At file scope there is no caller `@_` to forward and the
four spellings would still agree. Measured 5.42.0 with `outer(1, 2)`:
`answer()` prints `[]`, bare `answer` prints `[]`, `&answer` prints
`[1 2]`, `&answer()` prints `[]`.

THE THIRD LINE IS THE CLAIM: only the parenless ampersand forwards. The
FOURTH is why `&f()` is here rather than treated as a noisier `&f` -- an
EXPLICIT empty list passes nothing, so the ampersand alone does not cause
forwarding, the ABSENCE of an argument list does. A parser reading `&f`
and `&f()` as the same call would print `[1 2]` twice.

Measured, bare `f` compiles as `gv[*f]` where the parenthesised form
gave `gv[IV \&main::f]`: the parser had to decide whether `f` was a call
at all. Still one `entersub`.

```perl
sub answer { "[@_]" }
sub outer {
    print answer(), "\n";
    print answer, "\n";
    print &answer, "\n";
    print &answer(), "\n";
}
outer(1, 2);
```

```behavior
parses: yes
```

```output
[]
[]
[1 2]
[]
```

```ir
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: main::outer, package: main, param_names: [], want: void}, [2, 3], 0, "Maybe[Boolean]", 4, true], # 5
  [Return, {implicit: true}, [1], 5, ~, 5]]} # 6
main::answer: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 2], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 5], ~, Str, 2], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Return, {implicit: true}, [9], 0, ~, 2]]} # 10
main::outer: {start: 0, returns: [15], nodes: [
  [Start], # 0
  [MemStart], # 1
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::answer, package: main, param_names: [], want: list}, ~, 0, Str, 1, true], # 2
  [Coerce, {from_repr: Unknown, to_repr: Str}, [2], ~, Str], # 3
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 4
  [Print, ~, [3, 4], 2, "Maybe[Boolean]"], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::answer, package: main, param_names: [], want: list}, ~, 5, Str, 2, true], # 6
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 7
  [Print, ~, [7, 4], 6, "Maybe[Boolean]"], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::answer, package: main, param_names: [], shares_args: true, want: list}, ~, 8, Str, 6, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Print, ~, [10, 4], 9, "Maybe[Boolean]"], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: main::answer, package: main, param_names: [], want: list}, ~, 11, Str, 9, true], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Print, ~, [13, 4], 12, "Maybe[Boolean]"], # 14
  [Return, {implicit: true}, [14], 14, ~, 12]]} # 15
```

## Calling through a code reference

`$code->(...)`: the callee is a VALUE rather than a name, and the
argument list is parenthesised because there is no other way to spell it.

WHY THIS FORM HAS NO EXTENT QUESTION is the reason it sits beside the two
cases that do. An extent decided by a DECLARATION needs a declaration the
parser has already seen; here there is no name to have seen, so the
callee is whatever `$code` holds at run time, the parens are mandatory,
and the argument list ends where they close. The same construct that
makes the callee unknowable until run time makes its argument extent
knowable at parse time.

Measured 5.42.0, the call is `padsv` then `entersub[t3]` where the named
forms carry `gv` -- a callee read out of a pad slot rather than resolved
by name. Still `entersub`.

The empty call is the second statement rather than a case of its own:
`$code->()` with no arguments is where a parser treating `->(` as an
operator taking an operand would refuse, and it costs one line.

The token facts pin the arrow NEGATIVELY, the only form available, since
`->` appears twice and the vocabulary is `one` or `no`. They assert the
arrow is ONE token and not two -- neither a minus nor a greater-than is
anywhere in this source, so a lexer that split `->` would fail both at
once. The positive half is carried by the case parsing at all.

```perl
my $code = sub { return "c[@_]" };
print $code->(1, 2), "\n";
print $code->(), "\n";
```

```behavior
parses: yes
```

```output
c[1 2]
c[]
```

```tokens
no operator whose text is "-"
no operator whose text is ">"
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: main::__PROGRAM__::__ANON__:1:2, package: main, param_names: [], want: list}, [2, 3], 0, Str, 4, true], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, "Maybe[Boolean]"], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::__PROGRAM__::__ANON__:1:2, package: main, param_names: [], want: list}, ~, 8, Str, 5, true], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Print, ~, [10, 7], 9, "Maybe[Boolean]"], # 11
  [Return, {implicit: true}, [1], 11, ~, 9]]} # 12
main::__PROGRAM__::__ANON__:1:2: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "c["}, ~, ~, Str], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 2], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 5], ~, Str, 2], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Return, ~, [9], 0, ~, 2]]} # 10
```

## An attribute stands between the name and the body

`sub f :lvalue { ... }` and `sub :prototype($) { ... }`: an attribute
list sits after the name (or after `sub` itself, for an anonymous one)
and after any prototype, and the BODY STILL FOLLOWS IT.

THE ATTRIBUTE IS WHY THIS CASE EXISTS AND WHAT IT ASSERTS IS THE BODY.
Before this, one attribute cost the rest of the statement: the parser
finished the sub at the name and left `:lvalue { $slot }` as trailing
tokens, so `sub slot :lvalue { $slot }` became a bodiless declaration
followed by an Unknown. Measured over perl.git's `t/`, 26 of 620 files
use a sub attribute and 25 of those were dirty.

`:lvalue` is the one that makes the body OBSERVABLE rather than merely
present. An lvalue sub's last expression is assignable, so `slot() = 42`
writes through the call into `$slot` -- and a parser that lost the body
has nothing to write through. Measured 5.42.0, the assignment compiles
`entersub sKMS/LVINTRO` then `sassign`, where a plain sub's call is
`entersub lKS` and cannot be assigned to at all.

`:prototype($)` is the second form because its argument is not an
ordinary bracket group. `$)` is a real perl punctuation variable, so a
scanner balancing parens byte by byte reads `($)` as `(` then the
variable `$)` and the closing paren is gone -- taking the sub body with
it. The argument has to be scanned the way `sub f ($$)` is, as one
opaque prototype.

perl's own deparse writes the colon detached, `sub slot : lvalue`, and
nothing here depends on that spelling: the attribute's colon and name
are two tokens either way.

The ops are this tier's and tier 02's -- `entersub` and `anoncode` here,
`sassign` and `padsv_store` there. An attribute introduces no op of its
own, which is the point: it is a property of the CV, decided at compile
time, and the optree that runs afterwards shows only its effect on the
call's flags.

```perl
my $slot = 0;
sub slot :lvalue { $slot }
slot() = 42;
print slot(), "\n";
my $anon = sub :prototype($) { $_[0] * 2 };
print $anon->(21), "\n";
```

```behavior
parses: yes
```

```output
42
42
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "21"}, ~, ~, Int], # 2
  [MemStart], # 3
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: slot}, ~, ~, Unknown, 3], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int, 3, true], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::slot, package: main, param_names: [], want: scalar}, ~, ~, Unknown, 6], # 7
  [Constant, {const_type: integer, value: "42"}, ~, ~, Int], # 8
  [Assign, ~, [7, 8], 6, Int, 6, true], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::slot, package: main, param_names: [], want: list}, ~, 9, Unknown, 9, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [11, 12], 10, "Maybe[Boolean]"], # 13
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: main::__PROGRAM__::__ANON__:5:7, package: main, param_names: [], want: list}, [2], 13, Num, 10, true], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Print, ~, [15, 12], 14, "Maybe[Boolean]"], # 16
  [Return, {implicit: true}, [1], 16, ~, 14]]} # 17
main::__PROGRAM__::__ANON__:5:7: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Return, {implicit: true}, [7], 0, ~, 3]]} # 8
main::slot: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: slot}, ~, ~, Unknown, 1], # 2
  [Return, {implicit: true}, [2], 0, ~, 1]]} # 3
```

## The ampersand call passes the caller's `@_`

`&$code` with NO parens hands the callee the argument list the *caller*
received. `&$code()` hands it an empty one, and `$code->()` hands it an
empty one too. Three spellings of one call, and only the first is
implicit.

WHY THIS CASE SPENDS A SUB TO SAY IT. `conformance/07_subroutines/03_call_forms.t`
documents the same claim for the named `&f` form and its own prose admits
the claim is unobservable there, because the sub it calls ignores `@_` and
all four spellings print the same value. A case that cannot fail on the
fact it asserts is prose. So the callee here interpolates `@_`, and the
three spellings print three different strings: the difference is in the
output column, where a wrong parse has to disagree.

THE PARENS ARE THE WHOLE DIFFERENCE, which is why `&$code` and `&$code()`
sit in one statement. A parser that treats the parens as decoration --
or that drops them -- produces `[x y]` twice and the output says so.

Measured 5.42.0, both spellings are `padsv` then `rv2cv` then `entersub`,
the same three ops as `$code->()`; the implicit `@_` is a property of the
CALL FORM rather than of a different op, so this case claims no op the
tier has not already introduced.

NO TOKEN FACT, DELIBERATELY. The `&` of a call arrives as a FuncSigil
rather than an Operator -- that is what makes `&f` and `&&` stay
distinguishable -- and the token-fact vocabulary has no phrase for that
kind, so there is no true fact to write about it. The claim this case
exists for lives in the output column instead, where it can fail: a
parser that loses the parens prints `[x y]` twice. An untrue token fact
to fill the slot would be worse than none.

PERL REJECTS THE NEIGHBOURING SPELLINGS, and the corpus cannot assert a
syntax error, so they are recorded here rather than tested: `&@a` is
"Bareword found where operator expected", and `&$code[0]` and `&$code{k}`
are syntax errors at the bracket. So `&` takes a scalar and nothing
subscripted -- a parser that accepts those agrees with nothing.

```perl
my $show = sub { return "[@_]" };
sub outer { return "amp=" . &$show . " paren=" . &$show(); }
print outer("x", "y"), "\n";
print $show->(), "\n";
```

```behavior
parses: yes
```

```output
amp=[x y] paren=[]
[]
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: x}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 3
  [MemStart], # 4
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: show}, ~, ~, Unknown, 4], # 5
  [AnonSub, {name: main::__PROGRAM__::__ANON__:1:2}, ~, ~, CodeRef], # 6
  [Assign, ~, [5, 6], 0, CodeRef, 4, true], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::outer, package: main, param_names: [], want: list}, [2, 3], 7, Str, 7, true], # 8
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: show}, ~, ~, Unknown, 8], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [10, 11], 8, "Maybe[Boolean]"], # 12
  [Call, {dispatch_kind: indirect, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: "", package: main, param_names: [], want: list}, [9], 12, Unknown, 8, true], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Print, ~, [14, 11], 13, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 13]]} # 16
main::__PROGRAM__::__ANON__:1:2: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 2], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 5], ~, Str, 2], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Return, ~, [9], 0, ~, 2]]} # 10
main::outer: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "amp="}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: show}, ~, ~, Unknown, 2], # 3
  [Call, {dispatch_kind: indirect, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: "", package: main, param_names: [], shares_args: true, want: scalar}, [3], 0, Unknown, 2, true], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Concat, ~, [1, 5], ~, Str], # 6
  [Constant, {const_type: string, value: " paren="}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: show}, ~, ~, Unknown, 4], # 9
  [Call, {dispatch_kind: indirect, file: "/tmp/mvrHQew3rs/case.pl", line: 2, name: "", package: main, param_names: [], want: scalar}, [9], 4, Unknown, 4, true], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Concat, ~, [8, 11], ~, Str], # 12
  [Return, ~, [12], 10, ~, 10]]} # 13
```

## `return LIST` returns every element

`return` takes an optional list, and the list is the whole return value.
Three spellings in one case because they are three node shapes and one op:
an UNPARENTHESISED list, a PARENTHESISED one, and a single operand.

Measured 5.42.0, all three are `return` over a `pushmark`ed list, and the
parens add nothing to the optree -- `sub g { return ($a, $b) }` and
`sub f { return $a, $b }` deparse alike:

	$ perl -MO=Deparse -e 'sub f { return 1, 2 } sub g { return ($a,$b) }'
	sub f { return 1, 2; }
	sub g { return $a, $b; }

THE OUTPUT COLUMN IS WHERE THIS FAILS, and it is written to fail loudly.
`scalar(@p)` and `scalar(@g)` are the ELEMENT COUNTS, so a parser that
loses an operand prints `1` where the case says `2`, and one that loses
both prints `0`. The single-operand `one()` sits beside them because it is
the spelling that already worked: a fix that repaired the list by breaking
the scalar would show up in the same three characters.

This is what issue 01a0e013 measured. `return 1, 2;` canon'd as `return ,;`
and `return ($a, $b);` as `return ;` -- both operands gone at Unknown = 0,
so nothing but the emission could see it. The cause was neither half of what
the filing guessed: the parse was already right, and canon's LoopControl
case spelled every child as its bare `Text`, which for a comma Binary is
`","` and for a parenthesised List is the empty string.

NO TOKEN FACT, DELIBERATELY, for the reason the ampersand case above gives.
`return` is a Word and the source holds four of them, so `one word whose
text is "return"` is false; the commas are Operators and there are several,
so no `one` fact about them is true either. The vocabulary is `one` or `no`
and this construct needs a COUNT, which the output column carries instead.

```perl
my @l = ($ENV{A} // "a", "b");
sub pair { return $l[0], $l[1]; }
sub group { return ($l[0], $l[1]); }
sub one { return $l[0]; }
my @p = pair();
my @g = group();
print scalar(@p), scalar(@g), one(), "\n";
print "@p|@g\n";
```

```behavior
parses: yes
```

```output
22a
a b|a b
```

```ir
main::__PROGRAM__: {start: 0, returns: [31], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: l}, ~, ~, Array, 2], # 3
  [EnvRead, {key: A}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 5
  [DefinedOr, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 7
  [ArrayLiteral, {sigil: "@", symbol: l}, [6, 7], 0, Array], # 8
  [Assign, ~, [3, 8], 8, List, 2, true], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::pair, package: main, param_names: [], want: list}, ~, 9, List, 9, true], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 6, name: main::group, package: main, param_names: [], want: list}, ~, 10, List, 10, true], # 11
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::one, package: main, param_names: [], want: list}, ~, 11, Scalar, 11, true], # 12
  [EntryDef, {package: main, sigil: $, symbol: "\""}, ~, ~, Scalar, 12], # 13
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 14
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [14, 10], ~, Str], # 15
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [14, 11], ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [ArrayLiteral, {sigil: "@", symbol: p}, [10], ~, Array], # 22
  [Count, ~, [22], ~, Int, 11], # 23
  [Coerce, {from_repr: Int, to_repr: Str}, [23], ~, Str], # 24
  [ArrayLiteral, {sigil: "@", symbol: g}, [11], ~, Array], # 25
  [Count, ~, [25], ~, Int, 11], # 26
  [Coerce, {from_repr: Int, to_repr: Str}, [26], ~, Str], # 27
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 28
  [Print, ~, [24, 27, 28, 20], 12, "Maybe[Boolean]"], # 29
  [Print, ~, [21], 29, "Maybe[Boolean]"], # 30
  [Return, {implicit: true}, [1], 30, ~, 12]]} # 31
main::group: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: l}, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [1, 5], ~, Scalar, 3], # 6
  [ArrayLiteral, ~, [4, 6], ~, List], # 7
  [Coerce, {from_repr: List, to_repr: Scalar}, [6], ~, Scalar], # 8
  [Return, ~, [7, 8], 0, ~, 3]]} # 9
main::one: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: l}, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Return, ~, [4], 0, ~, 3]]} # 5
main::pair: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [PadAccess, {file: 1, shared: 1, sigil: "@", symbol: l}, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Subscript, {kind: array}, [1, 5], ~, Scalar, 3], # 6
  [ArrayLiteral, ~, [4, 6], ~, List], # 7
  [Coerce, {from_repr: List, to_repr: Scalar}, [6], ~, Scalar], # 8
  [Return, ~, [7, 8], 0, ~, 3]]} # 9
```

## A sub whose last statement is a loop

A sub returns the value of its last statement, and when that statement
is a loop, the value is the loop's last failed test: perl's shared false.
It is ONE value in list context and `""` in scalar context, never
anything the body computed, for `foreach` and `while` alike. Measured,
`builtin::is_bool` is true for both. Found by B::SoN translating chalk's
lib/ and running chalk's own suite against the emitted Perl, which
compiled and gave a wrong answer; it was the cause of 99 of chalk's
failing test files.

```perl
sub last_is_for   { my @seen; for my $x (@_) { push @seen, $x * 2 } }
sub last_is_while { my $i = 0; while ($i < 2) { $i++ } }
my @f = last_is_for(1, 2);
my @w = last_is_while();
my $s = last_is_for(3);
print scalar(@f), scalar(@w), "[", $f[0], "][", $s, "]\n";
```

```behavior
parses: yes
```

```output
11[][]
```

```ir
main::__PROGRAM__: {start: 0, returns: [23], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 3, name: main::last_is_for, package: main, param_names: [], want: list}, [2, 3], 0, Boolean, 4, true], # 5
  [ArrayLiteral, {sigil: "@", symbol: f}, [5], ~, Array], # 6
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 4, name: main::last_is_while, package: main, param_names: [], want: list}, ~, 5, Boolean, 5, true], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::last_is_for, package: main, param_names: [], want: scalar}, [7], 8, Boolean, 8, true], # 9
  [Count, ~, [6], ~, Int, 9], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [ArrayLiteral, {sigil: "@", symbol: w}, [8], ~, Array], # 12
  [Count, ~, [12], ~, Int, 9], # 13
  [Coerce, {from_repr: Int, to_repr: Str}, [13], ~, Str], # 14
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 15
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 16
  [Subscript, {kind: array}, [6, 16], ~, Scalar, 9], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: "]["}, ~, ~, Str], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 20
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 21
  [Print, ~, [11, 14, 15, 18, 19, 20, 21], 9, "Maybe[Boolean]"], # 22
  [Return, {implicit: true}, [1], 22, ~, 9]]} # 23
main::last_is_for: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: boolean, value: ""}, ~, ~, Boolean], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Proj, {index: 1}, [2]], # 3
  [Region, {head: 2}, [3]], # 4
  [MemStart], # 5
  [Phi, {memory: true, region: 2}, [5, 27], ~, Unknown], # 6
  [Phi, {memory: true, region: 4}, [6], ~, Unknown], # 7
  [Return, {implicit: true}, [1], 4, ~, 7], # 8
  [ArgsSource, ~, ~, ~, Array], # 9
  [Count, ~, [9], ~, Int, 6], # 10
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 11
  [Phi, {region: 2}, [11, 29], ~, Int], # 12
  [NumGt, ~, [10, 12], 2, Boolean], # 13
  [Proj, {index: 0}, [2]], # 14
  [Exists, {kind: array}, [9, 12], 14, Boolean, 6], # 15
  [PadAccess, {sigil: "@", symbol: seen}, ~, ~, Array], # 16
  [Subscript, {kind: array}, [9, 12], ~, Scalar], # 17
  [Ref, ~, [17], ~, ScalarRef], # 18
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 19
  [TernaryExpr, ~, [15, 18, 19], 15, "Maybe[ScalarRef]"], # 20
  [PostfixDeref, {sigil: $}, [20], ~, Scalar, 6], # 21
  [Subscript, {kind: array}, [9, 12], ~, Scalar, 6], # 22
  [TernaryExpr, ~, [15, 21, 22], 20, Scalar], # 23
  [Coerce, {from_repr: Scalar, to_repr: Num}, [23], ~, Num], # 24
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 25
  [Multiply, ~, [24, 25], ~, Num], # 26
  [Call, {dispatch_kind: builtin, name: push, param_names: []}, [16, 26], 23, Int, 6, true], # 27
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 28
  [Add, ~, [12, 28], ~, Int], # 29
  [Count, ~, [9], ~, Int, 5]]} # 30
main::last_is_while: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: boolean, value: ""}, ~, ~, Boolean], # 1
  [Loop, {bound: each}, [0], 0], # 2
  [Proj, {index: 1}, [2]], # 3
  [Region, {head: 2}, [3]], # 4
  [MemStart], # 5
  [Return, {implicit: true}, [1], 4, ~, 5], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Phi, {region: 2}, [7, 13], ~, Int], # 8
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 9
  [NumLt, ~, [8, 9], 2, Boolean], # 10
  [Proj, {index: 0}, [2]], # 11
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 12
  [Add, ~, [8, 12], ~, Int]]} # 13
```

## A die guarded inside a loop body

The guard runs on each element; the `die` leaves the loop and the sub on the element that fails it. A reader that steps past the `die` returns "ok" for both calls. Found by B::SoN translating chalk's lib/ and running chalk's own suite against the emitted Perl.

```perl
sub check {
    for my $x (@_) {
        die "too big: $x\n" if $x > 1;
    }
    return "ok";
}
print eval { check(1, 0) } // $@, "\n";
print eval { check(1, 9) } // $@;
```

```behavior
parses: yes
```

```output
ok
too big: 9
```

```ir
main::__PROGRAM__: {start: 0, returns: [37], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [MemStart], # 5
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 5], # 6
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 7
  [EntryWrite, ~, [6, 7], 0, Unknown, 5, true], # 8
  [Call, {dispatch_kind: direct, eval_id: 1, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::check, package: main, param_names: [], want: scalar}, [2, 4], 8, Str, 8, true], # 9
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 9], # 10
  [EntryWrite, ~, [10, 7], 9, Unknown, 9, true], # 11
  [Exc, ~, [9]], # 12
  [Region, {catch: true, eval_id: 1}, [12]], # 13
  [EntryWrite, ~, [10, 12], 13, Unknown, 9, true], # 14
  [Region, {eval_entry: 0, eval_id: 1}, [11, 14]], # 15
  [Phi, {memory: true, region: 15}, [11, 14], ~, Unknown], # 16
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 16], # 17
  [Phi, {region: 15}, [9, 1], ~, "Maybe[Str]"], # 18
  [DefinedOr, ~, [18, 17], ~, Scalar], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 20
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 21
  [Print, ~, [20, 21], 15, "Maybe[Boolean]"], # 22
  [EntryWrite, ~, [17, 7], 22, Unknown, 16, true], # 23
  [Call, {dispatch_kind: direct, eval_id: 2, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: main::check, package: main, param_names: [], want: scalar}, [2, 3], 23, Str, 23, true], # 24
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 24], # 25
  [EntryWrite, ~, [25, 7], 24, Unknown, 24, true], # 26
  [Exc, ~, [24]], # 27
  [Region, {catch: true, eval_id: 2}, [27]], # 28
  [EntryWrite, ~, [25, 27], 28, Unknown, 24, true], # 29
  [Region, {eval_entry: 22, eval_id: 2}, [26, 29]], # 30
  [Phi, {region: 30}, [24, 1], ~, "Maybe[Str]"], # 31
  [Phi, {memory: true, region: 30}, [26, 29], ~, Unknown], # 32
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 32], # 33
  [DefinedOr, ~, [31, 33], ~, Scalar], # 34
  [Coerce, {from_repr: Unknown, to_repr: Str}, [34], ~, Str], # 35
  [Print, ~, [35], 30, "Maybe[Boolean]"], # 36
  [Return, {implicit: true}, [1], 36, ~, 32]]} # 37
main::check: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: ok}, ~, ~, Str], # 1
  [Loop, {bound: entry}, [0], 0], # 2
  [Proj, {index: 1}, [2]], # 3
  [Region, {head: 2}, [3]], # 4
  [MemStart], # 5
  [Return, ~, [1], 4, ~, 5], # 6
  [ArgsSource, ~, ~, ~, Array], # 7
  [Count, ~, [7], ~, Int, 5], # 8
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 9
  [Phi, {region: 2}, [9, 19], ~, Int], # 10
  [NumGt, ~, [8, 10], 2, Boolean], # 11
  [Proj, {index: 0}, [2]], # 12
  [Subscript, {kind: array}, [7, 10], ~, Scalar, 5], # 13
  [Coerce, {from_repr: Scalar, to_repr: Num}, [13], ~, Num], # 14
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 15
  [NumGt, ~, [14, 15], ~, Boolean], # 16
  [If, ~, [12, 16], 12], # 17
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 18
  [Add, ~, [10, 15], ~, Int], # 19
  [Proj, {index: 0}, [17]], # 20
  [Proj, {index: 1}, [17]], # 21
  [Constant, {const_type: string, value: "too big: "}, ~, ~, Str], # 22
  [Concat, ~, [22, 18], ~, Str], # 23
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 24
  [Concat, ~, [23, 24], ~, Str], # 25
  [Unwind, {file: "/tmp/mvrHQew3rs/case.pl", line: 3}, [25], 20, ~, 5], # 26
  [Region, {head: 17}, [26, 21]]]} # 27
```

## A defined-or whose right side calls, in a loop body

The call runs only for the undefined elements: twice, not three times and not never. Found by B::SoN translating chalk's lib/ and running chalk's own suite against the emitted Perl.

```perl
my $calls = 0;
sub fallback { $calls++; return 7 }
my $out = "";
for my $x (undef, 2, undef) {
    my $v = $x // fallback();
    $out .= $v;
}
print "$out $calls\n";
```

```behavior
parses: yes
```

```output
727 2
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: calls}, ~, ~, Unknown, 3], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int, 3, true], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [2, 41], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Phi, {memory: true, region: 7}, [6, 36], ~, Unknown], # 11
  [Proj, {index: 1}, [7]], # 12
  [Region, {head: 7}, [12]], # 13
  [Phi, {memory: true, region: 13}, [11], ~, Unknown], # 14
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: calls}, ~, ~, Str, 14], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [10, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Print, ~, [19], 13, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 14], # 21
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 22
  [ArrayLiteral, ~, [1, 22, 1], ~, Array], # 23
  [Count, ~, [23], ~, Int, 6], # 24
  [Phi, {region: 7}, [5, 38], ~, Int], # 25
  [Count, ~, [23], ~, Int, 11], # 26
  [NumGt, ~, [26, 25], 7, Boolean], # 27
  [Proj, {index: 0}, [7]], # 28
  [Subscript, {kind: array}, [23, 25], ~, "Maybe[Int]", 11], # 29
  [Defined, ~, [29], ~, Boolean], # 30
  [If, ~, [28, 30], 28], # 31
  [Proj, {index: 1}, [31]], # 32
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::fallback, package: main, param_names: [], want: scalar}, ~, 32, Int, 11, true], # 33
  [Proj, {index: 0}, [31]], # 34
  [Region, {head: 31}, [34, 33]], # 35
  [Phi, {memory: true, predecessors: [34, 32], region: 35}, [11, 33], ~, Unknown], # 36
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 37
  [Add, ~, [25, 37], ~, Int], # 38
  [Phi, {predecessors: [34, 32], region: 35}, [29, 33], ~, "Maybe[Int]"], # 39
  [Coerce, {from_repr: Unknown, to_repr: Str}, [39], ~, Str], # 40
  [Concat, ~, [8, 40], ~, Str]]} # 41
main::fallback: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 1
  [MemStart], # 2
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: calls}, ~, ~, Unknown, 2], # 3
  [Increment, ~, [3], ~, Scalar], # 4
  [Assign, ~, [3, 4], 0, Scalar, 2, true], # 5
  [Return, ~, [1], 5, ~, 5]]} # 6
```

## A chain of ands with calls, guarding next

Each `id()` runs only when the operands to its left were true, so the calls are counted: 1 for the first element, 3 each for the others. Found by B::SoN translating chalk's lib/ and running chalk's own suite against the emitted Perl.

```perl
my $calls = 0;
sub id { $calls++; return $_[0] }
my $out = "";
for my $x (1, 2, 3, 9) {
    next unless id($x) && id($x) > 1 && id($x) < 9;
    $out .= $x;
}
print "$out $calls\n";
```

```behavior
parses: yes
```

```output
23 11
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: calls}, ~, ~, Unknown, 3], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [Assign, ~, [4, 5], 0, Int, 3, true], # 6
  [Loop, {bound: entry}, [6], 6], # 7
  [Phi, {region: 7}, [2, 65], ~, Str], # 8
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Phi, {memory: true, region: 7}, [6, 53], ~, Scalar], # 11
  [Proj, {index: 1}, [7]], # 12
  [Region, {head: 7}, [12]], # 13
  [Phi, {memory: true, region: 13}, [11], ~, Scalar], # 14
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: calls}, ~, ~, Str, 14], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [10, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Print, ~, [19], 13, "Maybe[Boolean]"], # 20
  [Return, {implicit: true}, [1], 20, ~, 14], # 21
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 22
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 23
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 24
  [Constant, {const_type: integer, value: "9"}, ~, ~, Int], # 25
  [ArrayLiteral, ~, [22, 23, 24, 25], ~, Array], # 26
  [Count, ~, [26], ~, Int, 6], # 27
  [Phi, {region: 7}, [5, 54], ~, Int], # 28
  [Count, ~, [26], ~, Int, 11], # 29
  [NumGt, ~, [29, 28], 7, Boolean], # 30
  [Proj, {index: 0}, [7]], # 31
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 11], # 32
  [Subscript, {kind: array}, [26, 28], ~, Int, 11], # 33
  [Assign, ~, [32, 33], 31, Int, 11, true], # 34
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 34], # 35
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::id, package: main, param_names: [], want: scalar}, [35], 34, Scalar, 34, true], # 36
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 36], # 37
  [If, ~, [36, 36], 36], # 38
  [Proj, {index: 0}, [38]], # 39
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::id, package: main, param_names: [], want: scalar}, [37], 39, Scalar, 36, true], # 40
  [Proj, {index: 1}, [38]], # 41
  [Region, {head: 38}, [40, 41]], # 42
  [Phi, {memory: true, predecessors: [39, 41], region: 42}, [40, 36], ~, Scalar], # 43
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 43], # 44
  [Coerce, {from_repr: Scalar, to_repr: Num}, [40], ~, Num], # 45
  [NumGt, ~, [45, 22], ~, Boolean], # 46
  [Phi, {predecessors: [39, 41], region: 42}, [46, 36], ~, Scalar], # 47
  [If, ~, [42, 47], 42], # 48
  [Proj, {index: 0}, [48]], # 49
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::id, package: main, param_names: [], want: scalar}, [44], 49, Scalar, 43, true], # 50
  [Proj, {index: 1}, [48]], # 51
  [Region, {head: 48}, [50, 51]], # 52
  [Phi, {memory: true, predecessors: [49, 51], region: 52}, [50, 43], ~, Scalar], # 53
  [Add, ~, [28, 22], ~, Int], # 54
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Str, 53], # 55
  [Coerce, {from_repr: Scalar, to_repr: Num}, [50], ~, Num], # 56
  [NumLt, ~, [56, 25], ~, Boolean], # 57
  [Coerce, {from_repr: Unknown, to_repr: Str}, [55], ~, Str], # 58
  [Phi, {predecessors: [49, 51], region: 52}, [57, 47], ~, Scalar], # 59
  [If, ~, [52, 59], 52], # 60
  [Concat, ~, [8, 58], ~, Str], # 61
  [Proj, {index: 1}, [60]], # 62
  [Proj, {index: 0}, [60]], # 63
  [Region, {head: 60}, [62, 63]], # 64
  [Phi, {predecessors: [62, 63], region: 64}, [8, 61], ~, Str]]} # 65
main::id: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: calls}, ~, ~, Unknown, 3], # 4
  [Increment, ~, [4], ~, Scalar], # 5
  [Assign, ~, [4, 5], 0, Scalar, 3, true], # 6
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 6], # 7
  [Return, ~, [7], 6, ~, 6]]} # 8
```

## A call under a statement modifier inside an if

The call runs only when both guards hold -- once in three calls of `f`. Found by B::SoN translating chalk's lib/ and running chalk's own suite against the emitted Perl.

```perl
my $calls = 0;
sub helper { $calls++ }
sub f {
    my ($x, $y) = @_;
    if ($x > 3) {
        helper() if $y > 3;
    }
}
f(5, 5); f(5, 1); f(1, 5);
print "$calls\n";
```

```behavior
parses: yes
```

```output
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 3
  [MemStart], # 4
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: calls}, ~, ~, Unknown, 4], # 5
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 6
  [Assign, ~, [5, 6], 0, Int, 4, true], # 7
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::f, package: main, param_names: [], want: void}, [3, 3], 7, Scalar, 7, true], # 8
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::f, package: main, param_names: [], want: void}, [3, 2], 8, Scalar, 8, true], # 9
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::f, package: main, param_names: [], want: void}, [2, 3], 9, Scalar, 9, true], # 10
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: calls}, ~, ~, Str, 10], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 13
  [Concat, ~, [12, 13], ~, Str], # 14
  [Print, ~, [14], 10, "Maybe[Boolean]"], # 15
  [Return, {implicit: true}, [1], 15, ~, 10]]} # 16
main::f: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Num], # 1
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 2
  [NumGt, ~, [1, 2], ~, Boolean], # 3
  [If, ~, [0, 3], 0], # 4
  [Proj, {index: 0}, [4]], # 5
  [PadAccess, {sigil: $, symbol: "y"}, ~, ~, Num], # 6
  [NumGt, ~, [6, 2], ~, Boolean], # 7
  [If, ~, [5, 7], 5], # 8
  [Proj, {index: 0}, [8]], # 9
  [MemStart], # 10
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 5, name: main::helper, package: main, param_names: []}, ~, 9, Scalar, 10, true], # 11
  [Proj, {index: 1}, [8]], # 12
  [Region, {head: 8}, [11, 12]], # 13
  [Phi, {predecessors: [9, 12], region: 13}, [11, 7], ~, Scalar], # 14
  [And, ~, [3, 14], ~, Scalar], # 15
  [Proj, {index: 1}, [4]], # 16
  [Region, {head: 4}, [16, 13]], # 17
  [Phi, {memory: true, predecessors: [9, 12], region: 13}, [11, 10], ~, Unknown], # 18
  [Phi, {memory: true, predecessors: [16, 5], region: 17}, [10, 18], ~, Unknown], # 19
  [Return, {implicit: true}, [15], 17, ~, 19], # 20
  [ArgsSource, ~, ~, ~, Array], # 21
  [Assign, {record: true, targets: 2}, [1, 6, 21], ~, List]]} # 22
main::helper: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {file: 1, shared: 1, sigil: $, symbol: calls}, ~, ~, Unknown, 1], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Scalar], # 4
  [Increment, ~, [2], ~, Scalar], # 5
  [Assign, ~, [2, 5], 0, Scalar, 1, true], # 6
  [Return, {implicit: true}, [4], 6, ~, 6]]} # 7
```

## A print under a modifier, ending a sub

The `if` is the sub's last statement, so it takes the caller's context: the inner modifier is neither void nor a plain value, and its print still runs only when both guards hold. Found by B::SoN translating chalk's lib/ and running chalk's own suite against the emitted Perl.

```perl
sub report {
    my ($x, $y) = @_;
    if ($x > 3) {
        print "both $x $y\n" if $y > 3;
    }
}
report(5, 5);
report(5, 1);
report(1, 5);
```

```behavior
parses: yes
```

```output
both 5 5
```

```ir
main::__PROGRAM__: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "5"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 7, name: main::report, package: main, param_names: [], want: void}, [3, 3], 0, "Maybe[Boolean]", 4, true], # 5
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 8, name: main::report, package: main, param_names: [], want: void}, [3, 2], 5, "Maybe[Boolean]", 5, true], # 6
  [Call, {dispatch_kind: direct, file: "/tmp/mvrHQew3rs/case.pl", line: 9, name: main::report, package: main, param_names: [], want: void}, [2, 3], 6, "Maybe[Boolean]", 6, true], # 7
  [Return, {implicit: true}, [1], 7, ~, 7]]} # 8
main::report: {start: 0, returns: [27], nodes: [
  [Start], # 0
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Num], # 1
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 2
  [NumGt, ~, [1, 2], ~, Boolean], # 3
  [Constant, {const_type: string, value: "both "}, ~, ~, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 5
  [Concat, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [PadAccess, {sigil: $, symbol: "y"}, ~, ~, Num], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Concat, ~, [8, 10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [If, ~, [0, 3], 0], # 14
  [Proj, {index: 0}, [14]], # 15
  [NumGt, ~, [9, 2], ~, Boolean], # 16
  [If, ~, [15, 16], 15], # 17
  [Proj, {index: 0}, [17]], # 18
  [Print, ~, [13], 18, "Maybe[Boolean]"], # 19
  [Proj, {index: 1}, [17]], # 20
  [Region, {head: 17}, [19, 20]], # 21
  [Phi, {predecessors: [18, 20], region: 21}, [19, 16], ~, "Maybe[Boolean]"], # 22
  [And, ~, [3, 22], ~, "Maybe[Boolean]"], # 23
  [Proj, {index: 1}, [14]], # 24
  [Region, {head: 14}, [24, 21]], # 25
  [MemStart], # 26
  [Return, {implicit: true}, [23], 25, ~, 26], # 27
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 28
  [Phi, {predecessors: [24, 15], region: 25}, [28, 13], ~, "Maybe[Str]"], # 29
  [ArgsSource, ~, ~, ~, Array], # 30
  [Assign, {record: true, targets: 2}, [1, 9, 30], ~, List]]} # 31
```
