# Census cause: a sub that calls itself (372 -> 373, pin 4c4c7e4b)

**Cause:** "direct call to X is recursive -- inlining is the only
direct-call mechanism". It held 248 (`fib`).

## What changed (chalk 4c4c7e4b)

- **Emitted as a define.** A sub whose own graph makes a direct call
  to it is registered `recursive` and emitted as a define even with
  CHALK_EMIT_SUB_DEFINES off. It is never inlined, so its body is not
  duplicated. `_call_sub_define` calls it from the program and from
  inside its own body.
- **Parameter types.** A sub's parameters are typed from its outside
  callers.
  - An arm from a call inside the sub's own body whose argument is
    still Unknown is deferred, as a self call's arm is. It counts once
    it resolves.
  - An Unknown self call contributes `None`, the join identity. Before,
    this applied only when the call had no stamp; the producer stamps
    Unknown.
- **Return type by trial.** Assume the sub returns R (Int, then Num,
  then Str), lower the body in a throwaway context, and keep R only if
  the body comes out R. Otherwise it stays Unknown and the call is
  refused.
- **Merges from lowered arms.** An untyped if-merge is decided from
  its arms as lowered. The type is read inside each arm's tail,
  because `_lower_arm_in_tail` drops the arm's cache afterwards.
  - An integer literal arm against a Num arm is that Num: it converts
    exactly, and perl prints 1 and 1.0 alike (`fact`).
- **The return boundary.** The define's return reads the body's repr
  as lowered.
- **Still refused:** mutual recursion.

**Lesson (third time):** `_repr_of` is right only after `lower_value`.
It bit the call arguments, the merge arms and the define's return
here.

**Round-tripped:** 248.
