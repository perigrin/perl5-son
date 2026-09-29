# Names: braces, carets and packages

Where the variable's NAME is the question rather than what it holds.
Braces around a name are punctuation; `$::` is a package-qualified name,
the scanner row measured at 0.0% clean over fourteen files; `$^O` folds
the caret into the name where a bare `$^` does not.

**Tier 02 variables.** Introduces `aassign`, `aelem`, `aelemfast`,
`aelemfast_lex`, `aelemfastlex_store`, `aslice`, `av2arylen`, `delete`,
`each`, `gv`, `gvsv`, `helem`, `hslice`, `multideref`, `padav`, `padhv`,
`push`, `rv2av`, `rv2hv`, `sassign`, `unshift`, `values`. Depends on
01_literals.

The package spellings are also where the tier's op list stops matching
the source a reader would write first. `sassign` -- the plain scalar
assignment -- is introduced by `$::x = 1`, not by `my $x = 1`, and the
four ops for a constant array subscript are only all reachable once both
a lexical and a package array are in the corpus.

## `${x}` is one variable, not a dereference

GLOSSARY.md says this outright under `variable` -- "`${name}` is
one variable: the braces are punctuation around a name. But `${ $ref }`
is NOT one token, because its contents are an expression requiring a
parser." The two spellings differ by what is inside the braces and by
nothing else, which makes this the tier's sharpest lexing question: a
lexer that sees `${` and commits to a dereference is wrong here, and a
lexer that sees `${` and commits to a name is wrong at tier 08. This
case takes the half that belongs to this tier; `${ $ref }` is tier 08's,
and writing it here would be reaching forward.

BOTH SIGILS ARE BRACED because the brace rule is about the NAME rather
than about scalars: `@{a}` is the same array as `@a`, and a lexer that
special-cased `${` would pass a case that only wrote the scalar form.

The ops are `padsv` and `padav`, identical to the unbraced spellings:
perl resolves the braces away entirely, so the optree cannot tell this
case from one without them. The claim is a LEXICAL one and only the
source records it -- the same situation tier 01 recorded for `-1`, whose
two tokens fold to one constant.

```perl
my $x = 42;
my @a = (7, 8);
print ${x}, "\n";
print scalar(@{a}), "\n";
```

```behavior
parses: yes
```

```output
42
2
```

```ir
main::__PROGRAM__: {start: 0, returns: [13], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "8"}, ~, ~, Int], # 3
  [ArrayLiteral, {sigil: "@", symbol: a}, [2, 3], ~, Array], # 4
  [MemStart], # 5
  [Count, ~, [4, 5], ~, Int], # 6
  [Coerce, {from_repr: Int, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Constant, {const_type: integer, value: "42"}, ~, ~, Int], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Print, ~, [10, 8], 0, Scalar], # 11
  [Print, ~, [7, 8], 11, Scalar], # 12
  [Return, ~, [1], 12]]} # 13
```

## `$^O` is one variable and a bare `$^` is another

The caret control variables are the third naming question in this tier,
and the one where the OUTPUT ALONE CANNOT SEE THE ANSWER. `$^O` lexed as
`Variable($^)` and a separate `Word(O)` -- two tokens where perl has
one -- and `my $x = $^O;` still produced a tree that parsed and
round-tripped, canonicalising to `$^;O()`: the punctuation variable, a
semicolon, and a call to a sub named `O`. Unknown=0 on a confidently
wrong tree. That is why this case carries TOKEN FACTS: they fail today
and the output block does not.

The braced spelling `${^TAINT}` was already right, because
`bracedNameFollowsAt` grew a caret branch when `TestLexDotTGoldenStream`
caught `${^TEST}` splitting. One spelling of the rule was repaired and
its bare sibling was left -- the same shape as `$::`, where `$:` alone is
also a real variable and the name only forms when something follows.

WHERE THE NAME STOPS is the whole claim, and perl is the authority.
Measured on 5.42.0 by compiling `my $x = $^C;` for every C: `$^A`
through `$^Z` compile, and so do `$^_`, `$^^` and `$^[`. A LOWERCASE
letter does not -- `$^o` is `Bareword found where operator expected`, so
perl read `$^` and then a word. Digits fail the same way. So the rule is
the uppercase range plus `_`, `^` and `[`, NOT the identifier class: a
lexer that took any identifier byte would swallow the word after a bare
`$^`, which is the format top-of-page name and a real variable.

`$^O` and `$^T` are ASSIGNED here and never printed, because their
values are the platform name and the start time -- neither is the same
twice. They still reach the token stream, which is where this case's
claim lives. `$^W` is the one with a value fixed across platforms, `0`
under the plain `perl FILE` the runner uses, so it carries the output.

