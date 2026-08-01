# ABOUTME: Tests for abstract base classes BinOp, UnaryOp, and Aggregate.
# ABOUTME: Verifies field accessors and op_str defaults.

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;
use SoN::IR::Node::Constant;
use SoN::IR::Node::BinOp;
use SoN::IR::Node::UnaryOp;
use SoN::IR::Node::Aggregate;
use SoN::IR::Stamp;

my $stamp = SoN::IR::Stamp->new(type => 'Int');

sub const ($val) {
    SoN::IR::Node::Constant->new(id => "const-$val", value => $val, stamp => $stamp)
}

# BinOp/UnaryOp/Aggregate are abstract intermediate classes never
# constructed via SoN::IR::NodeFactory (see the %ABSTRACT_BASE list in
# t/bootstrap/ir-subclass-field-audit.t in the chalk repo), so this helper
# reproduces the factory's _register_consumers wiring by hand for direct
# ->new construction in this file.
sub wire_consumers ($node, @inputs) {
    $_->add_consumer($node) for @inputs;
    return $node;
}

subtest 'BinOp base class' => sub {
    my $left  = const(1);
    my $right = const(2);
    my $node  = SoN::IR::Node::BinOp->new(id => 'binop-1', inputs => [$left, $right]);

    isa_ok($node, ['SoN::IR::Node'], 'BinOp is-a Node');
    is($node->left,  $left,  'left accessor returns first input');
    is($node->right, $right, 'right accessor returns second input');
    like(dies { $node->op_str }, qr/Subclass must implement op_str/,
        'op_str is abstract on the bare base class');
};

# NOTE: BinOp/UnaryOp/Aggregate declare no operation() override (see
# lib/Chalk/IR/Node.pm's abstract operation() and the %ABSTRACT_BASE list
# in t/bootstrap/ir-subclass-field-audit.t in the chalk repo) -- calling
# ->operation on a bare instance of one of these intermediate classes dies
# rather than returning the class-name suffix the old SoN::IR::Node
# hierarchy returned. The "operation name" subtests this file used to have
# for BinOp/UnaryOp/Aggregate tested SoN::IR::Node-specific behavior with
# no SoN::IR::Node equivalent, so they were dropped rather than ported.

subtest 'BinOp use-def chain wiring' => sub {
    my $left  = const(10);
    my $right = const(20);
    my $node  = wire_consumers(
        SoN::IR::Node::BinOp->new(id => 'binop-2', inputs => [$left, $right]),
        $left, $right,
    );

    is(scalar $left->consumers->@*,  1, 'left has 1 consumer');
    is(scalar $right->consumers->@*, 1, 'right has 1 consumer');
    is($left->consumers->[0],  $node, 'left consumer is the BinOp');
    is($right->consumers->[0], $node, 'right consumer is the BinOp');
};

subtest 'UnaryOp base class' => sub {
    my $operand = const(5);
    my $node    = SoN::IR::Node::UnaryOp->new(id => 'unaryop-1', inputs => [$operand]);

    isa_ok($node, ['SoN::IR::Node'], 'UnaryOp is-a Node');
    is($node->operand, $operand, 'operand accessor returns first input');
    like(dies { $node->op_str }, qr/Subclass must implement op_str/,
        'op_str is abstract on the bare base class');
};

subtest 'UnaryOp use-def chain wiring' => sub {
    my $operand = const(7);
    my $node    = wire_consumers(
        SoN::IR::Node::UnaryOp->new(id => 'unaryop-2', inputs => [$operand]),
        $operand,
    );

    is(scalar $operand->consumers->@*, 1, 'operand has 1 consumer');
    is($operand->consumers->[0], $node, 'operand consumer is the UnaryOp');
};

subtest 'Aggregate base class' => sub {
    my ($a, $b, $c) = (const(1), const(2), const(3));
    my $node = SoN::IR::Node::Aggregate->new(id => 'aggregate-1', inputs => [$a, $b, $c]);

    isa_ok($node, ['SoN::IR::Node'], 'Aggregate is-a Node');
    # SoN::IR::Node::Aggregate has no elements() accessor (unlike the old
    # SoN::IR::Node::Aggregate); its members are exactly its inputs.
    my $elems = $node->inputs;
    is(ref $elems, 'ARRAY', 'inputs returns an array ref');
    is(scalar $elems->@*, 3, 'inputs has correct count');
    is($elems->[0], $a, 'first element is correct');
    is($elems->[1], $b, 'second element is correct');
    is($elems->[2], $c, 'third element is correct');
};

subtest 'Aggregate with no inputs' => sub {
    my $node = SoN::IR::Node::Aggregate->new(id => 'aggregate-2');

    my $elems = $node->inputs;
    is(ref $elems, 'ARRAY', 'inputs returns an array ref');
    is(scalar $elems->@*, 0, 'inputs is empty with no inputs');
};

done_testing;
