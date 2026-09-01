# ABOUTME: Anonymous subroutine (closure) node in the Chalk IR.
# ABOUTME: Holds a nested SoN::IR::Graph for the sub body.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

class SoN::IR::Node::AnonSub :isa(SoN::IR::Value) {
    # Deterministic counter for unique AnonSub identity
    my $anon_counter = 0;

    # The `methods` key holding this sub's body. The body is its OWN graph
    # beside the others, not nested here -- see FromOptree's %ANON_BODIES for
    # why (a nested graph has no serializer arm on either side of the wire and
    # would be silently dropped).
    #
    # For a NON-CAPTURING anon sub the name IS the identity: the site is what
    # perl itself shares CVs by, across loop iterations and call frames alike.
    # A capturing one needs more than a name, which is why those refuse.
    field $name     :param :reader = undef;
    field $graph    :param :reader = undef;
    field $anon_id  :reader;

    ADJUST {
        $anon_id = $anon_counter++;
    }

    method operation() { 'AnonSub' }

    # Each anonymous sub is semantically unique (different closure body),
    # so include a sequential counter to prevent incorrect deduplication.
    method content_hash() {
        return join('|', 'AnonSub', "anon_id=$anon_id", $self->_serialize_inputs());
    }
}
