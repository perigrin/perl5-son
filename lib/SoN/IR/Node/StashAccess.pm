# ABOUTME: IR node for accessing a package (stash) variable in the Sea of Nodes graph.
# ABOUTME: Represents reads of package globals like $Foo::bar or %Foo::.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::Access;

class SoN::IR::Node::StashAccess :isa(SoN::IR::Node::Access) {
    field $stash_name :param :reader = '';
    field $var_name   :param :reader = '';

    # THE SIGIL IS PART OF THE IDENTITY. `$_` and `@_` are DIFFERENT variables
    # that share the glob name `_`, and a name-only identity hash-consed them
    # into ONE node: measured, `sub f { my $n = shift; /x/ ? 1 : 0 }` produced a
    # single StashAccess(_) feeding BOTH the `shift @_` Call and the RegexMatch
    # subject. One node cannot be two variables.
    #
    # The same applies to any stash holding one name under two sigils -- `$g`
    # and `@g` are unrelated variables.
    #
    # Defaults to '$' so an unstamped construction keeps a stable identity
    # rather than silently merging with a differently-sigilled sibling.
    field $sigil :param :reader = '$';

    method operation() { 'StashAccess' }

    method content_hash() {
        return join('|', 'StashAccess', "stash_name=$stash_name",
            "sigil=$sigil", "var_name=$var_name", $self->_serialize_inputs());
    }
}
