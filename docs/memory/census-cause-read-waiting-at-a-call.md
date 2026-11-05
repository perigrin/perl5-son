# Cause: "a store through a reference while a read through a reference waits" (2026-11-05)

- Held: pvm 184 and 233.
  - 233: `my $s = $info->{n}; my $e = emit($info, $k eq "a" ? 1 : undef)`,
    where emit stores `$h->{n}`.
  - 184: a foreach alias walk where `g($l, $i++)` stores
    `$_[0][$_[1]]`.
- Why refused: chalk leaves a read through a scalar-held reference waiting
  until its use (`_pending_tag_reads`), so that it does not exit where perl
  never read. A store through a reference refuses
  (`_container_ptr` autoviv) while any such read is unmade.
- Key fact: B::SoN makes every call a memory version
  (`_call_memory_barrier`). A read perl makes after a call is at the call's
  version or a later one, and none of those is registered yet when the call
  is reached. A read still waiting at a direct call is therefore perl's from
  before it.
- Built (chalk 11889bf5): `_make_pending_reads_before` on a direct Call
  makes each waiting read of this frame, unless a ternary arm chooses it.
  It then deletes the read from `_pending_tag_reads`, because the inlined
  callee checks under its own cache, so the read looked unmade there.
- Probe lesson: shrinking 233 took six variants. It needed a loop, a value
  taken from a hash element (so tagged), and a ?: argument together.
- Result: 233 and 184 round-trip. Census 400 -> 402.
