# ABOUTME: Tests SoN::FromOptree translates ref($x) (the type-reading builtin) to a Ref node.
# ABOUTME: ref($x) -> Ref(operand) (backend yields the type/class name Str), distinct from \x (refgen).

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Per corpus/mdtest/classes.md class-simple: ref($e) is a Ref node over its
# operand (the backend's _lower_ref_of_object yields the class name Str for an
# Object), NOT a generic builtin Call (which the backend cannot lower). The
# `ref` opcode is distinct from `refgen`/`srefgen` (the \ operator).

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub node_of ($g, $want_op) {
    my ($node) = grep { $_->operation eq $want_op } $g->nodes->@*;
    return $node;
}

subtest 'ref($x) is a Ref node, not a builtin Call (class-simple)' => sub {
    my $g = graph_of('sub { my $r = [1, 2, 3]; ref($r) }');
    my $ref = node_of($g, 'Ref');
    ok(defined $ref, 'has a Ref node');
    my $call = node_of($g, 'Call');
    ok(!defined $call || ($call->name // '') ne 'ref',
        'no builtin Call(ref) node');
};

subtest 'the \\ operator (refgen) is still a Ref (unchanged)' => sub {
    # refgen/srefgen already map to Ref; confirm the `ref` change did not
    # disturb the \-operator path.
    my $g = graph_of('sub { my $x = 5; \\$x }');
    ok(defined node_of($g, 'Ref'), '\\$x is a Ref node');
};

done_testing();
