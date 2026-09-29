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
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "21"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::double, param_names: [], want: list}, [2], 0, Num], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Return, ~, [1], 6]]} # 7
main::double: {start: 0, returns: [8], nodes: [
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
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "14"}, ~, ~, Int], # 2
  [Call, {dispatch_kind: direct, name: main::__PROGRAM__::__ANON__:1:2, param_names: [], want: list}, [2], 0, Num], # 3
  [Coerce, {from_repr: Unknown, to_repr: Str}, [3], ~, Str], # 4
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 5
  [Print, ~, [4, 5], 3, Scalar], # 6
  [Return, ~, [1], 6]]} # 7
main::__PROGRAM__::__ANON__:1:2: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Return, ~, [7], 0]]} # 8
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
main::__PROGRAM__: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Call, {dispatch_kind: direct, name: main::outer, param_names: [], want: void}, [2, 3], 0, Scalar], # 4
  [Return, ~, [1], 4]]} # 5
main::answer: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [2], ~, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Return, ~, [9], 0]]} # 10
main::outer: {start: 0, returns: [14], nodes: [
  [Start], # 0
  [Call, {dispatch_kind: direct, name: main::answer, param_names: [], want: list}, ~, 0, Str], # 1
  [Coerce, {from_repr: Unknown, to_repr: Str}, [1], ~, Str], # 2
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 3
  [Print, ~, [2, 3], 1, Scalar], # 4
  [Call, {dispatch_kind: direct, name: main::answer, param_names: [], want: list}, ~, 4, Str], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Print, ~, [6, 3], 5, Scalar], # 7
  [Call, {dispatch_kind: direct, name: main::answer, param_names: [], shares_args: true, want: list}, ~, 7, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Print, ~, [9, 3], 8, Scalar], # 10
  [Call, {dispatch_kind: direct, name: main::answer, param_names: [], want: list}, ~, 10, Str], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Print, ~, [12, 3], 11, Scalar], # 13
  [Return, ~, [13], 13]]} # 14
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
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Call, {dispatch_kind: direct, name: main::__PROGRAM__::__ANON__:1:2, param_names: [], want: list}, [2, 3], 0, Str], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 6
  [Print, ~, [5, 6], 4, Scalar], # 7
  [Call, {dispatch_kind: direct, name: main::__PROGRAM__::__ANON__:1:2, param_names: [], want: list}, ~, 7, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Print, ~, [9, 6], 8, Scalar], # 10
  [Return, ~, [1], 10]]} # 11
main::__PROGRAM__::__ANON__:1:2: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "c["}, ~, ~, Str], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [2], ~, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Return, ~, [9], 0]]} # 10
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
  [Call, {dispatch_kind: direct, name: main::slot, param_names: [], want: scalar}, ~, ~, Unknown], # 3
  [Constant, {const_type: integer, value: "42"}, ~, ~, Int], # 4
  [MemStart], # 5
  [PadAccess, {shared: 1, sigil: $, symbol: slot}, [5], ~, Unknown], # 6
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 7
  [Assign, ~, [6, 7], 0, Int], # 8
  [Assign, ~, [3, 4], 8, Int], # 9
  [Call, {dispatch_kind: direct, name: main::slot, param_names: [], want: list}, ~, 9, Unknown], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Print, ~, [11, 12], 10, Scalar], # 13
  [Call, {dispatch_kind: direct, name: main::__PROGRAM__::__ANON__:5:7, param_names: [], want: list}, [2], 13, Num], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Print, ~, [15, 12], 14, Scalar], # 16
  [Return, ~, [1], 16]]} # 17
main::__PROGRAM__::__ANON__:5:7: {start: 0, returns: [8], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 6
  [Multiply, ~, [5, 6], ~, Num], # 7
  [Return, ~, [7], 0]]} # 8
main::slot: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [PadAccess, {shared: 1, sigil: $, symbol: slot}, [1], ~, Unknown], # 2
  [Return, ~, [2], 0]]} # 3
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
  [PadAccess, {shared: 1, sigil: $, symbol: show}, [4], ~, Unknown], # 5
  [AnonSub, {name: main::__PROGRAM__::__ANON__:1:2}, ~, ~, CodeRef], # 6
  [Assign, ~, [5, 6], 0, CodeRef], # 7
  [Call, {dispatch_kind: direct, name: main::outer, param_names: [], want: list}, [2, 3], 7, Str], # 8
  [PadAccess, {shared: 1, sigil: $, symbol: show}, [8], ~, Unknown], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [10, 11], 8, Scalar], # 12
  [Call, {dispatch_kind: indirect, name: "", param_names: [], want: list}, [9], 12, Unknown], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Print, ~, [14, 11], 13, Scalar], # 15
  [Return, ~, [1], 15]]} # 16
