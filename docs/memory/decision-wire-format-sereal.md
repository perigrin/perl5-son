---
name: Wire format and module cache (Sereal)
description: why the B::SoN -> chalk wire moves to Sereal with a per-module cache, and the decoder chalk must own
type: project
---
perigrin, 2026-11-11: the wire goes to **Sereal**, and chalk needs its own
**chalk-compliant Sereal decoder** (plain Perl chalk can compile; the CPAN
`Sereal::Decoder` is XS and cannot ride along once chalk self-hosts).

**Why:** measured on one easy-tier test (t/bootstrap/assignment-scope.t, under
load): B::SoN 50s translating 1067 subs from 129 chalk modules; chalk 6s, of
which JSON::PP decode of the 6.4 MB pretty wire was 2.8s (Storable thaw of the
same: 0.03s, 2.5 MB). Sereal also carries shared/circular references natively,
which the node graph is (today flattened to id remaps both ends).

**Order (Go/Rust model: compile a unit once, cache it, prune at link time):**
1. Compact JSON (pretty-printed today: ~3x the bytes and decode time).
2. Per-module cache: B::SoN translates a module once, keyed by a hash of its
   file, its followed deps' keys, and B::SoN's version; chalk's reachability
   pruning stays the "linker". Perl caveat: a module whose BEGIN/import changes
   its own subs or globals per caller needs the `use` args in the key, or no cache.
3. Sereal for wire and cache, XS decoder first; then the chalk-compliant
   decoder (tags, refs/aliases, objects, Snappy/Zstd) as a self-hosting task.

**How to apply:** none of this is milestone 2. Milestone 3 (running chalk's
tests through T2) needs 1-2; pvm does not read this wire, so the format is
perl5-son + chalk's to change.

**Later angle (perigrin, 2026-11-11: "not right now ... interesting"):** a
queryable store for the cached IR, especially the newer embedded,
SQLite-like graph databases. Prior art: Code Property Graphs (Yamaguchi et
al., IEEE S&P 2014; Joern), CodeQL (relational), Glean, Kythe, Doop/Souffle;
rustc and salsa persist their query dependency graphs between builds. It would
pay for cross-module queries (what reaches this sub) across cached modules
without loading them all. A plain per-module cache doesn't need it.

**And (perigrin, same day):** a custom embedding of blocks that weights
types and effects (stamps, the memory/control chain). Prior art: IR2Vec
(seed vectors for opcode/type/argument, flow-aware), ProGraML (LLVM IR as a
control/data/call graph for GNNs), code2vec (AST paths); none uses an effect
system that I know of. Uses: similarity search in the cached-IR store, finding
the gaps that refuse most, optimization heuristics.
