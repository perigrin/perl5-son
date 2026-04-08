# B::SoN Package Filter

**Date:** 2026-04-08
**Goal:** Add a `package=` option to B::SoN so it emits only methods from specified packages.

## Problem

`perl -MO=SoN,json lib/Foo.pm` dumps IR for every module Perl loads at compile time — Carp, Exporter, strict, warnings, and everything else `use`d by `Foo.pm`. This makes per-file comparison with Chalk impossible. Chalk parses one source file and produces IR for the packages declared in it. B::SoN must match that scope.

## Solution

Add `package=Name` options to the B::SoN CLI. When present, only emit methods whose CV stash matches one of the specified packages. When absent, emit everything (backwards compatible).

**Syntax:**

```bash
# Single package
perl -MO=SoN,json,package=Foo lib/Foo.pm

# Multiple packages
perl -MO=SoN,json,package=Foo,package=Bar lib/Foo.pm
```

**Matching rule:** Exact stash name match only. `package=Foo` includes `Foo::method` but not `Foo::Bar::method`. Pass additional `package=` options for each package you want.

## Changes

### B::SoN::compile()

Parse `package=X` options from `@opts`. Collect into a set (hash for O(1) lookup). Pass the set (or undef if empty) to `_discover_and_translate`.

### B::SoN::_discover_and_translate()

Accept optional `$filter` hashref. Pass through to `_walk_package`.

### B::SoN::_walk_package()

Two filter points:

1. **Before CV translation:** If filter is active and `$pkg_name` is not in the filter, skip all CVs in this stash.
2. **Before recursion:** If filter is active and no filter key starts with `$sub_pkg::`, skip recursing into sub-packages entirely. (Optimization — avoids walking stashes we will never emit from.)

Point 2 is optional — point 1 alone is correct. But skipping recursion into irrelevant stashes avoids translating CVs only to discard them.

## Test Plan

1. **No filter** — existing tests pass unchanged
2. **Single filter** — `package=Baz` emits only `Baz::*` methods
3. **Multiple filters** — `package=Foo,package=Bar` emits both, excludes others
4. **Exclusion** — define packages Foo and Bar, filter Foo, verify Bar absent
5. **Text format** — filter works with text output, not just JSON

## Future

When Chalk gains dependency loading, this filter becomes less critical. For now it scopes perl5-son output to match Chalk's single-file view.
