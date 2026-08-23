# ABOUTME: Empty base class for all access IR nodes in the Chalk Sea of Nodes graph.
# ABOUTME: Groups PadAccess, FieldAccess, EntryDef, and Subscript under a common type.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

class SoN::IR::Node::Access :isa(SoN::IR::Value) {
}
