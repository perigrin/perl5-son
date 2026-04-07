# ABOUTME: Tests for SoN::Serialize::JSON — serialize/deserialize SoN::IR::Graph to/from JSON.
# ABOUTME: Verifies round-trip fidelity, field extraction, determinism, and multi-method support.

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;
use SoN::IR::Graph;
use SoN::IR::Stamp;
use SoN::Serialize::JSON qw(to_json from_json);

# ---- helpers ----

sub make_simple_graph () {
    my $factory = SoN::IR::NodeFactory->new();
    my $start   = $factory->make_cfg('Start');
    my $const   = $factory->make('Constant', value => '42', const_type => 'integer');
    my $ret     = $factory->make_cfg('Return', inputs => [$start, $const]);
    return SoN::IR::Graph->new(start => $start, returns => [$ret]);
}

# ====================================================
# 1. Basic serialization: structure of JSON output
# ====================================================

subtest 'to_json produces expected top-level structure' => sub {
    my $graph = make_simple_graph();
    my $json  = to_json({ 'Foo::bar' => $graph });

    ok(defined $json, 'to_json returns a value');
    like($json, qr/"version"\s*:\s*1/, 'version field is 1');
    like($json, qr/"methods"/, 'methods key present');
    like($json, qr/"Foo::bar"/, 'method name in output');
    like($json, qr/"nodes"/, 'nodes key present');
    like($json, qr/"start"/, 'start key present');
    like($json, qr/"returns"/, 'returns key present');
};

subtest 'to_json emits correct node ops' => sub {
    my $graph = make_simple_graph();
    my $json  = to_json({ 'test::fn' => $graph });

    like($json, qr/"op"\s*:\s*"Start"/,    'Start op present');
    like($json, qr/"op"\s*:\s*"Constant"/, 'Constant op present');
    like($json, qr/"op"\s*:\s*"Return"/,   'Return op present');
};

subtest 'to_json marks cfg nodes with cfg:true' => sub {
    my $graph = make_simple_graph();
    my $json  = to_json({ 'test::fn' => $graph });

    # Decode and inspect
    require JSON::PP;
    my $data = JSON::PP->new->decode($json);
    my $nodes = $data->{methods}{'test::fn'}{nodes};
    my %by_op;
    for my $n ($nodes->@*) {
        push $by_op{$n->{op}}->@*, $n;
    }

    ok($by_op{Start}[0]{cfg},  'Start has cfg:true');
    ok($by_op{Return}[0]{cfg}, 'Return has cfg:true');
    ok(!$by_op{Constant}[0]{cfg}, 'Constant does not have cfg:true');
};

subtest 'to_json emits Constant fields' => sub {
    my $graph = make_simple_graph();
    my $json  = to_json({ 'test::fn' => $graph });

    require JSON::PP;
    my $data  = JSON::PP->new->decode($json);
    my $nodes = $data->{methods}{'test::fn'}{nodes};
    my ($const_node) = grep { $_->{op} eq 'Constant' } $nodes->@*;

    ok(defined $const_node, 'found Constant node');
    is($const_node->{fields}{const_type}, 'integer', 'const_type field present');
    is($const_node->{fields}{value},      '42',      'value field present');
};

subtest 'start and returns use positional IDs' => sub {
    my $graph = make_simple_graph();

    require JSON::PP;
    my $json   = to_json({ 'test::fn' => $graph });
    my $data   = JSON::PP->new->decode($json);
    my $method = $data->{methods}{'test::fn'};

    my $start_id   = $method->{start};
    my $return_ids = $method->{returns};

    ok(defined $start_id,    'start field defined');
    ok(ref $return_ids eq 'ARRAY', 'returns is array');
    ok(scalar $return_ids->@* > 0, 'returns is non-empty');

    # The start node must have op=Start
    my $start_node = $method->{nodes}[$start_id];
    is($start_node->{op}, 'Start', 'start ID points to Start node');

    # Each return ID must have op=Return or op=Unwind
    for my $rid ($return_ids->@*) {
        my $rnode = $method->{nodes}[$rid];
        ok($rnode->{op} eq 'Return' || $rnode->{op} eq 'Unwind',
            "return ID $rid points to Return/Unwind node");
    }
};

# ====================================================
# 2. Round-trip: serialize then deserialize
# ====================================================

subtest 'round-trip preserves node count and ops' => sub {
    my $graph  = make_simple_graph();
    my $json   = to_json({ 'test::rt' => $graph });
    my $graphs = from_json($json);

    ok(exists $graphs->{'test::rt'}, 'method key preserved');
    my $rt_graph = $graphs->{'test::rt'};
    ok($rt_graph isa SoN::IR::Graph, 'returned object is SoN::IR::Graph');

    my $orig_nodes = $graph->nodes;
    my $rt_nodes   = $rt_graph->nodes;

    is(scalar $rt_nodes->@*, scalar $orig_nodes->@*, 'node count matches');

    my %orig_ops = map { $_->operation => 1 } $orig_nodes->@*;
    my %rt_ops   = map { $_->operation => 1 } $rt_nodes->@*;
    is(\%rt_ops, \%orig_ops, 'same set of operations after round-trip');
};

