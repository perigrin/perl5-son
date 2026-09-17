# A glob assignment is a typed binding, not a store

perigrin: perl has an interesting relationship between globs, types and variable
bindings.

Measured, and it is the whole of the construct:

    our @SRC = (1,2,3); our $SRC = "scalar"; sub SRC { "code" }

    *D1 = \@SRC     ->  @D1 = 1 2 3    $D1 = UNDEF      the ARRAY slot alone
    *D2 = \$SRC     ->  $D2 = scalar   @D2 = 0 elems    the SCALAR slot alone
    *D3 = \&SRC     ->  D3() = code                     the CODE slot alone
    *D4 = *SRC      ->  $D4, @D4, D4() all bound        every slot

THE RHS'S TYPE SELECTS THE BINDING. That is dispatch on type, not a store into
a location -- which is why modelling it as `Assign(target, value)` never fit.
The "four slots" are not four locations; they are what one binding means at
four types, and every one of those types is already a lattice member:
ArrayRef, ScalarRef, CodeRef, Glob.

## What the GAP is actually blocked on: PHASE ORDER, not knowledge

The refusal says the aliased slot is a runtime fact. For `*FH = shift` it is.
For the rest of the corpus it is not -- measured at the refusal point:

    comp/proto.t      *foo3      rhs=AnonSub    stamp=CodeRef    <- KNOWN
    base/lex.t        *crackers  rhs=Ref        stamp=Unknown
    base/rs.t         *FH        rhs=Call       stamp=Unknown
    comp/form_scope.t *STDOUT    rhs=Subscript  stamp=Unknown

`proto.t` already carries the answer and is refused anyway.

And `base/lex.t`'s Unknown is an artifact. B::SoN HAS the rule -- "\OPERAND: the
reference kind follows the operand's kind" (lib/B/SoN.pm:1467), which maps
Array -> ArrayRef, Code -> CodeRef, Glob -> GlobRef. Measured on the same
expression outside a glob assignment:

    our @SRC = (1,2,3); my $r = \@SRC;
      ->  Ref in=[EntryDef/Array] stamp=ArrayRef

The rule runs in B::SoN's POST-PASS, after the optree walk. The GAP fires
DURING the walk, before any stamp is derived. So the producer refuses for want
of a fact it computes one phase later.

## What this means for the refusal

It should not be one refusal. Three cases:

1. RHS stamp is a known ref kind (CodeRef/ArrayRef/HashRef/ScalarRef/GlobRef):
   the binding is fully determined. `*foo3 = sub {...}` installs a sub, which
   is an ordinary named-sub definition and needs no new vocabulary.
2. RHS stamp is Glob: every slot is aliased at once. Still not expressible as a
   value store, and this is the honest refusal.
3. RHS stamp is Unknown: genuinely undecidable, and `*FH = shift` is this --
   the same call site aliases a different slot per call (measured earlier:
   f(\@V) binds the array, f(\$V) the scalar).

Only (2) and (3) need to refuse. (1) is a lowering that is missing, not a fact
that is absent.

## Remaining work

1. Move the glob-assign decision to where the RHS stamp is known, or run the
   Ref rule earlier. This is the blocking step and it is phase plumbing, not
   analysis.
2. Then lower case (1): a CodeRef RHS is a sub definition under a new name.
   comp/proto.t is the corpus case and it is one node.
3. Leave (2) and (3) refused, with the message split so it says WHICH it is --
   "aliases every slot" and "the aliased slot is not known until runtime" are
   different facts and the current text conflates them.

## What does not change

base/rs.t stays refused: its `*FH = shift` is case (3). The measurement that
one call site aliases different slots on different calls still stands, and no
phase reordering touches it.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
