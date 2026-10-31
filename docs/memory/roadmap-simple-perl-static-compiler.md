# Roadmap: a very simple Perl static compiler (perigrin, 2026-10-31)

perigrin: "getting use/require working and the test suite using
Test::Chalk ... and then making sure the lowering can self-host ... we
should have the basics of a very simple Perl static compiler."

## Milestones, in order

perigrin's ordering: "B::SoN following use/require -> Test::Chalk ->
migrating tests to Test::Chalk -> B::SoN + LLVM round tripping the tests
-> Chalk Parser replaces B::SoN". T1/T2 is not a milestone. It fires on
a trigger (see below).

0. **Real calls.** perigrin: "real calls should definitely come before
   use/require step 1". A direct call to a user sub lowers to a real
   `define` + `call`, grown from the recursive-sub path. See
   decision-real-calls-not-inlining.md.
1. **B::SoN follows `use`/`require`.** It reads `%INC` after compile
   time and includes those files' subs transitively. Pragmas are
   skipped. XS modules are provided by chalk's runtime. Run-time
   `require $x` is a GAP. See plan-test-chalk.md.
2. **Test::Chalk.** The Test::More subset that compiles through LLVM.
   Checked against Test::More's own suite plus a differential harness.
3. **Migrate chalk's tests to Test::Chalk.** 559 files.
4. **A `prove` alternative that compiles first.** perigrin: "really just
   an alternate test::harness to `prove` that compiles everything
   through B::SoN + LLVM first and then runs the test file and compares
   it to the pure-perl version". For each test file: run it under perl,
   compile it (and the modules it loads) through B::SoN -> chalk -> lli,
   and compare the two outputs (TAP and exit code). Its summary counts
   (round-trip, GAP by cause, differs) are the census. Work it by
   largest cause. **Every failing idiom becomes a corpus case**
   (perigrin): cut a minimal program that reproduces it into an idioms
   corpus, separate from the pvm corpus so the goal's 430 stays fixed.
   Through 2026-10-31 this was NOT done. Shapes went into chalk unit
   tests (t/bootstrap/ir/*.t), and about 1053 probe programs sat in the
   session scratchpad, which is lost with the container. Each test pulls in the lowering it tests, so a clean
   run means the lowering compiles. Optional strong check: an IR fixed
   point.
   **Reuse tools/chalk-gate3.pl.** It already runs chalk's 547 test
   files against B::SoN's emitted Perl and matches 482 of 482 measured.
   Its 65 DEFERRED files read lib/ as source text, which the emitted
   lib/ replaced on disk. perigrin: through LLVM "we don't have that
   problem and we could pick up those 65 as well". The source tree stays
   in place and the compiled test reads it. They need run-time file I/O
   (open, readline, readdir, glob, run-time regex). Their gaps rank in
   the census like any other cause.
5. **Chalk's parser replaces B::SoN.** perigrin: "That'll drop the
   dependency on Perl itself." Done when chalk's parser parses the
   lowering and its tests into IR that passes the same census.

## Expected large pieces (judgment, not measured)

These are expected inside milestone 4, not before it. perigrin: "I
don't think we need the full T2 refactor to get the tests playing nice
with us as an oracle." The oracle only has to run and report. Early
GAPs are its data. Revisit T2 only if the chalk-t census shows the
per-site backend stalling on untyped values.

perigrin: "push that oracle as far as we can before we trigger the
T1/T2 refactor". The trigger is a measured stall in the chalk-t census,
not a forecast. Until then, work the census by largest cause in the
current backend.

perigrin: "T1/T2 is also triggered by maintainability ... and
optimization". There are three triggers, and any one of them is enough:
- **Coverage.** The chalk-t census stalls on untyped values.
- **Maintainability.** Per-site decisions in Context.pm get too tangled
  to change safely. Signs: one fix keeps needing edits at many sites,
  and the same rule is re-derived at each site (the `_repr_of`-after-
  `lower_value` lesson is an early example).
- **Optimization.** Per-site choices block whole-function
  representation decisions, such as unboxing across a loop or keeping a
  value typed across calls.

- **Real define/call everywhere.** Today every direct call is inlined,
  except a sub that calls itself.
- **A general boxed-Scalar path.** chalk's code is mostly untyped
  hashes and arrays of nodes. This is likely where the deferred T2
  refactor stops being optional.
  - Fold into it: %Slot's `defined` field is redundant with tag 0
    (Undef). It predates the tag (6101b9ef, 2026-08-31). Two sources of
    truth can disagree silently. Derive defined from the tag. First check
    that no Opaque (tag 9) path relies on the two differing. perigrin:
    "that's a later refactor".
- **A native runtime.** Scalar::Util's `refaddr`/`blessed` (771 uses in
  the lowering) and other XS functions must be provided.

## Still depends on perl

B::SoN uses perl's parser. Independence needs chalk's own parser end to
end, and that parser must also parse Test::Chalk (plan-test-chalk.md).
