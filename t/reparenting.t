# ABOUTME: Tests that arithmetic/logic/comparison nodes inherit from BinOp/UnaryOp.
# ABOUTME: Verifies ISA relationships, field accessors, and op_str values.

use v5.42.0;
use Test2::V0;

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::UnaryOp;
use SoN::IR::Stamp;

my $factory = Chalk::IR::NodeFactory->new;
my $stamp = SoN::IR::Stamp->new(type => 'Int');

sub const ($val) {
    $factory->make('Constant', value => $val, stamp => $stamp)
}

my @binop_cases = (
    [ 'Add',        '+'   ],
    [ 'Subtract',   '-'   ],
    [ 'Multiply',   '*'   ],
    [ 'Divide',     '/'   ],
    [ 'Modulo',     '%'   ],
    [ 'Power',      '**'  ],
    [ 'Concat',     '.'   ],
    [ 'NumEq',      '=='  ],
    [ 'NumNe',      '!='  ],
    [ 'NumLt',      '<'   ],
    [ 'NumGt',      '>'   ],
    [ 'NumLe',      '<='  ],
    [ 'NumGe',      '>='  ],
    [ 'NumCmp',     '<=>' ],
    [ 'StrEq',      'eq'  ],
    [ 'StrNe',      'ne'  ],
    [ 'StrLt',      'lt'  ],
    [ 'StrGt',      'gt'  ],
    [ 'StrLe',      'le'  ],
    [ 'StrGe',      'ge'  ],
    [ 'StrCmp',     'cmp' ],
    [ 'And',        '&&'  ],
    [ 'Or',         '||'  ],
    [ 'BitAnd',     '&'   ],
    [ 'BitOr',      '|'   ],
    [ 'BitXor',     '^'   ],
    [ 'LeftShift',  '<<'  ],
    [ 'RightShift', '>>'  ],
);

my @unaryop_cases = (
    [ 'Not',        '!'       ],
    [ 'Negate',     '-'       ],
    [ 'Complement', '~'       ],
    [ 'Defined',    'defined' ],
);

for my $case (@binop_cases) {
    my ($name, $op) = $case->@*;
    subtest "$name is a BinOp" => sub {
        my $left  = const(1);
        my $right = const(2);
        my $node  = $factory->make($name, inputs => [$left, $right]);

        isa_ok($node, ['Chalk::IR::Node::BinOp'], "$name isa BinOp");
        isa_ok($node, ['Chalk::IR::Node'],        "$name isa Node");
        is($node->left,   $left,  "$name->left returns first input");
        is($node->right,  $right, "$name->right returns second input");
        is($node->op_str, $op,    "$name->op_str eq '$op'");
    };
}

# Assign is a statement-effect BinOp (per-call identity, never
# hash-consed) so it is exercised separately from the hash-consed
# @binop_cases loop above -- factory->make('Assign', ...) allocates a
# fresh node every call rather than deduping by content.
subtest "Assign is a BinOp" => sub {
    my $left  = const(1);
    my $right = const(2);
    my $node  = $factory->make('Assign', inputs => [$left, $right]);

    isa_ok($node, ['Chalk::IR::Node::BinOp'], 'Assign isa BinOp');
    isa_ok($node, ['Chalk::IR::Node'],        'Assign isa Node');
    is($node->left,   $left,  'Assign->left returns first input');
    is($node->right,  $right, 'Assign->right returns second input');
    is($node->op_str, '=',    q{Assign->op_str eq '='});
};

for my $case (@unaryop_cases) {
    my ($name, $op) = $case->@*;
    subtest "$name is a UnaryOp" => sub {
        my $operand = const(1);
        my $node    = $factory->make($name, inputs => [$operand]);

        isa_ok($node, ['Chalk::IR::Node::UnaryOp'], "$name isa UnaryOp");
        isa_ok($node, ['Chalk::IR::Node'],          "$name isa Node");
        is($node->operand, $operand, "$name->operand returns first input");
        is($node->op_str,  $op,     "$name->op_str eq '$op'");
    };
}

done_testing;
