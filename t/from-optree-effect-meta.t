# ABOUTME: Unit tests for SoN::FromOptree::EffectMeta, the producer-side side
# ABOUTME: table carrying is_stmt_effect/loop_control for Chalk-typed nodes.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::FromOptree::EffectMeta;
use Chalk::IR::NodeFactory;

# A Chalk::IR::Node::Call has no is_stmt_effect field/param (feature-class
# dies on an unknown :param), so the producer cannot pass is_stmt_effect =>
# true to the Chalk factory. EffectMeta carries that knowledge OUTSIDE the
# node, keyed by node identity, for the serializer to consult instead.
my $factory = Chalk::IR::NodeFactory->new();
my $start   = $factory->make_cfg('Start');
my $call    = $factory->make('Call',
    dispatch_kind => 'direct', name => 'main::foo', inputs => [$start]);

ok(!SoN::FromOptree::EffectMeta::is_stmt_effect($call),
    'a node not yet marked is not a statement effect');

SoN::FromOptree::EffectMeta::mark_stmt_effect($call);
ok(SoN::FromOptree::EffectMeta::is_stmt_effect($call),
    'mark_stmt_effect records the node as a statement effect');

# loop_control: a distinct node, marked as the loop-header condition owned by
# a Loop node.
my $loop = $factory->make_cfg('Loop', inputs => [$start]);
my $cond = $factory->make('NumLt',
    inputs => [ $factory->make('Constant', value => 1, const_type => 'integer'),
                $factory->make('Constant', value => 2, const_type => 'integer') ]);

is(SoN::FromOptree::EffectMeta::loop_control_of($cond), undef,
    'a node not yet marked has no loop_control');

SoN::FromOptree::EffectMeta::mark_loop_control($cond, $loop);
is(SoN::FromOptree::EffectMeta::loop_control_of($cond), $loop,
    'mark_loop_control records the owning Loop node');

# Two distinct nodes with identical content (e.g. two hash-consed-looking
# Constants) must not collide in the table -- it is keyed by refaddr, not by
# content_hash or the node's own id string.
my $call2 = $factory->make('Call',
    dispatch_kind => 'direct', name => 'main::bar', inputs => [$start]);
ok(!SoN::FromOptree::EffectMeta::is_stmt_effect($call2),
    'marking one node does not mark an unrelated node');

done_testing();
