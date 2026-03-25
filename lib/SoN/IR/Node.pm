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
}

1;
