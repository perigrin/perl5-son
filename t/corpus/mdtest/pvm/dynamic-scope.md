# Dynamic scope and the bare block

The two constructs here are the ones that scope by TIME. `local` binds a
value for the duration of a block, and the bare block is the thing whose
exit performs the restore.

**Tier 05 scoping.** Introduces `enterloop`, `leaveloop`, `once`.
Depends on 04_operators.

`enterloop`/`leaveloop` is this tier's own op pair and the surprising
one: a bare block is a LOOP THAT RUNS ONCE. The two cases are together
because the pair is incidental in one and load-bearing in the other --
`leaveloop` is where `local`'s restore happens.

## `local` restores on block exit

This is the one form in the tier that is not lexical. `my`, `our` and
`state` all bind a NAME for a region of source; `local` binds a VALUE
for a region of TIME. Nothing about the name changes -- `$x` is the same
package scalar throughout -- and what the block changes is what that
scalar holds while the block is running.

The probe is the second print: the block shows the localised 2, and
after it `$x` is 1 again, restored by the block exit with no statement
putting it back. That restoration is the entire construct.

Like `our`, it emits no op of its own: `gvsv` and `sassign` are tier
02's, and the difference from `our` is a flag, `gvsv[*x] s/LVINTRO`
against `s/OURINTR`, which the ops list does not record. The `enterloop`
and `leaveloop` are the bare block's, this tier's own, and here they are
load-bearing rather than incidental -- `leaveloop` is where the restore
happens.

No `use strict`, deliberately. Under strict, `local $x` on an undeclared
package variable is a compile error ("Global symbol "$x" requires
explicit package name") and would need an `our $x` first, making the
case a test of two constructs. The corpus does not run under strict
unless a case asks for it, so the plain assignment on line 1 is what
brings `$main::x` into existence.

```perl
$x = 1;
{
  local $x = 2;
  print "$x\n";
}
print "$x\n";
```

```behavior
parses: yes
```

```output
2
1
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: $, symbol: x}, ~, ~, Scalar], # 2
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 3
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 4
  [MemStart], # 5
  [EntryWrite, ~, [2, 3, 5], 0, Unknown], # 6
  [EntryWrite, ~, [2, 4, 6], 6, Unknown], # 7
  [EntryDef, {package: main, sigil: $, symbol: x}, [7], ~, Int], # 8
  [Coerce, {from_repr: Int, to_repr: Str}, [8], ~, Str], # 9
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 10
  [Concat, ~, [9, 10], ~, Str], # 11
  [Print, ~, [11], 7, Scalar], # 12
  [EntryWrite, ~, [2, 3, 7], 12, Unknown], # 13
  [EntryDef, {package: main, sigil: $, symbol: x}, [13], ~, Int], # 14
  [Coerce, {from_repr: Int, to_repr: Str}, [14], ~, Str], # 15
  [Concat, ~, [15, 10], ~, Str], # 16
  [Print, ~, [16], 13, Scalar], # 17
  [Return, ~, [1], 17]]} # 18
```

## A bare block is a scope, and a loop that runs once

A bare `{ ... }` at statement position is a SCOPE: declarations inside
it are gone on the far side, and it executes exactly once. It compiles
to `enterloop`/`leaveloop` -- perl builds it as a loop that runs once,
so that `last`, `next` and `redo` have something to act on inside it.
The braces look like grouping and the optree says loop.

The contrast is measured, because the same braces produce different ops
depending on what precedes them. Under 5.42.0:

    $ perl -MO=Concise,-exec -e '{ print "a\n"; }'
    ... enter nextstate enterloop nextstate pushmark const print leaveloop leave

    $ perl -MO=Concise,-exec -e 'my $c = 1; if ($c) { my $y = 2; print "$y\n"; }'
    ... and enter nextstate const padsv_store ... print leave leave

The `if` block gets `enter`/`leave`, tier 01's ops, because nothing can
jump out of it; only the bare form gets the loop pair. With a constant
condition -- `if (1) { ... }` -- the block ops vanish entirely, folded
away, which is the optimiser-erases-constructs warning in miniature. So
`enterloop`/`leaveloop` belong to this tier and not to 06_control, even
though 06 is where loops live.

The loop-ness is not probed behaviourally. Showing it would take a
`last` inside the block, and `last` compiles to a `last` op that no tier
at or before 05 claims -- measured; the op stream carries a literal
`last` between `print` and `leaveloop`. That probe belongs with the loop
control tier. What this case asserts is the part inside the budget: the
scope closes, and the block is entered once and not repeated.

The second block is what shows "once": a construct perl builds as a loop
prints `again` a single time. Its ops are the same pair -- `{ 1; }`
keeps its `enterloop`/`leaveloop` under 5.42.0, measured rather than
assumed, so an optimiser that erased a do-nothing block would be visible
as a missing op rather than as identical output.

```perl
my $x = 1;
{
  my $x = 2;
  print "in $x\n";
}
print "out $x\n";
{
  print "again\n";
}
```

```behavior
parses: yes
```

```output
in 2
out 1
again
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "again\n"}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: "out "}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 4
  [Coerce, {from_repr: Int, to_repr: Str}, [4], ~, Str], # 5
  [Concat, ~, [3, 5], ~, Str], # 6
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 7
  [Concat, ~, [6, 7], ~, Str], # 8
  [Constant, {const_type: string, value: "in "}, ~, ~, Str], # 9
  [Constant, {const_type: integer, value: "2"}, ~, ~, Int], # 10
  [Coerce, {from_repr: Int, to_repr: Str}, [10], ~, Str], # 11
  [Concat, ~, [9, 11], ~, Str], # 12
  [Concat, ~, [12, 7], ~, Str], # 13
  [Print, ~, [13], 0, Scalar], # 14
  [Print, ~, [8], 14, Scalar], # 15
  [Print, ~, [2], 15, Scalar], # 16
  [Return, ~, [1], 16]]} # 17
```
