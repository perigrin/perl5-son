# ABOUTME: Loop-carried list accumulator in the Chalk IR.
# ABOUTME: inputs[0] is the list so far; the rest are appended this iteration.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

# THE VALUE A map/grep LOOP CARRIES. Those are loops -- they carry
# mapwhile/grepwhile exactly as `while` carries enterloop/leaveloop -- but their
# OUTPUT LENGTH IS NOT THEIR INPUT LENGTH:
#
#     map { ($_, $_) } (1,2)   -> 4 elements
#     map { () } (1,2)         -> 0 elements
#     grep { $_ > 1 } (1,2,3)  -> 2 elements
#
# `Count(list)` bounds the INPUT. Nothing bounded the output, which is why this
# could not be expressed by reusing the foreach lowering alone.
#
# inputs[0] is the accumulator so far -- a loop Phi, so the existing
# loop-carried machinery moves it across the back-edge with no new control
# handling. inputs[1..] are whatever this iteration contributes: NONE when a
# grep predicate is false or a map body yields the empty list, which is what
# makes the length variable.
class SoN::IR::Node::ListAppend :isa(SoN::IR::Value) {
    # WHICH COLLECTOR BUILT THIS, because the inputs alone do not say and the
    # two mean opposite things:
    #
    #     map   [acc, CONTRIBUTION...]        every input is appended
    #     grep  [acc, ELEMENT, PREDICATE]     the element is appended IF the
    #                                         predicate is true
    #
    # THE STAMPS CANNOT RECOVER IT. Measured, `map { $_ > 1 }` is
    # [Phi Array, NumGt Boolean] -- a Boolean CONTRIBUTION that must be kept --
    # while `grep { $_ > 1 }` is [Phi Array, Subscript Int, NumGt Boolean].
    # Same kinds, opposite meanings, so a reader that infers is wrong for one.
    field $collector :param :reader = 'map';

    method operation() { 'ListAppend' }

    method content_hash() {
        return join('|', 'ListAppend', "collector=$collector",
            $self->_serialize_inputs());
    }
}
