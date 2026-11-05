# Cause: "a list with a List in it is not lowered" (pvm 225), partial (2026-11-05)

- pvm 225 is still refused.
- Fixed (chalk 70247c1e): a TernaryExpr typed List inside a list literal
  (`ref $x ? @$x : ($x)`) now branches. Each arm builds its elements with
  `_emit_flattened_array_of` and appends them with chalk_array_append_all.
- Next: a recursive method (`$self->f($el)` inside f). Recursive subs get
  a define, but its ABI takes only Int/Num/Str/Boolean parameters
  (`_call_sub_define`). A method needs Object/HashRef parameters, plus a
  recursion check keyed by the qualified name (rc1.pl). That is a larger
  job, not done.
