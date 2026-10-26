---
name: census-cause-tr
description: 430/430 goal, "Transliterate writing the location in place is not lowered" (3: 374 375 390) -- tr/// had no lowering at all; built with a 256-byte map/set and @chalk_tr; 243 -> 246
metadata:
  type: project
---

**Cause:** "Transliterate writing the location $t in place is not lowered"
(374 375 390) -- behind it, `cannot lower op=Transliterate`: no lowering.

**Built (chalk ee35c39d):** `_lower_transliterate` expands the lists as
written (ranges, `\n \t \r \\ \- \/ \.`; ASCII only), pads a short to-list
with its last, takes an empty one as the from-list (counting only), first
mention wins; a 256-byte map and a 256-byte set as module globals;
`@chalk_tr(src, len, map, in, out)` writes the new string and returns the
count, which `TransliterateCount` reads from `cache{"trcount:<id>"}`. A
location subject is stored back, as s/// does, so `_refuse_an_in_place_
write_to_a_location` no longer refuses tr///'s subject.

**Refused by name:** any flag (c d s r), non-ASCII, other escapes, a range
running backwards.

**Result:** 374 375 390 round-trip; 243 -> 246. Probes (escaped `-`,
`a-y`/`b-z`, in a loop, counted twice, `\t`, short to-list) round-trip.
