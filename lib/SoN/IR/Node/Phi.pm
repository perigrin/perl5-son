# ABOUTME: Value selection node at Region or Loop merge points in the SoN IR graph.
# ABOUTME: Hash-consed data node that selects among incoming values based on control flow.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::Phi :isa(SoN::IR::Node) {
    field $region :param :reader;

    method operation () { 'Phi' }

    method content_hash () {
        my @input_ids = map { $_->id } $self->inputs->@*;
        return "Phi|region=" . $region->id
             . "|" . CORE::join('|', @input_ids);
    }

    # Wire the loop back-edge value as inputs[1], maintaining consumer edges.
    # A loop header Phi is constructed with only its init input (the back-edge
    # value does not exist yet -- it is computed by the body that reads the
    # Phi), then patched here once the body walk completes. Mirrors the Chalk
    # Phi contract the corpus builder relies on.
    method set_backedge ($value) {
        my $old = $self->inputs->[1];
        if (defined $old) {
            my $c = $old->consumers;
            @$c = grep { $_ != $self } @$c;
        }
        $self->inputs->[1] = $value;
        push $value->consumers->@*, $self;
    }
}

1;
