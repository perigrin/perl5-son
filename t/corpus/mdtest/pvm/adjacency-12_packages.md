# Every construct, each beside another

One body holding every construct this tier covers, each adjacent to
another, and paired with the declared prerequisite.

**Tier 12 packages.** Introduces `require`. Depends on 07_subroutines.

WHY A MIXTURE NEEDS ITS OWN CASE. The tier's other cases are one
construct each, which is what makes them diagnosable: when the bareword
`require` case fails, `require` is the only construct present. That same
property is why a corpus of such cases cannot reach an ADJACENCY bug --
a parser that handles every construct alone and mis-handles a pair goes
green over the pair. Tier 11 has the case the design was written for:
`class Foo { ADJUST { 1 } }` parses and `class Foo { ADJUST { 1 } method
m { 2 } }` does not.

## The whole tier in one body

The pairs this case puts next to each other:

    an importing `use` immediately followed by an empty-list `use`
    a `package NAME;` immediately followed by a `package NAME { }`
    a bareword `require` immediately followed by an expression `require`
    a `package main;` immediately followed by a statement
    an `import` sub DEFINED in one package and CALLED from another

The last is the pairing with `07_subroutines`, this tier's declared
prerequisite. `import` is the reason `use` is heavier than `require`,
and it is a plain sub call; a case that declared the dependency without
crossing the package boundary would assert nothing about it. Pairing
with tier 11 instead would assert nothing at all -- this tier needs
nothing from it.

`Greet::hello` and `Louder::shout` are called by their fully qualified
names, the third spelling of the package boundary here and the only one
that appears in the op stream: `gv[*Greet::hello]`. The two `package`
statements that put them there leave no trace.

EVERY PINNED LINE IS FALSIFIABLE BY DELETING A STATEMENT, which is what
a tier of no-op constructs has instead of an op check. Measured, each
deletion changes the output:

    drop `package Greet;`    `Greet::hello` is undefined and the program dies
    drop `package Louder {`  likewise for `Louder::shout`
    drop `use POSIX;`        `use:` reads `no` where it read `yes`
    drop either `require`    `inc:` loses a `yes`
    drop `Greet->import`     the first line of output goes

`use Fcntl ();` is the one whose deletion does NOT change the output,
because its whole claim is that it imports nothing: it is pinned by
CONTRAST with the `use POSIX;` above it. `LOCK_EX` is chosen over
`O_RDONLY` for exactly that reason -- POSIX exports `O_RDONLY` too, so
pinning it would have read `yes` whether or not `Fcntl` was ever loaded,
and the pair would have measured one statement twice. Measured on
5.42.0: POSIX exports `O_RDONLY` and does not export `LOCK_EX`.

THE COMPILE-PHASE SLICE WRAPS THE WHOLE BODY, which is the adjacency
claim it makes. `BEGIN` is written AFTER `END` in the source and runs
first; `END` runs after the last statement. Neither emits an op, so the
ordering is the only evidence either exists, and a parser that treated
them as ordinary blocks would print them where they appear.

`pkg main line 300 file adj` is four compile-time constructs in one
statement. The `#line` directive above it is a `#` at column zero that
is NOT a comment: it rewrites `__LINE__` and `__FILE__` for everything
below, which is why the line reports 300 and `adj` rather than its real
position. `__FILE__` is only pinnable at all because of that -- without
the directive it reports the runner's temp path. `TAG` is the bareword
`use constant` installed, and it prints `c` rather than `TAG`, which is
what separates an installed sub from a bareword string.

```perl
use POSIX;
use Fcntl ();
use constant TAG => "c";
END { print "end\n" }
BEGIN { print "begin\n" }
package Greet;
sub hello { return "hello" }
sub import { print "import $_[1]\n" }
package Louder {
    sub shout { return "HELLO" }
}
package main;
require strict;
my $mod = "warnings.pm";
require $mod;
Greet->import("tag");
print Greet::hello(), " ", Louder::shout(), "\n";
print "inc: ", ($INC{"strict.pm"} ? "yes" : "no"), ($INC{"warnings.pm"} ? "yes" : "no"), "\n";
print "use: ", ($main::{"floor"} ? "yes" : "no"), ($main::{"LOCK_EX"} ? "yes" : "no"), "\n";
#line 300 "adj"
print "pkg ", __PACKAGE__, " line ", __LINE__, " file ", __FILE__, " tag ", TAG, "\n";
```

```behavior
parses: yes
```

