# ABOUTME: Try/catch control flow node in the Chalk IR.
# ABOUTME: Represents a try block paired with one or more catch handlers.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::TryCatch :isa(SoN::IR::Node) {
    method operation() { 'TryCatch' }
}
