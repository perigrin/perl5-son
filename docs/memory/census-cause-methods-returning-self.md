---
name: census-cause-methods-returning-self
description: 430/430 goal, lattice TOP (4: 067 243 247 331) -- a class method returning $self chains (Analysis types the call Object, the method fn returns %self); found an older invalid-IR bug on the way (a package method's returned blessed $self read as a %Slot); 243 round-trips
metadata:
  type: project
---

**Cause:** "'Unknown' is the lattice TOP" (067 243 247 331).

**243/247 shape:** `Log->new->add("a")->add("b")`: `return $self` is a
PadAccess B::SoN leaves Unknown, so the call was Unknown and the chained
call's invocant had no type. Analysis `_type_calls_returning_self`: a
method Call whose CLASS method (Chalk::MOP::Method, not a package sub)
returns `$self` on every Return is stamped Object, and the method's
return_type narrows to Object; LLVM.pm's method emitter returns `%self`
for that body. 243 round-trips; 247 next hits a list assignment to a
field; 067 is `\&Other::helper` called as `$r->()`; 331 is `time()`.

**Older bug found probing the package-sub variant (invalid IR):** a
package method `sub add { my ($self, $x) = @_; ...; $self }` called as
`$p->add(3)->n` -- the inlined call, stamped Unknown, kept the callee's
HashRef value but no type, and the next call read the bare pointer as a
%Slot. The inline step now adopts a reference reading too, and boxes a
reference read where the call is a Scalar.

**Known risk (not hit by any probe):** that adoption is a `set_stamp` on
the call node. A call node inside a sub inlined twice with different
argument kinds would keep the first's type -- the stale-stamp bug fixed
earlier for And/Or. Probes for it are refused (ArgsSource) before they
reach it; if they stop being refused, move this to the `repr:` cache.
