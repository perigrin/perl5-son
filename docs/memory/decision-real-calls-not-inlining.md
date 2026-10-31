# Decision: real calls are the default; inlining is an optimization (perigrin, 2026-10-31)

perigrin: "inlining is/was a premature optimization that a different
claude session made without really asking".

**State on 2026-10-31.** chalk inlines every direct call. The one
exception is a sub that calls itself: `_recursive_sub_info` /
`_call_sub_define` in Context.pm emit a real LLVM `define` + `call`
(4c4c7e4b). Earlier work, such as "inline direct calls whose callee
prints or stores", extended inlining. It did not replace it.

**Direction.**
- A direct call to a user sub lowers to a real `define` + `call`.
- Inlining is a later optimization: opt-in, and measured.
- Don't extend the inliner further. Grow the define/call path, starting
  from the recursive-sub one.
- This matters for roadmap step 1. `use`/`require` pull in whole
  modules, and inlining a module at every call site doesn't scale.
