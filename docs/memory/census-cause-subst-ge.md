# Cause: "s/// whose replacement is computed per match (/ge)" (2026-11-05)

- Held: pvm 111, `s/(\d)/$1*10/ge`.
- B::SoN lifts the replacement into `main::...::__SUBSTREPL__:N`, a graph
  of its own. Its RegexCapture nodes read a RegexMatch node of that graph.
- Built (chalk 57ea6240):
  - JSON.pm's %CODE_GRAPHS now keeps `__SUBSTREPL__` bodies alongside
    `__REGEXCODE__`.
  - `_subst_body_value` accepts a body whose Return comes straight off
    Start, built only from its one RegexMatch, captures, constants, pure ops
    and uc/lc/length.
  - `_lower_regex_subst_g`, per match: a fresh cache, the body's match
    bound to the current match (`_regex_captures`, subj_ptr = the search
    start), the value coerced to Str and appended.
- Still refused: a body reading a variable, and anything the producer
  refuses (`uc($1) x 2` is "has an effect" to B::SoN).
- Result: 111 round-trips. Census 409 -> 410.
