# use, require and import

`use Foo LIST` locates a file, loads it, and then calls
`Foo->import(LIST)`. `require` is the same construct with the import
step removed, and `import` is an ordinary method call. Those three
statements are this whole area.

**Tier 12 packages.** Introduces `require`. Depends on 07_subroutines.

`use` EMITS NOTHING -- it is a `BEGIN` block that has finished before
there is an optree to dump. `require` is the one construct here that
reaches run time and the one op this tier introduces: `require strict;`
emits `const[PV "strict.pm"] s/BARE` and then `require`, `require $m`
emits `padsv` and the same `require`. One op, several sources. `import`
emits `pushmark`, two `const`, `method_named` and `entersub` -- tiers
01, 07 and 11 between them, with nothing left over. There is no import
op; the reason `use` is heavier than `require` is a call the op stream
cannot distinguish from any other call.

Because both halves of `use` are compile-time, the cases observe them
through `%INC` and the symbol table rather than through anything the
loaded module emits. The `04`/`05` pair is where the tier's claim
actually lives: neither case alone separates loading from importing.

## `use strict;` lexes, and that is all it establishes

A pragma is a `BEGIN` block, finished before there is a runtime optree.
The op stream for this case is the stream for `my $x = "ok"; print
"$x\n"` alone, differing only in the feature bits printed on
`nextstate`, which are a field rather than an op.

WHAT THIS CASE DOES NOT REACH, stated plainly because the pin does not
say it. Measured: delete both `use` lines and this program still prints
`ok`. So the pin establishes that the lines LEX and the statement is
delimited, and it establishes nothing about the load or the import. A
pragma cannot do better -- its effect is lexical and compile-time, and
`$^H` and `${^WARNING_BITS}` consulted at run time report the CALLER's
scope, measured OFF inside the very file that turned them on.

It is kept because `use` with a pragma is the overwhelmingly common
spelling and a lexer that mis-delimited it would fail here. The case
that reaches the rest is the next one.

```perl
use strict;
use warnings;
my $x = "ok";
print "$x\n";
```

```behavior
parses: yes
```

```output
ok
```

```ir
main::__PROGRAM__: {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: ok}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 3
  [Concat, ~, [2, 3], ~, Str], # 4
  [Print, ~, [4], 0, Scalar], # 5
  [Return, ~, [1], 5]]} # 6
"BEGIN 1": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: strict}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: strict.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: strict, dispatch_kind: method, name: import, param_names: []}, [1], 4, Unknown], # 5
  [Return, ~, [5], 5]]} # 6
"BEGIN 2": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: warnings}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: warnings, dispatch_kind: method, name: import, param_names: []}, [1], 4, Unknown], # 5
  [Return, ~, [5], 5]]} # 6
```

## `use POSIX;` loads the file AND calls import

This is the case that makes `use` FALSIFIABLE, through a module with an
exporter and the symbol table. `use POSIX;` puts `floor` into `main::`,
and deleting the `use` line changes both pinned lines -- so the output
measures the statement rather than its absence of syntax errors.

POSIX is core, its import list is not versioned in any way this case
observes, and nothing here depends on what it prints, because it prints
nothing.

MEASURED perl 5.42.0:

    $ perl -e 'use POSIX; print +($INC{"POSIX.pm"} ? "yes" : "no"), ($main::{"floor"} ? "yes" : "no"), "\n"'
    yesyes

```perl
use POSIX;
print "POSIX loaded: ", ($INC{"POSIX.pm"} ? "yes" : "no"), "\n";
print "floor imported: ", ($main::{"floor"} ? "yes" : "no"), "\n";
```

```behavior
parses: yes
```

