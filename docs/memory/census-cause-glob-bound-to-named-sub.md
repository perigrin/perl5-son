# Cause: "a reference to a Constant (Code) is not lowered" (2026-11-05)

- Held: pvm 209. `package B; *rr = \&A::rr; sub f { rr($_[0]) }`, and the
  same binding in main.
- B::SoN models it as `EntryWrite binds` of `&B::rr` with
  `Ref(Constant code "A::rr")`. The call `B::rr` has no MOP target.
- Built (chalk 17601d3a):
  - `_lower_entry_write` records `_sub_alias{"B::rr"} = "A::rr"`. It does so
    only on the program's own chain (`_arm_proj_of(control_in)` undef, no
    loop stack, not inlining) and over a name no sub already holds.
    Anything else is refused by name.
  - `_lower_call_direct` uses the alias when the call has no target. Calls
    lower in program order, so a call before the binding still finds no
    sub, which matches perl dying. A rebinding wins from then on.
- Result: 209 round-trips. Census 405 -> 406.
