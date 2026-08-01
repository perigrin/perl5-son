# ABOUTME: Intermediate base class for regex operation nodes.
# ABOUTME: Groups RegexMatch and RegexSubst, carrying shared pattern and flags fields.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

class SoN::IR::Node::Regex :isa(SoN::IR::Node) {
    field $pattern :param :reader = '';
    field $flags   :param :reader = '';

    method content_hash() {
        return join('|', $self->operation(), "pattern=$pattern", "flags=$flags", $self->_serialize_inputs());
    }
}
