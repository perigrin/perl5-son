# ABOUTME: Slice operation node in the Chalk IR.
# ABOUTME: Aggregate data node taking a container and index list, producing a slice.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Aggregate;

class SoN::IR::Node::Slice :isa(SoN::IR::Node::Aggregate) {
    method operation() { 'Slice' }
}
