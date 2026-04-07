# ABOUTME: Tests for 9 new BinOp subclasses: Repeat, Match, NotMatch, DefinedOr,
# ABOUTME: Xor, Range, Yada, IsaOp (simple), and CompoundAssign (with $op field).

use v5.42.0;
use Test2::V0;

use SoN::IR::Node;
use SoN::IR::Node::Constant;
use SoN::IR::Node::BinOp;
use SoN::IR::Stamp;

use SoN::IR::Node::Repeat;
use SoN::IR::Node::Match;
use SoN::IR::Node::NotMatch;
use SoN::IR::Node::DefinedOr;
use SoN::IR::Node::Xor;
use SoN::IR::Node::Range;
use SoN::IR::Node::Yada;
use SoN::IR::Node::IsaOp;
use SoN::IR::Node::CompoundAssign;

my $stamp = SoN::IR::Stamp->new(type => 'Int');

sub const ($val) {
    SoN::IR::Node::Constant->new(value => $val, stamp => $stamp)
}

# --- Simple BinOp subclasses ---

my @simple_cases = (
    [ 'Repeat',     'SoN::IR::Node::Repeat',     'x'   ],
    [ 'Match',      'SoN::IR::Node::Match',      '=~'  ],
    [ 'NotMatch',   'SoN::IR::Node::NotMatch',   '!~'  ],
    [ 'DefinedOr',  'SoN::IR::Node::DefinedOr',  '//'  ],
    [ 'Xor',        'SoN::IR::Node::Xor',        'xor' ],
    [ 'Range',      'SoN::IR::Node::Range',      '..'  ],
    [ 'Yada',       'SoN::IR::Node::Yada',       '...' ],
    [ 'IsaOp',      'SoN::IR::Node::IsaOp',      'isa' ],
);

for my $case (@simple_cases) {
    my ($name, $class, $op) = $case->@*;
    subtest "$name is a BinOp" => sub {
        my $left  = const(1);
        my $right = const(2);
        my $node  = $class->new(inputs => [$left, $right]);

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
        my ($name, $class) = $case->@*;
        my $node = $class->new(inputs => [$left, $right]);
        my $hash = $node->content_hash;
        like($hash, qr/\Q$name\E/, "$name content_hash contains operation name");
        like($hash, qr/\Q${\$left->id}\E/, "$name content_hash contains left id");
        like($hash, qr/\Q${\$right->id}\E/, "$name content_hash contains right id");
    }
};

# --- CompoundAssign ---

subtest 'CompoundAssign is a BinOp with op field' => sub {
    my $left  = const(1);
    my $right = const(2);
    my $node  = SoN::IR::Node::CompoundAssign->new(
        inputs => [$left, $right],
        op     => '+=',
    );

    isa_ok($node, ['SoN::IR::Node::BinOp'], 'CompoundAssign isa BinOp');
    isa_ok($node, ['SoN::IR::Node'],        'CompoundAssign isa Node');
    is($node->left,      $left,              'CompoundAssign->left returns first input');
    is($node->right,     $right,             'CompoundAssign->right returns second input');
    is($node->op_str,    '=',               'CompoundAssign->op_str eq \'=\'');
    is($node->operation, 'CompoundAssign',   'CompoundAssign->operation eq CompoundAssign');
    is($node->op,        '+=',              'CompoundAssign->op returns the operator');
};

subtest 'CompoundAssign content_hash includes op field and input ids' => sub {
    my $left  = const(1);
    my $right = const(2);

    my $plus_eq = SoN::IR::Node::CompoundAssign->new(
        inputs => [$left, $right], op => '+='
    );
    my $minus_eq = SoN::IR::Node::CompoundAssign->new(
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
    my $left  = const(5);
    my $right = const(3);

    my $n1 = SoN::IR::Node::CompoundAssign->new(inputs => [$left, $right], op => '+=');
    my $n2 = SoN::IR::Node::CompoundAssign->new(inputs => [$left, $right], op => '+=');
    my $n3 = SoN::IR::Node::CompoundAssign->new(inputs => [$left, $right], op => '-=');

    is($n1->content_hash, $n2->content_hash, 'same op and inputs share content hash');
    isnt($n1->content_hash, $n3->content_hash, 'different op gives different content hash');
};

# --- NodeFactory registration ---

subtest 'NodeFactory can create all 9 new nodes' => sub {
    use SoN::IR::NodeFactory;

    my $factory = SoN::IR::NodeFactory->new;
    my $left    = const(1);
    my $right   = const(2);

    for my $name (qw(Repeat Match NotMatch DefinedOr Xor Range Yada IsaOp)) {
        my $node = $factory->make($name, inputs => [$left, $right]);
        isa_ok($node, ['SoN::IR::Node::BinOp'], "factory->make('$name') returns BinOp");
    }

    my $ca = $factory->make('CompoundAssign', inputs => [$left, $right], op => '*=');
    isa_ok($ca, ['SoN::IR::Node::BinOp'], "factory->make('CompoundAssign') returns BinOp");
    is($ca->op, '*=', "factory-made CompoundAssign has correct op");
};

done_testing;
