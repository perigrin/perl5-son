---
name: a-lone-replacement-is-a-value
description: `s/a/$y/` with a computed $y deleted the match; `s/(y)/$1/` read an earlier match or refused; both s/// sites took only a Constant off the stack
metadata:
  type: feedback
---

A replacement that is one variable has no replacement subtree. Its value
sits on the stack before the `subst`. Both RegexSubst construction sites
(the main walk and `_walk_loop_body`) took it only if it was a Constant.

- A computed lexical was dropped, so `s/a/$y/` deleted the match (`b`
  for `Zb`).
- The loop site left the value on the stack.
- A lone `$1` read an earlier match's capture (`aQb` for `ayb`), or
  refused when none existed. That was chalk's
  `s/^sv_2mortal\((.+)\)$/$1/`, refused as "a capture inside a s///e
  replacement".

Perl pushes the magic `$1` SV itself and reads it inside pp_subst, after
the substitution's own match.

Fix: `_subst_lone_replacement`, shared by both sites. A Constant is the
string; any other value is the computed replacement. A capture gvsv
directly before a replroot-less `subst` pushes a placeholder (in
`%SUBST_OWN_CAPTURE`), built as `RegexCapture` over a match half of the
same target, pattern and flags. That is the device
`_walk_subst_replacement` already uses for interpolated captures. Under
`/g` it still refuses: each match has its own capture.

A match on the right of an `and` now also sets `last_match`, in the main
walk and in arm walks, as the loop body's walk already did.

**Why:** the GAP message blamed the s///e cycle. The construct was a
plain s/// whose replacement happens to be a capture.

**How to apply:** when a refusal names a construct, run `B::Concise
-exec` on the actual source line first. The `/e` in the message was not
in the code.
