# ABOUTME: Tests for SoN::IR::Node::Unwind CFG node creation and properties.
# ABOUTME: Verifies CFG uniqueness, operation name, inheritance, and use-def chains.

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;
use SoN::IR::Node::Start;

subtest 'Unwind is a SoN::IR::Node' => sub {
    my $factory = SoN::IR::NodeFactory->new();
    my $start   = $factory->make_cfg('Start');
    my $unwind  = $factory->make_cfg('Unwind', inputs => [$start]);
    isa_ok($unwind, 'SoN::IR::Node');
};

subtest 'operation() returns Unwind' => sub {
    my $factory = SoN::IR::NodeFactory->new();
    my $start   = $factory->make_cfg('Start');
    my $unwind  = $factory->make_cfg('Unwind', inputs => [$start]);
    is($unwind->operation, 'Unwind', 'operation is Unwind');
};

subtest 'Two Unwind nodes with same inputs get different IDs (CFG uniqueness)' => sub {
    my $factory = SoN::IR::NodeFactory->new();
    my $start   = $factory->make_cfg('Start');
    my $u1      = $factory->make_cfg('Unwind', inputs => [$start]);
    my $u2      = $factory->make_cfg('Unwind', inputs => [$start]);
    isnt($u1, $u2, 'two Unwind nodes are different instances');
    ok($u1->id ne $u2->id, 'different IDs');
};

subtest 'Use-def chains: start node has Unwind as consumer' => sub {
    my $factory = SoN::IR::NodeFactory->new();
    my $start   = $factory->make_cfg('Start');
    my $unwind  = $factory->make_cfg('Unwind', inputs => [$start]);
    is(scalar $start->consumers->@*, 1, 'start has 1 consumer');
    is($start->consumers->[0], $unwind, 'start consumer is unwind node');
};

done_testing;
