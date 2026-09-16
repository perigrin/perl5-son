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
