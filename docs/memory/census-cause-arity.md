---
name: census-cause-arity
description: 430/430 goal, cause "callee reads N positional args but the call passes M" (5) — perl's arity (undef/defaults/extras); a dropped shares_args flag made `&name` silently wrong, caught by the census; producer refusals now count as GAP not LOAD_FAIL; 139 -> 140 of 431
metadata:
  type: project
---

**Cause:** "callee reads N positional argument(s) but the call passes M"
held 5 cases at ddb38e93.

**Built:**
- A missing argument is undef, or its signature `= default`. The
  default is lowered after the passed arguments are bound, so it can
  read them. Extra arguments are passed and not read.
- A signature called with too many, or too few for a parameter with no
  default, dies in perl, and is refused by name.
- A parameter the body never reads is absent from the graph, so it
  counts as mandatory.
- An anon sub's declared list isn't on the wire, so only the parameters
  it reads are checked. The first version read the `@_` placeholder as
  slurpy and regressed 103 and 150.

**Wrong answer the census caught before commit:** `&name` without
parens runs on the caller's `@_` (the wire's `shares_args`). The loader
dropped the flag, and the zero-argument path gave an empty `@_`: "[]"
where perl says "[1 2]". The flag is now carried and refused by name.
Lesson: a field the loader drops is a wrong answer waiting for the code
path that would have needed it.

**Census tool:** bson's 0cc7a81 makes B::SoN refuse a string eval
beside lexicals by skipping the program graph. The census counted those
as LOAD_FAIL ("no program graph"). It now keeps the producer's stderr,
and such a case is GAP "producer: <reason>". The corpus is 431 cases now.

**Round-tripped:** 140 of 431.
