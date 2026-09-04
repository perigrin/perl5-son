# ABOUTME: The match count returned by a destructive s/// in scalar context.
# ABOUTME: Distinct from the substituted subject, which is what the RegexSubst itself is.

use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

# A DESTRUCTIVE s/// HAS TWO RESULTS AND THEY ARE NOT THE SAME VALUE. The
# substitution rebinds its target to the rewritten subject; the EXPRESSION
# yields the number of matches. Void context reads neither, /r yields the
# rewritten copy and no count at all, and only scalar/list context on the
# destructive form produces this node.
#
# ITS STAMP IS Str. Measured on 5.42.0:
#
#     "aaa" =~ s/a/b/g   ->  3
#     "xxx" =~ s/a/b/g   ->  ""    the EMPTY STRING, defined and false
#
# so zero matches is not 0, and `defined` cannot distinguish "no matches" from
# "some matches" -- only truth can. Int is wrong about the zero case, and
# Boolean is not an option: the lattice has Boolean => Scalar, not
# Boolean => Str (see the two-factor subtyping note in Stamp.pm), so a Boolean
# stamp would assert a relationship perl does not have. Int-or-empty-string is
# Str.
#
# NOT Count. That node is "the number of ELEMENTS in an aggregate", takes a
# memory input because an aggregate read must observe mutations, and is Int.
# A substitution count is none of those things.
class SoN::IR::Node::RegexSubstCount :isa(SoN::IR::Node::UnaryOp) {
    method operation() { 'RegexSubstCount' }
}
