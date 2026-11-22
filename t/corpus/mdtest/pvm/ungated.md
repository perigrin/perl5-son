# What the keywords mean with the feature off

Every version-gated construct in this corpus carries its pragma at the
top, and not one pinned what the same bytes mean with the feature OFF
-- which is half of what "version-gated" means, and the half where two
previously-found bugs lived. These four cases pin the other half.

**Tier 11 oo.** Introduces nothing of its own; each case uses `eval`
from 06_control and method dispatch from this tier. Depends on
08_references.

The shape is the same every time: ungated, the keyword is read as a
METHOD NAME or a FILEHANDLE, the bytes compile clean, and the program
means something else. The `eval` traps the death so STDOUT stays
pinnable -- without it a file would print nothing and exit 255, which
says nothing about where it failed.

THE TOKEN LAYER CANNOT SEPARATE THE TWO READINGS, and saying so is the
honest version of a claim these cases got wrong twice. Each positive
fact below is true under BOTH readings -- the keyword lexes as one word
whether it is a keyword or a method name -- so on its own it says
nothing about which reading applies. An earlier draft added `no
operator whose text is "->"` to each, reasoning that a method call is
written with an arrow and a lexer producing one here would have
manufactured it. A LEXER CANNOT MANUFACTURE BYTES THAT ARE NOT THERE:
`scanOperator` matches its table against `l.src` at each position, so a
token whose text is `->` requires those two bytes in the source. The
fact could never fail. The arrow was read off perl's DEPARSE of the
ungated reading and written as if it were a claim about tokens; the
reparse is the PARSER reinterpreting the same tokens, not the lexer
emitting different ones, which is exactly why the two readings are
dangerous. So each positive stays and does the work it can -- the
keyword lexes as ONE word, not split and not swallowed -- and THE
OUTPUT IS THE DISCRIMINATOR, because identical bytes lex identically.

## `state` without its feature is a method call

Without `use feature "state"`, `state $n = 0` is not a syntax error --
it is a METHOD CALL on an undeclared scalar, used as an lvalue.
Measured:

    $ perl -MO=Deparse -e 'sub c { state $n = 0; $n = $n + 1; return $n }'
    -e syntax OK
    sub c { $n->state = 0; $n = $n + 1; return $n; }

`-c` reports SYNTAX OK. The bytes compile clean and mean something
else: `state` is read as a method name, `$n` as the invocant, and the
whole thing as an lvalue. It fails only when the sub is called:

    $ perl -e 'sub c { state $n = 0; $n = $n + 1; return $n } print c()'
    Can't call method "state" on an undefined value

THE FAILURE IS AT RUNTIME, which is what makes this worth a case: a
parser that ignores the pragma produces a program perl accepts, and
nothing at compile time says otherwise. `defined $r` is the
discriminator -- under the feature `c()` returns 1 and this prints
`ran`; ungated it dies inside the eval and prints `died`. The enabled
half is `05_scoping/03_state.t`.

```perl
sub c { state $n = 0; $n = $n + 1; return $n }
my $r = eval { c() };
print defined $r ? "ran" : "died", "\n";
```

```behavior
parses: yes
```

```output
died
```

```tokens
one word whose text is "state"
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 2], # 3
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 4
  [EntryWrite, ~, [3, 4], 0, Unknown, 2, true], # 5
  [Call, {dispatch_kind: direct, eval_id: 1, file: "/tmp/yDlL8UMbFX/case.pl", line: 2, name: main::c, package: main, param_names: [], want: scalar}, ~, 5, Scalar, 5, true], # 6
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 6], # 7
  [EntryWrite, ~, [7, 4], 6, Unknown, 6, true], # 8
  [Exc, ~, [6]], # 9
  [Region, {catch: true, eval_id: 1}, [9]], # 10
  [EntryWrite, ~, [7, 9], 10, Unknown, 6, true], # 11
  [Region, {eval_entry: 0, eval_id: 1}, [8, 11]], # 12
  [Phi, {region: 12}, [6, 1], ~, Scalar], # 13
  [Defined, ~, [13], ~, Boolean], # 14
  [Constant, {const_type: string, value: ran}, ~, ~, Str], # 15
  [Constant, {const_type: string, value: died}, ~, ~, Str], # 16
  [TernaryExpr, ~, [14, 15, 16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [17, 18], 12, "Maybe[Boolean]"], # 19
  [Phi, {memory: true, region: 12}, [8, 11], ~, Unknown], # 20
  [Return, {implicit: true}, [1], 19, ~, 20]]} # 21
main::c: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [EntryDef, {package: main, sigil: $, symbol: "n"}, ~, ~, Scalar], # 1
  [MemStart], # 2
  [EntryDef, {package: main, sigil: $, symbol: "n"}, ~, ~, Scalar, 2], # 3
  [Call, {dispatch_kind: method, file: "/tmp/yDlL8UMbFX/case.pl", line: 1, name: state, package: main, param_names: [], want: scalar}, [3], 0, Unknown, 2, true], # 4
  [EntryDef, {package: main, sigil: $, symbol: "n"}, ~, ~, Scalar, 4], # 5
  [Coerce, {from_repr: Scalar, to_repr: Num}, [5], ~, Num], # 6
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 7
  [Add, ~, [6, 7], ~, Num], # 8
  [EntryWrite, ~, [1, 8], 4, Unknown, 4, true], # 9
  [EntryDef, {package: main, sigil: $, symbol: "n"}, ~, ~, Scalar, 9], # 10
  [Return, ~, [10], 9, ~, 9]]} # 11
```

