# Every construct, each beside another

One body holding every construct this tier introduces, each adjacent to
another -- and the one file in the corpus written because the bug it
catches was already known.

**Tier 11 oo.** Introduces nothing of its own; the mixture is the
subject. Depends on 08_references, and `bless` is the whole of the
dependency: the blessed hash below is a tier 08 reference plus a
string. Pairing with tier 10 instead would assert nothing -- this tier
uses no file handle.

MEASURED against our parser, and this is the case the whole
adjacency-file design was written for. Before the fix:

    class Foo { ADJUST { 1 } }                   parses, 0 Unknowns
    class Foo { ADJUST { 1 } method m { 2 } }    1 Unknown, swallowing both

`ADJUST` alone parsed -- that is the ADJUST case in `class.md`, and it
was green throughout. `ADJUST` followed by anything -- `method`,
`field`, or a second `ADJUST` -- did not. A corpus of one construct per
file goes green over this by CONSTRUCTION, because every construct in
such a corpus is measured alone and every construct alone passed.

The cause was that `ADJUST` sat in neither phaser table, so its `{` was
classified as an anonymous hash rather than a block; the statement then
wanted a `;` that valid perl does not write, and the declaration after
it was swallowed. Adding `ADJUST` beside `BEGIN` in both tables closed
it, and this case is green in both orders.

## The whole tier in one body

A `class` with a `field`, an `ADJUST` and a `method` in one body; a
classic `bless` of an empty anon hash; a compile-time method call and a
dynamic one on the result; an infix `isa` and a `can` chain; and a
`tie` with the `tied` that asks about it. The class side and the
classic side are adjacent to each other as well, because a parser that
switches modes on `class` has to switch back.

This case carried a `refuses:`/`refusal:` pair while the ADJUST gap was
open. Measured then, the Unknown started at the `ADJUST` keyword and ran
to the end of the `method` after it: the expression parser read the
ADJUST block as a subscripted bareword, then found the `method` before
the terminator, which is the `trailing_tokens` site. Both lines are gone
now that it parses -- a refusal record kept past its bug hides the
regression it was written to catch.

`$yes` and `$code` are the argument-extent slice's two constructs
(issue 01a0c730), adjacent to the dispatch they are not. `$b isa Bar`
is an INFIX OPERATOR: measured, it emits `<2> isa` with no `entersub`
and no `method_named` at all, so it sits here beside four method calls
that emit both, and a parser that read it as a fifth is caught by the
mixture and by nothing else. `$b->can("hi")->($b)` is TWO calls through
one chain and only the first is a method call; measured, two `entersub`
under one `method_named`, standing next to the plain `$b->hi` and the
dynamic `$b->$name` it must not be confused with.

`tie` and `tied` are here for a reason the other constructs are not:
they need `Bar` to grow a second ROLE. The same package is a plain
blessed class -- `bless {}, "Bar"`, reached by `$b->hi` -- and a tie
implementation, because `TIESCALAR` and `FETCH` live in it. A parser
that treats a package as having one kind sees a body in which the same
name is both, which no one-construct file can present. `tie my $t,
"Bar", "arg"` declares `$t` IN the argument list, standing next to `my
$b = bless {}, "Bar"`, so the two spellings of "make a variable hold a
Bar" are adjacent and only one of them is an assignment. `tied($t)` is
a NAMED UNARY where `tie` is a list operator -- measured, `<1> tied
sK/1` against `<@> tie vK/2`: one child and no mark against a mark and
two.

`FETCH` returns `fetched` and not `tied`, which reads more naturally
and is the trap: the word would otherwise appear in the output where a
reader would take it for the keyword.

`Foo2` is `ref($c)` then `$c->m`, which ADJUST raised from 1 to 2;
`Barbarbar` is `ref($b)` then the same method reached two ways;
`fetched` is `$t` read through the tie, which is `FETCH` reached with
no call written anywhere, and `y` is `tied($t)` answering. Nothing
prints a raw object: `Bar=HASH(0x...)` carries an address that changes
every run, so `ref` is what this asserts on.

```perl
use feature 'class', 'isa';
no warnings 'experimental::class';
class Foo {
    field $x = 1;
    ADJUST { $x = 2 }
    method m { $x }
}
package Bar;
sub hi { return "bar" }
sub TIESCALAR { return bless {}, "Bar" }
sub FETCH { return "fetched" }
package main;
my $c = Foo->new;
my $b = bless {}, "Bar";
my $name = "hi";
my $yes = $b isa Bar;
my $code = $b->can("hi")->($b);
tie my $t, "Bar", "arg";
my $is = tied($t) ? "y" : "n";
print ref($c), $c->m, ref($b), $b->hi, $b->$name, $yes, $code, $t, $is, "\n";
```

```behavior
parses: yes
```

```output
Foo2Barbarbar1barfetchedy
```

