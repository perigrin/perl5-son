# ABOUTME: Tests for abstract base classes BinOp, UnaryOp, and Aggregate.
# ABOUTME: Verifies field accessors, op_str defaults, and elements method.

use v5.42.0;
use Test2::V0;

use SoN::IR::Node;
use SoN::IR::Node::Constant;
use SoN::IR::Node::BinOp;
use SoN::IR::Node::UnaryOp;
use SoN::IR::Node::Aggregate;
use SoN::IR::Stamp;

my $stamp = SoN::IR::Stamp->new(type => 'Int');

sub const ($val) {
    SoN::IR::Node::Constant->new(value => $val, stamp => $stamp)
}

subtest 'BinOp base class' => sub {
    my $left  = const(1);
    my $right = const(2);
    my $node  = SoN::IR::Node::BinOp->new(inputs => [$left, $right]);

    isa_ok($node, ['SoN::IR::Node'], 'BinOp is-a Node');
    is($node->left,  $left,  'left accessor returns first input');
    is($node->right, $right, 'right accessor returns second input');
    is($node->op_str, '', 'op_str returns empty string by default');
};

subtest 'BinOp operation name' => sub {
    my $left  = const(1);
    my $right = const(2);
    my $node  = SoN::IR::Node::BinOp->new(inputs => [$left, $right]);

    is($node->operation, 'BinOp', 'operation returns class name suffix');
};

subtest 'BinOp use-def chain wiring' => sub {
    my $left  = const(10);
    my $right = const(20);
    my $node  = SoN::IR::Node::BinOp->new(inputs => [$left, $right]);

    is(scalar $left->consumers->@*,  1, 'left has 1 consumer');
    is(scalar $right->consumers->@*, 1, 'right has 1 consumer');
    is($left->consumers->[0],  $node, 'left consumer is the BinOp');
    is($right->consumers->[0], $node, 'right consumer is the BinOp');
};

subtest 'UnaryOp base class' => sub {
    my $operand = const(5);
    my $node    = SoN::IR::Node::UnaryOp->new(inputs => [$operand]);

    isa_ok($node, ['SoN::IR::Node'], 'UnaryOp is-a Node');
    is($node->operand, $operand, 'operand accessor returns first input');
    is($node->op_str, '', 'op_str returns empty string by default');
};

subtest 'UnaryOp operation name' => sub {
    my $operand = const(5);
    my $node    = SoN::IR::Node::UnaryOp->new(inputs => [$operand]);

    is($node->operation, 'UnaryOp', 'operation returns class name suffix');
};

subtest 'UnaryOp use-def chain wiring' => sub {
    my $operand = const(7);
    my $node    = SoN::IR::Node::UnaryOp->new(inputs => [$operand]);

    is(scalar $operand->consumers->@*, 1, 'operand has 1 consumer');
    is($operand->consumers->[0], $node, 'operand consumer is the UnaryOp');
};

subtest 'Aggregate base class' => sub {
    my ($a, $b, $c) = (const(1), const(2), const(3));
    my $node = SoN::IR::Node::Aggregate->new(inputs => [$a, $b, $c]);

    isa_ok($node, ['SoN::IR::Node'], 'Aggregate is-a Node');
    my $elems = $node->elements;
    is(ref $elems, 'ARRAY', 'elements returns an array ref');
    is(scalar $elems->@*, 3, 'elements has correct count');
    is($elems->[0], $a, 'first element is correct');
    is($elems->[1], $b, 'second element is correct');
    is($elems->[2], $c, 'third element is correct');
};

subtest 'Aggregate with no inputs' => sub {
    my $node = SoN::IR::Node::Aggregate->new();

    my $elems = $node->elements;
    is(ref $elems, 'ARRAY', 'elements returns an array ref');
    is(scalar $elems->@*, 0, 'elements is empty with no inputs');
};

subtest 'Aggregate operation name' => sub {
    my $node = SoN::IR::Node::Aggregate->new();
    is($node->operation, 'Aggregate', 'operation returns class name suffix');
};

done_testing;