## `field` without the class feature is a method call

Without the `class` feature, `field $x` is a METHOD CALL on `$x` and
`class Foo { }` is an indirect method call whose block is an anonymous
hash. Measured:

    $ perl -MO=Deparse -e 'my $x; field $x;'
    my $x;
    $x->field;

    $ perl -MO=Deparse -e 'class Foo { }'
    'Foo'->class({});

Both compile clean, and the brace group is read as a hashref
constructor -- the same indirect-object shape the `new Foo` case
measures.

THE ASYMMETRY IS THE PART WORTH RECORDING, because it decides what a
case can claim. Measured:

    class Foo { }                        compiles -- indirect method call
    class Foo { field $x; method m {} }  SYNTAX ERROR near "; method "

So the silent reparse applies only to the EMPTY form. A populated class
body is a hard error without the feature, which means the
field-and-method case has no silent-reparse partner to write and the
empty-class case sits exactly in the dangerous window.

This case pins the `field` half, because it is observable without the
indirect-object spelling: the method call dies at runtime on an
undefined invocant, which the eval traps. The `class` half is recorded
above rather than written, since `'Foo'->class({})` would need a
`class` sub in scope to produce output and that sub would then be the
subject rather than the reparse.

```perl
my $x;
my $r = eval { field $x; 1 };
print defined $r ? "ran" : "died", "\n";
```

```behavior
parses: yes
```

```output
died
```

```tokens
one word whose text is "field"
```

```ir
main::__PROGRAM__: {start: 0, returns: [25], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 3], # 4
  [Assign, ~, [4, 1], 0, Undef, 3, true], # 5
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 5], # 6
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 7
  [EntryWrite, ~, [6, 7], 5, Unknown, 5, true], # 8
  [PadAccess, {sigil: $, symbol: x}, ~, ~, Unknown, 8], # 9
  [Call, {dispatch_kind: method, eval_id: 1, file: "/tmp/yDlL8UMbFX/case.pl", line: 2, name: field, package: main, param_names: [], want: void}, [9], 8, Unknown, 8, true], # 10
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 10], # 11
  [EntryWrite, ~, [11, 7], 10, Unknown, 10, true], # 12
  [Exc, ~, [10]], # 13
  [Region, {catch: true, eval_id: 1}, [13]], # 14
  [EntryWrite, ~, [11, 13], 14, Unknown, 10, true], # 15
  [Region, {eval_entry: 5, eval_id: 1}, [12, 15]], # 16
  [Phi, {region: 16}, [2, 1], ~, "Maybe[Int]"], # 17
  [Defined, ~, [17], ~, Boolean], # 18
  [Constant, {const_type: string, value: ran}, ~, ~, Str], # 19
  [Constant, {const_type: string, value: died}, ~, ~, Str], # 20
  [TernaryExpr, ~, [18, 19, 20], ~, Str], # 21
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 22
  [Print, ~, [21, 22], 16, "Maybe[Boolean]"], # 23
  [Phi, {memory: true, region: 16}, [12, 15], ~, Unknown], # 24
  [Return, {implicit: true}, [1], 23, ~, 24]]} # 25
```

## `__CLASS__` without the feature is a filehandle

Without the `class` feature, `__CLASS__` is a FILEHANDLE, and `print
__CLASS__;` prints `$_` to it. Measured:

    $ perl -MO=Deparse -e 'print __CLASS__;'
    print __CLASS__ $_;

    $ perl -MO=Concise -e 'print __CLASS__;'
    ... rv2gv sKR/1 ...
        gv[*__CLASS__] s ...

`rv2gv` over `*__CLASS__` -- a GLOB. Perl reads the bareword as a
filehandle name, `$_` as the thing to print, and the statement as a
print to a handle nobody opened. It compiles clean, prints nothing, and
exits 0.

THAT SILENCE IS THE HAZARD. `state` and `field` die at runtime, loudly
enough that a test notices. This one SUCCEEDS and produces no output,
so a program that meant to print a class name prints nothing and says
nothing about why. The sentinel after it is what makes the silence
observable: the `after` arrives, the class name does not, and a parser
that read `__CLASS__` as a term would have printed something before it.

This case is also where the copied arrow fact was sharpest wrong: the
ungated reading here is not a method call at all, so there was never an
arrow in the deparse to read the claim off. Our parser has since
accepted the file -- `print __CLASS__;` was refused because `__CLASS__`
is all-caps and was taken into `print`'s filehandle slot, the same bug
`10_compile_tokens.t` records reached through a different keyword.

```perl
print __CLASS__;
print "after\n";
```

```behavior
parses: yes
```

```output
after
```

```tokens
one word whose text is "__CLASS__"
```

