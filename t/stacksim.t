# ABOUTME: Tests for SoN::FromOptree::StackSim virtual stack state machine.
# ABOUTME: Verifies stack ops, scope, snapshot, and merge with Phi creation.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree::StackSim;
use Chalk::IR::NodeFactory;
use SoN::IR::Stamp;

my $factory = Chalk::IR::NodeFactory->new();
my $int_stamp = SoN::IR::Stamp->new(type => 'Int');

subtest 'Stack push/pop' => sub {
    my $start = $factory->make_cfg('Start');
    my $sim = SoN::FromOptree::StackSim->new(control => $start);
    my $c = $factory->make('Constant', value => 42, stamp => $int_stamp);

    $sim->push_node($c);
    is($sim->stack_depth, 1, 'depth is 1 after push');
    my $popped = $sim->pop_node;
    is($popped, $c, 'popped same node');
    is($sim->stack_depth, 0, 'depth is 0 after pop');
};

subtest 'Mark stack' => sub {
    my $start = $factory->make_cfg('Start');
    my $sim = SoN::FromOptree::StackSim->new(control => $start);
    my $a = $factory->make('Constant', value => 1, stamp => $int_stamp);
    my $b = $factory->make('Constant', value => 2, stamp => $int_stamp);
    my $c = $factory->make('Constant', value => 3, stamp => $int_stamp);

    $sim->push_mark;
    $sim->push_node($a);
    $sim->push_node($b);
    $sim->push_node($c);

    my $args = $sim->pop_to_mark;
    is(scalar $args->@*, 3, 'popped 3 args to mark');
    is($args->[0], $a, 'first arg correct');
    is($args->[2], $c, 'last arg correct');
    is($sim->stack_depth, 0, 'stack empty after pop_to_mark');
};

subtest 'Scope define/lookup' => sub {
    my $start = $factory->make_cfg('Start');
    my $sim = SoN::FromOptree::StackSim->new(control => $start);
    my $c = $factory->make('Constant', value => 42, stamp => $int_stamp);

    $sim->define(3, $c);
    is($sim->lookup(3), $c, 'lookup returns defined node');
    is($sim->lookup(99), undef, 'lookup returns undef for undefined');
};

subtest 'Snapshot creates independent copy' => sub {
    my $start = $factory->make_cfg('Start');
    my $sim = SoN::FromOptree::StackSim->new(control => $start);
    my $c1 = $factory->make('Constant', value => 1, stamp => $int_stamp);
    my $c2 = $factory->make('Constant', value => 2, stamp => $int_stamp);

    $sim->define(1, $c1);
    $sim->push_node($c1);

    my $copy = $sim->snapshot;

    # Modify original
    $sim->define(1, $c2);
    $sim->push_node($c2);

    # Copy should be unchanged
    is($copy->lookup(1), $c1, 'copy scope unchanged');
    is($copy->stack_depth, 1, 'copy stack depth unchanged');
};

subtest 'Snapshot preserves mark positions below leftover values' => sub {
    # A mark can sit BELOW leftover stack values: the arm pushes some values,
    # then opens a mark, then pushes the args for a mark-consuming op. When such
    # a state is snapshotted, the copy must resolve pop_to_mark to the SAME
    # position as the original -- not collapse the mark to the final depth.
    my $start = $factory->make_cfg('Start');
    my $sim = SoN::FromOptree::StackSim->new(control => $start);
    my ($a, $b, $c, $d) =
        map { $factory->make('Constant', value => $_, stamp => $int_stamp) } 1 .. 4;

    $sim->push_node($a);   # leftover pos 0
    $sim->push_node($b);   # leftover pos 1
    $sim->push_mark;       # mark at position 2
    $sim->push_node($c);   # arg pos 2
    $sim->push_node($d);   # arg pos 3

    my $copy = $sim->snapshot;
    is($copy->stack_depth, 4, 'copy stack depth matches');
    is($copy->has_mark, 1, 'copy has the mark');

    my $args = $copy->pop_to_mark;
    is(scalar $args->@*, 2, 'pop_to_mark returns the 2 args above the mark');
    is($args->[0], $c, 'first arg is C');
    is($args->[1], $d, 'second arg is D');
    is($copy->stack_depth, 2, 'the 2 leftover values remain below the mark');
};

subtest 'Merge creates Region and Phi' => sub {
    my $start = $factory->make_cfg('Start');
    my $sim_a = SoN::FromOptree::StackSim->new(control => $start);
    my $sim_b = $sim_a->snapshot;

    my $ca = $factory->make('Constant', value => 10, stamp => $int_stamp);
    my $cb = $factory->make('Constant', value => 20, stamp => $int_stamp);

    $sim_a->define(1, $ca);
    $sim_b->define(1, $cb);

    my $region = $sim_a->merge($sim_b, $factory);

    isa_ok($region, 'Chalk::IR::Node::Region');
    my $merged = $sim_a->lookup(1);
    isa_ok($merged, 'Chalk::IR::Node::Phi');
    is(scalar $merged->inputs->@*, 2, 'phi has 2 inputs');
};

done_testing;
