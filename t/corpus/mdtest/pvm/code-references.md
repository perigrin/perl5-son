# Code references

`\&foo` on a named sub, the call through the result, and the builtin
that reads the prototype back out of one.

**Tier 08 references.** Introduces `anonlist`, `prototype`, `ref`,
`refgen`, `rv2cv`, `rv2sv`, `srefgen`. Depends on 07_subroutines.

THIS IS WHAT PINS THE TIER BELOW 07 rather than at 03. Everything else
here needs only tier 02's aggregates; `\&foo` needs a named sub to
exist, and a tier introducing `rv2cv` before subroutines existed would
be claiming an op for a construct it could not write.

`rv2cv` is narrower than it looks. It appears ONLY for `\&foo` on a
named sub: `&{$r}()` and `&$r()` both compile to `entersub` with no
`rv2cv` at all. So these two cases are the tier's only source for that
op.

## The code reference and the call through it

`\&twice` on a NAMED sub is the only construct in this tier that emits
`rv2cv`, and `$c->(21)` calls the result through tier 07's `entersub`
-- the same "different route to an earlier tier's op" this tier does
with `rv2av` and `multideref`. Removing this case would leave the
README claiming an op nothing emits.

```perl
sub twice { return $_[0] * 2 }
my $c = \&twice;
print $c->(21), "\n";
```

```behavior
parses: yes
```

```output
42
```

```tokens
one operator whose text is "\\"
one operator whose text is "->"
```

```ir
main::__PROGRAM__: {start: 0, returns: [9], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: code, value: twice}, ~, ~, Code], # 2
  [Ref, ~, [2], ~, CodeRef], # 3
  [Constant, {const_type: integer, value: "21"}, ~, ~, Int], # 4
  [Call, {dispatch_kind: indirect, name: "", param_names: [], want: list}, [3, 4], 0, Unknown], # 5
  [Coerce, {from_repr: Unknown, to_repr: Str}, [5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Print, ~, [6, 7], 5, Scalar], # 8
  [Return, ~, [1], 8]]} # 9
main::twice: {start: 0, returns: [8], nodes: [
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

## `prototype` reads the parser's own input back

`prototype \&f` hands back, as a runtime STRING, the very text that
changed how calls to `f` parse. The parser's own input is readable as
data.

WHY THIS TIER AND NOT 07. `prototype` takes a CODE REFERENCE, and a
code reference is this tier's construct. Measured, `prototype \&f`
emits `rv2cv` and `srefgen`, and both are THIS tier's. Tier 07 declares
a prototype and measures what it does to a call site, but tier 07
cannot WRITE this construct, because `\&f` is not available to it. Tier
08 is the earliest tier in which `prototype` is spellable at all, so
the op lint and the placement argument agree rather than merely not
conflicting.

WHAT TIER 07 ALREADY CLAIMS, AND WHAT THIS ADDS.
`07_subroutines/09_prototype_extent.t` measures the `($)` prototype's
effect on PARSING: `print g 1, 2` cuts the argument extent to one and
the second constant falls through to the enclosing `print`. That claim
is about a CALL SITE, where the prototype is invisible and only the
output reveals it. This case makes the complementary claim and repeats
none of it: there is no parenless call here, and the prototyped sub is
never called at all. What is here is the prototype coming back OUT as
the ONE-character string `$` -- measured, `prototype \&f` for
`sub f ($)` returns `$` with length 1, because the parentheses are
prototype SYNTAX and not part of the value.

THE WRONG PARSE THIS RULES OUT. `prototype \&f` is a word immediately
followed by a reference operator applied to a sub sigil, with no
parentheses to bracket the argument. A lexer that read `\&` as ONE
token -- a plausible reading, since the two characters only ever occur
together in this tier -- produces a program whose optree still contains
`srefgen` and whose output is unchanged, because perl's ops and perl's
bytes cannot see the difference. The token facts are the only place
that reading dies: exactly one `\` operator, and NOT one whose text is
`\&`.

`prototype` is the one word in the source, which is also a fact worth
pinning: a lexer that folded `prototype \&f` into a single term the way
it might a quote-like operator would leave no separate `prototype` word
behind. Its own text appears NOWHERE ELSE in the source, so the count
is a real claim rather than a coincidence of the fixture.

MEASURED perl 5.42.0, the whole program:

    3  <#> gv[IV \"$"] s
    4  <1> rv2cv[t3] lKRM/AMPER,TARG
    5  <1> srefgen sK/1
    6  <1> prototype sK/1

`gv[IV \"$"]` rather than `gv[IV \&main::f]`: with a prototype in force
perl has folded the sub's identity into its prototype string at compile
time, the same substitution `07_subroutines/09_prototype_extent.t`
records at its `entersub`. So the op stream does not even carry the
sub's NAME here, which is a further reason the token facts must.

```perl
sub f ($) { 1 }
my $p = prototype \&f;
print "[$p]\n";
```

```behavior
parses: yes
```

```output
[$]
```

```tokens
one operator whose text is "\\"
one word whose text is "prototype"
no operator whose text is "\\&"
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "["}, ~, ~, Str], # 2
  [Constant, {const_type: code, value: f}, ~, ~, Code], # 3
  [Ref, ~, [3], ~, CodeRef], # 4
  [Call, {dispatch_kind: builtin, name: prototype, param_names: []}, [4], ~, Scalar], # 5
  [Coerce, {from_repr: Scalar, to_repr: Str}, [5], ~, Str], # 6
  [Concat, ~, [2, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "]\n"}, ~, ~, Str], # 8
  [Concat, ~, [7, 8], ~, Str], # 9
  [Print, ~, [9], 0, Scalar], # 10
  [Return, ~, [1], 10]]} # 11
main::f: {start: 0, returns: [2], nodes: [
  [Start], # 0
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 1
  [Return, ~, [1], 0]]} # 2
```
