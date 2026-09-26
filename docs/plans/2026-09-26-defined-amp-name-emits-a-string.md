# `defined &NAME` is emitted as `defined("NAME")`

Found while asserting the `undef &foo` fix, on a program with no `undef` in it.

## The measurement

    sub foo {"S"}
    print defined(&foo) ? "yes\n" : "no\n";

    perl  yes
    ours  yes        -- and the emission is

    print join('', (defined("foo") ? "yes\n" : "no\n"));

`defined("foo")` asks whether a STRING is defined, which it always is. The right
answer arrives by accident.

## Why it matters

It is a silent wrong answer wherever the sub does NOT exist:

    sub foo {"S"} undef &foo;
    print defined(&foo) ? "still\n" : "gone\n";

    perl  gone
    ours  still      -- `defined("foo")` is true

So the defect is invisible in the common shape and wrong in exactly the shape
that tests a symbol table -- which is what perl's own t/comp/form_scope.t is
doing when it calls `defined &x` after `undef &x`.

INDEPENDENT OF THE UNDEF WORK. Measured on the program above, which has no
`undef` at all. It would have made the `undef &foo` subtest pass for the wrong
reason, which is why that subtest asserts by CALLING the sub instead.

## What it needs

The `rv2cv` operand of `defined` reaches the deparser as a bare name, and
`defined` renders its input as an expression -- so a Str Constant becomes a
quoted string. It needs the same treatment `undef &NAME` now has: an EntryDef
with sigil `&`, which spells `&main::foo`.

Probably a narrow fix at the `defined` handler, keyed on the operand op being
`rv2cv` rather than on what is on the stack -- the same signal the undef path
uses, for the same reason ([[a-shape-assertion-outlives-the-shape]]: the stack
has already lost which op produced the value).

Not attempted here: it is a separate cause from the undef narrowing, and
bundling it would have made both harder to verify.

Related: [[op-names-are-not-perl-spellings]],
[[a-silent-drop-is-worse-than-a-refusal]]
