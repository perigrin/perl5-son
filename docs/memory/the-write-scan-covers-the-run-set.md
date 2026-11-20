---
name: the-write-scan-covers-the-run-set
description: "_package_scalars_written read named subs only; anon subs, ADJUST blocks and unfollowed classes are on the wire too. Each body is scanned as its walk starts and B::SoN translates again when one names a new scalar"
metadata:
  type: project
---

Follow-up to W1 (branch `w1-scan`, off wip/chalk-lib-roundtrip 72ada53).
`_package_scalars_written` decides which package scalars are read through
memory. It read the program root and the named subs of the program's and its
followed modules' packages. The wire's run set is larger: anon sub bodies,
ADJUST blocks, field defaults, lexical subs, phase blocks, and the methods of
a class in a file that is not followed (a lower-case module name) which
`_emit_referenced_classes` emits because the program calls it.

Two wrong shapes, probes `p/w1lib1..6` (module under `p/w1lib/`):

- The loop stores the scalar, in a graph the scan missed (w1lib1-3): a value
  Phi. chalk 507c6875 refuses it (WireCheck's W1 rule); with that rule off,
  13 or 3 for perl's 33.
- The loop only reads it, the writer is in a graph the scan missed
  (w1lib4-6): no Phi, the pre-loop read is forwarded. No WireCheck rule sees
  it: chalk printed four empty lines for perl's "", 10, 20, 30. **Wrong today,
  not only once the rule is deleted.**

The fix: `_scan_run_set_cv` at the top of `_translate_from` reads the body's
CV if the scan has not; the first answer also descends `anoncode` and reads
the program's BEGIN/END blocks. A name found after the first answer bumps
`package_writes_found_late`, and `B::SoN::_translate_until_settled` runs
`_discover_and_translate` plus `_phase_blocks` again until a pass adds none.

**Lessons:**

- **A scan that predicts the run set is a second definition of it.** The
  walk is what knows which bodies are on the wire (referenced classes are
  found by a fixpoint over translated graphs). Scan where the walk starts a
  body, and re-run when that taught something; do not grow the predictor to
  match. The predictor (anoncode, phase blocks) only saves second passes.
- **The first hunt was for the wrong shape.** Every probe with a store in
  the loop came back SAME or REFUSED, because the loop's own store put the
  name in the set, or chalk refused. The scalar must be bound before the
  loop in that graph (an unbound key gets no Phi), and the wrong answer chalk
  does not refuse has no store in the reader's graph at all.
- **Straight-line code was already safe**: a call drops package bindings, so
  `$n = 1; $f->(); print $n` was right unscanned. Only a loop re-reads a
  binding made before a call it has not walked yet.
- **A second pass must be the same wire.** Forced on 454 programs, it
  differed on 37: `$EVAL_COUNT` was a file lexical never reset, so eval ids
  started at 2. Now `our`, reset in `_discover_and_translate`. Warnings are
  buffered per pass and only the kept pass's are printed.
- **Do not load a helper module into the compiled program to instrument
  it.** `-MForceRepass` and `$main::FLAG` both showed up in the wire (a
  followed module, a stash key); an `%ENV` key in a scratch copy of lib does
  not.
- **Two unit tests had pinned the hole.** `t/from-optree-stash-store.t` and
  `t/from-optree-match-subject.t` translate `sub { our $g = 5; $g }` in
  process and expected the read to be the stored Constant. That forwarding
  only ever happened because an anon sub's body was unscanned; a named sub
  with the same text read through memory already. They now follow the read
  to its EntryWrite and check the stored value.
- **Cost: none measured.** B::SoN on chalk's six largest lib modules
  (5948f648; Context.pm 80 s, Target/C.pm 54 s under a loaded machine): base
  and new within run-to-run noise, and the six wires byte-identical.
- `/usr/bin/time` is not installed here: a backgrounded command using it
  dies at once and its output file stays empty. Use `date +%s`.

Related: [[a-written-package-scalar-is-never-carried]],
[[the-wire-is-checked-before-it-is-loaded]], [[run-long-checks-on-a-snapshot]].
