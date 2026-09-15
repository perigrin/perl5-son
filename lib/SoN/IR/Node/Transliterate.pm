# ABOUTME: Transliteration operation node in the Chalk IR (tr/// and y///).
# ABOUTME: Maps characters in a source SET to a replacement SET, one for one.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

class SoN::IR::Node::Transliterate :isa(SoN::IR::Value) {
    # NOT A RegexSubst, though the shape is similar. `from` and `to` are
    # character SETS, not patterns: `tr/a-z/A-Z/` maps each letter to its
    # uppercase, while the same text read as a regex is a character CLASS
    # matching one letter. A consumer handed these as a pattern would compile
    # something the source never wrote, so the operation is its own kind
    # rather than a flag on the substitution.
    #
    # They are the SOURCE spelling, decoded back from the op's translation
    # table -- a range comes back as `a-z`, not as its 26 expanded members.
    field $from  :param :reader = '';
    field $to    :param :reader = '';

    # c (complement), d (delete), s (squash), r (non-destructive). `d` is not
    # recoverable from an empty `to`: `tr/x//` with no flags maps x to itself,
    # while `tr/x//d` removes it.
    field $flags :param :reader = '';

    method operation() { 'Transliterate' }

    method content_hash() {
        return join('|', 'Transliterate', "from=$from", "to=$to",
            "flags=$flags", $self->_serialize_inputs());
    }
}
