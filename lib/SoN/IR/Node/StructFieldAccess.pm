# ABOUTME: Struct field access node from the StructPromotion optimizer.
# ABOUTME: Accesses a named field on a promoted struct (distinct from class FieldAccess).
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use SoN::IR::Value;

class SoN::IR::Node::StructFieldAccess :isa(SoN::IR::Value) {
    method operation() { 'StructFieldAccess' }
}
