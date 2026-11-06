# T2 slices 6-7: objects and a run-time MOP (2026-11-06)

- perigrin's direction: method calls, inheritance, @ISA writes, SUPER and
  AUTOLOAD are all MOP manipulation. Build the MOP into the program's run
  time; static resolution is only an optimization over it.
- Built (chalk 68724d69); tests t2-slice6-objects.t, t2-slice7-dispatch.t.
  Census unchanged at 412 (the object cases stop on other shapes first).
  - An object: element 0 of its hash's %Array is the blessed class.
  - @t2_stashes: package name -> stash hash. A stash maps a sub name to a
    code slot (tag 7, a wrapper `%Slot (%Array* @_)`), and "@ISA" to an
    array slot (tag 6) of parent names (from use parent: MOP parent_name).
  - A method call builds @_, takes the class (object's or a name's own),
    looks the method up depth first through @ISA; none: a run-time stop.
  - Only subs whose names some method call uses are put in stashes; one of
    them T2 cannot build makes the whole program fall back.
- Lessons:
  - Functions were keyed by name; a method Call carries the bare name, so
    two classes' `hi` shared one function (a wrong answer). Key by sub.
  - In the Builder, `my ($b) = @_` hides sort's $b: sort plain keys.
  - `my (...) = @_` pinned by a following call: the reads after it are
    not in args; mapping only the targets read undef (6 for 14).
  - A check run in the background needs an explicit long timeout (the
    10-minute default killed one mid-suite).
- Next: `our @ISA = (...)` at run time, AUTOLOAD, SUPER::; then the five
  object cases (136, 175, 188, 212, 225) and what they hit next.
