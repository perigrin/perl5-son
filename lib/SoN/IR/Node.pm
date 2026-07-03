# ABOUTME: Base class for all Sea of Nodes IR nodes.
# ABOUTME: Provides id, inputs, consumers, and stamp fields with use-def chains.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node 0.01 {
    my $next_id = 0;

    field $id      :param :reader = $next_id++;
    field $inputs  :param :reader = [];
    field $consumers :reader      = [];
    field $stamp   :param :reader = undef;

    ADJUST {
        # Register this node as a consumer of each input
        for my $input ($inputs->@*) {
            push $input->consumers->@*, $self;
        }
    }

    method operation () { ref($self) =~ s/.*:://r }

    # Set the result stamp after construction. A loop header Phi's stamp is
    # the lattice join of its init and back-edge stamps, and the back-edge
    # value only exists after the body walk -- so the stamp is patched here
    # alongside set_backedge (the same post-construction seam Chalk's
    # set_representation provides on the consumer side).
    method set_stamp ($new_stamp) {
        $stamp = $new_stamp;
    }

    method content_hash () {
        my $op = $self->operation;
        my @input_ids = map { $_->id } $inputs->@*;
        return $op . '|' . CORE::join('|', @input_ids);
    }
}

1;
