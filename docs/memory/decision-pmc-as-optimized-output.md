# Decision: .pmc beside .pm as the optimized-Perl output (perigrin, 2026-10-31)

perigrin: "I _really_ like the .pmc solution because later if/when we
add optimizing steps to the compiler someone can get the benefit
without losing the pure-perl perks".

**What it is.** Perl's `require` prefers `Foo.pmc` over `Foo.pm` in the
same @INC directory. Verified on perl 5.42: an older .pmc wins over a
newer .pm behind `use lib "lib"`. Module::Compile used this precedent.

**Use 1, now.** gate3 writes each emitted module as `.pmc` beside its
`.pm` in its tree copy. Hard-coded `use lib 'lib'` stops mattering, and
the 65 tests that read lib/ as source become measurable (see roadmap
step 3).

**Use 2, later: the deployment model.**
- `Foo.pm` stays the readable, debuggable source of truth.
- `Foo.pmc` holds B::SoN/chalk's optimized Perl rendered from the SoN
  graph (folded constants, dead code removed, and so on).
- Delete it or set PERL_DISABLE_PMC and you're back to pure Perl.
- The test suite run against both (gate3) is each optimization's oracle.

**Two outputs from one graph.** .pmc for people who keep perl, native
code via LLVM for people who don't.
