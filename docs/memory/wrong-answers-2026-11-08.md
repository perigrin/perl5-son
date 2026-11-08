---
name: Wrong answers still in the probe sweep (2026-11-08)
description: Goal item 8 -- every probe the full sweep gets wrong, which lowering made it (T2 or the Context.pm fallback), and the cause; the ones fixed today.
type: project
---
The census (412 ROUNDTRIP, DIFFERS 0) is clean; these are the probe sweep's
WRONG lines (the `w299c` baseline), each re-run 2026-11-08 and attributed by
`t2why.pl`. "T2" = T2 took the program; "Context" = T2 refused, the fallback lowered it.

## Not miscompiles
- **ar, ar2, ar3** (T2): `print $r` shows an address; addresses differ run to run.
- **a8, d0** (T2): `print "ok"; die` -- perl's stdout is block-buffered on a
  pipe, so with 2>&1 its die message comes first; T2 writes as it goes. Same
  bytes per stream.

## T2 gets these wrong
| Probe | Program (short) | perl | T2 | Cause |
|---|---|---|---|---|
| a4e3, s1, s2 (review3) | `$a[-3] = 5` past the start | `... subscript -3 at FILE line N.` | message without ` at FILE line N.` | the die names no site |
| d05 | `for my $i (1, 2) { $i = 10 }` | dies: Modification of a read-only value | assigns | a foreach alias of a constant is read-only |
| s2 (ls) | `for my $x ("x" .. "z")` | `xyz` | `x` | a string range in a foreach |
| s7 | `$a[1e20]` | `d` | `u` | a huge float index (perl clamps to IV) |
| g06, g10, g13 | `use warnings` (FATAL too) | warning / die | silent | warnings are not emitted |
| h16, k10 (review4) | `18446744073709551615 + 1`, `2**62 * 2` | NV result | wraps | integer overflow does not go to a double |
| n2, n2b | `s/a(?{ $t = 1 })/x/r` | `1 0` | `0 0` | a code block in a s///r does not run |
| q_interp, y1, y3 | a code block in an interpolated / chosen qr | runs | does not run | code blocks through a qr value |

## Context.pm (fallback) gets these wrong
| Probe | Program (short) | perl | Context | Cause |
|---|---|---|---|---|
| e1, e1b, e1d | `eval q{ die ... }` | `$@` set, prints before | `$@` empty | string eval's die |
| k10 (review3), k10n | `$@ = "old"; eval q{ 1 }` | `[]` | `[old]` | a string eval does not clear `$@` |
| k2 | `package Foo; eval q{ h() }` | Foo::h | nothing | a string eval's package |
| x1, x3 | `sub f { eval q{ ... @_ ... } }` | the args | nothing | `@_` inside a string eval |
| k07 | `9007199254740993 + 0` in a code block | exact | 9.00719925474099e+15 | an integer kept as a double |
| lv1, ne6 | `my %h; for (1,2) { push @{$h{l}}, $_ }`; `for (@{$h{l}}) {} exists $h{l}` | `1 2`; `v` | empty; `n` | a push onto, or a foreach over, an element left undef in a loop (B::SoN does not vivify there; T2 refuses) |

## Fixed today
- `k1`: a sort comparator that dies was lowered by T2 without perl's comparison
  order (it compared other pairs, never died) -- now refused by name.
- `push @{$h{l}}, 4` / `push @{$r->{l}}, 4` printed nothing (Context): B::SoN
  now spells the autovivify (`$h{l} //= []`, stored back), and both lower it.
- `my %h; defined $h{x}{y}` exited 255 (Context): now T2's (a read through
  undef is undef).

**How to apply:** pick these up by cause, largest first (string eval in
Context; code blocks through a qr; integer overflow); each fix starts as a
probe that fails here.
