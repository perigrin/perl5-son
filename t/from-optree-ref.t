# ABOUTME: Tests SoN::FromOptree keeps ref($x) and the \ operator as DISTINCT nodes.
# ABOUTME: ref($x) -> RefType (reference -> type-name Str); \x -> Ref (value -> reference).

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# ref() and \ have opposite signatures: ref($x) takes a reference and produces a
# type-name string (RefType); \x takes a value and produces a reference (Ref).
# They must be DISTINCT node types so the backend never lowers one as the other
# (a Ref-of-object and a ref()-of-object are otherwise indistinguishable).

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

subtest 'ref($x) is a RefType node (not Ref, not Call)' => sub {
    my $g = graph_of('sub { my $r = [1, 2, 3]; ref($r) }');
    ok(defined node_of($g, 'RefType'), 'has a RefType node');
    ok(!defined node_of($g, 'Ref'), 'no Ref node (that is the \\ operator)');
    my $call = node_of($g, 'Call');
    ok(!defined $call || ($call->name // '') ne 'ref', 'no builtin Call(ref)');
};

subtest 'the \\ operator stays a Ref node (not RefType)' => sub {
    my $g = graph_of('sub { my $x = 5; \\$x }');
    ok(defined node_of($g, 'Ref'), '\\$x is a Ref node');
    ok(!defined node_of($g, 'RefType'), 'no RefType node (that is ref())');
};

subtest 'taking a reference to an object is Ref, not RefType (collision teeth)' => sub {
    # \(expr) over an object is the reference CONSTRUCTOR (Ref), NOT ref() -- the
    # two must not collapse, or \(obj) would lower to the class name.
    my $g = graph_of('sub { my $r = [1]; \\$r }');
    ok(defined node_of($g, 'Ref'), '\\$r is a Ref node');
    ok(!defined node_of($g, 'RefType'), 'reference-taking is not a RefType');
};

done_testing();