```ir
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "after\n"}, ~, ~, Str], # 2
  [Constant, {const_type: glob, value: __CLASS__}, ~, ~, Glob], # 3
  [MemStart], # 4
  [EntryDef, {package: main, sigil: $, symbol: _}, ~, ~, Scalar, 4], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Print, {has_filehandle: true}, [3, 6], 0, "Maybe[Boolean]"], # 7
  [Print, ~, [2], 7, "Maybe[Boolean]"], # 8
  [Return, {implicit: true}, [1], 8, ~, 4]]} # 9
```

## `defer` without its feature runs the block FIRST

THE WORST OF THE SIX, and the reason is temporal rather than
structural. The corpus's other version-gate findings change what a
construct IS: `say` becomes a method call, `isa` becomes a filehandle
print, `state` becomes a method call on undef, and each fails loudly or
at runtime. This one changes WHEN the code runs. Measured:

    $ perl -e 'sub f { defer { print "D\n" } print "body\n" } f();'
    D
    body
    Can't locate object method "defer" via package "1"

    $ perl -e 'use feature "defer"; sub f { defer { print "D\n" }
               print "body\n" } f();'
    body
    D

Ungated, `defer { ... }` is a method call whose INVOCANT is the brace
group's VALUE -- so the BLOCK IS EVALUATED EAGERLY to produce it,
printing `D`, and only then does perl look for a `defer` method and
fail. The error names the invocant, and it is the block's last value
rather than a hash reference:

    Can't locate object method "defer" via package "1"

`package "1"` -- the `1` the block evaluated to. Confirmed on the
optree:

    $ perl -MO=Concise -e 'zzz { 1 } print "b";'
      <.> method_named[PV "zzz"]      invocant const[IV 1]

So the brace group here is a BLOCK whose value is the invocant, not an
anonymous hash constructor; an earlier draft of this case said hash, and
the `package "1"` in its own recorded output was already the
counter-evidence. Gated, the block runs at scope exit, after `body`. The
two readings produce the same two lines in the OPPOSITE ORDER, and the
failure arrives after the damage. A parser that always treats `defer
BLOCK` as a compound statement is wrong on pre-5.36 code; one that never
does is wrong on modern code, and nothing at compile time distinguishes
them.

WHICH READING APPLIES IS A SYMBOL-TABLE QUESTION, and perl gives three
answers for the same bytes:

    zzz {a};                   zzz { 'a' }       undeclared: method call
    sub zzz {} zzz {a};        zzz({'a'})        declared: anon hash arg
    sub zzz(&) {} zzz { 1 };   &zzz(sub { 1; })  prototyped: code ref

All three agree on the STATEMENT BOUNDARY -- the brace group and what
follows belong to one statement -- which is the part a parser can settle
without the symbol table, and the part this case pins.

What this claims is the ORDER: `D` before `body`, which is the ungated
reading, where the gated one gives `body` before `D`. Perl's deparse of
the ungated reading keeps the block form and shows no arrow at all:

    $ perl -MO=Deparse -e 'defer { print "D\n" } print "body\n";'
    defer {
        print "D\n"
    } print("body\n");

```perl
sub f { defer { print "D\n" } print "body\n" }
eval { f() };
print "end\n";
```

```behavior
parses: yes
```

```output
D
body
end
```

```tokens
one word whose text is "defer"
```

```ir
main::__PROGRAM__: {start: 0, returns: [16], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "end\n"}, ~, ~, Str], # 2
  [MemStart], # 3
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 3], # 4
  [Constant, {const_type: string, value: ""}, ~, ~, Str], # 5
  [EntryWrite, ~, [4, 5], 0, Unknown, 3, true], # 6
  [Call, {dispatch_kind: direct, eval_id: 1, file: "/tmp/yDlL8UMbFX/case.pl", line: 2, name: main::f, package: main, param_names: [], want: void}, ~, 6, Unknown, 6, true], # 7
  [EntryDef, {package: main, sigil: $, symbol: "@"}, ~, ~, Scalar, 7], # 8
  [EntryWrite, ~, [8, 5], 7, Unknown, 7, true], # 9
  [Exc, ~, [7]], # 10
  [Region, {catch: true, eval_id: 1}, [10]], # 11
  [EntryWrite, ~, [8, 10], 11, Unknown, 7, true], # 12
  [Region, {eval_entry: 0, eval_id: 1}, [9, 12]], # 13
  [Print, ~, [2], 13, "Maybe[Boolean]"], # 14
  [Phi, {memory: true, region: 13}, [9, 12], ~, Unknown], # 15
  [Return, {implicit: true}, [1], 14, ~, 15]]} # 16
main::f: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "D\n"}, ~, ~, Str], # 1
  [Print, ~, [1], 0, "Maybe[Boolean]"], # 2
  [Constant, {const_type: string, value: "body\n"}, ~, ~, Str], # 3
  [Print, ~, [3], 2, "Maybe[Boolean]"], # 4
  [MemStart], # 5
  [Call, {dispatch_kind: method, file: "/tmp/yDlL8UMbFX/case.pl", line: 1, name: defer, package: main, param_names: []}, [2, 4], 4, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```
