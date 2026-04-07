# ABOUTME: Tests that arithmetic/logic/comparison nodes inherit from BinOp/UnaryOp.
# ABOUTME: Verifies ISA relationships, field accessors, and op_str values after reparenting.

use v5.42.0;
use Test2::V0;

use SoN::IR::Node;
use SoN::IR::Node::Constant;
use SoN::IR::Node::BinOp;
use SoN::IR::Node::UnaryOp;
use SoN::IR::Stamp;

# --- BinOp subclasses ---
use SoN::IR::Node::Add;
use SoN::IR::Node::Subtract;
use SoN::IR::Node::Multiply;
use SoN::IR::Node::Divide;
use SoN::IR::Node::Modulo;
use SoN::IR::Node::Power;
use SoN::IR::Node::Concat;
use SoN::IR::Node::NumEq;
use SoN::IR::Node::NumNe;
use SoN::IR::Node::NumLt;
use SoN::IR::Node::NumGt;
use SoN::IR::Node::NumLe;
use SoN::IR::Node::NumGe;
use SoN::IR::Node::NumCmp;
use SoN::IR::Node::StrEq;
use SoN::IR::Node::StrNe;
use SoN::IR::Node::StrLt;
use SoN::IR::Node::StrGt;
use SoN::IR::Node::StrLe;
use SoN::IR::Node::StrGe;
use SoN::IR::Node::StrCmp;
use SoN::IR::Node::And;
use SoN::IR::Node::Or;
use SoN::IR::Node::BitAnd;
use SoN::IR::Node::BitOr;
use SoN::IR::Node::BitXor;
use SoN::IR::Node::LeftShift;
use SoN::IR::Node::RightShift;
use SoN::IR::Node::Assign;

# --- UnaryOp subclasses ---
use SoN::IR::Node::Not;
use SoN::IR::Node::Negate;
use SoN::IR::Node::Complement;
use SoN::IR::Node::Defined;

my $stamp = SoN::IR::Stamp->new(type => 'Int');

sub const ($val) {
    SoN::IR::Node::Constant->new(value => $val, stamp => $stamp)
}

my @binop_cases = (
    [ 'Add',        'SoN::IR::Node::Add',        '+'   ],
    [ 'Subtract',   'SoN::IR::Node::Subtract',   '-'   ],
    [ 'Multiply',   'SoN::IR::Node::Multiply',   '*'   ],
    [ 'Divide',     'SoN::IR::Node::Divide',     '/'   ],
    [ 'Modulo',     'SoN::IR::Node::Modulo',     '%'   ],
    [ 'Power',      'SoN::IR::Node::Power',      '**'  ],
    [ 'Concat',     'SoN::IR::Node::Concat',     '.'   ],
    [ 'NumEq',      'SoN::IR::Node::NumEq',      '=='  ],
    [ 'NumNe',      'SoN::IR::Node::NumNe',      '!='  ],
    [ 'NumLt',      'SoN::IR::Node::NumLt',      '<'   ],
    [ 'NumGt',      'SoN::IR::Node::NumGt',      '>'   ],
    [ 'NumLe',      'SoN::IR::Node::NumLe',      '<='  ],
    [ 'NumGe',      'SoN::IR::Node::NumGe',      '>='  ],
    [ 'NumCmp',     'SoN::IR::Node::NumCmp',     '<=>' ],
    [ 'StrEq',      'SoN::IR::Node::StrEq',      'eq'  ],
    [ 'StrNe',      'SoN::IR::Node::StrNe',      'ne'  ],
    [ 'StrLt',      'SoN::IR::Node::StrLt',      'lt'  ],
    [ 'StrGt',      'SoN::IR::Node::StrGt',      'gt'  ],
    [ 'StrLe',      'SoN::IR::Node::StrLe',      'le'  ],
    [ 'StrGe',      'SoN::IR::Node::StrGe',      'ge'  ],
    [ 'StrCmp',     'SoN::IR::Node::StrCmp',     'cmp' ],
    [ 'And',        'SoN::IR::Node::And',        '&&'  ],
    [ 'Or',         'SoN::IR::Node::Or',         '||'  ],
    [ 'BitAnd',     'SoN::IR::Node::BitAnd',     '&'   ],
    [ 'BitOr',      'SoN::IR::Node::BitOr',      '|'   ],
    [ 'BitXor',     'SoN::IR::Node::BitXor',     '^'   ],
    [ 'LeftShift',  'SoN::IR::Node::LeftShift',  '<<'  ],
    [ 'RightShift', 'SoN::IR::Node::RightShift', '>>'  ],
    [ 'Assign',     'SoN::IR::Node::Assign',     '='   ],
);

my @unaryop_cases = (
    [ 'Not',        'SoN::IR::Node::Not',        '!'       ],
    [ 'Negate',     'SoN::IR::Node::Negate',     '-'       ],
    [ 'Complement', 'SoN::IR::Node::Complement', '~'       ],
    [ 'Defined',    'SoN::IR::Node::Defined',    'defined' ],
);

for my $case (@binop_cases) {
    my ($name, $class, $op) = $case->@*;
    subtest "$name is a BinOp" => sub {
        my $left  = const(1);
        my $right = const(2);
        my $node  = $class->new(inputs => [$left, $right]);

        isa_ok($node, ['SoN::IR::Node::BinOp'], "$name isa BinOp");
        isa_ok($node, ['SoN::IR::Node'],        "$name isa Node");
        is($node->left,   $left,  "$name->left returns first input");
        is($node->right,  $right, "$name->right returns second input");
        is($node->op_str, $op,    "$name->op_str eq '$op'");
    };
}

for my $case (@unaryop_cases) {
    my ($name, $class, $op) = $case->@*;
    subtest "$name is a UnaryOp" => sub {
        my $operand = const(1);
        my $node    = $class->new(inputs => [$operand]);

        isa_ok($node, ['SoN::IR::Node::UnaryOp'], "$name isa UnaryOp");
        isa_ok($node, ['SoN::IR::Node'],          "$name isa Node");
        is($node->operand, $operand, "$name->operand returns first input");
        is($node->op_str,  $op,     "$name->op_str eq '$op'");
    };
}

done_testing;
