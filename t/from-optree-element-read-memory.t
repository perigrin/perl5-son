# ABOUTME: Tests element reads carry a memory input (memory-SSA phase 2a).
# ABOUTME: A pre-store read and a post-store read of one slot are DISTINCT nodes (different memory).

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# An element read is Subscript(container, index, memory). The memory input is the
# current memory value at the read's program point (MemStart at entry; a store's
# node after a store). So a read BEFORE a store and a read AFTER a store of the
# same slot have DIFFERENT memory inputs -> DISTINCT nodes -> the pre-store read
# observes the pre-store memory (correct), not the final memory.

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub subscripts ($g) {
    return grep { $_->operation eq 'Subscript' } $g->nodes->@*;
}

subtest 'an element read carries a memory input' => sub {
    my $g = graph_of('sub { my @a = (1,2,3); $a[0] }');
    my ($sub) = subscripts($g);
    ok(defined $sub, 'has a Subscript') or return;
    is(scalar $sub->inputs->@*, 3, 'Subscript has 3 inputs (container, index, memory)');
    # container=[0], index=[1] unchanged; memory=[2].
    is($sub->inputs->[0]->operation, 'ArrayLiteral', 'input[0] is the container');
    my $mem = $sub->inputs->[2];
    ok(defined $mem, 'input[2] is the memory value');
    is($mem->operation, 'MemStart', 'at entry the memory is MemStart');
};

subtest 'pre-store and post-store reads of one slot are DISTINCT nodes' => sub {
    # `my $x=$a[0]; $a[0]=99; my $y=$a[0]` -- $x reads MemStart memory, $y reads
    # the store's memory. Two distinct read Subscripts, not one hash-consed node.
    my $g = graph_of('sub { my @a = (5,6,7); my $x=$a[0]; $a[0]=99; my $y=$a[0]; $x+$y }');
    my @reads = grep {
        # a READ Subscript (not the store lvalue): its consumer is not an Assign
        my $s = $_;
        !grep { $_->operation eq 'Assign' && $_->inputs->[-2] == $s } $g->nodes->@*;
    } subscripts($g);
    # There should be two distinct read nodes with different memory inputs.
    my %mem_ids = map { ($_->inputs->[2] ? $_->inputs->[2]->id : 'none') => 1 } subscripts($g);
    ok(scalar(keys %mem_ids) >= 2,
        'reads at different program points have different memory inputs')
        or diag('memory input ids: ' . join(', ', keys %mem_ids));
};

subtest 'a store consumes memory and produces a new memory (the store node)' => sub {
    my $g = graph_of('sub { my @a = (1,2,3); $a[0] = 42; $a[0] }');
    my ($assign) = grep { $_->operation eq 'Assign' } $g->nodes->@*;
    ok(defined $assign, 'has the store Assign') or return;

    # STRING comparison. Node ids are strings ("Assign#3", "MemStart"), so `==`
    # numifies every one to 0 and matches ANY memory input -- this assertion
    # passed whatever the read was pinned to, including MemStart, which is
    # exactly the bug it exists to catch.
    my ($read) = grep {
        $_->operation eq 'Subscript' && $_->inputs->[2]
            && $_->inputs->[2]->id eq $assign->id
    } $g->nodes->@*;
    ok(defined $read, 'the post-store read takes the store Assign as its memory input');

    # BILATERAL: the store TARGET must NOT be pinned to the store. It is the
    # 2-input lvalue form (an address, no memory input at all), and a version
    # of this check that accepted any node would not tell the two apart.
    my @pinned_to_memstart = grep {
        $_->operation eq 'Subscript' && $_->inputs->[2]
            && $_->inputs->[2]->operation eq 'MemStart'
            && $_->inputs->[2]->id eq $assign->id
    } $g->nodes->@*;
    is(scalar @pinned_to_memstart, 0,
        'no read is reported as pinned to BOTH MemStart and the Assign');
};

done_testing();
