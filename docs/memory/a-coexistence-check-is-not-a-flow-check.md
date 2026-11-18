---
name: a-coexistence-check-is-not-a-flow-check
description: T2's "scalar deref where a reference T2 does not make may reach it" asked only whether both were in the program; 192 of 288 Test::Chalk-swap files refused for it. Asked as a flow (Chalk::IR::ReferenceFlow) it refuses where the value may go
metadata:
  type: feedback
---

The check in Target/LLVM/Lower.pm refused the whole program when ANY `$`
PostfixDeref and ANY Ref T2 does not make were both in `_all_nodes` -- which
holds every sub of every loaded module, called or not. Symbol::gensym's
`\*{$genpkg . $name}` (loaded by File::Temp via IO::Handle) refused every
program that loaded it; `\@held_rows` in Earley.pm refused every program
reaching the parser.

Two causes, two layers:

1. `\@held_rows` was not an unmakeable reference at all. B::SoN stamps a
   variable by the op reading it: `!@held_rows` reads @held_rows as a count,
   so the PadAccess arrives `Scalar` and `\@held_rows` arrives `ScalarRef`
   (`\@chart`, never tested for truth, arrived ArrayRef). The loader already
   restamped the PadAccess Array; it now stamps the Ref by its operand's sigil
   (`\@x` is an ARRAY reference whatever the wire says). The producer's stamp
   is still wrong -- a B::SoN fix would be the root one.
2. The check measured coexistence, not reach. Chalk::IR::ReferenceFlow
   follows the Ref's value forward (value uses, stores by location, callee
   parameters and @_, returns to every caller and every code-value call) and
   ESCAPES -- refuses -- where it cannot say (closure cells, `local`, die, a
   builtin that may keep it, a store through a reference, a tie).

**Why:** a check that asks "is X anywhere?" over the whole MOP refuses every
program that LOADS a module with X. The refusal count looked like 192
programs needing glob support; most needed neither globs nor fields.

**How to apply:** when a program-wide refusal fires on most of a corpus, list
the offending nodes per file (a probe wrapping `Builder::out`) before
believing the reason. And a T2 build of an unmakeable Ref already refuses by
name ("a reference to what is not an array") -- the flow check only guards
Refs T2 never builds, so after it, the earley files refuse at the field Ref
instead: the honest next blocker.

Found beside it, not fixed: a hash in scalar or truth context reads its
%Slot (`my %h; print "e" if !%h` prints nothing; `my $n = %h` prints
`HASH(0x...)`) -- a T2 wrong answer the probes do not cover.
