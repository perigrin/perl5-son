# A read between a mutation and its result

Every case here is one destructive quote-like whose count is bound. What
differs is WHERE the subject is read -- in the same statement as the
count, or in a statement between the mutation and the count's use.

**Tier 09 regex.** Introduces `trans`. Depends on 01_literals.

THE TIER'S OTHER CASES PAIR CONSTRUCTS. This one pairs a construct with a
READ POSITION, which is a different axis and the reason it is here rather
than folded into the adjacency case. A destructive `tr///` and a
destructive `s///` each do two things -- change the subject, and yield a
count -- and an implementation that renders the mutation wherever its
value is first read is correct on every body that reads both in one
statement and wrong on every body that does not.

The property is not the operator's. Any op that mutates a container and
yields a value has it; `shift @q` is the same shape on an array. This tier
can only write the quote-like forms, so that is what these cases are, and
the generalisation is the point rather than the spelling. (`shift` is
claimed by tier 11 today, which is tracked as a grading defect in
`01a0dde3`; when it moves to tier 02 the array spelling belongs there.)

Contributed by the B::SoN session, which found the property by reverting a
fix whose three passing assertions all lived in the one-statement shape.
Every output below was verified against perl 5.42.0 on arrival.

## Both reads in one statement

The control. A mutation and its count read together cannot distinguish
"emitted where it happened" from "emitted where its value was wanted" --
there is only one position. A case like this passes under the defect the
next two cases catch, which is what makes it worth writing down: it
establishes that the `tr///` itself is right before the position is asked
about.

```perl
my $t = "a.c";
my $c = ($t =~ tr/./Z/);
print "both $t $c\n";
```

```behavior
parses: yes
```

```output
both aZc 1
```

```ir
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "both "}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: t}, [3], ~, Unknown], # 4
  [Constant, {const_type: string, value: a.c}, ~, ~, Str], # 5
  [Assign, ~, [4, 5], 0, Str], # 6
  [PadAccess, {sigil: $, symbol: t}, [6], ~, Unknown], # 7
  [Transliterate, {flags: "", from: ".", to: Z}, [7, 6], 6, Str], # 8
  [PadAccess, {sigil: $, symbol: t}, [8], ~, Str], # 9
  [Coerce, {from_repr: Unknown, to_repr: Str}, [9], ~, Str], # 10
  [Concat, ~, [2, 10], ~, Str], # 11
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [TransliterateCount, ~, [8], ~, Int], # 14
  [Coerce, {from_repr: Int, to_repr: Str}, [14], ~, Str], # 15
  [Concat, ~, [13, 15], ~, Str], # 16
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 17
  [Concat, ~, [16, 17], ~, Str], # 18
  [Print, ~, [18], 8, Scalar], # 19
  [Return, ~, [1], 19]]} # 20
```

## A read between the `tr///` and its count

The subject is read in a statement of its own, before the count is used.
That read must see the transliterated string, because the mutation has
already happened -- the binding of `$c` is where it happened, not where
`$c` is wanted.

An implementation that defers the `tr///` to the second print prints
`mid a.c` here and `end 1` after it. Both halves are individually
plausible: the count is right, and `a.c` is what `$t` held a statement
earlier. Only the pairing is wrong.

```perl
my $t = "a.c";
my $c = ($t =~ tr/./Z/);
print "mid $t\n";
print "end $c\n";
```

```behavior
parses: yes
```

```output
mid aZc
end 1
```

```ir
main::__PROGRAM__: {start: 0, returns: [21], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "end "}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: t}, [3], ~, Unknown], # 4
  [Constant, {const_type: string, value: a.c}, ~, ~, Str], # 5
  [Assign, ~, [4, 5], 0, Str], # 6
  [PadAccess, {sigil: $, symbol: t}, [6], ~, Unknown], # 7
  [Transliterate, {flags: "", from: ".", to: Z}, [7, 6], 6, Str], # 8
  [TransliterateCount, ~, [8], ~, Int], # 9
  [Coerce, {from_repr: Int, to_repr: Str}, [9], ~, Str], # 10
  [Concat, ~, [2, 10], ~, Str], # 11
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 12
  [Concat, ~, [11, 12], ~, Str], # 13
  [Constant, {const_type: string, value: "mid "}, ~, ~, Str], # 14
  [PadAccess, {sigil: $, symbol: t}, [8], ~, Str], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Concat, ~, [14, 16], ~, Str], # 17
  [Concat, ~, [17, 12], ~, Str], # 18
  [Print, ~, [18], 8, Scalar], # 19
  [Print, ~, [13], 19, Scalar], # 20
  [Return, ~, [1], 20]]} # 21
```

## The same read between an `s///` and its count

`s///` is the second two-region quote-like and has the identical shape: a
destructive form that mutates the subject and yields a count. A tier that
caught the `tr///` case and not this one would have fixed a spelling
rather than a property.

```perl
my $s = "aaa";
my $n = ($s =~ s/a/b/g);
print "mid $s\n";
print "end $n\n";
```

```behavior
parses: yes
```

```output
mid bbb
end 3
```

```ir
main::__PROGRAM__: {start: 0, returns: [20], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "end "}, ~, ~, Str], # 2
  [MemStart], # 3
  [PadAccess, {sigil: $, symbol: s}, [3], ~, Unknown], # 4
  [Constant, {const_type: string, value: aaa}, ~, ~, Str], # 5
  [Assign, ~, [4, 5], 0, Str], # 6
  [PadAccess, {sigil: $, symbol: s}, [6], ~, Unknown], # 7
  [RegexSubst, {flags: g, pattern: a, replacement: b}, [7, 6], 6, Str], # 8
  [RegexSubstCount, ~, [8], ~, Str], # 9
  [Concat, ~, [2, 9], ~, Str], # 10
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 11
  [Concat, ~, [10, 11], ~, Str], # 12
  [Constant, {const_type: string, value: "mid "}, ~, ~, Str], # 13
  [PadAccess, {sigil: $, symbol: s}, [8], ~, Str], # 14
  [Coerce, {from_repr: Unknown, to_repr: Str}, [14], ~, Str], # 15
  [Concat, ~, [13, 15], ~, Str], # 16
  [Concat, ~, [16, 11], ~, Str], # 17
  [Print, ~, [17], 8, Scalar], # 18
  [Print, ~, [12], 18, Scalar], # 19
  [Return, ~, [1], 19]]} # 20
```