subtest 'round-trip preserves input structure' => sub {
    my $graph    = make_simple_graph();
    my $json     = to_json({ 'test::inputs' => $graph });
    my $graphs   = from_json($json);
    my $rt_graph = $graphs->{'test::inputs'};

    # Find the Return node
    my ($ret) = grep { $_->operation eq 'Return' } $rt_graph->nodes->@*;
    ok(defined $ret, 'Return node found after round-trip');
    is(scalar $ret->inputs->@*, 2, 'Return has 2 inputs (Start + Constant)');

    my ($cfg_input) = grep { $_->operation eq 'Start' } $ret->inputs->@*;
    ok(defined $cfg_input, 'Return input includes Start node');

    my ($data_input) = grep { $_->operation eq 'Constant' } $ret->inputs->@*;
    ok(defined $data_input, 'Return input includes Constant node');
};

# ====================================================
# 3. Field-bearing nodes round-trip
# ====================================================

subtest 'Constant fields survive round-trip' => sub {
    my $factory = SoN::IR::NodeFactory->new();
    my $start   = $factory->make_cfg('Start');
    my $const   = $factory->make('Constant', value => 'hello', const_type => 'string');
    my $ret     = $factory->make_cfg('Return', inputs => [$start, $const]);
    my $graph   = SoN::IR::Graph->new(start => $start, returns => [$ret]);

    my $json     = to_json({ 'test::const' => $graph });
    my $graphs   = from_json($json);
    my $rt_graph = $graphs->{'test::const'};

    my ($rt_const) = grep { $_->operation eq 'Constant' } $rt_graph->nodes->@*;
    ok(defined $rt_const, 'Constant node found');
    is($rt_const->value,      'hello',  'value preserved');
    is($rt_const->const_type, 'string', 'const_type preserved');
};

subtest 'Call fields survive round-trip' => sub {
    my $factory = SoN::IR::NodeFactory->new();
    my $start   = $factory->make_cfg('Start');
    my $arg     = $factory->make('Constant', value => '1', const_type => 'integer');
    my $call    = $factory->make('Call',
        inputs        => [$arg],
        dispatch_kind => 'method',
        name          => 'Foo::bar',
    );
    my $ret = $factory->make_cfg('Return', inputs => [$start, $call]);
    my $graph = SoN::IR::Graph->new(start => $start, returns => [$ret]);

    my $json     = to_json({ 'test::call' => $graph });
    my $graphs   = from_json($json);
    my $rt_graph = $graphs->{'test::call'};

    my ($rt_call) = grep { $_->operation eq 'Call' } $rt_graph->nodes->@*;
    ok(defined $rt_call, 'Call node found');
    is($rt_call->dispatch_kind, 'method',  'dispatch_kind preserved');
    is($rt_call->name,          'Foo::bar', 'name preserved');
};

subtest 'Phi region field survives round-trip' => sub {
    my $factory = SoN::IR::NodeFactory->new();
    my $start   = $factory->make_cfg('Start');
    my $region  = $factory->make_cfg('Region', inputs => [$start]);
    my $v1      = $factory->make('Constant', value => '1', const_type => 'integer');
    my $v2      = $factory->make('Constant', value => '2', const_type => 'integer');
    my $phi     = $factory->make('Phi', region => $region, inputs => [$v1, $v2]);
    my $ret     = $factory->make_cfg('Return', inputs => [$region, $phi]);
    my $graph   = SoN::IR::Graph->new(start => $start, returns => [$ret]);

    my $json     = to_json({ 'test::phi' => $graph });
    my $graphs   = from_json($json);
    my $rt_graph = $graphs->{'test::phi'};

    my ($rt_phi) = grep { $_->operation eq 'Phi' } $rt_graph->nodes->@*;
    ok(defined $rt_phi, 'Phi node found');
    ok(defined $rt_phi->region, 'Phi region field is defined');
    is($rt_phi->region->operation, 'Region', 'Phi region points to a Region node');
    is(scalar $rt_phi->inputs->@*, 2, 'Phi has 2 value inputs');
};

# ====================================================
# 4. Determinism
# ====================================================

subtest 'serialize same graph twice produces identical output' => sub {
    my $graph  = make_simple_graph();
    my $json1  = to_json({ 'det::fn' => $graph });
    my $json2  = to_json({ 'det::fn' => $graph });
    is($json1, $json2, 'output is byte-identical across two calls');
};

# ====================================================
# 5. Multiple methods
# ====================================================

subtest 'multiple named methods serialize and round-trip' => sub {
    my $factory = SoN::IR::NodeFactory->new();

    my $start1 = $factory->make_cfg('Start');
    my $c1     = $factory->make('Constant', value => '10', const_type => 'integer');
    my $ret1   = $factory->make_cfg('Return', inputs => [$start1, $c1]);
    my $g1     = SoN::IR::Graph->new(start => $start1, returns => [$ret1]);

    my $start2 = $factory->make_cfg('Start');
    my $c2     = $factory->make('Constant', value => 'hi', const_type => 'string');
    my $ret2   = $factory->make_cfg('Return', inputs => [$start2, $c2]);
    my $g2     = SoN::IR::Graph->new(start => $start2, returns => [$ret2]);

    my $json   = to_json({ 'Alpha::one' => $g1, 'Beta::two' => $g2 });
    my $graphs = from_json($json);

    ok(exists $graphs->{'Alpha::one'}, 'Alpha::one preserved');
    ok(exists $graphs->{'Beta::two'},  'Beta::two preserved');

    my ($rt_c1) = grep { $_->operation eq 'Constant' } $graphs->{'Alpha::one'}->nodes->@*;
    my ($rt_c2) = grep { $_->operation eq 'Constant' } $graphs->{'Beta::two'}->nodes->@*;

    is($rt_c1->value, '10', 'Alpha::one constant value preserved');
    is($rt_c2->value, 'hi', 'Beta::two constant value preserved');
};

done_testing;
