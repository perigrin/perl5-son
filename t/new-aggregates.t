# ABOUTME: Tests for 3 Aggregate subclasses: HashRef, ArrayRef, and Interpolate.
# ABOUTME: Verifies isa chain, inputs() as element list, and NodeFactory round-trip for each.

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;
use SoN::IR::Stamp;

my $factory = SoN::IR::NodeFactory->new;
my $stamp = SoN::IR::Stamp->new(type => 'Str');

# Nodes are built through the factory, not by direct ->new: SoN::IR::Node
# requires an explicit content-hash id that only the factory assigns
# (SoN::IR::Node auto-generated one; SoN::IR::Node does not).
sub const ($val) {
    $factory->make('Constant', value => $val, stamp => $stamp)
}

# SoN::IR::Node::Aggregate has no elements() accessor (SoN::IR::Node::Aggregate
# had one as an alias for inputs()); the aggregate's members are exactly its
# inputs, so read them directly.

# --- HashRef ---

subtest 'HashLiteral is an Aggregate with 4 inputs' => sub {
    my @kv = map { const($_) } qw(k1 v1 k2 v2);
    my $node = $factory->make('HashLiteral', inputs => \@kv);

    isa_ok($node, ['SoN::IR::Node::Aggregate'], 'HashLiteral isa Aggregate');
    isa_ok($node, ['SoN::IR::Node'],            'HashLiteral isa Node');
    is($node->operation, 'HashLiteral', 'operation is HashLiteral');
    is(scalar $node->inputs->@*, 4, 'HashRef has 4 elements');

    my $elems = $node->inputs;
    for my $i (0 .. $#kv) {
        is($elems->[$i], $kv[$i], "elements[$i] matches input[$i]");
    }
};

subtest 'HashLiteral content_hash includes operation name and input ids' => sub {
    my @kv   = map { const($_) } qw(a 1 b 2);
    my $node = $factory->make('HashLiteral', inputs => \@kv);
    my $hash = $node->content_hash;

    like($hash, qr/HashLiteral/, 'content_hash contains HashLiteral');
    for my $el (@kv) {
        like($hash, qr/\Q${\$el->id}\E/, 'content_hash contains input id');
    }
};

# --- ArrayRef ---

subtest 'ArrayLiteral is an Aggregate with 3 inputs' => sub {
    my @elems = map { const($_) } (1, 2, 3);
    my $node  = $factory->make('ArrayLiteral', inputs => \@elems);

    isa_ok($node, ['SoN::IR::Node::Aggregate'], 'ArrayLiteral isa Aggregate');
    isa_ok($node, ['SoN::IR::Node'],            'ArrayLiteral isa Node');
    is($node->operation, 'ArrayLiteral', 'operation is ArrayLiteral');
    is(scalar $node->inputs->@*, 3, 'ArrayRef has 3 elements');

    my $got = $node->inputs;
    for my $i (0 .. $#elems) {
        is($got->[$i], $elems[$i], "elements[$i] matches input[$i]");
    }
};

subtest 'ArrayLiteral content_hash includes operation name and input ids' => sub {
    my @elems = map { const($_) } (10, 20, 30);
    my $node  = $factory->make('ArrayLiteral', inputs => \@elems);
    my $hash  = $node->content_hash;

    like($hash, qr/ArrayLiteral/, 'content_hash contains ArrayLiteral');
    for my $el (@elems) {
        like($hash, qr/\Q${\$el->id}\E/, 'content_hash contains input id');
    }
};

# --- Interpolate ---

subtest 'Interpolate is an Aggregate with 2 inputs' => sub {
    my $lit = const('Hello, ');
    my $var = const('world');
    my $node = $factory->make('Interpolate', inputs => [$lit, $var]);

    isa_ok($node, ['SoN::IR::Node::Aggregate'], 'Interpolate isa Aggregate');
    isa_ok($node, ['SoN::IR::Node'],            'Interpolate isa Node');
    is($node->operation, 'Interpolate', 'Interpolate->operation eq Interpolate');
    is(scalar $node->inputs->@*, 2, 'Interpolate has 2 elements');
    is($node->inputs->[0], $lit, 'elements[0] is the literal segment');
    is($node->inputs->[1], $var, 'elements[1] is the variable segment');
};

subtest 'Interpolate content_hash includes operation name and input ids' => sub {
    my $lit  = const('prefix_');
    my $var  = const('suffix');
    my $node = $factory->make('Interpolate', inputs => [$lit, $var]);
    my $hash = $node->content_hash;

    like($hash, qr/Interpolate/, 'content_hash contains Interpolate');
    like($hash, qr/\Q${\$lit->id}\E/, 'content_hash contains literal id');
    like($hash, qr/\Q${\$var->id}\E/, 'content_hash contains variable id');
};

# --- NodeFactory round-trips ---

subtest 'NodeFactory can create all 3 aggregate nodes' => sub {
    my @kv    = map { const($_) } qw(k 1);
    my $hnode = $factory->make('HashLiteral', inputs => \@kv);
    isa_ok($hnode, ['SoN::IR::Node::Aggregate'],
        "factory->make('HashLiteral') returns Aggregate");
    is($hnode->operation, 'HashLiteral', "factory-made HashRef has correct operation");

    my @elems = map { const($_) } (7, 8, 9);
    my $anode = $factory->make('ArrayLiteral', inputs => \@elems);
    isa_ok($anode, ['SoN::IR::Node::Aggregate'],
        "factory->make('ArrayLiteral') returns Aggregate");
    is($anode->operation, 'ArrayLiteral', "factory-made ArrayRef has correct operation");

    my $lit   = const('foo');
    my $var   = const('bar');
    my $inode = $factory->make('Interpolate', inputs => [$lit, $var]);
    isa_ok($inode, ['SoN::IR::Node::Aggregate'],
        "factory->make('Interpolate') returns Aggregate");
    is($inode->operation, 'Interpolate', "factory-made Interpolate has correct operation");
};

done_testing;
