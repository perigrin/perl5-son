# A void `/g` match is dropped from the graph

Found while fixing the lvalue cluster, and NOT part of that cause.

## The measurement

```
my $s = "abcabc";
$s =~ m/b/g;
my $a = pos($s);
print "$a\n";
```

perl prints `2`. The graph holds:

```
  2 PadAccess          in=[] sigil=$ symbol=s
  3 Call               in=[2] name=pos
  4 Coerce             in=[3]
```

Two things are gone:

1. **The `m/b/g` in void context.** Nothing in the graph records the match, so
   nothing sets the position `pos` reads.
2. **`my $s = "abcabc"`.** The PadAccess is unbound and no VarDecl or store
   accompanies it, so the emission reads an undeclared `$s`.

## Why it is a separate defect

The lvalue cluster's cause was `is_compound` claiming a ONE-OPERAND op (fixed:
a compound assignment is binary, so the predicate needs `@inputs >= 2`). That
fix makes `pos` name its variable, which is the whole of what it owns. The
match being absent is upstream of it: a void-context `match` with the `/g` flag
is not translated at all.

`pos` is the only reader of that state we currently model, so the drop is
invisible everywhere else -- which is why it surfaced here rather than in its
own fixture.

## What it needs

A void `/g` match has to become a node that ADVANCES MEMORY on its subject, the
way `each` advances a hash's iterator (see the `keys`/`values`/`each` arm in
FromOptree.pm) -- two matches on one subject must not hash-cons into one node,
or the second would return the first's position. And `pos` must read that
memory version, not the bare slot, for the same reason `keys` takes the
container plus the memory it is read at.

Until then `pos` after a `/g` match is a WRONG ANSWER rather than a refusal,
which is the failure mode this project treats as worst. Refusing it is the
smaller change and should come first.
