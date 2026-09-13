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
    # THE VARIABLE THIS AGGREGATE WAS BOUND TO, when it was bound to one.
    #
    # An aggregate is represented by the literal that INITIALISED it, and that
    # literal had no name -- so nothing downstream could WRITE the container.
    # An element store came out as Assign(Subscript(ArrayLiteral, 0), 7), and
    # `(1,2,3)[0] = 7` is not assignable Perl. Reads survive (a list slice is
    # legal); only stores need the name.
    #
    # ABSENT FOR AN ANONYMOUS AGGREGATE, and that is the point rather than an
    # omission: `[1,2,3]` names no variable. The STAMP already separates the
    # two -- Array/Hash for a pad-bound aggregate, ArrayRef/HashRef for an
    # anonymous one -- so this adds a name where one exists and nothing where
    # it does not.
    #
    # NOT PART OF content_hash. Two aggregates with the same contents are
    # already distinct nodes (this class is not hash-consed), so identity does
    # not depend on the name, and including it would make an unnamed and a
    # named aggregate with identical contents fail to share a cache entry for
    # no gain.
    field $varname :param :reader = undef;

    method operation() { 'ArrayLiteral' }
}
