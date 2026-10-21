---
name: mutually-loaded-modules-each-refuse-for-the-other
description: LLVM.pm and LLVM::Context call into each other by full name and load at run time; translated one file at a time, each call was "a call into nothing"
metadata:
  type: project
---

The census compiles each module alone. LLVM.pm `require`s Context at
run time, and Context aliases LLVM's helpers (`*_require_repr =
\&Chalk::Target::LLVM::_require_repr`) and calls others by full name.
When B::SoN runs, neither file's callees exist, so the producer can't
mark the calls `external`. The deparser refused each module for the
other's sake.

Two fixes:

- `_package_defined_here`: a call into a package this program never
  defines is another module's, reached like an import.
- The glob bind took its package from the gv's stash (`rv2gv`), not
  `main`. `*rr = \&A::rr` in package B had bound `main::rr`.

**How to apply:** a "not in the graph" refusal naming another module's
package is a census artifact, not a dropped sub. One naming this file's
own package is still a dropped sub, and still refuses (tested).
