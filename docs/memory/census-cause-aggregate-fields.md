# Census cause: aggregate fields (`field %h`, `field @a`)

**Causes:** "field X in class X has no declared repr" (119, 242, 246) and
"field X value repr=Hash/Array cannot be stored in an i64 payload" (141, 153,
161). Both are one cause: chalk had no aggregate fields.

**Round-tripped so far:** 119, 242 (pin 274); 161 (pin 275).
- 141 next hits `Coerce[HashRef->Str]` (`%h = ()` in a method's value).
- 153 next hits a Subscript over a List (a nested default).
- 246 next hits a method returning `values %h` (TOP).

## What was done

- **Analysis:** an aggregate field is typed HashRef or ArrayRef (the object's
  reference to its own aggregate). This applies when the wire gives no type, or
  gives Hash/Array from the default. Its FieldAccess reads are stamped the same
  way, over the producer's Hash, Array or Scalar stamp.
- **`new`:** a field with no default starts as a fresh empty hash or array. A
  default stores its pointer, tagged as a reference.
- **Field store of a Scalar:** stored as the whole `%Slot` cell (`$count++`).
- **`push`** accepts an array field.

## Wrong answers found on the way

- **`my $id = $count++` read the field after the increment's store** (1,2 for
  0,1). The producer pins that read on the control chain, with no memory input.
  Neither the main chain nor an arm's walk took it where it stood. Now it is
  lowered and frozen there, in arms too (`_collect_body_recursive`).
- **Two `new`s shared one default aggregate** (5252 for 52u1). The default's
  nodes were served from the lowering cache. They are evicted before each `new`
  lowers them.
- **Pre-existing:** `field $r = {}` shared its hash across objects the same way
  (5151 for 51u0).

## Lessons

- A lowering cache turns "evaluate per construction" into "evaluate once". Any
  node perl re-evaluates per call (a default, an anonymous aggregate) must be
  evicted, or every object shares it.
- A method body's helper (`++` on a Scalar) can need `@exit` after the prologue
  is rendered; the post-class re-emit declares it.
