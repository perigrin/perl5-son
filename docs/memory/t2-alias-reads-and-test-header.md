# T2: foreach alias reads; the core test header

**Date:** 2026-11-13

## Foreach over @_ — an alias read is the element read

B::SoN gives `foreach my $e (@_)` as `${ defined $_[i] ? \$_[i] : undef }`
(a TernaryExpr guarding a Ref to a Subscript). T2 reads that deref as
`$_[i]` itself — but ONLY when all of these hold:

- the guarded form (a bare `\$a[i]` deref is a reference T2 does not make);
- the array is `@_` (ArgsSource);
- nothing in the sub reshapes `@_` (shift/pop/push/unshift/splice).

**Why narrow:** the first, broad rule (any array) took
`for my $e (@a) { shift @a; ... }` — perl's alias holds the element, an
index read into the shifting array does not: a wrong answer (probe a14).
A write through the alias is still refused.

## Core test header: `BEGIN { chdir 't' if -d 't'; require './test.pl' }`

- `-d` → `t2_ftdir` (opendir → 1, exists → '', missing → undef).
- `chdir` → `t2_chdir`; both pinned where they stand (the next `-d` reads cwd).
- `require 'CONST'` of a file B::SoN followed (`%FOLLOWED` from the wire's
  method `module` tags) is 1; any other require stays out of T2.

## Lesson: a refusal test can flip to a pass

`llvm-a-class-method-on-a-run-time-object.t` expected a GAP for two classes
sharing a method. It was refused only because T2 lacked array `exists`;
with it, T2 dispatches by `t2_class_of` correctly. Before changing such a
test, find WHY it was refused (T2's `$PATH->{why}`), and probe more than
one order so a right answer is not luck. Then assert perl's answer.
