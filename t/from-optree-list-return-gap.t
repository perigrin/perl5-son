# ABOUTME: A multi-value list return carries every value plus its scalar
# ABOUTME: reading; the perl semantics it must reproduce are pinned here.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# `return (10,20,30)` in a list-context caller (`my @x = f()`) must yield all
# three values. The stack simulator's _exit_record kept only $args->[-1] (the
# last value) -- correct for scalar/comma-operator context, a silent drop for
# list context. The producer cannot know the caller's runtime wantarray, so a
# >1-value list return cannot be soundly represented by a single scalar Return.
# Per GAP-not-miscompile: refuse loudly rather than drop values.
#
# THE CONTAINER WAS NOT THE BUG. An attempt to wrap the N values in an
# ArrayLiteral was reverted after `my $s = f(); print $s` emitted
# Print <- Call(:Array) -- the caller received the container and printed the
# container. Nothing ever read it back out. In pure perl the two legs are
# `my $s = f()` and `my $s = () = f()`; both readings come off ONE container:
#
#     sub lit { return (10,20,30) }        scalar -> 30   () = -> 3
#     sub agg { my @a=(10,20,30); return @a }  scalar -> 3   () = -> 3
#
# THE SCALAR READING IS NOT "THE LAST VALUE". A comma list in scalar context
# yields its LAST OPERAND, read in scalar context, recursively:
#
#     return (10,20,30)               -> 30   last operand is a scalar
#     return @a         (3 elements)  ->  3   last operand is an array: LENGTH
#     my @x=(10,20); return (99, @x)  ->  2   NOT 20
#     my @x=(10,20); return (@x, 99)  -> 99
#     my @x=();      return (1, @x)   ->  0
#     my %h=(a=>1,b=>2); return (1,%h)->  2
#
# So the collapse cannot be elements[len-1] on a flattened container: flattening
# destroys the operand boundary the rule needs.
#
# WHEN THE LAST OPERAND IS A CALL, the caller's context propagates INTO it:
#
#     sub probe { wantarray ? "LIST" : "SCALAR" }
#     sub n7 { return (9, probe()) }
#     scalar(n7())     -> SCALAR
#     join(",", n7())  -> 9,LIST
#
# and that inner callsite carries NO static context -- `perl -MO=Concise,f`
# shows `entersub KS` with an empty context slot, where the two outer callsites
# show `sKS` and `lKS`. The body is compiled once and the context arrives at
# runtime from the caller's frame, which is why wantarray is a function.
#
# Lowering therefore needs the callsite's OPf_WANT propagated inward to
# last-operand position, not merely read at the outermost call. Until that
# exists the refusal is correct.

subtest 'multi-value list return lowers, carrying every value' => sub {
    my $sub = eval 'sub { return (10,20,30) }';
    my $graph;
    ok(lives { $graph = SoN::FromOptree->translate($sub) },
        'a multi-value list return no longer GAPs')
        or diag($@);
    ok(defined $graph, 'got a graph') or return;

    # It must carry all three, not collapse to one. The reverted attempt at
    # this (a418e51) emitted a container nothing read back out; the refusal
    # that replaced it said the callee could not choose a shape. Both are
    # resolved the same way: emit BOTH readings and let the callsite pick.
    my ($ret) = grep { $_->operation eq 'Return' } $graph->nodes->@*;
    ok($ret, 'the graph has a Return') or return;
    my $value = ($ret->inputs // [])->[0];
    ok($value, 'the Return carries a value') or return;
    is(scalar(($value->inputs // [])->@*), 3,
        'all three values are carried, not just the last');
};

subtest 'a single-value return still lowers (not over-GAPped)' => sub {
    my $sub = eval 'sub { return 42 }';
    my $graph;
    ok(lives { $graph = SoN::FromOptree->translate($sub) },
        'a single-value return does not GAP')
        or diag($@);
    ok(defined $graph, 'got a graph');
};

subtest 'a bare `return;` (empty) still lowers' => sub {
    my $sub = eval 'sub { return }';
    my $graph;
    ok(lives { $graph = SoN::FromOptree->translate($sub) },
        'an empty return does not GAP')
        or diag($@);
    ok(defined $graph, 'got a graph');
};

# PIN THE MEASURED SEMANTICS. Two plausible-looking collapse rules have already
# been proposed and refuted by running perl rather than by argument: "wrap it in
# the array container" (no read-back) and "take elements[len-1]" (wrong for a
# trailing aggregate operand). These assertions are against PERL ITSELF, so they
# stay true regardless of what B::SoN does, and a third attempt that gets the
# rule wrong fails here rather than in a corpus case.
subtest 'perl semantics the lowering must reproduce' => sub {
    my %scalar_reading = (
        'sub { return (10,20,30) }'                  => 30,
        'sub { my @a=(10,20,30); return @a }'        => 3,
        'sub { my @x=(10,20); return (99, @x) }'     => 2,
        'sub { my @x=(10,20); return (@x, 99) }'     => 99,
        'sub { my @x=();      return (1, @x) }'      => 0,
        'sub { my @x=(5);     return (1, @x) }'      => 1,
    );
    for my $src ( sort keys %scalar_reading ) {
        my $f = eval $src or die $@;
        my $got = scalar $f->();
        is($got, $scalar_reading{$src},
            "scalar context: $src -> $scalar_reading{$src}");
    }

    # The list reading is always every value, flattened.
    my $g = eval 'sub { my @x=(10,20); return (99, @x) }' or die $@;
    is([$g->()], [99,10,20], 'list context yields all N, flattened');

    # Context propagates INTO a last-operand call -- this is what makes the
    # rule cross call boundaries, and why the inner callsite cannot carry a
    # static context flag.
    my $probe = eval 'sub { wantarray ? "LIST" : "SCALAR" }' or die $@;
    {
        no strict 'refs';
        *{'main::__probe'} = $probe;
    }
    my $h = eval 'sub { return (9, __probe()) }' or die $@;
    is(scalar $h->(), 'SCALAR', 'scalar context reaches the last-operand call');
    is([$h->()], [9,'LIST'],   'list context reaches it too');
};

done_testing;
