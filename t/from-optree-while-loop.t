# ABOUTME: Tests SoN::FromOptree lowers while loops to the corpus Loop/Phi contract:
# ABOUTME: header Phis wired BEFORE the body walk, Projs on the Loop, exit Region control.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# The lowerable loop contract (corpus control-flow.md D2, proven end-to-end by
# Chalk's son-loop-backedge.t): the Loop node IS the header -- no If inside it;
# body and exit are Proj(loop, 0) / Proj(loop, 1); the Return control is a
# single-arm Region on the exit Proj; every loop-carried variable reads through
# a header Phi (inputs[0]=init, inputs[1]=backedge, region=Loop) so the
# condition and body see the current iteration's value, not the init constants.

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub nodes_of ($g, $want_op) {
    return grep { $_->operation eq $want_op } $g->nodes->@*;
}

subtest 'while loop emits the corpus Loop/Phi shape' => sub {
    my $g = graph_of(
        'sub { my $n = 3; my $s = 0; while ($n > 0) { $s += $n; $n-- } $s }');

    my @loops = nodes_of($g, 'Loop');
    is(scalar @loops, 1, 'exactly one Loop node');
    my $loop = $loops[0];
    is($loop->inputs->[0]->operation, 'Start', 'Loop entry control is Start');

    is([nodes_of($g, 'If')], [], 'no If node -- the Loop IS the header');

    my @phis = nodes_of($g, 'Phi');
    is(scalar @phis, 2, 'two header Phis (one per mutated variable)');
    my ($n_phi) = grep { ($_->inputs->[0]->value // '') == 3 } @phis;
    my ($s_phi) = grep { ($_->inputs->[0]->value // '') == 0 } @phis;
    ok(defined $n_phi, 'found the $n Phi (init 3)');
    ok(defined $s_phi, 'found the $s Phi (init 0)');

    is($n_phi->region->id, $loop->id, '$n Phi region is the Loop');
    is($s_phi->region->id, $loop->id, '$s Phi region is the Loop');

    is($n_phi->inputs->[1]->operation, 'Subtract', '$n Phi backedge is the decrement');
    is($s_phi->inputs->[1]->operation, 'Add',      '$s Phi backedge is the sum');

    # SSA renaming: condition and body read the Phis, not the init constants.
    my ($cmp) = nodes_of($g, 'NumGt');
    ok(defined $cmp, 'has the loop condition NumGt');
    is($cmp && $cmp->inputs->[0]->id, $n_phi->id, 'condition reads the $n Phi');

    my $add = $s_phi->inputs->[1];
    is($add->inputs->[0]->id, $s_phi->id, 'Add reads the $s Phi');
    is($add->inputs->[1]->id, $n_phi->id, 'Add reads the $n Phi');
    my $sub = $n_phi->inputs->[1];
    is($sub->inputs->[0]->id, $n_phi->id, 'Subtract reads the $n Phi');

    # Phis carry the joined stamp so the backend can pick a representation.
    ok(defined $n_phi->stamp, '$n Phi is stamped');
    is($n_phi->stamp->type, 'Int', '$n Phi stamp is Int');
    ok(defined $s_phi->stamp, '$s Phi is stamped');
    is($s_phi->stamp->type, 'Int', '$s Phi stamp is Int');

    # Control shape: Proj(loop,0) body, Proj(loop,1) exit, Region(exit Proj),
    # Return control = that Region, Return value = the $s Phi.
    my @projs = grep { $_->inputs->[0]->id eq $loop->id } nodes_of($g, 'Proj');
    is(scalar @projs, 2, 'two Projs hang directly on the Loop');
    my ($exit_proj) = grep { $_->index == 1 } @projs;
    ok(defined $exit_proj, 'has the exit Proj (index 1)');

    my ($region) = nodes_of($g, 'Region');
    ok(defined $region, 'has the exit Region');
    is($region->inputs->[0]->id, $exit_proj->id, 'Region merges the exit Proj');

    my ($ret) = nodes_of($g, 'Return');
    is($ret->control_in->id, $region->id, 'Return control is the exit Region');
    is($ret->inputs->[0]->id, $s_phi->id,  'Return value is the $s Phi');
};

subtest 'unchanged variables read through, no spurious Phi' => sub {
    my $g = graph_of(
        'sub { my $k = 2; my $s = 0; my $n = 3; while ($n > 0) { $s += $k; $n-- } $s }');
    my @phis = nodes_of($g, 'Phi');
    is(scalar @phis, 2, 'only the two mutated variables get Phis ($s, $n)');
    my ($add) = nodes_of($g, 'Add');
    my ($k_read) = grep { $_->operation eq 'Constant' && ($_->value // '') == 2 }
        map { $_->inputs->@* } nodes_of($g, 'Add');
    ok(defined $k_read, 'the invariant $k is read as its binding, not a Phi');
};

subtest 'topological order cuts only the Phi backedges' => sub {
    # The serializer emits nodes in graph order and the Chalk loader resolves
    # inputs single-pass, deferring ONLY a Phi's inputs[1] (the sanctioned
    # backedge patch). So the order contract is: every input precedes its
    # consumer, except a loop Phi's backedge which may follow.
    my $g = graph_of(
        'sub { my $n = 3; my $s = 0; while ($n > 0) { $s += $n; $n-- } $s }');
    my $nodes = $g->nodes;
    my %pos;
    $pos{ $nodes->[$_]->id } = $_ for 0 .. $nodes->$#*;
    my @violations;
    for my $node ($nodes->@*) {
        my $is_loop_phi = $node->operation eq 'Phi'
            && $node->region->operation eq 'Loop';
        my $ins = $node->inputs;
        for my $slot (0 .. $ins->$#*) {
            next if $is_loop_phi && $slot == 1;   # the one sanctioned forward edge
            my $in = $ins->[$slot];
            next unless defined $in;
            push @violations,
                sprintf('%s(pos %d) slot %d reads %s(pos %d)',
                    $node->operation, $pos{ $node->id }, $slot,
                    $in->operation, $pos{ $in->id })
                if $pos{ $in->id } > $pos{ $node->id };
        }
    }
    is(\@violations, [], 'no forward references outside Phi backedges');
};

subtest 'return inside a loop body refuses loudly' => sub {
    like(
        dies {
            graph_of('sub { my $n = 3; while ($n > 0) { return 9 if $n == 1; $n-- } 0 }')
        },
        qr/GAP/,
        'function exit inside a loop body dies with a GAP message'
    );
};

done_testing();
