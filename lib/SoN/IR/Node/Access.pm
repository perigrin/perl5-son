# ABOUTME: Empty base class for all access IR nodes in the Chalk Sea of Nodes graph.
# ABOUTME: Groups PadAccess, FieldAccess, EntryDef, and Subscript under a common type.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

class SoN::IR::Node::Access :isa(SoN::IR::Value) {
    # A PLACE (wire `fields.place`): the storage itself, not a read of it --
    # what perl binds an alias to where B::SoN cannot prove the alias private
    # (docs/plans/2026-11-24-aliases-as-places.md). No mem_in. `vivify`: the
    # binder makes the element exist (a foreach, map or grep item).
    field $place  :param :reader = 0;
    field $vivify :param :reader = 0;
}
