---
name: census-cause-no-resolved-callee
description: 430/430 goal, cause "direct call to X has no resolved callee" (8 cases) — anon subs called through a code ref had a graph and no metaobject; built from the graph; @_ of a no-arg call; ROUNDTRIP 122 -> 125
metadata:
  type: project
---

**Cause:** "direct call to X has no resolved callee" held 8 cases at
29c1f540.

**What it was:** B::SoN resolves `$f->(14)` to a direct Call that names
the anon body's graph (`main::__PROGRAM__::__ANON__:1:2`). But it
records only named subs in the class channel, and chalk's
`/^(.*)::([^:]+)$/` split can't parse that name anyway. B::SoN had
already met this and written down the rule: a Call names its callee
graph exactly, so ask the graph. `_attach_call_targets` now builds the
metaobject from the graph, once per body.

**Exposed:** a call passing no arguments to a sub that reads `@_` as a
list left ArgsSource unbound. That refused `c()` for named subs too.
`@_` is the empty array there now.

**Round-tripped:** 122 -> 125.

**What the rest hit:**
- `my sub` (lexical subs, 103).
- Signature anon subs (150).
- `utf8::upgrade` (229).
- `format` and `write` (292, 293). These need perl's formatter.
- `AUTOLOAD` (408). This is MOP dispatch.
