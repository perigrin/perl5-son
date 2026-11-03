# Plan: recursive closures as real functions (2026-11-03)

perigrin chose "Real closures, now" for census cases 134 and 135
(`my $w; $w = sub { ... $w->(...) ... }`). Inlining a closure that calls
itself never stops, so it needs a define.

## Done
- B::SoN 013da8c: a capture read in an arm or loop body goes through its cell
  (it was a PadAccess for a slot the closure doesn't own). Scouts don't see
  cells.
- chalk 09d7158e: an inlined closure writes its captures through the
  variable's location; a cell read is cached (one load); a frame's own
  MakeCell is not a capture.

## Step 3 (next): lambda-lift a recursive closure
- Define: `define internal RET @anon_<name>(%Slot* %cell0..N, args...)`.
  Cells are passed by pointer, so no heap environment is needed while the
  callee is static.
- In the body, bind each CellParam to `%cellI` (the 'cell:'.refaddr key
  _cell_storage already reads).
- Arguments and return: reuse the named-sub path (_args_from_reads,
  _settle_recursive_return, _sub_param_decl).
- Call site: an indirect Call whose code is CellRead(cell), where the cell's
  only write is one AnonSub with a define. From the maker frame, pass the
  variables' locations (_cell_storage of each MakeCell). Inside the body,
  pass %cellI on.
- Still refused: a code value that escapes (returned or stored elsewhere).
  That needs a runtime code value {fnptr, env}. It's a later step and T2's
  job.
