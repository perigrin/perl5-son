# ABOUTME: Regex match binding operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the =~ operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::BinOp;

class SoN::IR::Node::Match :isa(SoN::IR::Node::BinOp) {
    # The match's flags: a pattern made at run time has no qr// to carry them
    # (`$s =~ /$p/i`). In the hash: /$p/ and /$p/i are different matches.
    field $flags :param :reader = '';

    method operation() { 'Match' }
    method op_str()    { '=~' }
    method content_hash() {
        return join('|', $self->SUPER::content_hash(), "flags=$flags");
    }
}
