# ABOUTME: Singleton factory for SoN IR nodes with hash consing.
# ABOUTME: Deduplicates data nodes by content hash, assigns unique IDs to CFG nodes.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::NodeFactory 0.01 {
    # Map of operation name to class name
    my %NODE_CLASSES;
    my %CFG_CLASSES;

    # Register node classes at load time
    sub register ($class, $op_name, $node_class) {
        $NODE_CLASSES{$op_name} = $node_class;
    }

    sub register_cfg ($class, $op_name, $node_class) {
        $CFG_CLASSES{$op_name} = $node_class;
    }

    field %cache;

    # Create a data node with hash consing
    method make ($op_name, %args) {
        my $node_class = $NODE_CLASSES{$op_name}
            // die "Unknown data node type: $op_name";

        # Create a temporary node to compute its content hash
        my $node = $node_class->new(%args);
        my $hash = $node->content_hash;

        # Return cached node if we've seen this exact computation
        if (exists $cache{$hash}) {
            return $cache{$hash};
        }

        $cache{$hash} = $node;
        return $node;
    }

    # Create a CFG node (never hash-consed)
    method make_cfg ($op_name, %args) {
        my $node_class = $CFG_CLASSES{$op_name}
            // die "Unknown CFG node type: $op_name";
        return $node_class->new(%args);
    }
}

# Register built-in CFG node types
use SoN::IR::Node::Start;
use SoN::IR::Node::Return;
use SoN::IR::Node::Region;
use SoN::IR::Node::If;
use SoN::IR::Node::Proj;
use SoN::IR::Node::Loop;
use SoN::IR::Node::Unwind;

SoN::IR::NodeFactory->register_cfg('Start',  'SoN::IR::Node::Start');
SoN::IR::NodeFactory->register_cfg('Return', 'SoN::IR::Node::Return');
SoN::IR::NodeFactory->register_cfg('Region', 'SoN::IR::Node::Region');
SoN::IR::NodeFactory->register_cfg('If',     'SoN::IR::Node::If');
SoN::IR::NodeFactory->register_cfg('Proj',   'SoN::IR::Node::Proj');
SoN::IR::NodeFactory->register_cfg('Loop',   'SoN::IR::Node::Loop');
SoN::IR::NodeFactory->register_cfg('Unwind', 'SoN::IR::Node::Unwind');

# Register built-in data node types
use SoN::IR::Node::Constant;
SoN::IR::NodeFactory->register('Constant', 'SoN::IR::Node::Constant');

# Arithmetic operation nodes
use SoN::IR::Node::Add;
use SoN::IR::Node::Subtract;
use SoN::IR::Node::Multiply;
use SoN::IR::Node::Divide;
use SoN::IR::Node::Negate;
use SoN::IR::Node::Modulo;
use SoN::IR::Node::Power;
SoN::IR::NodeFactory->register('Add',      'SoN::IR::Node::Add');
SoN::IR::NodeFactory->register('Subtract', 'SoN::IR::Node::Subtract');
SoN::IR::NodeFactory->register('Multiply', 'SoN::IR::Node::Multiply');
SoN::IR::NodeFactory->register('Divide',   'SoN::IR::Node::Divide');
SoN::IR::NodeFactory->register('Negate',   'SoN::IR::Node::Negate');
SoN::IR::NodeFactory->register('Modulo',   'SoN::IR::Node::Modulo');
SoN::IR::NodeFactory->register('Power',    'SoN::IR::Node::Power');

# String operation nodes
use SoN::IR::Node::Concat;
use SoN::IR::Node::Length;
use SoN::IR::Node::Stringify;
SoN::IR::NodeFactory->register('Concat',    'SoN::IR::Node::Concat');
SoN::IR::NodeFactory->register('Length',    'SoN::IR::Node::Length');
SoN::IR::NodeFactory->register('Stringify', 'SoN::IR::Node::Stringify');

# Numeric comparison nodes
use SoN::IR::Node::NumEq;
use SoN::IR::Node::NumLt;
use SoN::IR::Node::NumGt;
use SoN::IR::Node::NumLe;
use SoN::IR::Node::NumGe;
use SoN::IR::Node::NumNe;
use SoN::IR::Node::NumCmp;
SoN::IR::NodeFactory->register('NumEq',  'SoN::IR::Node::NumEq');
SoN::IR::NodeFactory->register('NumLt',  'SoN::IR::Node::NumLt');
SoN::IR::NodeFactory->register('NumGt',  'SoN::IR::Node::NumGt');
SoN::IR::NodeFactory->register('NumLe',  'SoN::IR::Node::NumLe');
SoN::IR::NodeFactory->register('NumGe',  'SoN::IR::Node::NumGe');
SoN::IR::NodeFactory->register('NumNe',  'SoN::IR::Node::NumNe');
SoN::IR::NodeFactory->register('NumCmp', 'SoN::IR::Node::NumCmp');

