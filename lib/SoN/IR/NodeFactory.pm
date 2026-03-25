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

SoN::IR::NodeFactory->register_cfg('Start',  'SoN::IR::Node::Start');
SoN::IR::NodeFactory->register_cfg('Return', 'SoN::IR::Node::Return');
SoN::IR::NodeFactory->register_cfg('Region', 'SoN::IR::Node::Region');
SoN::IR::NodeFactory->register_cfg('If',     'SoN::IR::Node::If');
SoN::IR::NodeFactory->register_cfg('Proj',   'SoN::IR::Node::Proj');
SoN::IR::NodeFactory->register_cfg('Loop',   'SoN::IR::Node::Loop');

# Register built-in data node types
use SoN::IR::Node::Constant;
SoN::IR::NodeFactory->register('Constant', 'SoN::IR::Node::Constant');

# Operation nodes will be registered as they're implemented
eval { require SoN::IR::Node::Add; SoN::IR::NodeFactory->register('Add', 'SoN::IR::Node::Add') };

1;
