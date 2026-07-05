# ABOUTME: Initial aggregate-memory value for a SoN computation graph (memory-SSA).
# ABOUTME: Has no inputs; the memory state at function entry, before any element store.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::MemStart :isa(SoN::IR::Node) {
}

1;