```output
begin
import tag
hello HELLO
inc: yesyes
use: yesno
pkg main line 300 file adj tag c
end
```

```ir
Greet::hello: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: hello}, ~, ~, Str], # 1
  [Return, ~, [1], 0]]} # 2
Greet::import: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "import "}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, ~, [2, 3, 4], ~, Scalar], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Print, ~, [9], 0, Scalar], # 10
  [Return, ~, [10], 10]]} # 11
Louder::shout: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: HELLO}, ~, ~, Str], # 1
  [Return, ~, [1], 0]]} # 2
main::__PROGRAM__: {start: 0, returns: [44], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "pkg "}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: main}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: " line "}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "300"}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: " file "}, ~, ~, Str], # 6
  [Constant, {const_type: string, value: adj}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: " tag "}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: "use: "}, ~, ~, Str], # 11
  [EntryDef, {package: main, sigil: "%", symbol: "main::"}, ~, ~, Hash], # 12
  [Constant, {const_type: string, value: floor}, ~, ~, Str], # 13
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 14
  [Constant, {const_type: string, value: strict.pm}, ~, ~, Str], # 15
  [MemStart], # 16
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [15, 16], 0, Unknown], # 17
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [14, 17], 17, Unknown], # 18
  [Subscript, ~, [12, 13, 18], ~, Scalar], # 19
  [Constant, {const_type: string, value: "yes"}, ~, ~, Str], # 20
  [Constant, {const_type: string, value: "no"}, ~, ~, Str], # 21
  [TernaryExpr, ~, [19, 20, 21], ~, Str], # 22
  [Constant, {const_type: string, value: LOCK_EX}, ~, ~, Str], # 23
  [Subscript, ~, [12, 23, 18], ~, Scalar], # 24
  [TernaryExpr, ~, [24, 20, 21], ~, Str], # 25
  [Constant, {const_type: string, value: "inc: "}, ~, ~, Str], # 26
  [EntryDef, {package: main, sigil: "%", symbol: INC}, ~, ~, Hash], # 27
  [Subscript, ~, [27, 15, 18], ~, Scalar], # 28
  [TernaryExpr, ~, [28, 20, 21], ~, Str], # 29
  [Subscript, ~, [27, 14, 18], ~, Scalar], # 30
  [TernaryExpr, ~, [30, 20, 21], ~, Str], # 31
  [Constant, {const_type: string, value: Greet}, ~, ~, Str], # 32
  [Constant, {const_type: string, value: tag}, ~, ~, Str], # 33
  [Call, {class_name: Greet, dispatch_kind: method, name: import, param_names: []}, [32, 33], 18, Unknown], # 34
  [Call, {dispatch_kind: direct, name: Greet::hello, param_names: [], want: list}, ~, 34, Str], # 35
  [Coerce, {from_repr: Unknown, to_repr: Str}, [35], ~, Str], # 36
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 37
  [Call, {dispatch_kind: direct, name: Louder::shout, param_names: [], want: list}, ~, 35, Str], # 38
  [Coerce, {from_repr: Unknown, to_repr: Str}, [38], ~, Str], # 39
  [Print, ~, [36, 37, 39, 10], 38, Scalar], # 40
  [Print, ~, [26, 29, 31, 10], 40, Scalar], # 41
  [Print, ~, [11, 22, 25, 10], 41, Scalar], # 42
  [Print, ~, [2, 3, 4, 5, 6, 7, 8, 9, 10], 42, Scalar], # 43
  [Return, ~, [1], 43]]} # 44
"BEGIN 1": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: POSIX}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: POSIX.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: POSIX, dispatch_kind: method, name: import, param_names: []}, [1], 4, Unknown], # 5
  [Return, ~, [5], 5]]} # 6
"BEGIN 2": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: Fcntl.pm}, ~, ~, Str], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
"BEGIN 3": {start: 0, returns: [8], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: constant}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: TAG}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: c}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: constant.pm}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [4, 5], 0, Unknown], # 6
  [Call, {class_name: constant, dispatch_kind: method, name: import, param_names: []}, [1, 2, 3], 6, Unknown], # 7
  [Return, ~, [7], 7]]} # 8
"BEGIN 4": {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "begin\n"}, ~, ~, Str], # 1
  [Print, ~, [1], 0, Scalar], # 2
  [Return, ~, [2], 2]]} # 3
"END 5": {start: 0, returns: [3], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "end\n"}, ~, ~, Str], # 1
  [Print, ~, [1], 0, Scalar], # 2
  [Return, ~, [2], 2]]} # 3
```