```output
POSIX loaded: yes
floor imported: yes
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "floor imported: "}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "%", symbol: "main::"}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: floor}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, ~, [3, 4, 5], ~, Scalar], # 6
  [Constant, {const_type: string, value: "yes"}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: "no"}, ~, ~, Str], # 8
  [TernaryExpr, ~, [6, 7, 8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: "POSIX loaded: "}, ~, ~, Str], # 11
  [EntryDef, {package: main, sigil: "%", symbol: INC}, ~, ~, Hash], # 12
  [Constant, {const_type: string, value: POSIX.pm}, ~, ~, Str], # 13
  [Subscript, ~, [12, 13, 5], ~, Scalar], # 14
  [TernaryExpr, ~, [14, 7, 8], ~, Str], # 15
  [Print, ~, [11, 15, 10], 0, Scalar], # 16
  [Print, ~, [2, 9, 10], 16, Scalar], # 17
  [Return, ~, [1], 17]]} # 18
"BEGIN 1": {start: 0, returns: [6], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: POSIX}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: POSIX.pm}, ~, ~, Str], # 2
  [MemStart], # 3
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [2, 3], 0, Unknown], # 4
  [Call, {class_name: POSIX, dispatch_kind: method, name: import, param_names: []}, [1], 4, Unknown], # 5
  [Return, ~, [5], 5]]} # 6
```

## `use POSIX ();` loads the file and suppresses import

The empty parentheses are not an empty argument list but the absence of
one. Same module and the same two observations as the case above, one
statement apart:

    use POSIX;      loaded yes    imported yes
    use POSIX ();   loaded yes    imported no

The first column is `require`'s half of `use`, the second is `import`'s.
The two cases' op streams are byte-identical to each other and to the
two `print` statements alone, which is why the symbol table is where the
difference is visible at all. That is the tier's defining difficulty
stated as a measurement: `use` is real, and no optree records it.

A pragma could not stand in here, because a pragma's whole effect IS its
import and there would be nothing left to observe.

MEASURED perl 5.42.0:

    $ perl -e 'use POSIX (); print +($INC{"POSIX.pm"} ? "yes" : "no"), ($main::{"floor"} ? "yes" : "no"), "\n"'
    yesno

```perl
use POSIX ();
print "POSIX loaded: ", ($INC{"POSIX.pm"} ? "yes" : "no"), "\n";
print "floor imported: ", ($main::{"floor"} ? "yes" : "no"), "\n";
```

```behavior
parses: yes
```

```output
POSIX loaded: yes
floor imported: no
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "floor imported: "}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "%", symbol: "main::"}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: floor}, ~, ~, Str], # 4
  [MemStart], # 5
  [Subscript, ~, [3, 4, 5], ~, Scalar], # 6
  [Constant, {const_type: string, value: "yes"}, ~, ~, Str], # 7
  [Constant, {const_type: string, value: "no"}, ~, ~, Str], # 8
  [TernaryExpr, ~, [6, 7, 8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Constant, {const_type: string, value: "POSIX loaded: "}, ~, ~, Str], # 11
  [EntryDef, {package: main, sigil: "%", symbol: INC}, ~, ~, Hash], # 12
  [Constant, {const_type: string, value: POSIX.pm}, ~, ~, Str], # 13
  [Subscript, ~, [12, 13, 5], ~, Scalar], # 14
  [TernaryExpr, ~, [14, 7, 8], ~, Str], # 15
  [Print, ~, [11, 15, 10], 0, Scalar], # 16
  [Print, ~, [2, 9, 10], 16, Scalar], # 17
  [Return, ~, [1], 17]]} # 18
"BEGIN 1": {start: 0, returns: [4], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: POSIX.pm}, ~, ~, Str], # 1
  [MemStart], # 2
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [1, 2], 0, Unknown], # 3
  [Return, ~, [3], 3]]} # 4
```

## `require strict;` -- the tier's one runtime op

The bareword-to-filename rewrite is the compiler's: by the time the op
runs, `strict` has become the string `"strict.pm"`, emitted as
`const[PV "strict.pm"] s/BARE` and consumed by `require`. So `require`
takes a filename, never a package name, and the bareword spelling is
sugar the op stream cannot see.

`strict` is chosen because it is core, prints nothing, and its version
does not reach the output. The load is observed through `%INC` rather
than through anything the module itself emits.

MEASURED perl 5.42.0:

    $ perl -e 'require strict; print +($INC{"strict.pm"} ? "yes" : "no"), "\n"'
    yes

