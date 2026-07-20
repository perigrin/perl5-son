# ABOUTME: Tests for Chalk::IR::Graph and SoN::Render::Text.
# ABOUTME: Verifies graph construction, topological ordering, and text rendering.

use v5.42.0;
use Test2::V0;

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use SoN::IR::Stamp;
use SoN::Render::Text;

my $factory = Chalk::IR::NodeFactory->new();

subtest 'Simple graph: 1 + 2' => sub {
    my $start = $factory->make_cfg('Start');
    my $c1 = $factory->make('Constant', value => 1, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $c2 = $factory->make('Constant', value => 2, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $add = $factory->make('Add', inputs => [$c1, $c2]);
    my $ret = $factory->make_cfg('Return', inputs => [$start, $add]);

    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $nodes = $graph->nodes;
    ok(scalar $nodes->@* >= 4, 'graph has at least 4 nodes');

    # Start should come before Return in topological order
    my %pos;
    for my $i (0 .. $nodes->$#*) {
        $pos{$nodes->[$i]->id} = $i;
    }
    ok($pos{$start->id} < $pos{$ret->id}, 'start before return');
    ok($pos{$c1->id} < $pos{$add->id}, 'c1 before add');
    ok($pos{$c2->id} < $pos{$add->id}, 'c2 before add');
};

subtest 'Text rendering' => sub {
    # Fresh factory to get clean IDs
    my $f = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');
    my $c1 = $f->make('Constant', value => 42, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $c2 = $f->make('Constant', value => 10, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $add = $f->make('Add', inputs => [$c1, $c2]);
    my $ret = $f->make_cfg('Return', inputs => [$start, $add]);

    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);
    my $renderer = SoN::Render::Text->new();
    my $text = $renderer->render($graph);

    like($text, qr/Start/, 'contains Start');
    like($text, qr/Constant\(42\).*\[Int\]/, 'contains Constant(42) with Int stamp');
    like($text, qr/Constant\(10\).*\[Int\]/, 'contains Constant(10) with Int stamp');
    like($text, qr/Add/, 'contains Add');
    like($text, qr/Return/, 'contains Return');
};

subtest 'Text rendering is deterministic' => sub {
    my $f = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');
    my $c = $f->make('Constant', value => 1, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $ret = $f->make_cfg('Return', inputs => [$start, $c]);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $renderer = SoN::Render::Text->new();
    my $text1 = $renderer->render($graph);
    my $text2 = $renderer->render($graph);
    is($text1, $text2, 'same graph renders identically');
};

# NOTE: Chalk::IR::Graph has no node_by_id() (unlike the old
# SoN::IR::Graph) -- its API is members()/start()/returns()/nodes() only.
# The old "Node by id lookup" subtest tested a SoN::IR::Graph-specific
# convenience method with no Chalk::IR::Graph equivalent, so it was
# dropped rather than ported.

subtest 'PadAccess rendering' => sub {
    my $f = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');
    my $pad = $f->make('PadAccess', targ => 3, varname => '$x');
    my $ret = $f->make_cfg('Return', inputs => [$start, $pad]);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $text = SoN::Render::Text->new()->render($graph);
    like($text, qr/PadAccess\(targ: 3, name: '\$x'/, 'PadAccess renders with targ and name');
};

done_testing;
