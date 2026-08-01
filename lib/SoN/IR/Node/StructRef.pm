# ABOUTME: Struct reference constructor from the StructPromotion optimizer.
# ABOUTME: Represents a promoted hash-to-struct with a named schema and field values.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use SoN::IR::Node;

class SoN::IR::Node::StructRef :isa(SoN::IR::Node) {
    method operation() { 'StructRef' }
}
