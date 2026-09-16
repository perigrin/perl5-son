# require as a graph edge makes closure decidable

## The reframing

I claimed condition 4 -- "this file is the whole world for this sub" -- was a
build-time promise only the caller of B::SoN could make.

perigrin: it is not decidable from a single FILE, but it should be decidable
from a single GRAPH, if `require` is functional and loads a second graph into
place. Then closure is not a promise at all: it is the transitive closure over
require edges, and a consumer computes it.

That is right, and it turns an unanswerable question into an ordinary
reachability one.

## What already exists

`require Mod;` reaches the wire as an edge that NAMES ITS TARGET:

    5 Call in=[3,4] dispatch_kind=builtin name=require
    3 Constant const_type=string value=Mod.pm

and the callsite into it is honest about knowing nothing:

    6 Call in=[2] dispatch_kind=direct name=Mod::f   (stamp Unknown)

So the skeleton is there. Three things are missing.

## Gap 1: `use` leaves no trace

    use Mod;   ->   require nodes on the wire: 0

`use X LIST` is `BEGIN { require X; X->import(LIST) }`, and the BEGIN has
already run by the time B::SoN walks the optree. The module is loaded and the
statement is gone. Measured: the only mention of Mod anywhere in that wire is
the callee name `Mod::f`.

Most real dependencies are `use`, so without this the edge set is mostly empty
and closure is never provable.

RECOVERABLE FROM %INC. It is populated when a B backend runs, and its values
are resolved paths that separate our files from core:

    Mod.pm      /.../scratchpad/lib2/Mod.pm
    strict.pm   /.../versions/5.42.0/lib/perl5/5.42.0/strict.pm

## Gap 2: a require whose target is not a constant

    my $m = ...; require $m;   ->   require arg: TernaryExpr

The edge exists but names no file. This is the honest answer and the right
behaviour: such a graph is OPEN, and closure must not be claimed for it.

## Gap 3: nothing records the dependency as a dependency

The wire's top-level keys are `methods`, `source`, `version`. There is no
`requires` section, so a consumer holding one graph cannot tell what else it
needs in order to be whole.

## Proposed shape

1. A `requires` section on the wire: for each dependency, the module name, the
   resolved path, and whether it was resolved statically. Sourced from the
   constant require edges AND from %INC for the BEGIN-time ones, with core and
   CPAN paths marked so a consumer can decide what it is willing to treat as
   external.
2. A `closed` claim is then NOT stored. A consumer that holds a graph and every
   graph its `requires` transitively names knows it has the world; one that
   does not, does not. The graph states facts; the linker draws the conclusion.
3. Only then does the callsite-argument join of
   2026-09-16-a-globs-slot-is-a-type-hint-not-a-layout.md become sound, and it
   becomes sound for NAMED package subs -- which is what base/rs.t needs.

## What this does not fix

An `import` that installs subs at BEGIN time, `*alias = \&Other::f`, and
`AUTOLOAD` all add callers that no require edge names. Each is its own refusal
rather than something closure answers.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc

## Prior art: how other implementations handle precompiled libraries

perigrin's question, and the short answer is that the SoN lineage does not
answer it -- SoN is overwhelmingly a JIT IR, and the AoT members either refuse
the open world or decline cross-module inference.

    HotSpot C2, V8 Turbofan, IonMonkey   JIT. Speculate + guard + DEOPTIMIZE.
                                         Unavailable here: no interpreter to
                                         deopt into.
    Graal Native Image                   AoT, and the closest precedent. Its
                                         answer is closed-world points-to over
                                         the whole image; reflection must be
                                         DECLARED in config. Precision bought
                                         by forbidding openness.
    libFirm                              SoN, genuinely AoT, and does NOT do
                                         cross-TU inference at all.
    MLton                                Whole-program only. Same refusal.

So the applicable technique comes from the ML/Rust module tradition, not SoN:

    OCaml    .cmi is the INTERFACE, .cmx adds cross-module inlining info as an
             advisory body, plus a dependency hash that rebuilds dependents.
    Rust     crate metadata ships MIR for inlinable items, with a per-item
             fingerprint (SVH) that invalidates dependents.

Both separate a STABLE INTERFACE from an OPTIONAL BODY and version the pair.

## We already have most of that shape

A sub record on the wire today, with `graph` removed, is an interface:

    name, params, signature, return_type, uses_args

    their concept                    ours              status
    .cmi / crate interface           sub record        EXISTS
    .cmx / MIR body for inlining     record's `graph`  EXISTS
    dependency list                  `requires`        missing (above)
    interface hash / SVH             --                missing

## Where Perl breaks the analogy

OCaml and Rust hash at BUILD time because a compiled body is immutable. Perl's
is not:

    sub f { 1 }   print f();      # 1
    *f = sub { 2 };  print f();   # 2

A sub's body can be replaced AFTER load, so an interface hash can go stale at
RUNTIME -- something none of the prior art has to survive. Note what the
construct is: glob assignment, the same one refused earlier today.

That makes monkey-patching the thing that keeps Perl's world open. A
Graal-style closed-world claim is simply FALSE for Perl unless a graph that
assigns to a glob is refused, which is what happens today. The existing GAP is
therefore load-bearing for any future closure claim, not merely a missing
feature.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc

## TypeScript's .d.ts is the closer precedent

perigrin's addition, and it fits better than OCaml/Rust for one reason:

    OCaml .cmi / Rust metadata   DERIVED from an implementation the compiler
                                 compiled. The interface is a PROOF.
    TypeScript .d.ts             DESCRIBES code the compiler never saw.
                                 DefinitelyTyped is thousands of signatures
                                 asserted OVER untyped JavaScript. The
                                 interface is an ASSERTION.

CPAN is the second case, not the first. We will never compile most of what a
program calls, so an interface we can only DERIVE is an interface we mostly
cannot have.

## It also dissolves the staleness objection

I argued that `*f = sub { 2 }` replacing a body at runtime makes an interface
fingerprint unsound, because OCaml and Rust hash immutable compiled bodies.

TypeScript has exactly the same hole and does not treat it as one: JavaScript
can reassign any method at runtime, a `.d.ts` cannot see it, and the ecosystem
accepts that a declaration is a CLAIM which can be wrong. The type checker is
sound with respect to the declarations, not with respect to the program.

That is the right posture here too, and it is the T1/T2 split again: T1 records
what it SAW, a declaration records what someone ASSERTS, and the two are
different kinds of fact that must not be conflated on the wire. A declared
signature should be marked as declared, so a consumer can decide how much to
trust it -- exactly as `dispatch_kind=indirect` already marks an honest unknown.

## Where a declaration attaches, today

A sub record already carries `graph name params return_type signature
uses_args` -- interface and body already separable, with no work.

And a callsite into a sub we never compiled is already honest:

    Call Mod::f   stamp=Unknown   dispatch_kind=direct

It knows the NAME and admits it knows nothing else. That Unknown is the slot a
declaration fills. Nothing needs inventing to hold one; what is missing is a
source of declarations and a `declared` marker to keep an assertion
distinguishable from a derivation.

## Revised layering

    B::SoN::TypeLibrary        ambient, language-level -- perl's operators and
                               builtins. The `lib.d.ts` analogue. EXISTS.
    (missing)                  per-module declarations for subs we never
                               compile. The `@types/Foo` analogue.
    sub records                derived interfaces for what we DID compile.
                               EXISTS.

The middle row is the gap, and it is what makes precompiled libraries tractable
without whole-program closure at all: a declared signature answers the callsite
directly, so the require-closure work above becomes an optimization for code we
DO have rather than a precondition for compiling anything.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