```ir
Bar::FETCH: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: fetched}, ~, ~, Str], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
Bar::TIESCALAR: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [HashLiteral, ~, ~, 0, HashRef], # 1
  [Constant, {const_type: string, value: Bar}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [1, 2], 1, Unknown, 3, true], # 4
  [Return, ~, [4], 4, ~, 4]]} # 5
Bar::hi: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: bar}, ~, ~, Str], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
Foo::__ADJUST_0: {start: 0, returns: [5], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 1
  [FieldAccess, {field_index: 0, field_stash: Foo}, ~, ~, Int], # 2
  [MemStart], # 3
  [Assign, ~, [2, 1], 0, Int, 3, true], # 4
  [Return, {implicit: true}, [1], 4, ~, 4]]} # 5
Foo::__DEFAULT_0: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [MemStart], # 2
  [Return, ~, [1], 0, ~, 2]]} # 3
Foo::m: {start: 0, returns: [3], nodes: [
  [Start], # 0
  [MemStart], # 1
  [FieldAccess, {field_index: 0, field_stash: Foo}, ~, ~, Int, 1], # 2
  [Return, {implicit: true}, [2], 0, ~, 1]]} # 3
main::__PROGRAM__: {start: 0, returns: [38], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [PackageMark, {package: Foo}, ~, 0], # 2
  [PackageMark, {package: main}, ~, 2], # 3
  [MemStart], # 4
  [Call, {class_name: Foo, dispatch_kind: method, file: "/tmp/yDlL8UMbFX/case.pl", line: 13, name: new, package: main, param_names: [], want: scalar}, ~, 3, Object, 4, true], # 5
  [PadAccess, {sigil: $, symbol: t}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: Bar}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: arg}, ~, ~, Str], # 8
  [HashLiteral, ~, ~, 5, HashRef], # 9
  [Call, {dispatch_kind: builtin, name: bless, param_names: []}, [9, 7], 9, Unknown, 5, true], # 10
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Unknown, 10], # 11
  [Assign, ~, [11, 10], 10, Unknown, 10, true], # 12
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Scalar, 12], # 13
  [Constant, {const_type: string, value: hi}, ~, ~, Str], # 14
  [Call, {dispatch_kind: method, file: "/tmp/yDlL8UMbFX/case.pl", line: 17, name: can, package: main, param_names: [], want: scalar}, [13, 14], 12, Unknown, 12, true], # 15
  [Call, {dispatch_kind: indirect, file: "/tmp/yDlL8UMbFX/case.pl", line: 17, name: "", package: main, param_names: [], want: scalar}, [15, 13], 15, Unknown, 15, true], # 16
  [Call, {dispatch_kind: builtin, name: tie, param_names: []}, [6, 7, 8], 16, Unknown, 16, true], # 17
  [RefType, ~, [5], ~, Str, 17], # 18
  [Call, {class_name: Foo, dispatch_kind: method, file: "/tmp/yDlL8UMbFX/case.pl", line: 20, name: m, package: main, param_names: [], want: list}, [5], 17, Int, 17, true], # 19
  [Coerce, {from_repr: Unknown, to_repr: Str}, [19], ~, Str], # 20
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Unknown, 19], # 21
  [RefType, ~, [21], ~, Str, 19], # 22
  [Call, {dispatch_kind: method, file: "/tmp/yDlL8UMbFX/case.pl", line: 20, name: hi, package: main, param_names: [], want: list}, [21], 19, Unknown, 19, true], # 23
  [Coerce, {from_repr: Unknown, to_repr: Str}, [23], ~, Str], # 24
  [PadAccess, {sigil: $, symbol: b}, ~, ~, Unknown, 23], # 25
  [Call, {dispatch_kind: dynamic_method, name: "", param_names: [], want: list}, [25, 14], 23, Unknown, 23, true], # 26
  [Coerce, {from_repr: Unknown, to_repr: Str}, [26], ~, Str], # 27
  [IsaOp, ~, [13, 7], ~, Boolean], # 28
  [Coerce, {from_repr: Boolean, to_repr: Str}, [28], ~, Str], # 29
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 30
  [Coerce, {from_repr: Unknown, to_repr: Str}, [6], ~, Str], # 31
  [Call, {dispatch_kind: builtin, name: tied, param_names: []}, [6], ~, Unknown], # 32
  [Constant, {const_type: string, value: "y"}, ~, ~, Str], # 33
  [Constant, {const_type: string, value: "n"}, ~, ~, Str], # 34
  [TernaryExpr, ~, [32, 33, 34], ~, Str], # 35
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 36
  [Print, ~, [18, 20, 22, 24, 27, 29, 30, 31, 35, 36], 26, "Maybe[Boolean]"], # 37
  [Return, {implicit: true}, [1], 37, ~, 26]]} # 38
"BEGIN 1": {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: isa}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [4], 0, Unknown, 5, true], # 6
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/yDlL8UMbFX/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2, 3], 6, Unknown, 6, true], # 7
  [Return, {implicit: true}, [7], 7, ~, 7]]} # 8
"BEGIN 2": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: experimental::class}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: warnings, dispatch_kind: method, file: "/tmp/yDlL8UMbFX/case.pl", line: 2, name: unimport, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```
