---
name: census-cause-list-flattening
description: 430/430 goal, cause "ArrayRef elem[N] has repr=Array" (9) — lists flatten a call's array; three silent/flaky wrong answers in read freezing and string termination; a census flake caught by re-running; ROUNDTRIP 154 -> 161 of 431
metadata:
  type: project
---

**Cause:** "ArrayRef elem[N] has repr=Array, which has no i64 payload
encoding" held 9 cases at 21594732. A literal like `(sort(keys %h),
"z")` holds the Array that a call made. (Plain `(0, @a, 3)` already
worked.)

**Built:**
- The literal is built by appending, through `@chalk_array_push_slot`
  and `@chalk_array_append_all`. A reference stays one element.
- `join` over such a list walks the flattened result.
- The element type of such a literal is Scalar (read by tag). A literal
  of nothing but non-call Arrays is chalk's own nested array
  (son-aggregate-repr.t) and is kept as it was.

**Wrong answers reached, each fixed with a test that failed first:**
- In a sub whose body is a loop, `my %p = %$h` was re-copied after a
  store. `_find_memstart` never found MemStart (it's reachable only
  through the loop's statements), so the entry reads were never frozen.
  The walk now goes into control-node bodies, and a read that reaches
  an unlowered loop Phi through any input stays in its loop.
- A read already lowered during a freeze (a sort over a copy-deref) was
  left unmarked, so it re-made itself later.
- MakeCell (a closure's capture) carries a memory version on, and reads
  at it were never frozen. `my @k = sort keys %h` beside a closure over
  `%h` read `%h`'s final contents.
- A class method stringifying a Num needed `@fmt_num_g`/`@snprintf`,
  which only the prologue declared. They are now also re-emitted after
  class bodies.

**A census flake, the lesson of this pin:** the official census showed
DIFFERS 1 (417) at 43ba40ea; two reruns were clean. The cause:
`@chalk_str_inc` left its result unterminated, and `@chalk_str_to_num`
handed the raw pointer to strtod, which read past the length into
whatever followed. Fresh heap is usually zero, which is why it was
flaky. Both are fixed: the result is terminated, and the reader parses
a terminated copy. **Pin only after several census runs agree**, and
treat any single DIFFERS as a real bug until shown otherwise.

**Round-tripped:** 154 -> 161 (158, 181, 218, 237, 283, 149, 249 and
others).

**Follow-up (a934d567, 161 -> 164):** "a list with a List in it" (11)
was my own refusal in the flattening path. A direct call's value now
flattens: an Array element by element, a scalar as one. A probe found a
wrong answer: `sub g { () }` falls off its end on an empty list, and
the wire marks its Return `valueless`. The loader dropped that flag, so
`() = g()` counted 1 instead of 0. It's now carried, and such a call is
no element in a list. An explicit `return` is different: it carries an
empty ArrayLiteral as its list reading, so it already worked. A sub
whose returns merge different list readings (`return if $x; return 5`)
is refused by name. The rest of this cause: Slice (3), `\(...)` (2),
Range, Repeat.
