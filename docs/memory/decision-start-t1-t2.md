# Decision: start the T1/T2 refactor (perigrin, 2026-11-03)

Census at 386 of 430. The five context cases are done except 092. The
tail is one-offs, and the largest group (8) is refused because values are
untyped (Unknown): the coverage trigger perigrin set (see
roadmap-simple-perl-static-compiler.md, "three triggers").

perigrin chose: "Start T1/T2 (boxed values)".

Shape (from the roadmap): one layer decides each value's representation,
boxed (%Slot) by default, so it always works; the other emits code for
the chosen one. Typed fast paths become optimizations on top of the box.

Fold in: %Slot's `defined` field, which is redundant with tag 0 (Undef).

Process: a plan document first (design, seams in Context.pm, steps), each
step test-first with the census held at >= 386, DIFFERS 0.
