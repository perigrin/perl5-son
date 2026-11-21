---
name: a-freed-cvs-address-is-another-cvs
description: "A flake of t/from-optree-match-subject.t (about 3 in 100, at the base too) was the package-write scan remembering a CV by address: in-process, a freed anon sub's address was a later one's, its writes unread; translate now holds what it translated"
metadata:
  type: project
---

Found when the stage-4 gate run failed t/from-optree-match-subject.t once
(2026-11-21). Not this branch's: 5 in 200 runs at the base, 7 in 200 here;
no PERL_HASH_SEED reproduced it, which pointed at addresses, not hashes.

`_scan_cv_package_writes` skips a CV whose address is in `%PKG_SCALAR_CV`.
A test that translates code strings in-process (`eval 'sub {...}'`, then
`SoN::FromOptree->translate`) frees each sub afterwards; a later one
allocated at the same address was taken as already read, so its `our $ps =
"abc"` was never seen, `$ps` counted as unwritten, and the match read the
carried Constant (a W1 carry) instead of the read at the store. `translate`
now keeps the coderef for the process (t/from-optree-a-translated-cv-keeps-its-address.t).

**How to apply:** a flake that no hash seed reproduces: look for a cache
keyed by `$$ref` (an address) over things that can be freed. Measure the
rate at the base before calling it yours or not.

Related: [[a-shared-visited-set-makes-order-matter]], [[pending-bug-lower-pm-two-shapes]].
