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

subtest 'a reference to a VARIABLE demotes it to memory' => sub {
    # The trigger is the REFERENCE, not escape. `my $x=5; my $r=\$x; $$r=9;
    # print $x` never leaves the compiled region and is still wrong under a
    # value binding, so demotion keys on the reference being taken rather than
    # on any escape judgement. Every SSA IR draws it there: LLVM promotes an
    # alloca only when it is used solely by loads and stores, GCC gives an
    # aliased variable virtual operands, Go does not promote `addrtaken` locals.
    #
    # This used to assert a REFUSAL, and named the two absent pieces: deciding
    # which variables are referenced, and scalar load/store on the memory chain.
    # Both are built now -- _address_taken marks them before the walk, and the
    # sassign PadAccess branch stores through memory exactly as the Subscript
    # and FieldAccess branches already did.
    #
    # WHAT IT PINS INSTEAD is the property the refusal was protecting: the
    # variable survives as a LOCATION rather than folding to a value.
    for my $src ('sub { my $x = 5; \$x }', 'sub { our $g = 5; \$g }') {
        my $g = graph_of($src);
        ok(defined node_of($g, 'Ref'), "\\ builds a Ref: $src");
        ok(scalar(grep { $_->operation =~ /\A(?:PadAccess|EntryDef)\z/ }
                  $g->nodes->@*),
           "... over a surviving location, not a folded value: $src");
    }
};

# THE READ MUST OBSERVE THE WRITE -- the case the old refusal called out as
# unsafe even for read-only use. `my $x=5; my $r=\$x; $x=7; $$r` is 7 in perl,
# while a value binding would have captured 5.
subtest 'a write after the reference is visible to a later read' => sub {
    my $g = graph_of('sub { my $x = 5; my $r = \$x; $x = 7; return $x }');

    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    ok(defined $ret, 'the sub returns') or return;

    my $read = $ret->inputs->[0];
    is($read->operation, 'PadAccess', 'the return value is a location read');
    is($read->inputs->[0]->operation, 'Assign',
       'threaded to the STORE, so it observes the write rather than MemStart');
};

done_testing();
