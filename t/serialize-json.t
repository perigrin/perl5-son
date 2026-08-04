# ABOUTME: Tests for SoN::Serialize::JSON — serializes SoN::IR::Graph to JSON.
# ABOUTME: Verifies structure, field extraction, and determinism of to_json.

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;
use SoN::IR::Graph;
use SoN::IR::Stamp;
use SoN::Serialize::JSON qw(to_json);

# from_json/_deserialize_graph were deleted from SoN::Serialize::JSON (the
# real pipeline's only loader is SoN::IR::Serialize::JSON::from_json,
# which already has its own coverage in the chalk repo, e.g.
# t/bootstrap/ir-node-unify-roundtrip.t for the loop-Phi defer-patch this
# file used to test here). The round-trip subtests that only exercised the
# deleted SoN-side deserializer's own defer-patch/reconstruction behavior
# were removed rather than retargeted: retargeting to Chalk's from_json
# would pull the full MOP-replay/repr-inference pipeline in scope, and
# these subtests were never asserting a still-live SoN-side contract.

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
# 2. Determinism
# ====================================================

subtest 'serialize same graph twice produces identical output' => sub {
    my $graph  = make_simple_graph();
    my $json1  = to_json({ 'det::fn' => $graph });
    my $json2  = to_json({ 'det::fn' => $graph });
    is($json1, $json2, 'output is byte-identical across two calls');
};

# ====================================================
# 3. Multiple methods
# ====================================================

subtest 'multiple named methods serialize under distinct keys' => sub {
    my $factory = SoN::IR::NodeFactory->new();

    my $start1 = $factory->make_cfg('Start');
    my $c1     = $factory->make('Constant', value => '10', const_type => 'integer');
    my $ret1   = $factory->make_cfg('Return', inputs => [$start1, $c1]);
    my $g1     = SoN::IR::Graph->new(start => $start1, returns => [$ret1]);

    my $start2 = $factory->make_cfg('Start');
    my $c2     = $factory->make('Constant', value => 'hi', const_type => 'string');
    my $ret2   = $factory->make_cfg('Return', inputs => [$start2, $c2]);
    my $g2     = SoN::IR::Graph->new(start => $start2, returns => [$ret2]);

    my $json = to_json({ 'Alpha::one' => $g1, 'Beta::two' => $g2 });

    require JSON::PP;
    my $data = JSON::PP->new->decode($json);
    ok(exists $data->{methods}{'Alpha::one'}, 'Alpha::one present');
    ok(exists $data->{methods}{'Beta::two'},  'Beta::two present');

    my ($c1_node) = grep { $_->{op} eq 'Constant' }
        $data->{methods}{'Alpha::one'}{nodes}->@*;
    my ($c2_node) = grep { $_->{op} eq 'Constant' }
        $data->{methods}{'Beta::two'}{nodes}->@*;

    is($c1_node->{fields}{value}, '10', 'Alpha::one constant value serialized');
    is($c2_node->{fields}{value}, 'hi', 'Beta::two constant value serialized');
};

# ====================================================
# 4. Unwind's arrayref input (exception args)
# ====================================================

# An Unwind's inputs[0] is the exception-args ARRAYREF, not a bare node (see
# SoN::IR::Node::Unwind's ABOUTME). The topo-order DFS must still treat the
# arrayref's elements as producer edges -- otherwise a Constant referenced
# only through that arrayref can be emitted AFTER the Unwind that points to
# it, a forward reference the Chalk-side loader rejects outright.
subtest 'Unwind exception-args node is topo-ordered before the Unwind' => sub {
    my $factory = SoN::IR::NodeFactory->new();

    my $start = $factory->make_cfg('Start');
    my $msg   = $factory->make('Constant', value => 'boom', const_type => 'string');
    my $unwind = $factory->make_cfg('Unwind', inputs => [[$msg]]);
    $unwind->set_control_in($start);

    my $graph = SoN::IR::Graph->new(start => $start, returns => [$unwind]);
    my $json  = to_json({ 'Gamma::three' => $graph });

    require JSON::PP;
    my $data   = JSON::PP->new->decode($json);
    my $method = $data->{methods}{'Gamma::three'};

    my ($unwind_id) = grep { $method->{nodes}[$_]{op} eq 'Unwind' }
        0 .. $#{ $method->{nodes} };
    my ($msg_id) = grep { $method->{nodes}[$_]{op} eq 'Constant' }
        0 .. $#{ $method->{nodes} };

    ok(defined $unwind_id, 'Unwind node present');
    ok(defined $msg_id,    'exception-arg Constant node present');
    ok($msg_id < $unwind_id,
        "args Constant (index $msg_id) precedes Unwind (index $unwind_id)");

    is($method->{nodes}[$unwind_id]{inputs}, [$msg_id],
        "Unwind's inputs[0] is the resolved index of the args Constant");
};

done_testing;
