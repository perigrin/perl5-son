# ABOUTME: Division operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the / operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::Divide :isa(SoN::IR::Node::BinOp) {
    method operation() { 'Divide' }

    # ONE THAT MAY DIE (by what may be zero) names the block eval whose body
    # made it, and its statement's file and line, which perl's message
    # names. Part of its content: the same division in another eval, or at
    # another line, dies differently.
    field $eval_id :param :reader = undef;
    field $file    :param :reader = undef;
    field $line    :param :reader = undef;

    method content_hash() {
        my $h = $self->SUPER::content_hash();
        return defined $line ? join('|', $h, 'site', $eval_id // '', $file // '', $line) : $h;
    }
    method op_str()    { '/' }
}
