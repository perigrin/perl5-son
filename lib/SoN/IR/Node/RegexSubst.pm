# ABOUTME: Regex substitution operation node in the Chalk IR.
# ABOUTME: Represents a substitution (s///) applied to an input expression.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Regex;

class SoN::IR::Node::RegexSubst :isa(SoN::IR::Node::Regex) {
    field $replacement :param :reader = '';

    # A COMPUTED PATTERN CANNOT BE A STRING. `s/$P b$/X/` builds its pattern at
    # runtime, so it rides on inputs the way Match's already does -- measured,
    # `$s =~ /${P}b/` is Match(subject, Concat("a","b")) with no pattern field.
    #
    # RegexSubst cannot simply follow suit: its optional second input is
    # already the /e replacement, so position alone does not say which is
    # which. This flag does, and Print carries `has_filehandle` for exactly the
    # same reason -- one boolean saying how to read the inputs.
    #
    # When true, inputs are [target, pattern, replacement?] and the `pattern`
    # string field is empty. When false, [target, replacement?] and the string
    # field holds the pattern.
    field $pattern_is_input :param :reader = 0;

    method operation() { 'RegexSubst' }

    method content_hash() {
        return join('|', 'RegexSubst', "pattern=" . $self->pattern,
            "replacement=$replacement", "flags=" . $self->flags,
            "pat_in=$pattern_is_input",
            $self->_serialize_inputs());
    }
}
