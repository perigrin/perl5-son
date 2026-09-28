# ABOUTME: Perl's `++` applied to a value that may be a string: the magic
# ABOUTME: increment ("Az" -> "Ba", "a9" -> "b0"), numeric for anything else.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

# NOT Add(x, 1). perl increments a string matching /^[a-zA-Z]*[0-9]*$/ that has
# never been used as a number by carrying through the characters, and Add would
# coerce it to 0 first. The producer builds this only when the operand's stamp
# is not already numeric; an Int or Num counter stays an Add.
#
# Its one input is the value BEFORE the increment; the node is the value after.
# Decrement has no magic form in perl, so there is no Decrement.
class SoN::IR::Node::Increment :isa(SoN::IR::Node::UnaryOp) {
    method operation() { 'Increment' }
    method op_str()    { '++' }
}
