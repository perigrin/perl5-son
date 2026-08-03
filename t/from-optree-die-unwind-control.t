# ABOUTME: `die` must build an Unwind whose control flows via control_in, not inputs.
# ABOUTME: A flattened-args Unwind with control as an input operand strands the backward walk (F1).

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;

# `print "before\n"; die "boom\n"` -- the producer builds an Unwind CFG node for
# the die. Chalk's own node contract (SoN::IR::Node::Unwind's ABOUTME) says
# control flows through control_in, decorated via set_control_in, and inputs[0]
# is the exception-args ARRAYREF -- not the control node, and not flattened args.
#
# Pre-fix, FromOptree built `inputs => [$sim->control, $args->@*]` and called
# `$sim->set_control($unwind)` (which only updates the SIMULATOR's notion of
# current control) but never `$unwind->set_control_in(...)`. So control_in
# stayed undef on the Unwind itself, and inputs->[0] was the CONTROL NODE
# rather than the exception-args arrayref. Chalk's backward control-chain walk
# stops dead at a control_in-less Unwind, stranding the print one hop away.
subtest 'die builds an Unwind with control_in defined and inputs[0] the args arrayref' => sub {
    my $sub = eval 'sub { print "before\n"; die "boom\n" }';
    die "compile failed: $@" if $@;
    my $graph = SoN::FromOptree->translate($sub);

    my ($unwind) = grep { $_->operation eq 'Unwind' } $graph->nodes->@*;
    ok(defined $unwind, 'graph has an Unwind node') or return;

    ok(defined $unwind->control_in, 'Unwind.control_in is defined (control flows via control_in)');

    my $args = $unwind->inputs->[0];
    is(ref $args, 'ARRAY', 'Unwind.inputs[0] is the exception-args arrayref, not the control node');
};

# SoN::Render::Text walks every node's ->inputs->@* and calls ->id on each
# element, assuming inputs is always a flat list of node objects. An Unwind's
# inputs[0] is now the exception-args ARRAYREF (per the node's own contract),
# so a generic renderer must skip/expand non-node elements the same way
# SoN::IR::Graph::nodes() and SoN::IR::Serialize::JSON already do.
subtest 'rendering a graph with an Unwind does not crash on the arrayref input' => sub {
    my $sub = eval 'sub { print "before\n"; die "boom\n" }';
    die "compile failed: $@" if $@;
    my $graph = SoN::FromOptree->translate($sub);

    my $renderer = SoN::Render::Text->new();
    my $text = eval { $renderer->render($graph) };
    ok(!$@, 'render does not die') or diag("error: $@");
    like($text // '', qr/Unwind/, 'rendered text mentions Unwind');
};

done_testing;
