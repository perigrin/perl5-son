---
name: op-names-are-not-perl-spellings
description: The producer takes Call.name from the OP, and several perl op names are not the keyword that produced them
metadata:
  type: project
---

`SoN::FromOptree` sets `Call.name` from `$op->name`, and perl's op names do
not all match the keyword. Emitting one verbatim produces a call to a sub
that does not exist:

    prtf                  printf
    schomp schop          chomp chop (scalar forms)
    dofile                do EXPR      -- a named unary OPERATOR
    ftis ftchr ftdir ...  -e -c -d ... -- OPERATORS, not calls
    trans transr          tr/// y///
    pipe_op sselect gsockopt ssockopt open_dir substr_left subst

**The test is perl's own, not a list.** `prototype("CORE::$name")` throws
for a name that is not a keyword:

    die "..." unless eval { my $p = prototype("CORE::$name"); 1 };

A hand-kept list is how these got here: every one was silently emitting an
undefined sub call, and only running the emitted program found it.

**A spelling is not always enough.** `schomp` has an obvious keyword, but
the producer emits its Call with NO store -- the graph does not record the
mutation and the following read still names the pre-chomp value. Spelling
it turns a loud "Undefined subroutine" into a silent wrong answer, so it
stays refused. `trans` has no pattern or replacement on the wire at all.

Related: [[allow-lists-fail-asymmetrically]], [[crashes-mask-gaps]].
