# ABOUTME: Tests for SoN::IR::Node base class and CFG node subclasses.
# ABOUTME: Verifies node construction, use-def chains, and CFG node identity.

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;
use SoN::IR::Node::Start;
use SoN::IR::Node::Return;
use SoN::IR::Node::Region;
use SoN::IR::Node::If;
use SoN::IR::Node::Proj;
use SoN::IR::Node::Loop;

my $factory = SoN::IR::NodeFactory->new();

subtest 'Node base class fields' => sub {
    my $node = $factory->make_cfg('Start');
    ok(defined $node->id, 'node has an id');
    is(ref $node->inputs, 'ARRAY', 'inputs is an array ref');
    is(ref $node->consumers, 'ARRAY', 'consumers is an array ref');
    is($node->stamp, undef, 'stamp defaults to undef');
};

subtest 'CFG nodes get unique sequential IDs' => sub {
    my $a = $factory->make_cfg('Start');
    my $b = $factory->make_cfg('Return');
    my $c = $factory->make_cfg('Region');
    ok($a->id ne $b->id, 'different nodes get different IDs');
    ok($b->id ne $c->id, 'different nodes get different IDs');
};

subtest 'All 6 CFG node types constructable' => sub {
    my $start  = $factory->make_cfg('Start');
    my $return = $factory->make_cfg('Return', inputs => [$start]);
    my $region = $factory->make_cfg('Region');
    my $if     = $factory->make_cfg('If');
    my $proj   = $factory->make_cfg('Proj', inputs => [$if], index => 0);
    my $loop   = $factory->make_cfg('Loop');

    isa_ok($start,  'SoN::IR::Node');
    isa_ok($return, 'SoN::IR::Node');
    isa_ok($region, 'SoN::IR::Node');
    isa_ok($if,     'SoN::IR::Node');
    isa_ok($proj,   'SoN::IR::Node');
    isa_ok($loop,   'SoN::IR::Node');
};

subtest 'Use-def chains maintained' => sub {
    my $start  = $factory->make_cfg('Start');
    my $return = $factory->make_cfg('Return', inputs => [$start]);

    # Return's inputs should contain start
    is(scalar $return->inputs->@*, 1, 'return has 1 input');
    is($return->inputs->[0], $start, 'return input is start');

    # Start's consumers should contain return
    is(scalar $start->consumers->@*, 1, 'start has 1 consumer');
    is($start->consumers->[0], $return, 'start consumer is return');
};

subtest 'Multiple consumers tracked' => sub {
    my $start   = $factory->make_cfg('Start');
    my $region1 = $factory->make_cfg('Region', inputs => [$start]);
    my $region2 = $factory->make_cfg('Region', inputs => [$start]);

    is(scalar $start->consumers->@*, 2, 'start has 2 consumers');
};

subtest 'Proj carries index' => sub {
    my $if   = $factory->make_cfg('If');
    my $proj = $factory->make_cfg('Proj', inputs => [$if], index => 1);
    is($proj->index, 1, 'proj carries its index');
};

done_testing;
