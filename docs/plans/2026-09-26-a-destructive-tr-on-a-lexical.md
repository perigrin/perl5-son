# A destructive tr/// on a lexical needs three changes, not one

Case 010 and 180 of pvm's conformance corpus, the last two emissions in the
corpus that do not compile. First attempt REVERTED -- it fixed one third and
turned a compile error into a silent wrong answer, which is worse.

## The shape

```perl
my $tr = "a.c";
my $cnt = ($tr =~ tr/./Z/);
print "$tr $cnt\n";      # perl: aZc 1
```

emits

```perl
print join('', (((("a.c" =~ tr[.][Z]r) . " ") . ("a.c" =~ tr[.][Z])) . "\n"));
```

`Can't modify constant item in transliteration (tr///)`.

## Why the subject is a value

The op carries the targ and there is NO padsv operand -- measured:

```
7  <"> trans[$tr:1,3] sP/TRANS=ONLY_UTF8_INVARIANTS
```

so `$sim->pop_node` in the `trans` handler returns whatever the preceding
assignment left on the stack: the Constant the slot was bound to. The producer
then rebinds the slot to the Transliterate, which is right, but the node's
SUBJECT is a value.

The PACKAGE form was always correct -- its subject is the EntryDef, itself an
lvalue -- which is why only the lexical shape failed.

## The three parts, and why they are one commit

Substituting `_make_pad_or_field($cv, $op->targ, $factory)` for the popped value
fixes part 1 alone. Measured after that change:

```perl
print join('', (((($tr =~ tr[.][Z]r) . " ") . ($tr =~ tr[.][Z])) . "\n"));
```

It compiles. It is also wrong twice over:

1. **SUBJECT** (done, reverted with the rest): the subject must be the pad slot.
2. **THE DECLARATION IS PRUNED.** `my $tr = "a.c"` is gone -- the graph holds no
   VarDecl at all. `_declare` built one at the sassign, but with the slot bound
   to the Constant nothing consumed it and it was unreachable. Replacing the
   subject does not connect it; the PadAccess is unbound, so the emitted program
   reads an undeclared `$tr` and prints ` 1` where perl prints `aZc 1`. A
   compile error became a silent wrong answer.
3. **THE tr/// RUNS TWICE.** The Transliterate has two consumers -- the string
   read (rendered `/r`) and the TransliterateCount (rendered destructively) --
   and each renders it independently. The second run sees the already-
   transliterated string. This is exactly [[one-node-two-consumers-runs-twice]],
   and s/// already solved it: `EntryWrite` + `RegexSubst` + `_counted_subst`
   emits the destructive form ONCE, bound to a temporary, and the count reads
   the binding (Deparse.pm:2017). tr/// has no such arm, and the pad case has a
   VarDecl rather than an EntryWrite, so the existing arm would not catch it
   even if it covered Transliterate.

Shipping any one of the three alone is a regression on the other two. Part 1
without 2 is the silent wrong answer measured above; part 1 without 3 double-
runs a mutating op.

## What to build

- Producer: `trans` (not `transr`) with a targ takes the pad slot as its
  subject, and the declaration must stay reachable -- probably by threading the
  bound value as the PadAccess's input, the way an `addr_taken` read already
  does, so the VarDecl is not pruned.
- Deparser: a `VarDecl`/`Transliterate`/`TransliterateCount` arm mirroring the
  `EntryWrite`/`RegexSubst` one, so the destructive tr/// is emitted once and
  the count reads its binding.

The guards are already written and passing in
`t/from-optree-destructive-tr-names-its-pad.t`: the `/r` form must keep a value
subject, and the package form must keep its EntryDef.

Related: [[a-silent-drop-is-worse-than-a-refusal]],
[[removing-a-gap-can-create-a-miscompile]]