Interpolation is deliberately absent: `"$^"` is `$` followed by a
literal caret and warns `Use of uninitialized value $`, a different
question belonging to tier 01. Every op here is a tier 01 or 02
fixture -- `sassign`, `gvsv`, `const`, `print` -- so a ternary or a
`defined` would have reached forward into tiers 04 and 06.

Each caret variable is written EXACTLY ONCE, because a token fact
counts occurrences and the format's only forms are `one` and `no`. So
every value travels out through a package scalar rather than being
assigned and then read back -- including the bare `$^`, whose evidence
is the token fact rather than the output. The negatives carry their
half of the claim: the split produced a `Word` for the letter, so
`no word whose text is "O"` is reachable from this source and fails
whenever the caret stops binding its letter.

```perl
$::w = $^W;
$::o = $^O;
$::t = $^T;
$::c = $^;
print $::w, "\n";
print "read\n";
```

```behavior
parses: yes
```

```tokens
one variable whose text is "$^W"
one variable whose text is "$^O"
one variable whose text is "$^T"
one variable whose text is "$^"
no word whose text is "O"
no word whose text is "W"
no word whose text is "T"
```

```output
0
read
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "read\n"}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: $, symbol: c}, ~, ~, Scalar], # 3
  [EntryDef, {package: main, sigil: $, symbol: t}, ~, ~, Scalar], # 4
  [EntryDef, {package: main, sigil: $, symbol: o}, ~, ~, Scalar], # 5
  [EntryDef, {package: main, sigil: $, symbol: w}, ~, ~, Scalar], # 6
  [MemStart], # 7
  [EntryDef, {package: main, sigil: $, symbol: "\u0017"}, [7], ~, Scalar], # 8
  [EntryWrite, ~, [6, 8, 7], 0, Unknown], # 9
  [EntryDef, {package: main, sigil: $, symbol: "\u000f"}, [9], ~, Scalar], # 10
  [EntryWrite, ~, [5, 10, 9], 9, Unknown], # 11
  [EntryDef, {package: main, sigil: $, symbol: "\u0014"}, [11], ~, Scalar], # 12
  [EntryWrite, ~, [4, 12, 11], 11, Unknown], # 13
  [EntryDef, {package: main, sigil: $, symbol: "^"}, [13], ~, Scalar], # 14
  [EntryWrite, ~, [3, 14, 13], 13, Unknown], # 15
  [EntryDef, {package: main, sigil: $, symbol: w}, [15], ~, Scalar], # 16
  [Coerce, {from_repr: Unknown, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 18
  [Print, ~, [17, 18], 15, Scalar], # 19
  [Print, ~, [2], 19, Scalar], # 20
  [Return, ~, [1], 20]]} # 21
```

## A package array subscripts through `rv2av`

`$a[0]` on a lexical is `aelemfast_lex`. `$::a[0]` is `aelemfast`
behind an `rv2av` over a `gv`. Constant subscript, lexical or package,
read or write -- four ops for what reads as one construct, which is why
the tier's adjacency case carries all four rather than a representative
one.

```perl
@::a = (1, 2, 3);
print $::a[0], "\n";
print scalar(@::a), "\n";
```

```behavior
parses: yes
```

```output
1
3
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 2
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 4
  [ArrayLiteral, {sigil: "@", symbol: "@main::a"}, [2, 3, 4], ~, Array], # 5
  [EntryDef, {package: main, sigil: "@", symbol: a}, ~, ~, Array], # 6
  [MemStart], # 7
  [EntryWrite, ~, [6, 5, 7], 0, Unknown], # 8
  [Count, ~, [5, 8], ~, Int], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 12
  [Subscript, ~, [5, 12, 8], ~, Scalar], # 13
  [Coerce, {from_repr: Unknown, to_repr: Str}, [13], ~, Str], # 14
  [Print, ~, [14, 11], 8, Scalar], # 15
  [Print, ~, [10, 11], 15, Scalar], # 16
  [Return, ~, [1], 16]]} # 17
```

## A package hash reaches storage through `rv2hv`

The element access is `multideref` either way -- the optimiser
folds the glob lookup into the deref chain just as it folds the pad
lookup -- so the difference this case pins is in naming the hash itself,
not in subscripting it. `scalar(keys %::h)` is what forces the bare name
into the optree, and that is `gv` then `rv2hv`.

```perl
%::h = (a => 1, b => 2);
print scalar(keys %::h), "\n";
print $::h{a}, "\n";
```

```behavior
parses: yes
```