main::__PROGRAM__::__ANON__:1:2: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [2], ~, Scalar], # 3
  [Coerce, {from_repr: Scalar, to_repr: Str}, [3], ~, Str], # 4
  [ArgsSource, ~, ~, ~, Array], # 5
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [4, 5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "]"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Return, ~, [9], 0]]} # 10
main::outer: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "amp="}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {shared: 1, sigil: $, symbol: show}, [2], ~, Unknown], # 3
  [Call, {dispatch_kind: indirect, name: "", param_names: [], shares_args: true, want: scalar}, [3], 0, Unknown], # 4
  [Coerce, {from_repr: Unknown, to_repr: Str}, [4], ~, Str], # 5
  [Concat, ~, [1, 5], ~, Str], # 6
  [Constant, {const_type: string, value: " paren="}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [PadAccess, {shared: 1, sigil: $, symbol: show}, [4], ~, Unknown], # 9
  [Call, {dispatch_kind: indirect, name: "", param_names: [], want: scalar}, [9], 4, Unknown], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Concat, ~, [8, 11], ~, Str], # 12
  [Return, ~, [12], 10]]} # 13
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
  [PadAccess, {shared: 1, sigil: "@", symbol: l}, [2], ~, Unknown], # 3
  [EnvRead, {key: A}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 5
  [DefinedOr, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 7
  [ArrayLiteral, {sigil: "@", symbol: l}, [6, 7], ~, Array], # 8
  [Assign, ~, [3, 8], 0, List], # 9
  [Call, {dispatch_kind: direct, name: main::pair, param_names: [], want: list}, ~, 9, List], # 10
  [Call, {dispatch_kind: direct, name: main::group, param_names: [], want: list}, ~, 10, List], # 11
  [Call, {dispatch_kind: direct, name: main::one, param_names: [], want: list}, ~, 11, Scalar], # 12
  [EntryDef, {package: main, sigil: $, symbol: "\""}, [12], ~, Scalar], # 13
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 14
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [14, 10], ~, Str], # 15
  [Constant, {const_type: string, value: "|"}, ~, ~, Str], # 16
  [Concat, ~, [15, 16], ~, Str], # 17
  [Call, {dispatch_kind: builtin, name: join, param_names: []}, [14, 11], ~, Str], # 18
  [Concat, ~, [17, 18], ~, Str], # 19
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 20
  [Concat, ~, [19, 20], ~, Str], # 21
  [ArrayLiteral, {sigil: "@", symbol: p}, [10], ~, Array], # 22
  [Count, ~, [22, 11], ~, Int], # 23
  [Coerce, {from_repr: Int, to_repr: Str}, [23], ~, Str], # 24
  [ArrayLiteral, {sigil: "@", symbol: g}, [11], ~, Array], # 25
  [Count, ~, [25, 11], ~, Int], # 26
  [Coerce, {from_repr: Int, to_repr: Str}, [26], ~, Str], # 27
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 28
  [Print, ~, [24, 27, 28, 20], 12, Scalar], # 29
  [Print, ~, [21], 29, Scalar], # 30
  [Return, ~, [1], 30]]} # 31
main::group: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: l}, ~, ~, Unknown], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Subscript, ~, [1, 5, 3], ~, Scalar], # 6
  [ArrayLiteral, ~, [4, 6], ~, List], # 7
  [Coerce, {from_repr: List, to_repr: Scalar}, [6], ~, Scalar], # 8
  [Return, ~, [7, 8], 0]]} # 9
main::one: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: l}, ~, ~, Unknown], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Return, ~, [4], 0]]} # 5
main::pair: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [PadAccess, {shared: 1, sigil: "@", symbol: l}, ~, ~, Unknown], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 5
  [Subscript, ~, [1, 5, 3], ~, Scalar], # 6
  [ArrayLiteral, ~, [4, 6], ~, List], # 7
  [Coerce, {from_repr: List, to_repr: Scalar}, [6], ~, Scalar], # 8
  [Return, ~, [7, 8], 0]]} # 9
```
