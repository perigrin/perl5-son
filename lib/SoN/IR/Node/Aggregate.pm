# ABOUTME: Intermediate base class for aggregate constructor IR nodes.
# ABOUTME: Groups HashRef, ArrayRef, and Interpolate nodes.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

class SoN::IR::Node::Aggregate :isa(SoN::IR::Value) {
}
