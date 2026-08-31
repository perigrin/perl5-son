# ABOUTME: Hash reference constructor node in the Chalk IR.
# ABOUTME: Represents a list of key/value pairs assembled into a hash reference.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Aggregate;

class SoN::IR::Node::HashRef :isa(SoN::IR::Node::Aggregate) {
    method operation() { 'HashRef' }

}
