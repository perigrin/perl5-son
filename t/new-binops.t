# ABOUTME: Tests for 9 BinOp subclasses: Repeat, Match, NotMatch, DefinedOr,
# ABOUTME: Xor, Range, Yada, IsaOp (simple), and CompoundAssign (with $op field).

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;
use SoN::IR::Stamp;

my $factory = SoN::IR::NodeFactory->new;
my $stamp = SoN::IR::Stamp->new(type => 'Int');

# Nodes are built through the factory, not by direct ->new: SoN::IR::Node
# requires an explicit content-hash id that only the factory assigns
# (SoN::IR::Node auto-generated one; SoN::IR::Node does not).
sub const ($val) {
    $factory->make('Constant', value => $val, stamp => $stamp)
}

# --- Simple BinOp subclasses ---

my @simple_cases = (
    [ 'Repeat',     'x'   ],
    [ 'Match',      '=~'  ],
    [ 'NotMatch',   '!~'  ],
    [ 'DefinedOr',  '//'  ],
    [ 'Xor',        'xor' ],
    [ 'Range',      '..'  ],
    [ 'Yada',       '...' ],
    [ 'IsaOp',      'isa' ],
);

for my $case (@simple_cases) {
    my ($name, $op) = $case->@*;
    subtest "$name is a BinOp" => sub {
        my $left  = const(1);
        my $right = const(2);
        my $node  = $factory->make($name, inputs => [$left, $right]);

        isa_ok($node, ['SoN::IR::Node::BinOp'], "$name isa BinOp");
        isa_ok($node, ['SoN::IR::Node'],        "$name isa Node");
        is($node->left,      $left,  "$name->left returns first input");
        is($node->right,     $right, "$name->right returns second input");
        is($node->op_str,    $op,    "$name->op_str eq '$op'");
        is($node->operation, $name,  "$name->operation eq '$name'");
    };
}

# --- Content hash uses operation name for simple BinOps ---

subtest 'simple BinOp content_hash includes operation name and input ids' => sub {
    my $left  = const(10);
    my $right = const(20);

    for my $case (@simple_cases) {
        my ($name) = $case->@*;
        my $node = $factory->make($name, inputs => [$left, $right]);
        my $hash = $node->content_hash;
        like($hash, qr/\Q$name\E/, "$name content_hash contains operation name");
        like($hash, qr/\Q${\$left->id}\E/, "$name content_hash contains left id");
        like($hash, qr/\Q${\$right->id}\E/, "$name content_hash contains right id");
    }
};

# --- CompoundAssign ---

subtest 'CompoundAssign is a Node with op field' => sub {
    my $left  = const(1);
    my $right = const(2);
    my $node  = $factory->make('CompoundAssign',
        inputs => [$left, $right],
        op     => '+=',
    );

    # SoN::IR::Node::CompoundAssign is a %STATEMENT_EFFECT_OPS node (a
    # distinct read-modify-write side effect), so it inherits directly from
    # SoN::IR::Node rather than BinOp and has no left/right/op_str
    # accessors -- unlike SoN::IR::Node::CompoundAssign, which modeled it
    # as a pure BinOp. Read the operands via inputs() instead.
    isa_ok($node, ['SoN::IR::Node'],        'CompoundAssign isa Node');
    is($node->inputs->[0], $left,             'CompoundAssign inputs->[0] is first input');
    is($node->inputs->[1], $right,            'CompoundAssign inputs->[1] is second input');
    is($node->operation, 'CompoundAssign',   'CompoundAssign->operation eq CompoundAssign');
    is($node->op,        '+=',              'CompoundAssign->op returns the operator');
};

subtest 'CompoundAssign content_hash includes op field and input ids' => sub {
    my $left  = const(1);
    my $right = const(2);

    my $plus_eq = $factory->make('CompoundAssign',
        inputs => [$left, $right], op => '+='
    );
    my $minus_eq = $factory->make('CompoundAssign',
        inputs => [$left, $right], op => '-='
    );

    my $hash_plus  = $plus_eq->content_hash;
    my $hash_minus = $minus_eq->content_hash;

    like($hash_plus,  qr/CompoundAssign/, 'content_hash contains CompoundAssign');
    like($hash_plus,  qr/op=\+=/,        'content_hash for += contains op=+=');
    like($hash_minus, qr/op=-=/,         'content_hash for -= contains op=-=');
    isnt($hash_plus, $hash_minus, 'different op values produce different content hashes');
    like($hash_plus, qr/\Q${\$left->id}\E/, 'content_hash contains left id');
    like($hash_plus, qr/\Q${\$right->id}\E/, 'content_hash contains right id');
};

subtest 'CompoundAssign hash-consing differentiates by op' => sub {
    # CompoundAssign is a %STATEMENT_EFFECT_OPS entry in SoN::IR::NodeFactory:
    # every occurrence is a distinct side effect, so make() gives it per-call
    # identity rather than hash-consing by content. Compare content_hash
    # (the descriptive hash) rather than id (which now always differs).
    my $left  = const(5);
    my $right = const(3);

    my $n1 = $factory->make('CompoundAssign', inputs => [$left, $right], op => '+=');
    my $n2 = $factory->make('CompoundAssign', inputs => [$left, $right], op => '+=');
    my $n3 = $factory->make('CompoundAssign', inputs => [$left, $right], op => '-=');

    is($n1->content_hash, $n2->content_hash, 'same op and inputs share content hash');
    isnt($n1->content_hash, $n3->content_hash, 'different op gives different content hash');
};

# --- NodeFactory registration ---

subtest 'NodeFactory can create all 9 nodes' => sub {
    my $left    = const(1);
    my $right   = const(2);

    for my $name (qw(Repeat Match NotMatch DefinedOr Xor Range Yada IsaOp)) {
        my $node = $factory->make($name, inputs => [$left, $right]);
        isa_ok($node, ['SoN::IR::Node::BinOp'], "factory->make('$name') returns BinOp");
    }

    # CompoundAssign is not a BinOp under SoN::IR (see the "isa BinOp"
    # comment above) -- only assert it's a Node with the right op.
    my $ca = $factory->make('CompoundAssign', inputs => [$left, $right], op => '*=');
    isa_ok($ca, ['SoN::IR::Node'], "factory->make('CompoundAssign') returns a Node");
    is($ca->op, '*=', "factory-made CompoundAssign has correct op");
};

done_testing;
