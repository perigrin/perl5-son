# ABOUTME: Tests for SoN::IR::NodeFactory hash consing and node creation.
# ABOUTME: Verifies deduplication of data nodes and unique identity of CFG nodes.

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;
use SoN::IR::Node::Start;
use SoN::IR::Node::Region;
use SoN::IR::Stamp;

subtest 'Identical data nodes return same instance' => sub {
    my $factory = SoN::IR::NodeFactory->new();
    my $a = $factory->make('Constant', value => 42, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $b = $factory->make('Constant', value => 42, stamp => SoN::IR::Stamp->new(type => 'Int'));
    is($a, $b, 'same constant returns same object');
    is($a->id, $b->id, 'same id');
};

subtest 'Different data nodes return different instances' => sub {
    my $factory = SoN::IR::NodeFactory->new();
    my $a = $factory->make('Constant', value => 42, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $b = $factory->make('Constant', value => 99, stamp => SoN::IR::Stamp->new(type => 'Int'));
    isnt($a, $b, 'different constants return different objects');
};

subtest 'CFG nodes always create new instances' => sub {
    my $factory = SoN::IR::NodeFactory->new();
    my $a = $factory->make_cfg('Start');
    my $b = $factory->make_cfg('Start');
    isnt($a, $b, 'two Start nodes are different instances');
    ok($a->id ne $b->id, 'different IDs');
};

subtest 'Use-def chains maintained through factory' => sub {
    my $factory = SoN::IR::NodeFactory->new();
    my $c1 = $factory->make('Constant', value => 1, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $c2 = $factory->make('Constant', value => 2, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $add = $factory->make('Add', inputs => [$c1, $c2]);

    is(scalar $c1->consumers->@*, 1, 'c1 has 1 consumer');
    is($c1->consumers->[0], $add, 'c1 consumer is add');
    is(scalar $c2->consumers->@*, 1, 'c2 has 1 consumer');
    is($add->inputs->[0], $c1, 'add left input is c1');
    is($add->inputs->[1], $c2, 'add right input is c2');
};

subtest 'Content hash is deterministic' => sub {
    my $f1 = SoN::IR::NodeFactory->new();
    my $f2 = SoN::IR::NodeFactory->new();

    my $a1 = $f1->make('Constant', value => 42, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $a2 = $f2->make('Constant', value => 42, stamp => SoN::IR::Stamp->new(type => 'Int'));

    # Different factory instances but same content hash
    is($a1->content_hash, $a2->content_hash, 'same content produces same hash');
};

done_testing;
