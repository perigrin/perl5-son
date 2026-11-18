---
name: test-more-s-todo-is-the-caller-s
description: Moving chalk's tests to Test::Chalk; $TODO is read by package name (local breaks an exported alias), Level matters, and T2 reads a global stale after eval { $code->() }
metadata:
  type: feedback
---

2026-11-17, migrating t/ from Test::More to Test::Chalk (branch
test-chalk-migrate). Three things a "same API" stand-in got wrong or could
not do:

1. **$TODO must be read as `${"${caller_pkg}::TODO"}`.** Exporting `$TODO`
   aliases `*main::TODO{SCALAR}` to the module's scalar, but `local $TODO`
   swaps the glob's scalar slot, so the module's own `$TODO` never sees it.
   Test::Builder's find_TODO reads by name for this reason.
2. **`$Test::Builder::Level` is load-bearing.** A helper that bumps it
   (PrecedenceSpecHelpers::isa_with_shape) relies on it for whose `$TODO`
   applies, not only for the failure line. Without it the caller's TODO
   block is silently ignored. Level must start at 1, or the helper's
   `Level + 1` gives 1.
3. **T2 miscompiles a package variable read after `eval { $code->(); 1 }`**
   when the code ref wrote it: the pre-eval value is read (DIFFERS, not a
   refusal). Repro: `our $C; sub inc { $C = $C + 1 } sub st { my ($code) = @_;
   $C = 0; my $ran = eval { $code->(); 1 }; print $C + 0, "\n" } st(sub { inc(); inc() });`
   perl prints 2, T2 prints 0. So Test::Chalk's subtest has no eval, and a
   skip_all inside a subtest is still unsupported.

Also: Test::More's prototypes matter (`ok((grep {...} @ids), ...)` is a
count under `ok ($;$)`, the first match without it). Taking Test::More out
uncovered lib code that leaned on what it loaded (Chalk::IR::Node called
Scalar::Util::refaddr without loading it). And a `plan skip_all` inside a
subtest can hide a real `not ok` (son-loop-backedge.t).

Also: perl flushes every handle before `fork`, so an unbuffered-vs-buffered
TAP stream is not a fork hazard. Test2::V0's `is` deep-compares a reference
(a `class` object compares by identity, an unblessed ARRAY/HASH by
structure): probe each converted call at run time (wrap main::is to log
ref-valued expectations) rather than grepping.

**How to apply:** when replacing a test library, compare stdout, stderr and
exit status against the old one under perl for every feature the suite
calls (t/bootstrap/test-chalk-under-perl.t), including TODO, Level and
subtest plans, before converting files.
