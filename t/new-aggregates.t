# ABOUTME: Tests for 3 new Aggregate subclasses: HashRef, ArrayRef, and Interpolate.
# ABOUTME: Verifies isa chain, elements() method, and NodeFactory round-trip for each.

use v5.42.0;
use Test2::V0;

use SoN::IR::Node;
use SoN::IR::Node::Constant;
use SoN::IR::Node::Aggregate;
use SoN::IR::Stamp;

use SoN::IR::Node::HashRef;
use SoN::IR::Node::ArrayRef;
use SoN::IR::Node::Interpolate;

my $stamp = SoN::IR::Stamp->new(type => 'Str');

sub const ($val) {
    SoN::IR::Node::Constant->new(value => $val, stamp => $stamp)
}

# --- HashRef ---

subtest 'HashRef is an Aggregate with 4 inputs' => sub {
    my @kv = map { const($_) } qw(k1 v1 k2 v2);
    my $node = SoN::IR::Node::HashRef->new(inputs => \@kv);

    isa_ok($node, ['SoN::IR::Node::Aggregate'], 'HashRef isa Aggregate');
    isa_ok($node, ['SoN::IR::Node'],            'HashRef isa Node');
    is($node->operation, 'HashRef', 'HashRef->operation eq HashRef');
    is(scalar $node->elements->@*, 4, 'HashRef has 4 elements');

    my $elems = $node->elements;
    for my $i (0 .. $#kv) {
        is($elems->[$i], $kv[$i], "elements[$i] matches input[$i]");
    }
};

subtest 'HashRef content_hash includes operation name and input ids' => sub {
    my @kv   = map { const($_) } qw(a 1 b 2);
    my $node = SoN::IR::Node::HashRef->new(inputs => \@kv);
    my $hash = $node->content_hash;

    like($hash, qr/HashRef/, 'content_hash contains HashRef');
    for my $el (@kv) {
        like($hash, qr/\Q${\$el->id}\E/, 'content_hash contains input id');
    }
};

# --- ArrayRef ---

subtest 'ArrayRef is an Aggregate with 3 inputs' => sub {
    my @elems = map { const($_) } (1, 2, 3);
    my $node  = SoN::IR::Node::ArrayRef->new(inputs => \@elems);

    isa_ok($node, ['SoN::IR::Node::Aggregate'], 'ArrayRef isa Aggregate');
    isa_ok($node, ['SoN::IR::Node'],            'ArrayRef isa Node');
    is($node->operation, 'ArrayRef', 'ArrayRef->operation eq ArrayRef');
    is(scalar $node->elements->@*, 3, 'ArrayRef has 3 elements');

    my $got = $node->elements;
    for my $i (0 .. $#elems) {
        is($got->[$i], $elems[$i], "elements[$i] matches input[$i]");
    }
};

subtest 'ArrayRef content_hash includes operation name and input ids' => sub {
    my @elems = map { const($_) } (10, 20, 30);
    my $node  = SoN::IR::Node::ArrayRef->new(inputs => \@elems);
    my $hash  = $node->content_hash;

    like($hash, qr/ArrayRef/, 'content_hash contains ArrayRef');
    for my $el (@elems) {
        like($hash, qr/\Q${\$el->id}\E/, 'content_hash contains input id');
    }
};

# --- Interpolate ---

subtest 'Interpolate is an Aggregate with 2 inputs' => sub {
    my $lit = const('Hello, ');
    my $var = const('world');
    my $node = SoN::IR::Node::Interpolate->new(inputs => [$lit, $var]);

    isa_ok($node, ['SoN::IR::Node::Aggregate'], 'Interpolate isa Aggregate');
    isa_ok($node, ['SoN::IR::Node'],            'Interpolate isa Node');
    is($node->operation, 'Interpolate', 'Interpolate->operation eq Interpolate');
    is(scalar $node->elements->@*, 2, 'Interpolate has 2 elements');
    is($node->elements->[0], $lit, 'elements[0] is the literal segment');
    is($node->elements->[1], $var, 'elements[1] is the variable segment');
};

subtest 'Interpolate content_hash includes operation name and input ids' => sub {
    my $lit  = const('prefix_');
    my $var  = const('suffix');
    my $node = SoN::IR::Node::Interpolate->new(inputs => [$lit, $var]);
    my $hash = $node->content_hash;

    like($hash, qr/Interpolate/, 'content_hash contains Interpolate');
    like($hash, qr/\Q${\$lit->id}\E/, 'content_hash contains literal id');
    like($hash, qr/\Q${\$var->id}\E/, 'content_hash contains variable id');
};

# --- NodeFactory round-trips ---

subtest 'NodeFactory can create all 3 new aggregate nodes' => sub {
    use SoN::IR::NodeFactory;

    my $factory = SoN::IR::NodeFactory->new;

    my @kv    = map { const($_) } qw(k 1);
    my $hnode = $factory->make('HashRef', inputs => \@kv);
    isa_ok($hnode, ['SoN::IR::Node::Aggregate'],
        "factory->make('HashRef') returns Aggregate");
    is($hnode->operation, 'HashRef', "factory-made HashRef has correct operation");

    my @elems = map { const($_) } (7, 8, 9);
    my $anode = $factory->make('ArrayRef', inputs => \@elems);
    isa_ok($anode, ['SoN::IR::Node::Aggregate'],
        "factory->make('ArrayRef') returns Aggregate");
    is($anode->operation, 'ArrayRef', "factory-made ArrayRef has correct operation");

    my $lit   = const('foo');
    my $var   = const('bar');
    my $inode = $factory->make('Interpolate', inputs => [$lit, $var]);
    isa_ok($inode, ['SoN::IR::Node::Aggregate'],
        "factory->make('Interpolate') returns Aggregate");
    is($inode->operation, 'Interpolate', "factory-made Interpolate has correct operation");
};

done_testing;
