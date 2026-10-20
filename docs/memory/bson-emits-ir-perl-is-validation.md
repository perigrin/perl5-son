---
name: bson-emits-ir-perl-is-validation
description: "B::SoN's product is the IR; the Perl renderer exists only to validate the IR by running it and comparing with perl"
metadata:
  node_type: memory
  type: feedback
  originSessionId: c7427872-965a-4f72-9cbb-d235a4680e53
  modified: 2026-10-09T20:09:12.935Z
---

B::SoN's job is to emit IR. Lowering that IR back to Perl (SoN::Deparse) and
comparing the program's behaviour with the original is our VALIDATION that
the IR is right -- not a product in its own right.

**Why:** perigrin corrected me (2026-10-09) when I said "B::SoN's job is to
emit Perl that behaves like the original". I had spent days making the
rendered TEXT match the source's shape (conditional rebinds as statements,
class bodies in their blocks, `@INC` bare) so that chalk tests reading lib/
as source would pass -- work on the validation layer, not on the IR.

**How to apply:** Judge renderer work by whether it makes the validation
sound (runs the IR's meaning faithfully), not by whether the text resembles
the source. A test that reads the emitted text as INPUT (chalk's grammar on
lib/) does not validate the IR; defer such tests to chalk's own lowering.
A behaviour difference is a real defect in the IR or the renderer; a shape
difference usually is not. See [[read-generated-output-not-tests]].
