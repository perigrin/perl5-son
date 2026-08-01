# ABOUTME: Initial aggregate-memory value for a Chalk computation graph (memory-SSA).
# ABOUTME: Has no inputs; the memory state at function entry, before any element store.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::MemStart :isa(SoN::IR::Node) {
    method operation() { 'MemStart' }
}