```output
2
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: a}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: string, value: b}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 5
  [HashLiteral, {sigil: "%", symbol: "%main::h"}, [2, 3, 4, 5], ~, Hash], # 6
  [EntryDef, {package: main, sigil: "%", symbol: h}, ~, ~, Hash], # 7
  [MemStart], # 8
  [EntryWrite, ~, [7, 6, 8], 0, Unknown], # 9
  [Subscript, ~, [6, 2, 9], ~, Scalar], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Call, {dispatch_kind: builtin, name: keys, param_names: []}, [7, 9], ~, Int], # 13
  [Coerce, {from_repr: Int, to_repr: Str}, [13], ~, Str], # 14
  [Print, ~, [14, 12], 9, Scalar], # 15
  [Print, ~, [11, 12], 15, Scalar], # 16
  [Return, ~, [1], 16]]} # 17
```

## A package scalar is where `sassign` enters the corpus

Tier 01's `my $x = 0.5` emits `padsv_store` and no `sassign` at
all -- the lexical store is one op, not an assignment over a variable.
The package scalar is the first place the two halves separate: `gvsv`
fetches the glob's scalar slot and `sassign` puts the value in it. So
the op a reader would look for in tier 01 is introduced four constructs
into tier 02, by the spelling nobody writes first.

`$::x` rather than `$main::x`: `::` with an empty package name IS
`main`, and the short spelling is the one that makes the lexing question
visible -- whether `$::` is a sigil plus a name that begins with a
separator.

```perl
$::x = 1;
print $::x, "\n";
```

```behavior
parses: yes
```

```output
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [MemStart], # 4
  [EntryWrite, ~, [2, 3, 4], 0, Unknown], # 5
  [EntryDef, {package: main, sigil: $, symbol: x}, [5], ~, Int], # 6
  [Coerce, {from_repr: Int, to_repr: Str}, [6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 5, Scalar], # 9
  [Return, ~, [1], 9]]} # 10
```

## The bare main stash is `$::{...}` with an EMPTY package name

`$::{answer}` is `$main::{'answer'}`: the package name before the
separator is empty, so the name ends AT the second colon and the
subscript begins. `%::` is the whole stash.

WHY THE EMPTY NAME IS ITS OWN CASE, and not covered by the `$::x` one
already above. `$:` is a real punctuation variable -- the set of
characters a format may break a line on -- so a scanner that ends the
name at the first colon produces a *valid* variable and strands the
second colon as an operator. That is why this spelling failed while
`$main::{n}` and `$Pkg::{n}` were always right: the sibling spellings
have a name to scan and this one does not.

The scanner guard asked for a word byte after the two colons, which
`$::x` has and `$::{n}` does not. Two colons are now enough on their own,
because a scalar named `$:` cannot be followed by a second colon and
still be `$:`.

THE ASSERTION IS THE OUTPUT, both ways. A key that exists and a key that
does not, so a parser that reads the subscript as something else cannot
pass by accident -- `exists` on a stash slot is true only if the symbol
was installed, and `our $answer` installs one.

Measured 5.42.0: `gv` then `helem`, both introduced by this tier. The
empty package name costs no op the named spelling does not also use.

The whole stash `%::` is copied into a lexical hash, and the copy has the
key -- so the bare `%::` spelling is read as the hash it names.

```perl
our $answer = 42;
print "found: [", exists $::{answer}, "]\n";
print "gone: [", exists $::{nosuch}, "]\n";
my %stash = %::;
print "stash: [", exists $stash{answer}, "]\n";
```

```behavior
parses: yes
```

```output
found: [1]
gone: []
stash: [1]
```

```ir
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "stash: ["}, ~, ~, Str], # 2
  [EntryDef, {package: main, sigil: "%", symbol: "main::"}, ~, ~, Hash], # 3
  [Constant, {const_type: string, value: answer}, ~, ~, Str], # 4
  [EntryDef, {package: main, sigil: $, symbol: answer}, ~, ~, Scalar], # 5
  [Constant, {const_type: integer, value: "42"}, ~, ~, Int], # 6
  [MemStart], # 7
  [EntryWrite, ~, [5, 6, 7], 0, Unknown], # 8
  [Exists, ~, [3, 4, 8], ~, Boolean], # 9
  [Coerce, {from_repr: Boolean, to_repr: Str}, [9], ~, Str], # 10
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 11
  [Constant, {const_type: string, value: "gone: ["}, ~, ~, Str], # 12
  [Constant, {const_type: string, value: nosuch}, ~, ~, Str], # 13
  [Exists, ~, [3, 13, 8], ~, Boolean], # 14
  [Coerce, {from_repr: Boolean, to_repr: Str}, [14], ~, Str], # 15
  [Constant, {const_type: string, value: "found: ["}, ~, ~, Str], # 16
  [Print, ~, [16, 10, 11], 8, Scalar], # 17
  [Print, ~, [12, 15, 11], 17, Scalar], # 18
  [Print, ~, [2, 10, 11], 18, Scalar], # 19
  [Return, ~, [1], 19]]} # 20
```
