# Roadmap: a very simple Perl static compiler (perigrin, 2026-10-31)

perigrin: "getting use/require working and the test suite using
Test::Chalk ... and then making sure the lowering can self-host ... we
should have the basics of a very simple Perl static compiler."

## Milestones, in order

1. **B::SoN follows `use`/`require`.** It reads `%INC` after compile
   time and includes those files' subs transitively. Pragmas are
   skipped. XS modules are provided by chalk's runtime. Run-time
   `require $x` is a GAP. See plan-test-chalk.md.
2. **Test::Chalk.** The Test::More subset that compiles through LLVM.
   Checked against Test::More's own suite plus a differential harness.
   Chalk's 559 tests are swapped onto it.
3. **The chalk-t-through-LLVM census.** Chalk's tests become the
   oracle, as perl's `t/` is.
4. **The lowering self-hosts.** The strong form is a fixed point:
   chalk's lowering, compiled through LLVM, emits the same IR for the
   corpus as the perl-run lowering.
5. **Back to chalk's own parser.** perigrin: "pivot back to the parser
   to make sure it can *parse* the lowering tests and build an IR that
   lowers properly and we'll have the actual start of a self-hosting
   compiler ... That'll drop the dependency on Perl itself." Done when
   chalk's parser, not B::SoN, parses the lowering and its tests into
   IR that lowers and passes the same oracle.

## Expected large pieces (judgment, not measured)

These gate milestone 4 (self-hosting), not milestone 3. perigrin: "I
don't think we need the full T2 refactor to get the tests playing nice
with us as an oracle." The oracle only has to run and report. Early
GAPs are its data. Revisit T2 only if the chalk-t census shows the
per-site backend stalling on untyped values.

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
