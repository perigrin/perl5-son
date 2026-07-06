# ABOUTME: Tests a while/foreach loop whose body stores an element builds a Loop + header memory-Phi (2b-4).
# ABOUTME: The header memory-Phi has inputs[0]=pre-loop memory, inputs[1]=back-edge (body's final store), region=Loop; the post-loop read takes the Phi.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# A loop body element store threads memory around the back-edge via a
# loop-header memory-Phi -- exactly like a loop-carried scope slot. inputs[0]
# is the pre-loop memory (init), inputs[1] the back-edge (the body's final
# store), region is the Loop. The body's store advances memory OFF the header
# Phi; the post-loop read takes the header memory-Phi (the loop may run zero
# times, so the read must observe init OR back-edge = the Phi).

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub of_op ($g, $op) { grep { $_->operation eq $op } $g->nodes->@* }

# The loop-header memory-Phi: a Phi over a Loop region whose first input is the
# pre-loop MemStart (or an earlier store) and whose second input (the
# back-edge) is the body's element store.
sub loop_mem_phi ($g) {
    my @phis = grep {
        defined $_->region && $_->region->operation eq 'Loop'
    } of_op($g, 'Phi');
    my @mem = grep {
        my @in = $_->inputs->@*;
        @in == 2
            && grep { ref $_ && $_->operation eq 'Assign'
                && grep { ref $_ && $_->operation eq 'Subscript' } $_->inputs->@* }
               $in[1];   # the back-edge input is an element store
    } @phis;
    return $mem[0];
}

my $WHILE = 'sub { my @a = (1,2,3); my $i = 0; while ($i < 3) { $a[$i] = $i*2; $i = $i + 1 } $a[1] }';

subtest 'the while loop builds exactly one Loop node' => sub {
    my $g = graph_of($WHILE);
    is(scalar(of_op($g, 'Loop')), 1, 'exactly one Loop node');
};

subtest 'the body element store threads a loop-header memory-Phi' => sub {
    my $g = graph_of($WHILE);
    my $mem = loop_mem_phi($g);
    ok(defined $mem, 'a loop-header memory-Phi exists') or return;
    is($mem->region->operation, 'Loop', 'the memory-Phi region is the Loop');
    is(scalar($mem->inputs->@*), 2, 'the memory-Phi has two inputs (init, back-edge)');

    # inputs[0] is the pre-loop memory (MemStart at entry -- no store before the loop).
    my $init = $mem->inputs->[0];
    is($init->operation, 'MemStart', 'inputs[0] is the pre-loop memory (MemStart)');

    # inputs[1] is the back-edge: the body's element store (an Assign over a Subscript lvalue).
    my $back = $mem->inputs->[1];
    is($back->operation, 'Assign', 'inputs[1] (back-edge) is the body element store');
    ok((grep { ref $_ && $_->operation eq 'Subscript' } $back->inputs->@*),
        'the back-edge store carries a Subscript lvalue');
};

subtest 'the body store advances memory OFF the header Phi' => sub {
    my $g = graph_of($WHILE);
    my $mem = loop_mem_phi($g);
    ok(defined $mem, 'loop-header memory-Phi exists') or return;
    # The back-edge is the body store; it advances memory to a NEW value distinct
    # from the pre-loop init (so the Phi genuinely merges init OR back-edge -- not
    # a degenerate self-loop). The lvalue Subscript is a 2-input address node (no
    # memory input); the memory advance lives in the Assign, which IS the back-edge.
    my $init = $mem->inputs->[0];
    my $back = $mem->inputs->[1];
    isnt($back, $init, 'the back-edge (post-body memory) differs from the init memory');
    is($back->operation, 'Assign', 'the back-edge is the body element store (memory-out)');
    # The store is a statement effect threaded on the loop-body control chain.
    ok($back->is_stmt_effect, 'the store is a statement-effect on the loop control chain');
};

subtest 'the post-loop read takes the header memory-Phi' => sub {
    my $g = graph_of($WHILE);
    my $mem = loop_mem_phi($g);
    ok(defined $mem, 'loop-header memory-Phi exists') or return;
    my ($ret) = of_op($g, 'Return');
    my $read = $ret->inputs->[-1];
    is($read->operation, 'Subscript', 'the return value is a Subscript (the read)') or return;
    is($read->inputs->[2], $mem, 'the post-loop read memory is the header memory-Phi');
};

# The foreach-range body store is a SEPARATE producer code path
# (_translate_foreach_range: an induction Phi plus per-slot Phis over the same
# Loop region). Its memory-Phi shape must match the while form's contract, so a
# mis-seeded init or a back-edge wired to the wrong node is caught structurally
# here rather than only by an end-to-end value (which can coincidentally pass).
my $FOR = 'sub { my @a = (0,0,0); for my $i (0..2) { $a[$i] = $i + 1 } $a[2] }';

subtest 'a foreach-range body store threads the same loop-header memory-Phi' => sub {
    my $g = graph_of($FOR);
    is(scalar(of_op($g, 'Loop')), 1, 'exactly one Loop node');
    my $mem = loop_mem_phi($g);
    ok(defined $mem, 'a loop-header memory-Phi exists') or return;
    is($mem->region->operation, 'Loop', 'the memory-Phi region is the Loop');
    is(scalar($mem->inputs->@*), 2, 'the memory-Phi has two inputs (init, back-edge)');
    is($mem->inputs->[0]->operation, 'MemStart',
        'inputs[0] is the pre-loop memory (MemStart)');
    my $back = $mem->inputs->[1];
    is($back->operation, 'Assign', 'inputs[1] (back-edge) is the body element store');
    ok((grep { ref $_ && $_->operation eq 'Subscript' } $back->inputs->@*),
        'the back-edge store carries a Subscript lvalue');
    my ($ret) = of_op($g, 'Return');
    my $read = $ret->inputs->[-1];
    is($read->operation, 'Subscript', 'the return value is a Subscript (the read)') or return;
    is($read->inputs->[2], $mem, 'the post-loop read memory is the header memory-Phi');
};

done_testing();
