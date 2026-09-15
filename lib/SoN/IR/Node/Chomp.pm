# ABOUTME: chomp/chop in the Chalk IR -- an in-place trim of a string's tail.
# ABOUTME: Yields the trimmed string; the store back to the target is separate.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

class SoN::IR::Node::Chomp :isa(SoN::IR::Value) {
    # TWO OPERATIONS, NOT ONE. `chomp` removes a trailing $/ and returns how
    # many characters that was; `chop` removes the LAST character whatever it
    # is and returns that character. Perl gives them separate ops (schomp,
    # schop) and a consumer cannot guess which from the inputs.
    field $kind :param :reader = 'chomp';

    method operation() { 'Chomp' }

    method content_hash() {
        return join('|', 'Chomp', "kind=$kind", $self->_serialize_inputs());
    }
}