# String comparison nodes
use SoN::IR::Node::StrEq;
use SoN::IR::Node::StrLt;
use SoN::IR::Node::StrGt;
use SoN::IR::Node::StrLe;
use SoN::IR::Node::StrGe;
use SoN::IR::Node::StrNe;
use SoN::IR::Node::StrCmp;
SoN::IR::NodeFactory->register('StrEq',  'SoN::IR::Node::StrEq');
SoN::IR::NodeFactory->register('StrLt',  'SoN::IR::Node::StrLt');
SoN::IR::NodeFactory->register('StrGt',  'SoN::IR::Node::StrGt');
SoN::IR::NodeFactory->register('StrLe',  'SoN::IR::Node::StrLe');
SoN::IR::NodeFactory->register('StrGe',  'SoN::IR::Node::StrGe');
SoN::IR::NodeFactory->register('StrNe',  'SoN::IR::Node::StrNe');
SoN::IR::NodeFactory->register('StrCmp', 'SoN::IR::Node::StrCmp');

# Logical operation nodes
use SoN::IR::Node::And;
use SoN::IR::Node::Or;
use SoN::IR::Node::Not;
use SoN::IR::Node::Defined;
SoN::IR::NodeFactory->register('And',     'SoN::IR::Node::And');
SoN::IR::NodeFactory->register('Or',      'SoN::IR::Node::Or');
SoN::IR::NodeFactory->register('Not',     'SoN::IR::Node::Not');
SoN::IR::NodeFactory->register('Defined', 'SoN::IR::Node::Defined');

# Bitwise operation nodes
use SoN::IR::Node::BitAnd;
use SoN::IR::Node::BitOr;
use SoN::IR::Node::BitXor;
use SoN::IR::Node::LeftShift;
use SoN::IR::Node::RightShift;
use SoN::IR::Node::Complement;
SoN::IR::NodeFactory->register('BitAnd',      'SoN::IR::Node::BitAnd');
SoN::IR::NodeFactory->register('BitOr',       'SoN::IR::Node::BitOr');
SoN::IR::NodeFactory->register('BitXor',      'SoN::IR::Node::BitXor');
SoN::IR::NodeFactory->register('LeftShift',   'SoN::IR::Node::LeftShift');
SoN::IR::NodeFactory->register('RightShift',  'SoN::IR::Node::RightShift');
SoN::IR::NodeFactory->register('Complement',  'SoN::IR::Node::Complement');

# Assignment node
use SoN::IR::Node::Assign;
SoN::IR::NodeFactory->register('Assign', 'SoN::IR::Node::Assign');

# Compound assignment node
use SoN::IR::Node::CompoundAssign;
SoN::IR::NodeFactory->register('CompoundAssign', 'SoN::IR::Node::CompoundAssign');

# Regex binding nodes
use SoN::IR::Node::Match;
use SoN::IR::Node::NotMatch;
SoN::IR::NodeFactory->register('Match',    'SoN::IR::Node::Match');
SoN::IR::NodeFactory->register('NotMatch', 'SoN::IR::Node::NotMatch');

# String/list repetition node
use SoN::IR::Node::Repeat;
SoN::IR::NodeFactory->register('Repeat', 'SoN::IR::Node::Repeat');

# Defined-or operator node
use SoN::IR::Node::DefinedOr;
SoN::IR::NodeFactory->register('DefinedOr', 'SoN::IR::Node::DefinedOr');

# Logical exclusive or node
use SoN::IR::Node::Xor;
SoN::IR::NodeFactory->register('Xor', 'SoN::IR::Node::Xor');

# Range operator nodes
use SoN::IR::Node::Range;
use SoN::IR::Node::Yada;
SoN::IR::NodeFactory->register('Range', 'SoN::IR::Node::Range');
SoN::IR::NodeFactory->register('Yada',  'SoN::IR::Node::Yada');

# Type check operator node
use SoN::IR::Node::IsaOp;
SoN::IR::NodeFactory->register('IsaOp', 'SoN::IR::Node::IsaOp');

# Call node
use SoN::IR::Node::Call;
SoN::IR::NodeFactory->register('Call', 'SoN::IR::Node::Call');

# Phi node
use SoN::IR::Node::Phi;
SoN::IR::NodeFactory->register('Phi', 'SoN::IR::Node::Phi');

# Variable access nodes
use SoN::IR::Node::PadAccess;
use SoN::IR::Node::FieldAccess;
use SoN::IR::Node::StashAccess;
SoN::IR::NodeFactory->register('PadAccess',   'SoN::IR::Node::PadAccess');
SoN::IR::NodeFactory->register('FieldAccess', 'SoN::IR::Node::FieldAccess');
SoN::IR::NodeFactory->register('StashAccess', 'SoN::IR::Node::StashAccess');

# Collection access nodes
use SoN::IR::Node::Subscript;
use SoN::IR::Node::Slice;
SoN::IR::NodeFactory->register('Subscript', 'SoN::IR::Node::Subscript');
SoN::IR::NodeFactory->register('Slice',     'SoN::IR::Node::Slice');

1;
