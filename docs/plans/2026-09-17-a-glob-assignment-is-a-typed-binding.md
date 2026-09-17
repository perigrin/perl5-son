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

## What landed, and what it cost

perigrin: technically we are a compiler FRONT END -- perl's parser is upstream,
chalk's backend lowers our IR, and the deparser is a testing consumer.

The phase move is done. `_glob_bind` records the binding during the walk and
`B::SoN::_resolve_glob_slots` fills in the slot after inference, where the Ref
rule has run. Measured across t/base, t/comp and t/cmd:

    glob-assign GAPs   5  ->  2

and both survivors are `base/rs.t`'s `*FH = shift`, in `test_record` and
`test_string` -- case (3), which this doc predicted would stay refused.
`comp/proto.t`, `base/lex.t` and `comp/form_scope.t` now translate.

## NO NEW VOCABULARY FOR THE SLOT, one flag for the EVENT

The slot is a SIGIL, which an EntryDef already carries as part of its identity
-- so a later read of `@crackers` hash-conses to the very node the binding
writes, and a separate `slot` field would have been a second spelling nothing
else reads.

The post-pass REPLACES that EntryDef rather than mutating it: the sigil is in
content_hash AND is the node's id, so setting it in place would file a node
under a hash its content no longer matches. The input-swap `_insert_type_
coercions` already uses is the established shape.

What DID need a new field is `EntryWrite.binds`, and it is about the EVENT, not
the variable: `$g = \@a` stores a reference, `*g = \@a` aliases a name, and both
advance the memory chain over a stash entry. Rendered as a store, a binding is a
WRONG ANSWER -- measured, `*crackers = \@SRC; print "@crackers"` emitted
`@main::crackers = \(@main::SRC);` and printed nothing where perl prints 1 2 3.

## TWO DEFECTS THE CHANGE UNCOVERED, both fixed

1. `\&NAME` WAS A ScalarRef. The gv handler pushes a sub's name as a Str
   Constant, so the Ref rule -- correctly, from what it was handed -- called
   `our $x = \&SRC` a reference to a STRING. `rv2cv` is to code what `rv2gv`
   is to globs, and the optree separates them:

       foo()     gv[IV \&main::foo] -> entersub              no rv2cv
       \&SRC     gv[IV \&main::SRC] -> rv2cv -> srefgen      rv2cv

   restamped Str -> Code under srefgen only (an rv2cv on the CALL path still
   wants a name). The link is threaded through NULLS under rpeep suppression --
   reading one ->next link found `null` and the restamp never fired.

2. `\(@a)` IS NOT `\@a`. The Ref renderer parenthesised unconditionally, and
   for an aggregate that changes the program:

       our @SRC=(1,2,3); *c = \(@SRC);  ->  $c is 3, @c is empty
       our @SRC=(1,2,3); *c = \@SRC;    ->  @c is 1 2 3

   The parens exist for a real reason (`\$x . "y"`), so they are dropped only
   for a bare aggregate read, which no binary operator can be.

## Remaining work

1. A Ref over an `our` ARRAY drops the array's initialiser. Measured on a CLEAN
   tree with no glob involved:

       our @SRC=(1,2,3); my $r=\@SRC; print scalar(@$r);
         perl     3
         emitted  (empty)   -- the ArrayLiteral holding (1,2,3) is not in the graph

   This is pre-existing and independent; it blocks two round-trip cases in
   t/deparse-glob-binding-is-an-alias.t, which are TODO with this evidence.

2. A CALL THROUGH A BOUND NAME is refused by the missing-callee check, which
   cannot see that a binding installs the name. An honest refusal, not a
   miscompile, and TODO in the same file.

3. `base/rs.t` stays refused, as predicted.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
