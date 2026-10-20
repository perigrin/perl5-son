---
name: worktrees-share-one-stash
description: "git worktrees of one repo share a single stash; parallel agents using `git stash pop` swap each other's uncommitted work"
metadata:
  node_type: memory
  type: feedback
  originSessionId: c7427872-965a-4f72-9cbb-d235a4680e53
  modified: 2026-10-10T14:24:18.973Z
---

All worktrees of one repository share ONE stash list. On 2026-10-10 two
parallel fix agents (mc/arrayliteral, mc/derefassign) each ran `git stash` /
`git stash pop` to compare against base, and each popped the other's change:
derefassign's tree silently held arrayliteral's diff, so its suite run
measured the wrong code. The shared stash also holds perigrin's own entries
(e.g. `bson-wip-DO-NOT-DROP-...`), which a careless pop or drop would destroy.

**Why:** the stash is a ref in the common git dir, not per worktree.

**How to apply:** every fan-out prompt that gives agents worktrees must say
"never use git stash; compare against base with a second worktree, `git diff
BASE`, or `git show BASE:path`". When an agent reports a swap, check with
`git diff | diff - saved.diff` before restoring. See
[[landing-work-in-a-peers-repo-needs-a-commit]].
