# ABOUTME: Tests for SoN::Compare structural graph comparison.
# ABOUTME: Verifies diff detection for identical, missing, and different nodes.

use v5.42.0;
use Test2::V0;

use SoN::Compare;
use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use SoN::IR::Stamp;

my $int_stamp = SoN::IR::Stamp->new(type => 'Int');
my $num_stamp = SoN::IR::Stamp->new(type => 'Num');

subtest 'Identical graphs compare as empty diff' => sub {
    my $f = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');
    my $c = $f->make('Constant', value => 42, stamp => $int_stamp);
    my $ret = $f->make_cfg('Return', inputs => [$start, $c]);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $cmp = SoN::Compare->new();
    my $diff = $cmp->diff($graph, $graph);
    ok($diff->is_empty, 'same graph produces empty diff');
};

subtest 'Missing node detected' => sub {
    my $f1 = Chalk::IR::NodeFactory->new();
    my $s1 = $f1->make_cfg('Start');
    my $c1 = $f1->make('Constant', value => 42, stamp => $int_stamp);
    my $c2 = $f1->make('Constant', value => 10, stamp => $int_stamp);
    my $add = $f1->make('Add', inputs => [$c1, $c2]);
    my $r1 = $f1->make_cfg('Return', inputs => [$s1, $add]);
    my $g1 = Chalk::IR::Graph->new(start => $s1, returns => [$r1]);

    my $f2 = Chalk::IR::NodeFactory->new();
    my $s2 = $f2->make_cfg('Start');
    my $c3 = $f2->make('Constant', value => 42, stamp => $int_stamp);
    my $r2 = $f2->make_cfg('Return', inputs => [$s2, $c3]);
    my $g2 = Chalk::IR::Graph->new(start => $s2, returns => [$r2]);

    my $diff = SoN::Compare->new()->diff($g1, $g2);
    ok(!$diff->is_empty, 'different graphs produce non-empty diff');
    like($diff->to_text, qr/Missing|Extra|differs/, 'diff text describes differences');
};

subtest 'Stamp differences reported' => sub {
    my $f1 = Chalk::IR::NodeFactory->new();
    my $s1 = $f1->make_cfg('Start');
    my $c1 = $f1->make('Constant', value => 42, stamp => $int_stamp);
    my $r1 = $f1->make_cfg('Return', inputs => [$s1, $c1]);
    my $g1 = Chalk::IR::Graph->new(start => $s1, returns => [$r1]);

    my $f2 = Chalk::IR::NodeFactory->new();
    my $s2 = $f2->make_cfg('Start');
    my $c2 = $f2->make('Constant', value => 42, stamp => $num_stamp);
    my $r2 = $f2->make_cfg('Return', inputs => [$s2, $c2]);
    my $g2 = Chalk::IR::Graph->new(start => $s2, returns => [$r2]);

    my $diff = SoN::Compare->new()->diff($g1, $g2);
    ok(!$diff->is_empty, 'stamp difference detected');
    like($diff->to_text, qr/Stamp differs/, 'stamp diff in text');
};

subtest 'to_text produces readable output' => sub {
    my $f1 = Chalk::IR::NodeFactory->new();
    my $s1 = $f1->make_cfg('Start');
    my $r1 = $f1->make_cfg('Return', inputs => [$s1]);
    my $g1 = Chalk::IR::Graph->new(start => $s1, returns => [$r1]);

    my $f2 = Chalk::IR::NodeFactory->new();
    my $s2 = $f2->make_cfg('Start');
    my $c2 = $f2->make('Constant', value => 1, stamp => $int_stamp);
    my $r2 = $f2->make_cfg('Return', inputs => [$s2, $c2]);
    my $g2 = Chalk::IR::Graph->new(start => $s2, returns => [$r2]);

    my $diff = SoN::Compare->new()->diff($g1, $g2);
    my $text = $diff->to_text;
    ok(length($text) > 0, 'to_text produces output');
};

done_testing;
