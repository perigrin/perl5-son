# ABOUTME: The character count returned by tr/// in non-void context.
# ABOUTME: Distinct from the transliterated subject, which is the Transliterate itself.

use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

# A tr/// HAS TWO RESULTS AND THEY ARE NOT THE SAME VALUE. The
# transliteration rebinds its target to the rewritten subject; the
# EXPRESSION yields how many characters matched. Void context reads neither,
# and /r yields the rewritten copy with no count at all.
#
# ITS STAMP IS Int, UNLIKE RegexSubstCount. Measured on 5.42.0:
#
#     "aab" =~ tr/a//    ->  2
#     "xyz" =~ tr/a//    ->  0        a real zero, length 1
#
# where the s/// count gives the EMPTY STRING for no matches. So the two
# counts are not the same type and cannot share a node: stamping this Str
# would be true of s/// and false here, and stamping that Int the reverse.
class SoN::IR::Node::TransliterateCount :isa(SoN::IR::Node::UnaryOp) {
    method operation() { 'TransliterateCount' }
}
