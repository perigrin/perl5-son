# ABOUTME: List-container constructor node in the Chalk IR.
# ABOUTME: Builds an array from its element inputs; the STAMP says ref or not.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Aggregate;

# NAMED FOR WHAT IT BUILDS, NOT FOR A REFERENCE. One constructor serves both
# `my @a = (1,2,3)` (stamp Array) and `[1,2,3]` (stamp ArrayRef) -- they share a
# construction path, and the STAMP carries the distinction.
#
# It used to be called `ArrayRef`, which asserted "reference" for a case the
# stamp called a plain array. That is not a naming quibble: chalk read the op
# name, assumed it agreed with the stamp, and boxed unconditionally -- 37 corpus
# cases emitted nothing. Its first fix then unboxed for Array too, on the theory
# the two were one container reached two ways, and broke five genuine-reference
# cases. A consumer reading only the op name got it wrong silently.
class SoN::IR::Node::ArrayLiteral :isa(SoN::IR::Node::Aggregate) {
    method operation() { 'ArrayLiteral' }
}
