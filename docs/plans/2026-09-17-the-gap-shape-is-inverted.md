# The GAP shape is inverted

perigrin: perhaps the GAP implementation is the wrong shape -- maybe we need to
let things run further before declaring them GAPs. And: the only thing that
should GAP, from our discussions, is eval of a string read from outside the
system.

Both measured. The census says the shape is not just wrong, it is inverted.

## Every GAP fires during the walk. None fires after inference.

    lib/SoN/FromOptree.pm   82 GAPs      the optree walk
    lib/SoN/Deparse.pm      75 GAPs      a T2 consumer, correctly its own
    lib/B/SoN.pm             0 GAPs      the type-inference post-pass

Not one refusal is raised where the types are known. That is why the glob GAP
refuses `*crackers = \@array` for want of a stamp that B::SoN's own Ref rule
derives one phase later (measured: `Ref in=[EntryDef/Array] stamp=ArrayRef`
outside a glob assignment).

## The corpus census: 11 GAP kinds, and the one that should is absent

    5  assigning to a glob
    3  untranslatable op inside an if/else arm
    3  a bare block with a `continue` block
    2  map body contribution of unknown arity
    1  `write` whose format is not installed on the handle
    1  void-context 'or' arm did not converge
    1  void-context 'and' arm did not converge
    1  loop-carried value loses its stamp
    1  function exit inside a loop body
    1  an element store inside a nested one-armed branch
    1  a loop inside a branch arm

and:

    my $code = <STDIN>; my $r = eval $code;    does NOT gap

## What string eval actually produces

    4 Call    in=[3]  name=readline
    5 Coerce  in=[4]  from_repr=Scalar to_repr=Code
    7 Phi     in=[5,1]

`Coerce(Scalar -> Code)` is standing in for "compile and run arbitrary perl".
There is no node for that -- I checked every class in lib/SoN/IR/Node/. The
graph asserts a string read from STDIN IS code.

It round-trips ONLY because the deparser's target is perl and it can emit
`eval($eff4)` -- lowering perl to perl. For chalk there is no such escape: the
IR says coerce a Scalar to Code, and nothing can lower that. So this is a
T2-RELATIVE refusal, which is the deparser's business and not the producer's --
exactly the layering `caller` already uses.

## The graph already holds the discriminating fact

    eval "1 + 2"          Coerce(Str    -> Code)  source = Constant "1 + 2"
    eval <STDIN>          Coerce(Scalar -> Code)  source = Call readline

A literal eval's source is compile-time known and a consumer could compile it.
An external one cannot be. The graph distinguishes them and nothing acts on it.

## The inversion, stated

    TODAY                          SHOULD BE
    refuse early, on syntax        record truthfully, refuse on a FACT
    refuse before types exist      refuse after inference, where types are known
    producer refuses for T2        each T2 refuses what IT cannot lower
    string eval translates         the one construct with no lowering at all

## Remaining work

1. Move type-dependent GAPs to the post-pass. The glob assign is the worked
   example (docs/plans/2026-09-17-a-glob-assignment-is-a-typed-binding.md): 3
   of its 5 corpus occurrences have a knowable RHS type.
2. Audit the other 10 kinds against "is this a fact or a phase artifact". The
   convergence ones ("did not converge") read like artifacts; the arity ones
   read like facts.
3. Decide what string eval should DO. Options, unmeasured: a node kind for it
   so the fact reaches T2 and each T2 decides; or leave the Coerce and let the
   deparser keep lowering it while chalk refuses. The second needs no new
   vocabulary and is probably right, but chalk has to be asked.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
