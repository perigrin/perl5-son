# Census cause: plain-package inheritance (381 -> 382; producer b92a0ce + 6e17433, chalk b99ca2b0)

**Cause:** "perl's own package variable @ISA is not lowered". It held 056:
`package Derived; our @ISA = ("Base"); $o->SUPER::hi()`. Even
`use parent` failed: no class record for a sub-less package, and no
parent for any plain package. See finding-plain-package-inheritance.md.

## What changed

- **Producer (`_record_plain_parents`, `_plain_parent`).** A package a
  method call names, and its parents transitively, gets a class record
  whose parent is:
  - its compiled @ISA (`use parent`), or
  - a constant one-element @ISA write on the program's main control
    chain (walked back from its Return), with no method call before it
    and no branch or loop on the way.

  Two parents, a computed one, a write under a branch, or a parent
  from another file (Exporter) is not claimed. Test:
  t/b-son-a-plain-package-records-its-parent.t (13).
- **chalk.** `_attach_call_targets` finds a package sub through the
  superclass chain, and `X::SUPER::m` from X's parent. An @ISA store of
  exactly the recorded parent is a no-op; other @ISA uses are refused.
  Test: llvm-a-plain-package-inherits.t (5).
- llvm-a-package-method-is-its-sub.t expected the inherited case
  refused; it now checks perl's answer.

**Round-tripped:** 056.

**Seen on the way:**
- The first full check had two tests fail on `:isa(Exporter)`. The
  producer claimed Exporter as a parent; fixed by claiming only the
  program's own packages.
- The producer drops an `if` condition around an @ISA write
  (`if (@ARGV) { @X::ISA = ... }`), leaving a second successor of
  Start. chalk refuses that shape; added to the report list.
