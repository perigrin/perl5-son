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

# The referents below are ANONYMOUS. A reference to a VARIABLE makes it
# address-taken and is refused (see the last subtest), so the Ref-vs-RefType
# distinction is exercised on referents that alias no name. That refusal is
# about the REFERENT, not about Ref, so these still have their teeth.

subtest 'the \\ operator stays a Ref node (not RefType)' => sub {
    my $g = graph_of('sub { \\[1, 2] }');
    ok(defined node_of($g, 'Ref'), '\\[1,2] is a Ref node');
    ok(!defined node_of($g, 'RefType'), 'no RefType node (that is ref())');
};

subtest 'taking a reference to an aggregate is Ref, not RefType (collision teeth)' => sub {
    # \(expr) over an aggregate is the reference CONSTRUCTOR (Ref), NOT ref() --
    # the two must not collapse, or \(obj) would lower to the class name.
    my $g = graph_of('sub { \\{ a => 1 } }');
    ok(defined node_of($g, 'Ref'), '\\{a=>1} is a Ref node');
    ok(!defined node_of($g, 'RefType'), 'reference-taking is not a RefType');
};

subtest 'a reference to a VARIABLE is refused (address-taken)' => sub {
    # Every SSA IR demotes an address-taken variable to memory: LLVM inhibits
    # mem2reg promotion, GCC gives it virtual operands (VDEF/VUSE), Go and
    # Cranelift do not promote `addrtaken` locals.
    #
    # What chalk lacks is the DEMOTION, not a representation: a stored scalar
    # has a static type that maps to an LLVM type, which is its memory form.
    # Absent are the decision of which variables are address-taken, and scalar
    # load/store on the memory chain (which threads aggregate elements today).
    #
    # Read-only use is not safe either: `my $x=5; my $r=\$x; $x=7; $$r` is 7 in
    # perl, while a value binding would have captured 5.
    for my $src ('sub { my $x = 5; \\$x }', 'sub { our $g = 5; \\$g }') {
        my $err = dies { graph_of($src) };
        like($err, qr/address-taken/, "refused: $src");
    }
};

done_testing();