```perl
require strict;
print "loaded ", ($INC{"strict.pm"} ? "yes" : "no"), "\n";
```

```behavior
parses: yes
```

```output
loaded yes
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "loaded "}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "%", symbol: INC}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: strict.pm}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [4, 5], 0, Unknown], # 6
  [Subscript, ~, [3, 4, 6], ~, Scalar], # 7
  [Constant, {const_type: string, value: "yes"}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: "no"}, ~, ~, Str], # 9
  [TernaryExpr, ~, [7, 8, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [2, 10, 11], 6, Scalar], # 12
  [Return, ~, [1], 12]]} # 13
```

## `require $m;` takes the filename from a variable

This is the case that shows the bareword form was sugar. `require
strict` emits `const[PV "strict.pm"] s/BARE` then `require`; this emits
`padsv` then `require`. One op, two sources, and only the operand
differs -- which is also why `require Foo::Bar` and `require
"Foo/Bar.pm"` are the same statement and `require $m` with `$m` holding
`"Foo::Bar"` is not.

MEASURED perl 5.42.0:

    $ perl -e 'my $m = "warnings.pm"; require $m; print +($INC{$m} ? "yes" : "no"), "\n"'
    yes

```perl
my $m = "warnings.pm";
require $m;
print "loaded ", ($INC{$m} ? "yes" : "no"), "\n";
```

```behavior
parses: yes
```

```output
loaded yes
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "loaded "}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "%", symbol: INC}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: warnings.pm}, ~, ~, Str], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [4, 5], 0, Unknown], # 6
  [Subscript, ~, [3, 4, 6], ~, Scalar], # 7
  [Constant, {const_type: string, value: "yes"}, ~, ~, Str], # 8
  [Constant, {const_type: string, value: "no"}, ~, ~, Str], # 9
  [TernaryExpr, ~, [7, 8, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Print, ~, [2, 10, 11], 6, Scalar], # 12
  [Return, ~, [1], 12]]} # 13
```

## `import` is an ordinary method call

`Marker->import("tag")` emits `pushmark`, `const[PV "Marker"] sM/BARE`,
`const[PV "tag"] sM`, `method_named[PV "import"]`, `entersub` -- tiers
01, 07 and 11 between them and nothing left over. The claim is that
`import` is not special, and the way to demonstrate it is to call it
directly and get the same stream `use` would have produced.

Called at run time rather than from `BEGIN` so the output order is the
source order. Under `BEGIN` the same call runs during compilation and
prints first, which is true of any BEGIN block and is tier 05's
business, not this tier's.

MEASURED perl 5.42.0:

    $ perl -e 'package Marker; sub import { print "import $_[0] $_[1]\n" } package main; Marker->import("tag"); print "after\n"'
    import Marker tag
    after

```perl
package Marker;
sub import { print "import $_[0] $_[1]\n" }
package main;
Marker->import("tag");
print "after\n";
```

```behavior
parses: yes
```

```output
import Marker tag
after
```

```ir
Marker::import: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "import "}, ~, ~, Str], # 1
  [ArgsSource, ~, ~, ~, Array], # 2
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 3
  [MemStart], # 4
  [Subscript, ~, [2, 3, 4], ~, Scalar], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [1, 6], ~, Str], # 7
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 10
  [Subscript, ~, [2, 10, 4], ~, Scalar], # 11
  [Coerce, {from_repr: Unknown, to_repr: Str}, [11], ~, Str], # 12
  [Concat, ~, [9, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Print, ~, [15], 0, Scalar], # 16
  [Return, ~, [16], 16]]} # 17
main::__PROGRAM__: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "after\n"}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: Marker}, ~, ~, Str], # 3
  [Constant, {const_type: string, value: tag}, ~, ~, Str], # 4
  [Call, {class_name: Marker, dispatch_kind: method, name: import, param_names: []}, [3, 4], 0, Unknown], # 5
  [Print, ~, [2], 5, Scalar], # 6
  [Return, ~, [1], 6]]} # 7
```
